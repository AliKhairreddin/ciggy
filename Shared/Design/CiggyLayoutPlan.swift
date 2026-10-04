import Foundation

/// Window geometry, rather than a device name, drives every Ciggy layout.
public struct CiggyLayoutPlan: Equatable {
	public enum Mode: String, Equatable {
		case single, columns, book, tabletop
		public var isFolded: Bool { self == .book || self == .tabletop }
	}

	public let mode: Mode
	public let overview: CGRect
	public let controls: CGRect?

	public init(
		size: CGSize,
		regularWidth: Bool,
		accessibilitySize: Bool = false,
		division: CGRect? = nil,
		rightToLeft: Bool = false
	) {
		let bounds = CGRect(origin: .zero, size: size)
		// A division frame already includes the system's interactive margins.
		if let division, division.width > 0, division.height > 0 {
			let fold = bounds.intersection(division)
			if !fold.isNull, fold.width > fold.height,
			   fold.minY > 0, fold.maxY < size.height {
				mode = .tabletop
				overview = CGRect(x: 0, y: 0, width: size.width, height: fold.minY)
				controls = CGRect(x: 0, y: fold.maxY, width: size.width, height: size.height - fold.maxY)
				return
			}
			if !fold.isNull, fold.height > fold.width,
			   fold.minX > 0, fold.maxX < size.width {
				mode = .book
				let left = CGRect(x: 0, y: 0, width: fold.minX, height: size.height)
				let right = CGRect(x: fold.maxX, y: 0, width: size.width - fold.maxX, height: size.height)
				overview = rightToLeft ? right : left
				controls = rightToLeft ? left : right
				return
			}
			// A narrow multitasking window can intersect just one edge of the
			// hinge. Use its remaining region without creating an empty panel.
			if !fold.isNull, fold.width > fold.height, fold.height < size.height {
				mode = .single
				overview = fold.minY == 0
					? CGRect(x: 0, y: fold.maxY, width: size.width, height: size.height - fold.maxY)
					: CGRect(x: 0, y: 0, width: size.width, height: fold.minY)
				controls = nil
				return
			}
			if !fold.isNull, fold.height > fold.width, fold.width < size.width {
				mode = .single
				overview = fold.minX == 0
					? CGRect(x: fold.maxX, y: 0, width: size.width - fold.maxX, height: size.height)
					: CGRect(x: 0, y: 0, width: fold.minX, height: size.height)
				controls = nil
				return
			}
		}

		if size.width >= 600, (regularWidth || size.width > size.height), !accessibilitySize {
			mode = .columns
			let width = (size.width - 18) / 2
			let left = CGRect(x: 0, y: 0, width: width, height: size.height)
			let right = CGRect(x: width + 18, y: 0, width: width, height: size.height)
			overview = rightToLeft ? right : left
			controls = rightToLeft ? left : right
		} else {
			mode = .single
			overview = bounds
			controls = nil
		}
	}
}
