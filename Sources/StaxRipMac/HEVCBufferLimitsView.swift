import SwiftUI

struct HEVCBufferLimitsView: View {
    @Binding var configuration: EncodeConfiguration
    let source: URL?
    @State private var video: MediaProbe.Stream?
    @State private var inspectedURL: URL?
    @State private var readIssue: String?
    private var eligible: Bool { configuration.codec == "HEVC" && configuration.rate.backend == "Software" }
    private var inspectedSource: URL? { eligible && configuration.hevcBufferLimits != nil ? source : nil }
    private var recommendation: HEVCBufferRecommendation? {
        guard inspectedURL == inspectedSource, let video else { return nil }
        return try? HEVCBufferPlanner.resolve(configuration, video: video)
    }
    private var issue: String? {
        guard configuration.hevcBufferLimits != nil else { return nil }
        guard eligible else { return "Stored limits require software HEVC. Turn them off to use this codec or engine." }
        guard inspectedURL == inspectedSource, let video else { return readIssue ?? "Open a source to calculate limits. Encoding recalculates against its fresh probe." }
        do { _ = try HEVCBufferPlanner.resolve(configuration, video: video); return nil }
        catch { return error.localizedDescription }
    }
    private func update(_ body: (inout HEVCBufferLimits) -> Void) {
        var next = configuration.hevcBufferLimits ?? HEVCBufferLimits()
        body(&next); configuration.hevcBufferLimits = next
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if eligible || configuration.hevcBufferLimits != nil {
                Toggle("Limit HEVC peak bitrate (VBV)", isOn: Binding(get: { configuration.hevcBufferLimits != nil }, set: {
                    configuration.hevcBufferLimits = $0 ? HEVCBufferLimits() : nil
                }))
                .accessibilityIdentifier("hevc-vbv-enabled")
                .accessibilityLabel("Limit H E V C peak bitrate using a video buffering verifier")
                .accessibilityHint("Enables peak bitrate, buffer capacity, encoder level and decoder timing signaling. Existing recipes remain unrestricted until enabled.")
                if let limits = configuration.hevcBufferLimits {
                    settingPicker("Decoder tier", selection: Binding(get: { limits.tier }, set: { tier in update { $0.tier = tier } }), values: ["Main", "High"])
                        .accessibilityIdentifier("hevc-vbv-tier")
                    Text("Main favors decoder compatibility. High permits more bitrate headroom at supported levels. Neither option certifies a particular player.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Toggle("Use suggested limits", isOn: Binding(get: { limits.mode == "Suggested" }, set: { useSuggested in
                        let current = recommendation
                        update {
                            if !useSuggested, $0.mode == "Suggested", let current {
                                $0.maxrate = current.maxrate; $0.bufsize = current.bufsize
                            }
                            $0.mode = useSuggested ? "Suggested" : "Custom"
                        }
                    })).accessibilityIdentifier("hevc-vbv-suggested")
                        .accessibilityHint("Turn off to edit the prefilled suggestion. Manual values remain fixed when you change the source or picture settings.")
                    if limits.mode == "Suggested", recommendation == nil {
                        Text("Suggested peak and buffer: unavailable until the source is inspected.").font(.caption)
                    } else { HStack {
                        VStack(alignment: .leading) {
                            Text("Peak bitrate (kb/s)")
                            TextField("Peak bitrate", value: Binding(get: { limits.mode == "Suggested" ? recommendation?.maxrate ?? limits.maxrate : limits.maxrate }, set: { value in update { $0.maxrate = value } }), format: .number)
                                .accessibilityIdentifier("hevc-vbv-peak")
                                .accessibilityLabel("H E V C peak bitrate, in kilobits per second")
                        }
                        VStack(alignment: .leading) {
                            Text("Buffer capacity (kbit)")
                            TextField("Buffer capacity", value: Binding(get: { limits.mode == "Suggested" ? recommendation?.bufsize ?? limits.bufsize : limits.bufsize }, set: { value in update { $0.bufsize = value } }), format: .number)
                                .accessibilityIdentifier("hevc-vbv-buffer")
                                .accessibilityLabel("H E V C buffer capacity, in kilobits")
                                .accessibilityHint("Capacity in bits, distinct from peak bits per second.")
                        }
                    }.textFieldStyle(.roundedBorder).disabled(limits.mode == "Suggested" || !eligible) }
                    if let recommendation {
                        Text(recommendation.summary).font(.caption).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("hevc-vbv-summary")
                    }
                    if let issue { Text(issue).font(.caption).foregroundStyle(Color.warning).fixedSize(horizontal: false, vertical: true) }
                    Text("Suggestions use the output raster, declared cadence and HEVC level limits; they are not a content-quality estimate. Tight limits can reduce quality in complex scenes. This does not enable Dolby Vision conversion or verify complete HRD conformance.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }.task(id: inspectedSource) {
            video = nil; readIssue = nil; inspectedURL = nil
            guard let url = inspectedSource else { return }
            guard let tools = FFmpegTools.discover() else { readIssue = "Install FFmpeg to calculate source-based limits."; return }
            do {
                let result = try await MediaProbe.read(url, tools: tools)
                try Task.checkCancellation()
                inspectedURL = url
                video = result.video
                if video == nil { readIssue = "Source has no inspected video stream." }
            } catch {
                if !Task.isCancelled { readIssue = error.localizedDescription }
            }
        }
    }
}
