import Foundation

/// Original, locally synthesized ambient music. No streaming service, account,
/// network request, microphone access, or recording is involved.
public enum CiggyAmbientLoop {
	public enum Track: String, CaseIterable, Sendable {
		case blueHour, slowSunday, afterHours
		public var title: String {
			switch self {
			case .blueHour: return "Blue hour"
			case .slowSunday: return "Slow Sunday"
			case .afterHours: return "After hours"
			}
		}
		public var subtitle: String {
			switch self {
			case .blueHour: return "Hold music for the habit."
			case .slowSunday: return "The ashtray can wait."
			case .afterHours: return "The lighter is off the clock."
			}
		}
	}

	public static let duration: TimeInterval = 24

	/// PCM WAV with quiet chord swells and a bell-like arpeggio. Every chord and
	/// the loop boundary fade to zero, avoiding clicks during indefinite playback.
	public static func waveData(for track: Track) -> Data {
		let rate = 22_050
		let count = rate * Int(duration)
		let roots: [Double]
		switch track {
		case .blueHour: roots = [130.8128, 110, 174.6141, 146.8324]
		case .slowSunday: roots = [146.8324, 123.4708, 195.9977, 164.8138]
		case .afterHours: roots = [110, 130.8128, 98, 116.5409]
		}
		let ratios = [1.0, 1.259921, 1.498307, 1.887749]
		let sequence = [0, 2, 1, 3, 2, 1, 0, 3]
		var data = Data(capacity: 44 + count * 2)
		func word(_ value: UInt16) {
			data.append(UInt8(value & 0xff)); data.append(UInt8(value >> 8))
		}
		func integer(_ value: UInt32) { word(UInt16(value & 0xffff)); word(UInt16(value >> 16)) }
		data.append(contentsOf: "RIFF".utf8); integer(UInt32(36 + count * 2))
		data.append(contentsOf: "WAVEfmt ".utf8); integer(16)
		word(1); word(1); integer(UInt32(rate)); integer(UInt32(rate * 2)); word(2); word(16)
		data.append(contentsOf: "data".utf8); integer(UInt32(count * 2))
		for sample in 0..<count {
			let time = Double(sample) / Double(rate)
			let chord = min(3, Int(time / 6))
			let local = time - Double(chord) * 6
			let envelope = pow(sin(.pi * local / 6), 2)
			let root = roots[chord]
			var value = 0.0
			for ratio in ratios {
				let phase = 2 * Double.pi * root * ratio * local
				value += (sin(phase) + 0.16 * sin(phase * 2)) * 0.045
			}
			let beat = Int(local / 0.75)
			let pluck = local.truncatingRemainder(dividingBy: 0.75)
			let note = root * ratios[sequence[min(7, beat)]] * 2
			value += sin(2 * .pi * note * pluck) * exp(-pluck * 5) * min(1, pluck / 0.025) * 0.10
			value += sin(2 * .pi * root / 2 * local) * 0.06
			value *= envelope
			let pcm = Int16(max(-1, min(1, value)) * Double(Int16.max))
			word(UInt16(bitPattern: pcm))
		}
		return data
	}
}
