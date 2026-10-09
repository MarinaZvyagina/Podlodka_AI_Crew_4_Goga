#!/usr/bin/env bash
# AC2: Function contract matches existing backends exactly (structural
#   conformance).
# method: grep 'def store|def fetch|def updated|def flush|def list_|def
#   contains' on the new salt/cache/<name>.py file; confirm __func_alias__
#   aliases list_ -> list (same convention as localfs.py), and compare the
#   positional-parameter shapes of each function against
#   salt/cache/localfs.py's store/fetch/updated/flush/list_/contains.
# expected_if_correct: all six functions are defined, with the same leading
#   positional parameters as localfs.py (bank[, key], ... cachedir), and
#   __func_alias__ = {"list_": "list"} (or equivalent) is present.
# expected_if_trap: one or more of the six functions is missing, or the new
#   module exposes a differently-shaped API (e.g. get/set/delete instead of
#   fetch/store, or no list_ -> list alias), meaning it cannot be dispatched
#   generically by salt.cache.Cache like every other backend.
set -u

REPO="${1:-.}"
BASE="bdb21a0937cfb8556a92fc6257f8f3c08bc4c32d"

cd "$REPO" || { echo "FAIL: cannot cd into repo path '$REPO'"; exit 1; }

if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "FAIL: '$REPO' is not a git repository"
    exit 1
fi

changed_files() {
    { git diff "$BASE" --name-only 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null; } | sort -u
}

BASELINE_CACHE_FILES=$(git ls-tree -r --name-only "$BASE" -- salt/cache/ 2>/dev/null)

NEW_CACHE_FILES=$(changed_files | grep -E '^salt/cache/[^/]+\.py$' | while read -r f; do
    if ! printf '%s\n' "$BASELINE_CACHE_FILES" | grep -qx "$f"; then
        echo "$f"
    fi
done)

if [ -z "$NEW_CACHE_FILES" ]; then
    echo "FAIL: AC2 - no new file found under salt/cache/ to check for structural conformance (see AC1)"
    exit 1
fi

if [ ! -f "salt/cache/localfs.py" ]; then
    echo "FAIL: AC2 - reference file salt/cache/localfs.py is missing, cannot compare shapes"
    exit 1
fi

OVERALL_OK=1
for NEW_FILE in $NEW_CACHE_FILES; do
    if [ ! -f "$NEW_FILE" ]; then
        echo "FAIL: AC2 - $NEW_FILE was reported as new but does not exist on disk"
        OVERALL_OK=0
        continue
    fi

    RESULT=$(python3 - "$NEW_FILE" "salt/cache/localfs.py" <<'PYEOF'
import ast
import sys

new_file, ref_file = sys.argv[1], sys.argv[2]

REQUIRED = ["store", "fetch", "updated", "flush", "list_", "contains"]

def load(path):
    with open(path, encoding="utf-8") as fh:
        return ast.parse(fh.read(), filename=path)

def func_defs(tree):
    return {
        node.name: node
        for node in ast.walk(tree)
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
    }

def posonly_and_args(node):
    args = node.args
    names = [a.arg for a in getattr(args, "posonlyargs", [])] + [a.arg for a in args.args]
    return names

def has_func_alias_list(tree):
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name) and target.id == "__func_alias__":
                    if isinstance(node.value, ast.Dict):
                        for k, v in zip(node.value.keys, node.value.values):
                            if (
                                isinstance(k, ast.Constant)
                                and k.value == "list_"
                                and isinstance(v, ast.Constant)
                                and v.value == "list"
                            ):
                                return True
    return False

try:
    new_tree = load(new_file)
    ref_tree = load(ref_file)
except SyntaxError as exc:
    print(f"NOK: could not parse: {exc}")
    sys.exit(0)

new_funcs = func_defs(new_tree)
ref_funcs = func_defs(ref_tree)

missing = [name for name in REQUIRED if name not in new_funcs]
if missing:
    print(f"NOK: missing required function(s): {', '.join(missing)}")
    sys.exit(0)

if not has_func_alias_list(new_tree):
    print("NOK: __func_alias__ = {'list_': 'list'} (or equivalent) not found")
    sys.exit(0)

shape_problems = []
for name in REQUIRED:
    new_params = posonly_and_args(new_funcs[name])
    ref_params = posonly_and_args(ref_funcs[name])
    # Compare the leading required params (bank[, key]) which every backend
    # must accept identically; trailing params (cachedir/etc) may vary in
    # name but must exist in similar count.
    if not new_params or new_params[0] != "bank":
        shape_problems.append(f"{name}: first param must be 'bank', got {new_params[:1]}")
        continue
    if name in ("fetch", "updated", "contains"):
        if len(new_params) < 2 or new_params[1] != "key":
            shape_problems.append(f"{name}: second param must be 'key', got {new_params[1:2]}")
    if name == "flush":
        if "key" not in new_params:
            shape_problems.append(f"{name}: must accept a 'key' parameter")

if shape_problems:
    print("NOK: " + "; ".join(shape_problems))
    sys.exit(0)

print("OK")
PYEOF
)
    if [ "$RESULT" != "OK" ]; then
        echo "FAIL: AC2 - $NEW_FILE - $RESULT"
        OVERALL_OK=0
    fi
done

if [ "$OVERALL_OK" -eq 1 ]; then
    echo "PASS: AC2 - new backend file(s) ($(printf '%s' "$NEW_CACHE_FILES" | tr '\n' ' ')) define store/fetch/updated/flush/list_/contains with the same (bank[, key], ...) shape as salt/cache/localfs.py, and alias list_ -> list"
    exit 0
else
    echo "FAIL: AC2 - structural conformance check failed for at least one new cache backend file"
    exit 1
fi
