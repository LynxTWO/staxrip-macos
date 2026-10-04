import Foundation
import Security
import CryptoKit
import Darwin
import Testing
@testable import StaxRipMac

@Suite(.serialized)
struct HelperSignatureAdmissionTests {
    typealias Admission = HelperSignatureAdmission
    private struct Fixture {
        let original: CompanionOriginalMetadataCheckTests.Fixture
        let bundle: URL
        func url(_ role: Admission.Role) -> URL { bundle.appendingPathComponent("Contents/Helpers/" + role.basename) }
        func cleanup() { original.cleanup() }
    }
    private func fixture() async throws -> Fixture {
        let original = try await CompanionOriginalMetadataCheckTests.fixture(targetName: "native-helper-signature-fixtures")
        do {
            let bundle = original.root.appendingPathComponent("GeneratedHelperFixture.app")
            try FileManager.default.createDirectory(at: bundle.appendingPathComponent("Contents/Helpers"), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let f = Fixture(original: original, bundle: bundle)
            for role in [Admission.Role.reader, .writer] {
                try FileManager.default.copyItem(at: role == .reader ? original.reader : original.executable, to: f.url(role))
                try await sign(f, role)
            }
            return f
        } catch { original.cleanup(); throw error }
    }
    private func sign(_ f: Fixture, _ role: Admission.Role, runtime: Bool = true, identifier: String? = nil, entitlements: URL? = nil) async throws {
        var args = ["--force", "--sign", "-", "--timestamp=none", "--identifier", identifier ?? role.identifier]
        if runtime { args += ["--options", "runtime"] }
        if let entitlements { args += ["--entitlements", entitlements.path] }
        args.append(f.url(role).path)
        let r = try await ToolRunner().run(executable: URL(fileURLWithPath: "/usr/bin/codesign"), arguments: args)
        try #require(r.status == 0)
    }
    private func policy(_ f: Fixture, _ role: Admission.Role) throws -> Admission.Policy {
        // Creator captures known generated code immediately after its own signing.
        // This is explicitly not candidate-derived production trust.
        var code: SecStaticCode?, info: CFDictionary?
        try #require(SecStaticCodeCreateWithPath(f.url(role) as CFURL, SecCSFlags(), &code) == errSecSuccess)
        try #require(SecCodeCopySigningInformation(try #require(code), SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess)
        let values = try #require(info as? [String: Any]), hash = try #require(values[kSecCodeInfoUnique as String] as? Data)
        return try .development(role: role, trustedCDHash: hash.map { String(format: "%02x", $0) }.joined())
    }
    @Test func actualHardenedRustHelpersAdmitAndRunNativeBothModeSourceDependentPipeline() async throws {
        let f = try await fixture(); defer { f.cleanup() }
        let reader = try Admission.verify(bundle: f.bundle, role: .reader, policy: policy(f, .reader))
        let writer = try Admission.verify(bundle: f.bundle, role: .writer, policy: policy(f, .writer))
        #expect(!reader.developerIDRequirementMatched && !writer.developerIDRequirementMatched)
        #expect(reader.hardenedRuntime && writer.hardenedRuntime && reader.entitlementsAbsent && writer.entitlementsAbsent)
        #expect(reader.nativeThinArchitecture && writer.nativeThinArchitecture && !reader.executionOrNotarizationVerified)
        let readerTool = try CompanionMetadataProcess.Tool.development(f.url(.reader), expectedSHA256: reader.sha256)
        let writerTool = try CompanionWriterProcess.Tool.development(f.url(.writer), expectedSHA256: writer.sha256)
        let source = f.original.source, original = try Data(contentsOf: source)
        for mode in [OriginalCompanionTransaction.Retention.metadataOnly, .entireContainer] {
            let directory = f.original.root.appendingPathComponent(mode == .metadataOnly ? "metadata" : "whole")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            // Exercise signed helper execution below the single app-operation
            // owner. This independent fixture does not bypass or contend for its
            // one-operation admission rule; no release action is inferred.
            let result = try await OriginalCompanionTransaction.execute(source: source, in: directory, destinationName: "result", retention: mode,
                produce: { stage in try await CompanionWriterProcess.run(tool: writerTool, source: source, stage: stage, retention: mode).contents },
                verify: { stage, contents in
                    let r = try await CompanionDiskCheck.verifyOriginalMetadata(source: source, stage: stage, contents: contents, tool: readerTool)
                    let m = try #require(r.originalMetadata)
                    return .init(contents: r.contents, originalComponentsMatchSource: r.originalMetadataSemanticsVerified && m.originalComponentsMatchSource,
                        sourceIdentityChecked: true, decodedFrameAssociation: m.decodedFrameAssociation, immutableSnapshot: m.immutableSnapshot, stableImporter: m.stableImporter)
                })
            #expect(Set(try FileManager.default.contentsOfDirectory(atPath: result.directory.path)) == Set(mode.limits.keys))
            if mode == .entireContainer { #expect(try Data(contentsOf: result.directory.appendingPathComponent("original-container.mkv")) == original) }
        }
        #expect(try Data(contentsOf: source) == original)
    }
    @Test func actualAdHocSignatureCannotSatisfyDeveloperIDPolicyOrWrongRoleHash() async throws {
        let f = try await fixture(); defer { f.cleanup() }
        for role in [Admission.Role.reader, .writer] {
            let production = try Admission.Policy.developerID(role: role, trustedTeam: "AA11BB22CC")
            #expect(throws: NativeExportError.self) { try Admission.verify(bundle: f.bundle, role: role, policy: production) }
            let wrongHash = try Admission.Policy.development(role: role, trustedCDHash: String(repeating: "0", count: 40))
            #expect(throws: NativeExportError.self) { try Admission.verify(bundle: f.bundle, role: role, policy: wrongHash) }
        }
        #expect(throws: NativeExportError.self) { try Admission.verify(bundle: f.bundle, role: .reader, policy: policy(f, .writer)) }
        #expect(throws: NativeExportError.self) { try Admission.Policy.developerID(role: .reader, trustedTeam: "bad\"team") }
    }
    @Test func wrongIdentifierMissingRuntimeUnsignedAndEntitlementBlobRefuse() async throws {
        let f = try await fixture(); defer { f.cleanup() }
        let originalReaderPolicy = try policy(f, .reader)
        try await sign(f, .reader, identifier: "org.example.wrong")
        #expect(throws: NativeExportError.self) { try Admission.verify(bundle: f.bundle, role: .reader, policy: policy(f, .reader)) }
        try await sign(f, .reader, runtime: false)
        #expect(throws: NativeExportError.self) { try Admission.verify(bundle: f.bundle, role: .reader, policy: policy(f, .reader)) }
        let removed = try await ToolRunner().run(executable: URL(fileURLWithPath: "/usr/bin/codesign"), arguments: ["--remove-signature", f.url(.reader).path])
        try #require(removed.status == 0)
        #expect(throws: NativeExportError.self) { try Admission.verify(bundle: f.bundle, role: .reader, policy: originalReaderPolicy) }
        let entitlements = f.original.root.appendingPathComponent("generated-entitlements.plist")
        try PropertyListSerialization.data(fromPropertyList: ["com.apple.security.files.user-selected.read-only": true], format: .xml, options: 0).write(to: entitlements)
        try await sign(f, .reader, entitlements: entitlements)
        #expect(throws: NativeExportError.self) { try Admission.verify(bundle: f.bundle, role: .reader, policy: policy(f, .reader)) }
    }
    @Test func linkedWritableSpecialArchitectureAndParentSubstitutionsRefuse() async throws {
        let f = try await fixture(); defer { f.cleanup() }; let p = try policy(f, .reader), path = f.url(.reader)
        let saved = try Data(contentsOf: path)
        try #require(chmod(path.path, 0o777) == 0)
        #expect(throws: NativeExportError.self) { try Admission.verify(bundle: f.bundle, role: .reader, policy: p) }
        try #require(chmod(path.path, 0o755) == 0)
        let linked = f.original.root.appendingPathComponent("hard-link")
        try #require(link(path.path, linked.path) == 0)
        #expect(throws: NativeExportError.self) { try Admission.verify(bundle: f.bundle, role: .reader, policy: p) }
        try FileManager.default.removeItem(at: linked)
        try FileManager.default.removeItem(at: path)
        try FileManager.default.createSymbolicLink(at: path, withDestinationURL: f.original.reader)
        #expect(throws: NativeExportError.self) { try Admission.verify(bundle: f.bundle, role: .reader, policy: p) }
        try FileManager.default.removeItem(at: path)
        try #require(mkfifo(path.path, 0o600) == 0)
        #expect(throws: NativeExportError.self) { try Admission.verify(bundle: f.bundle, role: .reader, policy: p) }
        try FileManager.default.removeItem(at: path)
        var wrong = saved; wrong.replaceSubrange(4..<8, with: Data([0, 0, 0, 0])); try wrong.write(to: path); try #require(chmod(path.path, 0o755) == 0)
        #expect(throws: NativeExportError.self) { try Admission.verify(bundle: f.bundle, role: .reader, policy: p) }
        try FileManager.default.removeItem(at: path); try saved.write(to: path); try #require(chmod(path.path, 0o755) == 0)
        let helpers = f.bundle.appendingPathComponent("Contents/Helpers")
        try FileManager.default.moveItem(at: helpers, to: f.original.root.appendingPathComponent("original-helpers"))
        try FileManager.default.createSymbolicLink(at: helpers, withDestinationURL: f.original.root.appendingPathComponent("original-helpers"))
        #expect(throws: NativeExportError.self) { try Admission.verify(bundle: f.bundle, role: .reader, policy: p) }
    }
    @Test func actualAfterSignatureMutationAndCancellationRefuseBeforeSuccessfulReceipt() async throws {
        let f = try await fixture(); defer { f.cleanup() }; let p = try policy(f, .reader)
        #expect(throws: CancellationError.self) { try Admission.verify(bundle: f.bundle, role: .reader, policy: p, checkpoint: { throw CancellationError() }) }
        Admission.$testBoundary.withValue(.init(afterSignature: {
            let h = try FileHandle(forWritingTo: f.url(.reader)); try h.seek(toOffset: 4096); try h.write(contentsOf: Data([0xff])); try h.close()
        })) { #expect(throws: NativeExportError.self) { try Admission.verify(bundle: f.bundle, role: .reader, policy: p) } }
    }
}
