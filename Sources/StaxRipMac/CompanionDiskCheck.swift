import Foundation
import Darwin
import CryptoKit

/// Unused internal disk/source/component settlement, with explicit progressively
/// stronger source-dependent checks. Source observation spooling is explicit;
/// no import or native archive action.
enum CompanionDiskCheck {
    typealias Transaction = OriginalCompanionTransaction
    struct Receipt: Sendable {
        let contents: Transaction.Contents
        let fullContainerMatchesOriginalBytes: Bool
        let originalTrack: CompanionOriginalTrackCheck.Receipt?
        let originalPackets: CompanionOriginalPacketCheck.Receipt?
        let originalIndex: CompanionOriginalIndexCheck.Receipt?
        let originalAudit: CompanionOriginalAuditCheck.Receipt?
        let originalMetadata: CompanionOriginalMetadataCheck.Receipt?
        var originalMetadataSemanticsVerified: Bool { originalMetadata != nil }
    }
    struct Boundary: Sendable {
        var progress: @Sendable (String, Int64) -> Void = { _, _ in }
        var beforeFinal: @Sendable () -> Void = {}
        var originalTrackRead: @Sendable (Int64, Int) -> Void = { _, _ in }
        var originalComponentRead: @Sendable (String, Int64, Int) -> Void = { _, _, _ in }
        var fileOpened: @Sendable (String?) throws -> Void = { _ in }
        var admissionClosed: @Sendable (String?, Int32, Int32) -> Void = { _, _, _ in }
        var refuseAdmissionClose: @Sendable (String?) -> Bool = { _ in false }
    }
    #if DEBUG
    @TaskLocal static var testBoundary = Boundary()
    #endif
    private final class Cancellation: @unchecked Sendable {
        private let lock = NSLock(); private var requested = false
        func cancel() { lock.withLock { requested = true } }
        func check() throws { if lock.withLock({ requested }) { throw CancellationError() } }
    }
    private static func failure() -> NativeExportError { .invalid("Companion disk verification refused. No successful integrity receipt.") }
    /// Integrity only. Original track/configuration/packet/RPU semantics are not inferred.
    static func verify(source: URL, stage: URL, contents: Transaction.Contents) async throws -> Receipt {
        try await settle(source: source, stage: stage, contents: contents, originalTrack: false, originalPackets: false, originalIndex: false, originalAudit: false)
    }
    /// Partial native semantic prerequisite, never full original-components admission.
    static func verifyOriginalTrack(source: URL, stage: URL, contents: Transaction.Contents) async throws -> Receipt {
        try await settle(source: source, stage: stage, contents: contents, originalTrack: true, originalPackets: false, originalIndex: false, originalAudit: false)
    }
    /// Source packet/raw-RPU prerequisite only; index/audit/manifest semantics remain false.
    static func verifyOriginalPackets(source: URL, stage: URL, contents: Transaction.Contents) async throws -> Receipt {
        try await settle(source: source, stage: stage, contents: contents, originalTrack: true, originalPackets: true, originalIndex: false, originalAudit: false)
    }
    /// Persisted original index/manifest prerequisite; audit/metadata semantics remain false.
    static func verifyOriginalIndexAndManifest(source: URL, stage: URL, contents: Transaction.Contents) async throws -> Receipt {
        try await settle(source: source, stage: stage, contents: contents, originalTrack: true, originalPackets: true, originalIndex: true, originalAudit: false)
    }
    /// Stored audit framing/source facts; compact metadata truth remains unverified.
    static func verifyOriginalAudit(source: URL, stage: URL, contents: Transaction.Contents) async throws -> Receipt {
        try await settle(source: source, stage: stage, contents: contents, originalTrack: true, originalPackets: true, originalIndex: true, originalAudit: true)
    }
    /// Complete source-dependent original component comparison; not a portable importer or release action.
    static func verifyOriginalMetadata(source: URL, stage: URL, contents: Transaction.Contents,
                                       tool: CompanionMetadataProcess.Tool) async throws -> Receipt {
        try await settle(source: source, stage: stage, contents: contents, originalTrack: true, originalPackets: true,
                         originalIndex: true, originalAudit: true, metadataTool: tool)
    }
    /// Explicit read-only review of surviving files against the original source.
    /// No lost coordinator receipt, path discovery, import or cleanup authority.
    static func reviewOriginalCandidate(source: URL, candidate: URL, retention: Transaction.Retention,
                                        tool: CompanionMetadataProcess.Tool) async throws -> Receipt {
        try await settle(source: source, stage: candidate, input: .candidate(retention), originalTrack: true,
                         originalPackets: true, originalIndex: true, originalAudit: true, metadataTool: tool)
    }
    struct SourceSpoolReceipt: Sendable {
        let sourceID: Transaction.FileID
        let sourceBytes: Int64
        let sourceSHA256: String
        let track: CompanionOriginalTrackCheck.Receipt
        let packets: CompanionOriginalPacketCheck.Receipt
        let timestampScale: UInt64
        let unknownSegment: Bool
        let independentSourceFrameAssociationVerified = false
        let editedPictureSemanticsVerified = false
    }
    struct SourceFrameReceipt: Sendable {
        let source: SourceSpoolReceipt
        let decoder: DolbyDecoderStream.Receipt
        let independentSourceFrameAssociationVerified = true
        let editedPictureSemanticsVerified = false
    }
    /// Fixed decoder observations bound to independently reconstructed original
    /// source facts. Summary values still rely on the admitted decoder implementation.
    struct SourceSampleReceipt: Sendable {
        let source: SourceSpoolReceipt
        let decoder: DolbyDecoderStream.Receipt
        let independentSourceFrameAssociationVerified = true
        let independentSampleSourceAssociationVerified = true
        let independentSampleValuesVerified = false
        let editedPictureSemanticsVerified = false
    }
    /// Original-source agreement with a finite caller rectangle. The admitted
    /// decoder measures values; container/user ROI provenance is not reconstructed.
    struct SourceCropReceipt: Sendable {
        let source: SourceSpoolReceipt
        let decoder: DolbyDecoderStream.Receipt
        let independentSourceFrameAssociationVerified = true
        let originalSourceAndCallerCropAgreementVerified = true
        let independentSourceROIProvenanceVerified = false
        let independentSampleValuesVerified = false
        let editedPictureSemanticsVerified = false
    }
    /// Original container declarations, not independently decoded codec geometry.
    struct SourceVideoReceipt: Sendable {
        let source: SourceSpoolReceipt
        let declarations: CompanionOriginalAuditCheck.Declarations
        let effectiveDisplayDeclarations: [UInt64?]
        let originalVideoDeclarationsBoundToSource = true
        let independentSourceFrameAssociationVerified = false
        let independentSourceROIProvenanceVerified = false
        let independentSampleValuesVerified = false
        let editedPictureSemanticsVerified = false
    }
    /// Joint source declarations and fixed-decoder caller-crop observations.
    /// Raster equality is a comparison, never container/user coordinate provenance.
    struct SourceVideoCropReceipt: Sendable {
        let source: SourceSpoolReceipt
        let decoder: DolbyDecoderStream.Receipt
        let declarations: CompanionOriginalAuditCheck.Declarations
        let effectiveDisplayDeclarations: [UInt64?]
        let originalVideoDeclarationsBoundToSource = true
        let independentSourceFrameAssociationVerified = true
        let originalSourceAndCallerCropAgreementVerified = true
        let independentSourceROIProvenanceVerified = false
        let independentSampleValuesVerified = false
        let editedPictureSemanticsVerified = false
        var declaredPixelsEqualDecoderCodedPixels: Bool {
            declarations.width == UInt64(decoder.geometry.width) && declarations.height == UInt64(decoder.geometry.height)
        }
        var declaredPixelsEqualDecoderCodecVisiblePixels: Bool {
            declarations.width == UInt64(decoder.geometry.width-decoder.geometry.crop[0]-decoder.geometry.crop[1]) &&
            declarations.height == UInt64(decoder.geometry.height-decoder.geometry.crop[2]-decoder.geometry.crop[3])
        }
    }
    /// Explicit source-only prerequisite. Existing narrower source/decoder APIs
    /// neither acquire these facts nor change their admission subset.
    static func spoolOriginalSourceVideoDeclarations(source: URL, in directory: URL,
        limits: DolbyAssociationSpool.Limits = .init()) async throws -> SourceVideoReceipt {
        let result = try await sourceWork(source: source, in: directory, limits: limits, decoder: nil, declaredVideo: true)
        guard let declarations = result.2 else { throw failure() }
        return try .init(source: result.0, declarations: declarations,
            effectiveDisplayDeclarations: declarations.displayWithMatroskaDefaults())
    }
    /// Configuration prefix declarations only; active VPS/PPS/slice use remains unverified.
    struct SourceSPSPrefixReceipt: Sendable {
        let source: SourceSpoolReceipt
        let geometry: CompanionOriginalSPSCheck.GeometryPrefix
        let originalConfigurationSPSPrefixBoundToSource = true
        let selectedPacketParameterSetNALsAbsent = true
        let activePictureParameterSetSelectionVerified = false
        let completeSPSConformanceVerified = false
        let independentSourceFrameAssociationVerified = false
        let independentSourceROIProvenanceVerified = false
        let independentSampleValuesVerified = false
        let editedPictureSemanticsVerified = false
    }
    /// Caller owns explicit source/folder access and retains it on shared uncertainty.
    /// No decoder or source raster-to-picture origin mapping is invoked.
    static func spoolOriginalSourceSPSGeometryPrefix(source: URL, in directory: URL,
        limits: DolbyAssociationSpool.Limits = .init()) async throws -> SourceSPSPrefixReceipt {
        let result = try await sourceWork(source: source, in: directory, limits: limits,
            decoder: nil, sourceSPSPrefix: true)
        guard let geometry = result.3 else { throw failure() }
        return .init(source: result.0, geometry: geometry)
    }
    struct SourceCodingTreePrefixReceipt: Sendable {
        let source: SourceSpoolReceipt
        let codingTree: CompanionOriginalSPSCheck.CodingTreePrefix
        let originalCodingTreePrefixBoundToSource = true
        let selectedPacketParameterSetNALsAbsent = true
        let completeSPSConformanceVerified = false
        let activePictureParameterSetSelectionVerified = false
        let independentSourceFrameAssociationVerified = false
        let independentSourceROIProvenanceVerified = false
        let independentSampleValuesVerified = false
        let editedPictureSemanticsVerified = false
    }
    /// Caller holds explicit original-source/private-spool access through the existing
    /// source worker and retains it on shared uncertainty. No decoder or controller.
    static func spoolOriginalSourceCodingTreePrefix(source: URL, in directory: URL,
        limits: DolbyAssociationSpool.Limits = .init()) async throws -> SourceCodingTreePrefixReceipt {
        let result = try await sourceWork(source: source, in: directory, limits: limits,
                                         decoder: nil, codingTreePrefix: true)
        guard let codingTree = result.6 else { throw failure() }
        return .init(source: result.0, codingTree: codingTree)
    }
    struct SourceSegmentPrefixReceipt: Sendable {
        let source: SourceSpoolReceipt
        let segments: CompanionOriginalPacketCheck.SegmentReadback
        let originalVCLSegmentPrefixesBoundToSource = true
        let selectedPacketParameterSetNALsAbsent = true
        let completeSliceAndParameterConformanceVerified = false
        let pictureGroupingVerified = false
        let activePictureParameterSetSelectionVerified = false
        let independentSourceFrameAssociationVerified = false
        let independentSourceROIProvenanceVerified = false
        let independentSampleValuesVerified = false
        let editedPictureSemanticsVerified = false
    }
    /// Caller retains explicit source/private-spool access on shared uncertainty.
    /// Matching one segment prefix per packet is not a complete picture association.
    static func spoolOriginalSourceSegmentPrefixes(source: URL, in directory: URL,
        limits: DolbyAssociationSpool.Limits = .init()) async throws -> SourceSegmentPrefixReceipt {
        let result = try await sourceWork(source: source, in: directory, limits: limits,
                                         decoder: nil, segmentPrefixes: true)
        guard let segments = result.7 else { throw failure() }
        return .init(source: result.0, segments: segments)
    }
    struct SourceParameterReferencesReceipt: Sendable {
        let source: SourceSpoolReceipt
        let references: CompanionOriginalSPSCheck.ParameterReferences
        let originalParameterReferencePrefixesBoundToSource = true
        let selectedPacketParameterSetNALsAbsent = true
        let activePictureParameterSetSelectionVerified = false
        let completeParameterSetConformanceVerified = false
        let independentSourceFrameAssociationVerified = false
        let independentSourceROIProvenanceVerified = false
        let independentSampleValuesVerified = false
        let editedPictureSemanticsVerified = false
    }
    /// Explicit caller access/retention; configuration references, not slice activation.
    static func spoolOriginalSourceParameterReferences(source: URL, in directory: URL,
        limits: DolbyAssociationSpool.Limits = .init()) async throws -> SourceParameterReferencesReceipt {
        let result = try await sourceWork(source: source, in: directory, limits: limits,
            decoder: nil, parameterReferences: true)
        guard let references = result.4 else { throw failure() }
        return .init(source: result.0, references: references)
    }
    struct SourceVCLReferencesReceipt: Sendable {
        let source: SourceSpoolReceipt
        let parameters: CompanionOriginalSPSCheck.ParameterReferences
        let vcl: CompanionOriginalPacketCheck.VCLSummary
        let originalFirstSlicePPSPrefixesBoundToSource = true
        let selectedPacketParameterSetNALsAbsent = true
        let activePictureParameterSetSelectionVerified = false
        let completeSliceAndParameterConformanceVerified = false
        let independentSourceFrameAssociationVerified = false
        let independentSourceROIProvenanceVerified = false
        let independentSampleValuesVerified = false
        let editedPictureSemanticsVerified = false
    }
    /// Caller holds explicit source/spool access and retention on shared uncertainty.
    static func spoolOriginalSourceVCLReferences(source: URL, in directory: URL,
        limits: DolbyAssociationSpool.Limits = .init()) async throws -> SourceVCLReferencesReceipt {
        let result = try await sourceWork(source: source, in: directory, limits: limits,
            decoder: nil, vclReferences: true)
        guard let vcl = result.5 else { throw failure() }
        return .init(source: result.0, parameters: vcl.parameters, vcl: vcl.summary)
    }
    /// Joint original prefix references and settled fixed-decoder caller crop.
    /// Geometry comparisons do not establish active selection or coordinate origins.
    struct SourceParameterCropReceipt: Sendable {
        let source: SourceSpoolReceipt
        let decoder: DolbyDecoderStream.Receipt
        let declarations: CompanionOriginalAuditCheck.Declarations
        let effectiveDisplayDeclarations: [UInt64?]
        let parameters: CompanionOriginalSPSCheck.ParameterReferences
        let vcl: CompanionOriginalPacketCheck.VCLSummary
        let originalVideoDeclarationsBoundToSource = true
        let originalFirstSlicePPSPrefixesBoundToSource = true
        let selectedPacketParameterSetNALsAbsent = true
        let independentSourceFrameAssociationVerified = true
        let originalSourceAndCallerCropAgreementVerified = true
        let activePictureParameterSetSelectionVerified = false
        let completeSliceAndParameterConformanceVerified = false
        let independentSourceROIProvenanceVerified = false
        let independentSampleValuesVerified = false
        let editedPictureSemanticsVerified = false
        var sourceSPSPrefixEqualsDecoderCodedGeometry: Bool {
            parameters.geometry.codedWidth == decoder.geometry.width &&
            parameters.geometry.codedHeight == decoder.geometry.height
        }
        var sourceSPSPrefixEqualsDecoderConformanceWindow: Bool {
            sourceSPSPrefixEqualsDecoderCodedGeometry && parameters.geometry.conformanceCrop == decoder.geometry.crop
        }
    }
    private struct DecoderRequest: Sendable {
        var profile: DolbyDecoderStream.Profile = .metadata
        let tool: DolbyDecoderProcess.Tool
        let threads: Int
        let timeout: Double
        var cropRequest: DolbyDecoderStream.CropRequest? = nil
    }
    /// Unused development association. Caller owns explicit empty private folder
    /// and source access; this establishes no release or edited-picture admission.
    static func associateOriginalFrames(source: URL, in directory: URL, tool: DolbyDecoderProcess.Tool,
                                        threads: Int = 4, timeout: Double = 120,
                                        limits: DolbyAssociationSpool.Limits = .init()) async throws -> SourceFrameReceipt {
        guard [1,4].contains(threads), timeout.isFinite, timeout > 0, timeout <= 120 else { throw failure() }
        let result=try await sourceWork(source:source,in:directory,limits:limits,
                                       decoder:.init(tool:tool,threads:threads,timeout:timeout))
        guard let decoder=result.1 else { throw failure() }
        return .init(source:result.0,decoder:decoder)
    }
    /// Distinct development sample path on the same pinned source/open-store worker.
    /// Caller owns folder/access; no resource controller, edits or release action.
    static func associateOriginalSamples(source: URL, in directory: URL, tool: DolbyDecoderProcess.Tool,
                                         threads: Int = 4, timeout: Double = 120,
                                         limits: DolbyAssociationSpool.Limits = .init()) async throws -> SourceSampleReceipt {
        guard [1,4].contains(threads), timeout.isFinite, timeout > 0, timeout <= 120 else { throw failure() }
        let result = try await sourceWork(source: source, in: directory, limits: limits,
            decoder: .init(profile: .baseSamples, tool: tool, threads: threads, timeout: timeout))
        guard let decoder = result.1 else { throw failure() }
        return .init(source: result.0, decoder: decoder)
    }
    /// Distinct development crop composition on the existing pinned source/open
    /// database worker. Caller owns the explicit folder and required access.
    static func associateOriginalCrops(source: URL, in directory: URL, tool: DolbyDecoderProcess.Tool,
                                       request: DolbyDecoderStream.CropRequest, threads: Int = 4,
                                       timeout: Double = 120, limits: DolbyAssociationSpool.Limits = .init()) async throws -> SourceCropReceipt {
        guard [1,4].contains(threads), timeout.isFinite, timeout > 0, timeout <= 120 else { throw failure() }
        let result = try await sourceWork(source: source, in: directory, limits: limits,
            decoder: .init(profile: .cropSamples, tool: tool, threads: threads, timeout: timeout, cropRequest: request))
        guard let decoder = result.1 else { throw failure() }
        return .init(source: result.0, decoder: decoder)
    }
    /// Distinct joint readback on the same pinned source/open-store worker.
    /// No source raster-to-decoder origin mapping or sample-aspect default follows.
    static func associateOriginalVideoCrops(source: URL, in directory: URL, tool: DolbyDecoderProcess.Tool,
        request: DolbyDecoderStream.CropRequest, threads: Int = 4, timeout: Double = 120,
        limits: DolbyAssociationSpool.Limits = .init()) async throws -> SourceVideoCropReceipt {
        guard [1,4].contains(threads), timeout.isFinite, timeout > 0, timeout <= 120 else { throw failure() }
        let result = try await sourceWork(source:source,in:directory,limits:limits,
            decoder:.init(profile:.cropSamples,tool:tool,threads:threads,timeout:timeout,cropRequest:request),declaredVideo:true)
        guard let decoder=result.1, let video=result.2 else { throw failure() }
        return try .init(source:result.0,decoder:decoder,declarations:video,
            effectiveDisplayDeclarations:video.displayWithMatroskaDefaults())
    }
    /// Caller holds explicit source/spool access and retention. Same worker/store;
    /// full parameter/slice conformance and active picture selection remain false.
    static func associateOriginalParameterCrops(source: URL, in directory: URL, tool: DolbyDecoderProcess.Tool,
        request: DolbyDecoderStream.CropRequest, threads: Int = 4, timeout: Double = 120,
        limits: DolbyAssociationSpool.Limits = .init()) async throws -> SourceParameterCropReceipt {
        guard [1,4].contains(threads), timeout.isFinite, timeout > 0, timeout <= 120 else { throw failure() }
        let result = try await sourceWork(source: source, in: directory, limits: limits,
            decoder: .init(profile: .cropSamples, tool: tool, threads: threads, timeout: timeout, cropRequest: request),
            declaredVideo: true, vclReferences: true)
        guard let decoder = result.1, let video = result.2, let vcl = result.5,
              vcl.summary.prefixes == decoder.frames else { throw failure() }
        return try .init(source: result.0, decoder: decoder, declarations: video,
            effectiveDisplayDeclarations: video.displayWithMatroskaDefaults(), parameters: vcl.parameters, vcl: vcl.summary)
    }
    struct SourceOwnershipFailure: CompanionUnsettledOwnership { var operationError: Error? = nil }
    /// Finite file admission rollback only; later component/deinit closes remain separate.
    struct FileAdmissionFailure: CompanionUnsettledOwnership {
        let operationError: Error
        let component: String?
        let closeStatus, closeErrno: Int32
        let reportedAfterActualClose: Bool
    }
    /// Source-only observations into an exclusive disposable database. Caller
    /// owns the empty private folder/access and retains it on uncertain close.
    /// Neither companion equality nor decoder association follows from this pass.
    static func spoolOriginalSource(source: URL, in directory: URL,
                                    limits: DolbyAssociationSpool.Limits = .init()) async throws -> SourceSpoolReceipt {
        try await sourceWork(source:source,in:directory,limits:limits,decoder:nil).0
    }
    private static func sourceWork(source: URL, in directory: URL, limits: DolbyAssociationSpool.Limits,
                                   decoder: DecoderRequest?, declaredVideo: Bool = false, sourceSPSPrefix: Bool = false, parameterReferences: Bool = false, vclReferences: Bool = false, codingTreePrefix: Bool = false, segmentPrefixes: Bool = false) async throws -> (SourceSpoolReceipt,DolbyDecoderStream.Receipt?,CompanionOriginalAuditCheck.Declarations?,CompanionOriginalSPSCheck.GeometryPrefix?,CompanionOriginalSPSCheck.ParameterReferences?,CompanionOriginalPacketCheck.VCLReadback?,CompanionOriginalSPSCheck.CodingTreePrefix?,CompanionOriginalPacketCheck.SegmentReadback?) {
        try Task.checkCancellation()
        let cancelled = Cancellation()
        #if DEBUG
        let boundary = testBoundary
        let decoderBoundary = DolbyDecoderProcess.testBoundary
        let spoolBoundary = DolbyAssociationSpool.testAdmissionBoundary
        #else
        let boundary = Boundary()
        let decoderBoundary = DolbyDecoderProcess.Boundary()
        let spoolBoundary = DolbyAssociationSpool.AdmissionBoundary()
        #endif
        let result: (SourceSpoolReceipt,DolbyDecoderStream.Receipt?,CompanionOriginalAuditCheck.Declarations?,CompanionOriginalSPSCheck.GeometryPrefix?,CompanionOriginalSPSCheck.ParameterReferences?,CompanionOriginalPacketCheck.VCLReadback?,CompanionOriginalSPSCheck.CodingTreePrefix?,CompanionOriginalPacketCheck.SegmentReadback?) = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue(label: "StaxRip.original-source-spool", qos: .userInitiated).async {
                    continuation.resume(with: Result {
                        try cancelled.check()
                        let file = try File(url: source, maximum: 1 << 40, boundary: boundary, checkpoint: cancelled.check)
                        let outcome = Result {
                            let hash = try file.hash(cancelled: cancelled, original: nil) { boundary.progress("source", $0) }
                            try file.check(source)
                            let view = ReadView(sourceBytes: file.bytes, source: { offset, count in
                                try cancelled.check()
                                guard offset >= 0, count >= 0, count <= 1 << 20,
                                      offset <= file.bytes, Int64(count) <= file.bytes - offset else { throw failure() }
                                boundary.originalTrackRead(offset, count)
                                return try file.read(offset: offset, count: count, cancelled: cancelled)
                            }, component: { _ in throw failure() }, checkpoint: cancelled.check)
                            let receipt = try DolbyAssociationSpool.withSpool(in: directory, sourceBytes: file.bytes,
                                                                            limits: limits, checkpoint: cancelled.check, admissionBoundary: spoolBoundary) { spool in
                                let track = try CompanionOriginalTrackCheck.readSource(view)
                                let video = declaredVideo ? try CompanionOriginalAuditCheck.sourceDeclarations(view, track: track) : nil
                                let references = parameterReferences ? try CompanionOriginalSPSCheck.readSourceReferences(view, track: track) : nil
                                let sps = sourceSPSPrefix ? try CompanionOriginalSPSCheck.readSource(view, track: track) : nil
                                let codingTree = codingTreePrefix ? try CompanionOriginalSPSCheck.readSourceCodingTreePrefix(view, track: track) : nil
                                var timing: (UInt64, Bool)?
                                let begin: (UInt64, Bool) throws -> Void = { scale, unknown in
                                    guard timing == nil else { throw failure() }; timing = (scale, unknown)
                                }
                                let vcl: CompanionOriginalPacketCheck.VCLReadback?
                                let segments: CompanionOriginalPacketCheck.SegmentReadback?
                                let packets: CompanionOriginalPacketCheck.Receipt
                                if segmentPrefixes {
                                    let actual = try CompanionOriginalPacketCheck.readSourceSegmentPrefixes(view, track: track,
                                        begin: begin, observe: { try spool.append($0) })
                                    segments = actual; vcl = nil; packets = actual.packets
                                } else if vclReferences {
                                    segments = nil
                                    let actual = try CompanionOriginalPacketCheck.readSourceVCLReferences(view, track: track,
                                        begin: begin, observe: { try spool.append($0) })
                                    vcl = actual; packets = actual.packets
                                } else {
                                    segments = nil; vcl = nil
                                    packets = try CompanionOriginalPacketCheck.readSource(view, track: track, begin: begin,
                                        observe: { try spool.append($0) }, refuseInBandParameterSets: sourceSPSPrefix || parameterReferences || codingTreePrefix)
                                }
                                _ = try spool.finishSourcePass(expected: .init(packets: packets.packets, rpus: packets.records))
                                guard let timing else { throw failure() }
                                var decoded: DolbyDecoderStream.Receipt?
                                if let decoder {
                                    try spool.startDecoderPass(profile: decoder.profile, cropRequest: decoder.cropRequest)
                                    // No second worker, nested async wait or closed-store adoption.
                                    let actual: DolbyDecoderStream.Receipt
                                    switch decoder.profile {
                                    case .metadata:
                                        actual = try DolbyDecoderProcess.runOwned(tool:decoder.tool,source:source,
                                            threads:decoder.threads,observe:{ try spool.acceptDecoderRow($0,track:track) },
                                            timeout:decoder.timeout,checkCancellation:cancelled.check,boundary:decoderBoundary)
                                    case .baseSamples:
                                        actual = try DolbyDecoderProcess.runOwnedSamples(tool:decoder.tool,source:source,
                                            threads:decoder.threads,observeSamples:{ try spool.acceptSampleObservation($0) },
                                            observe:{ try spool.acceptDecoderRow($0,track:track) },
                                            timeout:decoder.timeout,checkCancellation:cancelled.check,boundary:decoderBoundary)
                                    case .cropSamples:
                                        guard let request = decoder.cropRequest else { throw failure() }
                                        actual = try DolbyDecoderProcess.runOwnedCrops(tool:decoder.tool,source:source,
                                            request:request,threads:decoder.threads,observeCrops:{ try spool.acceptCropObservation($0) },
                                            observe:{ try spool.acceptDecoderRow($0,track:track) },
                                            timeout:decoder.timeout,checkCancellation:cancelled.check,boundary:decoderBoundary)
                                    }
                                    guard actual.source == SourceFingerprint(sha256:hash,byteCount:file.bytes),
                                          actual.configurationSHA256 == track.configurationSHA256,
                                          actual.packets == packets.packets, actual.frames == packets.packets else { throw failure() }
                                    try spool.finishDecoderPass(actual); decoded=actual
                                }
                                let finalHash = try file.hash(cancelled: cancelled, original: nil) { boundary.progress("source-recheck", $0) }
                                guard finalHash == hash else { throw failure() }
                                boundary.beforeFinal()
                                try file.check(source); try cancelled.check()
                                return (SourceSpoolReceipt(sourceID: file.id, sourceBytes: file.bytes, sourceSHA256: hash,
                                    track: track, packets: packets, timestampScale: timing.0, unknownSegment: timing.1),decoded,video,sps,references,vcl,codingTree,segments)
                            }
                            try file.check(source); try cancelled.check()
                            return receipt
                        }
                        // An uncertain actual close supersedes success or ordinary
                        // refusal. The caller must retain its owned folder/access.
                        let original: Error?
                        if case .failure(let error) = outcome { original = error } else { original = nil }
                        try file.closeChecked(operationError: original)
                        return try outcome.get()
                    })
                }
            }
        } onCancel: { cancelled.cancel() }
        try Task.checkCancellation(); return result
    }
    private enum Input: Sendable {
        case provided(Transaction.Contents), candidate(Transaction.Retention)
        var retention: Transaction.Retention {
            switch self { case .provided(let c): return c.retention; case .candidate(let r): return r }
        }
        var provided: Transaction.Contents? {
            if case .provided(let c) = self { return c }; return nil
        }
    }
    struct ReadView {
        let sourceBytes: Int64
        let source: (Int64, Int) throws -> Data
        let component: (String) throws -> Data
        let checkpoint: () throws -> Void
        var componentBytes: (String) throws -> Int64 = { _ in throw failure() }
        var componentRead: (String, Int64, Int) throws -> Data = { _, _, _ in throw failure() }
    }
    private static func settle(source: URL, stage: URL, contents: Transaction.Contents, originalTrack: Bool, originalPackets: Bool, originalIndex: Bool, originalAudit: Bool, metadataTool: CompanionMetadataProcess.Tool? = nil) async throws -> Receipt {
        try await settle(source: source, stage: stage, input: .provided(contents), originalTrack: originalTrack,
                         originalPackets: originalPackets, originalIndex: originalIndex, originalAudit: originalAudit, metadataTool: metadataTool)
    }
    private static func settle(source: URL, stage: URL, input: Input, originalTrack: Bool, originalPackets: Bool,
                               originalIndex: Bool, originalAudit: Bool, metadataTool: CompanionMetadataProcess.Tool? = nil) async throws -> Receipt {
        try Task.checkCancellation()
        let cancelled = Cancellation()
        #if DEBUG
        let boundary = testBoundary
        let metadataBoundary = CompanionMetadataProcess.testBoundary
        #else
        let boundary = Boundary()
        let metadataBoundary = CompanionMetadataProcess.Boundary()
        #endif
        let result: Receipt = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue(label: "StaxRip.companion-disk-check", qos: .userInitiated).async {
                    continuation.resume(with: Result {
                        try check(source: source, stage: stage, input: input, originalTrack: originalTrack, originalPackets: originalPackets, originalIndex: originalIndex, originalAudit: originalAudit, metadataTool: metadataTool, metadataBoundary: metadataBoundary, cancelled: cancelled, boundary: boundary)
                    })
                }
            }
        } onCancel: { cancelled.cancel() }
        try Task.checkCancellation(); return result
    }
    private static func check(source url: URL, stage urlStage: URL, input: Input,
                              originalTrack: Bool, originalPackets: Bool, originalIndex: Bool, originalAudit: Bool, metadataTool: CompanionMetadataProcess.Tool?, metadataBoundary: CompanionMetadataProcess.Boundary, cancelled: Cancellation, boundary: Boundary) throws -> Receipt {
        try cancelled.check()
        let source = try File(url: url, maximum: 1 << 40, boundary: boundary, checkpoint: cancelled.check), directory = try Directory(urlStage)
        let limits = input.retention.limits, expected = Set(limits.keys), provided = input.provided
        guard try directory.names() == expected else { throw failure() }
        if let c = provided {
            guard source.id == c.sourceID, directory.id == c.stageID, source.bytes == c.sourceBytes,
                  (1...2_000_000).contains(c.packets), (1...2_000_000).contains(c.records),
                  (0...4_000_000_000_000).contains(c.enhancementNALs), c.members.count == expected.count,
                  Set(c.members.map(\.name)) == expected else { throw failure() }
        }
        let sourceHash = try source.hash(cancelled: cancelled, original: nil, progress: { count in
            #if DEBUG
            boundary.progress("source", count)
            #endif
        })
        if let c = provided { guard sourceHash == c.sourceSHA256 else { throw failure() } }
        var opened: [String: File] = [:], actualMembers: [ResultSetStaging.Member] = []
        defer { withExtendedLifetime((source, directory, opened)) {} }
        for name in expected.sorted() {
            try cancelled.check()
            guard let maximum = limits[name] else { throw failure() }
            let file = try File(name: name, directory: directory.fd, maximum: maximum, boundary: boundary, checkpoint: cancelled.check)
            opened[name] = file
            if let c = provided {
                guard let member = c.members.first(where: { $0.name == name }), (1...maximum).contains(member.byteCount),
                      file.bytes == member.byteCount else { throw failure() }
            }
            let original = name == "original-container.mkv" ? source : nil
            if original != nil { guard file.bytes == source.bytes else { throw failure() } }
            let digest = try file.hash(cancelled: cancelled, original: original, progress: { count in
                #if DEBUG
                boundary.progress(name, count)
                #endif
            })
            if let c = provided {
                guard let member = c.members.first(where: { $0.name == name }), file.bytes == member.byteCount,
                      digest == member.sha256 else { throw failure() }
            }
            actualMembers.append(.init(name: name, byteCount: file.bytes, sha256: digest))
        }
        let contents: Transaction.Contents
        if let c = provided { contents = c }
        else {
            guard let manifest = opened["manifest.json"], manifest.bytes <= 1 << 20 else { throw failure() }
            let bytes = try manifest.read(offset: 0, count: Int(manifest.bytes), cancelled: cancelled)
            #if DEBUG
            boundary.originalComponentRead("manifest.json", 0, Int(manifest.bytes))
            #endif
            try cancelled.check()
            // Only bootstrap bounded count claims. D111 then admits the whole
            // exact manifest schema and D110 reconstructs those counts from source.
            let claims = try CompanionArchiveJSON.object(bytes, maximum: 1 << 20)
            contents = .init(retention: input.retention, sourceID: source.id, stageID: directory.id,
                sourceBytes: source.bytes, sourceSHA256: sourceHash,
                packets: Int64(try CompanionArchiveJSON.unsigned(claims, "packets", 1...2_000_000)),
                records: Int64(try CompanionArchiveJSON.unsigned(claims, "records", 1...2_000_000)),
                enhancementNALs: Int64(try CompanionArchiveJSON.unsigned(claims, "enhancement_nals", 0...4_000_000_000_000)),
                members: actualMembers)
        }
        let track: CompanionOriginalTrackCheck.Receipt?
        let packets: CompanionOriginalPacketCheck.Receipt?
        let index: CompanionOriginalIndexCheck.Receipt?
        let audit: CompanionOriginalAuditCheck.Receipt?
        let metadata: CompanionOriginalMetadataCheck.Receipt?
        if originalTrack {
            let view = ReadView(sourceBytes: source.bytes, source: { offset, count in
                guard offset >= 0, count >= 0, count <= 1 << 20, offset <= source.bytes,
                      Int64(count) <= source.bytes - offset else { throw failure() }
                let data = try source.read(offset: offset, count: count, cancelled: cancelled)
                #if DEBUG
                boundary.originalTrackRead(offset, count)
                #endif
                try cancelled.check(); return data
            }, component: { name in
                guard ["original-track-entry-payload.bin", "hevc-configuration.bin"].contains(name),
                      let file = opened[name], file.bytes <= 1 << 20 else { throw failure() }
                return try file.read(offset: 0, count: Int(file.bytes), cancelled: cancelled)
            }, checkpoint: { try cancelled.check() }, componentBytes: { name in
                guard ["original-rpu.bin", "rpu-index.jsonl", "manifest.json", "source-audit.jsonl"].contains(name), let file = opened[name] else { throw failure() }
                return file.bytes
            }, componentRead: { name, offset, count in
                guard ["original-rpu.bin", "rpu-index.jsonl", "manifest.json", "source-audit.jsonl"].contains(name), let file = opened[name], offset >= 0,
                      count >= 0, count <= 1 << 20, offset <= file.bytes,
                      Int64(count) <= file.bytes - offset else { throw failure() }
                let data = try file.read(offset: offset, count: count, cancelled: cancelled)
                #if DEBUG
                boundary.originalComponentRead(name, offset, count)
                #endif
                try cancelled.check(); return data
            })
            let selected = try CompanionOriginalTrackCheck.read(view)
            track = selected
            if originalAudit {
                let checked = try CompanionOriginalAuditCheck.read(view, track: selected, contents: contents)
                audit = checked; index = checked.index; packets = checked.index.packets
                if let tool = metadataTool {
                    metadata = try CompanionOriginalMetadataCheck.read(view, source: url, contents: contents, audit: checked, tool: tool, boundary: metadataBoundary)
                } else { metadata = nil }
            } else if originalIndex {
                metadata = nil; audit = nil
                let checked = try CompanionOriginalIndexCheck.read(view, track: selected, contents: contents)
                index = checked; packets = checked.packets
            } else if originalPackets {
                metadata = nil; audit = nil; index = nil
                let result = try CompanionOriginalPacketCheck.read(view, track: selected)
                guard result.packets == contents.packets, result.records == contents.records,
                      result.enhancementNALs == contents.enhancementNALs else { throw failure() }
                packets = result
            } else { packets = nil; index = nil; audit = nil; metadata = nil }
        } else { track = nil; packets = nil; index = nil; audit = nil; metadata = nil }
        #if DEBUG
        boundary.beforeFinal()
        #endif
        try cancelled.check(); try source.check(url); try directory.check()
        guard try directory.names() == expected else { throw failure() }
        for (name, file) in opened { try cancelled.check(); try file.check(name: name, directory: directory.fd) }
        try cancelled.check()
        return .init(contents: contents, fullContainerMatchesOriginalBytes: contents.retention == .entireContainer, originalTrack: track, originalPackets: packets, originalIndex: index, originalAudit: audit, originalMetadata: metadata)
    }
    private static func same(_ a: stat, _ b: stat) -> Bool {
        Transaction.FileID(a) == Transaction.FileID(b) && a.st_mode == b.st_mode && a.st_uid == b.st_uid &&
            a.st_nlink == b.st_nlink && a.st_size == b.st_size &&
            a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec && a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec &&
            a.st_ctimespec.tv_sec == b.st_ctimespec.tv_sec && a.st_ctimespec.tv_nsec == b.st_ctimespec.tv_nsec
    }
    private final class File {
        let fd: Int32, initial: stat
        private var closed = false
        var id: Transaction.FileID { .init(initial) }
        var bytes: Int64 { initial.st_size }
        init(url: URL, maximum: Int64, boundary: Boundary = .init(), checkpoint: () throws -> Void = {}) throws {
            guard url.isFileURL, !url.path.utf8.contains(0) else { throw failure() }
            var descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
            guard descriptor >= 0 else { throw failure() }
            var info = stat(), path = stat()
            do {
                #if DEBUG
                try boundary.fileOpened(nil)
                #endif
                try checkpoint()
                guard fstat(descriptor, &info) == 0, lstat(url.path, &path) == 0,
                      info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), (1...maximum).contains(info.st_size), same(info, path) else { throw failure() }
            } catch {
                try Self.rollback(&descriptor, component: nil, cause: error, boundary: boundary)
                throw error
            }
            fd = descriptor; initial = info
        }
        init(name: String, directory: Int32, maximum: Int64, boundary: Boundary = .init(), checkpoint: () throws -> Void = {}) throws {
            // Name comes only from the fixed exact membership/receipt schema above.
            var descriptor = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
            guard descriptor >= 0 else { throw failure() }
            var info = stat(), path = stat()
            do {
                #if DEBUG
                try boundary.fileOpened(name)
                #endif
                try checkpoint()
                guard fstat(descriptor, &info) == 0, fstatat(directory, name, &path, AT_SYMLINK_NOFOLLOW) == 0,
                      info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), info.st_uid == geteuid(),
                      info.st_mode & 0o7777 == 0o600, info.st_nlink == 1, (1...maximum).contains(info.st_size), same(info, path) else { throw failure() }
            } catch {
                try Self.rollback(&descriptor, component: name, cause: error, boundary: boundary)
                throw error
            }
            fd = descriptor; initial = info
        }
        private static func rollback(_ descriptor: inout Int32, component: String?, cause: Error, boundary: Boundary) throws {
            let number = descriptor; descriptor = -1 // Consume before close; never retry.
            let status = Darwin.close(number), code: Int32 = status == 0 ? 0 : errno
            #if DEBUG
            boundary.admissionClosed(component, status, code)
            let reported = status == 0 && boundary.refuseAdmissionClose(component)
            #else
            let reported = false
            #endif
            if status != 0 || reported {
                throw FileAdmissionFailure(operationError: cause, component: component,
                    closeStatus: status, closeErrno: code, reportedAfterActualClose: reported)
            }
        }
        deinit { if !closed { Darwin.close(fd) } }
        func closeChecked(operationError: Error? = nil) throws {
            guard !closed else { throw SourceOwnershipFailure(operationError: operationError) }
            closed = true // Never retry a possibly reused descriptor after close failure.
            guard Darwin.close(fd) == 0 else { throw SourceOwnershipFailure(operationError: operationError) }
        }
        func check(_ url: URL) throws {
            var info = stat(), path = stat()
            guard fstat(fd, &info) == 0, lstat(url.path, &path) == 0, same(initial, info), same(initial, path) else { throw failure() }
        }
        func check(name: String, directory: Int32) throws {
            var info = stat(), path = stat()
            guard fstat(fd, &info) == 0, fstatat(directory, name, &path, AT_SYMLINK_NOFOLLOW) == 0,
                  same(initial, info), same(initial, path) else { throw failure() }
        }
        func read(offset: Int64, count: Int, cancelled: Cancellation) throws -> Data {
            var data = Data(count: count), completed = 0
            while completed < count {
                try cancelled.check()
                let n = data.withUnsafeMutableBytes { p in pread(fd, p.baseAddress!.advanced(by: completed), count - completed, offset + Int64(completed)) }
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { throw failure() }; completed += n; try cancelled.check()
            }
            return data
        }
        func hash(cancelled: Cancellation, original: File?, progress: (Int64) -> Void) throws -> String {
            var hasher = SHA256(), offset: Int64 = 0
            while offset < bytes {
                try cancelled.check()
                let count = Int(min(1 << 20, bytes - offset)), data = try read(offset: offset, count: count, cancelled: cancelled)
                if let original { guard try original.read(offset: offset, count: count, cancelled: cancelled) == data else { throw failure() } }
                hasher.update(data: data); offset += Int64(count); progress(offset); try cancelled.check()
            }
            return DolbyInspection.hex(hasher.finalize())
        }
    }
    private final class Directory {
        let url: URL, fd: Int32, initial: stat
        var id: Transaction.FileID { .init(initial) }
        init(_ url: URL) throws {
            guard url.isFileURL, !url.path.utf8.contains(0) else { throw failure() }
            let descriptor = Darwin.open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard descriptor >= 0 else { throw failure() }
            var info = stat(), path = stat()
            guard fstat(descriptor, &info) == 0, lstat(url.path, &path) == 0, info.st_uid == geteuid(),
                  info.st_mode & 0o7777 == 0o700, same(info, path) else { Darwin.close(descriptor); throw failure() }
            self.url = url; fd = descriptor; initial = info
        }
        deinit { Darwin.close(fd) }
        func check() throws {
            var info = stat(), path = stat()
            guard fstat(fd, &info) == 0, lstat(url.path, &path) == 0, same(initial, info), same(initial, path) else { throw failure() }
        }
        func names() throws -> Set<String> {
            let copy = fcntl(fd, F_DUPFD_CLOEXEC, 0)
            guard copy >= 0 else { throw failure() }
            guard let entries = fdopendir(copy) else { Darwin.close(copy); throw failure() }
            defer { closedir(entries) }
            rewinddir(entries) // Duplicate descriptors share directory position.
            var result: Set<String> = []
            while true {
                errno = 0
                guard let entry = readdir(entries) else { guard errno == 0 else { throw failure() }; break }
                let count = Int(entry.pointee.d_namlen)
                guard (1...128).contains(count) else { throw failure() }
                let name = withUnsafePointer(to: &entry.pointee.d_name) {
                    $0.withMemoryRebound(to: UInt8.self, capacity: count) { String(decoding: UnsafeBufferPointer(start: $0, count: count), as: UTF8.self) }
                }
                if name == "." || name == ".." { continue }
                guard result.count < 16, result.insert(name).inserted else { throw failure() }
            }
            return result
        }
    }
}
