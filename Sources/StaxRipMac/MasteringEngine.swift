import Foundation

struct IndependentMasterCheck: Codable, Sendable {
    let integrated: Double, range: Double, truePeak: Double
}
struct MasterVerification: Codable, Sendable {
    let schemaVersion: Int
    let algorithm: String
    let settings: MasterSettings
    let source: SourceFingerprint
    let output: SourceFingerprint
    let before: MeterSummary
    let after: MeterSummary
    let speechBefore: MeterValue
    let speechAfter: MeterValue
    let regions: [SpeechRegion]
    let regionResults: [RegionMeasurement]
    let track: Int, sampleRate: Int, channelLabels: [String]
    let decoder: String, decodingPolicy: String
    let constantGain: Bool, baseGainDB: Double, minimumEnvelopeGainDB: Double, maximumEnvelopeGainDB: Double
    let momentaryMaximum: MeterValue, shortTermMaximum: MeterValue
    let independent: IndependentMasterCheck
    let attempts: Int
    func validate() throws {
        try settings.validate()
        func fingerprint(_ f: SourceFingerprint) -> Bool { f.byteCount > 0 && f.sha256.count == 64 && f.sha256.allSatisfy { "0123456789abcdef".contains($0) } }
        func value(_ v: MeterValue) -> Bool { v.value.map { $0.isFinite && v.unavailable == nil } ?? (v.unavailable?.isEmpty == false) }
        func meter(_ m: MeterSummary) -> Bool {
            m.frames > 0 && m.frames <= Int64(sampleRate)*14400 && m.trace.isEmpty && [m.integrated,m.range,m.samplePeak,m.truePeak].allSatisfy(value)
        }
        guard schemaVersion == 1, [44100,48000,88200,96000,192000].contains(sampleRate),
              channelLabels == ["FC"] || channelLabels == ["FL","FR"], (0...1024).contains(track),
              fingerprint(source), fingerprint(output), meter(before), meter(after), before.frames == after.frames,
              value(speechBefore), value(speechAfter), value(momentaryMaximum), value(shortTermMaximum),
              [baseGainDB,minimumEnvelopeGainDB,maximumEnvelopeGainDB].allSatisfy({ $0.isFinite && (-36...12).contains($0) }),
              minimumEnvelopeGainDB <= maximumEnvelopeGainDB, (1...3).contains(attempts),
              [independent.integrated,independent.range,independent.truePeak].allSatisfy({ $0.isFinite }),
              regions.count <= 16, regionResults.count == regions.count, !algorithm.isEmpty, algorithm.count <= 1024,
              decoder.count <= 1024, decodingPolicy.count <= 2048 else { throw NativeExportError.invalid("Invalid processing report; it was not saved.") }
        var previous: Int64 = 0
        for (region,result) in zip(regions,regionResults) {
            guard region.startFrame >= previous,region.endFrame > region.startFrame,region.endFrame <= after.frames,
                  result.region == region,meter(result.result),result.result.frames == region.endFrame-region.startFrame else {
                throw NativeExportError.invalid("Invalid processing report speech interval.")
            }
            previous = region.endFrame
        }
    }
    func save(to url: URL) throws {
        try Task.checkCancellation(); try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard schemaVersion == 1, data.count <= 32*1024*1024 else { throw NativeExportError.invalid("Processing report exceeds its size limit.") }
        let staged = url.deletingLastPathComponent().appendingPathComponent(".staxrip-receipt-"+UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: staged) }
        try data.write(to: staged, options: .withoutOverwriting)
        try Task.checkCancellation(); try ExportPublication.publish(staged: staged, destination: url)
    }
}
// Process-local ownership; never deserialized from a user report.
final class MasterCandidate: @unchecked Sendable {
    let folder: URL, source: URL, destination: URL, original: URL, processed: URL
    let plan: GainPlan
    let verification: MasterVerification
    init(folder: URL, source: URL, destination: URL, original: URL, processed: URL, plan: GainPlan, verification: MasterVerification) {
        self.folder = folder; self.source = source; self.destination = destination; self.original = original
        self.processed = processed; self.plan = plan; self.verification = verification
    }
    deinit { try? FileManager.default.removeItem(at: folder) }
    func publish() async throws {
        guard try await SourceFingerprint.read(source) == verification.source,
              try await SourceFingerprint.read(processed) == verification.output else {
            throw NativeExportError.invalid("Source or candidate changed. Rebuild the plan before saving.")
        }
        try Task.checkCancellation()
        try ExportPublication.publish(staged: processed, destination: destination)
    }
}
enum MasteringEngine {
    static func scratchEstimate(rate: Int, channels: Int, seconds: Double) throws -> Int64 {
        guard [44100,48000,88200,96000,192000].contains(rate), (1...2).contains(channels), seconds.isFinite, seconds > 0, seconds <= 14400 else {
            throw NativeExportError.invalid("Unsupported format or duration for original mastering.")
        }
        return Int64(ceil(Double(rate*channels)*seconds*29))+128*1024*1024
    }
    static func runTool(_ tools: FFmpegTools, _ arguments: [String], checkedReaders: Bool = false) async throws {
        let result = try await ToolRunner(checkedReaders: checkedReaders).run(executable: tools.ffmpeg, arguments: ["-hide_banner","-nostdin","-v","error","-xerror","-n"]+arguments)
        guard result.status == 0 else { throw NativeExportError.invalid("Audio conversion failed. No candidate was published.") }
    }
    static func encode(raw: URL, output: URL, rate: Int, channels: Int, dynamic: Bool, tools: FFmpegTools, checkedReaders: Bool = false) async throws {
        var args = ["-f","f64le","-ar",String(rate),"-ac",String(channels),"-i",raw.path]
        if dynamic {
            args += ["-af", "aresample=\(rate*4),alimiter=limit=0.8413951416:attack=5:release=50:level=false:latency=true,aresample=\(rate)"]
        }
        args += ["-map_metadata","-1","-map_chapters","-1","-ar",String(rate)]
        if output.pathExtension.lowercased() == "flac" { args += ["-c:a","flac","-sample_fmt","s32","-bits_per_raw_sample","24"] }
        else { args += ["-c:a","pcm_s24le","-rf64","auto"] }
        try await runTool(tools,args+[output.path],checkedReaders: checkedReaders)
    }
    static func independent(_ url: URL, tools: FFmpegTools, checkedReaders: Bool = false) async throws -> IndependentMasterCheck {
        func measure(padded: Bool) async throws -> IndependentMasterCheck {
            let filter = (padded ? "apad=pad_dur=1.5," : "")+"ebur128=peak=true"
            let result = try await ToolRunner(checkedReaders: checkedReaders).run(executable: tools.ffmpeg, arguments: ["-hide_banner","-nostdin","-nostats","-protocol_whitelist","file,pipe","-i",url.path,"-af",filter,"-f","null","-"])
            guard result.status == 0, let summary = String(decoding: result.stderr, as: UTF8.self).components(separatedBy: "Summary:").last else {
                throw NativeExportError.invalid("Independent output verification failed.")
            }
            func value(_ pattern: String) throws -> Double {
                let expression = try NSRegularExpression(pattern: pattern)
                guard let match = expression.firstMatch(in: summary, range: NSRange(summary.startIndex...,in: summary)),
                      let range = Range(match.range(at: 1),in: summary), let number = Double(summary[range]), number.isFinite else {
                    throw NativeExportError.invalid("Independent output measurement is unavailable.")
                }
                return number
            }
            return try IndependentMasterCheck(integrated: value("I:\\s+(-?[0-9.]+)"), range: value("LRA:\\s+(-?[0-9.]+)"), truePeak: value("Peak:\\s+(-?[0-9.]+)"))
        }
        // The Swift meter's 1.5-second tail is LRA-only. Padding the independent
        // integrated reading would add artificial partial-energy windows.
        let real = try await measure(padded: false)
        let tail = try await measure(padded: true)
        return IndependentMasterCheck(integrated: real.integrated,range: tail.range,truePeak: real.truePeak)
    }
    static func failures(_ after: FreshAnalysis, plan: GainPlan, independent: IndependentMasterCheck) -> [String] {
        let p = after.report.programme, settings = plan.settings
        var failures = [String]()
        if let ref = GainPlanner.reference(after,settings: settings) {
            if abs(ref-settings.target) > 0.5 { failures.append("Selected reference \(String(format: "%.2f",ref)) LUFS missed target \(String(format: "%.2f",settings.target)) LUFS by more than 0.5 LU.") }
        } else { failures.append("Selected reference became unmeasurable.") }
        if let range = p.range.value { if range > settings.maximumLRA+1 { failures.append(String(format: "Programme range %.2f LU exceeds the requested maximum plus 1 LU (%.2f LU).",range,settings.maximumLRA+1)) } }
        else { failures.append("Programme range is unavailable.") }
        if (p.truePeak.value ?? .infinity) > -1 || independent.truePeak > -1 { failures.append("True peak exceeds -1 dBTP.") }
        if abs((p.integrated.value ?? .infinity)-independent.integrated) > 0.15 || abs((p.truePeak.value ?? .infinity)-independent.truePeak) > 0.2 || abs((p.range.value ?? .infinity)-independent.range) > 1 {
            failures.append("Independent meters disagree beyond the registered tolerances: Swift I \(p.integrated.display), LRA \(p.range.display), TP \(p.truePeak.display); FFmpeg I \(independent.integrated), LRA \(independent.range), TP \(independent.truePeak).")
        }
        if settings.mode == .night {
            if (p.trace.compactMap(\.momentary).max() ?? .infinity) > settings.target+9.5 { failures.append("Momentary excursion exceeds the Night ceiling.") }
            if (p.trace.compactMap(\.shortTerm).max() ?? .infinity) > settings.target+6.5 { failures.append("Short-term excursion exceeds the Night ceiling.") }
        }
        if p.frames != plan.frames || after.report.sampleRate != plan.rate || after.report.channelLabels != plan.analysis.report.channelLabels {
            failures.append("Output frame count, rate or channel layout differs from the source.")
        }
        return failures
    }
    static func prepare(source: URL, track: Int, regions: [SpeechRegion], layout: String?, settings: MasterSettings,
                        destination: URL, tools: FFmpegTools, expectedSource: SourceFingerprint? = nil, status: @escaping @Sendable (String,Double) -> Void) async throws -> MasterCandidate {
        try settings.validate()
        guard ["wav","flac"].contains(destination.pathExtension.lowercased()), source.isFileURL, destination.isFileURL,
              source.resolvingSymlinksInPath() != destination.resolvingSymlinksInPath(), !FileManager.default.fileExists(atPath: destination.path) else {
            throw NativeExportError.invalid("Choose a new FLAC or WAV destination. Existing files are never replaced.")
        }
        let probe = try await MediaProbe.read(source,tools: tools,checkedReaders: true)
        guard let stream = probe.streams.first(where: { $0.index == track && $0.codec_type == "audio" }), let rate = Int(stream.sample_rate ?? ""), let channels = stream.channels else { throw NativeExportError.invalid("Select a supported audio stream.") }
        let required = try scratchEstimate(rate: rate, channels: channels, seconds: probe.seconds)
        let parent = destination.deletingLastPathComponent()
        let attrs = try FileManager.default.attributesOfFileSystem(forPath: parent.path)
        guard let free = attrs[.systemFreeSize] as? NSNumber, free.int64Value >= required else {
            throw NativeExportError.invalid("Not enough scratch space. Approximately \(ByteCountFormatter.string(fromByteCount: required,countStyle: .file)) is required.")
        }
        let folder = parent.appendingPathComponent(".staxrip-master-"+UUID().uuidString)
        try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: false,attributes: [.posixPermissions: 0o700])
        var retained = false
        defer { if !retained { try? FileManager.default.removeItem(at: folder) } }
        do {
        status("Fresh analysis and source verification",0)
        let before = try await MeasuredAnalysis.fresh(source: source,track: track,regions: regions,tools: tools,declaredLayout: layout,checkedReaders: true) { status("Measuring source",$0*0.2) }
        if let expectedSource, before.report.source != expectedSource { throw NativeExportError.invalid("Source changed since the inspected plan. Build a fresh plan.") }
        // Build now to refuse unsupported targets before copying full PCM.
        let initialPlan = try await GainPlanner.build(before,settings: settings)
        let raw = folder.appendingPathComponent("source.f64"), rendered = folder.appendingPathComponent("render.f64")
        let original = folder.appendingPathComponent("original.wav"), output = folder.appendingPathComponent("candidate."+destination.pathExtension.lowercased())
        status("Decoding selected track for linked rendering",0.2)
        try await runTool(tools,["-protocol_whitelist","file,pipe","-i",source.path,"-map","0:\(track)","-vn","-sn","-dn","-c:a","pcm_f64le","-f","f64le",raw.path],checkedReaders: true)
        guard try await SourceFingerprint.read(source) == before.report.source else { throw NativeExportError.invalid("Source changed after analysis. Rebuild the plan.") }
        try await runTool(tools,["-f","f64le","-ar",String(rate),"-ac",String(channels),"-i",raw.path,"-map_metadata","-1","-c:a","pcm_f64le","-rf64","auto",original.path],checkedReaders: true)
        var correction = 0.0, problems = [String]()
        for attempt in 0..<3 {
            try Task.checkCancellation()
            let plan = try await (attempt == 0 ? initialPlan : GainPlanner.build(before,settings: settings,attempt: attempt,correction: correction))
            status("Rendering candidate \(attempt+1) of at most 3",0.3+Double(attempt)*0.2)
            if attempt > 0 { try FileManager.default.removeItem(at: rendered); try FileManager.default.removeItem(at: output) }
            #if DEBUG
            let wroteChunk = LinkedRenderer.wroteChunk, closeReport = LinkedRenderer.closeReport
            #endif
            let renderTask = Task.detached {
                #if DEBUG
                try LinkedRenderer.$wroteChunk.withValue(wroteChunk) {
                    try LinkedRenderer.$closeReport.withValue(closeReport) {
                        try LinkedRenderer.render(raw: raw,to: rendered,plan: plan)
                    }
                }
                #else
                try LinkedRenderer.render(raw: raw,to: rendered,plan: plan)
                #endif
            }
            try await withTaskCancellationHandler { try await renderTask.value } onCancel: { renderTask.cancel() }
            try await encode(raw: rendered,output: output,rate: rate,channels: channels,dynamic: plan.dynamic,tools: tools,checkedReaders: true)
            status("Measuring encoded candidate \(attempt+1)",0.4+Double(attempt)*0.2)
            let after = try await MeasuredAnalysis.fresh(source: output,track: 0,regions: regions,tools: tools,declaredLayout: channels == 1 ? "mono" : "stereo",checkedReaders: true) { _ in }
            let format = try await MediaProbe.read(output,tools: tools,checkedReaders: true)
            guard let encoded = format.streams.first, encoded.codec_name == (destination.pathExtension.lowercased() == "flac" ? "flac" : "pcm_s24le"), encoded.bits_per_raw_sample == "24" else {
                throw NativeExportError.invalid("Encoded candidate is not the requested 24-bit lossless format.")
            }
            let crosscheck = try await independent(output,tools: tools,checkedReaders: true)
            problems = failures(after,plan: plan,independent: crosscheck)
            if !problems.isEmpty { status("Candidate \(attempt+1) rejected: "+problems.joined(separator: " "),0.5+Double(attempt)*0.2) }
            if problems.isEmpty {
                guard try await SourceFingerprint.read(source) == before.report.source else { throw NativeExportError.invalid("Source changed during rendering. Rebuild the plan.") }
                func compact(_ m: MeterSummary) -> MeterSummary { MeterSummary(frames: m.frames, integrated: m.integrated,range: m.range,samplePeak: m.samplePeak,truePeak: m.truePeak,trace: []) }
                let receipt = MasterVerification(schemaVersion: 1,algorithm: GainPlan.version,settings: settings,source: before.report.source,output: after.report.source,
                    before: compact(before.report.programme),after: compact(after.report.programme),speechBefore: before.speechReference,speechAfter: after.speechReference,
                    regions: regions,regionResults: after.report.speech,track: track,sampleRate: rate,channelLabels: before.report.channelLabels,
                    decoder: before.report.decoder,decodingPolicy: before.report.decodingPolicy,constantGain: !plan.dynamic,baseGainDB: plan.baseDB,minimumEnvelopeGainDB: plan.minimumDB,maximumEnvelopeGainDB: plan.maximumDB,
                    momentaryMaximum: .measured(after.report.programme.trace.compactMap(\.momentary).max()),shortTermMaximum: .measured(after.report.programme.trace.compactMap(\.shortTerm).max()),independent: crosscheck,attempts: attempt+1)
                try FileManager.default.removeItem(at: raw); try FileManager.default.removeItem(at: rendered)
                try Task.checkCancellation()
                let candidate = MasterCandidate(folder: folder,source: source,destination: destination,original: original,processed: output,plan: plan,verification: receipt)
                retained = true; status("Verified candidate ready. Audition before saving.",1)
                return candidate
            }
            if let measured = GainPlanner.reference(after,settings: settings) { correction += settings.target-measured }
        }
        throw NativeExportError.invalid("The experimental planner did not meet these settings after three bounded attempts. No output was published. "+problems.joined(separator: " ")+" Try other settings or keep the original. This refusal does not prove that the requested result is mathematically impossible.")
        } catch {
            if error is CompanionUnsettledOwnership { retained = true }
            throw error
        }
    }
}
