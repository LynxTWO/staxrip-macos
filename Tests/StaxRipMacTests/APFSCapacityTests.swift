import Foundation
import Darwin
import Testing
@testable import StaxRipMac

@MainActor
struct APFSCapacityTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["STAXRIP_APFS_TEST_MOUNT"] != nil && FFmpegTools.discover() != nil), .timeLimit(.minutes(2)))
    func fullOwnedAPFSFailsWithoutPublicationAndCanRetry() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["STAXRIP_APFS_TEST_MOUNT"])
        let mount = URL(fileURLWithPath: path).standardizedFileURL
        let marker = mount.appendingPathComponent(".staxrip-apfs-fixture")
        let token = try #require(ProcessInfo.processInfo.environment["STAXRIP_APFS_TEST_TOKEN"])
        try #require(UUID(uuidString: token) != nil)
        try #require(try String(contentsOf: marker, encoding: .utf8) == "StaxRip disposable APFS fixture v1 " + token + "\n")
        var filesystem = statfs()
        try #require(statfs(mount.path, &filesystem) == 0)
        let filesystemName = withUnsafePointer(to: &filesystem.f_fstypename) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) { String(cString: $0) }
        }
        try #require(filesystemName == "apfs", "APFS qualification requires an APFS mount")
        var mounted = stat(), parent = stat()
        try #require(stat(mount.path, &mounted) == 0)
        try #require(stat(mount.deletingLastPathComponent().path, &parent) == 0)
        try #require(mounted.st_dev != parent.st_dev, "Must be a dedicated mounted filesystem")
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: mount.path)
        let capacity = try #require((attributes[.systemSize] as? NSNumber)?.int64Value)
        let available = try #require((attributes[.systemFreeSize] as? NSNumber)?.int64Value)
        try #require(capacity > 0 && capacity <= 64 * 1024 * 1024 && available > 8 * 1024 * 1024)
        let owned = mount.appendingPathComponent("owned-" + UUID().uuidString)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("apfs-capacity-source-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: owned, withIntermediateDirectories: false)
        var activeBatch: BatchController?
        defer {
            if activeBatch?.running == true { activeBatch?.cancel() }
            else { try? FileManager.default.removeItem(at: owned) }
        }
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: false)
        defer { if activeBatch?.running != true { try? FileManager.default.removeItem(at: scratch) } }
        let tools = try #require(FFmpegTools.discover()), source = scratch.appendingPathComponent("source.mkv")
        let fixture = try await ToolRunner().run(executable: tools.ffmpeg, arguments: ["-v", "error", "-n", "-f", "lavfi", "-i", "testsrc2=size=320x192:rate=24:duration=2", "-c:v", "libx264", "-preset", "ultrafast", source.path])
        try #require(fixture.status == 0)
        let sourceBytes = try Data(contentsOf: source), sentinel = owned.appendingPathComponent("prior.mkv")
        try Data("prior output".utf8).write(to: sentinel)
        let filler = owned.appendingPathComponent("filler")
        let fd = Darwin.open(filler.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        try #require(fd >= 0)
        var written = 0, exhausted = false
        let block = [UInt8](repeating: 0x5a, count: 65536)
        while written + block.count <= 64 * 1024 * 1024 {
            let count = block.withUnsafeBytes { Darwin.write(fd, $0.baseAddress!, $0.count) }
            if count < 0 { exhausted = errno == ENOSPC; break }
            if count == 0 { break }
            written += count
        }
        let syncResult = fsync(fd), syncError = errno
        close(fd)
        try #require(exhausted || (syncResult < 0 && syncError == ENOSPC), "Fixture must actually reach ENOSPC")
        print("APFS_CAPACITY filesystem=\(filesystemName) device=\(mounted.st_dev) fixture_bytes=\(capacity) filler_bytes=\(written) actual_ENOSPC=true")
        // Exercise the publication remedy directly as well: the subsequent real
        // encode may exhaust capacity earlier while closing its own output.
        var publishedLinks: [URL] = []
        var publicationExhausted = false
        for index in 0..<1024 {
            let destination = owned.appendingPathComponent("capacity-link-\(index)")
            do {
                try ExportPublication.publish(staged: sentinel, destination: destination)
                publishedLinks.append(destination)
            } catch {
                let detail = error.localizedDescription
                #expect(detail.contains("Could not publish the output: No space left on device"))
                #expect(detail.contains("Free space on the destination"))
                #expect(!detail.contains("supports hard links"))
                #expect(!FileManager.default.fileExists(atPath: destination.path))
                publicationExhausted = detail.contains("No space left on device")
                print("APFS_CAPACITY direct_publication=\(detail) successful_links=\(publishedLinks.count)")
                break
            }
        }
        try #require(publicationExhausted, "Bounded APFS link fixture must exercise actual publication ENOSPC")
        for link in publishedLinks { try FileManager.default.removeItem(at: link) }
        var c = EncodeConfiguration(); c.codec = "H.264"; c.encoder = "x264"; c.container = "MKV"; c.audio = "No audio"; c.subtitleMode = "Remove all subtitles"; c.picture.deinterlace = "Off"
        let first = QueueJob(id: UUID(), source: source.path, isDemo: false, destination: owned.appendingPathComponent("result.mkv").path, configuration: c, created: Date())
        let next = QueueJob(id: UUID(), source: source.path, isDemo: false, destination: owned.appendingPathComponent("next.mkv").path, configuration: c, created: Date())
        let batch = BatchController(journalURL: scratch.appendingPathComponent("journal.json"))
        activeBatch = batch
        batch.tools = tools; batch.encoders = ["libx264"]; batch.start([first, next]); try await finish(batch)
        let status = try #require(batch.statuses[first.id])
        print("APFS_CAPACITY phase=\(status.phase) detail=\(status.detail)")
        #expect(status.phase == "Failed"); #expect(status.destination == nil)
        #expect(status.detail.contains("No space left on device"))
        // APFS allocation can exhaust while closing the encoded file or while
        // adding the publication link. Both were observed on the same size fixture.
        if status.detail.contains("Could not publish the output") {
            #expect(status.detail.contains("Free space on the destination"))
        } else {
            #expect(status.detail.contains("FFmpeg exited"))
        }
        #expect(!status.detail.contains("supports hard links"))
        #expect(batch.statuses[next.id]?.phase == "Pending")
        #expect(!FileManager.default.fileExists(atPath: first.destination)); #expect(!FileManager.default.fileExists(atPath: next.destination))
        #expect(try Data(contentsOf: source) == sourceBytes)
        #expect(try Data(contentsOf: sentinel) == Data("prior output".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: owned.path).allSatisfy { !$0.hasPrefix(".staxrip-batch-") })
        try FileManager.default.removeItem(at: filler)
        batch.start([first]); try await finish(batch)
        #expect(batch.statuses[first.id]?.phase == "Completed")
        #expect(try await MediaProbe.read(URL(fileURLWithPath: first.destination), tools: tools).video?.codec_name == "h264")
        #expect(try Data(contentsOf: source) == sourceBytes)
        #expect(try Data(contentsOf: sentinel) == Data("prior output".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: owned.path).allSatisfy { !$0.hasPrefix(".staxrip-batch-") })
    }
    private func finish(_ batch: BatchController) async throws {
        do {
            while batch.running { try await Task.sleep(for: .milliseconds(10)) }
        } catch {
            batch.cancel()
            throw error
        }
    }
}
