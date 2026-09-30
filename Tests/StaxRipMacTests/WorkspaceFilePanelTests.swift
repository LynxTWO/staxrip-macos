import Foundation
import Testing
@testable import StaxRipMac

@MainActor
struct WorkspaceFilePanelTests {
    @MainActor
    private final class Panels: WorkspacePanelPresenting {
        var selections: [(WorkspaceFileRequest, @MainActor (URL?) -> Void)] = []
        var confirmations: [@MainActor (Bool) -> Void] = []
        var allowSelection = true, allowConfirmation = true
        func select(_ request: WorkspaceFileRequest, completion: @escaping @MainActor (URL?) -> Void) -> Bool {
            guard allowSelection else { return false }
            selections.append((request, completion)); return true
        }
        func confirmReplacement(completion: @escaping @MainActor (Bool) -> Void) -> Bool {
            guard allowConfirmation else { return false }
            confirmations.append(completion); return true
        }
    }
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("workspace-panels-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
    private func document(_ root: URL) -> SessionDocument {
        var config = EncodeConfiguration(); config.selectCodec("H.264"); config.audio = "No audio"
        let item = QueueJob(id: UUID(), source: root.appendingPathComponent("generated.mp4").path, isDemo: false,
                            destination: root.appendingPathComponent("generated-result.mkv").path,
                            configuration: config, created: Date(timeIntervalSince1970: 1000))
        return SessionDocument(sourcePath: nil, configuration: config, outputFolder: root.path, outputStem: "restored", jobs: [item])
    }

    @Test func allWorkspaceDialogsCancelWithoutMutatingIntentOrWriting() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let panels = Panels()
        // Use a separate model sharing this controlled presenter for each cancellation.
        let actions: [@MainActor (WorkspaceModel) -> Void] = [{$0.chooseSource()}, {$0.chooseOutput()}, {$0.openSession()}, {$0.saveSession()}, {$0.exportQueue()}]
        for action in actions {
            let current = WorkspaceModel(filePanels: panels)
            current.outputFolder = directory
            let before = current.sessionSnapshot
            let count = panels.selections.count
            action(current)
            #expect(current.filePanelActive)
            #expect(panels.selections.count == count + 1)
            panels.selections[count].1(nil)
            #expect(!current.filePanelActive && current.sessionSnapshot == before)
            #expect(current.sessionName == "Untitled session" && current.error == nil)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test func duplicateAndOldCallbacksCannotConsumeANewerRequest() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let panels = Panels(), model = WorkspaceModel(filePanels: panels)
        model.chooseOutput()
        model.chooseSource(); model.openSession(); model.saveSession(); model.exportQueue()
        #expect(panels.selections.count == 1)
        let first = panels.selections[0].1
        first(directory)
        #expect(model.outputFolder == directory && !model.filePanelActive)
        model.chooseOutput()
        first(directory.appendingPathComponent("old"))
        #expect(model.filePanelActive && model.outputFolder == directory)
        panels.selections[1].1(nil)
        #expect(!model.filePanelActive && model.outputFolder == directory)

        panels.allowSelection = false
        model.chooseSource()
        #expect(!model.filePanelActive && model.notice.contains("Bring the workspace"))
        panels.allowSelection = true
        model.chooseOutput()
        #expect(model.filePanelActive)
        panels.selections[2].1(nil)
    }

    @Test func changedWorkspaceAndSourceGenerationRefuseStaleSelections() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let panels = Panels(), model = WorkspaceModel(filePanels: panels)
        let folder = model.outputFolder
        model.chooseOutput()
        model.config.quality = 19
        panels.selections[0].1(directory)
        #expect(model.outputFolder == folder && model.config.quality == 19)
        #expect(!model.filePanelActive && model.notice.contains("workspace changed"))

        model.chooseSource()
        let before = model.sessionSnapshot
        model.showDemo() // Same persisted intent; a newer source-load identity still wins.
        #expect(model.sessionSnapshot == before)
        panels.selections[1].1(directory.appendingPathComponent("unread.mp4"))
        #expect(!model.loading && model.sourceURL == nil && !model.filePanelActive)
        #expect(model.notice.contains("workspace changed"))

        let saved = directory.appendingPathComponent("session.json")
        try document(directory).write(to: saved)
        model.openSession()
        model.outputStem = "newer-name"
        panels.selections[2].1(saved)
        #expect(panels.confirmations.isEmpty && model.outputStem == "newer-name")
        #expect(!model.filePanelActive)
    }

    @Test func replacementConfirmationPreservesCancelAndRejectsStaleOrRepeatedResults() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let saved = directory.appendingPathComponent("session.json"), incoming = document(directory)
        try incoming.write(to: saved)
        let panels = Panels(), model = WorkspaceModel(filePanels: panels)
        let original = model.sessionSnapshot
        model.openSession(); panels.selections[0].1(saved)
        #expect(model.filePanelActive && panels.confirmations.count == 1)
        panels.selections[0].1(saved) // Duplicate selection cannot open another confirmation.
        #expect(panels.confirmations.count == 1 && model.filePanelActive)
        panels.confirmations[0](false)
        #expect(model.sessionSnapshot == original && !model.filePanelActive)

        model.openSession(); panels.selections[1].1(saved)
        model.outputStem = "newer-edit"
        panels.confirmations[1](true)
        #expect(model.outputStem == "newer-edit" && model.jobs.isEmpty && !model.filePanelActive)
        #expect(model.notice.contains("workspace changed"))

        model.openSession(); panels.selections[2].1(saved)
        panels.confirmations[2](true)
        #expect(model.sessionSnapshot == incoming && !model.filePanelActive)
        #expect(model.sessionName == "session" && model.notice == "Session restored")
        #expect(!FileManager.default.fileExists(atPath: incoming.jobs[0].destination))
        model.outputStem = "after-restore"
        panels.confirmations[2](true)
        #expect(model.outputStem == "after-restore")

        panels.allowConfirmation = false
        model.openSession(); panels.selections[3].1(saved)
        #expect(model.outputStem == "after-restore" && !model.filePanelActive)
        #expect(model.notice.contains("Bring the workspace"))
    }

    @Test func savesUseCapturedDocumentsAndQueueArraysWithoutMarkingNewerEditsSaved() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let panels = Panels(), model = WorkspaceModel(filePanels: panels)
        model.restoreSession(document(directory))
        let original = model.sessionSnapshot
        let saved = directory.appendingPathComponent("saved.json")
        model.saveSession()
        model.config.quality = 20
        panels.selections[0].1(saved)
        #expect(try SessionDocument.read(from: saved) == original)
        #expect(model.config.quality == 20 && model.notice.contains("unsaved changes"))
        model.openSession(); panels.selections[1].1(saved)
        #expect(panels.confirmations.count == 1) // The newer edit was not marked saved.
        panels.confirmations[0](false)

        let queue = directory.appendingPathComponent("queue.json"), jobs = model.jobs
        model.exportQueue()
        model.jobs = []
        panels.selections[2].1(queue)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode([QueueJob].self, from: Data(contentsOf: queue)) == jobs)
        #expect(model.jobs.isEmpty && model.notice.contains("current queue has changed"))
        #expect(throws: (any Error).self) { try SessionDocument.read(from: queue) }
        #expect(!FileManager.default.fileExists(atPath: original.jobs[0].destination))
        let savedBytes = try Data(contentsOf: saved)
        panels.selections[0].1(queue)
        #expect(try Data(contentsOf: saved) == savedBytes)
        #expect(try decoder.decode([QueueJob].self, from: Data(contentsOf: queue)) == jobs)
    }

    @Test func invalidDocumentsAndWriteFailuresReleaseTheRequest() throws {
        let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
        let panels = Panels(), model = WorkspaceModel(filePanels: panels)
        let invalid = directory.appendingPathComponent("invalid.json")
        try Data("{\"format\":\"not-a-session\"}".utf8).write(to: invalid)
        let original = model.sessionSnapshot
        model.openSession(); panels.selections[0].1(invalid)
        #expect(!model.filePanelActive && model.sessionSnapshot == original && model.error != nil)
        #expect(panels.confirmations.isEmpty)
        model.error = nil
        model.saveSession(); panels.selections[1].1(directory.appendingPathComponent("missing/session.json"))
        #expect(!model.filePanelActive && model.error != nil && model.sessionName == "Untitled session")
        model.error = nil
        model.exportQueue(); panels.selections[2].1(directory.appendingPathComponent("missing/queue.json"))
        #expect(!model.filePanelActive && model.error != nil && model.sessionSnapshot == original)
        model.chooseOutput(); panels.selections[3].1(directory)
        #expect(model.outputFolder == directory && !model.filePanelActive)
    }
}
