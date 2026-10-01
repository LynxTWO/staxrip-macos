import Foundation
import Testing
@testable import StaxRipMac

@MainActor
struct SourceImportLifecycleTests {
    private final class Panels: WorkspacePanelPresenting {
        var selections: [(WorkspaceFileRequest, @MainActor (URL?) -> Void)] = []
        func select(_ request: WorkspaceFileRequest, completion: @escaping @MainActor (URL?) -> Void) -> Bool {
            selections.append((request, completion)); return true
        }
        func confirmReplacement(completion: @escaping @MainActor (Bool) -> Void) -> Bool { false }
    }
    private actor Reader {
        var started: [URL] = []
        var active = 0, maximumActive = 0
        var pending: [URL: CheckedContinuation<LoadedSource, Error>] = [:]
        func read(_ url: URL) async throws -> LoadedSource {
            started.append(url); active += 1; maximumActive = max(maximumActive, active)
            defer { active -= 1 }
            // Deliberately ignore cancellation until released, to test ownership
            // and rejection of a late success or failure from an uncooperative read.
            return try await withCheckedThrowingContinuation { pending[url] = $0 }
        }
        func release(_ url: URL, fail: Bool = false) {
            guard let continuation = pending.removeValue(forKey: url) else { Issue.record("No held reader for requested release"); return }
            if fail { continuation.resume(throwing: NativeExportError.invalid("Generated read failure")) }
            else { continuation.resume(returning: LoadedSource(nativePreview: false, info: "Generated source information")) }
        }
        func releaseAll() {
            let held = pending; pending = [:]
            for continuation in held.values { continuation.resume(throwing: CancellationError()) }
        }
    }
    private func waitFor(_ count: Int, reader: Reader) async throws {
        while await reader.started.count < count { try await Task.sleep(for: .milliseconds(1)) }
    }
    private func settle(_ model: WorkspaceModel) async throws {
        while model.loading { try await Task.sleep(for: .milliseconds(1)) }
    }
    private func prior(_ model: WorkspaceModel) {
        model.sourceURL = URL(fileURLWithPath: "/generated/prior.mkv")
        model.sourceName = "prior.mkv"; model.sourceInfo = "Prior information"; model.sourceUnavailable = true
        model.outputStem = "prior-output"
        model.config.audioTracks = [3]; model.config.subtitleTracks = [4]
        model.config.quality = 19
    }
    @Test(.timeLimit(.minutes(1))) func replacementsWaitForOldWorkerAndOnlyStartLatestRequest() async throws {
        let reader = Reader(), a = URL(fileURLWithPath: "/generated/a.mkv"), b = URL(fileURLWithPath: "/generated/b.mkv"), c = URL(fileURLWithPath: "/generated/c.mkv")
        let model = WorkspaceModel(readSource: { try await reader.read($0) }); prior(model)
        let before = model.sessionSnapshot
        do {
            model.load(a); try await waitFor(1, reader: reader)
            model.load(b); model.load(c)
            #expect(model.loading && model.sourceLoadingStatus.contains("Stopping the previous"))
            #expect(model.sessionSnapshot == before)
            #expect(await reader.started == [a])
            await reader.release(a)
            try await waitFor(2, reader: reader)
            #expect(await reader.started == [a, c])
            #expect(await reader.maximumActive == 1)
            #expect(model.sessionSnapshot == before && model.error == nil)
            await reader.release(c); try await settle(model)
            #expect(model.sourceURL == c && model.sourceName == "c.mkv")
            #expect(model.outputStem == "c_encoded" && model.sourceUnavailable)
            #expect(model.sourceInfo == "Generated source information")
            #expect(model.config.audioTracks == nil && model.config.subtitleTracks == nil)
            #expect(model.config.quality == 19 && !model.canUndoSettings)
        } catch { model.cancelSourceLoad(); await reader.releaseAll(); throw error }
    }
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func cancellationPreservesPriorWorkspaceAndRejectsLateSuccessOrFailure(fail: Bool) async throws {
        let reader = Reader(), selected = URL(fileURLWithPath: "/generated/selected.mkv")
        let model = WorkspaceModel(readSource: { try await reader.read($0) }); prior(model)
        let before = model.sessionSnapshot
        #expect(model.canUndoSettings)
        do {
            model.load(selected); try await waitFor(1, reader: reader)
            model.load(URL(fileURLWithPath: "/generated/pending-cancelled.mkv"))
            model.cancelSourceLoad()
            #expect(model.loading && model.sourceLoadStopping)
            #expect(model.sourceLoadingStatus.contains("Waiting for the current reader"))
            #expect(model.sessionSnapshot == before && model.sourceInfo == "Prior information")
            await reader.release(selected, fail: fail); try await settle(model)
            #expect(!model.sourceLoadStopping && model.sourceLoadingStatus.isEmpty)
            #expect(model.sessionSnapshot == before && model.sourceInfo == "Prior information")
            #expect(model.error == nil && model.notice.contains("cancelled"))
            #expect(await reader.started == [selected])
            #expect(model.canUndoSettings)
        } catch { model.cancelSourceLoad(); await reader.releaseAll(); throw error }
    }
    @Test(.timeLimit(.minutes(1))) func cancellationBeforeTaskStartsNeverInvokesReader() async throws {
        let reader = Reader(), model = WorkspaceModel(readSource: { try await reader.read($0) })
        prior(model); let before = model.sessionSnapshot
        model.load(URL(fileURLWithPath: "/generated/not-opened.mkv")); model.cancelSourceLoad()
        do { try await settle(model) }
        catch { await reader.releaseAll(); throw error }
        #expect(await reader.started.isEmpty)
        #expect(model.sessionSnapshot == before && model.error == nil)
    }
    @Test(.timeLimit(.minutes(1))) func demoAndRestorationCancelOldWorkAndKeepSavedSourceIntent() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("source-restore-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let saved = root.appendingPathComponent("saved.mkv"); try Data([1]).write(to: saved)
        let old = root.appendingPathComponent("old.mkv"), reader = Reader(), panels = Panels()
        let model = WorkspaceModel(filePanels: panels, readSource: { try await reader.read($0) }); prior(model)
        var configuration = EncodeConfiguration(); configuration.audioTracks = [7]; configuration.subtitleTracks = [8]
        let document = SessionDocument(sourcePath: saved.path, configuration: configuration, outputFolder: root.path, outputStem: "saved-output", jobs: [])
        do {
            model.load(old); try await waitFor(1, reader: reader)
            model.showDemo()
            #expect(model.isDemo && model.player == nil && model.loading && model.sourceLoadStopping)
            model.restoreSession(document)
            #expect(model.sessionSnapshot == document)
            #expect(await reader.started == [old])
            await reader.release(old, fail: true)
            try await settle(model)
            #expect(await reader.started == [old])
            #expect(model.sourceNeedsReview && model.sourceUnavailable && model.player == nil)
            model.reviewSavedSource()
            #expect(panels.selections.count == 1 && panels.selections[0].0 == .reviewSource(saved))
            panels.selections[0].1(saved)
            try await waitFor(2, reader: reader)
            #expect(model.sessionSnapshot == document && model.error == nil)
            await reader.release(saved); try await settle(model)
            #expect(model.sessionSnapshot == document && model.sourceUnavailable)
            #expect(!model.sourceNeedsReview)
            #expect(model.config.audioTracks == [7] && model.config.subtitleTracks == [8])
            #expect(model.error == nil && !model.canUndoSettings)
            #expect(await reader.maximumActive == 1)
        } catch { model.cancelSourceLoad(); await reader.releaseAll(); throw error }
    }

    @Test(.timeLimit(.minutes(1))) func restoredReviewCancelWrongPathAndStaleCallbacksPreserveIntent() async throws {
        let reader = Reader(), panels = Panels()
        let model = WorkspaceModel(filePanels: panels, readSource: { try await reader.read($0) })
        let saved = URL(fileURLWithPath: "/generated/saved.mkv")
        var c = EncodeConfiguration()
        c.audioTracks = [1]; c.subtitleTracks = [3]; c.cropTop = 12
        c.picture.start = 2; c.picture.end = 8
        c.externalSubtitle = ExternalSubtitle(path: "/generated/captions.srt")
        let job = QueueJob(id: UUID(), source: saved.path, isDemo: false, destination: "/generated/queued.mkv", configuration: c, created: Date())
        let document = SessionDocument(sourcePath: saved.path, configuration: c, outputFolder: "/generated", outputStem: "saved-name", jobs: [job])
        model.restoreSession(document)
        #expect(!model.loading && model.sourceNeedsReview && model.player == nil)
        #expect(model.sessionSnapshot == document)
        #expect(await reader.started.isEmpty)
        model.reviewSavedSource(); model.reviewSavedSource()
        #expect(panels.selections.count == 1)
        panels.selections[0].1(nil)
        #expect(!model.filePanelActive && model.sessionSnapshot == document && model.sourceNeedsReview)
        model.reviewSavedSource()
        panels.selections[1].1(URL(fileURLWithPath: "/generated/different.mkv"))
        #expect(model.error?.contains("Choose the saved source") == true)
        #expect(model.sessionSnapshot == document && !model.loading && model.sourceNeedsReview)
        model.reviewSavedSource()
        model.outputStem = "newer-edit"
        let newer = model.sessionSnapshot
        panels.selections[2].1(saved)
        #expect(model.sessionSnapshot == newer && !model.loading && !model.filePanelActive)
        #expect(model.notice.contains("workspace changed"))
        #expect(await reader.started.isEmpty)
        model.reviewSavedSource()
        model.showDemo()
        let demo = model.sessionSnapshot
        panels.selections[3].1(saved)
        #expect(model.sessionSnapshot == demo && model.isDemo && !model.sourceNeedsReview)
        #expect(await reader.started.isEmpty)
    }

    @Test(.timeLimit(.minutes(1))) func restoredReviewFailureRetryAndDuplicateSelectionKeepFullRecipe() async throws {
        let reader = Reader(), panels = Panels()
        let model = WorkspaceModel(filePanels: panels, readSource: { try await reader.read($0) })
        let saved = URL(fileURLWithPath: "/generated/review-retry.mkv")
        var c = EncodeConfiguration(); c.audioTracks = []; c.subtitleTracks = [8]
        c.cropTop = 12; c.picture.cropLeft = 6; c.picture.start = 1; c.picture.end = 3
        c.externalSubtitle = ExternalSubtitle(path: "/generated/retained.srt")
        let document = SessionDocument(sourcePath: saved.path, configuration: c, outputFolder: "/generated", outputStem: "retained-name", jobs: [])
        model.restoreSession(document)
        do {
            model.reviewSavedSource(); panels.selections[0].1(saved); panels.selections[0].1(saved)
            try await waitFor(1, reader: reader)
            #expect(await reader.started == [saved])
            model.reviewSavedSource()
            #expect(panels.selections.count == 1) // A running review still owns the reader.
            await reader.release(saved, fail: true); try await settle(model)
            #expect(model.sessionSnapshot == document && model.sourceNeedsReview)
            #expect(model.error == "Generated read failure" && model.player == nil)
            model.reviewSavedSource(); panels.selections[1].1(saved)
            try await waitFor(2, reader: reader)
            #expect(model.error == nil)
            await reader.release(saved); try await settle(model)
            #expect(model.sessionSnapshot == document && !model.sourceNeedsReview)
            #expect(model.sourceUnavailable && !model.canUndoSettings)
            #expect(await reader.maximumActive == 1)
        } catch { model.cancelSourceLoad(); await reader.releaseAll(); throw error }
    }
    @Test(.timeLimit(.minutes(1))) func currentFailureRetainsPriorSourceAndAllowsRetry() async throws {
        let reader = Reader(), source = URL(fileURLWithPath: "/generated/retry.mkv")
        let model = WorkspaceModel(readSource: { try await reader.read($0) }); prior(model)
        let before = model.sessionSnapshot
        do {
            model.load(source); try await waitFor(1, reader: reader)
            await reader.release(source, fail: true); try await settle(model)
            #expect(model.sessionSnapshot == before && model.error == "Generated read failure")
            model.load(source); try await waitFor(2, reader: reader)
            #expect(model.error == nil)
            await reader.release(source); try await settle(model)
            #expect(model.sourceURL == source && model.outputStem == "retry_encoded")
            #expect(model.error == nil && model.notice.contains("Source inspected"))
        } catch { model.cancelSourceLoad(); await reader.releaseAll(); throw error }
    }
}
