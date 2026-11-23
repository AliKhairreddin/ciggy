#if os(iOS) || os(watchOS)
import CoreMotion
import Foundation

public final class RecordedAccelerometer {
    private let recorder = CMSensorRecorder()

    public init() {}

    public static var authorizationStatus: CMAuthorizationStatus { CMSensorRecorder.authorizationStatus() }
    public static var isAvailable: Bool { CMSensorRecorder.isAccelerometerRecordingAvailable() }

    public func record(for duration: TimeInterval) {
        recorder.recordAccelerometer(forDuration: duration)
    }

    public var history: SensorHistoryQuery {
        SensorHistoryQuery { [recorder] start, end in
            guard let source = recorder.accelerometerData(from: start, to: end) else { return nil }
            var iterator = NSFastEnumerationIterator(source)
            return AnySequence { AnyIterator {
                guard let sample = iterator.next() as? CMRecordedAccelerometerData else { return nil }
                return RecordedAccelerationSample(timestamp: sample.startDate, x: sample.acceleration.x,
                                                  y: sample.acceleration.y, z: sample.acceleration.z)
            } }
        }
    }
}
#endif
