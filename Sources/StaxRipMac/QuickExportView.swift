import SwiftUI
import AppKit

struct QuickExportView: View {
    @EnvironmentObject var model: WorkspaceModel
    @EnvironmentObject var exporter: ExportController
    @EnvironmentObject var audio: AudioController
    @EnvironmentObject var batch: BatchController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 9) {
                        eyebrow("BUILT INTO YOUR MAC")
                        Text("From source to screen.").font(.system(size: 30, weight: .semibold, design: .rounded))
                        Text("A real MP4 export, with a little less ceremony.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "bolt.circle.fill").font(.system(size: 52, weight: .light)).foregroundStyle(Color.accent)
                }.padding(.bottom, 8)
                HStack(spacing: 16) {
                    Image(systemName: "film.stack").font(.title).foregroundStyle(Color.accent)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.isDemo ? "Choose a source video" : model.sourceName).font(.headline).lineLimit(2)
                        Text(model.isDemo ? "MOV and MP4 are a good place to start." : model.sourceInfo).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(model.sourceNeedsReview ? "Review saved source…" : model.isDemo ? "Open video…" : "Change source…") {
                        if model.sourceNeedsReview { model.reviewSavedSource() }
                        else { model.chooseSource() }
                    }
                        .disabled(exporter.running || model.loading || batch.running || audio.running)
                }.padding(20).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
                HStack(spacing: 12) {
                    ForEach(NativePreset.allCases) { preset in
                        Button { exporter.preset = preset } label: {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Image(systemName: preset == .hevcHD ? "leaf" : preset == .h264Small ? "paperplane" : "play.rectangle")
                                    Spacer()
                                    Image(systemName: exporter.preset == preset ? "checkmark.circle.fill" : "circle")
                                }.font(.title3).foregroundStyle(exporter.preset == preset ? Color.accent : .secondary)
                                Text(preset.rawValue).font(.system(size: 15, weight: .semibold))
                                Text(preset.detail).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3).frame(maxWidth: .infinity, alignment: .leading)
                            }.padding(18).frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
                                .background(exporter.preset == preset ? Color.accent.opacity(0.09) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 13))
                                .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(exporter.preset == preset ? Color.accent : .clear))
                        }.buttonStyle(.plain).disabled(exporter.running || audio.running)
                            .accessibilityLabel("Native \(AccessibilityLanguage.spokenCodecs(preset.rawValue)) preset")
                            .accessibilityValue(exporter.preset == preset ? "Selected" : "Not selected")
                            .accessibilityInputLabels([Text(preset.rawValue)])
                            .accessibilityHint(AccessibilityLanguage.nativePresetHint(preset))
                    }
                }
                Label("Apple’s preset controls video and supported audio tracks. Workspace CRF, crop, audio, subtitles and queued configurations are not used here.", systemImage: "info.circle")
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: exporter.result != nil ? "checkmark.seal.fill" : exporter.failure != nil ? "exclamationmark.triangle" : "waveform.path")
                            .foregroundStyle(exporter.failure != nil ? Color.warning : Color.accent)
                        Text(exporter.status).font(.headline)
                        Spacer()
                        if exporter.running && !exporter.finishing { Text("\(Int(exporter.progress * 100))%").monospacedDigit() }
                    }
                    if exporter.running {
                        if exporter.finishing {
                            ProgressView().accessibilityLabel("Saving completed output")
                            Text("Saving has started. The app will wait for the destination’s result before removing temporary files.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else { ProgressView(value: exporter.progress) }
                        Text(exporter.sourceName).font(.caption).foregroundStyle(.secondary)
                    }
                    if let error = exporter.failure { Text(error).font(.callout).foregroundStyle(Color.warning).textSelection(.enabled) }
                    if let url = exporter.result {
                        Text(url.lastPathComponent).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                        HStack {
                            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                            Button("Preview result") { model.load(url); model.section = "Workspace" }
                        }
                    }
                    HStack {
                        Text("Existing media is never replaced.").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if exporter.running {
                            Button(exporter.finishing ? "Saving output…" : "Cancel export", role: .cancel) { exporter.cancel() }
                                .disabled(exporter.finishing)
                                .help(exporter.finishing ? "The filesystem save is in progress and cannot be recalled. Its result will be reported when it finishes." : "Cancel encoding before the completed output is saved.")
                        } else {
                            Button {
                                model.chooseNativeExport(using: exporter) { !batch.running && !audio.running }
                            } label: {
                                Label("Export MP4…", systemImage: "arrow.up.forward.video")
                            }.primaryAction().controlSize(.large)
                                .disabled(model.isDemo || model.loading || model.sourceUnavailable || model.filePanelActive || batch.running || audio.running)
                        }
                    }
                }.padding(22).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
                Text("Native export uses AVFoundation. Format support, frame dimensions, HDR handling and audio conversion follow the selected Apple preset; this is not a precision archival workflow.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(30)
        }
    }
}
