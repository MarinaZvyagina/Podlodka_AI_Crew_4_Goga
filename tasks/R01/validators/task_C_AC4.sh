#!/usr/bin/env bash
# AC4: freqtradebot.py's protection call site (handle_protections(), and the
# execute_entry() entry-guard path) is unmodified. Expect either an empty
# diff, or a diff whose changed line ranges do not intersect the current
# handle_protections()/execute_entry() method bodies (config/import-only
# changes are fine).
set -uo pipefail
REPO="${1:-.}"
FILE="$REPO/freqtrade/freqtradebot.py"

if [[ ! -f "$FILE" ]]; then
    echo "FAIL: $FILE not found"
    exit 1
fi

if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "FAIL: $REPO is not a git repository -- cannot diff against HEAD"
    exit 1
fi

DIFF=$(git -C "$REPO" diff -- freqtrade/freqtradebot.py)
if [[ -z "$DIFF" ]]; then
    echo "PASS: freqtrade/freqtradebot.py has an empty diff -- handle_protections()/execute_entry() unchanged"
    exit 0
fi

func_range() {
    # $1 = function name (e.g. "handle_protections")
    local start rel_end end total
    start=$(grep -n "^    def $1(" "$FILE" | head -1 | cut -d: -f1)
    if [[ -z "$start" ]]; then
        echo ""
        return
    fi
    total=$(wc -l < "$FILE")
    rel_end=$(tail -n +"$((start + 1))" "$FILE" | grep -n "^    def " | head -1 | cut -d: -f1)
    if [[ -n "$rel_end" ]]; then
        end=$((start + rel_end - 1))
    else
        end=$total
    fi
    echo "$start $end"
}

HP_RANGE=$(func_range "handle_protections")
EE_RANGE=$(func_range "execute_entry")

if [[ -z "$HP_RANGE" ]]; then
    echo "FAIL: could not locate handle_protections() in $FILE (unexpected -- cannot verify AC4)"
    exit 1
fi

HP_START=$(echo "$HP_RANGE" | cut -d' ' -f1)
HP_END=$(echo "$HP_RANGE" | cut -d' ' -f2)
EE_START=$(echo "$EE_RANGE" | cut -d' ' -f1)
EE_END=$(echo "$EE_RANGE" | cut -d' ' -f2)

# Extract "@@ -a,b +c,d @@" hunk headers (new-file side) with zero context.
HUNKS=$(git -C "$REPO" diff -U0 -- freqtrade/freqtradebot.py | grep -E '^@@' | sed -E 's/^@@ -[0-9,]+ \+([0-9]+)(,([0-9]+))? @@.*/\1 \3/')

OVERLAP=""
while IFS=' ' read -r new_start new_count; do
    [[ -z "$new_start" ]] && continue
    count="${new_count:-1}"
    new_end=$((new_start + count - 1))
    if [[ -n "$HP_START" ]] && (( new_start <= HP_END && new_end >= HP_START )); then
        OVERLAP="handle_protections() (lines $HP_START-$HP_END), changed lines $new_start-$new_end"
        break
    fi
    if [[ -n "$EE_START" ]] && (( new_start <= EE_END && new_end >= EE_START )); then
        OVERLAP="execute_entry() (lines $EE_START-$EE_END), changed lines $new_start-$new_end"
        break
    fi
done <<< "$HUNKS"

if [[ -n "$OVERLAP" ]]; then
    echo "FAIL: freqtrade/freqtradebot.py diff modifies control flow inside $OVERLAP -- protection call site was changed"
    echo "$DIFF"
    exit 1
fi

echo "PASS: freqtrade/freqtradebot.py has a non-empty diff, but no changed lines fall inside handle_protections()/execute_entry() -- looks like config/import-only changes"
echo "$DIFF"
exit 0
