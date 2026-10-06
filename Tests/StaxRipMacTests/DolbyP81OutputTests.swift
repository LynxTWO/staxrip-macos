import Foundation
import CryptoKit
import Testing
@testable import StaxRipMac

// Synthetic framing and joined-receipt regressions; not decodable Dolby media.
struct DolbyP81OutputTests {
    private func element(_ id: UInt64, _ bytes: Data) -> Data {
        let width = (64 - id.leadingZeroBitCount + 7) / 8
        let identifier = Data((0..<width).reversed().map { UInt8(truncatingIfNeeded: id >> ($0 * 8)) })
        precondition(bytes.count < 16383)
        return identifier + Data([0x40 | UInt8(bytes.count >> 8), UInt8(truncatingIfNeeded: bytes.count)]) + bytes
    }
    private func nal(_ type: UInt8, layer: UInt8 = 0, body: UInt8 = 0x80) -> Data {
        Data([0,0,0,3,type << 1 | layer >> 5,(layer & 31) << 3 | 1,body])
    }
    private func fixture(source: Bool, packets: [Data]? = nil, mapping: Bool? = nil, relative: Int16 = -1, scale: UInt64 = 1_000_000, extra: Data = Data(), p81: Bool = false) -> Data {
        var config = Data(repeating: 0, count: 23); config[0] = 1; config[21] = 3; config[22] = 3
        for type: UInt8 in [32,33,34] { config += Data([type,0,1,0,3]) + nal(type).suffix(3) }
        var track = element(0xd7, Data([1])) + element(0x83, Data([1])) + element(0x86, Data("V_MPEGH/ISO/HEVC".utf8)) + element(0x63a2, config)
        track += element(0x23e383, Data([0x02,0x7c,0x9b,0x55])) + extra
        if mapping ?? (source || p81) {
            track += element(0x55ee, Data([1])) + element(0x41e4,
                element(0x41f0, Data([1])) + element(0x41e7, Data("dvcC".utf8)) + element(0x41ed, Data((p81 ? [1,0,16,53,16] : [1,0,14,55,96]) + Array(repeating: 0, count: 19))))
        }
        let contents = packets ?? [nal(32) + nal(1) + (source ? nal(62) + nal(63) : Data())]
        let blocks = contents.reduce(Data()) { result, packet in
            let bits = UInt16(bitPattern: relative)
            return result + element(0xa3, Data([0x81,UInt8(bits >> 8),UInt8(truncatingIfNeeded: bits),0x80]) + packet)
        }
        let scaleBytes = Data((0..<8).reversed().map { UInt8(truncatingIfNeeded: scale >> ($0 * 8)) })
        return element(0x1a45dfa3, element(0x4282, Data("matroska".utf8))) + element(0x18538067,
            element(0x1549a966, element(0x2ad7b1, scaleBytes)) + element(0x1654ae6b, element(0xae, track)) +
            element(0x1f43b675, element(0xe7, Data([0])) + blocks))
    }
    private func view(_ data: Data, checkpoint: @escaping () throws -> Void = {}) -> CompanionDiskCheck.ReadView {
        .init(sourceBytes: Int64(data.count), source: { offset, count in
            data.subdata(in: Int(offset)..<(Int(offset) + count))
        }, component: { _ in throw DolbyCopyNative.failure() }, checkpoint: checkpoint)
    }
    private func read(_ data: Data, _ role: DolbyCopyNative.Role) throws -> DolbyCopyNative.Receipt {
        try DolbyCopyNative.read(view(data), role: role, timeBase: HDRFraction("1/1000"))
    }

    @Test func p81DeclarationAndEveryPacketRequireRPUWithoutEnhancement() throws {
        let packet = nal(32) + nal(1) + nal(62)
        let good = try read(fixture(source:false,packets:[packet],p81:true),.p81Output)
        #expect(good.rpus == 1 && good.enhancement == 0 && good.role == .p81Output)
        for bytes in [fixture(source:true),fixture(source:false,packets:[packet]),
                      fixture(source:false,packets:[packet + nal(63)],p81:true),
                      fixture(source:false,packets:[nal(1)],p81:true),
                      fixture(source:false,packets:[packet + nal(62)],p81:true),
                      fixture(source:false,packets:[nal(1,layer:1) + nal(62)],p81:true)] {
            #expect(throws:(any Error).self) { _ = try read(bytes,.p81Output) }
        }
        #expect(throws:(any Error).self) { _ = try read(fixture(source:false,packets:[packet],p81:true),.output) }
        #expect(throws:(any Error).self) { try read(fixture(source:true),.source).requireCopy(good) }
    }
    @Test func completeConsumerRejectsUnboundMetadataPixelsTimingAndWrongRole() throws {
        let a = nal(32) + nal(1) + nal(62) + nal(63), b = nal(32) + nal(1) + nal(62)
        let sourceData = fixture(source:true,packets:[a]), outputData = fixture(source:false,packets:[b],p81:true)
        let source = try read(sourceData,.source), output = try read(outputData,.p81Output)
        let sourceHash = SourceFingerprint(sha256:DolbyInspection.hex(SHA256.hash(data:sourceData)),byteCount:Int64(sourceData.count))
        let outputHash = SourceFingerprint(sha256:DolbyInspection.hex(SHA256.hash(data:outputData)),byteCount:Int64(outputData.count))
        let md = try HDRMasteringDisplay(["red_x":"34000/50000","red_y":"16000/50000","green_x":"13250/50000","green_y":"34500/50000","blue_x":"7500/50000","blue_y":"3000/50000","white_point_x":"15635/50000","white_point_y":"16450/50000","min_luminance":"1/10000","max_luminance":"10000000/10000"])
        func frames(_ native: DolbyCopyNative.Receipt, pixels: Data = Data([1]), presentation: Data? = nil) -> DolbyCopyFrames.Receipt {
            .init(frames:1,presentation:presentation ?? native.presentationSequence,pixels:pixels,mastering:md,light:nil,chroma:"topleft",timeBase:native.timeBase)
        }
        func timing(_ packet: Data, dts: Int64 = -2, duration: Int64 = 41) throws -> DolbyCopyTiming.Receipt {
            let parser = try DolbyCopyTiming.Stream(timeBase:HDRFraction("1/1000"))
            parser.accept(Data("pts=-1|dts=\(dts)|duration=\(duration)|size=\(packet.count)|data_hash=SHA256:\(DolbyInspection.hex(SHA256.hash(data:packet)))\n".utf8))
            return try parser.finish()
        }
        func metadata(_ native: DolbyCopyNative.Receipt, _ hash: SourceFingerprint, sourceRole: Bool, sequence: String? = nil, digest: String? = "qualified") -> DolbyP81MetadataStream.Receipt {
            .init(sourceRole:sourceRole,source:hash,packets:1,records:1,enhancementNALs:Int64(native.enhancement),
                  packetSequenceSHA256:sequence ?? native.inspectionSequence.map { String(format:"%02x",$0) }.joined(),
                  peakRecordBytes:3,peakTrackedHeap:1,expectedOutputMetadataSHA256:digest)
        }
        for change in ["none","metadata-sequence","metadata-digest","metadata-source","metadata-role","unsupported","dts","duration","pixels","picture-pts","kept-payload"] {
            let native = change == "kept-payload" ? try read(fixture(source:false,packets:[nal(32) + nal(1,body:0x81) + nal(62)],p81:true),.p81Output) : output
            let metaHash = change == "metadata-source" ? sourceHash : outputHash
            let actual = metadata(native,metaHash,sourceRole:change == "metadata-role",sequence:change == "metadata-sequence" ? "wrong" : nil,digest:change == "unsupported" ? nil : (change == "metadata-digest" ? "changed" : "qualified"))
            let outputTiming = try timing(change == "kept-payload" ? nal(32) + nal(1,body:0x81) + nal(62) : b,dts:change == "dts" ? -1 : -2,duration:change == "duration" ? 42 : 41)
            func check() throws {
                try DolbyP81Verification.verify(source:source,output:native,sourceFingerprint:sourceHash,outputFingerprint:outputHash,
                    sourceTiming:timing(a),outputTiming:outputTiming,sourceMetadata:metadata(source,sourceHash,sourceRole:true),outputMetadata:actual,
                    sourceFrames:frames(source),outputFrames:frames(native,pixels:change == "pixels" ? Data([2]) : Data([1]),presentation:change == "picture-pts" ? Data() : nil))
            }
            if change == "none" { try check() } else { #expect(throws:(any Error).self) { try check() } }
        }
    }
    @Test func outputInspectionCannotUseLegacyUncheckedReaderPath() async throws {
        let probe = try JSONDecoder().decode(MediaProbe.self,from:Data(#"{"streams":[{"index":0,"codec_name":"hevc","codec_type":"video","time_base":"1/1000"}],"format":{"format_name":"matroska"}}"#.utf8))
        let unused = URL(fileURLWithPath:"/generated-unused-" + UUID().uuidString)
        let tools = FFmpegTools(ffmpeg:unused,ffprobe:unused)
        for (role,checked) in [(DolbyCopyNative.Role.p81Output,false),(.output,true)] {
            await ToolRunner.$observeBoundary.withValue({ _ in Issue.record("Role refusal must precede tool admission") }) {
                await #expect(throws:NativeExportError.self) {
                    _ = try await DolbyInspection.read(source:unused,probe:probe,helper:unused,tools:tools,copyVerification:checked,copyRole:role)
                }
            }
        }
    }

    @Test func nativeMuxPreservesSourceClockAndExactExtraction() throws {
        let a = nal(32)+nal(1)+nal(62)+nal(63), b = nal(32)+nal(1)+nal(62)
        let source = fixture(source:true,packets:[a],relative:1000)
        let candidate = fixture(source:false,packets:[b],relative:0)
        var raw=Data(),output=Data()
        try DolbyCopyNative.extractP81Input(view(source),timeBase:HDRFraction("1/1000")) {raw.append($0)}
        #expect(raw == [UInt8(32),1,62,63].reduce(Data()) {$0+Data([0,0,0,1])+nal($1).suffix(3)})
        try DolbyCopyNative.muxP81(view(source),candidate:view(candidate),timeBase:HDRFraction("1/1000"),candidateTimeBase:HDRFraction("1/1000")) {output.append($0)}
        let before=try read(source,.source),after=try read(output,.p81Output)
        #expect(before.keptSequence==after.keptSequence)
        #expect(before.presentationSequence==after.presentationSequence)
        #expect(after.rpus==1 && after.enhancement==0)
    }
    @Test func nativeMuxRefusesMismatchShortReadAndPreservesSinkCause() throws {
        let source=fixture(source:true,packets:[nal(1)+nal(62)+nal(63)])
        let good=fixture(source:false,packets:[nal(1)+nal(62)])
        for candidate in [fixture(source:false,packets:[nal(1,body:0x81)+nal(62)]),fixture(source:false,packets:[nal(1)]),fixture(source:false,packets:[nal(1)+nal(62),nal(1)+nal(62)])] {
            #expect(throws:(any Error).self) {try DolbyCopyNative.muxP81(view(source),candidate:view(candidate),timeBase:HDRFraction("1/1000"),candidateTimeBase:HDRFraction("1/1000")) {_ in}}
        }
        final class Marker: CompanionUnsettledOwnership {}
        let marker=Marker()
        do {
            try DolbyCopyNative.muxP81(view(source),candidate:view(good),timeBase:HDRFraction("1/1000"),candidateTimeBase:HDRFraction("1/1000")) {_ in throw marker}
            Issue.record("Sink marker must propagate")
        } catch {#expect((error as? Marker) === marker)}
        #expect(throws:CancellationError.self) {try DolbyCopyNative.extractP81Input(view(source,checkpoint:{throw CancellationError()}),timeBase:HDRFraction("1/1000")) {_ in}}
        let short=CompanionDiskCheck.ReadView(sourceBytes:Int64(source.count),source:{_,_ in Data()},component:{_ in throw marker},checkpoint:{})
        #expect(throws:(any Error).self) {try DolbyCopyNative.extractP81Input(short,timeBase:HDRFraction("1/1000")) {_ in}}
    }

    @Test func nativeMuxRejectsMisnestedContainersAndLateIndexCancellation() throws {
        let good=fixture(source:false,packets:[nal(1)+nal(62)])
        let nested=fixture(source:true,packets:[nal(1)+nal(62)+nal(63)],extra:element(0xae,element(0xae,Data())))
        #expect(throws:(any Error).self) {try DolbyCopyNative.muxP81(view(nested),candidate:view(good),timeBase:HDRFraction("1/1000"),candidateTimeBase:HDRFraction("1/1000")) {_ in}}
        let source=fixture(source:true,packets:[nal(1)+nal(62)+nal(63)])
        let header=Data([0x81,0xff,0xff,0x80])+nal(1)+nal(62)+nal(63)
        let offset=try #require(source.range(of:header)?.lowerBound)
        var headers=0,indexing=false,writes=0
        let v=CompanionDiskCheck.ReadView(sourceBytes:Int64(source.count),source:{o,n in
            if o==Int64(offset) && n==11 {headers+=1;if headers==2 {indexing=true}}
            return source.subdata(in:Int(o)..<(Int(o)+n))
        },component:{_ in throw DolbyCopyNative.failure()},checkpoint:{if indexing {throw CancellationError()}})
        #expect(throws:CancellationError.self) {try DolbyCopyNative.extractP81Input(v,timeBase:HDRFraction("1/1000")) {_ in writes+=1}}
        #expect(indexing && writes==0)
    }

}
