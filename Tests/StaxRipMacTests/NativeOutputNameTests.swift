import Foundation
import Testing
@testable import StaxRipMac

struct NativeOutputNameTests {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("native-name-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }
    @Test func requiredExtensionAndInvalidInputsAreExplicit() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        for name in ["new.mp4", "new.MP4", "new name 日本語.mp4"] {
            let url = root.appendingPathComponent(name)
            #expect(try NativeOutputName.candidate(url) == url)
            try NativeOutputName.validate(url)
        }
        #expect(try NativeOutputName.candidate(root.appendingPathComponent("new")) == root.appendingPathComponent("new.mp4"))
        for invalid in [nil, URL(string: "https://example.invalid/new.mp4"), URL(fileURLWithPath: root.path, isDirectory: true),
                        root.appendingPathComponent("new.mov"), root.appendingPathComponent("bad\0.mp4")] {
            #expect(throws: (any Error).self) { try NativeOutputName.validate(invalid) }
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test func existingFilesDirectoriesAndDanglingLinksStayUntouched() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("taken.mp4"), folder = root.appendingPathComponent("folder.mp4")
        let link = root.appendingPathComponent("link.mp4"), missing = root.appendingPathComponent("missing")
        try Data("Prior output".utf8).write(to: file)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: missing)
        for existing in [file, file.deletingPathExtension(), folder, link, file.appendingPathComponent("child.mp4")] {
            #expect(throws: (any Error).self) { try NativeOutputName.validate(existing) }
        }
        // A name can become occupied after a successful check. Final publication
        // must still refuse; no destructive reservation or rename is performed.
        let fresh = root.appendingPathComponent("fresh.mp4"), staged = root.appendingPathComponent("staged.mp4")
        try NativeOutputName.validate(fresh)
        try Data("Racing output".utf8).write(to: fresh)
        try Data("New encode".utf8).write(to: staged)
        #expect(throws: (any Error).self) { try ExportPublication.publish(staged: staged, destination: fresh) }
        #expect(try Data(contentsOf: fresh) == Data("Racing output".utf8))
        #expect(try Data(contentsOf: staged) == Data("New encode".utf8))
        #expect(try Data(contentsOf: file) == Data("Prior output".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == missing.path)
    }
}
