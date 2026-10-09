#!/usr/bin/env bash
# AC4: No new dependency edge from domain to data, and no new dependency from presentation-core.
#
# Checks that domain/build.gradle.kts has no diff at all, and that presentation-core/build.gradle.kts
# has no diff at all. (data/build.gradle.kts MAY change — adding test-scope dependencies such as
# JUnit/MockK for a new data/src/test directory is explicitly allowed and not an architecture
# violation.)
set -uo pipefail

REPO="${1:-.}"

DOMAIN_GRADLE="domain/build.gradle.kts"
PRESENTATION_CORE_GRADLE="presentation-core/build.gradle.kts"

if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "FAIL: '$REPO' is not a git working tree"
    exit 1
fi

FAIL_REASON=""

DOMAIN_DIFF="$(git -C "$REPO" diff -- "$DOMAIN_GRADLE")"
if [ -n "$DOMAIN_DIFF" ]; then
    FAIL_REASON="$FAIL_REASON\n  - $DOMAIN_GRADLE changed:\n$DOMAIN_DIFF"
fi

PRES_CORE_DIFF="$(git -C "$REPO" diff -- "$PRESENTATION_CORE_GRADLE")"
if [ -n "$PRES_CORE_DIFF" ]; then
    FAIL_REASON="$FAIL_REASON\n  - $PRESENTATION_CORE_GRADLE changed:\n$PRES_CORE_DIFF"
fi

# Extra safety net: explicitly flag the trap of `projects.data` appearing anywhere new in
# domain/build.gradle.kts (would also be caught above, but called out for a clearer message).
if git -C "$REPO" diff -- "$DOMAIN_GRADLE" | grep -E '^\+' | grep -q 'projects\.data'; then
    FAIL_REASON="$FAIL_REASON\n  - $DOMAIN_GRADLE gained a new dependency on projects.data"
fi

if [ -n "$FAIL_REASON" ]; then
    echo -e "FAIL: unexpected build.gradle.kts dependency change(s):$FAIL_REASON"
    exit 1
fi

echo "PASS: no diff in $DOMAIN_GRADLE or $PRESENTATION_CORE_GRADLE"
exit 0
