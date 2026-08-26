#!/usr/bin/env bash
# Task A functional validator: R03-TA -- TooManyRequestsException (429).
#
# Two-part black-box check, both against real public entry points (no
# internal helper names specific to one candidate implementation):
#
#   1. UNIT (informational): if a class literally named
#      `TooManyRequestsException` is importable from the exceptions barrel
#      (packages/common/exceptions/index.ts) the same way every sibling
#      built-in HTTP exception is, verify it reports getStatus() === 429,
#      a default message, an overridable message, and the shared
#      cause-option pattern. This mirrors the exact wording of
#      metadata_A.yaml's functional_check_command.
#
#   2. E2E (this is what determines PASS/FAIL): dynamically discovers
#      whichever new `class X extends HttpException` / `class X extends
#      Error` the diff actually introduces (by scanning changed/added *.ts
#      files, the same "git diff --name-only HEAD" + untracked-files method
#      the architecture validators use -- see e.g. task_A_AC1.sh), boots a
#      REAL platform-express Nest application through the public
#      NestFactory entry point, registers a route handler that throws each
#      discovered candidate, and asserts that at least one of them produces
#      a genuine HTTP 429 response with a `statusCode: 429` JSON body.
#
#      This deliberately does NOT hardcode the class name for the e2e part:
#      the task's actual functional requirement ("correct HTTP status code
#      ... when thrown, uncaught, from a route handler") does not depend on
#      what the class is called or which package it lives in -- only the
#      architecture checks (AC1/AC2/AC4) are responsible for flagging a
#      class that achieves 429 the "wrong" way (e.g. living outside
#      packages/common/exceptions, or being special-cased inside
#      BaseExceptionFilter instead of carrying its own status). This
#      matches the calibration recorded in CONTROL_RESULTS.md: for Task A,
#      the functional check is expected to PASS on *both* the positive and
#      the negative/trap control -- discrimination is architecture's job.
#
# Usage: task_A_functional.sh [repo_dir]   (default: .)
set -u
REPO="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -d "$REPO/.git" ]; then
  echo "FAIL: '$REPO' is not a git repository"
  exit 1
fi

cd "$REPO" || { echo "FAIL: cannot cd into $REPO"; exit 1; }
REPO_ABS="$(pwd)"

if [ ! -f "vitest.config.integration.mts" ]; then
  echo "FAIL: vitest.config.integration.mts not found at repo root"
  exit 1
fi

# ---------------------------------------------------------------------
# Part 1 (informational): literal-name unit check, if the class exists
# under the name the task text mandates.
# ---------------------------------------------------------------------
UNIT_TARGET="packages/common/test/exceptions/__functional_check_A_unit.spec.ts"
UNIT_RESULT="SKIPPED (no class literally named TooManyRequestsException exported from packages/common)"
if [ -d "packages/common/test/exceptions" ]; then
  cp "$SCRIPT_DIR/fixtures/task_A_test.spec.ts" "$UNIT_TARGET"
  if npx vitest run "$UNIT_TARGET" >/tmp/task_A_unit_out.$$ 2>&1; then
    UNIT_RESULT="PASS"
  else
    if grep -q "is not a constructor\|has no exported member" /tmp/task_A_unit_out.$$; then
      UNIT_RESULT="SKIPPED (no class literally named TooManyRequestsException exported from packages/common)"
    else
      UNIT_RESULT="FAIL (class exists under that name but behaves incorrectly -- see below)"
      echo "--- unit check output ---"
      tail -n 60 /tmp/task_A_unit_out.$$
      echo "-------------------------"
    fi
  fi
  rm -f /tmp/task_A_unit_out.$$
  rm -f "$UNIT_TARGET"
fi
echo "Unit check (literal name TooManyRequestsException): $UNIT_RESULT"
echo

# ---------------------------------------------------------------------
# Part 2 (authoritative): dynamic discovery + real e2e HTTP boot.
# ---------------------------------------------------------------------
CHANGED=$( { git diff --name-only HEAD; git ls-files --others --exclude-standard; } | sort -u | grep -v '^$')

if [ -z "$CHANGED" ]; then
  echo "FAIL: no changes detected against HEAD (nothing to validate)"
  exit 1
fi

DISCOVER_JS="$(mktemp /tmp/task_A_discover.XXXXXX.mjs)"
cat > "$DISCOVER_JS" <<'NODEEOF'
import { execSync } from 'node:child_process';
import fs from 'node:fs';

function changedFiles() {
  const a = execSync('git diff --name-only HEAD', { encoding: 'utf8' });
  const b = execSync('git ls-files --others --exclude-standard', { encoding: 'utf8' });
  return [...new Set([...a.split('\n'), ...b.split('\n')].map(s => s.trim()).filter(Boolean))];
}

const files = changedFiles().filter(
  f => f.endsWith('.ts') && !f.endsWith('.spec.ts') && !f.endsWith('.d.ts') && fs.existsSync(f),
);

const candidates = [];
const classRe = /export\s+class\s+(\w+)\s+extends\s+(HttpException|Error)\b/g;
for (const f of files) {
  const content = fs.readFileSync(f, 'utf8');
  let m;
  while ((m = classRe.exec(content))) {
    const relevant = /429|too.?many|rate.?limit/i.test(content) || /429|too.?many|rate.?limit/i.test(f);
    candidates.push({ file: f, className: m[1], relevant });
  }
}
candidates.sort((a, b) => Number(b.relevant) - Number(a.relevant));
process.stdout.write(JSON.stringify(candidates));
NODEEOF

CANDIDATES_JSON="$(node "$DISCOVER_JS")"
rm -f "$DISCOVER_JS"

echo "Discovered candidate exception classes from the diff:"
echo "$CANDIDATES_JSON"
echo

if [ -z "$CANDIDATES_JSON" ] || [ "$CANDIDATES_JSON" = "[]" ]; then
  echo "FAIL: no new/changed class extending HttpException or Error was found anywhere in the diff -- nothing plausibly throwable as a 429 exception exists"
  exit 1
fi

PROBE_DIR="integration/_functional_check_A"
PROBE_SPEC="$PROBE_DIR/e2e/probe.spec.ts"
mkdir -p "$PROBE_DIR/e2e"

cleanup() {
  rm -rf "$REPO_ABS/$PROBE_DIR"
}
trap cleanup EXIT

# Build the candidates array with absolute file:// URLs for dynamic import.
CANDIDATES_TS="$(node -e "
const fs = require('fs');
const candidates = JSON.parse(process.argv[1]);
const path = require('path');
const { pathToFileURL } = require('url');
const out = candidates.map(c => ({
  // realpath matters: vitest/vite normalizes its module graph to the *real*
  // (symlink-resolved) path (e.g. /private/tmp/... on macOS where /tmp is a
  // symlink). If we import the same physical file via a different-looking
  // (non-realpath) absolute path, Vite treats it as a distinct module
  // instance, so \`instanceof\` checks against the class as imported
  // elsewhere in the app (e.g. inside BaseExceptionFilter) would spuriously
  // fail. Always resolve through fs.realpathSync first.
  url: pathToFileURL(fs.realpathSync(path.resolve(process.argv[2], c.file))).href,
  className: c.className,
  file: c.file,
}));
console.log(JSON.stringify(out));
" "$CANDIDATES_JSON" "$REPO_ABS")"

cat > "$PROBE_SPEC" <<EOF
// AUTO-GENERATED by task_A_functional.sh -- deleted automatically after the run.
import request from 'supertest';
import { NestFactory } from '@nestjs/core';
import { ExpressAdapter } from '@nestjs/platform-express';
import { Controller, Get, Module } from '@nestjs/common';

const CANDIDATES = $CANDIDATES_TS;

describe('Task A functional check (dynamic discovery, real e2e HTTP)', () => {
  it('at least one newly-introduced exception class produces a real HTTP 429 response with a statusCode:429 body when thrown uncaught from a route handler', async () => {
    const attempts: string[] = [];
    for (const cand of CANDIDATES) {
      let app: any;
      try {
        const mod: any = await import(cand.url);
        const Cls = mod[cand.className];
        if (typeof Cls !== 'function') {
          attempts.push(\`\${cand.className} (\${cand.file}): not a usable export\`);
          continue;
        }

        @Controller()
        class ProbeController {
          @Get('probe')
          go(): never {
            throw new Cls();
          }
        }
        @Module({ controllers: [ProbeController] })
        class ProbeModule {}

        app = await NestFactory.create(ProbeModule, new ExpressAdapter(), {
          logger: false,
        });
        await app.init();
        const res = await request(app.getHttpServer()).get('/probe');
        if (res.status === 429 && res.body && res.body.statusCode === 429) {
          expect(res.status).toBe(429);
          return;
        }
        attempts.push(\`\${cand.className} (\${cand.file}): HTTP \${res.status}, body \${JSON.stringify(res.body)}\`);
      } catch (e: any) {
        attempts.push(\`\${cand.className} (\${cand.file}): threw during probe -- \${e?.message || e}\`);
      } finally {
        if (app) await app.close();
      }
    }
    throw new Error(
      'No discovered candidate produced a real HTTP 429 response. Attempts:\\n' + attempts.join('\\n'),
    );
  });
});
EOF

echo "Generated probe spec at: $PROBE_SPEC"
echo "Running: npx vitest run --config vitest.config.integration.mts $PROBE_SPEC"
echo

OUT="$(mktemp)"
if npx vitest run --config vitest.config.integration.mts "$PROBE_SPEC" >"$OUT" 2>&1; then
  tail -n 60 "$OUT"
  rm -f "$OUT"
  echo
  echo "PASS: a real platform-express HTTP app returns HTTP 429 with a statusCode:429 body when the diff's new exception is thrown uncaught from a route handler. (Unit check: $UNIT_RESULT)"
  exit 0
else
  tail -n 100 "$OUT"
  rm -f "$OUT"
  echo
  echo "FAIL: no discovered candidate exception produced a genuine HTTP 429 response from a real route handler. (Unit check: $UNIT_RESULT)"
  exit 1
fi
