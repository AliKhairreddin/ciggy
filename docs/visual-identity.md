# Ciggy visual identity

Ciggy pairs a playful cigarette character with a warm paper-and-ink identity. The iPhone uses cream graph paper, peach and ember, lilac illustration notes, rounded typography, and a cigarette-pack daily-limit meter. The Watch retains a dark canvas for glanceable counts and uses the same character, icon, and warmer accents.

The original character is drawn in SwiftUI Canvas. On Today it gently sways, blinks, waves, and animates its smoke ribbon. Decorative artwork has no accessibility label. Motion stops when Reduce Motion is enabled, the scene becomes inactive, or the character leaves the screen. Secondary-screen and Watch illustrations stay still.

Controls use native Liquid Glass on iOS/watchOS 26 and later, with regular material on supported earlier systems. Reduce Transparency replaces custom glass with an opaque surface. Content cards remain paper-like surfaces. The system TabView supplies native tab semantics and glass navigation. Headings use Dynamic Type, and Today falls back to a vertical character layout when the count and drawing cannot fit side by side.

Phone logging is available from Today. Its sheet accepts an optional note and records one manual event. Save sends that event through the existing paired-device connectivity path. The confirmation offers Undo, which removes the same event ID and sends the deletion through the existing tombstone-aware sync path. Cancel leaves the repository unchanged. No sample events are inserted by the redesign.

## Validation

Run `swift test` with the full Xcode developer directory, then build the `ciggy` scheme for an iPhone simulator and for generic iOS Release. That scheme embeds and builds the Watch companion. The UI tests cover phone logging, cancellation, undo persistence, goal persistence, the four branded screens, large-text logging, and the historical detection preview.

The repository currently has no App Store/TestFlight publishing workflow or hosting configuration. Simulator installation verifies the app locally; store distribution requires an existing signing and publishing workflow.
