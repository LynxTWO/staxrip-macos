import Foundation
import Security
import CryptoKit
import Darwin
import Testing
@testable import StaxRipMac

/// Actual static native qualification only; no runtime adapter or product entry.
@Suite(.serialized)
@MainActor
struct StaticHardenedNativeHostTests {
    static let identifier = "org.staxrip.generated.static-native-host"
    #if arch(arm64)
    private static let target = "arm64-apple-macos14.0"
    private static let nativeHeader: [UInt8] = [0xcf, 0xfa, 0xed, 0xfe, 0x0c, 0, 0, 1]
    #elseif arch(x86_64)
    private static let target = "x86_64-apple-macos14.0"
    private static let nativeHeader: [UInt8] = [0xcf, 0xfa, 0xed, 0xfe, 0x07, 0, 0, 1]
    #else
    #error("Generated native host requires a supported native Mac architecture")
    #endif
    private static var repo: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }
    private static func hash(_ url: URL) throws -> String { try HardenedReaderBundleFixture.hash(url) }
    private static func sign(_ url: URL) async throws {
        let result = try await ToolRunner().run(executable: URL(fileURLWithPath: "/usr/bin/codesign"), arguments: ["--force", "--sign", "-", "--options", "runtime", "--timestamp=none", "--identifier", identifier, url.path])
        try #require(result.status == 0 && !result.truncated)
    }
    private static func signature(_ url: URL, identifier: String, nested: Bool = true) throws -> String {
        var code: SecStaticCode?, information: CFDictionary?
        try #require(SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(), &code) == errSecSuccess)
        let value = try #require(code)
        try #require(SecStaticCodeCheckValidity(value, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures | (nested ? kSecCSCheckNestedCode : 0)), nil) == errSecSuccess)
        try #require(SecCodeCopySigningInformation(value, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess)
        let info = try #require(information as? [String: Any]), flags = try #require(info[kSecCodeInfoFlags as String] as? NSNumber)
        try #require(info[kSecCodeInfoIdentifier as String] as? String == identifier && flags.uint32Value & 0x10000 != 0 && flags.uint32Value & 2 != 0)
        try #require(info[kSecCodeInfoEntitlementsDict as String] == nil && info[kSecCodeInfoEntitlements as String] == nil && info[kSecCodeInfoTeamIdentifier as String] == nil)
        return try #require(info[kSecCodeInfoUnique as String] as? Data).map { String(format: "%02x", $0) }.joined()
    }
    private static func resources(_ root: URL) throws -> String {
        let enumerator = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]))
        var values: [String] = []
        for case let url as URL in enumerator where try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
            values.append(String(url.path.dropFirst(root.path.count + 1)) + ":" + (try hash(url)))
        }
        return DolbyInspection.hex(SHA256.hash(data: Data(values.sorted().joined(separator: "\n").utf8)))
    }
    @MainActor private final class Owned {
        let pid: pid_t
        private let output: FileHandle
        private var status: Int32?
        init(_ executable: URL, arguments: [String], log: URL) throws {
            try #require(FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600]))
            output = try FileHandle(forWritingTo: log)
            var actions: posix_spawn_file_actions_t?, attributes: posix_spawnattr_t?
            try #require(posix_spawn_file_actions_init(&actions) == 0); defer { posix_spawn_file_actions_destroy(&actions) }
            try #require(posix_spawnattr_init(&attributes) == 0); defer { posix_spawnattr_destroy(&attributes) }
            try #require(posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETPGROUP)) == 0 && posix_spawnattr_setpgroup(&attributes, 0) == 0)
            try #require(posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0) == 0)
            try #require(posix_spawn_file_actions_adddup2(&actions, output.fileDescriptor, STDOUT_FILENO) == 0 && posix_spawn_file_actions_adddup2(&actions, output.fileDescriptor, STDERR_FILENO) == 0)
            let argv = ([executable.path] + arguments).map { strdup($0) } + [nil]
            let env = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("DYLD_") && !$0.key.hasPrefix("STAXRIP_TEST_") }
            let envp = env.sorted { $0.key < $1.key }.map { strdup($0.key + "=" + $0.value) } + [nil]
            defer { for value in argv + envp { if let value { free(value) } } }
            var child: pid_t = 0
            let result = argv.withUnsafeBufferPointer { a in envp.withUnsafeBufferPointer { e in posix_spawn(&child, executable.path, &actions, &attributes, a.baseAddress!, e.baseAddress!) } }
            try #require(result == 0 && child > 0); pid = child
        }
        func reaped() throws -> Bool {
            if status != nil { return true }
            var value: Int32 = 0; let result = waitpid(pid, &value, WNOHANG)
            if result < 0 && errno == EINTR { return false }
            try #require(result == 0 || result == pid)
            if result == pid { status = value; return true }; return false
        }
        func awaitExit(log: URL, seconds: Double, maximum: Int64) async throws -> Int32 {
            let limit = ContinuousClock.now.advanced(by: .seconds(seconds))
            while try !reaped(), ContinuousClock.now < limit {
                var size = stat(); try #require(lstat(log.path, &size) == 0)
                if size.st_size > maximum { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            guard try reaped() else {
                // Sole owner signals only its still-unreaped exact PID/group.
                // Uncertain nested ownership always retains the whole fixture.
                _ = Darwin.kill(-pid, SIGKILL); _ = Darwin.kill(pid, SIGKILL)
                let stop = ContinuousClock.now.advanced(by: .seconds(3))
                while try !reaped(), ContinuousClock.now < stop { try await Task.sleep(for: .milliseconds(10)) }
                if try reaped() { try output.close() }
                throw NativeExportError.invalid("Owned generated compiler/host bound exceeded; retain fixture")
            }
            var again: Int32 = 0
            try #require(waitpid(pid, &again, WNOHANG) == -1 && errno == ECHILD)
            try output.close()
            try #require((try FileManager.default.attributesOfItem(atPath: log.path)[.size] as? NSNumber)?.int64Value ?? Int64.max <= maximum)
            return try #require(status)
        }
        deinit { try? output.close() }
    }
    private static func cancellationSource(_ original: Data) throws -> Data {
        let view = CompanionDiskCheck.ReadView(sourceBytes: Int64(original.count), source: { o, n in original.subdata(in: Int(o)..<(Int(o) + n)) }, component: { _ in Data() }, checkpoint: {})
        let walk = CompanionOriginalTrackCheck.Walker(view), header = try walk.element(0, end: view.sourceBytes), segment = try walk.element(header.end, end: view.sourceBytes)
        var prefix = Data(), clusters = Data(), offset = segment.payload
        while offset < segment.end {
            let element = try walk.element(offset, end: segment.end), bytes = original.subdata(in: Int(offset)..<Int(element.end))
            if element.id == 0x1f43b675 { clusters.append(bytes) } else { prefix.append(bytes) }; offset = element.end
        }
        try #require(!clusters.isEmpty)
        var generated = original.prefix(Int(header.end)) + Data([0x18, 0x53, 0x80, 0x67, 0xff]) + prefix
        for _ in 0..<2000 { generated.append(clusters) }
        return generated
    }
    @Test func staticallyLinkedHardenedHostRunsBothNativeModesAndSettlesActualReaderCancellation() async throws {
        let bundle = try await HardenedReaderBundleFixture.make(targetName: "static-hardened-native-fixtures")
        var settled = false
        defer { if settled { bundle.cleanup() } else { print("GENERATED_STATIC_NATIVE_REVIEW " + bundle.original.root.path) } }
        let root = bundle.original.root, main = bundle.bundle.appendingPathComponent("Contents/MacOS/StaticNativeHost")
        try FileManager.default.removeItem(at: bundle.main)
        let sources = try FileManager.default.contentsOfDirectory(at: Self.repo.appendingPathComponent("Sources/StaxRipMac"), includingPropertiesForKeys: nil).filter { $0.pathExtension == "swift" && $0.lastPathComponent != "StaxRipMacApp.swift" }.sorted { $0.path < $1.path }
        // D124 adds two real non-entry product files to the prior 90-source closure.
        try #require(sources.count == 92)
        try #require(Set(sources.map(\.lastPathComponent)).isSuperset(of: ["DolbyDecoderProcess.swift", "DolbyDecoderStream.swift"]))
        let entry = Self.repo.appendingPathComponent("scripts/fixtures/static-native-companion-host.swift")
        let fingerprints = try sources.map { try Self.hash($0) }, entryHash = try Self.hash(entry)
        let compiler = try await ToolRunner().run(executable: URL(fileURLWithPath: "/usr/bin/xcrun"), arguments: ["--find", "swiftc"])
        try #require(compiler.status == 0 && compiler.stdout.count < 4096)
        let path = URL(fileURLWithPath: String(decoding: compiler.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        let compilerLog = root.appendingPathComponent("compiler.log")
        let compile = try Owned(path, arguments: ["-parse-as-library", "-swift-version", "5", "-D", "DEBUG", "-Onone", "-whole-module-optimization", "-target", Self.target, "-module-name", "GeneratedNativeQualification", "-o", main.path] + sources.map(\.path) + [entry.path], log: compilerLog)
        let compilation = try await compile.awaitExit(log: compilerLog, seconds: 120, maximum: 4 << 20)
        try #require(compilation == 0)
        try #require(sources.map { try Self.hash($0) } == fingerprints)
        try #require(Self.hash(entry) == entryHash)
        let info: [String: Any] = ["CFBundleExecutable": "StaticNativeHost", "CFBundleIdentifier": Self.identifier, "CFBundlePackageType": "APPL", "CFBundleVersion": "1", "LSMinimumSystemVersion": "14.0"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: bundle.bundle.appendingPathComponent("Contents/Info.plist"))
        try await Self.sign(main); try await Self.sign(bundle.bundle)
        let outer = try Self.signature(bundle.bundle, identifier: Self.identifier), mainHash = try Self.hash(main)
        // Native thin executable, not the SwiftPM test host or a dlopen
        // module. All dynamic dependencies must remain installed system code.
        let header = try Data(contentsOf: main).prefix(16)
        try #require(Array(header.prefix(8)) == Self.nativeHeader)
        try #require(Array(header.suffix(4)) == [2, 0, 0, 0])
        let linkage = try await ToolRunner().run(executable: URL(fileURLWithPath: "/usr/bin/otool"), arguments: ["-L", main.path])
        try #require(linkage.status == 0 && !linkage.truncated)
        let libraries = String(decoding: linkage.stdout, as: UTF8.self).split(separator: "\n").dropFirst().map { $0.trimmingCharacters(in: .whitespaces).components(separatedBy: " (compatibility")[0] }
        try #require(!libraries.isEmpty && libraries.allSatisfy { ($0.hasPrefix("/System/Library/") || $0.hasPrefix("/usr/lib/")) && !$0.contains("XCTest") && !$0.contains("Testing.framework") })
        let writer = try HelperSignatureAdmission.verify(bundle: bundle.bundle, role: .writer, policy: bundle.writerPolicy)
        let reader = try HelperSignatureAdmission.verify(bundle: bundle.bundle, role: .reader, policy: bundle.readerPolicy)
        let noticeHash = try Self.resources(bundle.bundle.appendingPathComponent("Contents/Resources"))
        let source = root.appendingPathComponent("source.mkv"), cancellation = root.appendingPathComponent("cancellation-source.mkv"), parent = root.appendingPathComponent("destination")
        let sourceBytes = try Data(contentsOf: bundle.original.source), prior = Data("Generated prior output".utf8)
        try sourceBytes.write(to: source, options: .withoutOverwriting)
        try Self.cancellationSource(sourceBytes).write(to: cancellation, options: .withoutOverwriting)
        let sourceHash = try Self.hash(source), cancelHash = try Self.hash(cancellation)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        try prior.write(to: parent.appendingPathComponent("prior"), options: .withoutOverwriting)
        var rootID = stat(), parentID = stat(); try #require(lstat(root.path, &rootID) == 0 && lstat(parent.path, &parentID) == 0)
        let hostLog = root.appendingPathComponent("host.log")
        let host = try Owned(main, arguments: ["generated-only", root.path, sourceHash, outer, mainHash, writer.cdHash, reader.cdHash, noticeHash], log: hostLog)
        let ready = root.appendingPathComponent("cancel-ready.json"), limit = ContinuousClock.now.advanced(by: .seconds(20))
        while !FileManager.default.fileExists(atPath: ready.path), try !host.reaped(), ContinuousClock.now < limit { try await Task.sleep(for: .milliseconds(10)) }
        if FileManager.default.fileExists(atPath: ready.path) {
            let bytes = try Data(contentsOf: ready); try #require(bytes.count < 4096)
            let frame = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            try #require(Set(frame.keys) == ["version", "realPacketObserved", "readerPID"] && frame["version"] as? Int == 1 && frame["realPacketObserved"] as? Bool == true)
            let pid = try #require(frame["readerPID"] as? Int); try #require(pid > 0)
            let ps = try await ToolRunner().run(executable: URL(fileURLWithPath: "/bin/ps"), arguments: ["-p", String(pid), "-o", "stat="])
            try #require(ps.status == 0 && !String(decoding: ps.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("Z"))
            try Data().write(to: root.appendingPathComponent("cancel-request"), options: .withoutOverwriting)
        }
        let status = try await host.awaitExit(log: hostLog, seconds: 3, maximum: 1 << 20)
        try #require(status == 0)
        let data = try Data(contentsOf: root.appendingPathComponent("complete.json")); try #require(data.count < 4096)
        let result = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        try #require(Set(result.keys) == ["version", "pid", "bothModesNativeSemantics", "pipelineHelperChildrenJoined", "cancelReaderJoined", "cancellation", "sourceSHA256", "cancellationSourceSHA256"])
        try #require(result["version"] as? Int == 1 && result["pid"] as? Int == Int(host.pid) && result["bothModesNativeSemantics"] as? Bool == true && result["pipelineHelperChildrenJoined"] as? Int == 6 && result["cancelReaderJoined"] as? Bool == true && result["sourceSHA256"] as? String == sourceHash && result["cancellationSourceSHA256"] as? String == cancelHash)
        let classification = try #require(result["cancellation"] as? String)
        try #require(classification == "cancelled" || classification == "unsettled-group-joined-child")
        var finalRoot = stat(), finalParent = stat(); try #require(lstat(root.path, &finalRoot) == 0 && lstat(parent.path, &finalParent) == 0)
        try #require(OriginalCompanionTransaction.FileID(finalRoot) == .init(rootID) && OriginalCompanionTransaction.FileID(finalParent) == .init(parentID))
        try #require(Self.hash(source) == sourceHash)
        try #require(Self.hash(cancellation) == cancelHash)
        try #require(Data(contentsOf: parent.appendingPathComponent("prior")) == prior)
        try #require(Self.signature(bundle.bundle, identifier: Self.identifier) == outer)
        try #require(Self.hash(main) == mainHash)
        try #require(Self.resources(bundle.bundle.appendingPathComponent("Contents/Resources")) == noticeHash)
        _ = try HelperSignatureAdmission.verify(bundle: bundle.bundle, role: .writer, policy: bundle.writerPolicy)
        _ = try HelperSignatureAdmission.verify(bundle: bundle.bundle, role: .reader, policy: bundle.readerPolicy)
        for mode in [OriginalCompanionTransaction.Retention.metadataOnly, .entireContainer] {
            let tool = try CompanionMetadataProcess.Tool.development(bundle.helper(.reader), expectedSHA256: reader.sha256)
            // The actual D120 operation already ran inside the isolated native
            // host. Independent parent review needs no shared operation registry.
            let review = try await CompanionDiskCheck.reviewOriginalCandidate(source: source, candidate: parent.appendingPathComponent(mode == .metadataOnly ? "metadata" : "entire"), retention: mode, tool: tool)
            try #require(review.originalMetadataSemanticsVerified && review.fullContainerMatchesOriginalBytes == (mode == .entireContainer))
        }
        print("GENERATED_STATIC_NATIVE_EXECUTED helpers_joined=7 cancellation=" + classification)
        settled = classification == "cancelled"
    }
}
