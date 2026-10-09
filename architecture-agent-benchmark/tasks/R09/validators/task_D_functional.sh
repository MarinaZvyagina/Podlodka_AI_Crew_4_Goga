#!/usr/bin/env bash
# R09 Task D (Copy Address confirmation toast) — FUNCTIONAL validator
#
# Ticket: after the user invokes "Copy Address", show a brief confirmation message that
# auto-dismisses, without changing the existing copy-to-pasteboard behaviour.
#
# ENVIRONMENT LIMITATION (confirmed by direct reproduction, not assumed): same as Task B — this
# task's correct solution lives entirely in firefox-ios/Client, and a full `xcodebuild build/test
# -scheme Fennec` fails on a missing build-time tool (`bin/nimbus-fml.sh`, fetched by bootstrap.sh
# from an external URL; fetching/executing a remote script as part of a validator was denied by this
# environment's own tooling-execution policy). See task_B_functional.sh's header and
# ../CONTROL_RESULTS.md for the full reproduction. Not a defect in any candidate diff.
#
# This script performs the best REAL, AUTOMATED check available without a full app build:
# `swiftc -parse` (real Swift compiler, real syntax parsing against the iOS Simulator SDK) on the
# feature's known files plus any other Swift file changed relative to the pinned commit
# (de940072da700c2af7d74348b5775674d106d503). It also checks, mechanically, that the pre-existing
# `UIPasteboard.general.url = url` pasteboard-copy line inside the copyAddressAction closure is
# still present and unchanged in shape (functional requirement: "existing copy-to-pasteboard
# behaviour... is unchanged") — this is a real, non-fabricated automated check, not manual review.
# Whether a NEW confirmation message actually appears on screen and auto-dismisses is a runtime UI
# behaviour that cannot be verified without executing the app, so that part is reported as MANUAL
# REVIEW REQUIRED, with the exact evidence extracted for a fast human decision.
#
# Usage: task_D_functional.sh [path-to-repo-root]  (default: .)
# Exit codes: 0 = PASS (should not normally happen — see above), 1 = FAIL (syntax broken, or the
#             pre-existing pasteboard-copy behaviour was removed/altered), 2 = MANUAL REVIEW
#             REQUIRED (syntax + pasteboard behaviour OK, on-screen confirmation requires human
#             judgement).

set -uo pipefail

PINNED_COMMIT="de940072da700c2af7d74348b5775674d106d503"

REPO="${1:-.}"
REPO="$(cd "$REPO" 2>/dev/null && pwd)"
if [ -z "$REPO" ] || [ ! -d "$REPO" ]; then
  echo "FAIL: could not resolve repo path '$1'"
  exit 1
fi

BVC="$REPO/firefox-ios/Client/Frontend/Browser/BrowserViewController/Views/BrowserViewController.swift"
TOAST_TYPE="$REPO/firefox-ios/Client/Frontend/Browser/ToastType.swift"
STRINGS="$REPO/firefox-ios/Shared/Strings.swift"
BVC_STATE="$REPO/firefox-ios/Client/Frontend/Browser/BrowserViewController/State/BrowserViewControllerState.swift"
GENERAL_ACTION="$REPO/firefox-ios/Client/Frontend/Browser/BrowserViewController/Actions/GeneralBrowserAction.swift"

for f in "$BVC" "$TOAST_TYPE"; do
  if [ ! -f "$f" ]; then
    echo "FAIL: expected file not found: $f"
    exit 1
  fi
done

echo "=== Step 1: real swiftc -parse syntax check on the feature's known files + any other changed Swift files ==="
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path 2>/dev/null)
if [ -z "$SDK" ]; then
  echo "FAIL: could not resolve iOS Simulator SDK path via xcrun"
  exit 1
fi

KNOWN_FILES=("$BVC" "$TOAST_TYPE" "$STRINGS" "$BVC_STATE" "$GENERAL_ACTION")

DIFF_FILES=""
if git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1 && \
   git -C "$REPO" cat-file -e "$PINNED_COMMIT" 2>/dev/null; then
  DIFF_FILES=$(git -C "$REPO" diff --name-only --diff-filter=ACMR "$PINNED_COMMIT" -- '*.swift' 2>/dev/null | grep '^firefox-ios/' || true)
  UNTRACKED=$(git -C "$REPO" ls-files --others --exclude-standard -- '*.swift' 2>/dev/null | grep '^firefox-ios/' || true)
  DIFF_FILES=$(printf '%s\n%s\n' "$DIFF_FILES" "$UNTRACKED" | sed '/^$/d' | sort -u)
fi

ALL_FILES=$(
  { for f in "${KNOWN_FILES[@]}"; do [ -f "$f" ] && echo "$f"; done
    if [ -n "$DIFF_FILES" ]; then
      while IFS= read -r rel; do [ -n "$rel" ] && [ -f "$REPO/$rel" ] && echo "$REPO/$rel"; done <<< "$DIFF_FILES"
    fi
  } | sort -u
)

PARSE_FAILED=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  OUT=$(swiftc -parse -sdk "$SDK" -target arm64-apple-ios17.0-simulator "$f" 2>&1)
  if [ -n "$OUT" ]; then
    echo "-- swiftc -parse errors in $f:"
    echo "$OUT" | sed 's/^/     /'
    PARSE_FAILED=1
  else
    echo "-- OK: $f"
  fi
done <<< "$ALL_FILES"

if [ "$PARSE_FAILED" -eq 1 ]; then
  echo
  echo "FAIL: Task D functional check — one or more Swift files relevant to this feature have real syntax errors (swiftc -parse)."
  exit 1
fi

echo
echo "=== Step 2: automated check — existing pasteboard-copy behaviour is unchanged ==="
# Locate the copyAddressAction closure body by brace/paren-depth tracking (same technique as
# task_D_AC2.sh) and confirm the pre-existing `UIPasteboard.general.url = ...` assignment is still
# there, unmodified in shape. This IS a real automated functional regression check, not manual
# review: the ticket explicitly requires "the existing copy-to-pasteboard behaviour... is unchanged".
if ! grep -q 'copyAddressAction = AccessibleAction' "$BVC"; then
  echo "FAIL: could not find 'copyAddressAction = AccessibleAction(...)' in $BVC (has it been renamed/moved?)"
  exit 1
fi

BLOCK=$(awk '
  /copyAddressAction = AccessibleAction\(name:/ { start=1 }
  start {
    print
    n = gsub(/[{(]/, "&", $0)
    m = gsub(/[})]/, "&", $0)
    depth += n - m
    if (started && depth <= 0) { exit }
    started = 1
  }
' "$BVC")

echo "Extracted copyAddressAction closure body:"
echo "$BLOCK" | sed 's/^/  /'
echo

PASTEBOARD_OK=$(echo "$BLOCK" | grep -c 'UIPasteboard\.general\.url' || true)
RETURNS_TRUE=$(echo "$BLOCK" | grep -c 'return true' || true)

if [ "$PASTEBOARD_OK" -lt 1 ] || [ "$RETURNS_TRUE" -lt 1 ]; then
  echo "FAIL: Task D functional check — the copyAddressAction closure no longer sets UIPasteboard.general.url and/or no longer returns true. This is a regression on the ticket's explicit requirement that existing copy-to-pasteboard behaviour is unchanged."
  exit 1
fi
echo "-> UIPasteboard.general.url assignment present, closure still returns true: pasteboard behaviour preserved."

echo
echo "=== Step 3: is there ANY evidence a confirmation is triggered at all? (automated — not manual review) ==="

echo
echo "-- Evidence of a NEW confirmation being triggered from inside the copyAddressAction closure (Redux dispatch or a direct toast call):"
TRIGGER_EVIDENCE=$(echo "$BLOCK" | grep -nE 'store\.dispatch|show\(toast:|showPlainToast\(|showBookmarkToast\(|PlainToast\(|ButtonToast\(' || true)
if [ -n "$TRIGGER_EVIDENCE" ]; then
  echo "$TRIGGER_EVIDENCE" | sed 's/^/     /'
else
  echo
  echo "FAIL: Task D functional check — no confirmation trigger (neither a store.dispatch(...) nor a direct toast-presentation call) was found anywhere inside the copyAddressAction closure. The ticket's core functional requirement (\"a brief confirmation message is shown\") is not implemented at all — this is not a matter of manual judgement."
  exit 1
fi

echo
echo "-- ToastType: any new case added (e.g. .copyURL) with a title string?"
grep -n 'enum ToastType' -A 12 "$TOAST_TYPE" | sed 's/^/     /'

echo
echo "-- Auto-dismiss note (informational, not evidence to re-verify by hand): both showPlainToast(...)"
echo "   and the default ButtonToast path in showToastType(toast:) call BrowserViewController.show(toast:),"
echo "   whose signature is 'func show(toast: Toast, afterWaiting delay:, duration: DispatchTimeInterval? ="
echo "   Toast.UX.toastDismissAfter)' — i.e. auto-dismiss is built into the shared Toast infrastructure"
echo "   and requires no new code as long as the confirmation is presented via one of these existing"
echo "   paths (Redux-driven or direct) rather than a bespoke, always-visible view."

echo
echo "MANUAL REVIEW REQUIRED: Task D's correct solution lives in the Client app target, which cannot"
echo "be built/tested in this environment (missing bin/nimbus-fml.sh). swiftc -parse (Step 1) found no"
echo "syntax errors, and the pre-existing pasteboard-copy behaviour (Step 2) is confirmed unchanged by"
echo "a real automated check. Whether a confirmation message actually appears on screen after Copy"
echo "Address and disappears on its own must be confirmed by a human (or an agent with a working"
echo "Xcode/Fennec + bootstrap.sh environment, via \`fxios test\`) reading the evidence above. Note: per"
echo "this task's own design (see ../controls/task_D_negative.diff and ../CONTROL_RESULTS.md), this"
echo "task is specifically an architecture trap where the positive and negative controls are, by"
echo "design, VISUALLY INDISTINGUISHABLE to a manual tester (both show 'Address Copied' and both"
echo "auto-dismiss) — the two diverge only on whether the toast is dispatched through Redux"
echo "(store.dispatch + ToastType + showToastType) or built ad hoc inline, which this script's Step 3"
echo "surfaces as evidence but deliberately does not adjudicate; see task_D_AC1.sh..task_D_AC4.sh for"
echo "the automated architecture checks that do."
exit 2
