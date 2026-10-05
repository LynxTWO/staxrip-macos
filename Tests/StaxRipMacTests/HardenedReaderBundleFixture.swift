import Foundation
import Security
import CryptoKit
import Darwin
import Testing
@testable import StaxRipMac

/// Owned test packaging only. The real Rust reader is this bundle's main, not the
/// SwiftUI app. No runtime factory or archive-selected executable comes from it.
struct HardenedReaderBundleFixture {
    typealias Admission = HelperSignatureAdmission
    static let identifier = "org.staxrip.generated.companion-reader-host"
    let original: CompanionOriginalMetadataCheckTests.Fixture
    let bundle: URL
    let outerCDHash: String
    let readerPolicy, writerPolicy: Admission.Policy
    let mainSHA256: String
    let noticeHashes: [String: String]
    var main: URL { bundle.appendingPathComponent("Contents/MacOS/staxrip-dolby-metadata-audit") }
    func helper(_ role: Admission.Role) -> URL { bundle.appendingPathComponent("Contents/Helpers/" + role.basename) }
    func cleanup() { original.cleanup() }
    static func hash(_ url: URL) throws -> String { DolbyInspection.hex(SHA256.hash(data: try Data(contentsOf: url))) }
    private static var repo: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }
    private static func signingInfo(_ url: URL) throws -> [String: Any] {
        var code: SecStaticCode?, values: CFDictionary?
        try #require(SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(), &code) == errSecSuccess)
        try #require(SecCodeCopySigningInformation(try #require(code), SecCSFlags(rawValue: kSecCSSigningInformation), &values) == errSecSuccess)
        return try #require(values as? [String: Any])
    }
    private static func cdHash(_ url: URL) throws -> String {
        let values = try signingInfo(url), bytes = try #require(values[kSecCodeInfoUnique as String] as? Data)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
    private static func sign(_ url: URL, identifier: String) async throws {
        let r = try await ToolRunner().run(executable: URL(fileURLWithPath: "/usr/bin/codesign"), arguments: [
            "--force", "--sign", "-", "--timestamp=none", "--options", "runtime", "--identifier", identifier, url.path])
        try #require(r.status == 0)
    }
    static func make() async throws -> Self {
        let f = try await CompanionOriginalMetadataCheckTests.fixture()
        do {
            let initial = f.root.appendingPathComponent("GeneratedReaderHost.app")
            let resources = initial.appendingPathComponent("Contents/Resources")
            for path in ["Contents/MacOS", "Contents/Helpers", "Contents/Resources"] {
                try FileManager.default.createDirectory(at: initial.appendingPathComponent(path), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            }
            let info: [String: Any] = ["CFBundleExecutable": "staxrip-dolby-metadata-audit", "CFBundleIdentifier": identifier,
                "CFBundlePackageType": "APPL", "CFBundleVersion": "1", "LSMinimumSystemVersion": "14.0"]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: initial.appendingPathComponent("Contents/Info.plist"))
            try FileManager.default.copyItem(at: f.reader, to: initial.appendingPathComponent("Contents/MacOS/staxrip-dolby-metadata-audit"))
            for role in [Admission.Role.reader, .writer] {
                let destination = initial.appendingPathComponent("Contents/Helpers/" + role.basename)
                try FileManager.default.copyItem(at: role == .reader ? f.reader : f.executable, to: destination)
                try await sign(destination, identifier: role.identifier)
            }
            let toolRoot = repo.appendingPathComponent("Tools/DolbyMetadataAudit")
            try FileManager.default.copyItem(at: repo.appendingPathComponent("THIRD-PARTY-NOTICES.md"), to: resources.appendingPathComponent("THIRD-PARTY-NOTICES.md"))
            let licenses = resources.appendingPathComponent("DolbyMetadataLicenses")
            try FileManager.default.copyItem(at: toolRoot.appendingPathComponent("LICENSES"), to: licenses)
            for (name, target) in [("DEPENDENCY-LICENSES.json", "DEPENDENCY-LICENSES.json"), ("LICENSE", "LICENSE-staxrip-helper")] {
                try FileManager.default.copyItem(at: toolRoot.appendingPathComponent(name), to: licenses.appendingPathComponent(target))
            }
            // Trusted repository lock grammar, not an archive TOML importer.
            let inventory = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: toolRoot.appendingPathComponent("DEPENDENCY-LICENSES.json"))) as? [[String: Any]])
            let lock = try String(contentsOf: toolRoot.appendingPathComponent("Cargo.lock"), encoding: .utf8)
            func field(_ block: Substring, _ key: String) throws -> String {
                let line = try #require(block.split(separator: "\n").first { $0.hasPrefix(key + " = \"") })
                return String(line.dropFirst(key.count + 4).dropLast())
            }
            let locked = try Set(lock.components(separatedBy: "[[package]]").dropFirst().map { block -> String in
                try field(Substring(block), "name") + "@" + field(Substring(block), "version")
            }.filter { !$0.hasPrefix("staxrip-dolby-metadata-audit@") })
            let listed = try Set(inventory.map { try #require($0["name"] as? String) + "@" + #require($0["version"] as? String) })
            try #require(locked == listed && !listed.isEmpty)
            for package in inventory {
                let name = try #require(package["name"] as? String), version = try #require(package["version"] as? String)
                let entries = try #require(package["license_texts"] as? [[String: Any]])
                try #require(!entries.isEmpty)
                for entry in entries {
                    let path = licenses.appendingPathComponent(name + "-" + version).appendingPathComponent(try #require(entry["name"] as? String))
                    let expected = try #require(entry["sha256"] as? String)
                    try #require(hash(path) == expected)
                }
            }
            let sys = try await ToolRunner().run(executable: URL(fileURLWithPath: "/usr/bin/env"), arguments: ["rustc", "--print", "sysroot"])
            try #require(sys.status == 0 && sys.stdout.count < 4096)
            let sysroot = URL(fileURLWithPath: String(decoding: sys.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
            let rust = licenses.appendingPathComponent("RustLibrary")
            try FileManager.default.createDirectory(at: rust, withIntermediateDirectories: false)
            for source in [sysroot.appendingPathComponent("LICENSE-MIT"), sysroot.appendingPathComponent("LICENSE-APACHE"), sysroot.appendingPathComponent("COPYRIGHT"), sysroot.appendingPathComponent("share/doc/rustc/COPYRIGHT-library.html"), sysroot.appendingPathComponent("share/doc/rustc/licenses")] {
                try FileManager.default.copyItem(at: source, to: rust.appendingPathComponent(source.lastPathComponent))
            }
            let notices = try resourceHashes(resources)
            try #require(notices.count > inventory.count)
            try await sign(initial, identifier: identifier)
            let outer = try cdHash(initial)
            let reader = try Admission.Policy.development(role: .reader, trustedCDHash: cdHash(initial.appendingPathComponent("Contents/Helpers/" + Admission.Role.reader.basename)))
            let writer = try Admission.Policy.development(role: .writer, trustedCDHash: cdHash(initial.appendingPathComponent("Contents/Helpers/" + Admission.Role.writer.basename)))
            let mainHash = try hash(initial.appendingPathComponent("Contents/MacOS/staxrip-dolby-metadata-audit"))
            let movedParent = f.root.appendingPathComponent("owned relocated folder")
            try FileManager.default.createDirectory(at: movedParent, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let moved = movedParent.appendingPathComponent(initial.lastPathComponent)
            try FileManager.default.moveItem(at: initial, to: moved)
            return .init(original: f, bundle: moved, outerCDHash: outer, readerPolicy: reader, writerPolicy: writer, mainSHA256: mainHash, noticeHashes: notices)
        } catch { f.cleanup(); throw error }
    }
    private static func resourceHashes(_ resources: URL) throws -> [String: String] {
        let e = try #require(FileManager.default.enumerator(at: resources, includingPropertiesForKeys: [.isRegularFileKey]))
        var values: [String: String] = [:]
        for case let url as URL in e {
            if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                values[String(url.path.dropFirst(resources.path.count + 1))] = try hash(url)
            }
        }
        return values
    }
    func admit() throws -> (CompanionWriterProcess.Tool, CompanionMetadataProcess.Tool) {
        var code: SecStaticCode?, requirement: SecRequirement?
        try #require(SecStaticCodeCreateWithPath(bundle as CFURL, SecCSFlags(), &code) == errSecSuccess)
        let expression = "identifier \"\(Self.identifier)\" and cdhash H\"\(outerCDHash)\""
        try #require(SecRequirementCreateWithString(expression as CFString, SecCSFlags(), &requirement) == errSecSuccess)
        let signedCode = try #require(code), capturedRequirement = try #require(requirement)
        let validity = SecStaticCodeCheckValidity(signedCode, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckNestedCode | kSecCSCheckAllArchitectures), capturedRequirement)
        guard validity == errSecSuccess else {
            throw NativeExportError.invalid("Generated bundle outer seal refused")
        }
        let info = try Self.signingInfo(bundle), flags = try #require(info[kSecCodeInfoFlags as String] as? NSNumber)
        try #require(flags.uint32Value & 0x10000 != 0 && flags.uint32Value & 0x0002 != 0)
        try #require(info[kSecCodeInfoEntitlementsDict as String] == nil && info[kSecCodeInfoEntitlements as String] == nil && info[kSecCodeInfoTeamIdentifier as String] == nil)
        let actualMain = try Self.hash(main), actualNotices = try Self.resourceHashes(bundle.appendingPathComponent("Contents/Resources"))
        try #require(actualMain == mainSHA256 && actualNotices == noticeHashes)
        _ = try Admission.verify(bundle: bundle, role: .reader, policy: readerPolicy)
        let writer = try Admission.verify(bundle: bundle, role: .writer, policy: writerPolicy)
        return (try .development(helper(.writer), expectedSHA256: writer.sha256), try .development(main, expectedSHA256: mainSHA256))
    }
}
