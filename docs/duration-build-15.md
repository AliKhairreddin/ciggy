# Build 15 duration-based estimates

The previous detector counted one connected smoking-like pattern and required a quiet gap before another count. Build 15 instead requires five minutes of qualifying evidence per estimated cigarette and can count successive segments during continued motion. Normal sensitivity still requires at least five completed gestures; high/low sensitivity requires four/seven. Each segment needs fresh gestures, and a qualifying gesture must complete the duration requirement before a count is emitted.

Five minutes is a research-informed engineering default, not a global average or a validated measurement of a cigarette. The [research rationale](cigarette-duration.md) describes the studies, population differences and limitations. Short cigarettes may be missed, long cigarettes may be split, and similar non-smoking motion can still create estimates.

Long pauses and missing sensor coverage discard incomplete duration evidence. Live sampling interruptions do not earn elapsed-time credit. Historical checkpoints preserve continuous evidence across processing batches; legacy detector checkpoints migrate without awarding previously elapsed time. Adjacent estimates remain distinct in the event repository, while shifted representations of the same segment, deletions and corrections retain replay protection.

## Validation

- Full Xcode toolchain at the project's configured installation.
- Swift package: 279 tests passed, including continuous duration segments, fresh evidence, idle time, missing source, checkpoint migration, interruption recovery, replay, corrections and synchronization.
- The package's 800 synthetic motion scenarios processed 1,675,345 samples through each pipeline. These invented inputs test software behavior; they do not establish real-world accuracy.
- Native iPhone simulator suite: five tests passed.
- Native paired Watch simulator suite: two tests passed.
- Xcode project source membership, shared framework links, Watch dependency/embedding and companion bundle identifier verified.
- Signed Release archive succeeded. The iPhone, Watch and both widget extensions have matching version 1.0/build 15 and verified signatures.
- Staged changes were checked for whitespace errors, secrets, private tester evidence and unintended generated files.

## Delivery

The product changes were committed to and pushed on `main`. App Store Connect accepted and finished processing the signed build 15 upload. The exact 1,275-character build-specific What to Test text was saved and matched after a full page reload. The existing internal tester group is assigned and lists version 1.0 (15) as Testing.

The exact build notes are recorded in [the release notes](releases/build-15.md). No server deployment is needed for this native app update. Real-device validation of detection accuracy and unattended latency remains necessary. Background analysis and iPhone delivery still depend on watchOS, so the five-minute evidence requirement is not a five-minute delivery guarantee.
