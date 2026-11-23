---
name: verify-transport-receipts
description: Check the durable Watch outbox when changing completion callbacks, transport receipts, message kinds or snapshot persistence.
---

# Verify Watch transport receipts

Run the bounded Swift model on macOS. The Shared Swift tests workflow runs it with Xcode 27.2.

```sh
DEVELOPER_DIR=/Applications/dev/Xcode.app/Contents/Developer xcrun swift test --filter TransportReceiptModelTests
```

An event, deletion or review stays in the sender's outbox until its companion confirms a durable save. If the sender cannot save the removal, it retains the item for another attempt. System completions and matching legacy replies may retire the four control and status kinds. Future message kinds require a durable receipt by default.

The model enumerates every ordered pair of seven actions for one queued envelope of each of nine message kinds. The actions are system completion, matching legacy reply, reply with the wrong ID, matching v2 reply, explicit inbox receipt, failure to write a receipt, and restart. After each action it compares both the in-memory outbox and a separately reopened disk snapshot with the expected pending envelopes. The failure case temporarily makes the destination reject atomic replacement. The model covers completed callbacks and their persisted effects. WatchConnectivity timing, device pairing, receiver-side persistence and hardware power loss are outside this bound.

If the check fails, follow the reported callbacks in order. Inspect the persisted message kind and the evidence supplied to `confirm`. The caller parsing a compatible reply or receipt must supply the corresponding protocol version and message ID. Change the model only when the receiving and sending protocol contracts both support the new behavior.

In a disposable checkout, return `true` unconditionally from the `.systemTransfer` arm of `Confirmation.confirms`, then rerun. This restores the retirement rule from `a6a8594`. The first system completion drops the pending event. Restore the source and confirm that the model passes again.

Coverage at `63d57c8805e8f544aae9ea0c2cbda5178115e831` includes `ConnectivityTransportStore.confirm`, `Confirmation.confirms` and `ConnectivityEnvelope.requiresDurableReceipt` in `Shared/Services/ConnectivityTransportStore.swift`. The production inputs come from `flushPendingDurablePayloads`, `deliver` and the user-info completion delegate in `Shared/Services/ConnectivityManager.swift`. The model lives in `Tests/CiggySharedTests/TransportReceiptModelTests.swift`. Compare those paths when they change. Advance the coverage commit after rechecking the callback mapping, historical failure and passing model.
