import AppKit
import Combine

@MainActor
final class DockStatusController {
    private var observations: AnyCancellable?
    private var read: (() -> DockPresentation)?
    private var show: ((String) -> Void)?
    private var presentation = DockPresentation(activities: [], attention: [])

    func bind(model: WorkspaceModel, exporter: ExportController, batch: BatchController,
              audio: AudioController, picture: PicturePreviewController, motion: MotionPreviewController,
              chapters: ChapterEditorController, dolby: DolbyInspectionController? = nil, show: @escaping (String) -> Void) {
        self.show = show
        read = { [weak model, weak exporter, weak batch, weak audio, weak picture, weak motion, weak chapters, weak dolby] in
            var work: [DockPresentation.Activity] = [], attention: [String] = []
            if let model, let batch {
                let queue = DockPresentation.queue(jobs: model.jobs.map(\.id), statuses: batch.statuses,
                    running: batch.running, reviewing: batch.reviewing, publishing: batch.publicationJobID, checks: batch.queueChecks)
                if let active = queue.0 { work.append(active) }
                attention += queue.1
                if batch.inspecting { work.append(.init(title: "Inspecting media")) }
                if batch.recoveryError != nil { attention.append("Queue · recovery needs attention") }
            }
            if let exporter {
                if exporter.running {
                    work.append(.init(title: exporter.finishing ? "Quick Export · finishing output" : "Quick Export · processing",
                                      progress: exporter.finishing ? nil : exporter.progress))
                } else if exporter.failure != nil {
                    attention.append(exporter.result == nil ? "Quick Export · review the failed export" : "Quick Export · saved, cleanup needs attention")
                }
            }
            if model?.loading == true { work.append(.init(title: "Loading source")) }
            if audio?.running == true { work.append(.init(title: "Audio Lab · processing")) }
            if picture?.running == true { work.append(.init(title: "Rendering picture comparison")) }
            if motion?.running == true { work.append(.init(title: "Rendering motion comparison")) }
            if motion?.cleanupFailed == true { attention.append("Motion comparison · cleanup needs attention") }
            if chapters?.running == true { work.append(.init(title: "Reading chapters")) }
            if dolby?.running == true { work.append(.init(title: "Inspecting Dolby Vision metadata")) }
            return DockPresentation(activities: work, attention: attention)
        }
        // Published values change after objectWillChange. Deliver on the next main
        // queue turn so each snapshot reads the committed state, without polling.
        observations = Publishers.MergeMany([
            model.objectWillChange.eraseToAnyPublisher(), exporter.objectWillChange.eraseToAnyPublisher(),
            batch.objectWillChange.eraseToAnyPublisher(), audio.objectWillChange.eraseToAnyPublisher(),
            picture.objectWillChange.eraseToAnyPublisher(), motion.objectWillChange.eraseToAnyPublisher(),
            chapters.objectWillChange.eraseToAnyPublisher()
        ] + (dolby.map { [$0.objectWillChange.eraseToAnyPublisher()] } ?? [])).receive(on: DispatchQueue.main).sink { [weak self] _ in self?.refresh() }
        refresh(force: true)
    }

    private func refresh(force: Bool = false) {
        guard let value = read?() else { return }
        guard force || value != presentation else { return }
        presentation = value
        // Preserve the system-rendered app icon and its appearance/material layers.
        NSApplication.shared.dockTile.badgeLabel = value.badge
    }

    func menu() -> NSMenu {
        refresh()
        let menu = NSMenu()
        menu.autoenablesItems = false
        let summary = NSMenuItem(title: presentation.summary, action: nil, keyEquivalent: "")
        summary.isEnabled = false
        menu.addItem(summary)
        if presentation.details.count > 1 || presentation.badge == "!" {
            for line in presentation.details {
                let item = NSMenuItem(title: line, action: nil, keyEquivalent: "")
                item.isEnabled = false; menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        for section in ["Workspace", "Queue", "Quick Export", "Audio Lab"] {
            let item = NSMenuItem(title: "Show \(section)", action: #selector(navigate(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = section
            menu.addItem(item)
        }
        return menu
    }

    @objc private func navigate(_ item: NSMenuItem) {
        guard let section = item.representedObject as? String else { return }
        show?(section)
    }
}
