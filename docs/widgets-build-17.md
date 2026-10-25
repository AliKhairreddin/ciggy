# Build 17 widgets and parody icons

The widget gallery now distinguishes **Cigarettes Today**, which counts recorded cigarettes, from **Daily Limit Remaining**, which shows how many remain before the limit. The remaining gauge decreases as the count rises. Compact layouts identify today, left, at-limit and over-limit values; exceeding the limit shows the excess instead of an unexplained zero. Small Home Screen widgets retain their titles, and the elapsed widget no longer includes an unrelated daily-count ring.

**Last 7 Days** describes the rolling period accurately. **Log a Cigarette** opens the existing form and still requires saving in the app. Existing widget/control identifiers and destinations are preserved. Gallery previews use synthetic examples, and accessibility labels identify the metric without relying on its icon.

Ten original custom symbols replace unrelated feature imagery across the apps, widgets, complications, Live Activity and controls. Cigarette-shaped chart bars, a cigarette clock hand and a cigarette-plus action carry Ciggy's packaging parody; savings uses coins. The assets retain symbol metadata, nine weights and three scales. The project's `AGENTS.md` now records the parody voice, visual direction and requirement to keep functional labels and data accurate. Supporting gallery copy adds paper-trail and receipt jokes without disguising count or limit states.

## Validation

- Swift package: 293 tests passed.
- Native iPhone: five unit tests and two navigation/goal/deep-link UI checks passed.
- Native paired Watch: two unit tests and the logging/relaunch UI check passed.
- A temporary native rendering harness was used to inspect small, circular, rectangular and inline layouts in light and dark appearances, including under/at/over-limit counts and empty/long timers. It was removed before the release archive and commit. Host rendering does not replace testing system-managed WidgetKit layouts on real devices.
- Original symbol catalogs compiled for iPhone, Watch and macOS. Native glyph previews were inspected at small sizes.
- Xcode source membership, shared library links, Watch embedding/dependency, companion identifiers and unchanged widget/control kind IDs were verified.
- Signed Release archive succeeded. All four executable bundles have version 1.0/build 17, verified signatures and all ten custom symbol assets.
- Staged changes were reviewed for credentials, private tester data and temporary/generated test artifacts.

Actual Control Center placements, Watch faces and the full physical-device appearance matrix still need validation. Recognition and background-check timing are unchanged.

## Delivery

Product commit `11d8796` was pushed to `main`. App Store Connect accepted and finished processing the signed build 17 upload. The exact 1,411-character What to Test body was saved and matched after a full page reload. The existing internal tester group is assigned and lists version 1.0 (17) as Testing.

Build-specific update details are in [the release notes](releases/build-17.md). This native app update does not require a server deployment.
