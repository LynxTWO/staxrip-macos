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
                    .accessibilityHint("Opens a saved loudness report. Its source must be verified separately.")
                Button("Measure and build report") { if let tools { audio.measuredAnalysis(tools: tools) } }
                    .primaryAction().disabled(busy || audio.source == nil || tools == nil)
                    .accessibilityHint("Measures the selected audio track and your speech intervals. Does not apply gain or export audio.")
            }
            if audio.running {
                HStack {
                    ProgressView(value: audio.progress).accessibilityLabel("Audio operation progress")
                        .accessibilityValue(Text("\(Int(audio.progress * 100)) percent"))
                        .accessibilityHint("Progress is available here while audio is decoded. Source verification may continue after decoding.")
                    Button("Cancel audio operation", role: .cancel) { audio.cancel() }
                }
            }
            Text(audio.status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Picker("Source channel layout", selection: $audio.analysisLayout) {
                Text("Use stream metadata").tag("metadata")
                Text("I confirm mono (FC)").tag("mono").accessibilityLabel("I confirm mono, front centre")
                Text("I confirm stereo (FL / FR)").tag("stereo").accessibilityLabel("I confirm stereo, front left and front right")
            }.accessibilityHint("Use stream metadata unless the layout is unknown and you know whether the source is mono or stereo.")
            .disabled(busy).onChange(of: audio.analysisLayout) { _, _ in audio.analysisReport = nil; audio.analysisSourceVerified = false }
            DisclosureGroup("Optional speech intervals · selected by you") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Mark clean speech in seconds. Each interval is measured separately with reset filters. Music and effects in the selection are still included; this is not speech detection.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach($audio.speechInputs) { $interval in
                        let number = (audio.speechInputs.firstIndex(where: { $0.id == interval.id }) ?? 0) + 1
                        HStack {
                            TextField("Start seconds", value: $interval.start, format: .number).accessibilityLabel("Speech interval \(number), start time in seconds")
                                .accessibilityHint("Must be earlier than the end time and within the source.")
                            Text("to")
                            TextField("End seconds", value: $interval.end, format: .number).accessibilityLabel("Speech interval \(number), end time in seconds")
                                .accessibilityHint("Must be later than the start time and within the source.")
                            Button("Remove interval") { audio.speechInputs.removeAll { $0.id == interval.id } }
                                .accessibilityLabel(Text("Remove speech interval \(number), from \(interval.start, specifier: "%.2f") to \(interval.end, specifier: "%.2f") seconds"))
                                .accessibilityHint("Removes this interval from the analysis selection.")
                        }.textFieldStyle(.roundedBorder)
                    }
                    Button("Add speech interval") { audio.speechInputs.append(SpeechIntervalDraft()) }.disabled(audio.speechInputs.count >= 16)
                }.padding(.top, 8).disabled(busy)
                .onChange(of: audio.speechInputs) { _, _ in audio.analysisReport = nil; audio.analysisSourceVerified = false }
            }
            if let report = audio.analysisReport {
                HStack(spacing: 24) {
                    meter("PROGRAMME", report.programme.integrated, "LUFS", spokenName: "Measured programme loudness", spokenUnit: "LUFS", hint: "Integrated measurement of the selected audio track.")
                    meter("LOUDNESS RANGE", report.programme.range, "LU", spokenName: "Measured loudness range", spokenUnit: "loudness units", hint: "Describes loudness variation, not individual peaks.")
                    meter("TRUE-PEAK ESTIMATE", report.programme.truePeak, "dBTP", spokenName: "Estimated true peak", spokenUnit: "decibels true peak", hint: "Estimates peaks between audio samples.")
                    meter("SAMPLE PEAK", report.programme.samplePeak, "dBFS", spokenName: "Measured sample peak", spokenUnit: "decibels relative to full scale", hint: "Measures the stored audio samples.")
                }
                let points = plotPoints(report.programme.trace)
                Chart {
                    ForEach(points, id: \.frame) { point in
                        if let m = point.momentary { LineMark(x: .value("Seconds", Double(point.frame)/Double(report.sampleRate)), y: .value("LUFS", m), series: .value("Segment", "M-\(point.mSegment)")).foregroundStyle(by: .value("Window", "Momentary")) }
                        if let s = point.shortTerm { LineMark(x: .value("Seconds", Double(point.frame)/Double(report.sampleRate)), y: .value("LUFS", s), series: .value("Segment", "S-\(point.sSegment)")).foregroundStyle(by: .value("Window", "Short term")) }
                    }
                }
                .chartForegroundStyleScale(["Momentary": Color(red: 0.24, green: 0.73, blue: 0.64).opacity(0.6), "Short term": Color.orange])
                .chartXAxisLabel("Source time (seconds)").chartYAxisLabel("LUFS").frame(height: 180)
                .accessibilityLabel("Loudness over time")
                .accessibilityHint("Momentary loudness uses 400-millisecond windows. Short-term loudness uses three-second windows. Explore the chart data for measured values; gaps indicate unavailable measurements.")
                Text("Plot sampled to at most 1,000 points; the saved report retains the 20 ms measurements. Empty portions mean insufficient duration or no finite energy.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Label(audio.analysisSourceVerified ? "Fingerprint matched" : "Saved report · source unverified", systemImage: audio.analysisSourceVerified ? "checkmark.seal" : "questionmark.circle")
                        .foregroundStyle(audio.analysisSourceVerified ? Color.accent : Color.warning)
                    Text("\(Double(report.programme.frames)/Double(report.sampleRate), specifier: "%.2f") s · \(report.sampleRate) Hz · \(report.channelLabels.joined(separator: " / ")) · track #\(report.track)").font(.caption)
                    Spacer()
                    Button("Verify source") { audio.verifyAnalysisSource() }.disabled(busy || audio.source == nil)
                        .accessibilityLabel("Verify report source")
                        .accessibilityHint("Checks whether the selected file and audio track match this saved report. Does not validate externally edited measurement values.")
                    Button("Save report…") { saveReport() }.disabled(busy)
                }
                DisclosureGroup("Channel, speech and measurement details") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(report.channels.indices, id: \.self) { i in
                            VStack(alignment: .leading) { Text("\(report.channelLabels[i]) as mono: \(report.channels[i].integrated.display) LUFS · \(report.channels[i].truePeak.display) dBTP") }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("\(AccessibilityLanguage.channel(report.channelLabels[i])) channel, measured separately as mono")
                                .accessibilityValue("Loudness: \(AccessibilityLanguage.measurement(report.channels[i].integrated, unit: "LUFS")). True peak: \(AccessibilityLanguage.measurement(report.channels[i].truePeak, unit: "decibels true peak"))")
                        }
                        ForEach(report.speech.indices, id: \.self) { i in
                            let passage = report.speech[i]
                            VStack(alignment: .leading) { Text("User-selected interval \(i+1): \(Double(passage.region.startFrame)/Double(report.sampleRate), specifier: "%.2f")–\(Double(passage.region.endFrame)/Double(report.sampleRate), specifier: "%.2f") s · \(passage.result.integrated.display) LUFS · \(passage.result.range.display) LU LRA") }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(Text("User-selected speech interval \(i+1), from \(Double(passage.region.startFrame)/Double(report.sampleRate), specifier: "%.2f") to \(Double(passage.region.endFrame)/Double(report.sampleRate), specifier: "%.2f") seconds"))
                                .accessibilityValue("Loudness: \(AccessibilityLanguage.measurement(passage.result.integrated, unit: "LUFS")). Loudness range: \(AccessibilityLanguage.measurement(passage.result.range, unit: "loudness units"))")
                        }
                        Text(report.algorithm)
                        Text(report.decoder)
                        Text(report.decodingPolicy)
                        ForEach(report.warnings, id: \.self) { Text($0) }
                        DisclosureGroup("Source fingerprint · SHA-256") {
                            Text(report.source.sha256).textSelection(.enabled)
                        }.accessibilityHint("Expand to read or copy the complete source fingerprint.")
                    }.font(.caption).foregroundStyle(.secondary).padding(.top, 8).frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("This report measures the selected source track without applying your output recipe. It records the decoder, algorithm and source fingerprint. Silent or too-short material stays explicitly unavailable.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }.padding(20).background(Color.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }
    private func meter(_ title: String, _ value: MeterValue, _ unit: String, spokenName: String, spokenUnit: String, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(value.display).font(.system(.title2, design: .rounded).weight(.semibold)).monospacedDigit()
            Text(value.value == nil ? (value.unavailable ?? "Unavailable") : unit).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenName)
            .accessibilityValue(AccessibilityLanguage.measurement(value, unit: spokenUnit))
            .accessibilityHint(hint)
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
