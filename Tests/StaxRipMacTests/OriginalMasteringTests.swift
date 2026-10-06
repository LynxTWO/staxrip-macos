import Foundation
import Testing
@testable import StaxRipMac

@Suite(.serialized)
struct OriginalMasteringTests {
    @Test func poolsEnergyWithDurationAndGatesBeforeConvertingToLUFS() throws {
        // 9 equally sized windows at -20 LUFS and one at -26: duration weighting,
        // not the -23 LUFS average of two passage readings.
        func energy(_ lufs: Double) -> Double { pow(10,(lufs+0.691)/10) }
        let levels = Array(repeating: energy(-20), count: 9)+[energy(-26)]
        let expected = -0.691+10*log10(levels.reduce(0,+)/10)
        let value = try #require(StreamingLoudness.pooledIntegrated(levels+[0,energy(-90)]).value)
        #expect(abs(value-expected) < 1e-10)
        #expect(abs(value+23) > 2)
        #expect(StreamingLoudness.pooledIntegrated([0,energy(-90)]).value == nil)
    }
    @Test func planningEnergyLanePredictsConstantGainAndDoesNotIncludeTail() throws {
        let meter = try StreamingLoudness(rate: 48000,channels: 1)
        // Non-bin-aligned end verifies that finish's LRA padding does not become source.
        let frames = 48000*7+137
        for i in 0..<frames {
            let amplitude = i < 48000*3 ? 0.08 : 0.16
            try meter.pushFrame([amplitude*sin(2 * .pi * 997 * Double(i)/48000)],offset: 0)
        }
        let binsBefore = meter.planningEnergies
        let measured = meter.finish()
        #expect(meter.planningEnergies == binsBefore)
        #expect(binsBefore.count == (frames+959)/960)
        let prediction = GainPrediction(energies: binsBefore,envelope: Array(repeating: -6,count: binsBefore.count+1))
        #expect(abs(try #require(prediction.integrated)-(try #require(measured.integrated.value)-6)) < 0.01)
        #expect(abs((try #require(prediction.high)-#require(prediction.low))-(try #require(measured.range.value))) < 0.03)
        let silence = GainPrediction(energies: Array(repeating: 0,count: 151),envelope: Array(repeating: 0,count: 152))
        #expect(silence.integrated == nil && silence.low == nil && silence.high == nil)
    }
    private func fixture(_ expression: String, rate: Int = 48000, seconds: Int = 12) async throws -> (URL,URL,FFmpegTools) {
        let tools = try #require(FFmpegTools.discover())
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("mastering-test-"+UUID().uuidString)
        try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: false)
        let source = folder.appendingPathComponent("source.flac")
        try await MasteringEngine.runTool(tools,["-f","lavfi","-i","aevalsrc='\(expression)':s=\(rate):d=\(seconds)","-c:a","flac",source.path])
        return (folder,source,tools)
    }
    @Test(.enabled(if: FFmpegTools.discover() != nil))
    func constantCandidateAndPublicationAreVerifiedAndExclusive() async throws {
        let (folder,source,tools) = try await fixture("0.1*sin(2*PI*1000*t)|-0.05*sin(2*PI*1000*t)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let destination = folder.appendingPathComponent("result.flac")
        let candidate = try await MasteringEngine.prepare(source: source,track: 0,regions: [],layout: nil,settings: MasterSettings(),destination: destination,tools: tools) { _,_ in }
        #expect(!candidate.plan.dynamic)
        #expect(abs(try #require(candidate.verification.after.integrated.value)+18) <= 0.01)
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        try await candidate.publish()
        #expect(try await SourceFingerprint.read(destination) == candidate.verification.output)
        await #expect(throws: (any Error).self) { try await candidate.publish() }
        let receipt = folder.appendingPathComponent("result.json")
        try candidate.verification.save(to: receipt)
        #expect(!String(decoding: try Data(contentsOf: receipt),as: UTF8.self).contains(folder.path))
        #expect(throws: (any Error).self) { try candidate.verification.save(to: receipt) }
    }
    @Test(.enabled(if: FFmpegTools.discover() != nil))
    func nightLevelsLargeTransitionsWithoutPublishingBeforeReview() async throws {
        let expression = "if(lt(t,10),0.03,if(lt(t,20),0.3,0.08))*sin(2*PI*1000*t)"
        let (folder,source,tools) = try await fixture(expression+"|"+expression,seconds: 30)
        defer { try? FileManager.default.removeItem(at: folder) }
        var settings = MasterSettings(); settings.mode = .night; settings.maximumLRA = 3
        let destination = folder.appendingPathComponent("night.wav")
        let candidate = try await MasteringEngine.prepare(source: source,track: 0,regions: [],layout: nil,settings: settings,destination: destination,tools: tools) { _,_ in }
        #expect(candidate.plan.dynamic)
        #expect(candidate.verification.attempts <= 3)
        #expect(try #require(candidate.verification.after.range.value) <= 4)
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }
    @Test(.enabled(if: FFmpegTools.discover() != nil), arguments: [44100,48000,88200,96000,192000])
    func limiterPreservesFrameCountAndImpulsePosition(rate: Int) async throws {
        let (folder,source,tools) = try await fixture("if(eq(n,\(rate)),1.5,0)",rate: rate,seconds: 4)
        defer { try? FileManager.default.removeItem(at: folder) }
        // Float raw fixture avoids FLAC clipping of the deliberately over-full-scale impulse.
        let raw = folder.appendingPathComponent("impulse.f64")
        try await MasteringEngine.runTool(tools,["-f","lavfi","-i","aevalsrc=if(eq(n\\,\(rate))\\,1.5\\,0):s=\(rate):d=4","-c:a","pcm_f64le","-f","f64le",raw.path])
        let output = folder.appendingPathComponent("limited.wav")
        try await MasteringEngine.encode(raw: raw,output: output,rate: rate,channels: 1,dynamic: true,tools: tools)
        let decoded = folder.appendingPathComponent("decoded.f64")
        try await MasteringEngine.runTool(tools,["-i",output.path,"-f","f64le","-c:a","pcm_f64le",decoded.path])
        let data = try Data(contentsOf: decoded)
        #expect(data.count == rate*4*8)
        let samples = data.withUnsafeBytes { bytes in stride(from: 0,to: bytes.count,by: 8).map { Double(bitPattern: UInt64(littleEndian: bytes.loadUnaligned(fromByteOffset: $0,as: UInt64.self))) } }
        let position = try #require(samples.indices.max(by: { abs(samples[$0]) < abs(samples[$1]) }))
        #expect(position == rate)
        let after = try await MeasuredAnalysis.fresh(source: output,track: 0,regions: [],tools: tools,declaredLayout: "mono") { _ in }
        #expect(try #require(after.report.programme.truePeak.value) <= -1)
        _ = source
    }
    @Test(.enabled(if: FFmpegTools.discover() != nil))
    func constantPCMMatchesMultiplicationAndPhaseOpposedStereo() async throws {
        let (folder,source,tools) = try await fixture("0.1*sin(2*PI*1000*t)|-0.05*sin(2*PI*1000*t)",seconds: 4)
        defer { try? FileManager.default.removeItem(at: folder) }
        let destination = folder.appendingPathComponent("constant.wav")
        let candidate = try await MasteringEngine.prepare(source: source,track: 0,regions: [],layout: nil,settings: MasterSettings(),destination: destination,tools: tools) { _,_ in }
        let raw = folder.appendingPathComponent("out.f64")
        try await MasteringEngine.runTool(tools,["-i",candidate.processed.path,"-f","f64le","-c:a","pcm_f64le",raw.path])
        let originalRaw = folder.appendingPathComponent("in.f64")
        try await MasteringEngine.runTool(tools,["-i",source.path,"-f","f64le","-c:a","pcm_f64le",originalRaw.path])
        let output = try Data(contentsOf: raw), input = try Data(contentsOf: originalRaw)
        #expect(output.count == input.count)
        let gain = pow(10,candidate.plan.baseDB/20), tolerance = 2.0/pow(2.0,23.0)
        var maxError = 0.0
        input.withUnsafeBytes { before in output.withUnsafeBytes { after in
            for i in stride(from: 0,to: input.count,by: 8) {
                let a = Double(bitPattern: before.loadUnaligned(fromByteOffset: i,as: UInt64.self))
                let b = Double(bitPattern: after.loadUnaligned(fromByteOffset: i,as: UInt64.self))
                maxError = max(maxError,abs(b-a*gain))
            }
        } }
        #expect(maxError <= tolerance)
    }
    @Test(.enabled(if: FFmpegTools.discover() != nil))
    func speechConfirmationAndSilentReferenceRefuseAndCleanup() async throws {
        let (folder,source,tools) = try await fixture("if(lt(t,4),0,0.1*sin(2*PI*1000*t))",seconds: 8)
        defer { try? FileManager.default.removeItem(at: folder) }
        let fingerprint = try await SourceFingerprint.read(source)
        var settings = MasterSettings(); settings.reference = .speech
        let silent = [SpeechRegion(startFrame: 0,endFrame: 3*48000)]
        let destination = folder.appendingPathComponent("refused.flac")
        await #expect(throws: (any Error).self) {
            try await MasteringEngine.prepare(source: source,track: 0,regions: silent,layout: nil,settings: settings,destination: destination,tools: tools) { _,_ in }
        }
        settings.speechConfirmed = true
        await #expect(throws: (any Error).self) {
            try await MasteringEngine.prepare(source: source,track: 0,regions: silent,layout: nil,settings: settings,destination: destination,tools: tools) { _,_ in }
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(try await SourceFingerprint.read(source) == fingerprint)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).allSatisfy { !$0.hasPrefix(".staxrip-master-") })
    }
    @Test(.enabled(if: FFmpegTools.discover() != nil))
    func linkedDynamicEnvelopeHoldsQuietTailAndVerifiesRange() async throws {
        let expression = "if(lt(t,8),0.03,if(lt(t,16),0.3,0.000001))*sin(2*PI*1000*t)"
        let (folder,source,tools) = try await fixture(expression+"|-0.5*("+expression+")",seconds: 24)
        defer { try? FileManager.default.removeItem(at: folder) }
        let before = try await MeasuredAnalysis.fresh(source: source,track: 0,regions: [],tools: tools) { _ in }
        var settings = MasterSettings(); settings.mode = .night; settings.maximumLRA = 3
        let plan = try GainPlanner.make(before,settings: settings)
        #expect(plan.dynamic)
        #expect(plan.minimumDB >= -36 && plan.maximumDB <= 12)
        // Far from transitions, below-floor noise cannot drive an upward ramp.
        #expect(plan.gainDB(at: 23*48000) <= plan.gainDB(at: 19*48000)+1e-10)
        let raw = folder.appendingPathComponent("in.f64"), output = folder.appendingPathComponent("linked.f64")
        try await MasteringEngine.runTool(tools,["-i",source.path,"-f","f64le","-c:a","pcm_f64le",raw.path])
        try LinkedRenderer.render(raw: raw,to: output,plan: plan)
        let data = try Data(contentsOf: output)
        var maxRatioError = 0.0
        data.withUnsafeBytes { bytes in
            for i in stride(from: 0,to: data.count,by: 16) {
                let left = Double(bitPattern: bytes.loadUnaligned(fromByteOffset: i,as: UInt64.self))
                let right = Double(bitPattern: bytes.loadUnaligned(fromByteOffset: i+8,as: UInt64.self))
                // Input is already integer FLAC; allow its amplified quantization.
                maxRatioError = max(maxRatioError,abs(right+0.5*left))
            }
        }
        #expect(maxRatioError < 0.000001)
        let destination = folder.appendingPathComponent("safe.flac")
        let candidate = try await MasteringEngine.prepare(source: source,track: 0,regions: [],layout: nil,settings: settings,destination: destination,tools: tools) { _,_ in }
        #expect(try #require(candidate.verification.after.range.value) <= 4)
        #expect(abs(try #require(candidate.verification.after.integrated.value)-settings.target) <= 0.5)
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil && ProcessInfo.processInfo.environment["STAXRIP_EXPERIMENTAL_SPARSE"] == "1"))
    func sparseBackgroundDoesNotRetainForegroundBoost() async throws {
        let expression = "if(lt(t,8),0.03,if(lt(t,16),0.3,if(lt(t,32),0.0008,if(lt(t,40),0.08,0.0008))))*sin(2*PI*997*t)"
        let (folder,source,tools) = try await fixture(expression+"|-0.5*("+expression+")",seconds: 48)
        defer { try? FileManager.default.removeItem(at: folder) }
        let fresh = try await MeasuredAnalysis.fresh(source: source,track: 0,regions: [],tools: tools) { _ in }
        for mode in MasterMode.allCases {
            var settings = MasterSettings(); settings.mode = mode
            settings.target = mode == .smart ? -23 : -30
            settings.maximumLRA = mode == .smart ? 11 : 3
            let plan = try await GainPlanner.build(fresh,settings: settings)
            #expect(plan.gainDB(at: 28*48000) <= plan.baseDB+0.1)
            #expect(plan.gainDB(at: 46*48000) <= plan.baseDB+0.1)
            let candidate = try await MasteringEngine.prepare(source: source,track: 0,regions: [],layout: nil,
                settings: settings,destination: folder.appendingPathComponent(mode.rawValue+".flac"),tools: tools) { _,_ in }
            #expect(abs(try #require(candidate.verification.after.integrated.value)-settings.target) <= 0.5)
            #expect(try #require(candidate.verification.after.range.value) <= settings.maximumLRA+1)
        }
    }
    @Test(.enabled(if: FFmpegTools.discover() != nil))
    func excessiveRequiredBoostRefusesWithoutPublishing() async throws {
        let (folder,source,tools) = try await fixture("0.0001*sin(2*PI*1000*t)",seconds: 4)
        defer { try? FileManager.default.removeItem(at: folder) }
        let destination = folder.appendingPathComponent("refused.flac")
        await #expect(throws: (any Error).self) {
            try await MasteringEngine.prepare(source: source,track: 0,regions: [],layout: nil,settings: MasterSettings(),destination: destination,tools: tools) { _,_ in }
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).allSatisfy { !$0.hasPrefix(".staxrip-master-") })
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil))
    func changedSourceCannotPublishVerifiedCandidate() async throws {
        let (folder,source,tools) = try await fixture("0.1*sin(2*PI*1000*t)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let candidate = try await MasteringEngine.prepare(source: source,track: 0,regions: [],layout: nil,settings: MasterSettings(),destination: folder.appendingPathComponent("safe.flac"),tools: tools) { _,_ in }
        try Data("changed".utf8).write(to: source)
        await #expect(throws: (any Error).self) { try await candidate.publish() }
        #expect(!FileManager.default.fileExists(atPath: candidate.destination.path))
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil))
    func selectedSpeechUsesFreshWindowsAndDrivesOutputReference() async throws {
        let (folder,source,tools) = try await fixture("if(lt(t,3),0.1,0.05)*sin(2*PI*1000*t)",seconds: 15)
        defer { try? FileManager.default.removeItem(at: folder) }
        let regions = [SpeechRegion(startFrame: 48000,endFrame: 96000),SpeechRegion(startFrame: 4*48000,endFrame: 8*48000)]
        let fresh = try await MeasuredAnalysis.fresh(source: source,track: 0,regions: regions,tools: tools) { _ in }
        // Full-window counts are 7 and 37. Independently resetting each passage
        // prevents windows spanning the unselected two-second gap.
        let values = try fresh.report.speech.map { try #require($0.result.integrated.value) }
        let expected = -0.691+10*log10((7*pow(10,(values[0]+0.691)/10)+37*pow(10,(values[1]+0.691)/10))/44)
        #expect(abs(try #require(fresh.speechReference.value)-expected) < 0.001)
        #expect(abs(try #require(fresh.speechReference.value)-(values[0]+values[1])/2) > 1)
        var settings = MasterSettings(); settings.reference = .speech; settings.speechConfirmed = true
        let candidate = try await MasteringEngine.prepare(source: source,track: 0,regions: regions,layout: nil,settings: settings,destination: folder.appendingPathComponent("speech.flac"),tools: tools) { _,_ in }
        #expect(abs(try #require(candidate.verification.speechAfter.value)+18) <= 0.5)
        #expect(candidate.verification.regionResults.count == 2)
        try candidate.verification.validate()
    }

}

private final class MasterCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<MasterCandidate,Error>?
    private var requested = false
    private var retainedForReview: MasterCancellation?
    func install(_ task: Task<MasterCandidate,Error>) {
        lock.lock(); self.task = task; let cancel = requested; lock.unlock()
        if cancel { task.cancel() }
    }
    func cancel() {
        lock.lock(); requested = true; let task = task; lock.unlock(); task?.cancel()
    }
    // A failed notification gives no cleanup authority. Retain the exact completed
    // task, including any returned candidate whose deinit would remove scratch.
    func joinAndRetainAfterMissingNotification(_ owned: Task<MasterCandidate, Error>) async {
        owned.cancel()
        _ = await owned.result
        lock.withLock { task = owned; retainedForReview = self }
    }
    func retainJoined(_ owned: Task<MasterCandidate, Error>) {
        lock.withLock { task = owned; retainedForReview = self }
    }
    func clearAfterJoin() { lock.withLock { task = nil } }
}

// Renderer-test timer only. The test caller is the sole join owner. No detach,
// forced cancellation, production worker or dispatch queue policy change.
private final class MasterRendererTimer: @unchecked Sendable {
    private let lock = NSLock()
    private let ready = DispatchSemaphore(value: 0)
    private let armed = DispatchSemaphore(value: 0)
    private let stop = DispatchSemaphore(value: 0)
    private var thread: pthread_t?
    private var deadline: DispatchTime?
    private var action: (@Sendable () -> Void)?
    private var stopped = false
    private var joinResult: Int32?
    private var joining = false
    private var retained: MasterRendererTimer?
    private(set) var createStatus: Int32?
    private(set) var actualJoinStatus: Int32?
    private(set) var joinAttempts = 0
    private let signalReady: Bool
    private let reportJoined: Bool
    init(signalReady: Bool = true, reportJoined: Bool = false) {
        self.signalReady = signalReady; self.reportJoined = reportJoined
    }
    func start(allowCreate: Bool = true, readinessDeadline: DispatchTime = .now()+10) -> Bool {
        precondition(createStatus == nil)
        guard allowCreate else { createStatus = EAGAIN; return false }
        let context = Unmanaged.passRetained(self).toOpaque()
        var created: pthread_t?
        let status = pthread_create(&created, nil, { context in
            let owner = Unmanaged<MasterRendererTimer>.fromOpaque(context).takeRetainedValue()
            owner.run(); return nil
        }, context)
        createStatus = status
        guard status == 0 else {
            Unmanaged<MasterRendererTimer>.fromOpaque(context).release(); return false
        }
        thread = created
        if ready.wait(timeout: readinessDeadline) == .success { return true }
        // A readiness timeout is not thread absence or a bounded join guarantee.
        _ = finish(); return false
    }
    func arm(_ action: @escaping @Sendable () -> Void) -> Bool {
        let accepted = lock.withLock {
            guard !stopped, deadline == nil else { return false }
            deadline = .now()+0.02; self.action = action; return true
        }
        if accepted { armed.signal() }
        return accepted
    }
    private func run() {
        if signalReady { ready.signal() }
        armed.wait()
        let selected = lock.withLock { stopped ? nil : deadline }
        guard let selected else { return }
        // Semaphore timed wait uses the monotonic DispatchTime deadline. Only
        // shutdown signals this semaphore; an early signal never delivers work.
        guard stop.wait(timeout: selected) == .timedOut else { return }
        let callback = lock.withLock { stopped ? nil : action }
        callback?() // The gate, not this wakeup, authorizes delivery versus expiry.
    }
    func shutdown() {
        lock.withLock { stopped = true }
        armed.signal(); stop.signal()
    }
    func finish() -> Int32 {
        shutdown()
        let selected: pthread_t? = lock.withLock {
            guard joinResult == nil, !joining, let thread else { return nil }
            joining = true; return thread
        }
        guard let selected else { return lock.withLock { joinResult ?? (joining ? EBUSY : 0) } }
        // Never hold a timer/gate lock across join, and never join this thread itself.
        guard pthread_equal(pthread_self(), selected) == 0 else {
            return lock.withLock { joinResult = EDEADLK; retained = self; return EDEADLK }
        }
        joinAttempts += 1
        let actual = pthread_join(selected, nil)
        actualJoinStatus = actual
        let result: Int32 = actual == 0 && reportJoined ? EIO : actual
        return lock.withLock {
            joinResult = result
            if result == 0 { thread = nil; action = nil }
            else { retained = self } // Consumed join attempt is never retried.
            return result
        }
    }
}

// Test-only categorical diagnosis. Never retain raw status, errors, candidates or clocks.
private final class MasterPhaseDiagnosis: @unchecked Sendable {
    enum Phase: String { case none, freshAnalysis, measuringSource, decoding, rendering, measuringCandidate, rejected, ready, other }
    enum Event: String { case phaseNext, finished }
    enum Terminal: String { case pending, candidateReturned, cancelled, plannerReference, plannerGain, plannerTimeline, incompletePCM, nativeInvalid, decoding, posix, cocoa, other }
    private let lock = NSLock()
    private var phase = Phase.none, terminal = Terminal.pending
    private var matched = false, code: Int?
    func status(_ text: String, matched: Bool) {
        let category: Phase
        if text.hasPrefix("Fresh analysis") { category = .freshAnalysis }
        else if text.hasPrefix("Measuring source") { category = .measuringSource }
        else if text.hasPrefix("Decoding selected track") { category = .decoding }
        else if text.hasPrefix("Rendering candidate") { category = .rendering }
        else if text.hasPrefix("Measuring encoded candidate") { category = .measuringCandidate }
        else if text.hasPrefix("Candidate ") { category = .rejected }
        else if text.hasPrefix("Verified candidate ready") { category = .ready }
        else { category = .other }
        lock.withLock { phase = category; self.matched = self.matched || matched }
    }
    func returned() { lock.withLock { terminal = .candidateReturned } }
    func failed(_ error: any Error) {
        let category: Terminal, number: Int?
        if error is CancellationError { category = .cancelled; number = nil }
        else if case NativeExportError.invalid(let text) = error {
            switch text {
            case "The selected reference or programme range is unmeasurable. Choose a longer measurable track or correct the speech intervals.": category = .plannerReference
            case "The target requires gain outside -36 to +12 dB. Change the target or source; no candidate was published.": category = .plannerGain
            case "No timeline is available for gain planning.": category = .plannerTimeline
            case "Audio decoding failed or returned incomplete PCM. No report was saved.": category = .incompletePCM
            default: category = .nativeInvalid
            }
            number = nil
        } else if error is DecodingError { category = .decoding; number = nil }
        else {
            let value = error as NSError
            if value.domain == NSPOSIXErrorDomain { category = .posix; number = value.code }
            else if value.domain == NSCocoaErrorDomain { category = .cocoa; number = value.code }
            else { category = .other; number = nil }
        }
        lock.withLock { terminal = category; code = number }
    }
    func record(target: Phase, event: Event, received: Bool?) -> String {
        lock.withLock { "MASTERING_CASE target=\(target.rawValue) event=\(event.rawValue) received=\(received.map(String.init) ?? "none") phase=\(phase.rawValue) matched=\(matched) terminal=\(terminal.rawValue) code=\(code.map(String.init) ?? "none")" }
    }
}

// One generated-test gate holds the actual selected worker, never a phase label.
private final class MasterLiveGate: @unchecked Sendable {
    private let lock = NSLock()
    private enum Resolution: String { case idle, waiting, completed, expired }
    enum Context: String { case recovery, settlement }
    // The timer records entry before acquiring the authoritative gate lock.
    // No path holds entryLock while trying to acquire lock.
    private let entryLock = NSLock()
    private var timerEntered = false
    private var timerAtExpiry: Bool?
    func markTimerEntry() { entryLock.withLock { timerEntered = true } }
    func record(context: Context, target: MasterPhaseDiagnosis.Phase, testCancelled: Bool) -> String {
        lock.withLock {
            entryLock.withLock {
                "MASTER_GATE context=\(context.rawValue) target=\(target.rawValue) resolution=\(resolution.rawValue) timerEntered=\(timerEntered) timerAtExpiry=\(timerAtExpiry.map(String.init) ?? "none") live=\(resolution == .completed ? String(actualLiveAtRequest) : "none") testCancelled=\(testCancelled)"
            }
        }
    }
    private var selected = false
    private var resolution = Resolution.idle
    private var actualLiveAtRequest = false
    private var closes = [Bool]()
    func select(_ value: Bool) { lock.withLock { selected = value } }
    func close(_ role: String, _ succeeded: Bool) -> Bool {
        lock.withLock { closes.append(succeeded) }; return false
    }
    func begin() -> Bool {
        lock.withLock {
            guard selected, resolution == .idle else { return false }
            resolution = .waiting; return true
        }
    }
    func complete(live: () -> Bool, deliver: () -> Void) {
        lock.withLock {
            guard resolution == .waiting else { return }
            actualLiveAtRequest = live()
            deliver()
            resolution = .completed
        }
    }
    func expire(failure: () -> Void) {
        lock.withLock {
            guard resolution == .waiting else { return }
            // Freeze the entry fact with the expiry transition. A later timer
            // entry cannot turn an earlier false observation into true.
            entryLock.withLock { timerAtExpiry = timerEntered; resolution = .expired }
            failure()
        }
    }
    func hold(runner: ToolRunner?, cancellation: MasterCancellation, notification: AsyncStream<Date>.Continuation, rendererTimer: MasterRendererTimer? = nil) {
        guard begin() else { return }
        let release = DispatchSemaphore(value: 0)
        let deliver: @Sendable () -> Void = { [self] in
            markTimerEntry()
            complete(live: {
                // nil is the renderer: this exact worker is still inside its chunk callback.
                runner == nil || runner?.ownedLivePID != nil
            }, deliver: {
                notification.yield(Date()); notification.finish(); cancellation.cancel()
                release.signal()
            })
        }
        if let rendererTimer {
            if !rendererTimer.arm(deliver) { expire { cancellation.cancel(); notification.finish() } }
        } else { DispatchQueue.global().asyncAfter(deadline: .now()+0.02, execute: deliver) }
        if release.wait(timeout: .now()+10) != .success {
            expire { cancellation.cancel(); notification.finish() }
        }
        rendererTimer?.shutdown()
    }
    var passed: Bool { lock.withLock { resolution == .completed && actualLiveAtRequest } }
    var allClosesSucceeded: Bool { lock.withLock { !closes.isEmpty && closes.allSatisfy { $0 } } }
}

@Suite(.serialized)
struct MasteringRecoveryTests {
    @Test func liveGateCompletionAndExpiryHaveOneAuthoritativeWinner() {
        for expiresFirst in [true, false] {
            for live in [true, false] {
                let gate = MasterLiveGate()
                gate.select(true)
                #expect(gate.begin())
                #expect(!gate.begin())
                var observations = 0, deliveries = 0, failures = 0
                if expiresFirst { gate.expire { failures += 1 } }
                for _ in 0..<2 {
                    gate.complete(live: { observations += 1; return live }, deliver: { deliveries += 1 })
                }
                gate.expire { failures += 1 }
                #expect(observations == (expiresFirst ? 0 : 1))
                #expect(deliveries == (expiresFirst ? 0 : 1))
                #expect(failures == (expiresFirst ? 1 : 0))
                #expect(gate.passed == (!expiresFirst && live))
            }
        }
    }

    @Test func rendererTimerJoinsUnarmedStartupRefusalAndReportedJoin() {
        let refused = MasterRendererTimer()
        #expect(!refused.start(allowCreate: false))
        #expect(refused.createStatus == EAGAIN && refused.joinAttempts == 0)
        let unarmed = MasterRendererTimer()
        #expect(unarmed.start())
        #expect(unarmed.finish() == 0)
        #expect(unarmed.actualJoinStatus == 0 && unarmed.joinAttempts == 1)
        #expect(unarmed.finish() == 0 && unarmed.joinAttempts == 1)
        let notReady = MasterRendererTimer(signalReady: false)
        #expect(!notReady.start(readinessDeadline: .now()))
        #expect(notReady.createStatus == 0 && notReady.actualJoinStatus == 0 && notReady.joinAttempts == 1)
        final class Witness { weak var timer: MasterRendererTimer? }
        let witness = Witness()
        var reported: MasterRendererTimer? = MasterRendererTimer(reportJoined: true)
        witness.timer = reported
        #expect(reported!.start())
        #expect(reported!.finish() == EIO)
        #expect(reported!.actualJoinStatus == 0 && reported!.joinAttempts == 1)
        #expect(reported!.finish() == EIO && reported!.joinAttempts == 1)
        reported = nil
        #expect(witness.timer != nil) // Controlled report after actual join, not OS failure.
    }

    @Test func reportedTimerJoinRetainsCompletedOwnedTaskAfterCallerDrop() async {
        final class Evidence: Error, @unchecked Sendable {}
        final class Witness {
            weak var evidence: Evidence?
            weak var holder: MasterCancellation?
        }
        let witness = Witness()
        var evidence: Evidence? = Evidence()
        witness.evidence = evidence
        var holder: MasterCancellation? = MasterCancellation()
        witness.holder = holder
        var owned: Task<MasterCandidate, Error>? = Task { [evidence = evidence!] in throw evidence }
        holder!.install(owned!)
        _ = await owned!.result // Same task is complete before attempting timer join.
        evidence = nil
        let timer = MasterRendererTimer(reportJoined: true)
        #expect(timer.start())
        let status = timer.finish()
        #expect(status == EIO && timer.actualJoinStatus == 0 && timer.joinAttempts == 1)
        if status != 0 { holder!.retainJoined(owned!) }
        owned = nil; holder = nil
        #expect(witness.holder != nil && witness.evidence != nil)
        // Returned-candidate deinit and actual OS join failure remain separate.
    }

    @Test func rendererTimerDeliversAfterDelayAndExpiredGateSuppressesLateWork() {
        for expireFirst in [false, true] {
            let timer = MasterRendererTimer(), gate = MasterLiveGate()
            let returned = DispatchSemaphore(value: 0)
            final class Facts: @unchecked Sendable {
                let lock = NSLock()
                var live = 0, delivered = 0
                func observe() -> Bool { lock.withLock { live += 1; return true } }
                func deliver() { lock.withLock { delivered += 1 } }
            }
            let facts = Facts()
            #expect(timer.start())
            gate.select(true); #expect(gate.begin())
            if expireFirst { gate.expire {} }
            let start = DispatchTime.now().uptimeNanoseconds
            #expect(timer.arm {
                gate.markTimerEntry()
                gate.complete(live: { facts.observe() }, deliver: { facts.deliver() })
                returned.signal()
            })
            #expect(returned.wait(timeout: .now()+10) == .success)
            #expect(DispatchTime.now().uptimeNanoseconds - start >= 20_000_000)
            #expect(timer.finish() == 0 && timer.actualJoinStatus == 0 && timer.joinAttempts == 1)
            #expect(gate.passed == !expireFirst)
            #expect(facts.lock.withLock { facts.live == (expireFirst ? 0 : 1) && facts.delivered == (expireFirst ? 0 : 1) })
        }
        let stopped = MasterRendererTimer()
        #expect(stopped.start())
        stopped.shutdown()
        #expect(!stopped.arm { Issue.record("Stopped timer delivered") })
        #expect(stopped.finish() == 0 && stopped.joinAttempts == 1)
    }

    @Test func timerEntryEvidenceFreezesAtExpiryWithoutChangingWinner() {
        for enteredBeforeExpiry in [false, true] {
            let gate = MasterLiveGate()
            gate.select(true)
            #expect(gate.begin())
            if enteredBeforeExpiry { gate.markTimerEntry() }
            var expiries = 0, observations = 0, deliveries = 0
            gate.expire { expiries += 1 }
            let before = gate.record(context: .settlement, target: .rendering, testCancelled: false)
            #expect(before.contains("resolution=expired"))
            #expect(before.contains("live=none"))
            #expect(before.contains("timerAtExpiry=\(enteredBeforeExpiry)"))
            gate.markTimerEntry()
            gate.complete(live: { observations += 1; return true }, deliver: { deliveries += 1 })
            let after = gate.record(context: .settlement, target: .rendering, testCancelled: true)
            #expect(after.contains("timerEntered=true timerAtExpiry=\(enteredBeforeExpiry)"))
            #expect(after.contains("testCancelled=true"))
            #expect(expiries == 1 && observations == 0 && deliveries == 0 && !gate.passed)
        }
        let completed = MasterLiveGate()
        completed.select(true)
        #expect(completed.begin())
        completed.markTimerEntry()
        completed.complete(live: { true }, deliver: {})
        completed.expire { Issue.record("Completed gate must not expire") }
        #expect(completed.passed)
        #expect(completed.record(context: .recovery, target: .rendering, testCancelled: false)
            .contains("resolution=completed timerEntered=true timerAtExpiry=none live=true"))
    }

    @Test func missingNotificationJoinsAndRetainsExactTaskResult() async {
        final class Evidence: Error, @unchecked Sendable {}
        final class Witnesses: @unchecked Sendable {
            weak var evidence: Evidence?
            weak var holder: MasterCancellation?
            private let lock = NSLock()
            private var returned = false
            func markReturned() { lock.withLock { returned = true } }
            var hasReturned: Bool { lock.withLock { returned } }
        }
        let witness = Witnesses()
        let ready = AsyncStream<CheckedContinuation<Void, Never>>.makeStream()
        let cancelled = AsyncStream<Void>.makeStream()
        var holder: MasterCancellation? = MasterCancellation()
        witness.holder = holder
        var owned: Task<MasterCandidate, Error>?
        do {
            let evidence = Evidence()
            witness.evidence = evidence
            owned = Task {
                try await withTaskCancellationHandler {
                    await withCheckedContinuation { ready.continuation.yield($0) }
                    throw evidence
                } onCancel: { cancelled.continuation.yield(()) }
            }
        }
        holder!.install(owned!)
        var readyIterator = ready.stream.makeAsyncIterator()
        let release = await readyIterator.next()!
        var join: Task<Void, Never>? = Task { [holder = holder!, owned = owned!] in
            await holder.joinAndRetainAfterMissingNotification(owned)
            witness.markReturned()
        }
        var cancelledIterator = cancelled.stream.makeAsyncIterator()
        _ = await cancelledIterator.next()
        #expect(!witness.hasReturned)
        release.resume()
        await join!.value
        #expect(witness.hasReturned)
        if case .failure(let error) = await owned!.result {
            #expect(error as? Evidence === witness.evidence)
        } else { Issue.record("Expected exact task failure") }
        join = nil; owned = nil; holder = nil
        #expect(witness.holder != nil)
        #expect(witness.evidence != nil)
        ready.continuation.finish(); cancelled.continuation.finish()
    }

    @Test func terminalDiagnosticsKeepOnlyFiniteCategoriesAndNumericCodes() {
        let privateText = "Generated private path/payload sentinel"
        let d = MasterPhaseDiagnosis()
        d.status("Candidate 1 rejected: " + privateText, matched: true)
        d.failed(NativeExportError.invalid(privateText))
        let opaque = d.record(target: .rendering,event: .phaseNext,received: false)
        #expect(opaque.contains("phase=rejected matched=true terminal=nativeInvalid code=none"))
        #expect(!opaque.contains(privateText))
        d.failed(NativeExportError.invalid("The selected reference or programme range is unmeasurable. Choose a longer measurable track or correct the speech intervals."))
        #expect(d.record(target: .rendering,event: .finished,received: nil).contains("terminal=plannerReference"))
        d.failed(POSIXError(.EACCES))
        #expect(d.record(target: .rendering,event: .finished,received: nil).contains("terminal=posix code=13"))
        d.failed(NSError(domain: privateText,code: 99,userInfo: [NSLocalizedDescriptionKey:privateText]))
        #expect(d.record(target: .rendering,event: .finished,received: nil).contains("terminal=other code=none"))
        d.failed(CancellationError())
        #expect(d.record(target: .rendering,event: .finished,received: nil).contains("terminal=cancelled"))
        d.returned()
        #expect(d.record(target: .rendering,event: .finished,received: nil).contains("terminal=candidateReturned"))
    }
    @Test(.enabled(if: FFmpegTools.discover() != nil), arguments: ["Fresh analysis", "Rendering candidate", "Measuring encoded candidate"])
    func cancelsOwnedWorkWithoutPublishing(phase: String) async throws {
        let tools = try #require(FFmpegTools.discover())
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("master-cancel-"+UUID().uuidString)
        try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: false)
        var mayRemoveFixture = false
        defer { if mayRemoveFixture { try? FileManager.default.removeItem(at: folder) } }
        let source = folder.appendingPathComponent("source.flac"), destination = folder.appendingPathComponent("output.flac")
        try await MasteringEngine.runTool(tools,["-f","lavfi","-i","aevalsrc=0.1*sin(2*PI*1000*t):s=48000:d=30","-c:a","flac",source.path])
        let fingerprint = try await SourceFingerprint.read(source)
        let cancellation = MasterCancellation()
        let notified = AsyncStream<Date>.makeStream()
        let diagnosis = MasterPhaseDiagnosis()
        let gate = MasterLiveGate()
        let target: MasterPhaseDiagnosis.Phase = phase == "Fresh analysis" ? .freshAnalysis : phase == "Rendering candidate" ? .rendering : .measuringCandidate
        let rendererTimer = phase == "Rendering candidate" ? MasterRendererTimer() : nil
        if let rendererTimer { try #require(rendererTimer.start()) }
        defer { print(diagnosis.record(target: target,event: .finished,received: nil)) }
        let task = Task {
            defer { notified.continuation.finish() }
            do {
                let candidate = try await ToolRunner.$readerCloseReport.withValue({ gate.close($0, $1) }) {
                try await LinkedRenderer.$closeReport.withValue({ gate.close($0, $1) }) {
                try await MeasuredAnalysis.$consumedPCM.withValue({ runner in
                    if phase != "Rendering candidate" { gate.hold(runner: runner, cancellation: cancellation, notification: notified.continuation) }
                }) {
                try await LinkedRenderer.$wroteChunk.withValue({
                    if phase == "Rendering candidate" { gate.hold(runner: nil, cancellation: cancellation, notification: notified.continuation, rendererTimer: rendererTimer) }
                }) {
                try await MasteringEngine.prepare(source: source,track: 0,regions: [],layout: nil,settings: MasterSettings(),destination: destination,tools: tools) { status,_ in
                    let matched = status.hasPrefix(phase)
                    diagnosis.status(status,matched: matched)
                    gate.select(matched || (phase == "Fresh analysis" && status.hasPrefix("Measuring source")))
                }
                } } } }
                diagnosis.returned(); return candidate
            } catch {
                diagnosis.failed(error); throw error
            }
        }
        cancellation.install(task)
        defer {
            let status = rendererTimer?.finish() ?? 0
            #expect(status == 0)
            if status != 0 { mayRemoveFixture = false; cancellation.retainJoined(task) }
        }
        var iterator = notified.stream.makeAsyncIterator()
        let next = await iterator.next()
        print(diagnosis.record(target: target,event: .phaseNext,received: next != nil))
        print(gate.record(context: .recovery, target: target, testCancelled: Task.isCancelled))
        if next == nil {
            await cancellation.joinAndRetainAfterMissingNotification(task)
        }
        let start = try #require(next)
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(Date().timeIntervalSince(start) < 5)
        #expect(gate.passed)
        #expect(gate.allClosesSucceeded)
        if case .failure(let error) = await task.result, error is CancellationError { mayRemoveFixture = true }
        #expect(try await SourceFingerprint.read(source) == fingerprint)
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).allSatisfy { !$0.hasPrefix(".staxrip-master-") })
    }
}

private final class WeakToolWitness: @unchecked Sendable {
    weak var value: ToolRunner?
    init(_ value: ToolRunner) { self.value = value }
}
private final class WeakRenderHandleWitness {
    weak var value: FileHandle?
    init(_ value: FileHandle) { self.value = value }
}
private final class SettlementReports: @unchecked Sendable {
    private let lock = NSLock()
    private var enabled = false
    private var observed = [(String, Bool)]()
    func enable() { lock.withLock { enabled = true } }
    func report(_ role: String, _ success: Bool) -> Bool {
        lock.withLock { guard enabled else { return false }; observed.append((role, success)); return true }
    }
    var records: [(String, Bool)] { lock.withLock { observed } }
}

@Suite(.serialized)
struct MasteringSettlementTests {
    @Test func checkedReaderReportsRetainSameRunnerAndRejectReuse() async throws {
        for selected in [["stdout"], ["stderr"], ["stdout", "stderr"]] {
            var runner: ToolRunner? = ToolRunner(checkedReaders: true)
            let witness = WeakToolWitness(runner!)
            var task: Task<ToolResult, Error>? = Task { [owned = runner!] in
                try await ToolRunner.$readerCloseReport.withValue({ role, success in
                    #expect(success)
                    return selected.contains(role)
                }) {
                    try await owned.run(executable: URL(fileURLWithPath: "/usr/bin/awk"), arguments: ["BEGIN { print \"generated\"; print \"error\" > \"/dev/stderr\"; exit 7 }"])
                }
            }
            do { _ = try await task!.value; Issue.record("Expected reported reader uncertainty") }
            catch let error as ToolRunner.ReaderCloseFailure {
                #expect(error.owner === runner)
                #expect(error.roles == selected.sorted())
                #expect(error.closeErrors.isEmpty)
                #expect(error.processStatus == 7)
                #expect(error.owner.retainsUncertainty)
            }
            task = nil; runner = nil
            let retained = try #require(witness.value)
            #expect(retained.retainsUncertainty)
            await #expect(throws: NativeExportError.self) {
                try await retained.run(executable: URL(fileURLWithPath: "/usr/bin/true"), arguments: [])
            }
            #expect(retained.retainsUncertainty)
        }
    }

    @Test(.enabled(if: FFmpegTools.discover() != nil), arguments: ["reader", "renderer", "readerCancel", "rendererCancel"])
    func preparationRetainsScratchAfterReportedCloseUncertainty(role: String) async throws {
        let tools = try #require(FFmpegTools.discover())
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("master-settlement-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        // Intentionally retained even after an unexpected error: no recovery authority.
        print("GENERATED_MASTER_SETTLEMENT_REVIEW \(folder.path)")
        let source = folder.appendingPathComponent("source.flac"), destination = folder.appendingPathComponent("output.flac")
        try await MasteringEngine.runTool(tools, ["-f", "lavfi", "-i", "aevalsrc=0.1*sin(2*PI*1000*t):s=48000:d=30", "-c:a", "flac", source.path])
        let fingerprint = try await SourceFingerprint.read(source)
        let reports = SettlementReports()
        let cancellation = MasterCancellation(), gate = MasterLiveGate()
        let notified = AsyncStream<Date>.makeStream()
        let cancelling = role.hasSuffix("Cancel"), reader = role.hasPrefix("reader")
        let rendererTimer = cancelling && !reader ? MasterRendererTimer() : nil
        if let rendererTimer { try #require(rendererTimer.start()) }
        var witness: WeakToolWitness?
        var handles: [WeakRenderHandleWitness] = []
        var task: Task<MasterCandidate, Error>? = Task {
            try await ToolRunner.$readerCloseReport.withValue({ reader ? reports.report($0, $1) : false }) {
                try await LinkedRenderer.$closeReport.withValue({ !reader ? reports.report($0, $1) : false }) {
                    try await MeasuredAnalysis.$consumedPCM.withValue({ runner in
                        if cancelling && reader {
                            reports.enable(); gate.hold(runner: runner, cancellation: cancellation, notification: notified.continuation)
                        }
                    }) {
                    try await LinkedRenderer.$wroteChunk.withValue({
                        if cancelling && !reader {
                            reports.enable(); gate.hold(runner: nil, cancellation: cancellation, notification: notified.continuation, rendererTimer: rendererTimer)
                        }
                    }) {
                    try await MasteringEngine.prepare(source: source, track: 0, regions: [], layout: nil, settings: MasterSettings(), destination: destination, tools: tools) { text, _ in
                        if !cancelling && text.hasPrefix("Fresh analysis") { reports.enable() }
                        gate.select(reader ? text.hasPrefix("Fresh analysis") || text.hasPrefix("Measuring source") : text.hasPrefix("Rendering candidate"))
                    }
                    } }
                }
            }
        }
        cancellation.install(task!)
        defer {
            let status = rendererTimer?.finish() ?? 0
            #expect(status == 0)
            if status != 0, let task { cancellation.retainJoined(task) }
        }
        do { _ = try await task!.value; Issue.record("Expected reported preparation uncertainty") }
        catch let error as ToolRunner.ReaderCloseFailure {
            #expect(reader); witness = WeakToolWitness(error.owner)
            #expect(error.roles == ["stderr", "stdout"])
            #expect(error.closeErrors.isEmpty)
            if cancelling { #expect(error.cause is CancellationError) }
        } catch let error as LinkedRenderer.CloseFailure {
            #expect(!reader); handles = error.handles.map(WeakRenderHandleWitness.init)
            #expect(error.roles == ["output", "input"])
            #expect(error.closeErrors.isEmpty)
            if cancelling { #expect(error.cause is CancellationError) }
            else { #expect(error.cause == nil) }
        }
        if cancelling {
            print(gate.record(context: .settlement, target: reader ? .freshAnalysis : .rendering, testCancelled: Task.isCancelled))
        }
        let joined = rendererTimer?.finish() ?? 0
        if joined != 0 { cancellation.retainJoined(task!) }
        task = nil
        if joined == 0 { cancellation.clearAfterJoin() }
        #expect(reports.records.count == 2)
        #expect(reports.records.allSatisfy { $0.1 })
        if cancelling { #expect(gate.passed) }
        if reader { #expect(witness?.value?.retainsUncertainty == true) }
        else { #expect(handles.count == 2 && handles.allSatisfy { $0.value != nil }) }
        #expect(try await SourceFingerprint.read(source) == fingerprint)
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasPrefix(".staxrip-master-") }.count == 1)
    }
}
