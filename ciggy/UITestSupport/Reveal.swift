import XCTest

extension XCUIElement {
    @MainActor
    func reveal(maxAttempts: Int, advance: () -> Void) {
        for _ in 0..<maxAttempts {
            if isHittable { return }
            advance()
        }
    }
}
