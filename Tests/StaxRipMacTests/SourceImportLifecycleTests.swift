import Foundation
import Testing
@testable import StaxRipMac

@MainActor
struct SourceImportLifecycleTests {
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
        let old = root.appendingPathComponent("old.mkv"), reader = Reader()
        let model = WorkspaceModel(readSource: { try await reader.read($0) }); prior(model)
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
            try await waitFor(2, reader: reader)
            #expect(model.sessionSnapshot == document && model.error == nil)
            await reader.release(saved); try await settle(model)
            #expect(model.sessionSnapshot == document && model.sourceUnavailable)
            #expect(model.config.audioTracks == [7] && model.config.subtitleTracks == [8])
            #expect(model.error == nil && !model.canUndoSettings)
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
