#if DEBUG
import Foundation

// Shared only by explicit, bounded worker-contention qualification tests.
final class WorkerContentionLoad: @unchecked Sendable {
    let lock = NSLock(), group = DispatchGroup()
    var entered = 0, ready = false
    var submitted: ContinuousClock.Instant?, worker: ContinuousClock.Instant?
    var checksum: UInt64 = 0
    let count: Int
    init(count: Int) { self.count = count }
    func observe(_ event: String) {
        if event == "submitting worker" {
            let deadline = ContinuousClock.now.advanced(by: .seconds(1))
            for _ in 0..<count {
                group.enter()
                DispatchQueue(label: "StaxRip.test-source-contention", qos: .userInitiated).async {
                    self.lock.withLock { self.entered += 1 }
                    let end = ContinuousClock.now.advanced(by: .seconds(3))
                    var state: UInt64 = 123456789
                    while ContinuousClock.now < end {
                        for _ in 0..<10000 { state = state &* 6364136223846793005 &+ 1442695040888963407 }
                    }
                    self.lock.withLock { self.checksum ^= state }
                    self.group.leave()
                }
            }
            while lock.withLock({ entered < count }), ContinuousClock.now < deadline {
                Thread.sleep(forTimeInterval: 0.001)
            }
            lock.withLock { ready = entered == count && ContinuousClock.now < deadline; submitted = .now }
        } else if event == "worker entered" {
            lock.withLock { worker = .now }
        }
    }
    func settle() async {
        await withCheckedContinuation { continuation in
            group.notify(queue: DispatchQueue(label: "StaxRip.test-source-contention-join")) { continuation.resume() }
        }
    }
}

#endif
