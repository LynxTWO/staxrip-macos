import Foundation
import Darwin

// CI preparation before timed tests. Same native flock as RustFixtureBuild;
// always use the fixed development feature set and separate target.
let args = CommandLine.arguments
precondition(args.count == 3)
let target = args[1], manifest = args[2]
try FileManager.default.createDirectory(atPath: target, withIntermediateDirectories: true)
let fd = Darwin.open(target + "/fixture-build.lock", O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
guard fd >= 0 else { throw NSError(domain: "FixturePreparation", code: Int(errno)) }
var result: Result<Void, Error>
do {
    var info = stat()
    guard fstat(fd, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
          info.st_uid == geteuid(), info.st_nlink == 1, info.st_mode & 0o7777 == 0o600,
          flock(fd, LOCK_EX) == 0 else { throw NSError(domain: "FixturePreparation", code: Int(errno)) }
    for command in [["build", "--release", "--bins"], ["test", "--no-run", "--lib", "--bins", "--test", "matroska"]] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["cargo"] + command + ["--locked", "--features", "development-companion-writer", "--target-dir", target, "--manifest-path", manifest]
        process.standardInput = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw NSError(domain: "FixturePreparation", code: Int(process.terminationStatus)) }
    }
    result = .success(())
} catch { result = .failure(error) }
let unlocked = flock(fd, LOCK_UN) == 0
let closed = Darwin.close(fd) == 0
// Consume once even on failure; never retry uncertain numbers.
guard unlocked, closed else { throw NSError(domain: "FixturePreparationClose", code: Int(errno)) }
try result.get()
