import Foundation
import AVFoundation

extension AudioController {
    func invalidateMaster() {
        let hadMaster = masterPlan != nil || masterCandidate != nil
        masterGeneration = UUID()
        resetMasterPreview()
        masterCandidate = nil; masterPlan = nil; masterSaved = nil
        if hadMaster { status = "Mastering inputs changed. Build a fresh plan." }
    }
    func resetMasterPreview() {
        masterPlayer.pause(); masterPlayer.replaceCurrentItem(with: nil)
        if let previewObserver { masterPlayer.removeTimeObserver(previewObserver); self.previewObserver = nil }
        previewReady = false; previewPlaying = false; previewPosition = 0; previewGeneration = UUID()
        for url in previewURLs { try? FileManager.default.removeItem(at: url) }
        previewURLs = []; previewVolumes = []
        previewMatchDescription = "Build an excerpt before listening."
    }
    func buildMasterPlan(tools: FFmpegTools) {
        guard !running, let source, let rate = Int(tracks.first(where: { $0.index == track })?.sample_rate ?? "") else { return }
        invalidateMaster()
        let generation = masterGeneration
        let selected = track, inputs = speechInputs, settings = masterSettings, layout = analysisLayout == "metadata" ? nil : analysisLayout
        perform("Measuring a fresh mastering plan…") {
            try settings.validate()
            let regions = try inputs.map { try $0.region(rate: rate) }.sorted { $0.startFrame < $1.startFrame }
            let fresh = try await MeasuredAnalysis.fresh(source: source,track: selected,regions: regions,tools: tools,declaredLayout: layout) { value in
                Task { @MainActor in
                    guard self.running, self.masterGeneration == generation else { return }
                    self.progress = value
                }
            }
            guard self.masterGeneration == generation else { throw CancellationError() }
            let plan = try await GainPlanner.build(fresh,settings: settings)
            guard self.masterGeneration == generation else { throw CancellationError() }
            self.masterPlan = plan
            self.status = "Fresh plan ready. Inspect the reference and limits before rendering."
        }
    }
    func renderMaster(to destination: URL, tools: FFmpegTools) {
        guard !running, let source, let plan = masterPlan else { return }
        resetMasterPreview(); masterCandidate = nil; masterSaved = nil
        let generation = masterGeneration
        let layout = analysisLayout == "metadata" ? nil : analysisLayout
        perform("Building a full verified candidate…") {
            let candidate = try await MasteringEngine.prepare(source: source,track: plan.analysis.report.track,
                regions: plan.analysis.report.speech.map(\.region),layout: layout,settings: plan.settings,destination: destination,tools: tools,expectedSource: plan.analysis.report.source) { phase,value in
                    Task { @MainActor in
                        guard self.running, self.masterGeneration == generation else { return }
                        self.status = phase; self.progress = value
                    }
                }
            guard self.masterGeneration == generation else { throw CancellationError() }
            self.masterCandidate = candidate
            self.previewStart = 0; self.previewLength = min(30,Double(plan.frames)/Double(plan.rate))
            self.status = "Candidate verified. Build an excerpt to compare, or save the lossless audio."
        }
    }
    func publishMaster() {
        guard !running, let candidate = masterCandidate, masterSaved == nil else { return }
        pauseMasterPreview()
        perform("Checking source and candidate before publication…") {
            try await candidate.publish(); self.masterSaved = candidate.destination
            self.status = "Audio saved. The optional processing report is saved separately."
        }
    }
    func saveMasterReport(to url: URL) {
        guard !running, let report = masterCandidate?.verification else { return }
        let audioSaved = masterSaved != nil
        perform("Saving processing report…") {
            do {
                let task = Task.detached { try report.save(to: url) }
                try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
                self.status = audioSaved ? "Audio and processing report saved." : "Processing report saved. Audio candidate has not been published."
            } catch {
                throw NativeExportError.invalid((audioSaved ? "Audio is already saved. Report was not saved; retry with a new name. " : "Report was not saved. ")+error.localizedDescription)
            }
        }
    }
    func buildMasterExcerpt(tools: FFmpegTools) {
        guard !running, let candidate = masterCandidate else { return }
        resetMasterPreview()
        let start = previewStart, length = previewLength, rate = candidate.plan.rate
        perform("Preparing aligned preview excerpts…") {
            let duration = Double(candidate.plan.frames)/Double(rate)
            guard start.isFinite, length.isFinite, start >= 0, (5...60).contains(length), start+length <= duration else {
                throw NativeExportError.invalid("Choose a 5 to 60 second excerpt wholly inside the source. Shorter sources can be saved, but cannot use this preview.")
            }
            let first = Int64((start*Double(rate)).rounded()), end = Int64(((start+length)*Double(rate)).rounded())
            var urls = [URL](), readings = [MeterSummary]()
            var retained = false
            defer { if !retained { for url in urls { try? FileManager.default.removeItem(at: url) } } }
            for source in [candidate.original,candidate.processed] {
                let url = candidate.folder.appendingPathComponent("excerpt-"+UUID().uuidString+".wav"); urls.append(url)
                try await MasteringEngine.runTool(tools,["-i",source.path,"-af","atrim=start_sample=\(first):end_sample=\(end),asetpts=PTS-STARTPTS","-c:a","pcm_f64le",url.path])
                let measured = try await MeasuredAnalysis.fresh(source: url,track: 0,regions: [],tools: tools,declaredLayout: candidate.plan.analysis.report.channelLabels.count == 1 ? "mono" : "stereo") { _ in }
                guard measured.report.programme.frames == end-first else { throw NativeExportError.invalid("Preview frame alignment failed.") }
                readings.append(measured.report.programme)
            }
            let safeDB = min(0,-1-(readings.compactMap { $0.truePeak.value }.max() ?? -1))
            self.previewSafeVolume = Float(pow(10,safeDB/20))
            if let a = readings[0].integrated.value, let b = readings[1].integrated.value,
               let ap = readings[0].truePeak.value, let bp = readings[1].truePeak.value {
                let match = min(a,b,a-1-ap,b-1-bp)
                self.previewVolumes = [Float(pow(10,(match-a)/20)),Float(pow(10,(match-b)/20))]
                self.previewMatchDescription = "Excerpt level match: \(String(format: "%.2f",match)) LUFS. Playback attenuation only; exported gain is unchanged."
            } else {
                self.previewVolumes = []; self.previewMatched = false
                self.previewMatchDescription = "Level matching unavailable: an excerpt is unmeasurable. Playback uses peak-safe attenuation."
            }
            self.previewURLs = urls; retained = true; self.previewReady = true
            self.selectMasterPreview(processed: self.previewProcessed)
            self.status = "Aligned excerpt ready. Playback is paused."
        }
    }
    func selectMasterPreview(processed: Bool) {
        guard previewReady, previewURLs.count == 2 else { return }
        let position = min(previewLength,max(0,masterPlayer.currentTime().seconds.isFinite ? masterPlayer.currentTime().seconds : previewPosition))
        masterPlayer.pause(); previewPlaying = false; previewProcessed = processed
        previewGeneration = UUID()
        masterPlayer.replaceCurrentItem(with: AVPlayerItem(url: previewURLs[processed ? 1 : 0]))
        updateMasterVolume()
        masterPlayer.seek(to: CMTime(seconds: position,preferredTimescale: 192000),toleranceBefore: .zero,toleranceAfter: .zero)
        previewPosition = position
        if previewObserver == nil {
            previewObserver = masterPlayer.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1,preferredTimescale: 600),queue: .main) { [weak self] time in
                Task { @MainActor in
                    guard let self, time.seconds.isFinite else { return }
                    self.previewPosition = min(self.previewLength,max(0,time.seconds))
                    if self.previewPosition >= self.previewLength-0.03 { self.masterPlayer.pause(); self.previewPlaying = false }
                }
            }
        }
    }
    func pauseMasterPreview() {
        previewGeneration = UUID(); masterPlayer.pause(); previewPlaying = false
    }
    func updateMasterVolume() {
        pauseMasterPreview()
        masterPlayer.volume = previewMatched && previewVolumes.count == 2 ? previewVolumes[previewProcessed ? 1 : 0] : previewSafeVolume
    }
    func seekMasterPreview(_ seconds: Double) {
        masterPlayer.pause(); previewPlaying = false; previewGeneration = UUID()
        previewPosition = min(previewLength,max(0,seconds))
        masterPlayer.seek(to: CMTime(seconds: previewPosition,preferredTimescale: 192000),toleranceBefore: .zero,toleranceAfter: .zero)
    }
    func toggleMasterPlayback() {
        guard previewReady, !running else { return }
        if previewPlaying { pauseMasterPreview(); return }
        let generation = previewGeneration
        previewPlaying = true
        let position = previewPosition >= previewLength-0.05 ? 0 : previewPosition
        Task { @MainActor in
            let ready = await masterPlayer.seek(to: CMTime(seconds: position,preferredTimescale: 192000),toleranceBefore: .zero,toleranceAfter: .zero)
            guard previewGeneration == generation, previewReady, !running else { return }
            guard ready else { previewPlaying = false; status = "Preview could not seek. Rebuild the excerpt to retry."; return }
            masterPlayer.play(); previewPlaying = true
        }
    }
}
