import Foundation
import Security
import CryptoKit
import Darwin

/// Unused fixed-role static signature prerequisite. No release Tool capability,
/// importer, signing operation or archive action is installed by this check.
enum HelperSignatureAdmission {
    enum Role: Sendable {
        case reader, writer
        var basename: String { self == .reader ? "staxrip-dolby-metadata-audit" : "staxrip-dolby-companion-writer" }
        var identifier: String { self == .reader ? "org.staxrip.mac.dolby-reader" : "org.staxrip.mac.dolby-writer" }
    }
    struct Policy: Sendable {
        fileprivate let role: Role, requirement: String, team: String?
        private init(role: Role, requirement: String, team: String?) { self.role = role; self.requirement = requirement; self.team = team }
        /// The caller must obtain this team from trusted release configuration,
        /// never media, archives or a candidate executable's own signing claims.
        static func developerID(role: Role, trustedTeam: String) throws -> Self {
            guard trustedTeam.utf8.count == 10, trustedTeam.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) }) else { throw refused() }
            return .init(role: role, requirement: "anchor apple generic and identifier \"\(role.identifier)\" and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = \"\(trustedTeam)\"", team: trustedTeam)
        }
        #if DEBUG
        /// A captured code-directory hash qualifies only explicit generated trust.
        /// Ad-hoc code is always refused by the Developer ID policy above.
        static func development(role: Role, trustedCDHash: String) throws -> Self {
            guard trustedCDHash.utf8.count == 40, trustedCDHash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw refused() }
            return .init(role: role, requirement: "identifier \"\(role.identifier)\" and cdhash H\"\(trustedCDHash)\"", team: nil)
        }
        #endif
    }
    struct Receipt: Sendable {
        let role: Role
        let fileID: OriginalCompanionTransaction.FileID
        let byteCount: Int64
        let sha256, cdHash: String
        let developerIDRequirementMatched: Bool
        let hardenedRuntime = true
        let entitlementsAbsent = true
        let nativeThinArchitecture = true
        let executionOrNotarizationVerified = false
    }
    #if DEBUG
    struct Boundary { var afterSignature: () throws -> Void = {} }
    @TaskLocal static var testBoundary = Boundary()
    #endif
    private static func refused() -> NativeExportError { .invalid("Fixed helper signature admission refused. No executable capability was issued.") }

    /// Synchronous work for an owning worker. Security/filesystem calls cannot be
    /// preempted; checkpoints do not establish a hard physical-I/O deadline.
    static func verify(bundle: URL, role: Role, policy: Policy, checkpoint: () throws -> Void = {}) throws -> Receipt {
        guard bundle.isFileURL, !bundle.path.utf8.contains(0), bundle.pathExtension == "app", policy.role == role else { throw refused() }
        try checkpoint()
        let pins = try Pins(bundle: bundle, role: role)
        let digest = try pins.hash(checkpoint)
        try pins.check(); try checkpoint()
        var code: SecStaticCode?, requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(pins.url as CFURL, SecCSFlags(), &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(policy.requirement as CFString, SecCSFlags(), &requirement) == errSecSuccess, let requirement,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures), requirement) == errSecSuccess else { throw refused() }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let info = information as? [String: Any], info[kSecCodeInfoIdentifier as String] as? String == role.identifier,
              let flags = info[kSecCodeInfoFlags as String] as? NSNumber, flags.uint32Value & 0x10000 != 0,
              info[kSecCodeInfoEntitlements as String] == nil, info[kSecCodeInfoEntitlementsDict as String] == nil,
              let cdHash = info[kSecCodeInfoUnique as String] as? Data, cdHash.count == 20 else { throw refused() }
        if let team = policy.team {
            guard flags.uint32Value & 0x0002 == 0, info[kSecCodeInfoTeamIdentifier as String] as? String == team else { throw refused() }
        } else {
            // Development policy cannot accidentally become a certificate policy.
            guard flags.uint32Value & 0x0002 != 0, info[kSecCodeInfoTeamIdentifier as String] == nil else { throw refused() }
        }
        #if DEBUG
        try testBoundary.afterSignature()
        #endif
        try checkpoint(); try pins.check()
        guard try pins.hash(checkpoint) == digest else { throw refused() }
        try pins.check(); try checkpoint()
        return .init(role: role, fileID: .init(pins.initial), byteCount: pins.initial.st_size,
            sha256: digest, cdHash: cdHash.map { String(format: "%02x", $0) }.joined(), developerIDRequirementMatched: policy.team != nil)
    }

    private final class Pins {
        let url: URL
        private var fds: [Int32] = []
        private var observed: [stat] = []
        private let paths: [URL]
        var initial: stat { observed[3] }
        init(bundle: URL, role: Role) throws {
            let contents = bundle.appendingPathComponent("Contents"), helpers = contents.appendingPathComponent("Helpers")
            url = helpers.appendingPathComponent(role.basename); paths = [bundle, contents, helpers, url]
            do {
                for i in 0..<4 {
                    let options = O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_NOCTTY | O_CLOEXEC | (i < 3 ? O_DIRECTORY : 0)
                    let fd = i == 0 ? Darwin.open(bundle.path, options) : openat(fds[i-1], i == 1 ? "Contents" : i == 2 ? "Helpers" : role.basename, options)
                    guard fd >= 0 else { throw refused() }; fds.append(fd)
                    var s = stat()
                    guard fstat(fd, &s) == 0, s.st_mode & mode_t(S_IFMT) == mode_t(i < 3 ? S_IFDIR : S_IFREG),
                          [0, geteuid()].contains(s.st_uid), s.st_mode & 0o022 == 0,
                          i < 3 || (s.st_nlink == 1 && s.st_mode & 0o100 != 0 && (32...Int64(1 << 28)).contains(s.st_size)) else { throw refused() }
                    observed.append(s)
                }
                try check()
                var header = [UInt8](repeating: 0, count: 8)
                guard pread(fds[3], &header, header.count, 0) == header.count else { throw refused() }
                func word(_ at: Int) -> UInt32 { (0..<4).reduce(0) { $0 | UInt32(header[at+$1]) << (8*$1) } }
                #if arch(arm64)
                let native: UInt32 = 0x0100000c
                #elseif arch(x86_64)
                let native: UInt32 = 0x01000007
                #else
                let native: UInt32 = 0
                #endif
                guard word(0) == 0xfeedfacf, native != 0, word(4) == native else { throw refused() }
            } catch { close(); throw error }
        }
        func check() throws {
            guard fds.count == 4, observed.count == 4 else { throw refused() }
            for i in 0..<4 {
                var s = stat(), p = stat()
                guard fstat(fds[i], &s) == 0, lstat(paths[i].path, &p) == 0,
                      same(observed[i], s, file: i == 3), same(observed[i], p, file: i == 3) else { throw refused() }
            }
        }
        private func same(_ a: stat, _ b: stat, file: Bool) -> Bool {
            guard a.st_dev == b.st_dev, a.st_ino == b.st_ino, a.st_mode == b.st_mode, a.st_uid == b.st_uid else { return false }
            return !file || (a.st_nlink == b.st_nlink && a.st_size == b.st_size &&
                a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec && a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec &&
                a.st_ctimespec.tv_sec == b.st_ctimespec.tv_sec && a.st_ctimespec.tv_nsec == b.st_ctimespec.tv_nsec)
        }
        func hash(_ checkpoint: () throws -> Void) throws -> String {
            var offset: Int64 = 0, hasher = SHA256(), buffer = [UInt8](repeating: 0, count: 1 << 20)
            while offset < initial.st_size {
                try checkpoint()
                let count = pread(fds[3], &buffer, Int(min(Int64(buffer.count), initial.st_size-offset)), off_t(offset))
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw refused() }
                buffer.withUnsafeBytes { hasher.update(bufferPointer: UnsafeRawBufferPointer(rebasing: $0[..<count])) }
                offset += Int64(count)
            }
            try check(); return DolbyInspection.hex(hasher.finalize())
        }
        private func close() { for fd in fds { Darwin.close(fd) }; fds.removeAll() }
        deinit { close() }
    }
}
