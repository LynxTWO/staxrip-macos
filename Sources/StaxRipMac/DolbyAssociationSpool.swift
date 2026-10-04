import Foundation
import Darwin
import SQLite3

/// Unused synchronous source-observation storage. The caller owns the private
/// directory and worker. Stored rows are not independent association evidence.
final class DolbyAssociationSpool {
    typealias Packet = CompanionOriginalPacketCheck.Packet
    typealias RPU = CompanionOriginalPacketCheck.RPU
    enum Failure: Error { case refused, storageFull }
    struct OwnershipFailure: CompanionUnsettledOwnership {}
    struct Counts: Equatable { let packets: Int64, rpus: Int64 }
    struct Limits: Sendable {
        var pages = 131_072 // 512 MiB at the required 4096-byte page size.
        var records: Int64 = 2_000_000
    }
    static let name = "association.sqlite"
    private let directory: URL, folderFD: Int32, fileFD: Int32, folderID: stat, fileID: stat
    private let canonicalFolder: String
    private let sourceBytes: Int64, limits: Limits, checkpoint: () throws -> Void
    private var db: OpaquePointer?
    private var packets: Int64 = 0, rpus: Int64 = 0, archiveOffset: Int64 = 0, lastNAL: Int64 = -1
    private var sealed = false, poisoned = false
    private var decoderStarted = false, decoderBegan = false, decoderComplete = false
    private var decoderPackets: Int64 = 0, decoderFrames: Int64 = 0
    private var decoderTimeBase = [Int]()
    private var decoderProfile: DolbyDecoderStream.Profile = .metadata
    private var sampleObservations: Int64 = 0
    private var pendingSample: (index: Int64, packet: Int64)?
    private let ownerThread = pthread_self()
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// Exclusively creates a fixed file; never adopts, removes or publishes one.
    /// Every return closes SQLite and owned pins. Close uncertainty is retained.
    static func withSpool<T>(in directory: URL, sourceBytes: Int64, limits: Limits = .init(),
                             checkpoint: @escaping () throws -> Void = {},
                             body: (DolbyAssociationSpool) throws -> T) throws -> T {
        let spool = try DolbyAssociationSpool(directory, sourceBytes: sourceBytes, limits: limits, checkpoint: checkpoint)
        let result = Result { let value = try body(spool); try spool.operation(false) {}; return value }
        try spool.close()
        return try result.get()
    }
    private init(_ directory: URL, sourceBytes: Int64, limits: Limits, checkpoint: @escaping () throws -> Void) throws {
        try checkpoint()
        guard directory.isFileURL, (1...(1 << 40)).contains(sourceBytes),
              (8...131_072).contains(limits.pages), (1...2_000_000).contains(limits.records) else { throw Failure.refused }
        let folder = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard folder >= 0 else { throw Failure.refused }
        var fs = stat()
        guard fstat(folder, &fs) == 0, fs.st_uid == geteuid(), fs.st_mode & 0o7777 == 0o700 else {
            Darwin.close(folder); throw Failure.refused
        }
        // SQLite NOFOLLOW refuses symlinked ancestors such as macOS /var.
        // F_GETPATH comes from the already owned directory descriptor; retain
        // both the caller path and this concrete path through final checks.
        var path = [CChar](repeating:0,count:Int(MAXPATHLEN))
        guard fcntl(folder,F_GETPATH,&path) == 0 else { Darwin.close(folder); throw Failure.refused }
        let concreteFolder = String(cString:path)
        do {
            guard try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty else { throw Failure.refused }
        } catch { Darwin.close(folder); throw error }
        let fd = openat(folder, Self.name, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { Darwin.close(folder); throw Failure.refused }
        var statFile = stat()
        guard fstat(fd, &statFile) == 0, statFile.st_nlink == 1, statFile.st_mode & 0o7777 == 0o600 else {
            Darwin.close(fd); Darwin.close(folder); throw Failure.refused
        }
        self.directory = directory; folderFD = folder; fileFD = fd; folderID = fs; fileID = statFile
        canonicalFolder = concreteFolder
        self.sourceBytes = sourceBytes; self.limits = limits; self.checkpoint = checkpoint
        do {
            try identities()
            let status = sqlite3_open_v2(canonicalFolder+"/"+Self.name, &db,
                                         SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX | SQLITE_OPEN_NOFOLLOW, nil)
            try checked(status)
            try sql("PRAGMA page_size=4096")
            try sql("PRAGMA journal_mode=MEMORY")
            guard try statement("PRAGMA journal_mode", { s in
                guard sqlite3_step(s) == SQLITE_ROW else { return false }; return try text(s,0) == "memory"
            }) else { throw Failure.refused }
            try sql("PRAGMA synchronous=OFF") // Disposable observations, not crash-durable recovery.
            try sql("PRAGMA temp_store=MEMORY")
            try sql("PRAGMA cache_size=-8192")
            try sql("PRAGMA mmap_size=0")
            try sql("PRAGMA max_page_count=\(limits.pages)")
            guard try scalar("PRAGMA page_size") == 4096,
                  try scalar("PRAGMA max_page_count") == Int64(limits.pages) else { throw Failure.refused }
            try sql("CREATE TABLE packets(idx INTEGER PRIMARY KEY, pts INTEGER NOT NULL, input INTEGER NOT NULL, block INTEGER NOT NULL, bytes INTEGER NOT NULL, hash TEXT NOT NULL, duration TEXT, invisible INTEGER NOT NULL, keyframe INTEGER, discardable INTEGER)")
            try sql("CREATE TABLE rpus(idx INTEGER PRIMARY KEY, packet INTEGER NOT NULL, nal INTEGER NOT NULL, pts INTEGER NOT NULL, input INTEGER NOT NULL, archive INTEGER NOT NULL, bytes INTEGER NOT NULL, hash TEXT NOT NULL)")
            try identities(); try checkpoint()
        } catch {
            // Even a failed constructor retains its exclusively created partial file.
            let original = error
            try close(); throw original
        }
    }
    private func checked(_ code: Int32) throws {
        guard code == SQLITE_OK || code == SQLITE_DONE || code == SQLITE_ROW else {
            poisoned = true
            if code & 0xff == SQLITE_FULL { throw Failure.storageFull }
            throw Failure.refused
        }
    }
    private func statement<T>(_ text: String, _ body: (OpaquePointer) throws -> T) throws -> T {
        guard let db else { throw Failure.refused }
        var prepared: OpaquePointer?
        try checked(sqlite3_prepare_v2(db, text, -1, &prepared, nil))
        guard let prepared else { throw Failure.refused }
        defer { sqlite3_finalize(prepared) }
        return try body(prepared)
    }
    private func sql(_ text: String) throws {
        try statement(text) { s in
            var code = sqlite3_step(s)
            while code == SQLITE_ROW { code = sqlite3_step(s) }
            try checked(code)
            guard code == SQLITE_DONE else { throw Failure.refused }
        }
    }
    private func scalar(_ text: String) throws -> Int64 {
        try statement(text) { s in
            let code = sqlite3_step(s); try checked(code)
            guard code == SQLITE_ROW else { throw Failure.refused }
            let result = sqlite3_column_int64(s, 0)
            guard sqlite3_step(s) == SQLITE_DONE else { throw Failure.refused }; return result
        }
    }
    private func integer(_ s: OpaquePointer, _ i: Int32, _ n: Int64?) throws {
        try checked(n.map { sqlite3_bind_int64(s, i, $0) } ?? sqlite3_bind_null(s, i))
    }
    private func string(_ s: OpaquePointer, _ i: Int32, _ text: String?) throws {
        if let text { try checked(sqlite3_bind_text(s, i, text, -1, Self.transient)) }
        else { try checked(sqlite3_bind_null(s, i)) }
    }
    private func operation<T>(_ writing: Bool, _ body: () throws -> T) throws -> T {
        guard pthread_equal(ownerThread, pthread_self()) != 0, db != nil, !poisoned, !writing || !sealed else { throw Failure.refused }
        do { try checkpoint(); try identities(); let result = try body(); try identities(); try checkpoint(); return result }
        catch { poisoned = true; throw error }
    }
    func append(_ observation: CompanionOriginalPacketCheck.Observation) throws {
        try operation(true) {
            switch observation {
            case .packet(let p):
                guard p.index == packets, packets < limits.records, p.inputOffset >= p.blockOffset,
                      p.blockOffset >= 0, p.inputOffset < sourceBytes, (1...(16 << 20)).contains(p.encodedBytes),
                      p.encodedBytes <= sourceBytes - p.inputOffset else { throw Failure.refused }
                _ = try DolbyInspection.hash(p.sha256)
                try statement("INSERT INTO packets VALUES(?,?,?,?,?,?,?,?,?,?)") { s in
                    for (i, n) in [p.index,p.ptsNS,p.inputOffset,p.blockOffset,p.encodedBytes].enumerated() { try integer(s,Int32(i+1),n) }
                    try string(s,6,p.sha256); try string(s,7,p.durationNS.map { String($0, radix:16) })
                    try integer(s,8,p.invisible ? 1 : 0); try integer(s,9,p.keyframe.map { $0 ? 1 : 0 }); try integer(s,10,p.discardable.map { $0 ? 1 : 0 })
                    try checked(sqlite3_step(s))
                }
                packets += 1; lastNAL = -1
            case .rpu(let r):
                guard r.index == rpus, rpus < limits.records, packets > 0, r.packetIndex == packets-1,
                      r.nalIndex > lastNAL, r.archiveDelimiterOffset == archiveOffset,
                      (1...65536).contains(r.payloadBytes) else { throw Failure.refused }
                let p = try loadPacket(r.packetIndex)
                guard r.ptsNS == p.ptsNS, r.inputOffset >= p.inputOffset,
                      r.inputOffset <= p.inputOffset+p.encodedBytes-Int64(r.payloadBytes) else { throw Failure.refused }
                _ = try DolbyInspection.hash(r.sha256)
                try statement("INSERT INTO rpus VALUES(?,?,?,?,?,?,?,?)") { s in
                    for (i,n) in [r.index,r.packetIndex,r.nalIndex,r.ptsNS,r.inputOffset,r.archiveDelimiterOffset,Int64(r.payloadBytes)].enumerated() { try integer(s,Int32(i+1),n) }
                    try string(s,8,r.sha256); try checked(sqlite3_step(s))
                }
                rpus += 1; archiveOffset += Int64(r.payloadBytes+4); lastNAL = r.nalIndex
            }
        }
    }
    func finishSourcePass(expected: Counts) throws -> Counts {
        try operation(true) {
            guard expected == Counts(packets:packets,rpus:rpus), packets > 0,
                  try scalar("SELECT COUNT(*) FROM packets") == packets,
                  try scalar("SELECT COUNT(*) FROM rpus") == rpus else { throw Failure.refused }
            guard let db, sqlite3_get_autocommit(db) != 0 else { throw Failure.refused }; sealed = true; return expected
        }
    }
    func packet(_ index: Int64) throws -> Packet {
        try operation(false) { guard sealed else { throw Failure.refused }; return try loadPacket(index) }
    }
    private func text(_ s: OpaquePointer, _ i: Int32) throws -> String {
        guard let value = sqlite3_column_text(s,i) else { throw Failure.refused }; return String(cString:value)
    }
    private func loadPacket(_ index: Int64) throws -> Packet {
        try statement("SELECT pts,input,block,bytes,hash,duration,invisible,keyframe,discardable FROM packets WHERE idx=?") { s in
            try integer(s,1,index)
            guard sqlite3_step(s) == SQLITE_ROW else { throw Failure.refused }
            func nullable(_ i: Int32) -> Bool? { sqlite3_column_type(s,i) == SQLITE_NULL ? nil : sqlite3_column_int(s,i) != 0 }
            let duration: UInt64?
            if sqlite3_column_type(s,5) == SQLITE_NULL { duration = nil }
            else { guard let n = UInt64(try text(s,5), radix:16) else { throw Failure.refused }; duration = n }
            return try .init(index:index,inputOffset:sqlite3_column_int64(s,1),blockOffset:sqlite3_column_int64(s,2),ptsNS:sqlite3_column_int64(s,0),durationNS:duration,invisible:sqlite3_column_int(s,6) != 0,keyframe:nullable(7),discardable:nullable(8),encodedBytes:sqlite3_column_int64(s,3),sha256:text(s,4))
        }
    }
    func rpu(_ index: Int64) throws -> RPU {
        try operation(false) {
            guard sealed else { throw Failure.refused }
            return try statement("SELECT packet,nal,pts,input,archive,bytes,hash FROM rpus WHERE idx=?") { s in
                try integer(s,1,index); guard sqlite3_step(s) == SQLITE_ROW else { throw Failure.refused }
                return try .init(index:index,packetIndex:sqlite3_column_int64(s,0),nalIndex:sqlite3_column_int64(s,1),ptsNS:sqlite3_column_int64(s,2),inputOffset:sqlite3_column_int64(s,3),archiveDelimiterOffset:sqlite3_column_int64(s,4),payloadBytes:Int(sqlite3_column_int64(s,5)),sha256:text(s,6))
            }
        }
    }
    /// Exact rational ticks, reducing before multiplication. No rounding or
    /// overflowing multiply-then-divide, including signed magnitude extremes.
    static func nanoseconds(_ ticks: Int64, timeBase: [Int]) throws -> Int64 {
        guard timeBase.count == 2, timeBase.allSatisfy({ (1...Int(Int32.max)).contains($0) }) else { throw Failure.refused }
        var factors = [ticks.magnitude, UInt64(timeBase[0]), UInt64(1_000_000_000)]
        var divisor = UInt64(timeBase[1])
        func gcd(_ a: UInt64, _ b: UInt64) -> UInt64 {
            var x=a, y=b; while y != 0 { let r=x%y; x=y; y=r }; return x
        }
        for i in factors.indices { let common=gcd(factors[i],divisor); factors[i]/=common; divisor/=common }
        guard divisor == 1 else { throw Failure.refused }
        var magnitude: UInt64 = 1
        for f in factors { let product=magnitude.multipliedReportingOverflow(by:f); guard !product.overflow else { throw Failure.refused }; magnitude=product.partialValue }
        let maximum=UInt64(Int64.max)+(ticks < 0 ? 1 : 0)
        guard magnitude <= maximum else { throw Failure.refused }
        if ticks < 0 { return magnitude == UInt64(Int64.max)+1 ? .min : -Int64(magnitude) }
        return Int64(magnitude)
    }
    /// Additional fixed disposable coverage only after source settlement. Source
    /// rows remain intact; unsupported multiplicity is refusal, never deduplication.
    func startDecoderPass(profile: DolbyDecoderStream.Profile = .metadata) throws {
        try operation(false) {
            guard sealed, !decoderStarted, packets > 0, rpus == packets else { throw Failure.refused }
            try sql("CREATE TABLE checked(idx INTEGER PRIMARY KEY, frame INTEGER NOT NULL)")
            decoderProfile=profile; decoderStarted=true
        }
    }
    /// Typed sample callback precedes its raw frame on the same owning worker.
    /// Hold only indices; values remain transient fixed-decoder observations.
    func acceptSampleObservation(_ frame: DolbyDecoderStream.BaseSampleFrame) throws {
        try operation(false) {
            guard decoderProfile == .baseSamples, decoderStarted, decoderBegan, !decoderComplete,
                  pendingSample == nil, frame.index == decoderFrames,
                  frame.packetIndex >= 0, frame.packetIndex < decoderPackets,
                  sampleObservations == decoderFrames, frame.coded.count == 3,
                  frame.codecVisible.count == 3 else { throw Failure.refused }
            pendingSample = (frame.index, frame.packetIndex); sampleObservations += 1
        }
    }
    /// Called synchronously by D124's strict owning stream parser. This checks
    /// source relationships, not executable authenticity or joined EOF/status.
    func acceptDecoderRow(_ data: Data, track: CompanionOriginalTrackCheck.Receipt) throws {
        try operation(false) {
            guard sealed, decoderStarted, !decoderComplete else { throw Failure.refused }
            typealias J = CompanionArchiveJSON
            let row=try J.object(data,maximum:65_535,decoderSampleFields:decoderProfile == .baseSamples), kind=try J.string(row,"kind")
            func n(_ key: String) throws -> Int64 {
                Int64(try J.unsigned(row,key,0...UInt64(Int64.max)))
            }
            func time(_ key: String) throws -> Int64 { try Self.nanoseconds(J.signed(row,key),timeBase:decoderTimeBase) }
            switch kind {
            case "begin", "sample-begin":
                guard kind == (decoderProfile == .metadata ? "begin" : "sample-begin"), !decoderBegan, try n("input_bytes") == sourceBytes,
                      try n("configuration_bytes") == track.configurationBytes,
                      try J.digest(row,"configuration_sha256") == track.configurationSHA256,
                      case .array(let base)? = row["time_base"], base.count == 2 else { throw Failure.refused }
                decoderTimeBase=try base.map { item in
                    guard case .unsigned(let v)=item, (1...UInt64(Int32.max)).contains(v) else { throw Failure.refused }; return Int(v)
                }
                decoderBegan=true
            case "packet":
                guard decoderBegan, decoderPackets < packets, try n("index") == decoderPackets else { throw Failure.refused }
                let original=try loadPacket(decoderPackets)
                guard !original.invisible, try time("pts") == original.ptsNS,
                      try n("block_input_byte_offset") == original.blockOffset,
                      try n("encoded_bytes") == original.encodedBytes,
                      try J.digest(row,"sha256") == original.sha256 else { throw Failure.refused }
                try statement("INSERT INTO checked VALUES(?,0)") { q in
                    try integer(q,1,decoderPackets); try checked(sqlite3_step(q))
                }
                decoderPackets += 1
            case "frame", "sample-frame":
                guard kind == (decoderProfile == .metadata ? "frame" : "sample-frame"), decoderBegan, decoderFrames < packets, try n("index") == decoderFrames else { throw Failure.refused }
                let index=try n("packet_index")
                guard index >= 0, index < decoderPackets else { throw Failure.refused }
                if decoderProfile == .baseSamples {
                    guard pendingSample?.index == decoderFrames, pendingSample?.packet == index else { throw Failure.refused }
                    pendingSample = nil
                } else { guard pendingSample == nil, sampleObservations == 0 else { throw Failure.refused } }
                let original=try loadPacket(index), raw=try rpu(index)
                guard !original.invisible, raw.packetIndex == index, raw.ptsNS == original.ptsNS,
                      try time("pts") == original.ptsNS, try time("packet_pts") == original.ptsNS,
                      try time("best_effort_pts") == original.ptsNS,
                      try n("block_input_byte_offset") == original.blockOffset,
                      try n("packet_size") == original.encodedBytes,
                      try n("rpu_bytes") == raw.payloadBytes,
                      try J.digest(row,"rpu_sha256") == raw.sha256 else { throw Failure.refused }
                try statement("UPDATE checked SET frame=1 WHERE idx=? AND frame=0") { q in
                    try integer(q,1,index); try checked(sqlite3_step(q)); guard let db, sqlite3_changes(db) == 1 else { throw Failure.refused }
                }
                decoderFrames += 1
            case "complete", "sample-complete":
                guard kind == (decoderProfile == .metadata ? "complete" : "sample-complete"), pendingSample == nil,
                      sampleObservations == (decoderProfile == .baseSamples ? packets : 0), decoderBegan, decoderPackets == packets, decoderFrames == packets,
                      try n("packets") == packets, try n("frames") == packets,
                      try scalar("SELECT COUNT(*) FROM checked") == packets,
                      try scalar("SELECT COUNT(*) FROM checked WHERE frame!=1") == 0 else { throw Failure.refused }
                decoderComplete=true
            default: throw Failure.refused
            }
        }
    }
    /// The owning caller must additionally require actual joined decoder result,
    /// matching source fingerprint/configuration and final source/tool settlement.
    func finishDecoderPass(_ result: DolbyDecoderStream.Receipt) throws {
        try operation(false) {
            guard decoderComplete, pendingSample == nil,
                  result.sampleFrameSummaryCount == sampleObservations,
                  (result.sampleColorDeclarations != nil) == (decoderProfile == .baseSamples), result.packets == packets, result.frames == packets,
                  result.timeBase == decoderTimeBase,
                  try scalar("SELECT COUNT(*) FROM checked") == packets,
                  try scalar("SELECT COUNT(*) FROM checked WHERE frame!=1") == 0 else { throw Failure.refused }
        }
    }
    private func identities() throws {
        var folder = stat(), folderPath = stat(), concrete = stat(), file = stat(), filePath = stat()
        func same(_ a: stat, _ b: stat, links: Bool = true) -> Bool { a.st_dev == b.st_dev && a.st_ino == b.st_ino && a.st_uid == b.st_uid && a.st_mode == b.st_mode && (!links || a.st_nlink == b.st_nlink) }
        guard fstat(folderFD,&folder) == 0, lstat(directory.path,&folderPath) == 0,
              fstat(fileFD,&file) == 0, fstatat(folderFD,Self.name,&filePath,AT_SYMLINK_NOFOLLOW) == 0,
              lstat(canonicalFolder,&concrete) == 0, same(concrete,folderID,links:false),
              same(folder,folderID,links:false), same(folderPath,folderID,links:false), same(file,fileID), same(filePath,fileID),
              try FileManager.default.contentsOfDirectory(atPath:directory.path) == [Self.name] else { throw Failure.refused }
    }
    private func close() throws {
        guard pthread_equal(ownerThread,pthread_self()) != 0 else { throw OwnershipFailure() }
        let status = db.map { sqlite3_close($0) } ?? SQLITE_OK
        guard status == SQLITE_OK else { throw OwnershipFailure() }
        db = nil; poisoned = true
        let fileClosed = Darwin.close(fileFD), folderClosed = Darwin.close(folderFD)
        guard fileClosed == 0, folderClosed == 0 else { throw OwnershipFailure() }
        #if DEBUG
        ownedPinsClosed = true
        #endif
    }
    #if DEBUG
    var ownedDescriptors: [Int32] { [folderFD,fileFD] }
    var hasPendingStatements: Bool { db.map { sqlite3_next_stmt($0,nil) != nil } ?? false }
    private(set) var ownedPinsClosed = false
    #endif
}
