#!/usr/bin/env bash
# Task C / AC1: Rejection is implemented via a class shaped like the
# framework's existing "allowed to proceed" contract (CanActivate), not a
# manual guard-clause pasted into handler bodies or an interceptor-shaped
# class.
#
# Method: grep -n 'implements CanActivate' across the diff. Correct: present,
# and the class is registered via @UseGuards(...) or provide: APP_GUARD.
# Trap: no CanActivate impl; instead an interceptor-shaped class
# (implements NestInterceptor), or `if (maintenanceService.isOn()) { throw
# ... }` guard-clauses pasted directly into handler bodies.
#
# Usage: task_C_AC1.sh [repo_dir]   (default: .)
set -u
REPO="${1:-.}"

if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "FAIL: '$REPO' is not a git repository"
  exit 1
fi

cd "$REPO" || { echo "FAIL: cannot cd into $REPO"; exit 1; }

CHANGED=$(git diff --name-only HEAD; git status --porcelain -uall | awk '{print $2}')
CHANGED=$(echo "$CHANGED" | sort -u | grep -v '^$' | grep -E '\.(ts|js)$')

if [ -z "$CHANGED" ]; then
  echo "FAIL: no changed .ts/.js files detected against HEAD (nothing to validate)"
  exit 1
fi

echo "Changed source files:"
echo "$CHANGED" | sed 's/^/  /'
echo

CANACTIVATE_MATCHES=""
for f in $CHANGED; do
  [ -f "$f" ] || continue
  M=$(grep -n 'implements CanActivate' "$f" 2>/dev/null)
  if [ -n "$M" ]; then
    CANACTIVATE_MATCHES="${CANACTIVATE_MATCHES}${f}:
${M}
"
  fi
done

if [ -z "$CANACTIVATE_MATCHES" ]; then
  echo "FAIL: no 'implements CanActivate' found in any changed file."
  echo "This suggests the rejection was implemented some other way (e.g. an"
  echo "interceptor-shaped class, or a manual 'if (maintenanceService.isOn())"
  echo "{ throw ... }' guard-clause pasted into handler bodies) instead of"
  echo "reusing the framework's existing CanActivate guard contract."
  exit 1
fi

echo "Found CanActivate implementation(s):"
echo "$CANACTIVATE_MATCHES"

GUARD_CLASSES=$(echo "$CANACTIVATE_MATCHES" | grep -oE 'class [A-Za-z0-9_]+' | awk '{print $2}' | sort -u)

REG_MATCHES=""
for f in $CHANGED; do
  [ -f "$f" ] || continue
  M=$(grep -nE '@UseGuards\(|APP_GUARD' "$f" 2>/dev/null)
  if [ -n "$M" ]; then
    REG_MATCHES="${REG_MATCHES}${f}:
${M}
"
  fi
done

if [ -z "$REG_MATCHES" ]; then
  echo
  echo "FAIL: a CanActivate class was found (${GUARD_CLASSES}) but no"
  echo "@UseGuards(...) or APP_GUARD registration was found anywhere in the"
  echo "diff -- the guard does not appear to actually be wired into the"
  echo "request/message pipeline."
  exit 1
fi

echo
echo "Found guard registration (@UseGuards / APP_GUARD):"
echo "$REG_MATCHES"

echo "PASS: a CanActivate-implementing class was found (${GUARD_CLASSES}) and is registered via @UseGuards/APP_GUARD."
exit 0
