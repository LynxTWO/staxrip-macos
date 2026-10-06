import Foundation
import Security
import CryptoKit
import Darwin
import Testing
@testable import StaxRipMac

/// A scoped loading discriminator using only owned copies and a selected native
/// test entry. It is not an app bootstrap, importer or release executable factory.
@Suite(.serialized)
@MainActor
struct HardenedSwiftHostTests {
    private static let hostID = "org.staxrip.generated.native-host"
    private static let moduleID = "org.staxrip.generated.native-tests"
    private static let selector = "HardenedSwiftHostTests/ownedHardenedSwiftHostLoadsNativeEntryOrReportsConcreteLoaderRefusal"
    private static func hash(_ url: URL) throws -> String { try HardenedReaderBundleFixture.hash(url) }
    private static func run(_ executable: String, _ arguments: [String]) async throws {
        let r = try await ToolRunner().run(executable: URL(fileURLWithPath: executable), arguments: arguments)
        try #require(r.status == 0 && !r.truncated)
    }
    private static func sign(_ url: URL, identifier: String) async throws {
        // Remove the copied host's existing get-task-allow entitlement before
        // signing. Never edit the installed host or original compiled module.
        try await run("/usr/bin/codesign", ["--remove-signature", url.path])
        try await run("/usr/bin/codesign", ["--force", "--sign", "-", "--options", "runtime", "--timestamp=none", "--identifier", identifier, url.path])
    }
    private static func inspect(_ url: URL, identifier: String, nested: Bool) throws -> String {
        var code: SecStaticCode?, information: CFDictionary?
        try #require(SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(), &code) == errSecSuccess)
        let value = try #require(code)
        let options = kSecCSStrictValidate | kSecCSCheckAllArchitectures | (nested ? kSecCSCheckNestedCode : 0)
        try #require(SecStaticCodeCheckValidity(value, SecCSFlags(rawValue: options), nil) == errSecSuccess)
        try #require(SecCodeCopySigningInformation(value, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess)
        let info = try #require(information as? [String: Any]), flags = try #require(info[kSecCodeInfoFlags as String] as? NSNumber)
        try #require(info[kSecCodeInfoIdentifier as String] as? String == identifier)
        try #require(flags.uint32Value & 0x10000 != 0 && flags.uint32Value & 0x0002 != 0)
        try #require(info[kSecCodeInfoEntitlementsDict as String] == nil && info[kSecCodeInfoEntitlements as String] == nil && info[kSecCodeInfoTeamIdentifier as String] == nil)
        let digest = try #require(info[kSecCodeInfoUnique as String] as? Data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    @MainActor
    private final class Host {
        let pid: pid_t
        let output: FileHandle
        private(set) var status: Int32?
        init(executable: URL, module: URL, environment: [String: String], log: URL) throws {
            output = try FileHandle(forWritingTo: log)
            var actions: posix_spawn_file_actions_t?, attributes: posix_spawnattr_t?
            try #require(posix_spawn_file_actions_init(&actions) == 0)
            defer { posix_spawn_file_actions_destroy(&actions) }
            try #require(posix_spawnattr_init(&attributes) == 0)
            defer { posix_spawnattr_destroy(&attributes) }
            try #require(posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETPGROUP)) == 0)
            try #require(posix_spawnattr_setpgroup(&attributes, 0) == 0)
            try #require(posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0) == 0)
            try #require(posix_spawn_file_actions_adddup2(&actions, output.fileDescriptor, STDOUT_FILENO) == 0)
            try #require(posix_spawn_file_actions_adddup2(&actions, output.fileDescriptor, STDERR_FILENO) == 0)
            let args = [executable.path, "--test-bundle-path", module.path, "--filter", Self.selector, "--testing-library", "swift-testing"]
            let argv = args.map { strdup($0) } + [nil], envp = environment.sorted { $0.key < $1.key }.map { strdup($0.key + "=" + $0.value) } + [nil]
            defer { for v in argv + envp { if let v { free(v) } } }
            var child: pid_t = 0
            let result = argv.withUnsafeBufferPointer { a in envp.withUnsafeBufferPointer { e in
                posix_spawn(&child, executable.path, &actions, &attributes, a.baseAddress!, e.baseAddress!)
            } }
            try #require(result == 0 && child > 0); pid = child
        }
        private static var selector: String { HardenedSwiftHostTests.selector }
        func reapIfExited() throws -> Bool {
            if status != nil { return true }
            var observed: Int32 = 0; let result = waitpid(pid, &observed, WNOHANG)
            if result < 0 && errno == EINTR { return false }
            try #require(result == 0 || result == pid)
            if result == pid { status = observed; return true }; return false
        }
        func stopUnreapedOwnedGroup() {
            guard status == nil else { return }
            // Only this sole owner may signal its still-unreaped exact PID/group.
            _ = Darwin.kill(-pid, SIGKILL); _ = Darwin.kill(pid, SIGKILL)
        }
        func joined() throws -> Int32 {
            let value = try #require(status); var again: Int32 = 0
            try #require(waitpid(pid, &again, WNOHANG) == -1 && errno == ECHILD)
            try output.close(); return value
        }
        deinit { try? output.close() }
    }
    private final class Children: @unchecked Sendable {
        private let lock = NSLock(); private var live: [pid_t] = [], joined: [pid_t] = []
        func launch(_ p: pid_t) { lock.withLock { live.append(p) } }
        func join(_ p: pid_t) { lock.withLock { joined.append(p) } }
        func requireJoined() throws {
            let values = lock.withLock { (live, joined) }; try #require(values.0.count == 6 && values.0 == values.1)
            for p in values.0 { var s: Int32 = 0; try #require(waitpid(p, &s, WNOHANG) == -1 && errno == ECHILD) }
        }
    }
    private func nativeEntry(root: URL, writerHash: String, readerHash: String, sourceHash: String) async throws {
        let source = root.appendingPathComponent("source.mkv"), bundle = root.appendingPathComponent("owned relocated folder/GeneratedReaderHost.app")
        try #require(Self.hash(source) == sourceHash)
        let entry = Darwin.open(root.appendingPathComponent("entered").path, O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC, 0o600)
        try #require(entry >= 0); Darwin.close(entry)
        let writer = try CompanionWriterProcess.Tool.development(bundle.appendingPathComponent("Contents/Helpers/staxrip-dolby-companion-writer"), expectedSHA256: writerHash)
        let reader = try CompanionMetadataProcess.Tool.development(bundle.appendingPathComponent("Contents/Helpers/staxrip-dolby-metadata-audit"), expectedSHA256: readerHash)
        let children = Children(), parent = root.appendingPathComponent("destination"), prior = try Data(contentsOf: parent.appendingPathComponent("prior"))
        let reviewedData = try Data(contentsOf: source)
        let reviewedSource = SourceFingerprint(sha256: SHA256.hash(data: reviewedData).map { String(format: "%02x", $0) }.joined(), byteCount: Int64(reviewedData.count))
        for mode in [OriginalCompanionTransaction.Retention.metadataOnly, .entireContainer] {
            let result = try await CompanionWriterProcess.$testBoundary.withValue(.init(launched: { children.launch($0) }, settled: { children.join($0) })) {
                try await CompanionMetadataProcess.$testBoundary.withValue(.init(launched: { children.launch($0) }, settled: { children.join($0) })) {
                    try await CompanionArchiveOperation.execute(source: source, reviewedSource: reviewedSource, in: parent, destinationName: mode == .metadataOnly ? "metadata" : "entire", retention: mode, writer: writer, reader: reader)
                }
            }
            let review = try await CompanionMetadataProcess.$testBoundary.withValue(.init(launched: { children.launch($0) }, settled: { children.join($0) })) {
                try await CompanionArchiveOperation.reviewCandidate(source: source, candidate: result.directory, retention: mode, reader: reader)
            }
            try #require(review.originalMetadataSemanticsVerified && review.fullContainerMatchesOriginalBytes == (mode == .entireContainer))
        }
        try children.requireJoined()
        try #require(Self.hash(source) == sourceHash)
        try #require(Data(contentsOf: parent.appendingPathComponent("prior")) == prior)
        let frame: [String: Any] = ["version": 1, "pid": getpid(), "nativeBothModes": true, "helperDirectChildrenJoined": 6, "sourceSHA256": sourceHash]
        let bytes = try JSONSerialization.data(withJSONObject: frame, options: [.sortedKeys]); try #require(bytes.count <= 4096)
        let fd = Darwin.open(root.appendingPathComponent("complete.json").path, O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC, 0o600)
        try #require(fd >= 0); let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        try file.write(contentsOf: bytes); try file.close()
        Darwin._exit(0)
    }
    // The installed SwiftPM helper traps on the known loader refusal, producing
    // visible macOS crash reports. Keep this discriminator explicit opt-in;
    // routine regression must not repeatedly crash a copied helper on the desktop.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["STAXRIP_TEST_HARDENED_MODULE_LOADING"] == "1"),
          arguments: ["StaxRipMacTests", "StaxRipMacPackageTests"])
    func ownedHardenedSwiftHostLoadsNativeEntryOrReportsConcreteLoaderRefusal(copiedModuleName: String) async throws {
        let env = ProcessInfo.processInfo.environment
        if let root = env["STAXRIP_TEST_SWIFT_HOST_ROOT"] {
            try await nativeEntry(root: URL(fileURLWithPath: root), writerHash: try #require(env["STAXRIP_TEST_SWIFT_HOST_WRITER_SHA"]), readerHash: try #require(env["STAXRIP_TEST_SWIFT_HOST_READER_SHA"]), sourceHash: try #require(env["STAXRIP_TEST_SWIFT_HOST_SOURCE_SHA"]))
            return
        }
        let originalHost = URL(fileURLWithPath: CommandLine.arguments[0])
        try #require(originalHost.lastPathComponent == "swiftpm-testing-helper")
        let index = try #require(CommandLine.arguments.firstIndex(of: "--test-bundle-path")); try #require(index + 1 < CommandLine.arguments.count)
        let originalModule = URL(fileURLWithPath: CommandLine.arguments[index + 1])
        // Installed SwiftPM versions use either fixed package test-module name.
        // Never admit an arbitrary basename or media-selected executable.
        try #require(["StaxRipMacTests", "StaxRipMacPackageTests"].contains(originalModule.lastPathComponent))
        let hostBefore = try Self.hash(originalHost), moduleBefore = try Self.hash(originalModule)
        let b = try await HardenedReaderBundleFixture.make()
        var settled = false
        defer { if settled { b.cleanup() } else { print("GENERATED_SWIFT_HOST_REVIEW " + b.original.root.path) } }
        let contents = b.bundle.appendingPathComponent("Contents"), main = contents.appendingPathComponent("MacOS/SwiftNativeHost")
        try FileManager.default.removeItem(at: b.main)
        try FileManager.default.copyItem(at: originalHost, to: main)
        let plugins = contents.appendingPathComponent("PlugIns")
        try FileManager.default.createDirectory(at: plugins, withIntermediateDirectories: false)
        let module = plugins.appendingPathComponent("GeneratedNativeTests.xctest")
        let moduleRoot = originalModule.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        try #require(moduleRoot.pathExtension == "xctest")
        try FileManager.default.copyItem(at: moduleRoot, to: module)
        let originalCopy = module.appendingPathComponent("Contents/MacOS/" + originalModule.lastPathComponent)
        let moduleBinary = module.appendingPathComponent("Contents/MacOS/" + copiedModuleName)
        // The SDK dependency path is explicit installed test infrastructure, not a
        // DYLD override, copied platform library or distribution portability proof.
        let developer = try #require(originalHost.path.components(separatedBy: "/Toolchains/").first)
        try #require(developer.hasSuffix("/Contents/Developer"))
        let sdk = developer + "/Platforms/MacOSX.platform/Developer/Library/Frameworks"
        try await Self.run("/usr/bin/codesign", ["--remove-signature", module.path])
        if originalCopy != moduleBinary { try FileManager.default.moveItem(at: originalCopy, to: moduleBinary) }
        let moduleInfoURL = module.appendingPathComponent("Contents/Info.plist")
        var moduleInfo: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: moduleInfoURL.path) {
            moduleInfo = try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: moduleInfoURL), format: nil) as? [String: Any])
        }
        moduleInfo["CFBundleExecutable"] = copiedModuleName
        moduleInfo["CFBundleIdentifier"] = Self.moduleID
        moduleInfo["CFBundlePackageType"] = "BNDL"
        try PropertyListSerialization.data(fromPropertyList: moduleInfo, format: .xml, options: 0).write(to: moduleInfoURL)
        try await Self.run("/usr/bin/install_name_tool", ["-add_rpath", sdk, moduleBinary.path])
        let info: [String: Any] = ["CFBundleIdentifier": Self.hostID, "CFBundleExecutable": "SwiftNativeHost", "CFBundlePackageType": "APPL", "CFBundleVersion": "1", "LSMinimumSystemVersion": "14.0"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        // Module has already had its original signature removed for rpath edit.
        try await Self.run("/usr/bin/codesign", ["--force", "--sign", "-", "--options", "runtime", "--timestamp=none", "--identifier", Self.moduleID, module.path])
        try await Self.sign(main, identifier: Self.hostID)
        try await Self.run("/usr/bin/codesign", ["--force", "--sign", "-", "--options", "runtime", "--timestamp=none", "--identifier", Self.hostID, b.bundle.path])
        let outer = try Self.inspect(b.bundle, identifier: Self.hostID, nested: true), moduleHash = try Self.inspect(module, identifier: Self.moduleID, nested: false)
        _ = try HelperSignatureAdmission.verify(bundle: b.bundle, role: .reader, policy: b.readerPolicy)
        _ = try HelperSignatureAdmission.verify(bundle: b.bundle, role: .writer, policy: b.writerPolicy)
        let source = b.original.root.appendingPathComponent("source.mkv"), parent = b.original.root.appendingPathComponent("destination")
        try FileManager.default.copyItem(at: b.original.source, to: source)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let prior = Data("Generated prior output".utf8); try prior.write(to: parent.appendingPathComponent("prior"), options: .withoutOverwriting)
        let sourceHash = try Self.hash(source), log = b.original.root.appendingPathComponent("host.log")
        try #require(FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600]))
        var rootID = stat(), destinationID = stat(); try #require(lstat(b.original.root.path, &rootID) == 0 && lstat(parent.path, &destinationID) == 0)
        var environment = env.filter { !$0.key.hasPrefix("DYLD_") }
        environment["STAXRIP_TEST_SWIFT_HOST_ROOT"] = b.original.root.path
        environment["STAXRIP_TEST_SWIFT_HOST_WRITER_SHA"] = try Self.hash(b.helper(.writer))
        environment["STAXRIP_TEST_SWIFT_HOST_READER_SHA"] = try Self.hash(b.helper(.reader))
        environment["STAXRIP_TEST_SWIFT_HOST_SOURCE_SHA"] = sourceHash
        let host = try Host(executable: main, module: moduleBinary, environment: environment, log: log)
        let deadline = ContinuousClock.now.advanced(by: .seconds(20))
        var exceeded = false
        while try !host.reapIfExited(), ContinuousClock.now < deadline {
            var size = stat(); try #require(lstat(log.path, &size) == 0)
            if size.st_size > 1 << 20 { exceeded = true; break }
            try await Task.sleep(for: .milliseconds(10))
        }
        guard try host.reapIfExited(), !exceeded else {
            host.stopUnreapedOwnedGroup()
            let stopLimit = ContinuousClock.now.advanced(by: .seconds(3))
            while try !host.reapIfExited(), ContinuousClock.now < stopLimit { try await Task.sleep(for: .milliseconds(10)) }
            if try host.reapIfExited() { _ = try host.joined() }
            throw NativeExportError.invalid("Generated host deadline/log refusal; retain uncertain fixture")
        }
        let status = try host.joined(), textBytes = try Data(contentsOf: log); try #require(textBytes.count <= 1 << 20)
        let text = String(decoding: textBytes, as: UTF8.self)
        let entered = b.original.root.appendingPathComponent("entered"), complete = b.original.root.appendingPathComponent("complete.json")
        var nowRoot = stat(), nowParent = stat(); try #require(lstat(b.original.root.path, &nowRoot) == 0 && lstat(parent.path, &nowParent) == 0)
        try #require(OriginalCompanionTransaction.FileID(nowRoot) == .init(rootID) && OriginalCompanionTransaction.FileID(nowParent) == .init(destinationID))
        try #require(Self.hash(source) == sourceHash)
        try #require(Data(contentsOf: parent.appendingPathComponent("prior")) == prior)
        try #require(Self.inspect(b.bundle, identifier: Self.hostID, nested: true) == outer)
        try #require(Self.inspect(module, identifier: Self.moduleID, nested: false) == moduleHash)
        try #require(Self.hash(originalHost) == hostBefore)
        try #require(Self.hash(originalModule) == moduleBefore)
        _ = try HelperSignatureAdmission.verify(bundle: b.bundle, role: .reader, policy: b.readerPolicy)
        _ = try HelperSignatureAdmission.verify(bundle: b.bundle, role: .writer, policy: b.writerPolicy)
        if status & 0x7f == 0 && (status >> 8) & 0xff == 0 {
            let bytes = try Data(contentsOf: complete); try #require(bytes.count <= 4096)
            let frame = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            try #require(Set(frame.keys) == ["version", "pid", "nativeBothModes", "helperDirectChildrenJoined", "sourceSHA256"])
            try #require(frame["version"] as? Int == 1 && frame["pid"] as? Int == Int(host.pid) && frame["nativeBothModes"] as? Bool == true && frame["helperDirectChildrenJoined"] as? Int == 6 && frame["sourceSHA256"] as? String == sourceHash)
            for mode in [OriginalCompanionTransaction.Retention.metadataOnly, .entireContainer] {
                let reader = try CompanionMetadataProcess.Tool.development(b.helper(.reader), expectedSHA256: Self.hash(b.helper(.reader)))
                let review = try await CompanionDiskCheck.reviewOriginalCandidate(source: source, candidate: parent.appendingPathComponent(mode == .metadataOnly ? "metadata" : "entire"), retention: mode, tool: reader)
                try #require(review.originalMetadataSemanticsVerified)
            }
            print("GENERATED_SWIFT_HOST_NATIVE_LOAD_PASSED")
        } else {
            let validation = text.contains("not valid for use in process") && text.contains("mapped file") && (text.contains("different Team IDs") || text.contains("no Team ID"))
            let missingSDK = text.contains("Library not loaded:") && (text.contains("XCTest.framework") || text.contains("Testing.framework")) && text.contains("Reason:")
            try #require(validation || missingSDK, "Unclassified hardened host refusal; retain fixture")
            try #require(!FileManager.default.fileExists(atPath: entered.path) && !FileManager.default.fileExists(atPath: complete.path))
            try #require(FileManager.default.contentsOfDirectory(atPath: parent.path) == ["prior"])
            // Fixed test-only diagnostic record, never producer/recovery authority.
            let finding: [String: Any] = ["version": 1, "hostPID": host.pid, "waitStatus": status,
                "diagnostic": validation ? "library-team-refusal" : "missing-sdk-dependency", "directHostJoined": true,
                "nativeEntryStarted": false, "sourceSHA256": sourceHash, "outerCDHash": outer, "moduleCDHash": moduleHash]
            let fd = Darwin.open(b.original.root.appendingPathComponent("loading-refusal.json").path, O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC, 0o600)
            try #require(fd >= 0); let record = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            try record.write(contentsOf: JSONSerialization.data(withJSONObject: finding, options: [.sortedKeys])); try record.close()
            // Keep the exact signed copied artifacts and diagnostic for review.
            print("GENERATED_SWIFT_HOST_LOADING_REFUSED " + b.original.root.path)
            // Classified refusal remains retained, although the host itself joined.
            return
        }
        settled = true
    }
}
