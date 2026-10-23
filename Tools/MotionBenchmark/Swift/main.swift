import CiggyShared
import Foundation

// Offline measured-data replay. This intentionally does not tune production rules.
struct Manifest: Decodable {
    let dataset: String
    let sourceSHA256: String
    let recordings: [Recording]
}

struct Recording: Codable {
    let subject: String
    let session: Int
    let file: String
    let samples: Int
    let durationSeconds: Double
    let groundTruthPuffs: Int
}

struct Result: Encodable {
    let subject: String
    let session: Int
    let samples: Int
    let durationSeconds: Double
    let groundTruthPuffs: Int
    let gyroProxyGestures: Int
    let gyroProxyCandidates: Int
    let recordedCandidates: Int
}

struct Report: Encodable {
    let dataset: String
    let sourceSHA256: String
    let sensitivity: Double
    let participants: Int
    let recordings: Int
    let samples: Int
    let groundTruthPuffs: Int
    let gyroProxyGestures: Int
    let gyroProxyCandidates: Int
    let recordedCandidates: Int
    let recordingsWithGyroProxyCandidate: Int
    let recordingsWithRecordedCandidate: Int
    let limitations: [String]
    let results: [Result]
}

enum BenchmarkError: Error, CustomStringConvertible {
    case invalid(String)
    var description: String {
        switch self { case .invalid(let message): return message }
    }
}

func replay(_ item: Recording, directory: URL, sensitivity: Double) throws -> Result {
    guard item.file == URL(fileURLWithPath: item.file).lastPathComponent,
          item.samples > 1 else { throw BenchmarkError.invalid("Invalid recording manifest") }
    let text = try String(contentsOf: directory.appendingPathComponent(item.file), encoding: .utf8)
    let lines = text.split(whereSeparator: \.isNewline)
    guard lines.first == "T,AccX,AccY,AccZ,GyrX,GyrY,GyrZ,GT" else {
        throw BenchmarkError.invalid("Unexpected CSV columns: \(item.file)")
    }
    var recorded = RecordedMotionAnalyzer(sensitivity: sensitivity)
    var gesture = MotionGestureEngine()
    var fusion = DetectionFusionEngine()
    fusion.updateSensitivity(sensitivity)
    var gravity: MotionVector?
    var firstTime: Double?
    var previousTime: Double?
    var sampleCount = 0
    var groundTruthPuffs = 0
    var wasPuff = false
    var gestureCount = 0
    var gyroCandidates = 0
    var recordedCandidates = 0
    let origin = Date(timeIntervalSince1970: 1_700_000_000)
    for line in lines.dropFirst() {
        let fields = line.split(separator: ",", omittingEmptySubsequences: false)
        let row = fields.compactMap { Double($0) }
        guard row.count == 8, row.allSatisfy(\.isFinite),
              row[7] == -1 || row[7] == 1,
              previousTime.map({ row[0] > $0 }) ?? true else {
            throw BenchmarkError.invalid("Invalid measured sample in \(item.file)")
        }
        if firstTime == nil { firstTime = row[0] }
        let timestamp = origin.addingTimeInterval(row[0] - (firstTime ?? row[0]))
        // SED acceleration includes gravity in SI units; Core Motion expects g.
        let acceleration = MotionVector(x: row[1] / 9.80665, y: row[2] / 9.80665, z: row[3] / 9.80665)
        if recorded.record(.init(timestamp: timestamp, x: acceleration.x,
                                 y: acceleration.y, z: acceleration.z)) != nil { recordedCandidates += 1 }

        // SED does not contain CMDeviceMotion fused gravity/userAcceleration.
        // This is a gyro-assisted proxy, using the historical path's 0.25s filter,
        // not a replay of actual Apple live fusion or its 30Hz sample schedule.
        let elapsed = previousTime.map { row[0] - $0 } ?? 0.02
        if elapsed > 1 { gravity = nil; gesture.reset() }
        let weight = 1 - exp(-elapsed / 0.25)
        gravity = gravity?.blended(with: acceleration, weight: weight) ?? acceleration
        if let gravity {
            let sample = MotionSample(timestamp: timestamp, gravity: gravity,
                                      userAcceleration: .init(x: acceleration.x - gravity.x,
                                                              y: acceleration.y - gravity.y,
                                                              z: acceleration.z - gravity.z),
                                      rotationRate: .init(x: row[4], y: row[5], z: row[6]))
            if let at = gesture.record(sample) {
                gestureCount += 1
                if fusion.recordGesture(at: at) != nil { gyroCandidates += 1 }
            }
        }
        if row[7] > 0, wasPuff == false { groundTruthPuffs += 1 }
        wasPuff = row[7] > 0
        sampleCount += 1
        previousTime = row[0]
    }
    guard sampleCount == item.samples, groundTruthPuffs == item.groundTruthPuffs,
          let firstTime, let previousTime,
          abs(previousTime - firstTime - item.durationSeconds) < 0.001 else {
        throw BenchmarkError.invalid("CSV does not match manifest: \(item.file)")
    }
    return Result(subject: item.subject, session: item.session, samples: sampleCount,
                  durationSeconds: item.durationSeconds, groundTruthPuffs: groundTruthPuffs,
                  gyroProxyGestures: gestureCount, gyroProxyCandidates: gyroCandidates,
                  recordedCandidates: recordedCandidates)
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard arguments.count == 1 || arguments.count == 2 else {
        throw BenchmarkError.invalid("Usage: CiggyMotionBenchmark /absolute/path/to/SED-CSV [sensitivity 0...1]")
    }
    let sensitivity = arguments.count == 2 ? Double(arguments[1]) ?? .nan : 0.5
    guard sensitivity.isFinite, (0...1).contains(sensitivity) else {
        throw BenchmarkError.invalid("Sensitivity must be in 0...1")
    }
    let directory = URL(fileURLWithPath: arguments[0], isDirectory: true)
    let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: directory.appendingPathComponent("manifest.json")))
    guard manifest.dataset == "SED", manifest.sourceSHA256 == "0c21f6a78dc1c2c2814f596bdcc9339c229255dd860d5c1ae92c3836b65fa414",
          manifest.recordings.isEmpty == false else { throw BenchmarkError.invalid("Unsupported dataset release") }
    let results = try manifest.recordings.map { try replay($0, directory: directory, sensitivity: sensitivity) }
    let report = Report(dataset: manifest.dataset, sourceSHA256: manifest.sourceSHA256, sensitivity: sensitivity,
                        participants: Set(results.map(\.subject)).count, recordings: results.count,
                        samples: results.reduce(0) { $0 + $1.samples },
                        groundTruthPuffs: results.reduce(0) { $0 + $1.groundTruthPuffs },
                        gyroProxyGestures: results.reduce(0) { $0 + $1.gyroProxyGestures },
                        gyroProxyCandidates: results.reduce(0) { $0 + $1.gyroProxyCandidates },
                        recordedCandidates: results.reduce(0) { $0 + $1.recordedCandidates },
                        recordingsWithGyroProxyCandidate: results.filter { $0.gyroProxyCandidates > 0 }.count,
                        recordingsWithRecordedCandidate: results.filter { $0.recordedCandidates > 0 }.count,
                        limitations: ["SED is positive smoking-session data; this does not measure free-living false positives or daily accuracy.",
                                      "Puff labels and cigarette/session candidates measure different units; counts are not puff precision/recall.",
                                      "Gyro proxy estimates gravity from raw acceleration and retains source sampling; it is not Apple CMDeviceMotion live fusion.",
                                      "Non-Apple hardware, standardized orientation, small participant scope; no thresholds trained or tuned."],
                        results: results)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(decoding: try encoder.encode(report), as: UTF8.self))
} catch {
    FileHandle.standardError.write(Data("Motion benchmark failed: \(error)\n".utf8))
    exit(1)
}
