#!/usr/bin/env bash
# AC3: Dispatch wired through existing minion-side routing table, not a
#   parallel handler.
# method: review diff to Minion.manage_beacons() in salt/minion.py -- confirm
#   one new entry in the existing `funcs` dict, not a new elif/tag handler
#   block or a parallel manage_beacons-like function.
# expected_if_correct: exactly one new "key": ("method_name", {...}) entry
#   added to the existing funcs = {...} dict inside manage_beacons().
# expected_if_trap: no changes to salt/minion.py at all, or a brand new
#   elif tag.startswith(...) block / new dispatch function added instead of
#   extending the existing funcs dict.
set -u

REPO="${1:-.}"
BASE="bdb21a0937cfb8556a92fc6257f8f3c08bc4c32d"

cd "$REPO" || { echo "FAIL: cannot cd into repo path '$REPO'"; exit 1; }

if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "FAIL: '$REPO' is not a git repository"
    exit 1
fi

DIFF=$(git diff "$BASE" -- salt/minion.py 2>/dev/null)

if [ -z "$DIFF" ]; then
    echo "FAIL: no changes to salt/minion.py -- the minion-side dispatch table was never extended"
    exit 1
fi

RESULT=$(python3 - "$REPO" "$BASE" <<'PYEOF'
import re
import subprocess
import sys

repo, base = sys.argv[1], sys.argv[2]
diff = subprocess.run(
    ["git", "diff", base, "--", "salt/minion.py"],
    cwd=repo,
    capture_output=True,
    text=True,
).stdout

try:
    with open(f"{repo}/salt/minion.py", encoding="utf-8") as fh:
        new_lines = fh.readlines()
except OSError:
    new_lines = []

# Locate Minion.manage_beacons()'s body range in the post-patch file, by
# indentation, so we don't depend on the (small, default 3-line) diff
# context window containing the "funcs = {" line too.
func_start = None
func_indent = None
def_re = re.compile(r"^(\s*)def manage_beacons\(self, tag, data\):")
for i, line in enumerate(new_lines):
    m = def_re.match(line)
    if m:
        func_start = i
        func_indent = len(m.group(1))
        break

func_end = len(new_lines)
if func_start is not None:
    for j in range(func_start + 1, len(new_lines)):
        line = new_lines[j]
        if not line.strip():
            continue
        cur_indent = len(line) - len(line.lstrip())
        if cur_indent <= func_indent and line.lstrip().startswith("def "):
            func_end = j
            break

# hunk header line numbers are 1-indexed; func_start/func_end are 0-indexed
func_range = (func_start + 1, func_end) if func_start is not None else (None, None)

new_key_re = re.compile(r'^\+\s*"[a-zA-Z_]+":\s*\(')
hunk_header_re = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@")

hunks = re.split(r"(?m)^(?=@@ )", diff)

added_in_funcs_dict = False
new_parallel_handler = False

for hunk in hunks:
    if not hunk.startswith("@@"):
        continue
    lines = hunk.splitlines()
    header_match = hunk_header_re.match(lines[0])
    added_lines = [
        l for l in lines if l.startswith("+") and not l.startswith("+++")
    ]

    if header_match and func_range[0] is not None:
        new_start = int(header_match.group(1))
        new_count = int(header_match.group(2) or 1)
        hunk_range = (new_start, new_start + new_count)
        overlaps_func = not (
            hunk_range[1] <= func_range[0] or hunk_range[0] >= func_range[1]
        )
        if overlaps_func:
            for l in added_lines:
                if new_key_re.match(l):
                    added_in_funcs_dict = True

    for l in added_lines:
        # a brand new def manage_beacons-like function (not the pre-existing one)
        if re.match(r"^\+\s*def manage_beacons\w+\(", l):
            new_parallel_handler = True
        # a brand new elif branch dispatching on the beacons tag elsewhere
        if re.search(r"^\+\s*elif tag\.startswith\(.manage_beacons", l):
            new_parallel_handler = True

if new_parallel_handler:
    print("PARALLEL")
elif added_in_funcs_dict:
    print("OK")
else:
    print("NOK")
PYEOF
)

case "$RESULT" in
    OK)
        echo "PASS: AC3 - one new entry added to the existing funcs dict inside Minion.manage_beacons(); no new elif/tag.startswith handler block or parallel manage_beacons-like function detected"
        exit 0
        ;;
    PARALLEL)
        echo "FAIL: AC3 - diff adds a new elif/tag.startswith block or a parallel manage_beacons-like function instead of extending the existing funcs dispatch dict"
        exit 1
        ;;
    *)
        echo "FAIL: AC3 - MANUAL REVIEW SUGGESTED - could not confirm a new entry was added to the existing 'funcs = {' dispatch dict inside Minion.manage_beacons(); verify manually that dispatch was wired through the existing table"
        exit 1
        ;;
esac
