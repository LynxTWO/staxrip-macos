import Testing
import Foundation
import AVFoundation
import CoreVideo
import CoreGraphics
@testable import StaxRipMac

private final class NativePublicationGate: @unchecked Sendable {
    private let lock = NSLock()
    private let signal = DispatchSemaphore(value: 0)
    private var value: (entered: Bool, mainThread: Bool, staged: URL?) = (false, false, nil)
    var snapshot: (entered: Bool, mainThread: Bool, staged: URL?) { lock.withLock { value } }
    func release() { signal.signal() }
    func publish(_ staged: URL, _ destination: URL, fail: Bool) throws {
        lock.withLock { value = (true, Thread.isMainThread, staged) }
        guard signal.wait(timeout: .now() + 30) == .success else {
            throw NativeExportError.invalid("Held native publication timed out before its main-actor observer could release it")
        }
        if fail { throw NativeExportError.invalid("Injected destination refused publication") }
        try ExportPublication.publish(staged: staged, destination: destination)
    }
}

@MainActor
struct ExportTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("staxrip-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    @Test func publicationNeverReplacesAnExistingFileOrSymlink() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let stage = dir.appendingPathComponent("stage")
        let output = dir.appendingPathComponent("output")
        try Data("new".utf8).write(to: stage)
        try Data("original".utf8).write(to: output)
        #expect(throws: (any Error).self) { try ExportPublication.publish(staged: stage, destination: output) }
        #expect(try String(contentsOf: output, encoding: .utf8) == "original")
        let symlink = dir.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: dir.appendingPathComponent("absent"))
        #expect(throws: (any Error).self) { try ExportPublication.publish(staged: stage, destination: symlink) }
        let fresh = dir.appendingPathComponent("fresh")
        try ExportPublication.publish(staged: stage, destination: fresh)
        #expect(try String(contentsOf: fresh, encoding: .utf8) == "new")
    }

    @Test(arguments: NativePreset.allCases) func nativeExportCreatesPlayableMediaAndPreservesSource(preset: NativePreset) async throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("source.mov")
        try await makeFixture(at: source)
        let original = try Data(contentsOf: source)
        let destination = dir.appendingPathComponent("result.mp4")
        let service = NativeExportService()
        try await service.export(source: source, destination: destination, preset: preset)
        #expect(try Data(contentsOf: source) == original)
        let asset = AVURLAsset(url: destination)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        #expect(tracks.count == 1)
        let formats = try await tracks[0].load(.formatDescriptions)
        #expect(CMFormatDescriptionGetMediaSubType(formats[0]) == (preset == .hevcHD ? kCMVideoCodecType_HEVC : kCMVideoCodecType_H264))
        let audio = try await asset.loadTracks(withMediaType: .audio)
        #expect(audio.count == 1)
        let audioFormats = try await audio[0].load(.formatDescriptions)
        #expect(CMFormatDescriptionGetMediaSubType(audioFormats[0]) == kAudioFormatMPEG4AAC)
        let duration = try await asset.load(.duration)
        #expect(duration.seconds >= 0.9 && duration.seconds <= 1.1)
        let resultBefore = try Data(contentsOf: destination)
        do {
            try await service.export(source: source, destination: destination, preset: preset)
            Issue.record("Existing output should have been rejected")
        } catch { }
        #expect(try Data(contentsOf: destination) == resultBefore)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).allSatisfy { !$0.hasPrefix(".staxrip-export-") })
    }

    @Test func cancellationDoesNotPublishOutput() async throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("source.mov")
        try await makeFixture(at: source)
        let target = dir.appendingPathComponent("cancelled.mp4")
        let service = NativeExportService()
        let task = Task { try await service.export(source: source, destination: target, preset: .h264Small) }
        task.cancel()
        do { try await task.value; Issue.record("Cancelled task should not publish") }
        catch is CancellationError { }
        #expect(!FileManager.default.fileExists(atPath: target.path))
        #expect(!service.active)
    }

    @Test(arguments: 0..<8) func cancellationOfActiveSessionCleansItsStagingDirectory(iteration: Int) async throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("source.mov")
        try await makeFixture(at: source)
        let target = dir.appendingPathComponent("cancelled.mp4")
        let service = NativeExportService()
        var requested = false
        var firstProgress: Double?
        do {
            try await service.export(source: source, destination: target, preset: .h264HD, progress: { value in
                if !requested { firstProgress = value; requested = true; service.cancel() }
            })
            Issue.record("Active cancellation should prevent publication")
        } catch is CancellationError { }
        #expect(requested)
        #expect(firstProgress == 0)
        #expect(!FileManager.default.fileExists(atPath: target.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).allSatisfy { !$0.hasPrefix(".staxrip-export-") })
    }

    @Test func stagingCleanupRetriesWrappedTransientErrorsEvenWhenCancelled() async throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let owned = dir.appendingPathComponent("owned")
        try FileManager.default.createDirectory(at: owned, withIntermediateDirectories: false)
        let protected = dir.appendingPathComponent("existing-output")
        try Data("keep".utf8).write(to: protected)
        var attempts = 0
        let task = Task { @MainActor in
            try await ExportStaging.remove(owned, removeItem: { url in
                #expect(url == owned)
                attempts += 1
                if attempts < 3 {
                    throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError,
                                  userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(ENOTEMPTY))])
                }
                try FileManager.default.removeItem(at: url)
            })
        }
        task.cancel()
        try await task.value
        #expect(attempts == 3)
        #expect(!FileManager.default.fileExists(atPath: owned.path))
        #expect(try Data(contentsOf: protected) == Data("keep".utf8))
    }

    @Test func stagingCleanupBoundsRetriesAndSurfacesPermanentFailure() async throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        for code in [EBUSY, EACCES] {
            var attempts = 0
            var delays: [Double] = []
            do {
                try await ExportStaging.remove(dir, removeItem: { _ in
                    attempts += 1
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
                }, wait: { delays.append($0) })
                Issue.record("Persistent removal failure must be reported")
            } catch {
                #expect((error as NSError).code == Int(code))
            }
            #expect(attempts == (code == EBUSY ? 6 : 1))
            #expect(delays.count == (code == EBUSY ? 5 : 0))
            #expect(delays.reduce(0, +) <= 1.551)
        }
        try await ExportStaging.remove(dir.appendingPathComponent("already-absent"))
        #expect(FileManager.default.fileExists(atPath: dir.path))
        do {
            try await ExportStaging.remove(dir, removeItem: { _ in
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENOENT))
            })
            Issue.record("A missing child must not hide a remaining staging directory")
        } catch { #expect((error as NSError).code == Int(ENOENT)) }
    }

    @Test(arguments: [false, true]) func cleanupFailureReportsWhetherOutputWasPublished(cancel: Bool) async throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("source.mov")
        try await makeFixture(at: source)
        let original = try Data(contentsOf: source)
        let target = dir.appendingPathComponent("result.mp4")
        let service = NativeExportService(removeStaging: { _ in
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))
        })
        do {
            try await service.export(source: source, destination: target, preset: .h264Small, progress: { _ in
                if cancel { service.cancel() }
            })
            Issue.record("Cleanup failure must not be suppressed")
        } catch let error as ExportCleanupError {
            #expect(error.publishedOutput == (cancel ? nil : target))
            #expect((error.operationError is CancellationError) == cancel)
            #expect((error.cleanupError as NSError).code == Int(EACCES))
            #expect(error.directory.deletingLastPathComponent().standardizedFileURL == dir.standardizedFileURL)
        }
        #expect(!service.active)
        #expect(FileManager.default.fileExists(atPath: target.path) == !cancel)
        #expect(try Data(contentsOf: source) == original)
    }

    @Test func invalidMediaFailsWithoutOutputOrStagingDebris() async throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("invalid.mov")
        try Data("not a video".utf8).write(to: source)
        let target = dir.appendingPathComponent("result.mp4")
        let service = NativeExportService()
        do { try await service.export(source: source, destination: target, preset: .h264Small); Issue.record("Invalid media accepted") }
        catch { }
        #expect(!FileManager.default.fileExists(atPath: target.path))
        #expect(!service.active)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).count == 1)
    }

    @Test func cancellationAtFinalSaveBoundaryDoesNotDispatchPublication() async throws {
        let dir = try folder(); defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("source.mov"), output = dir.appendingPathComponent("output.mp4")
        try await makeFixture(at: source)
        let original = try Data(contentsOf: source)
        let dispatched = dir.appendingPathComponent("unexpected-publication")
        let service = NativeExportService(publishOperation: { _, _ in try Data([1]).write(to: dispatched) })
        do {
            try await service.export(source: source, destination: output, preset: .h264Small, finishing: { service.cancel() })
            Issue.record("Cancellation before dispatch must not report a save")
        } catch { #expect(error is CancellationError) }
        #expect(!FileManager.default.fileExists(atPath: dispatched.path) && !service.active && !FileManager.default.fileExists(atPath: output.path))
        #expect(try Data(contentsOf: source) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).allSatisfy { !$0.hasPrefix(".staxrip-export-") })
    }

    @Test(.timeLimit(.minutes(3)), arguments: ["success", "collision", "failure", "cleanup"])
    func finalPublicationKeepsUIAndStagingOwnedAndReportsRealOutcome(outcome: String) async throws {
        let dir = try folder()
        let gate = NativePublicationGate()
        var cleanupCalls = 0
        var cleaned: URL?
        let service = NativeExportService(removeStaging: { directory in
            cleanupCalls += 1; cleaned = directory
            if outcome == "cleanup" { throw NativeExportError.invalid("Injected cleanup refusal") }
            try await ExportStaging.remove(directory)
        }, publishOperation: { staged, destination in
            try gate.publish(staged, destination, fail: outcome == "failure")
        })
        defer {
            gate.release()
            if !service.active { try? FileManager.default.removeItem(at: dir) }
        }
        let source = dir.appendingPathComponent("source.mov")
        try await makeFixture(at: source)
        let original = try Data(contentsOf: source)
        let protected = dir.appendingPathComponent("prior.mp4"), protectedBytes = Data("prior output".utf8)
        try protectedBytes.write(to: protected)
        let destination = dir.appendingPathComponent("output.mp4")
        let controller = ExportController(service: service)
        controller.preset = .h264Small
        controller.start(source: source, destination: destination)
        while controller.running && !gate.snapshot.entered { try await Task.sleep(for: .milliseconds(5)) }
        #expect(!gate.snapshot.mainThread)
        try #require(gate.snapshot.entered && controller.running)
        MainActor.preconditionIsolated()
        #expect(controller.finishing && controller.status.hasPrefix("Finishing output"))
        let staged = try #require(gate.snapshot.staged)
        #expect(service.active && cleanupCalls == 0)
        #expect(FileManager.default.fileExists(atPath: staged.path))
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        // Cancellation cannot abandon the filesystem operation or erase its result.
        controller.cancel()
        try await Task.sleep(for: .milliseconds(50))
        #expect(controller.running && controller.finishing && service.active && cleanupCalls == 0)
        #expect(controller.status.hasPrefix("Finishing output"))
        #expect(FileManager.default.fileExists(atPath: staged.path))
        let competitor = Data("competing output".utf8)
        if outcome == "collision" { try competitor.write(to: destination) }
        gate.release()
        while controller.running { try await Task.sleep(for: .milliseconds(5)) }
        #expect(!service.active && !controller.finishing && cleanupCalls == 1)
        #expect(cleaned == staged.deletingLastPathComponent())
        #expect(try Data(contentsOf: source) == original)
        #expect(try Data(contentsOf: protected) == protectedBytes)
        #expect(FileManager.default.fileExists(atPath: staged.path) == (outcome == "cleanup"))
        if outcome == "success" || outcome == "cleanup" {
            #expect(controller.result == destination && controller.progress == 1)
            #expect(controller.status == (outcome == "cleanup" ? "Export saved · temporary files remain" : "Export complete"))
            #expect((controller.failure != nil) == (outcome == "cleanup"))
            let tracks = try await AVURLAsset(url: destination).loadTracks(withMediaType: .video)
            #expect(tracks.count == 1)
        } else {
            #expect(controller.result == nil && controller.status == "Export failed")
            if outcome == "collision" {
                #expect(controller.failure?.contains("nothing was overwritten") == true)
                #expect(try Data(contentsOf: destination) == competitor)
                // An explicit retry gets a fresh lifecycle and a new destination.
                let retry = dir.appendingPathComponent("retry.mp4")
                gate.release()
                controller.start(source: source, destination: retry)
                while controller.running { try await Task.sleep(for: .milliseconds(5)) }
                #expect(controller.result == retry && controller.failure == nil && controller.status == "Export complete")
                #expect(try Data(contentsOf: destination) == competitor)
                #expect(cleanupCalls == 2)
            } else {
                #expect(controller.failure == "Injected destination refused publication")
                #expect(!FileManager.default.fileExists(atPath: destination.path))
            }
        }
    }

    private func makeFixture(at url: URL) async throws {
        let videoURL = url.deletingPathExtension().appendingPathExtension("video.mov")
        let writer = try AVAssetWriter(outputURL: videoURL, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 180])
        let adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 180])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error! }
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<30 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(1)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault, 320, 180, kCVPixelFormatType_32ARGB, [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary, &buffer)
            let pixel = try #require(buffer)
            CVPixelBufferLockBaseAddress(pixel, [])
            let context = try #require(CGContext(data: CVPixelBufferGetBaseAddress(pixel), width: 320, height: 180, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixel), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue))
            context.setFillColor(CGColor(red: CGFloat(frame) / 30, green: 0.5, blue: 0.5, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 320, height: 180))
            CVPixelBufferUnlockBaseAddress(pixel, [])
            guard adapter.append(pixel, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)) else { throw writer.error! }
        }
        input.markAsFinished()
        await withCheckedContinuation { continuation in writer.finishWriting { continuation.resume() } }
        guard writer.status == .completed else { throw writer.error! }
        let audioURL = url.deletingPathExtension().appendingPathExtension("caf")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1))
        let audioBuffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48000))
        audioBuffer.frameLength = 48000
        for index in 0..<48000 { audioBuffer.floatChannelData![0][index] = Float(sin(Double(index) * 2 * .pi * 440 / 48000)) * 0.1 }
        do {
            let file = try AVAudioFile(forWriting: audioURL, settings: format.settings)
            try file.write(from: audioBuffer)
        }
        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: audioURL)
        let videoTrack = try #require(try await videoAsset.loadTracks(withMediaType: .video).first)
        let audioTrack = try #require(try await audioAsset.loadTracks(withMediaType: .audio).first)
        let range = CMTimeRange(start: .zero, duration: CMTime(value: 1, timescale: 1))
        let composedVideo = try #require(composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid))
        let composedAudio = try #require(composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid))
        try composedVideo.insertTimeRange(range, of: videoTrack, at: .zero)
        try composedAudio.insertTimeRange(range, of: audioTrack, at: .zero)
        let fixtureExport = try #require(AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality))
        fixtureExport.outputURL = url
        fixtureExport.outputFileType = .mov
        await withCheckedContinuation { continuation in fixtureExport.exportAsynchronously { continuation.resume() } }
        guard fixtureExport.status == .completed else { throw fixtureExport.error! }
    }
}
