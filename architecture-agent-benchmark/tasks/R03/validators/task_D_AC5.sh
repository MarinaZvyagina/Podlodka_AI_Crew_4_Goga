#!/usr/bin/env bash
# Task D / AC5: Manual verification under Fastify -- a REAL runnable check,
# not just a grep-based review.
#
# Strategy:
#   1. If the diff already contains a test file that (a) looks like a Fastify
#      bootstrap (references FastifyAdapter / @nestjs/platform-fastify) and
#      (b) actually asserts something about a request/correlation-id header,
#      run that spec for real via vitest against the integration config and
#      treat its pass/fail as the verdict. This is a genuine automated run
#      under Fastify.
#   2. Otherwise (this is exactly the trap scenario: a test-writer who only
#      exercised the default/Express adapter), synthesize a small, throwaway
#      Fastify-only spec that boots the diff's own application module under
#      `new FastifyAdapter()`, injects a request, and inspects the response
#      headers directly for a well-formed request/correlation id. Run it via
#      vitest and treat pass/fail as the verdict. The synthesized spec is
#      deleted afterwards regardless of outcome.
#   3. If no bootable module/controller can be located at all, this AC is
#      reported as MANUAL REVIEW REQUIRED (truly unscriptable case).
#
# Usage: task_D_AC5.sh [repo_dir]   (default: .)
set -u
REPO="${1:-.}"

if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "FAIL: '$REPO' is not a git repository"
  exit 1
fi

cd "$REPO" || { echo "FAIL: cannot cd into $REPO"; exit 1; }
REPO_ABS="$(pwd)"

if [ ! -f "vitest.config.integration.mts" ]; then
  echo "FAIL: vitest.config.integration.mts not found at repo root -- cannot run a real Fastify boot"
  exit 1
fi

CHANGED=$( { git diff --name-only HEAD; git ls-files --others --exclude-standard; } | sort -u | grep -v '^$')

if [ -z "$CHANGED" ]; then
  echo "FAIL: no changes detected against HEAD (nothing to validate)"
  exit 1
fi

GENERATED_SPEC=""
cleanup() {
  if [ -n "$GENERATED_SPEC" ] && [ -f "$GENERATED_SPEC" ]; then
    rm -f "$GENERATED_SPEC"
  fi
}
trap cleanup EXIT

# --- Step 1: is there already a relevant fastify spec in the diff? ---------
CANDIDATE_FASTIFY_SPECS=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -f "$f" ] || continue
  case "$f" in
    *.spec.ts) ;;
    *) continue ;;
  esac
  if grep -qE "FastifyAdapter|@nestjs/platform-fastify" "$f" 2>/dev/null \
     && grep -qiE "request-id|correlation-id|requestid|correlationid" "$f" 2>/dev/null; then
    CANDIDATE_FASTIFY_SPECS="${CANDIDATE_FASTIFY_SPECS}${f}"$'\n'
  fi
done <<< "$CHANGED"
CANDIDATE_FASTIFY_SPECS=$(echo "$CANDIDATE_FASTIFY_SPECS" | grep -v '^$' || true)

if [ -n "$CANDIDATE_FASTIFY_SPECS" ]; then
  echo "Found Fastify-bootstrapping test file(s) in the diff that assert on a request/correlation id header:"
  echo "$CANDIDATE_FASTIFY_SPECS" | sed 's/^/  /'
  echo
  echo "Running them for real via vitest (integration config)..."
  # shellcheck disable=SC2086
  if npx vitest run --config vitest.config.integration.mts $CANDIDATE_FASTIFY_SPECS > /tmp/task_D_AC5_out.$$ 2>&1; then
    cat /tmp/task_D_AC5_out.$$ | tail -40
    rm -f /tmp/task_D_AC5_out.$$
    echo
    echo "PASS: real automated Fastify boot (via diff's own e2e spec) confirms the request-id header behavior"
    exit 0
  else
    cat /tmp/task_D_AC5_out.$$ | tail -60
    rm -f /tmp/task_D_AC5_out.$$
    echo
    echo "FAIL: the diff's own Fastify e2e spec(s) did not pass"
    exit 1
  fi
fi

echo "No existing Fastify-bootstrapping test file with request-id assertions found in the diff."
echo "(This is exactly the situation the trap variant of this task produces: an Express-only"
echo " test suite. Synthesizing an independent Fastify-only probe against the diff's own"
echo " application code.)"
echo

# --- Step 2: synthesize a minimal Fastify probe against the diff's module --
MODULE_FILE=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -f "$f" ] || continue
  case "$f" in
    *.module.ts)
      case "$f" in
        integration/*/src/*) MODULE_FILE="$f"; break ;;
      esac
      ;;
  esac
done <<< "$CHANGED"

if [ -z "$MODULE_FILE" ]; then
  echo "MANUAL REVIEW REQUIRED: could not auto-locate a bootable NestJS *.module.ts under an integration/**/src directory in the diff. Please manually bootstrap the changed application with FastifyAdapter, issue a request, and inspect response headers directly."
  exit 1
fi

SRC_DIR="$(dirname "$MODULE_FILE")"
INTEGRATION_DIR="$(dirname "$SRC_DIR")"
MODULE_BASENAME="$(basename "$MODULE_FILE" .ts)"
MODULE_CLASS="$(grep -oE 'export class [A-Za-z0-9_]+' "$MODULE_FILE" | head -1 | awk '{print $3}')"

if [ -z "$MODULE_CLASS" ]; then
  echo "MANUAL REVIEW REQUIRED: found module file $MODULE_FILE but could not determine its exported class name."
  exit 1
fi

# Try to find a GET route path declared in any controller alongside the module.
ROUTE_PATH=""
for cf in "$SRC_DIR"/*.controller.ts; do
  [ -f "$cf" ] || continue
  MATCH=$(grep -oE "@Get\('[^']*'\)|@Get\(\"[^\"]*\"\)" "$cf" | head -1)
  if [ -n "$MATCH" ]; then
    ROUTE_PATH=$(echo "$MATCH" | sed -E "s/@Get\(['\"]([^'\"]*)['\"]\)/\1/")
    break
  fi
done
ROUTE_PATH="${ROUTE_PATH:-hello}"
case "$ROUTE_PATH" in
  /*) ;;
  *) ROUTE_PATH="/$ROUTE_PATH" ;;
esac

GENERATED_SPEC="$INTEGRATION_DIR/e2e/_ac5_fastify_probe.spec.ts"
mkdir -p "$INTEGRATION_DIR/e2e"

cat > "$GENERATED_SPEC" <<EOF
// AUTO-GENERATED by task_D_AC5.sh -- deleted automatically after the run.
import {
  FastifyAdapter,
  NestFastifyApplication,
} from '@nestjs/platform-fastify';
import { Test } from '@nestjs/testing';
import { ${MODULE_CLASS} } from '../src/${MODULE_BASENAME}.js';

const CANDIDATE_HEADERS = [
  'x-request-id',
  'x-correlation-id',
  'request-id',
  'correlation-id',
];

describe('AC5 synthetic Fastify probe', () => {
  let app: NestFastifyApplication;

  beforeAll(async () => {
    const module = await Test.createTestingModule({
      imports: [${MODULE_CLASS}],
    }).compile();

    app = module.createNestApplication<NestFastifyApplication>(
      new FastifyAdapter(),
    );
    await app.init();
  });

  it('returns a non-empty request/correlation id header under Fastify', async () => {
    const res = await app.inject({ method: 'GET', url: '${ROUTE_PATH}' });
    const found = CANDIDATE_HEADERS
      .map(h => [h, res.headers[h]])
      .find(([, v]) => typeof v === 'string' && v.length > 0);

    if (!found) {
      throw new Error(
        'No request/correlation id header found under Fastify. Headers seen: ' +
          JSON.stringify(res.headers),
      );
    }
    expect(found[1]).toBeTruthy();
  });

  it('echoes back an incoming request id unchanged under Fastify', async () => {
    const incomingId = 'ac5-fastify-probe-incoming-id';
    const res = await app.inject({
      method: 'GET',
      url: '${ROUTE_PATH}',
      headers: { 'x-request-id': incomingId },
    });
    const echoed = res.headers['x-request-id'];
    if (echoed !== incomingId) {
      throw new Error(
        \`Expected incoming x-request-id to be echoed back unchanged, got: \${JSON.stringify(echoed)}\`,
      );
    }
  });

  afterAll(async () => {
    await app.close();
  });
});
EOF

echo "Synthesized probe spec at: $GENERATED_SPEC"
echo "Module under test: $MODULE_CLASS (from $MODULE_FILE), route: $ROUTE_PATH"
echo
echo "Running it for real via vitest against a genuine Fastify boot..."

if npx vitest run --config vitest.config.integration.mts "$GENERATED_SPEC" > /tmp/task_D_AC5_out.$$ 2>&1; then
  cat /tmp/task_D_AC5_out.$$ | tail -60
  rm -f /tmp/task_D_AC5_out.$$
  echo
  echo "PASS: synthesized, genuinely-executed Fastify boot shows the request-id header present and correctly echoed"
  exit 0
else
  cat /tmp/task_D_AC5_out.$$ | tail -80
  rm -f /tmp/task_D_AC5_out.$$
  echo
  echo "FAIL: synthesized Fastify boot of the diff's own application module did NOT produce a valid request-id header (or the app failed to boot under Fastify at all) -- this is the classic 'works under Express only' trap"
  exit 1
fi
