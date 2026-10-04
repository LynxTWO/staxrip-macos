// TEST ONLY: compiled separately with unchanged non-entry product sources.
// No application startup, session load, runtime bridge or release capability.
import Foundation
import CryptoKit
import Security
import Darwin

@main
struct GeneratedStaticNativeHost {
    static let identifier = "org.staxrip.generated.static-native-host"
    static func require(_ condition: @autoclosure () throws -> Bool) throws {
        guard try condition() else { throw NativeExportError.invalid("Generated static host qualification refused") }
    }
    static func digest(_ url: URL) throws -> String {
        DolbyInspection.hex(SHA256.hash(data: try Data(contentsOf: url)))
    }
    static func record(_ value: [String: Any], at url: URL) throws {
        let bytes = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        try require(bytes.count <= 4096)
        let fd = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        try require(fd >= 0)
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        try handle.write(contentsOf: bytes); try handle.close()
    }
    static func outer(_ bundle: URL, expected: String) throws {
        var code: SecStaticCode?, requirement: SecRequirement?, information: CFDictionary?
        try require(expected.count == 40 && expected.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) })
        try require(SecStaticCodeCreateWithPath(bundle as CFURL, SecCSFlags(), &code) == errSecSuccess)
        let expression = "identifier \"\(identifier)\" and cdhash H\"\(expected)\""
        try require(SecRequirementCreateWithString(expression as CFString, SecCSFlags(), &requirement) == errSecSuccess)
        guard let code, let requirement else { throw NativeExportError.invalid("Generated outer admission missing") }
        try require(SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckNestedCode | kSecCSCheckAllArchitectures), requirement) == errSecSuccess)
        try require(SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess)
        guard let info = information as? [String: Any], let flags = info[kSecCodeInfoFlags as String] as? NSNumber else { throw NativeExportError.invalid("Generated outer information missing") }
        try require(flags.uint32Value & 0x10000 != 0 && flags.uint32Value & 2 != 0)
        try require(info[kSecCodeInfoEntitlementsDict as String] == nil && info[kSecCodeInfoEntitlements as String] == nil && info[kSecCodeInfoTeamIdentifier as String] == nil)
    }
    static func resources(_ root: URL) throws -> String {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { throw NativeExportError.invalid("Generated resources missing") }
        var values: [String] = []
        for case let url as URL in enumerator where try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
            values.append(String(url.path.dropFirst(root.path.count + 1)) + ":" + (try digest(url)))
        }
        return DolbyInspection.hex(SHA256.hash(data: Data(values.sorted().joined(separator: "\n").utf8)))
    }
    final class Children: @unchecked Sendable {
        private let lock = NSLock()
        private var launched: [pid_t] = [], joined: [pid_t] = []
        func launch(_ pid: pid_t) { lock.withLock { launched.append(pid) } }
        func join(_ pid: pid_t) { lock.withLock { joined.append(pid) } }
        var lastPID: pid_t { lock.withLock { launched.last ?? 0 } }
        func check(_ count: Int) throws {
            let state = lock.withLock { (launched, joined) }
            try require(state.0.count == count && state.0 == state.1)
            for pid in state.0 { var status: Int32 = 0; try require(waitpid(pid, &status, WNOHANG) == -1 && errno == ECHILD) }
        }
    }
    final class Gate: @unchecked Sendable {
        let signal = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var held = false
        private(set) var failed = false
        func hold() -> Bool { lock.withLock { if held { return false }; held = true; return true } }
        func wait() { if signal.wait(timeout: .now() + 5) != .success { lock.withLock { failed = true } } }
        var didFail: Bool { lock.withLock { failed } }
    }
    @MainActor static func main() async {
        do { try await qualify() }
        catch { print("GENERATED_STATIC_NATIVE_HOST_REFUSED " + String(describing: type(of: error))); Darwin._exit(1) }
    }
    @MainActor static func qualify() async throws {
        let args = CommandLine.arguments
        try require(args.count == 9 && args[1] == "generated-only")
        let root = URL(fileURLWithPath: args[2]), source = root.appendingPathComponent("source.mkv")
        let bundle = root.appendingPathComponent("owned relocated folder/GeneratedReaderHost.app")
        let main = bundle.appendingPathComponent("Contents/MacOS/StaticNativeHost")
        try outer(bundle, expected: args[4])
        try require(try digest(main) == args[5])
        try require(try resources(bundle.appendingPathComponent("Contents/Resources")) == args[8])
        let writerReceipt = try HelperSignatureAdmission.verify(bundle: bundle, role: .writer, policy: .development(role: .writer, trustedCDHash: args[6]))
        let readerReceipt = try HelperSignatureAdmission.verify(bundle: bundle, role: .reader, policy: .development(role: .reader, trustedCDHash: args[7]))
        let writer = try CompanionWriterProcess.Tool.development(bundle.appendingPathComponent("Contents/Helpers/staxrip-dolby-companion-writer"), expectedSHA256: writerReceipt.sha256)
        let reader = try CompanionMetadataProcess.Tool.development(bundle.appendingPathComponent("Contents/Helpers/staxrip-dolby-metadata-audit"), expectedSHA256: readerReceipt.sha256)
        try require(try digest(source) == args[3])
        let parent = root.appendingPathComponent("destination"), prior = try Data(contentsOf: parent.appendingPathComponent("prior"))
        try record(["version": 1, "pid": getpid(), "staticNativeEntry": true], at: root.appendingPathComponent("entered.json"))
        let children = Children()
        for mode in [OriginalCompanionTransaction.Retention.metadataOnly, .entireContainer] {
            let result = try await CompanionWriterProcess.$testBoundary.withValue(.init(launched: { children.launch($0) }, settled: { children.join($0) })) {
                try await CompanionMetadataProcess.$testBoundary.withValue(.init(launched: { children.launch($0) }, settled: { children.join($0) })) {
                    try await CompanionArchiveOperation.execute(source: source, in: parent, destinationName: mode == .metadataOnly ? "metadata" : "entire", retention: mode, writer: writer, reader: reader)
                }
            }
            let review = try await CompanionMetadataProcess.$testBoundary.withValue(.init(launched: { children.launch($0) }, settled: { children.join($0) })) {
                try await CompanionArchiveOperation.reviewCandidate(source: source, candidate: result.directory, retention: mode, reader: reader)
            }
            try require(review.originalMetadataSemanticsVerified && review.fullContainerMatchesOriginalBytes == (mode == .entireContainer))
        }
        try children.check(6)
        // A separate actual streaming-reader cancellation, not candidate review
        // of a different source. Parent observes a real packet and live process.
        let cancellationSource = root.appendingPathComponent("cancellation-source.mkv")
        let cancellationHash = try digest(cancellationSource), cancelChildren = Children(), gate = Gate()
        let task = Task {
            try await CompanionMetadataProcess.$testBoundary.withValue(.init(launched: { cancelChildren.launch($0) }, settled: { cancelChildren.join($0) })) {
                try await CompanionMetadataProcess.run(tool: reader, source: cancellationSource, observe: { row in
                    if String(decoding: row, as: UTF8.self).contains("\"kind\":\"packet\"") && gate.hold() {
                        try record(["version": 1, "realPacketObserved": true, "readerPID": cancelChildren.lastPID], at: root.appendingPathComponent("cancel-ready.json"))
                        gate.wait()
                    }
                })
            }
        }
        let limit = ContinuousClock.now.advanced(by: .seconds(5))
        while !FileManager.default.fileExists(atPath: root.appendingPathComponent("cancel-request").path), ContinuousClock.now < limit {
            try await Task.sleep(for: .milliseconds(5))
        }
        let requested = FileManager.default.fileExists(atPath: root.appendingPathComponent("cancel-request").path)
        task.cancel(); gate.signal.signal()
        var cancellation = "unexpected"
        do { _ = try await task.value }
        catch is CancellationError { cancellation = "cancelled" }
        catch let error as CompanionMetadataProcess.OwnershipFailure {
            try require(error.reason == "group-1-joined-true")
            cancellation = "unsettled-group-joined-child"
        }
        try cancelChildren.check(1)
        try require(requested && !gate.didFail && cancellation != "unexpected")
        try require(try digest(cancellationSource) == cancellationHash)
        try require(try digest(source) == args[3])
        try require(try Data(contentsOf: parent.appendingPathComponent("prior")) == prior)
        try outer(bundle, expected: args[4])
        try require(try digest(main) == args[5])
        try require(try resources(bundle.appendingPathComponent("Contents/Resources")) == args[8])
        _ = try HelperSignatureAdmission.verify(bundle: bundle, role: .writer, policy: .development(role: .writer, trustedCDHash: args[6]))
        _ = try HelperSignatureAdmission.verify(bundle: bundle, role: .reader, policy: .development(role: .reader, trustedCDHash: args[7]))
        try record(["version": 1, "pid": getpid(), "bothModesNativeSemantics": true, "pipelineHelperChildrenJoined": 6,
                    "cancelReaderJoined": true, "cancellation": cancellation, "sourceSHA256": args[3], "cancellationSourceSHA256": cancellationHash], at: root.appendingPathComponent("complete.json"))
        Darwin._exit(0)
    }
}
