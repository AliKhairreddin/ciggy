import Foundation
import XCTest
@testable import CiggyShared

/// Procedural regression/stress fixtures, not measured motion or training data.
/// Labels describe the scenario we intended to model; the sensor inputs do not
/// encode the object in the hand. Overlap and missed scenarios are reported.
final class SyntheticMotionSimulationTests: XCTestCase {
    func testRestOrientationAndSmallerExcursionsAcrossAllAxes() {
        // Invented larger/smaller wrist arcs, not measured standing/seated data.
        // A different resting orientation must not require the hand to reach a
        // fixed height. A below-threshold arc documents an actual blind spot.
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        for base in [-1.2, 0, 1.2] {
            for plane in [0, Double.pi / 3, Double.pi / 2] {
                for excursion in [0.3, 0.6, 1.4] {
                    var live = MotionGestureEngine()
                    var fusion = DetectionFusionEngine()
                    var recorded = RecordedMotionAnalyzer()
                    var liveCount = 0
                    var recordedCount = 0
                    for index in 0...(365 * 30) {
                        let seconds = Double(index) / 30
                        let t = seconds.truncatingRemainder(dividingBy: 60)
                        let fraction: Double
                        let rate: Double
                        if t < 1 { fraction = 0; rate = 0 }
                        else if t < 2 { fraction = t - 1; rate = excursion }
                        else if t < 4 { fraction = 1; rate = 0 }
                        else if t < 5 { fraction = 5 - t; rate = -excursion }
                        else { fraction = 0; rate = 0 }
                        let angle = base + excursion * fraction
                        let gravity = MotionVector(x: sin(angle) * cos(plane),
                            y: sin(angle) * sin(plane), z: -cos(angle))
                        let time = start.addingTimeInterval(seconds)
                        let sample = MotionSample(timestamp: time, gravity: gravity,
                            userAcceleration: .init(x: 0, y: 0, z: 0),
                            rotationRate: .init(x: rate * sin(plane), y: -rate * cos(plane), z: 0))
                        if let gesture = live.record(sample), fusion.recordGesture(at: gesture) != nil { liveCount += 1 }
                        if recorded.record(.init(timestamp: time, x: gravity.x, y: gravity.y, z: gravity.z)) != nil {
                            recordedCount += 1
                        }
                    }
                    let expected = excursion < 0.45 ? 0 : 1
                    let context = "base=\(base), plane=\(plane), excursion=\(excursion)"
                    XCTAssertEqual(liveCount, expected, "Live: \(context)")
                    XCTAssertEqual(recordedCount, expected, "Recorded: \(context)")
                }
            }
        }
    }

    func testSyntheticSessionSweep() throws {
        let requested = ProcessInfo.processInfo.environment["CIGGY_SIMULATION_SESSIONS"].flatMap(Int.init) ?? 800
        let total = min(1_000_000, max(8, requested))
        var results = Dictionary(uniqueKeysWithValues: Scenario.allCases.map { ($0, Result()) })
        for index in 0..<total {
            let scenario = Scenario.allCases[index % Scenario.allCases.count]
            let trace = Trace(scenario: scenario, seed: UInt64(index) &+ 1)
            var live = MotionGestureEngine()
            var fusion = DetectionFusionEngine()
            var recorded = RecordedMotionAnalyzer()
            var result = Result(sessions: 1)
            var ids = Set<UUID>()
            trace.forEachSample { sample in
                result.samples += 1
                if let at = live.record(sample), let candidate = fusion.recordGesture(at: at) {
                    result.liveCandidates += 1
                    if ids.insert(candidate.id).inserted == false { result.duplicateIDs += 1 }
                }
                let acceleration = sample.gravity.blended(with: .init(
                    x: sample.gravity.x + sample.userAcceleration.x,
                    y: sample.gravity.y + sample.userAcceleration.y,
                    z: sample.gravity.z + sample.userAcceleration.z), weight: 1)
                if recorded.record(.init(timestamp: sample.timestamp, x: acceleration.x,
                                         y: acceleration.y, z: acceleration.z)) != nil {
                    result.recordedCandidates += 1
                }
            }
            XCTAssertLessThanOrEqual(result.liveCandidates, 1, "One-duration trace must not log twice: \(scenario), seed \(index + 1)")
            XCTAssertLessThanOrEqual(result.recordedCandidates, 1, "Recorded trace must not log twice: \(scenario), seed \(index + 1)")
            XCTAssertEqual(result.duplicateIDs, 0)
            if scenario == .ambiguousHandToMouth {
                XCTAssertEqual(result.liveCandidates, 1, "The positive trace includes five minutes of qualifying motion")
                XCTAssertEqual(result.recordedCandidates, 1, "The saved positive trace must exercise the production duration gate")
            }
            if scenario == .stationary || scenario == .oppositeWrist || scenario == .interrupted {
                XCTAssertEqual(result.liveCandidates, 0, "Incomplete/nonmoving trace: \(scenario), seed \(index + 1)")
                XCTAssertEqual(result.recordedCandidates, 0, "Incomplete/nonmoving history: \(scenario), seed \(index + 1)")
            }
            results[scenario, default: Result()].add(result)
        }
        print("SYNTHETIC MOTION SWEEP (invented inputs; not real-world accuracy):")
        for scenario in Scenario.allCases {
            let result = results[scenario, default: Result()]
            print("\(scenario.rawValue): sessions=\(result.sessions), samples=\(result.samples), live_candidates=\(result.liveCandidates), recorded_candidates=\(result.recordedCandidates), duplicate_ids=\(result.duplicateIDs)")
        }
        print("Total: \(total) complete session traces, \(results.values.reduce(0) { $0 + $1.samples }) samples through EACH of the live and recorded pipelines.")
    }

    func testIndistinguishableObjectsProduceIdenticalDetection() {
        // A deliberately identical wrist trace may mean smoking, slowly eating,
        // or repeated sips. A classifier using only this trace cannot tell which.
        let trace = Trace(scenario: .ambiguousHandToMouth, seed: 42)
        var smoking = MotionGestureEngine()
        var eating = MotionGestureEngine()
        var drinking = MotionGestureEngine()
        var smokingFusion = DetectionFusionEngine()
        var eatingFusion = DetectionFusionEngine()
        var drinkingFusion = DetectionFusionEngine()
        var outputs = [[UUID](), [], []]
        trace.forEachSample { sample in
            if let at = smoking.record(sample), let candidate = smokingFusion.recordGesture(at: at) { outputs[0].append(candidate.id) }
            if let at = eating.record(sample), let candidate = eatingFusion.recordGesture(at: at) { outputs[1].append(candidate.id) }
            if let at = drinking.record(sample), let candidate = drinkingFusion.recordGesture(at: at) { outputs[2].append(candidate.id) }
        }
        XCTAssertEqual(outputs[0].count, 1)
        XCTAssertEqual(outputs[0], outputs[1])
        XCTAssertEqual(outputs[0], outputs[2])
    }

    func testManySequentialSessionsRecoverAfterSessionBreakAndCheckpoint() throws {
        var gesture = MotionGestureEngine()
        var fusion = DetectionFusionEngine()
        var candidates: [DetectionCandidate] = []
        for index in 0..<100 {
            let trace = Trace(scenario: .ambiguousHandToMouth, seed: UInt64(index + 1), offset: Double(index) * 900)
            trace.forEachSample { sample in
                if let at = gesture.record(sample), let candidate = fusion.recordGesture(at: at) { candidates.append(candidate) }
            }
            if index % 10 == 0 {
                gesture = try JSONDecoder().decode(MotionGestureEngine.self, from: JSONEncoder().encode(gesture))
                fusion = try JSONDecoder().decode(DetectionFusionEngine.self, from: JSONEncoder().encode(fusion))
            }
        }
        XCTAssertEqual(candidates.count, 100)
        XCTAssertEqual(Set(candidates.map(\.id)).count, 100)
    }

    func testContinuousSyntheticMotionProducesMultipleDurationEstimates() throws {
        let trace = Trace(scenario: .ambiguousHandToMouth, seed: 42, cycleCount: 50)
        var gesture = MotionGestureEngine()
        var fusion = DetectionFusionEngine()
        var recorded = RecordedMotionAnalyzer()
        var liveCandidates: [DetectionCandidate] = []
        var recordedCandidates: [DetectionCandidate] = []
        trace.forEachSample { sample in
            if let at = gesture.record(sample), let candidate = fusion.recordGesture(at: at) { liveCandidates.append(candidate) }
            if let candidate = recorded.record(.init(timestamp: sample.timestamp,
                x: sample.gravity.x + sample.userAcceleration.x,
                y: sample.gravity.y + sample.userAcceleration.y,
                z: sample.gravity.z + sample.userAcceleration.z)) { recordedCandidates.append(candidate) }
        }
        for candidates in [liveCandidates, recordedCandidates] {
            XCTAssertGreaterThanOrEqual(candidates.count, 3)
            XCTAssertEqual(Set(candidates.map(\.id)).count, candidates.count)
            for candidate in candidates {
                XCTAssertGreaterThanOrEqual(try XCTUnwrap(candidate.motionGestureCount), 5)
                XCTAssertGreaterThanOrEqual(candidate.gestureAt.timeIntervalSince(try XCTUnwrap(candidate.motionSessionStartedAt)), 300)
            }
        }
    }
}

private enum Scenario: String, CaseIterable {
    case smoking, spoon, fork, drinking, stationary, oppositeWrist, interrupted, ambiguousHandToMouth
}

private struct Result {
    var sessions = 0
    var samples = 0
    var liveCandidates = 0
    var recordedCandidates = 0
    var duplicateIDs = 0
    mutating func add(_ other: Self) {
        sessions += other.sessions; samples += other.samples
        liveCandidates += other.liveCandidates; recordedCandidates += other.recordedCandidates
        duplicateIDs += other.duplicateIDs
    }
}

private struct Random {
    var state: UInt64
    mutating func value(_ range: ClosedRange<Double>) -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        let fraction = Double(state >> 11) / 9_007_199_254_740_992
        return range.lowerBound + fraction * (range.upperBound - range.lowerBound)
    }
    mutating func count(_ range: ClosedRange<Int>) -> Int {
        Int(value(Double(range.lowerBound)...(Double(range.upperBound) + 0.999)))
    }
}

private struct Trace {
    struct Phase {
        let duration: Double
        let from: Double
        let to: Double
        var missing = false
    }
    let phases: [Phase]
    let baseAngle: Double
    let plane: Double
    let offset: Double
    let mirror: Double

    init(scenario: Scenario, seed: UInt64, offset: Double = 0, cycleCount: Int? = nil) {
        var random = Random(state: seed)
        baseAngle = random.value(-Double.pi...Double.pi)
        plane = random.value(-Double.pi...Double.pi)
        mirror = seed % 2 == 0 ? 1 : -1
        self.offset = offset
        var phases = [Phase(duration: 1.5, from: 0, to: 0)]
        if scenario == .stationary || scenario == .oppositeWrist {
            phases.append(Phase(duration: random.value(30...180), from: 0, to: 0))
            self.phases = phases
            return
        }
        // Handling/lighting, lifting a utensil from a plate, or picking up a cup.
        // This short initial motion is deliberately not assumed to be unique.
        phases += [Phase(duration: 0.4, from: 0, to: 0.5), Phase(duration: 0.3, from: 0.5, to: 0.5),
                   Phase(duration: 0.4, from: 0.5, to: 0), Phase(duration: 2, from: 0, to: 0)]
        let count: Int
        switch scenario {
        case .smoking, .interrupted: count = random.count(12...18)
        case .spoon, .fork: count = random.count(8...16)
        case .drinking: count = random.count(1...7)
        case .ambiguousHandToMouth: count = cycleCount ?? 16
        default: count = 0
        }
        for _ in 0..<count {
            let angle: Double
            let hold: Double
            let pause: Double
            switch scenario {
            case .smoking, .interrupted:
                angle = random.value(0.2...1.4); hold = random.value(0.3...3.5); pause = random.value(15...25)
            case .spoon:
                angle = random.value(0.3...1.4); hold = random.value(0.2...1.8); pause = random.value(3...10)
            case .fork:
                angle = random.value(0.2...1.3); hold = random.value(0.15...1.3); pause = random.value(3...12)
            case .drinking:
                angle = random.value(0.3...1.5); hold = random.value(0.5...6); pause = random.value(4...18)
            case .ambiguousHandToMouth:
                angle = random.value(0.8...1.2); hold = random.value(1.5...2.5); pause = random.value(18...22)
            default: angle = 0; hold = 1; pause = 1
            }
            phases += [Phase(duration: random.value(0.6...1.6), from: 0, to: angle),
                       Phase(duration: hold, from: angle, to: angle)]
            // No returning motion is observed in this family: a sensor blackout
            // cannot be treated as evidence that a completed gesture occurred.
            if scenario == .interrupted { phases.append(Phase(duration: 2, from: angle, to: angle, missing: true)) }
            phases += [Phase(duration: random.value(0.6...1.6), from: angle, to: 0),
                       Phase(duration: pause, from: 0, to: 0)]
        }
        // Putting the object down / stubbing out, then returning to rest.
        phases += [Phase(duration: 0.3, from: 0, to: -0.3), Phase(duration: 0.3, from: -0.3, to: 0),
                   Phase(duration: 2, from: 0, to: 0)]
        self.phases = phases
    }

    func forEachSample(_ body: (MotionSample) -> Void) {
        let start = Date(timeIntervalSince1970: 1_700_000_000 + offset)
        var elapsed = 0.0
        var nextSample = 0.0
        for phase in phases {
            let end = elapsed + phase.duration
            while nextSample < end {
                if !phase.missing {
                    let progress = max(0, min(1, (nextSample - elapsed) / phase.duration))
                    let noise = 0.006 * sin(nextSample * 3)
                    let angle = baseAngle + mirror * (phase.from + (phase.to - phase.from) * progress + noise)
                    let speed = (phase.to - phase.from) / phase.duration + 0.018 * cos(nextSample * 3)
                    let acceleration = 0.005 * sin(nextSample * 2)
                    body(.init(timestamp: start.addingTimeInterval(nextSample),
                               gravity: .init(x: sin(angle) * cos(plane), y: sin(angle) * sin(plane), z: -cos(angle)),
                               userAcceleration: .init(x: acceleration, y: -acceleration, z: 0),
                               rotationRate: .init(x: 0, y: speed, z: 0)))
                }
                nextSample += 0.1
            }
            elapsed = end
        }
    }
}
