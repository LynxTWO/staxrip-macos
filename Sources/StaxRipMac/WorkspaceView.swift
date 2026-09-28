import SwiftUI
import AVKit
import UniformTypeIdentifiers

struct WorkspaceView: View {
    @EnvironmentObject var model: WorkspaceModel
    @EnvironmentObject var exporter: ExportController
    @EnvironmentObject var batch: BatchController
    @State private var showingInspector = false
    @AppStorage("appearance") private var appearance = "System"
    @State private var isDropTarget = false
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 208)
            Divider()
            VStack(spacing: 0) {
                header
                Divider()
                if model.section == "Quick Export" {
                    QuickExportView()
                } else if model.section == "Audio Lab" {
                    AudioLabView()
                } else if model.section == "Queue" {
                    QueueView()
                } else {
                    HStack(spacing: 0) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 22) {
                                sourceHeader
                                preview
                                settings
                            }.padding(26)
                        }
                        Divider()
                        outputInspector.frame(width: 272)
                    }
                }
                Divider()
                statusBar
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showingInspector) {
            if let source = model.sourceURL { MediaInspectorView(source: source).environmentObject(batch) }
        }
        .alert("Couldn’t complete that action", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 25, weight: .semibold)).foregroundStyle(Color.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("StaxRip").font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("MADE FOR MAC").font(.system(size: 8, weight: .bold)).tracking(2).foregroundStyle(.secondary)
                }
            }.padding(.top, 42).padding(.bottom, 36)
            eyebrow("LIBRARY").padding(.bottom, 12)
            navItem("Workspace", symbol: "slider.horizontal.3")
            navItem("Quick Export", symbol: "bolt.fill")
            navItem("Audio Lab", symbol: "waveform")
            navItem("Queue", symbol: "square.stack", count: model.jobs.count)
            eyebrow("ADVANCED PRESETS").padding(.top, 34).padding(.bottom, 12)
            preset("Compact AV1", subtitle: "Smaller files, more detail", symbol: "leaf")
            preset("Everyday HEVC", subtitle: "A balanced starting point", symbol: "sparkles")
            preset("H.264 Quality", subtitle: "Broad playback support", symbol: "play.rectangle")
            Spacer()
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    Circle().fill(Color.accent).frame(width: 6, height: 6)
                    Text(exporter.running ? "Export in progress" : "Native media workspace").font(.system(size: 11, weight: .semibold))
                }
                Text("Your media. Your Mac. Your rules.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
                Picker("Appearance", selection: $appearance) {
                    Text("Auto").tag("System")
                    Text("Light").tag("Light")
                    Text("Dark").tag("Dark")
                }.pickerStyle(.segmented).labelsHidden().help("App appearance")
                Text("v0.6  /  LOCAL PREVIEW").font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
            }.padding(.bottom, 24)
        }.padding(.horizontal, 18)
            .background(.ultraThinMaterial)
    }

    private func navItem(_ title: String, symbol: String, count: Int = 0) -> some View {
        Button { model.section = title } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 18)
                Text(title).fontWeight(model.section == title ? .semibold : .regular)
                Spacer()
                if count > 0 { Text("\(count)").font(.caption).padding(.horizontal, 6).padding(.vertical, 2).background(.quaternary, in: Capsule()) }
            }.font(.system(size: 13)).padding(.horizontal, 12).padding(.vertical, 11)
                .foregroundStyle(model.section == title ? Color.accent : Color.primary)
                .background(model.section == title ? Color.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 9))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).padding(.bottom, 4)
    }

    private func preset(_ title: String, subtitle: String, symbol: String) -> some View {
        Button { model.applyPreset(title) } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 17).padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 12, weight: .medium))
                    Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }.padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).help("Apply \(title) configuration")
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.section).font(.system(size: 17, weight: .semibold))
                Text(model.section == "Workspace" ? "Make every frame count." : model.section == "Quick Export" ? "Real exports. Native engine." : model.section == "Audio Lab" ? "Give sound the attention it deserves." : "Your next encodes, all in one place.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button("Save session…") { model.saveSession() }
                Button("Open session…") { model.openSession() }
            } label: { Label("Session", systemImage: "doc.badge.gearshape") }
            .menuStyle(.borderlessButton).fixedSize().help(model.sessionName).disabled(exporter.running || batch.running)
            Text("PROTOTYPE").font(.system(size: 9, weight: .semibold)).tracking(1)
                .foregroundStyle(.secondary).padding(.horizontal, 9).padding(.vertical, 5)
                .overlay(Capsule().strokeBorder(.quaternary))
            Button { model.chooseSource() } label: { Label("Open source", systemImage: "plus") }
                .controlSize(.large).padding(.leading, 12)
                .disabled(model.loading || exporter.running || batch.running)
        }.padding(.horizontal, 26).frame(height: 83)
    }

    private var sourceHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "film").font(.title3).foregroundStyle(Color.accent)
                .frame(width: 42, height: 42).background(Color.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(model.sourceName).font(.system(size: 16, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                    if model.isDemo { Text("DEMO").font(.system(size: 8, weight: .bold)).padding(.horizontal, 5).padding(.vertical, 3).background(.quaternary, in: RoundedRectangle(cornerRadius: 3)) }
                }
                Text(model.sourceInfo).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if model.loading { ProgressView().controlSize(.small) }
            if model.sourceURL != nil {
                Button { showingInspector = true } label: { Image(systemName: "info.circle") }
                    .buttonStyle(.borderless).help("Inspect media tracks").accessibilityLabel("Inspect media tracks")
            }
            if !model.isDemo || model.loading {
                Button { model.showDemo() } label: { Image(systemName: "arrow.counterclockwise") }
                    .buttonStyle(.borderless).disabled(exporter.running || batch.running).help("Return to demo preview").accessibilityLabel("Return to demo preview")
            }
        }
    }

    private var preview: some View {
        VStack(spacing: 0) {
            Group {
                if let player = model.player {
                    NativeVideoPreview(player: player)
                } else if !model.isDemo {
                    VStack(spacing: 12) {
                        Image(systemName: "video.slash").font(.largeTitle).foregroundStyle(.secondary)
                        Text("Source preview unavailable").font(.headline)
                        Text("Native playback is unavailable. The advanced engine may still support this source.").font(.caption).foregroundStyle(.secondary)
                        Button("Locate source…") { model.chooseSource() }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    AlpinePreview()
                }
            }.frame(height: 230).frame(maxWidth: .infinity).clipped()
            HStack(spacing: 8) {
                Image(systemName: model.isDemo ? "photo" : "play.rectangle")
                Text(model.isDemo ? "Illustrated demo · open a video for playback" : "Source playback · encoding filters are not applied")
                Spacer(minLength: 0)
                Image(systemName: "arrow.down.doc").help("Drop a video onto the preview")
            }.font(.system(size: 10)).foregroundStyle(.secondary).padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
        }
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(isDropTarget ? Color.accent : Color.primary.opacity(0.08), lineWidth: isDropTarget ? 2 : 1))
        .onDrop(of: [.fileURL], isTargeted: $isDropTarget) { providers in
            guard !exporter.running, !batch.running, let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { Task { @MainActor in model.load(url) } }
            }
            return true
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 18) {
            Picker("Settings", selection: $model.tab) {
                ForEach(["Picture", "Video", "Audio", "Subtitles"], id: \.self) { Text($0) }
            }.pickerStyle(.segmented).labelsHidden()
            switch model.tab {
            case "Picture": pictureSettings
            case "Audio": audioSettings
            case "Subtitles": subtitleSettings
            default: videoSettings
            }
        }
    }

    private var videoSettings: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                sectionTitle("Video encoding", subtitle: "Quality first. Every setting within reach.")
                Spacer()
                Text("SOFTWARE").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                settingPicker("Codec", selection: $model.config.codec, values: ["AV1", "HEVC", "H.264"])
                    .onChange(of: model.config.codec) { _, value in
                        model.config.encoder = value == "AV1" ? "SVT-AV1" : value == "HEVC" ? "x265" : "x264"
                    }
                VStack(alignment: .leading, spacing: 6) {
                    eyebrow("ENCODER")
                    Text(model.config.encoder).font(.system(size: 12, weight: .medium)).frame(maxWidth: .infinity, alignment: .leading).padding(9)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Constant quality").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text("CRF \(Int(model.config.quality))").font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(Color.accent)
                }
                Slider(value: $model.config.quality, in: 0...51, step: 1).accessibilityLabel("Constant rate factor")
                HStack {
                    Text("Higher quality")
                    Spacer()
                    Text("Smaller file")
                }.font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(14).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            settingPicker("Speed preference", selection: $model.config.speed, values: ["Thorough", "Balanced", "Fast"])
            Text("FFmpeg applies these settings when you start the queue. First video, all audio tracks; SDR 8-bit 4:2:0 sources only.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private var pictureSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionTitle("Picture", subtitle: "Keep the original frame, or shape your output.")
            settingPicker("Output size", selection: $model.config.resolution, values: ["Original", "1920 × 1080", "1280 × 720"])
            HStack(spacing: 24) {
                Stepper("Top crop: \(model.config.cropTop) px", value: $model.config.cropTop, in: 0...240, step: 2)
                Stepper("Bottom: \(model.config.cropBottom) px", value: $model.config.cropBottom, in: 0...240, step: 2)
            }.font(.system(size: 12))
            Text("Crop and size apply during queue encoding. Size fits within the selected bounds without stretching; the source preview stays unfiltered.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var audioSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionTitle("Audio", subtitle: "Choose how your soundtrack travels.")
            settingPicker("Audio handling", selection: $model.config.audio, values: ["AAC", "Opus", "Copy original", "No audio"])
            if model.config.audio == "AAC" || model.config.audio == "Opus" {
                settingPicker("Bitrate", selection: $model.config.audioBitrate, values: ["128 kb/s", "192 kb/s", "256 kb/s", "320 kb/s"])
            }
            Text("Applies to all audio tracks. Copy preserves their codecs; AAC and Opus re-encode at the selected bitrate. Inspect the source to see its tracks.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var subtitleSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionTitle("Subtitles", subtitle: "Set a default for embedded subtitle tracks.")
            settingPicker("Track handling", selection: $model.config.subtitleMode, values: ["Keep embedded tracks", "Remove all subtitles"])
            Label("Embedded tracks are copied without re-encoding", systemImage: "text.bubble")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Text("MKV preserves supported subtitle formats and attachments. MP4 accepts existing mov_text tracks; choose MKV for other subtitle formats.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var outputInspector: some View {
        VStack(alignment: .leading, spacing: 22) {
            sectionTitle("Output", subtitle: "The finishing details.")
            settingPicker("Container", selection: $model.config.container, values: ["MKV", "MP4"])
            VStack(alignment: .leading, spacing: 8) {
                eyebrow("FILE NAME")
                HStack(spacing: 4) {
                    TextField("Output name", text: $model.outputStem).textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Output file name")
                    Text("." + model.config.container.lowercased()).foregroundStyle(.secondary)
                }.font(.system(size: 12, design: .monospaced))
                if let issue = model.outputIssue {
                    Text(issue).font(.system(size: 10)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    eyebrow("DESTINATION")
                    Spacer()
                    Button("Choose…") { model.chooseOutput() }.buttonStyle(.link).font(.system(size: 11))
                }
                Label(model.outputFolder.lastPathComponent, systemImage: "folder")
                    .font(.system(size: 12)).lineLimit(2).help(model.outputFolder.path)
            }
            Divider()
            VStack(alignment: .leading, spacing: 13) {
                eyebrow("AT A GLANCE")
                summaryRow("Video", "\(model.config.codec) · CRF \(Int(model.config.quality))")
                summaryRow("Size", model.config.resolution)
                summaryRow("Audio", model.config.audio)
                summaryRow("Container", model.config.container)
            }
            Spacer(minLength: 20)
            VStack(alignment: .leading, spacing: 10) {
                Label("Make it yours", systemImage: "sparkle").font(.system(size: 12, weight: .semibold))
                Text("Try a preset, adjust the details, then collect your configurations in the queue.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
            }.padding(15).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            VStack(spacing: 10) {
                Button { model.addToQueue() } label: {
                    HStack { Image(systemName: "plus"); Text("Add to queue"); Spacer(); Text("⌘J").opacity(0.6) }
                        .font(.system(size: 12, weight: .semibold)).padding(13)
                        .foregroundStyle(Color.ink).background(Color.accent, in: RoundedRectangle(cornerRadius: 9))
                }.buttonStyle(.plain).disabled(model.loading || model.outputIssue != nil)
                Text(batch.tools == nil ? "FFmpeg required to run jobs" : "FFmpeg engine ready")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }.padding(22).background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
    }

    private var statusBar: some View {
        HStack(spacing: 7) {
            Circle().fill(Color.accent).frame(width: 5, height: 5)
            Text(exporter.running ? exporter.status : model.loading ? "Reading source…" : model.notice.isEmpty ? "Ready to explore" : model.notice)
            Spacer()
            Text(model.sessionName).lineLimit(1).foregroundStyle(.tertiary)
            Text("·").foregroundStyle(.tertiary)
            Text("\(model.jobs.count) queued").foregroundStyle(.secondary)
        }.font(.system(size: 10)).padding(.horizontal, 24).frame(height: 32)
    }

    private func summaryRow(_ title: String, _ value: String) -> some View {
        HStack { Text(title).foregroundStyle(.secondary); Spacer(); Text(value).lineLimit(1) }.font(.system(size: 11))
    }
}

func eyebrow(_ text: String) -> some View {
    Text(text.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(1.2).foregroundStyle(.secondary)
}

func sectionTitle(_ title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 5) {
        Text(title).font(.system(size: 15, weight: .semibold))
        Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
    }
}

func settingPicker(_ title: String, selection: Binding<String>, values: [String]) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        eyebrow(title)
        Picker(title, selection: selection) { ForEach(values, id: \.self) { Text($0) } }
            .labelsHidden().frame(maxWidth: .infinity).controlSize(.large)
    }.frame(maxWidth: .infinity, alignment: .leading)
}
