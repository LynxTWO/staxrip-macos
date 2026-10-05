import Foundation
import SwiftUI

@MainActor final class DolbyInspectionController: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var stage = ""
    @Published private(set) var report: DolbySourceReport?
    private(set) var reportSource: URL?
    func report(for source: URL) -> DolbySourceReport? {
        guard !running, reportSource == source.standardizedFileURL else { return nil }
        return report
    }
    @Published private(set) var error: String?
    typealias Reader = @Sendable (URL, MediaProbe, @escaping @Sendable (String) -> Void) async throws -> DolbySourceReport
    private let reader: Reader
    private var stopping = false
    init(reader: @escaping Reader = { source, probe, progress in
        guard let helper = DolbyInspection.bundledHelper(), let tools = FFmpegTools.discover() else {
            throw DolbyInspection.failure("The inspection component or FFprobe is unavailable in this app build.")
        }
        return try await DolbyInspection.read(source: source, probe: probe, helper: helper, tools: tools, progress: progress)
    }) { self.reader = reader }
    private var task: Task<Void, Never>?
    private var generation = UUID()
    @discardableResult func start(source: URL, probe: MediaProbe) -> Task<Void, Never> {
        let previous = task; previous?.cancel()
        let id = UUID(); generation = id
        running = true; stopping = false; report = nil; reportSource = nil; error = nil; stage = "Preparing full-source inspection…"
        task = Task { [weak self] in
            await previous?.value
            guard let self, self.generation == id else { return }
            do {
                try Task.checkCancellation()
                let value = try await self.reader(source, probe) { [weak self] message in
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == id, self.running, !self.stopping else { return }
                        self.stage = message
                    }
                }
                try Task.checkCancellation()
                if self.generation == id { self.report = value; self.reportSource = source.standardizedFileURL; self.stage = "Metadata and encoded packet checks completed." }
            } catch is CancellationError {
                if self.generation == id { self.stage = "Inspection cancelled." }
            } catch {
                if self.generation == id { self.error = error.localizedDescription; self.stage = "Inspection incomplete." }
            }
            if self.generation == id { self.running = false; self.task = nil }
        }
        return task!
    }
    // Resetting a sheet never abandons its child. The app retains this controller
    // while the replaced task and all its resources settle.
    @discardableResult func reset() -> Task<Void, Never> {
        let previous = task; previous?.cancel()
        let id = UUID(); generation = id
        report = nil; reportSource = nil; error = nil; stopping = previous != nil; running = stopping
        stage = stopping ? "Stopping the previous inspection…" : ""
        let replacement = Task { [weak self] in
            await previous?.value
            guard let self, self.generation == id else { return }
            self.running = false; self.stopping = false; self.stage = ""; self.task = nil
        }
        task = replacement
        return replacement
    }
    func cancel() {
        guard running else { return }
        stopping = true; stage = "Stopping inspection…"; task?.cancel()
    }
}

struct DolbyInspectionView: View {
    @ObservedObject var controller: DolbyInspectionController
    let source: URL
    let probe: MediaProbe
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Dolby Vision signal inventory", systemImage: "square.stack.3d.up")
                .font(.headline).accessibilityAddTraits(.isHeader)
            Text("Read the complete metadata sequence and independently check the encoded video packets. Large movies can take several minutes.")
                .font(.caption).foregroundStyle(.secondary)
            if !DolbyInspection.eligible(probe) {
                Text("Full-sequence inspection currently supports Matroska with one HEVC video track. Other containers and AV1 need separate readers.")
                    .foregroundStyle(Color.warning).font(.caption)
            }
            HStack {
                Button(controller.report == nil ? "Inspect full Dolby metadata" : "Inspect again") { controller.start(source: source, probe: probe) }
                    .disabled(controller.running || !DolbyInspection.eligible(probe))
                    .accessibilityLabel("Inspect the complete Dolby Vision metadata sequence")
                    .accessibilityIdentifier("dolby.inspection.start")
                    .help("Reads the entire source, validates reference picture metadata and checks every encoded video packet independently.")
                if controller.running { ProgressView().controlSize(.small) }
            }
            if !controller.stage.isEmpty { Text(controller.stage).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("dolby.inspection.stage") }
            if let error = controller.error { Text(error).foregroundStyle(Color.warning).textSelection(.enabled) }
            if let report = controller.report { result(report) }
            Text("Crop and resize change active-area coordinates. Resampling can change brightness statistics. Dynamic HDR edits still need exact geometry, rounding, picture measurements and output verification.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
    private func result(_ report: DolbySourceReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Metadata validated · packet sequence verified", systemImage: "checkmark.shield")
                .font(.subheadline.weight(.semibold)).accessibilityIdentifier("dolby.inspection.result")
            HStack(alignment: .top, spacing: 20) {
                metric("VIDEO PACKETS", report.packets)
                metric("VALIDATED RPUs", report.records, spoken: "Validated reference picture metadata units")
                metric("SCENE REFRESHES", report.sceneRefreshes, spoken: "Declared scene refreshes")
            }
            ForEach(report.mappings.keys.sorted(), id: \.self) { key in
                Text(mapping(key) + " · " + report.mappings[key, default: 0].formatted() + " records")
                    .font(.caption).textSelection(.enabled)
                    .accessibilityLabel(mapping(key).replacingOccurrences(of: "RPU", with: "Reference picture metadata") + ", " + report.mappings[key, default: 0].formatted() + " records")
            }
            if report.mappings["7:FEL"] != nil {
                Text("Full enhancement metadata is present. A fidelity-preserving re-encode needs qualified enhancement reconstruction. Original preservation retains the matching encoded base and enhancement signal.")
                    .font(.caption).foregroundStyle(Color.warning)
            }
            if report.records == 0 || report.packetsWithoutRPU > 0 || report.packetsWithMultipleRPUs > 0 {
                Text("Packets without an RPU: \(report.packetsWithoutRPU.formatted()). Packets with multiple RPUs: \(report.packetsWithMultipleRPUs.formatted()). Decoded-frame association requires further checks.")
                    .font(.caption).foregroundStyle(Color.warning)
            }
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    let h = report.header
                    Text("Reported pixel raster: \(h.declaredPixelWidth) × \(h.declaredPixelHeight)")
                    Text("Container crop, left / right / top / bottom: " + h.declaredCropLeftRightTopBottom.map(String.init).joined(separator: " / "))
                    Text("Declared display dimensions: " + h.declaredDisplayWidthHeight.map { $0.map(String.init) ?? "unspecified" }.joined(separator: " × "))
                    Text("Display units: " + displayUnit(h.declaredDisplayUnit))
                    if report.activeAreas.isEmpty { Text("No Level 5 active-area blocks reported. Pixel black-bar edges have not been measured.") }
                    ForEach(sortedAreas(report).indices, id: \.self) { index in
                        let area = sortedAreas(report)[index]
                        Text("Level 5 offsets · left \(area.left), right \(area.right), top \(area.top), bottom \(area.bottom) luma pixels · \(report.activeAreas[area, default: 0].formatted()) declarations")
                            .textSelection(.enabled)
                        if report.activeAreas.count == 1 { areaDiagram(area, width: h.declaredPixelWidth, height: h.declaredPixelHeight) }
                    }
                    Text("These offsets describe an active region in metadata. Odd luma offsets are valid; a pixel crop must separately respect chroma sampling. Display dimensions can express a ratio or physical units.")
                        .foregroundStyle(.secondary)
                }.font(.caption).padding(.top, 8)
            } label: {
                Text("Active-area and geometry declarations")
                    .accessibilityLabel("Active-area and geometry declarations")
                    .help("Expand the container raster, crop and display declarations, and Dolby Vision Level five active-area offsets. These are metadata declarations, not measurements of the pixels.")
            }.accessibilityIdentifier("dolby.inspection.geometry")
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Every RPU passed syntax and CRC checks. Every video packet's payload, order and timestamp agreed with FFprobe. The source content hash was rechecked.")
                    Text("Mapping families describe RPU metadata. Container Dolby Vision profiles and playback compatibility require separate checks. Enhancement units counted: \(report.enhancementNALs.formatted()); units are not frame counts.")
                    Text("Content mapping 2.9 appears in \(report.cmv29Records.formatted()) records; 4.0 in \(report.cmv40Records.formatted()).")
                    Text("Decoded-frame association, enhancement reconstruction, brightness measurements and calibrated rendering remain separate qualifications.")
                }.font(.caption).foregroundStyle(.secondary).padding(.top, 8)
            } label: {
                Text("What the check establishes")
                    .accessibilityLabel("What the Dolby Vision inspection establishes")
                    .help("Expand verified metadata and encoded packet checks, plus the remaining picture, enhancement and rendering qualifications.")
            }.accessibilityIdentifier("dolby.inspection.scope")
        }
    }
    private func metric(_ name: String, _ value: Int, spoken: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(name).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            Text(value.formatted()).font(.system(size: 19, weight: .semibold, design: .rounded)).monospacedDigit()
        }.accessibilityElement(children: .combine).accessibilityLabel((spoken ?? name) + ": " + value.formatted())
            .help((spoken ?? name) + ": " + value.formatted())
            .accessibilityIdentifier("dolby.inspection.metric." + name)
    }
    private func mapping(_ key: String) -> String {
        let parts = key.split(separator: ":")
        let layer = parts.last == "MEL" ? "minimal enhancement metadata" : parts.last == "FEL" ? "full enhancement metadata" : "enhancement type not classified"
        return "RPU mapping family \(parts.first ?? "?") · \(layer)"
    }
    private func displayUnit(_ value: Int) -> String { ["pixels", "centimeters", "inches", "display aspect ratio", "unknown"][value] }
    private func sortedAreas(_ report: DolbySourceReport) -> [DolbyActiveArea] {
        report.activeAreas.keys.sorted { [$0.left,$0.right,$0.top,$0.bottom].lexicographicallyPrecedes([$1.left,$1.right,$1.top,$1.bottom]) }
    }
    @ViewBuilder private func areaDiagram(_ area: DolbyActiveArea, width: Int, height: Int) -> some View {
        if area.left + area.right < width, area.top + area.bottom < height {
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 8).fill(.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 4).fill(Color.accent.opacity(0.65))
                        .frame(width: proxy.size.width * Double(width-area.left-area.right)/Double(width),
                               height: proxy.size.height * Double(height-area.top-area.bottom)/Double(height))
                        .offset(x: proxy.size.width*Double(area.left)/Double(width), y: proxy.size.height*Double(area.top)/Double(height))
                }
            }.aspectRatio(CGFloat(width) / CGFloat(height), contentMode: .fit).frame(maxWidth: 360).accessibilityHidden(true)
            Text("Schematic of the declared active area; decoded pixels have not been measured.").foregroundStyle(.secondary)
        } else { Text("The declared offsets exceed the reported raster. Geometry needs review.").foregroundStyle(Color.warning) }
    }
}
