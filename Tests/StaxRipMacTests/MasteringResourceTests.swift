import Foundation
import Darwin
import Testing
@testable import StaxRipMac

private final class ResourcePhaseLog: @unchecked Sendable {
    private let lock = NSLock()
    private var previous = ""
    private(set) var peakDisk: Int64 = 0
    func record(_ phase: String,folder: URL) {
        lock.lock(); defer { lock.unlock() }
        guard phase != previous else { return }; previous = phase
        let files = FileManager.default.enumerator(at: folder,includingPropertiesForKeys: [.fileSizeKey,.isRegularFileKey])
        var bytes: Int64 = 0
        while let url = files?.nextObject() as? URL {
            if let values = try? url.resourceValues(forKeys: [.fileSizeKey,.isRegularFileKey]), values.isRegularFile == true { bytes += Int64(values.fileSize ?? 0) }
        }
        peakDisk = max(peakDisk,bytes)
        print("RESOURCE PHASE: \(phase) owned_disk_bytes=\(bytes)")
    }
}
struct MasteringResourceTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["STAXRIP_MASTER_LONG"] == "1"))
    func twoHourPipeline() async throws {
        let tools = try #require(FFmpegTools.discover())
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("master-long-"+UUID().uuidString)
        try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("two-hours.flac")
        try await MasteringEngine.runTool(tools,["-f","lavfi","-i","aevalsrc='if(lt(mod(t,60),30),0.03,0.12)*sin(2*PI*1000*t)|if(lt(mod(t,60),30),0.03,0.12)*sin(2*PI*1000*t)':s=48000:d=7200","-c:a","flac",source.path])
        var settings = MasterSettings(); settings.mode = .night; settings.maximumLRA = 3
        let start = Date(), phases = ResourcePhaseLog()
        let candidate = try await MasteringEngine.prepare(source: source,track: 0,regions: [],layout: nil,settings: settings,destination: folder.appendingPathComponent("master.flac"),tools: tools) { phase,_ in phases.record(phase,folder: folder) }
        #expect(candidate.verification.after.frames == 345600000)
        #expect(candidate.plan.dynamic)
        // Include an aligned float preview excerpt and its measurement.
        let excerpt = candidate.folder.appendingPathComponent("preview.wav")
        try await MasteringEngine.runTool(tools,["-i",candidate.original.path,"-af","atrim=start_sample=342720000:end_sample=345600000,asetpts=PTS-STARTPTS","-c:a","pcm_f64le",excerpt.path])
        let preview = try await MeasuredAnalysis.fresh(source: excerpt,track: 0,regions: [],tools: tools,declaredLayout: "stereo") { _ in }
        #expect(preview.report.programme.frames == 2880000)
        var own = rusage(), child = rusage()
        getrusage(RUSAGE_SELF,&own); getrusage(RUSAGE_CHILDREN,&child)
        #expect(own.ru_maxrss <= 512*1024*1024)
        let estimate = try MasteringEngine.scratchEstimate(rate: 48000,channels: 2,seconds: 7200)
        print("MASTER RESOURCE elapsed=\(Date().timeIntervalSince(start)) app_peak_bytes=\(own.ru_maxrss) child_peak_bytes=\(child.ru_maxrss) scratch_budget_bytes=\(estimate) peak_owned_disk_bytes=\(phases.peakDisk) attempts=\(candidate.verification.attempts)")
    }
}
