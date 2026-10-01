import Foundation
import Darwin
import Testing
@testable import StaxRipMac

struct ToolRunnerConcurrencyTests {
    private final class CollectedBytes: @unchecked Sendable {
        private let lock = NSLock()
        private var stored = Data()
        var bytes: Data { lock.withLock { stored } }
        func append(_ data: Data) { lock.withLock { stored.append(data) } }
    }

    @Test(.timeLimit(.minutes(1)))
    func concurrentChildrenDrainBothPipesAndPreserveExitStatus() async throws {
        // Both outputs exceed a pipe buffer. Waiting for exit before readers run deadlocks.
        let script = "BEGIN { s=\"A\"; for(i=0;i<20;i++) s=s s; printf \"%s\",s; s=\"B\"; for(i=0;i<15;i++) s=s s; printf \"%s\",s > \"/dev/stderr\"; exit 17 }"
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<96 {
                group.addTask {
                    let result = try await ToolRunner().run(executable: URL(fileURLWithPath: "/usr/bin/awk"), arguments: [script], stdoutLimit: 1_048_576)
                    #expect(result.status == 17)
                    #expect(result.stdout == Data(repeating: 65, count: 1_048_576))
                    #expect(result.stderr == Data(repeating: 66, count: 32_768))
                    #expect(!result.truncated)
                }
            }
            try await group.waitForAll()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func streamedBytesFinishBeforeReturnWhileRetainedTailStaysBounded() async throws {
        let collector = CollectedBytes()
        let script = "BEGIN { s=\"A\"; for(i=0;i<20;i++) s=s s; printf \"%sEND\",s; s=\"B\"; for(i=0;i<17;i++) s=s s; printf \"%s\",s > \"/dev/stderr\" }"
        let result = try await ToolRunner().run(executable: URL(fileURLWithPath: "/usr/bin/awk"), arguments: [script], stdoutLimit: 37, onOutput: { collector.append($0) })
        #expect(result.status == 0 && result.truncated)
        #expect(result.stdout == Data(repeating: 65, count: 34) + Data("END".utf8))
        #expect(result.stderr == Data(repeating: 66, count: 65_536))
        #expect(collector.bytes == Data(repeating: 65, count: 1_048_576) + Data("END".utf8))
        let empty = try await ToolRunner().run(executable: URL(fileURLWithPath: "/usr/bin/true"), arguments: [])
        #expect(empty.status == 0 && empty.stdout.isEmpty && empty.stderr.isEmpty && !empty.truncated)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellationEscalatesAndWaitsForExitAndLaunchFailureAllowsRetry() async throws {
        let runner = ToolRunner(), collector = CollectedBytes()
        // A direct shell child ignores gentle signals, so cancellation must await escalation.
        await #expect(throws: CancellationError.self) {
            try await runner.run(executable: URL(fileURLWithPath: "/bin/zsh"), arguments: ["-c", "trap '' INT TERM; print -r -- $$; while true; do :; done"], onOutput: {
                collector.append($0); runner.cancel()
            })
        }
        let pid = try #require(Int32(String(decoding: collector.bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)))
        #expect(kill(pid, 0) == -1 && errno == ESRCH)
        let retry = ToolRunner()
        await #expect(throws: (any Error).self) { try await retry.run(executable: URL(fileURLWithPath: "/nonexistent-staxrip-test-tool"), arguments: []) }
        let ok = try await retry.run(executable: URL(fileURLWithPath: "/usr/bin/true"), arguments: [])
        #expect(ok.status == 0)
    }
}
