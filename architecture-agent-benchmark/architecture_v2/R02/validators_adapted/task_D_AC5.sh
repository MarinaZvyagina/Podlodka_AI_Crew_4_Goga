#!/usr/bin/env bash
# AC5: Public signature/return format unchanged.
#
# Method (per metadata_D.yaml): diff the function signature line and a
# sampled return value against the pre-change version and existing tests.
#
# expected_if_correct: "def usage(args=None):" is unchanged, and a sample
#   call to usage() (with mocked cmd.run/__grains__) still returns a dict
#   keyed by mount point with the same per-mount keys as before
#   (filesystem/1K-blocks/used/available/capacity).
# expected_if_trap: N/A for the module-level-global trap (it preserves the
#   signature/shape too) -- this AC guards against a *different* failure
#   mode (an implementation that changes the call signature or return
#   shape while adding caching).
set -u

REPO="${1:-.}"
BASE="bdb21a0937cfb8556a92fc6257f8f3c08bc4c32d"
FILE="salt/modules/disk.py"

cd "$REPO" || { echo "FAIL: cannot cd into repo path '$REPO'"; exit 1; }

if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "FAIL: '$REPO' is not a git repository"
    exit 1
fi

if [ ! -f "$FILE" ]; then
    echo "FAIL: $FILE not found"
    exit 1
fi

before_sig=$(git show "$BASE:$FILE" 2>/dev/null | grep -E '^def usage\(')
after_sig=$(grep -E '^def usage\(' "$FILE")

if [ -z "$before_sig" ] || [ -z "$after_sig" ]; then
    echo "FAIL: could not locate 'def usage(' signature line in base and/or current $FILE"
    exit 1
fi

if [ "$before_sig" != "$after_sig" ]; then
    echo "FAIL: usage() signature changed: before='$before_sig' after='$after_sig'"
    exit 1
fi

# Activate the repo's venv if present, without requiring it.
if [ -f "$REPO/.venv/bin/activate" ]; then
    # shellcheck disable=SC1091
    source "$REPO/.venv/bin/activate"
fi

if command -v python >/dev/null 2>&1; then
    PY=python
elif command -v python3 >/dev/null 2>&1; then
    PY=python3
else
    echo "FAIL: no python interpreter found on PATH"
    exit 1
fi

sample_out=$("$PY" - <<'PYEOF' 2>&1
import sys
import salt.modules.disk as disk

df_output = (
    "Filesystem     1K-blocks     Used Available Use% Mounted on\n"
    "/dev/sda1        1000000   500000    500000  50% /\n"
)

# Use a kernel other than "Linux" so the /etc/mtab existence check
# (irrelevant to the return-shape being sampled here) doesn't
# short-circuit depending on whether /etc/mtab happens to exist on
# the machine running this validator.
disk.__grains__ = {"kernel": "SunOS"}
disk.__salt__ = {"cmd.run": lambda *a, **k: df_output}
disk.__context__ = {}

ret = disk.usage()

assert isinstance(ret, dict), f"expected dict, got {type(ret)}"
assert "/" in ret, f"expected '/' mount key in return, got {list(ret.keys())}"
entry = ret["/"]
expected_keys = {"filesystem", "1K-blocks", "used", "available", "capacity"}
assert set(entry.keys()) == expected_keys, (
    f"unexpected per-mount keys: {sorted(entry.keys())} != {sorted(expected_keys)}"
)
print("SAMPLE_OK")
PYEOF
)
py_rc=$?

if [ $py_rc -ne 0 ] || ! printf '%s' "$sample_out" | grep -q 'SAMPLE_OK'; then
    echo "FAIL: sampled usage() return value does not match expected shape -- $(printf '%s' "$sample_out" | tr '\n' ' | ')"
    exit 1
fi

echo "PASS: usage() signature and sampled return shape unchanged"
exit 0
