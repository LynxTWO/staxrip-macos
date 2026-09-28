import Foundation

enum MasterMode: String, Codable, CaseIterable, Sendable { case smart = "Smart", night = "Night" }
enum MasterReference: String, Codable, CaseIterable, Sendable { case programme = "Whole programme", speech = "Selected speech" }
struct MasterSettings: Codable, Equatable, Sendable {
    var mode: MasterMode = .smart
    var reference: MasterReference = .programme
    var target = -18.0
    var maximumLRA = 11.0
    var speechConfirmed = false
    func validate() throws {
        guard target.isFinite, (-36 ... -9).contains(target), maximumLRA.isFinite, (1...20).contains(maximumLRA),
              reference != .speech || speechConfirmed else {
            throw NativeExportError.invalid("Choose a target from -36 to -9 LUFS and a range from 1 to 20 LU. Confirm representative speech before selecting its reference.")
        }
    }
}
struct GainPlan: Sendable {
    static let version = "Swift linked gain planner 3; bounded energy feedback; 20 ms envelope; 500 ms look-ahead; FFmpeg 4x alimiter for dynamic path"
    let analysis: FreshAnalysis
    let settings: MasterSettings
    let baseDB: Double
    let dynamic: Bool
    let envelope: [Double]
    let minimumDB: Double
    let maximumDB: Double
    var rate: Int { analysis.report.sampleRate }
    var frames: Int64 { analysis.report.programme.frames }
    func gainDB(at frame: Int64) -> Double {
        guard dynamic else { return baseDB }
        let x = Double(frame)/Double(rate/50)
        let i = min(max(0, Int(x)), envelope.count-1), j = min(i+1,envelope.count-1)
        return envelope[i]+(envelope[j]-envelope[i])*min(1,max(0,x-Double(i)))
    }
}
enum GainPlanner {
    static func build(_ analysis: FreshAnalysis, settings: MasterSettings, attempt: Int = 0, correction: Double = 0) async throws -> GainPlan {
        let task = Task.detached { try make(analysis,settings: settings,attempt: attempt,correction: correction) }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
    static func reference(_ analysis: FreshAnalysis, settings: MasterSettings) -> Double? {
        settings.reference == .programme ? analysis.report.programme.integrated.value : analysis.speechReference.value
    }
    static func make(_ analysis: FreshAnalysis, settings: MasterSettings, attempt: Int = 0, correction: Double = 0) throws -> GainPlan {
        try Task.checkCancellation()
        try settings.validate(); try analysis.report.validate()
        guard (0...2).contains(attempt), correction.isFinite,
              let ref = reference(analysis, settings: settings), let lra = analysis.report.programme.range.value,
              let peak = analysis.report.programme.truePeak.value else {
            throw NativeExportError.invalid("The selected reference or programme range is unmeasurable. Choose a longer measurable track or correct the speech intervals.")
        }
        let base = settings.target-ref+correction
        guard (-36...12).contains(base) else { throw NativeExportError.invalid("The target requires gain outside -36 to +12 dB. Change the target or source; no candidate was published.") }
        let trace = analysis.report.programme.trace
        let mMax = trace.compactMap(\.momentary).max() ?? -.infinity
        let sMax = trace.compactMap(\.shortTerm).max() ?? -.infinity
        let constantOK = attempt == 0 && lra <= settings.maximumLRA && peak+base <= -1.5 &&
            (settings.mode == .smart || (mMax+base <= settings.target+9 && sMax+base <= settings.target+6))
        if constantOK { return GainPlan(analysis: analysis, settings: settings, baseDB: base, dynamic: false, envelope: [], minimumDB: base, maximumDB: base) }
        guard !trace.isEmpty else { throw NativeExportError.invalid("No timeline is available for gain planning.") }
        let strength = min(1, max(settings.mode == .night ? 0.75 : 0, 1-settings.maximumLRA/max(0.01,lra)) + Double(attempt)*0.15)
        let floor = max(-55,ref-25)
        var desired = [Double](), holds = [Bool](), last = base
        // Shift the end-stamped 400 ms windows to their centres.
        for i in 0...trace.count {
            let point = trace[min(i+9, trace.count-1)]
            let hold = point.momentary == nil || point.momentary! < floor
            // LRA is a distribution of 3-second energy. Use its centred window
            // for levelling, retaining the faster point for holds/excursion caps.
            let shortIndex = min(trace.count-1,max(149,i+74))
            let control = trace[shortIndex].shortTerm ?? point.momentary ?? ref
            var gain = hold ? last : base+strength*(ref-control)
            if settings.mode == .night {
                if let m = point.momentary { gain = min(gain,settings.target+9-m) }
                if let st = point.shortTerm { gain = min(gain,settings.target+6-st) }
            }
            gain = min(12,max(-36,gain)); desired.append(gain); holds.append(hold); last = gain
        }
        func constrain(_ gains: [Double]) -> [Double] {
            var desired = gains
            for i in desired.indices {
                var gain = min(12,max(-36,desired[i]))
                if settings.mode == .night {
                    let point = trace[min(i+9,trace.count-1)]
                    if let m = point.momentary { gain = min(gain,settings.target+9-m) }
                    if let st = point.shortTerm { gain = min(gain,settings.target+6-st) }
                }
                desired[i] = max(-36,gain)
            }
            // Offline future minimum starts attenuation before an upcoming loud event.
            var anticipated = desired
            for i in desired.indices { anticipated[i] = desired[i...min(i+25,desired.count-1)].min()! }
            let attack = settings.mode == .night ? 0.020 : 0.200
            let release = settings.mode == .night ? 0.500 : 2.000
            var smooth = anticipated[0], envelope = [Double](); envelope.reserveCapacity(desired.count)
            for i in anticipated.indices {
                let target = holds[i] ? min(smooth,anticipated[i]) : anticipated[i]
                let coefficient = exp(-0.020/(target < smooth ? attack : release))
                smooth = target+(smooth-target)*coefficient
                envelope.append(smooth)
            }
            return envelope
        }
        var envelope = constrain(desired)
        let energies = analysis.planningEnergies
        guard energies.count == Int((analysis.report.programme.frames+Int64(analysis.report.sampleRate/50)-1)/Int64(analysis.report.sampleRate/50)),
              energies.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            throw NativeExportError.invalid("Fresh energy timeline is missing or invalid.")
        }
        for _ in 0..<24 {
            try Task.checkCancellation()
            let prediction = GainPrediction(energies: energies, envelope: envelope)
            guard let low = prediction.low, let high = prediction.high else { break }
            let width = max(0.5,settings.maximumLRA-0.5)
            let middle = (low+high)/2
            let offset = settings.reference == .programme ? min(1,max(-1,settings.target+correction-(prediction.integrated ?? settings.target))) : 0
            if high-low <= width && abs(offset) < 0.02 { break }
            var changes = [Double](repeating: 0,count: envelope.count+1)
            var counts = [Int](repeating: 0,count: envelope.count+1)
            if high-low > width {
                for window in prediction.windows {
                    guard window.lufs > prediction.threshold else { continue }
                    let adjustment = min(1.5,max(-1.5,min(middle+width/2,max(middle-width/2,window.lufs))-window.lufs))
                    let end = min(envelope.count,window.start+150)
                    changes[window.start] += adjustment; changes[end] -= adjustment
                    counts[window.start] += 1; counts[end] -= 1
                }
            }
            var change = 0.0, count = 0
            for i in envelope.indices {
                change += changes[i]; count += counts[i]
                desired[i] += (count > 0 ? change/Double(count) : 0)+offset
                desired[i] = min(12,max(-36,desired[i]))
            }
            envelope = constrain(desired)
        }
        return GainPlan(analysis: analysis, settings: settings, baseDB: base, dynamic: true, envelope: envelope,
                        minimumDB: envelope.min()!, maximumDB: envelope.max()!)
    }
}

/// Approximate gain planning only. Final acceptance uses fresh PCM measurements.
struct GainPrediction {
    struct Window { let start: Int; let lufs: Double }
    let integrated: Double?
    let windows: [Window]
    let threshold: Double
    let low: Double?
    let high: Double?
    init(energies: [Double], envelope: [Double]) {
        var prefix = [0.0]; prefix.reserveCapacity(energies.count+76)
        for i in energies.indices {
            let gain = (envelope[min(i,envelope.count-1)]+envelope[min(i+1,envelope.count-1)])/2
            prefix.append(prefix.last!+energies[i]*pow(10,gain/10))
        }
        var blocks = [Double]()
        if energies.count >= 20 {
            for end in stride(from: 20,through: energies.count,by: 5) { blocks.append(max(0,(prefix[end]-prefix[end-20])/20)) }
        }
        integrated = StreamingLoudness.pooledIntegrated(blocks).value
        let tail = prefix.last!
        prefix.append(contentsOf: repeatElement(tail,count: 75))
        var windows = [Window](), absolute = [Double]()
        if energies.count >= 150 {
            for end in stride(from: 150,through: energies.count+75,by: 5) {
                let energy = max(0,(prefix[end]-prefix[end-150])/150)
                let value = energy > 0 ? -0.691+10*log10(energy) : -Double.infinity
                windows.append(Window(start: end-150,lufs: value))
                if value > -70 { absolute.append(energy) }
            }
        }
        self.windows = windows
        let threshold = absolute.isEmpty ? -70 : max(-70,-0.691+10*log10(absolute.reduce(0,+)/Double(absolute.count))-20)
        self.threshold = threshold
        let selected = windows.map(\.lufs).filter { $0 > threshold }.sorted()
        low = selected.isEmpty ? nil : selected[Int((Double(selected.count-1)*0.10).rounded())]
        high = selected.isEmpty ? nil : selected[Int((Double(selected.count-1)*0.95).rounded())]
    }
}

/// Applies one identical envelope to all channels; no source PCM is held beyond a chunk.
enum LinkedRenderer {
    static func render(raw: URL, to output: URL, plan: GainPlan) throws {
        let input = try FileHandle(forReadingFrom: raw)
        defer { try? input.close() }
        guard !FileManager.default.fileExists(atPath: output.path), FileManager.default.createFile(atPath: output.path, contents: nil) else {
            throw NativeExportError.invalid("Cannot create owned render staging file.")
        }
        let writer = try FileHandle(forWritingTo: output); defer { try? writer.close() }
        let channels = plan.analysis.report.channelLabels.count, bytesPerFrame = channels*8
        var frame: Int64 = 0
        while true {
            try Task.checkCancellation()
            let consumed = try autoreleasepool { () throws -> Int in
                let data = try input.read(upToCount: bytesPerFrame*4096) ?? Data()
                guard !data.isEmpty else { return 0 }
                guard data.count % bytesPerFrame == 0 else { throw NativeExportError.invalid("Incomplete source PCM frame.") }
                var result = Data(count: data.count)
                try data.withUnsafeBytes { src in
                    try result.withUnsafeMutableBytes { dst in
                        for offset in stride(from: 0, to: data.count, by: bytesPerFrame) {
                            guard frame < plan.frames else { throw NativeExportError.invalid("Source PCM duration differs from the fresh plan.") }
                            let gain = pow(10,plan.gainDB(at: frame)/20)
                            for channel in 0..<channels {
                                let index = offset+channel*8
                                let value = Double(bitPattern: UInt64(littleEndian: src.loadUnaligned(fromByteOffset: index, as: UInt64.self)))
                                guard value.isFinite, abs(value) <= 1e6 else { throw NativeExportError.invalid("Invalid source PCM.") }
                                dst.storeBytes(of: (value*gain).bitPattern.littleEndian, toByteOffset: index, as: UInt64.self)
                            }
                            frame += 1
                        }
                    }
                }
                try writer.write(contentsOf: result)
                return data.count
            }
            if consumed == 0 { break }
        }
        guard frame == plan.frames else { throw NativeExportError.invalid("Source PCM duration differs from the fresh plan.") }
    }
}
