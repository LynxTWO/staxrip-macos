import SwiftUI
import Charts
import UniformTypeIdentifiers

struct SpeechIntervalDraft: Identifiable, Equatable {
    let id = UUID()
    var start = 0.0
    var end = 30.0
    func region(rate: Int) throws -> SpeechRegion {
        guard start.isFinite, end.isFinite, start >= 0, end > start, end <= 14400,
              [44100,48000,88200,96000,192000].contains(rate) else {
            throw NativeExportError.invalid("Enter finite speech start/end times within the four-hour analysis limit.")
        }
        return SpeechRegion(startFrame: Int64((start*Double(rate)).rounded()), endFrame: Int64((end*Double(rate)).rounded()))
    }
}

struct MeasuredAnalysisView: View {
    @EnvironmentObject var audio: AudioController
    let busy: Bool
    let tools: FFmpegTools?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("MEASURE BEFORE YOU MOVE").font(.caption.weight(.semibold)).tracking(2).foregroundStyle(Color.accent)
                    Text("A clearer picture of loudness").font(.title2.weight(.semibold))
                    Text("SignalForge-derived research meter · mono / stereo · up to four hours").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Open report…") { openReport() }.disabled(busy)
                Button("Measure and build report") { if let tools { audio.measuredAnalysis(tools: tools) } }
                    .buttonStyle(.borderedProminent).disabled(busy || audio.source == nil || tools == nil)
            }
            if audio.running {
                HStack {
                    ProgressView(value: audio.progress).accessibilityLabel("Audio operation progress")
                    Button("Cancel audio operation", role: .cancel) { audio.cancel() }
                }
            }
            Text(audio.status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Picker("Source channel layout", selection: $audio.analysisLayout) {
                Text("Use stream metadata").tag("metadata")
                Text("I confirm mono (FC)").tag("mono")
                Text("I confirm stereo (FL / FR)").tag("stereo")
            }.disabled(busy).onChange(of: audio.analysisLayout) { _, _ in audio.analysisReport = nil; audio.analysisSourceVerified = false }
            DisclosureGroup("Optional speech intervals · selected by you") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Mark clean speech in seconds. Each interval is measured separately with reset filters. Music and effects in the selection are still included; this is not speech detection.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach($audio.speechInputs) { $interval in
                        HStack {
                            TextField("Start seconds", value: $interval.start, format: .number).accessibilityLabel("Speech interval start seconds")
                            Text("to")
                            TextField("End seconds", value: $interval.end, format: .number).accessibilityLabel("Speech interval end seconds")
                            Button("Remove interval") { audio.speechInputs.removeAll { $0.id == interval.id } }
                        }.textFieldStyle(.roundedBorder)
                    }
                    Button("Add speech interval") { audio.speechInputs.append(SpeechIntervalDraft()) }.disabled(audio.speechInputs.count >= 16)
                }.padding(.top, 8).disabled(busy)
                .onChange(of: audio.speechInputs) { _, _ in audio.analysisReport = nil; audio.analysisSourceVerified = false }
            }
            if let report = audio.analysisReport {
                HStack(spacing: 24) {
                    meter("PROGRAMME", report.programme.integrated, "LUFS")
                    meter("LOUDNESS RANGE", report.programme.range, "LU")
                    meter("TRUE-PEAK ESTIMATE", report.programme.truePeak, "dBTP")
                    meter("SAMPLE PEAK", report.programme.samplePeak, "dBFS")
                }
                let points = plotPoints(report.programme.trace)
                Chart {
                    ForEach(points, id: \.frame) { point in
                        if let m = point.momentary { LineMark(x: .value("Seconds", Double(point.frame)/Double(report.sampleRate)), y: .value("LUFS", m), series: .value("Segment", "M-\(point.mSegment)")).foregroundStyle(by: .value("Window", "Momentary")) }
                        if let s = point.shortTerm { LineMark(x: .value("Seconds", Double(point.frame)/Double(report.sampleRate)), y: .value("LUFS", s), series: .value("Segment", "S-\(point.sSegment)")).foregroundStyle(by: .value("Window", "Short term")) }
                    }
                }
                .chartForegroundStyleScale(["Momentary": Color.accent.opacity(0.6), "Short term": Color.orange])
                .chartXAxisLabel("Source time (seconds)").chartYAxisLabel("LUFS").frame(height: 180)
                .accessibilityLabel("Loudness history, momentary 400 milliseconds and short term 3 seconds")
                Text("Plot sampled to at most 1,000 points; the saved report retains the 20 ms measurements. Empty portions mean insufficient duration or no finite energy.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Label(audio.analysisSourceVerified ? "Fingerprint matched" : "Saved report · source unverified", systemImage: audio.analysisSourceVerified ? "checkmark.seal" : "questionmark.circle")
                        .foregroundStyle(audio.analysisSourceVerified ? Color.accent : Color.orange)
                    Text("\(Double(report.programme.frames)/Double(report.sampleRate), specifier: "%.2f") s · \(report.sampleRate) Hz · \(report.channelLabels.joined(separator: " / ")) · track #\(report.track)").font(.caption)
                    Spacer()
                    Button("Verify source") { audio.verifyAnalysisSource() }.disabled(busy || audio.source == nil)
                    Button("Save report…") { saveReport() }.disabled(busy)
                }
                DisclosureGroup("Channel, speech and measurement details") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(report.channels.indices, id: \.self) { i in
                            Text("\(report.channelLabels[i]) as mono: \(report.channels[i].integrated.display) LUFS · \(report.channels[i].truePeak.display) dBTP")
                        }
                        ForEach(report.speech.indices, id: \.self) { i in
                            let passage = report.speech[i]
                            Text("User-selected interval \(i+1): \(Double(passage.region.startFrame)/Double(report.sampleRate), specifier: "%.2f")–\(Double(passage.region.endFrame)/Double(report.sampleRate), specifier: "%.2f") s · \(passage.result.integrated.display) LUFS · \(passage.result.range.display) LU LRA")
                        }
                        Text(report.algorithm)
                        Text(report.decoder)
                        Text(report.decodingPolicy)
                        ForEach(report.warnings, id: \.self) { Text($0) }
                        Text("SHA-256: \(report.source.sha256)").textSelection(.enabled)
                    }.font(.caption).foregroundStyle(.secondary).padding(.top, 8).frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("This report measures the selected source track without applying your output recipe. It records the decoder, algorithm and source fingerprint. Silent or too-short material stays explicitly unavailable.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }.padding(20).background(Color.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }
    private func meter(_ title: String, _ value: MeterValue, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(value.display).font(.system(.title2, design: .rounded).weight(.semibold)).monospacedDigit()
            Text(value.value == nil ? (value.unavailable ?? "Unavailable") : unit).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }
    private struct PlotPoint {
        let frame: Int64
        let momentary: Double?, shortTerm: Double?
        let mSegment: Int, sSegment: Int
    }
    private func plotPoints(_ points: [LoudnessPoint]) -> [PlotPoint] {
        let step = max(1, (points.count+999)/1000)
        var result: [PlotPoint] = [], mSegment = 0, sSegment = 0
        var hadM = false, hadS = false
        for (i,p) in points.enumerated() {
            if p.momentary != nil && !hadM { mSegment += 1 }
            if p.shortTerm != nil && !hadS { sSegment += 1 }
            hadM = p.momentary != nil; hadS = p.shortTerm != nil
            if i % step == 0 { result.append(PlotPoint(frame: p.frame, momentary: p.momentary, shortTerm: p.shortTerm, mSegment: mSegment, sSegment: sSegment)) }
        }
        return result
    }
    private func openReport() {
        let panel = NSOpenPanel(); panel.title = "Open measured analysis report"; panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { audio.openAnalysis(url) }
    }
    private func saveReport() {
        let panel = NSSavePanel(); panel.title = "Save measured analysis report"; panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Loudness Analysis.json"
        if panel.runModal() == .OK, let url = panel.url { audio.saveAnalysis(to: url) }
    }
}
