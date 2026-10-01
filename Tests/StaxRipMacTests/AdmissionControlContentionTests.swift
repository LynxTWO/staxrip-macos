#if DEBUG
import Foundation
import Darwin
import Testing
@testable import StaxRipMac

struct AdmissionControlContentionTests {
    private final class Observation: @unchecked Sendable {
        let lock = NSLock()
        var qos: UInt32 = 0, onMain = true
        func record() { lock.withLock { qos = qos_class_self().rawValue; onMain = Thread.isMainThread } }
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["STAXRIP_ADMISSION_CONTROL_STRESS"] == "1"), .timeLimit(.minutes(1)))
    func actualAdmissionAndProcessLaunchStartDuringBoundedCPUContention() async throws {
        let count = ProcessInfo.processInfo.activeProcessorCount
        try #require((2...32).contains(count), "This opt-in fixture supports two through 32 reported CPUs")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("admission-control-contention-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("source"), bytes = Data("generated regular source".utf8)
        try bytes.write(to: file)
        // Run sequentially: each controlled load must settle before the next.
        for kind in ["source admission", "process launch"] {
            let load = WorkerContentionLoad(count: count), context = Observation()
            let observe: @Sendable (String) -> Void = { event in
                if event == "worker entered" { context.record() }
                load.observe(event)
            }
            do {
                try #require(Task.currentPriority == .medium)
                if kind == "source admission" {
                    let result = try await SourceLoader.$observeBoundary.withValue(observe) {
                        // Real regular-file admission; native decoding is outside this control.
                        try await SourceLoader.read(file, tools: nil, nativeReader: { _ in
                            LoadedSource(nativePreview: false, info: "admission fixture")
                        })
                    }
                    #expect(result.info == "admission fixture")
                } else {
                    let result = try await ToolRunner.$observeBoundary.withValue(observe) {
                        try await ToolRunner().run(executable: URL(fileURLWithPath: "/usr/bin/true"), arguments: [])
                    }
                    #expect(result.status == 0 && result.stdout.isEmpty && result.stderr.isEmpty && !result.truncated)
                }
                await load.settle()
                let timing = load.lock.withLock { (load.ready, load.submitted, load.worker) }
                try #require(timing.0, "All owned CPU workers must start within the setup bound")
                let submission = try #require(timing.1), worker = try #require(timing.2)
                let delay = submission.duration(to: worker)
                print("ADMISSION_CONTROL_CONTENTION operation=\(kind) CPUs=\(count) submitted-to-worker=\(delay)")
                #expect(delay < .seconds(1))
                let workerContext = context.lock.withLock { (context.qos, context.onMain) }
                #expect(workerContext.0 >= QOS_CLASS_DEFAULT.rawValue)
                #expect(!workerContext.1)
                #expect(try Data(contentsOf: file) == bytes)
            } catch {
                await load.settle()
                throw error
            }
        }
    }
}
#endif
