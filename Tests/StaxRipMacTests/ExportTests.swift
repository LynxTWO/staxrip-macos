import Testing
import Foundation
import AVFoundation
import CoreVideo
import CoreGraphics
@testable import StaxRipMac

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

    @Test func cancellationOfActiveSessionCleansItsStagingDirectory() async throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("source.mov")
        try await makeFixture(at: source)
        let target = dir.appendingPathComponent("cancelled.mp4")
        let service = NativeExportService()
        var requested = false
        do {
            try await service.export(source: source, destination: target, preset: .h264HD) { _ in
                if !requested { requested = true; service.cancel() }
            }
            Issue.record("Active cancellation should prevent publication")
        } catch is CancellationError { }
        #expect(requested)
        #expect(!FileManager.default.fileExists(atPath: target.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).allSatisfy { !$0.hasPrefix(".staxrip-export-") })
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
