import Foundation

// Temporary D-090 diagnostic: static phase names and monotonic times only.
// No file paths, process arguments, media metadata, or unbounded output.
final class BoundedLifecycleTrace: @unchecked Sendable {
    private let lock = NSLock()
    private let enabled: Bool
    private let reservedCritical: Int
    private let origin = ProcessInfo.processInfo.systemUptime
    private var events: [(Double, String)] = []
    private var ordinaryCount = 0
    private var dropped = 0
    init(enabled: Bool = true, reservedCritical: Int = 0) {
        self.enabled = enabled; self.reservedCritical = reservedCritical
    }
    func record(_ label: String, critical: Bool = false) {
        guard enabled else { return }
        lock.lock(); defer { lock.unlock() }
        guard events.count < 32, critical || ordinaryCount < 32 - reservedCritical else { dropped += 1; return }
        events.append((ProcessInfo.processInfo.systemUptime - origin, label))
        if !critical { ordinaryCount += 1 }
    }
    func report(_ prefix: String) {
        guard enabled else { return }
        lock.lock(); let saved = events; let omitted = dropped; lock.unlock()
        for (time, label) in saved { print(prefix + String(format: " %.6f %@", time, label)) }
        print(prefix + " records=\(saved.count) omitted=\(omitted)")
    }
}
