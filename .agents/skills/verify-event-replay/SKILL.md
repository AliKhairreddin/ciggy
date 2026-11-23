---
name: verify-event-replay
description: Check the persisted count after duplicate, reordered and interrupted deliveries when changing EventRepository event matching, deletion or snapshot loading.
---

# Verify Watch event replay

Run the bounded model from the repository root on macOS. CI runs the same test in the full Swift suite with Xcode 27.2.

```sh
DEVELOPER_DIR=/Applications/dev/Xcode.app/Contents/Developer xcrun swift test --filter EventReplayModelTests
```

A replay of the first estimate counts once. Its neighbor counts independently. A deletion hides the first estimate once the receiver has enough evidence to associate the deleted ID with it. A restart must preserve all three facts.

The checker generates every ordering of two adjacent five-minute segments, one replay shifted by 30 seconds, a deletion addressed to either version of the first segment, one duplicate replay or deletion, and one restart. It checks the visible log after each action. Each delivery calls the real Swift repository. Each restart opens its on-disk snapshot. The bound covers one receiving device, six actions, completed local writes and the specified synthetic intervals. WatchConnectivity scheduling, power loss during a filesystem operation and motion recognition are outside the model.

The checker prints the sequence through the first mismatch. Read it in order. A deletion for an unknown ID becomes visible to the user only when a matching event arrives. Verify whether the expected distinct segments and the point of alias discovery agree with the product semantics before changing the model. To check sensitivity in a disposable checkout, replace `Shared/Services/EventRepository.swift` with that file from `06c927a` and rerun. The adjacent segment disappears when it touches the prior interval. Restore the current source and rerun.

Coverage at `da3931359444301fb276da841c2b5d8652b504fd` includes `EventRepository.receiveEvent`, `receiveDeletion`, `automaticSessionID`, `install` and `publishDerivedEvents` in `Shared/Services/EventRepository.swift`, plus snapshot reads and writes in `Shared/Services/DurableSnapshotFile.swift`. The checker lives in `Tests/CiggySharedTests/EventReplayModelTests.swift`. When those paths change, compare their transitions with the model, rerun the historical failure and the current check, then advance the coverage commit.
