import Foundation
import Darwin

struct QueueCheck: Identifiable, Sendable {
    enum Kind: String, Sendable { case checked = "Preliminary check passed", issue = "Needs correction", deferred = "Further checks required", completed = "Already completed" }
    let id: UUID
    let kind: Kind
    let detail: String
}

enum QueuePreflight {
    static func review(_ jobs: [QueueJob], completed: Set<UUID>, tools: FFmpegTools, encoders: Set<String>,
                       timeout: Double = 15, progress: @escaping @Sendable (QueueCheck) -> Void = { _ in }) async throws -> [QueueCheck] {
        guard jobs.count <= 1000, Set(jobs.map(\.id)).count == jobs.count else {
            throw NativeExportError.invalid("Check at most 1000 queue items with unique identifiers.")
        }
        try Task.checkCancellation()
        let pending = jobs.filter { !completed.contains($0.id) }
        let destinations = Dictionary(grouping: pending, by: { destinationKey($0.destination) })
        let duplicates = Set(destinations.values.filter { $0.count > 1 }.flatMap { $0.map(\.id) })
        var result: [QueueCheck] = []
        for job in jobs {
            try Task.checkCancellation()
            let item: QueueCheck
            if completed.contains(job.id) {
                item = QueueCheck(id: job.id, kind: .completed, detail: "Not selected to run again. No source or output check performed.")
            } else {
                do {
                    guard !duplicates.contains(job.id) else { throw NativeExportError.invalid("Queue destinations may collide, including names differing only by case. Choose distinct output names.") }
                    item = try await inspect(job, tools: tools, encoders: encoders, timeout: timeout)
                } catch is CancellationError { throw CancellationError() }
                catch { item = QueueCheck(id: job.id, kind: .issue, detail: String(error.localizedDescription.prefix(2000))) }
            }
            try Task.checkCancellation()
            result.append(item); progress(item)
        }
        return result
    }
    private static func destinationKey(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
            .precomposedStringWithCanonicalMapping.lowercased(with: Locale(identifier: "en_US_POSIX"))
    }
    static func inspect(_ job: QueueJob, tools: FFmpegTools, encoders: Set<String>, timeout: Double = 15) async throws -> QueueCheck {
        guard !job.isDemo else { throw NativeExportError.invalid("Demo source: open a real video and add its configuration.") }
        try SessionDocument.validate(job.configuration)
        guard job.source.hasPrefix("/"), job.destination.hasPrefix("/"), ![job.source, job.destination].contains(where: { $0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) }) else {
            throw NativeExportError.invalid("Source and destination must be valid absolute local paths.")
        }
        let source = URL(fileURLWithPath: job.source), output = URL(fileURLWithPath: job.destination)
        guard output.pathExtension.lowercased() == job.configuration.container.lowercased(),
              WorkspaceModel.filenameIssue(output.deletingPathExtension().lastPathComponent) == nil else {
            throw NativeExportError.invalid("The output name or extension does not match the selected container. Edit the queue item.")
        }
        guard source.standardizedFileURL.resolvingSymlinksInPath() != output.standardizedFileURL.resolvingSymlinksInPath() else {
            throw NativeExportError.invalid("The output points to the source. Choose a new output name.")
        }
        var info = stat()
        guard stat(source.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG, FileManager.default.isReadableFile(atPath: source.path) else {
            throw NativeExportError.invalid("The source is missing, unreadable or not a regular file. Locate it or update this queue item.")
        }
        if lstat(output.path, &info) == 0 { throw NativeExportError.invalid("The output already exists, including any symbolic link. Choose a new output name.") }
        guard errno == ENOENT else { throw NativeExportError.invalid("Cannot inspect the destination. Check its folder and permissions.") }
        let parent = output.deletingLastPathComponent()
        guard stat(parent.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR, FileManager.default.isWritableFile(atPath: parent.path) else {
            throw NativeExportError.invalid("The output folder is missing or not writable. Choose an existing writable folder.")
        }
        let probe = try await boundedProbe(source, tools: tools, timeout: timeout)
        try Task.checkCancellation()
        let c = job.configuration
        if c.colorMode == "Preserve static HDR10" {
            try EncodePlan.validateHDRSettings(c)
            guard encoders.contains("libx265"), let video = probe.video else { throw NativeExportError.invalid("HDR10 needs a video stream and the libx265 encoder.") }
            try HDR10Audit.validate(video)
            // This deliberately does not fabricate a full-frame HDR contract.
            return QueueCheck(id: job.id, kind: .deferred, detail: "Paths, HDR settings and stream metadata checked. Full HDR frame/timing audit, tool qualification and track/container validation still run when encoding starts.")
        }
        // Planning creates arguments only. This path never runs an encoder,
        // creates staging, or writes a recovery journal or destination.
        let plan = try EncodePlan.make(job: job, probe: probe, encoders: encoders, staged: output)
        if c.rate.backend == "Apple hardware" {
            return QueueCheck(id: job.id, kind: .deferred, detail: "Paths and encoding plan checked. The encoder is advertised by FFmpeg, but actual hardware availability is checked during encoding. " + plan.summary)
        }
        return QueueCheck(id: job.id, kind: .checked, detail: plan.summary + ". Execution rechecks; available disk space and filesystem publication support are not guaranteed.")
    }
    private static func boundedProbe(_ source: URL, tools: FFmpegTools, timeout: Double) async throws -> MediaProbe {
        try await withThrowingTaskGroup(of: MediaProbe.self) { group in
            group.addTask { try await MediaProbe.read(source, tools: tools) }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(0.001, min(15, timeout)) * 1_000_000_000))
                throw NativeExportError.invalid("Source inspection reached its time limit. Check that the file and drive are available, then retry.")
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }
}
