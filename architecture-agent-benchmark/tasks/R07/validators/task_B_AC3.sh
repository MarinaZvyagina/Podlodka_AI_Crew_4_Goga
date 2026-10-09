#!/usr/bin/env bash
# AC3: Snooze read/write goes through MangaRepository's existing update mechanism via a
# dedicated interactor, not a new parallel repository.
#
# Checks:
#  1. No new file was added under domain/src/main/java/tachiyomi/domain/manga/repository/
#     (i.e. no brand new repository interface was introduced for this feature).
#  2. A new interactor file exists under domain/src/main/java/tachiyomi/domain/manga/interactor/
#     that references snoozing, constructs a tachiyomi.domain.manga.model.MangaUpdate(...), and
#     calls mangaRepository.update(...)/updateAll(...) — i.e. reuses the existing partial-update
#     pattern instead of talking to a raw database.
set -uo pipefail

REPO="${1:-.}"

MANGA_REPO_DIR="domain/src/main/java/tachiyomi/domain/manga/repository"
INTERACTOR_DIR="domain/src/main/java/tachiyomi/domain/manga/interactor"

if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "FAIL: '$REPO' is not a git working tree"
    exit 1
fi

# 1. No new repository interface file under the manga repository directory.
NEW_REPO_FILES="$(git -C "$REPO" status --porcelain -- "$MANGA_REPO_DIR" | awk '$1 == "??" {print $2}')"
if [ -n "$NEW_REPO_FILES" ]; then
    echo "FAIL: new file(s) added under $MANGA_REPO_DIR: $NEW_REPO_FILES — snoozing should reuse the existing MangaRepository, not introduce a new repository interface"
    exit 1
fi

# 2. A new interactor building MangaUpdate(...) with a snooze reference, calling
#    MangaRepository.update/updateAll.
NEW_INTERACTOR_FILES="$(git -C "$REPO" status --porcelain -- "$INTERACTOR_DIR" | awk '$1 == "??" {print $2}')"

HIT=""
for f in $NEW_INTERACTOR_FILES; do
    CONTENT="$(cat "$REPO/$f" 2>/dev/null)"
    if echo "$CONTENT" | grep -qi 'snooz' \
        && echo "$CONTENT" | grep -q 'MangaUpdate(' \
        && echo "$CONTENT" | grep -qE '\.(update|updateAll)\('; then
        HIT="$f"
        break
    fi
done

if [ -z "$HIT" ]; then
    echo "FAIL: no new domain interactor under $INTERACTOR_DIR builds a MangaUpdate(...) referencing a snooze field and calls MangaRepository.update/updateAll"
    exit 1
fi

echo "PASS: new interactor $HIT builds MangaUpdate(...) referencing snoozing and calls MangaRepository.update/updateAll; no new repository interface added under $MANGA_REPO_DIR"
exit 0
