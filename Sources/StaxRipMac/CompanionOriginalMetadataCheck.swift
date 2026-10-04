import Foundation

/// Actual fresh-reader/stored-audit comparison after independent source framing.
/// Its internal result is transient until D108 final pinned observations settle.
enum CompanionOriginalMetadataCheck {
    struct Receipt: Sendable {
        let fresh: CompanionMetadataStream.Receipt
        let compactMetadataSummaryMatchesOriginalSource = true
        let originalPacketRPUSemanticsVerified = true
        let originalComponentsMatchSource = true
        let decodedFrameAssociation = "not-established"
        let immutableSnapshot = false
        let stableImporter = false
        let persistedProducerBinding = false
    }
    private static func refused() -> NativeExportError { .invalid("Original companion metadata comparison refused. No complete original component result.") }
    static func read(_ view: CompanionDiskCheck.ReadView, source: URL,
                     contents: OriginalCompanionTransaction.Contents, audit: CompanionOriginalAuditCheck.Receipt,
                     tool: CompanionMetadataProcess.Tool, boundary: CompanionMetadataProcess.Boundary) throws -> Receipt {
        try view.checkpoint()
        let rows = try CompanionOriginalIndexCheck.Rows(view, fixed:.audit)
        var mismatch = false
        // A semantic mismatch never grants cleanup while a reader is live. Keep
        // draining its bounded validated stream, join, then refuse. Cancellation
        // still propagates promptly to the same owned process control loop.
        let fresh = try CompanionMetadataProcess.runOwned(tool:tool, source:source, observe:{ data in
            try view.checkpoint()
            let actual = try CompanionArchiveJSON.object(data, maximum:65_535, auditNullable:true)
            if try CompanionArchiveJSON.string(actual,"kind") == "resources" { return }
            guard !mismatch else { return }
            do {
                guard let stored = try rows.next(), stored == actual else { mismatch = true; return }
            } catch is CancellationError { throw CancellationError() }
            catch { mismatch = true }
        }, timeout:120, checkCancellation:view.checkpoint, boundary:boundary)
        try view.checkpoint()
        let packets = audit.index.packets
        guard !mismatch, try rows.next() == nil,
              fresh.source.byteCount == contents.sourceBytes, fresh.source.sha256 == contents.sourceSHA256,
              fresh.packets == packets.packets, fresh.records == packets.records,
              fresh.enhancementNALs == packets.enhancementNALs,
              fresh.peakRecordBytes == packets.peakRecordBytes,
              fresh.packetSequenceSHA256 == packets.packetSequenceSHA256 else { throw refused() }
        try view.checkpoint(); return .init(fresh:fresh)
    }
}
