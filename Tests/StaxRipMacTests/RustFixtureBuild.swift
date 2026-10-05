import Foundation
import CryptoKit
import Darwin
import Testing
@testable import StaxRipMac

/// Test-only development artifacts. This does not provide an app tool capability.
/// Hold the native build lock through generation and exclusive private copies.
enum RustFixtureBuild {
    enum Kind: Sendable {
        case staged, original, reference, inspection
        var variable: String {
            switch self {
            case .staged: return "STAXRIP_GENERATED_STAGED_COMPANION_DIRECTORY"
            case .original: return "STAXRIP_GENERATED_COMPANION_FIXTURE_DIRECTORY"
            case .reference: return "STAXRIP_GENERATED_DOLBY_REFERENCE_DIRECTORY"
            case .inspection: return "STAXRIP_GENERATED_DOLBY_FIXTURE"
            }
        }
        var filter: String {
            switch self {
            case .staged: return "owned_stage_packages_preserve_originals_and_match_disk_receipts"
            case .original: return "original_companions_preserve_raw_bytes_encoded_order_and_distinct_retention"
            case .reference, .inspection: return "actual_hevc_packets_and_rpu_association_match_independent_ffprobe"
            }
        }
    }
    struct Helpers: Sendable { let writer, reader: URL }
    struct Boundary: Sendable {
        var acquired: @Sendable () -> Void = {}
        var preparing: @Sendable (String) -> Void = { _ in }
        var waiting: @Sendable () -> Void = {}
        var beforeCopy: @Sendable () async throws -> Void = {}
        var released: @Sendable () -> Void = {}
    }
    static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let shared = Coordinator(repo: repo, target: repo.appendingPathComponent("Tools/DolbyMetadataAudit/target/native-development-fixtures"))
    static func generate(_ kind: Kind, at destination: URL, copiesIn root: URL) async throws -> Helpers {
        try await shared.generate(kind, at: destination, copiesIn: root)
    }

    actor Coordinator {
        private struct Prepared {
            let helpers: Helpers
            let unit, matroska: URL
            let stagedTest: String
            let writerHash, readerHash: String
        }
        private let repo, target: URL
        private let boundary: Boundary
        private var prepared: Prepared?
        init(repo: URL, target: URL, boundary: Boundary = .init()) {
            self.repo = repo; self.target = target; self.boundary = boundary
        }
        private func acquire() async throws -> Int32 {
            try Task.checkCancellation()
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            let path = target.appendingPathComponent("fixture-build.lock")
            let fd = Darwin.open(path.path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard fd >= 0 else { throw POSIXError(.EACCES) }
            do {
                var info = stat()
                guard fstat(fd, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
                      info.st_uid == geteuid(), info.st_nlink == 1, info.st_mode & 0o7777 == 0o600 else {
                    throw NativeExportError.invalid("Unsafe fixture build lock")
                }
                while flock(fd, LOCK_EX | LOCK_NB) != 0 {
                    guard errno == EWOULDBLOCK || errno == EAGAIN else { throw POSIXError(.EIO) }
                    boundary.waiting()
                    try Task.checkCancellation()
                    try await Task.sleep(for: .milliseconds(10))
                }
                try Task.checkCancellation()
                return fd
            } catch {
                // Consume the local number exactly once, even during acquisition rollback.
                guard Darwin.close(fd) == 0 else { throw NativeExportError.invalid("Fixture lock rollback close refused") }
                throw error
            }
        }
        private func prepare() async throws -> Prepared {
            if let prepared { return prepared }
            let cargo = repo.appendingPathComponent("Tools/DolbyMetadataAudit/Cargo.toml")
            let common = ["--locked", "--features", "development-companion-writer", "--target-dir", target.path, "--manifest-path", cargo.path, "--message-format=json"]
            boundary.preparing("release")
            let release = try await ToolRunner().run(executable: URL(fileURLWithPath: "/usr/bin/env"), arguments: ["cargo", "build", "--release", "--bins"] + common)
            guard release.status == 0, !release.truncated else { throw NativeExportError.invalid("Shared development helper build refused") }
            boundary.preparing("tests")
            let tests = try await ToolRunner().run(executable: URL(fileURLWithPath: "/usr/bin/env"), arguments: ["cargo", "test", "--no-run", "--lib", "--bins", "--test", "matroska"] + common)
            guard tests.status == 0, !tests.truncated else { throw NativeExportError.invalid("Shared Rust fixture harness build refused") }
            var executables: [String: URL] = [:]
            for line in tests.stdout.split(separator: 10) {
                guard let row = try JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                      row["reason"] as? String == "compiler-artifact",
                      let profile = row["profile"] as? [String: Any], profile["test"] as? Bool == true,
                      let value = row["executable"] as? String, let t = row["target"] as? [String: Any],
                      let name = t["name"] as? String else { continue }
                guard value.hasPrefix(target.path + "/"), executables[name] == nil else { throw NativeExportError.invalid("Ambiguous fixture test artifact") }
                executables[name] = URL(fileURLWithPath: value)
            }
            guard let unit = executables["staxrip_dolby_metadata_audit"], let matroska = executables["matroska"] else { throw NativeExportError.invalid("Missing native Rust test harness") }
            let listed = try await ToolRunner().run(executable: unit, arguments: ["--list"], stdoutLimit: 65536)
            let names = String(decoding: listed.stdout, as: UTF8.self).split(separator: "\n").filter { $0.hasSuffix(Kind.staged.filter + ": test") }
            guard listed.status == 0, !listed.truncated, names.count == 1 else { throw NativeExportError.invalid("Missing or ambiguous staged generator") }
            let value = Prepared(helpers: .init(writer: target.appendingPathComponent("release/staxrip-dolby-companion-writer"), reader: target.appendingPathComponent("release/staxrip-dolby-metadata-audit")), unit: unit, matroska: matroska, stagedTest: String(names[0].dropLast(6)), writerHash: try digest(target.appendingPathComponent("release/staxrip-dolby-companion-writer")), readerHash: try digest(target.appendingPathComponent("release/staxrip-dolby-metadata-audit")))
            prepared = value
            return value
        }
        private func digest(_ path: URL) throws -> String {
            DolbyInspection.hex(SHA256.hash(data: try Data(contentsOf: path)))
        }
        private func check(_ value: Prepared) throws {
            guard try digest(value.helpers.writer) == value.writerHash,
                  try digest(value.helpers.reader) == value.readerHash else { throw NativeExportError.invalid("Prepared fixture helper changed") }
        }
        func generate(_ kind: Kind, at destination: URL, copiesIn root: URL) async throws -> Helpers {
            let fd = try await acquire()
            boundary.acquired()
            let result: Result<Helpers, Error>
            do {
                let value = try await prepare()
                try check(value)
                try Task.checkCancellation()
                let executable = kind == .staged ? value.unit : value.matroska
                let filter = kind == .staged ? value.stagedTest : kind.filter
                let generated = try await ToolRunner().run(executable: URL(fileURLWithPath: "/usr/bin/env"), arguments: [kind.variable + "=" + destination.path, executable.path, filter, "--exact"], stdoutLimit: 65536)
                guard generated.status == 0, !generated.truncated,
                      String(decoding: generated.stdout, as: UTF8.self).contains("1 passed; 0 failed") else { throw NativeExportError.invalid("Named Rust fixture generator refused") }
                try Task.checkCancellation()
                try await boundary.beforeCopy()
                let helpers = Helpers(writer: root.appendingPathComponent("staxrip-dolby-companion-writer"), reader: root.appendingPathComponent("staxrip-dolby-metadata-audit"))
                // copyItem is exclusive. Later signing/mutation/execution uses only these copies.
                try FileManager.default.copyItem(at: value.helpers.writer, to: helpers.writer)
                try FileManager.default.copyItem(at: value.helpers.reader, to: helpers.reader)
                try check(value)
                guard try digest(helpers.writer) == value.writerHash, try digest(helpers.reader) == value.readerHash else {
                    throw NativeExportError.invalid("Private helper copy differs from prepared build")
                }
                result = .success(helpers)
            } catch { result = .failure(error) }
            // Release only after generator/build direct-child and reader completion and copying.
            // No process-group/descendant or physical-I/O preemption guarantee follows.
            let unlocked = flock(fd, LOCK_UN) == 0
            let closed = Darwin.close(fd) == 0 // Consume once; never retry an uncertain number.
            guard unlocked, closed else { throw NativeExportError.invalid("Fixture build lock settlement refused") }
            boundary.released()
            return try result.get()
        }
    }
}
