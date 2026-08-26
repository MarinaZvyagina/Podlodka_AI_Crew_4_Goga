// === TASK_D_FUNCTIONAL_VALIDATOR_FIXTURE ===
// Injected temporarily by validators/task_D_functional.sh into
// SignalServiceKit/tests/Messages/DeleteForMe/DeleteForMeOutgoingSyncMessageManagerTest.swift (an existing,
// already-project-referenced test file for exactly the sync-message manager this feature must reuse), and
// stripped back out afterward. Not part of the permanent test suite.
//
// WHY THIS IS A CHECKLIST, NOT A LITERAL RUNNABLE ASSERTION:
// The task's own notes_for_positive_negative_control describe "a new UI action that only needs to call this
// one method" without mandating a fixed type/method name -- metadata_D.yaml's required_existing_abstractions
// name the *underlying* manager (`InteractionDeleteManager`, `DeleteForMeOutgoingSyncMessageManager`) that any
// correct implementation must route through, but not the name of the new "delete all my messages in this
// thread" entry point itself. (In this benchmark's own positive/negative control diffs both happen to converge
// on `DeleteAllMessagesSentByLocalUserManager.deleteAllMessagesSentByLocalUser(in:tx:)`, but hardcoding that
// exact name here would violate this task's explicit "not internal helpers specific to one candidate
// implementation" instruction -- an arbitrary candidate could legally call it anything, or wire it directly
// into a view-controller action with no separate manager type at all.)
//
// validators/task_D_functional.sh's automated signal is therefore a static/behavioral scan over the whole
// diff: does *some* new code path (a) select TSInteractions authored by the local user (TSOutgoingMessage) in
// a specific thread, and (b) actually remove them (via InteractionDeleteManager.delete(...) OR a direct
// anyRemove(transaction:) loop -- for FUNCTIONAL purposes only, this check is deliberately implementation-
// agnostic per this task's own notes: "Functional Success = true, Architecture Conformance = false" is the
// documented intended outcome for the negative/trap control). Which of the two deletion paths was used is what
// the architecture checks (task_D_AC1..AC4.sh) exist to distinguish, not this functional check.
//
// MANUAL QA CHECKLIST (perform against a running build with 2+ linked devices, e.g. primary iPhone + linked
// iPad/Desktop):
//   1. In a 1:1 or group conversation with messages from both the local user and other participant(s),
//      trigger "delete all messages I sent in this conversation."
//   2. Confirm only the local user's messages are removed; the other participant(s)' messages remain.
//   3. Confirm the conversation's preview text, unread state, and message list update immediately on the
//      device where the action was performed, without relaunching the app.
//   4. On a linked device (the actual multi-device sync path -- this is the one functional_requirements bullet
//      that a same-device automated/static check fundamentally cannot verify), confirm the same messages
//      disappear there too, without any manual action on that device.
//   5. If any deleted message corresponds to a call in that conversation, confirm the call history entry is
//      also removed/updated consistently (no call entry pointing at a now-nonexistent message).
//
// Step 4 in particular is the exact "dangerous success" scenario this task is designed to probe: a same-
// device-only implementation (the negative control) satisfies steps 1-3 but silently fails step 4. This
// fixture's checklist -- and validators/task_D_functional.sh's explicit "MANUAL REVIEW REQUIRED" output for
// multi-device sync -- exist so that gap is never silently scored as a full functional pass.
// === END TASK_D_FUNCTIONAL_VALIDATOR_FIXTURE ===
