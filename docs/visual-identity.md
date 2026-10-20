# Ciggy visual identity

Ciggy pairs a playful cigarette character with a warm paper-and-ink identity. The iPhone uses cream graph paper, peach and ember, lilac illustration notes, rounded typography, and a cigarette-pack daily-limit meter. Both companion apps default to cream and use the same character, icon, and warmer accents. Settings offers **Cream**, **Dark**, and **Follow System**. Changes apply immediately and persist separately on each device, so incoming detection and goal settings never replace a local appearance choice. Follow System uses the current device’s SwiftUI color scheme. Dark appearance adapts text, cards, glass controls, charts, character details, and the Today poster to a warm plum palette. Watch uses a continuous copper-to-cream wash behind the native clock and navigation, with a plum wash in Dark appearance. There is no separate dark clock strip.

Siggy uses one transparent illustration shared by both apps and their layered icons. His arms and legs join the body continuously, with a scalloped ash cap, cream paper, an orange filter, and dark espresso outlines. The shared `CiggyMascot` displays that artwork on every existing mascot placement. On Today it gently sways and bobs as one connected character. Decorative artwork has no accessibility label. Motion stops when Reduce Motion is enabled, the scene becomes inactive, or the character leaves the screen. Secondary-screen and Watch illustrations stay still. A subtle light rim keeps his dark limbs readable on dark surfaces.

## Layered app icons

Both app targets contain an `AppIcon.icon` document created with Apple's Icon Composer. A solid apricot background (`#F0AD78`) sits behind the separate Siggy foreground group. The character remains opaque; Icon Composer supplies specular lighting and a restrained native shadow. The source contains no decorative circle, gradient, sparkles, baked mask, or baked glass effects. The system provides the rounded-square iOS and circular watchOS masks and appearance variants.

The foreground is scaled to 72% and shifted 20 points left in the shared 1024-point layout so the whole character, including smoke and shoes, stays inside both masks. The iOS and Watch documents contain identical artwork and settings. Both existing Xcode synchronized target folders include their `.icon` document automatically, and both targets retain `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`. Xcode compiles the layered rendition and the required legacy icon sizes; the old flat app-icon sets have been removed.

`Shared/Resources/SiggyArtwork.xcassets/Siggy.imageset/Siggy.png` is the matching in-app image, loaded from the Swift package's resource bundle. Keep it byte-identical to the `Assets/Siggy.png` in both icon documents. See [the artwork prompt](siggy-artwork-prompt.md) for the generation brief.

## Fictional pack wallpaper

Three original parody brands live on the graph-paper background of both apps. **Ashford** is a burgundy, old-money label ("Old money. New ash."); **Égo** uses petrol-green art-deco packaging ("A very expensive air."); **Later** uses a burnt-orange sunset clock ("Tomorrow’s finest.", "Since eventually"). The jokes target the inflated promises of packaging and procrastination. The reference was the world-building approach of GTA's fictional brands; no GTA logos, names, images, or pack artwork are included.

`Shared/Design/CiggyPackArtwork.swift` draws the packs as scalable SwiftUI vectors, including their lettering, folded lids, side panels, invented seals, and subtle print grain. On iPhone, the shared `CiggyBackdrop` places all three at stable, irregular angles behind scrolling content. Cards remain in the foreground; the collage peeks through the paper around them. Watch omits the pack collage to keep its small screen readable. The background has no animation or hit targets and is hidden from accessibility. It never changes counts, goals, or logging behavior.

Watch Today sizes its progress ring to the available screen height, keeps the count unobstructed, and shows the full logging button before secondary status cards. Logging uses a compact character header and note field; native Back cancels without saving. Weekly includes weekday labels and a nonzero chart scale even with empty history. Secondary content remains scrollable with native Watch navigation.

Siggy keeps his friendly diagonal stance. His face stays dark on the cream body in either appearance.

Controls use native Liquid Glass on iOS/watchOS 26 and later, with regular material on supported earlier systems. Reduce Transparency replaces custom glass with an opaque surface. Content cards remain paper-like surfaces. The system TabView supplies native tab semantics and glass navigation. Headings use Dynamic Type, and Today falls back to a vertical character layout when the count and drawing cannot fit side by side.

Phone logging is available from Today. Its sheet accepts an optional note and records one manual event. Save sends that event through the existing paired-device connectivity path. The confirmation offers Undo, which removes the same event ID and sends the deletion through the existing tombstone-aware sync path. Cancel leaves the repository unchanged. No sample events are inserted by the redesign.

## Validation

Run `swift test` with the full Xcode developer directory, then build the `ciggy` scheme for an iPhone simulator and for generic iOS Release. That scheme embeds and builds the Watch companion. The UI tests cover phone logging, cancellation, undo persistence, goal persistence, the four branded screens, large-text logging, the historical detection preview, and immediate appearance changes and persistence on both devices.

The signed archive is distributed through App Store Connect and TestFlight. See [TestFlight delivery](testflight.md) for the established upload workflow and the difference between a successful upload and an installable beta.
