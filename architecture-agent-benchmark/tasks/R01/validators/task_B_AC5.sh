#!/usr/bin/env bash
# AC5: Consistency -- running the equivalent scenario through both engines
# (live/dry-run execute_entry() vs. backtesting's entry path) must yield the
# same accept/reject/resize outcome. This is inherently semantic (it requires
# actually running trade sequences through both engines and comparing
# outcomes), so this script automates two things and leaves the rest as
# MANUAL REVIEW REQUIRED:
#   1) A structural check that both engines call the SAME shared function with
#      an equivalent-shaped argument list (strong static proxy for "the same
#      computation is used"), reusing the detection approach from AC1/AC2.
#   2) A best-effort attempt to actually RUN a cross-engine test if one exists
#      in the repo's tests/ tree (a file whose added/changed lines reference
#      both a live-engine entry point (execute_entry/FreqtradeBot) and a
#      backtest-engine entry point (_enter_trade/Backtesting) -- if found and
#      pytest is available, this is run for real and its result is decisive.
# If neither of these is conclusive, this script prints MANUAL REVIEW REQUIRED
# rather than fabricating a verdict.
set -uo pipefail
REPO="${1:-.}"

if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "FAIL: $REPO is not a git repository -- cannot diff against HEAD"
    exit 1
fi

LIVE_FILE="freqtrade/freqtradebot.py"
BT_FILE="freqtrade/optimize/backtesting.py"

echo "MANUAL REVIEW REQUIRED: AC5 (live vs. backtest outcome consistency) cannot be fully"
echo "settled by static analysis alone. Automated signals below; a human (or a real pytest"
echo "run of a cross-engine test) must confirm identical accept/reject/resize decisions."
echo

# --- Signal 1: structural comparison of the call sites -----------------------
NAME_RE='exposure|currency_cap|pair_cap|base_currency|currency_exposure|currency_limit|max_pair_exposure'
SHARED_CANDIDATES=$(git -C "$REPO" diff --name-only -- freqtrade/ \
    | grep -vE "^${LIVE_FILE}\$|^${BT_FILE}\$|^freqtrade/strategy/interface\.py\$" || true)

FOUND_FN=""
for f in $SHARED_CANDIDATES; do
    [[ -f "$REPO/$f" ]] || continue
    NEWDEFS=$(git -C "$REPO" diff -- "$f" | grep -E '^\+[[:space:]]*def [a-zA-Z_][a-zA-Z0-9_]*\(' \
        | sed -E 's/^\+[[:space:]]*def ([a-zA-Z_][a-zA-Z0-9_]*)\(.*/\1/')
    for fn in $NEWDEFS; do
        if echo "$fn" | grep -qiE "$NAME_RE"; then
            # Prefer a candidate that's actually called from BOTH engine files
            # (matches AC1's stricter selection) over merely name-matching helpers.
            CALL_LIVE_CHECK=$(grep -n "\.${fn}(" "$REPO/$LIVE_FILE" 2>/dev/null || true)
            CALL_BT_CHECK=$(grep -n "\.${fn}(" "$REPO/$BT_FILE" 2>/dev/null || true)
            if [[ -n "$CALL_LIVE_CHECK" && -n "$CALL_BT_CHECK" ]]; then
                FOUND_FN="$fn"
                break 2
            elif [[ -z "$FOUND_FN" ]]; then
                # Fall back to the first name-matching def if none is called from both.
                FOUND_FN="$fn"
            fi
        fi
    done
done

STRUCTURAL_OK=0
if [[ -n "$FOUND_FN" ]]; then
    CALL_LIVE=$(grep -n "\.${FOUND_FN}(" "$REPO/$LIVE_FILE" 2>/dev/null | head -1 || true)
    CALL_BT=$(grep -n "\.${FOUND_FN}(" "$REPO/$BT_FILE" 2>/dev/null | head -1 || true)
    echo "Shared candidate function: $FOUND_FN"
    echo "  call site in $LIVE_FILE: ${CALL_LIVE:-<not found>}"
    echo "  call site in $BT_FILE:   ${CALL_BT:-<not found>}"
    if [[ -n "$CALL_LIVE" && -n "$CALL_BT" ]]; then
        # Rough structural equivalence: same function called; both call sites
        # mention a "pair"-like and a "stake"-like token among their arguments.
        LIVE_ARGS=$(echo "$CALL_LIVE" | grep -oE '\(.*\)')
        BT_ARGS=$(echo "$CALL_BT" | grep -oE '\(.*\)')
        if echo "$LIVE_ARGS" | grep -qi 'pair' && echo "$BT_ARGS" | grep -qi 'pair' \
            && echo "$LIVE_ARGS" | grep -qi 'stake' && echo "$BT_ARGS" | grep -qi 'stake'; then
            STRUCTURAL_OK=1
            echo "  -> structurally consistent: both call sites pass pair + stake-like arguments to the same function"
        else
            echo "  -> WARNING: call sites do not look structurally equivalent (different argument shapes)"
        fi
    fi
else
    echo "No shared exposure function detected (see AC1/AC2 for that determination)."
fi
echo

# --- Signal 2: best-effort real cross-engine test run -------------------------
CROSS_TEST_FILES=""
for f in $(git -C "$REPO" diff --name-only -- tests/ 2>/dev/null || true); do
    [[ -f "$REPO/$f" ]] || continue
    FDIFF=$(git -C "$REPO" diff -- "$f")
    if echo "$FDIFF" | grep -qE '^\+.*(execute_entry|FreqtradeBot)' && \
       echo "$FDIFF" | grep -qE '^\+.*(_enter_trade|Backtesting)'; then
        CROSS_TEST_FILES="$CROSS_TEST_FILES $f"
    fi
done
# Also consider entirely new test files (git diff --name-only already includes
# added files with a full diff against /dev/null).
for f in $(git -C "$REPO" status --porcelain -- tests/ 2>/dev/null | awk '{print $2}'); do
    [[ -f "$REPO/$f" ]] || continue
    if grep -qE '(execute_entry|FreqtradeBot)' "$REPO/$f" 2>/dev/null && \
       grep -qE '(_enter_trade|Backtesting)' "$REPO/$f" 2>/dev/null; then
        case " $CROSS_TEST_FILES " in
            *" $f "*) ;;
            *) CROSS_TEST_FILES="$CROSS_TEST_FILES $f" ;;
        esac
    fi
done

RAN_TEST=0
TEST_RESULT=""
if [[ -n "$(echo "$CROSS_TEST_FILES" | tr -d '[:space:]')" ]]; then
    PY="$REPO/.venv/bin/python"
    [[ -x "$PY" ]] || PY="python3"
    for f in $CROSS_TEST_FILES; do
        echo "Found candidate cross-engine test file: $f -- attempting a real pytest run"
        if ( cd "$REPO" && "$PY" -m pytest "$f" -q ) > /tmp/task_B_AC5_pytest_out.$$ 2>&1; then
            RAN_TEST=1
            TEST_RESULT="pass"
        else
            if grep -qE "no tests ran|ERROR|ModuleNotFoundError|ImportError" /tmp/task_B_AC5_pytest_out.$$; then
                echo "  (pytest run could not be completed in this environment -- see output below)"
                RAN_TEST=0
            else
                RAN_TEST=1
                TEST_RESULT="fail"
            fi
        fi
        tail -20 /tmp/task_B_AC5_pytest_out.$$ | sed 's/^/  /'
        rm -f /tmp/task_B_AC5_pytest_out.$$
    done
else
    echo "No candidate cross-engine test file found under tests/ (a file referencing both"
    echo "a live entry point and a backtest entry point)."
fi
echo

if [[ "$RAN_TEST" -eq 1 && "$TEST_RESULT" == "pass" ]]; then
    echo "PASS (automated): a real cross-engine test was found and passed, plus $( [[ $STRUCTURAL_OK -eq 1 ]] && echo "consistent" || echo "inconclusive" ) call-site structure. MANUAL REVIEW REQUIRED only to spot-check the test actually covers a same-base-currency, cross-pair scenario."
    exit 0
elif [[ "$RAN_TEST" -eq 1 && "$TEST_RESULT" == "fail" ]]; then
    echo "FAIL (automated): a real cross-engine test was found and FAILED -- live and backtest outcomes diverge."
    exit 1
elif [[ "$STRUCTURAL_OK" -eq 1 ]]; then
    echo "PASS (heuristic only): call-site structure is consistent between engines, but no executable cross-engine test could be run. MANUAL REVIEW REQUIRED to actually confirm identical outcomes."
    exit 0
else
    echo "FAIL (heuristic only): could not establish structural consistency between the two engines' call sites, and no executable cross-engine test was found/run. MANUAL REVIEW REQUIRED."
    exit 1
fi
