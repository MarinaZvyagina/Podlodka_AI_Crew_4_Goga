// Task D functional validator -- discovery + spec-generation script.
//
// Task D's whole point is the Express-vs-Fastify "Dangerous Success" gap
// (see CONTROL_RESULTS.md), so the functional check MUST independently and
// genuinely run under both adapters -- not just review the diff. For each
// platform (express, fastify) independently:
//
//   1. If the diff itself already contains a *.spec.ts that both (a)
//      bootstraps that specific platform (references FastifyAdapter/
//      platform-fastify, or ExpressAdapter/platform-express/the
//      no-adapter-arg default) and (b) asserts something about a
//      request/correlation-id header, that file is executed for real via
//      vitest and its pass/fail is used as-is for that platform. This
//      mirrors task_D_AC4/AC5's own detection method exactly.
//   2. Otherwise (the actual trap scenario: a test suite that only ever
//      exercises one platform), a throwaway probe is synthesized that
//      boots the diff's own discovered *.module.ts under that platform,
//      issues two real requests -- one with no incoming id header, one
//      with an incoming id header set to a known value -- and inspects
//      the raw HTTP response headers directly (never the response body,
//      since the body shape is candidate-specific) for a well-formed,
//      correctly-echoed id header. This is the same synthesis strategy as
//      task_D_AC5.sh, generalized to run for BOTH platforms independently
//      rather than only Fastify.
//
// Usage: node task_D_discover.mjs <repoAbsPath> <outDir>
// Writes <outDir>/express.spec.ts and/or <outDir>/fastify.spec.ts (only
// the ones that needed synthesizing -- pre-existing diff specs are run
// in place, not copied) and prints, to stdout, a JSON plan describing
// which spec file to run for each platform. Exits 1 with a diagnostic on
// stderr if neither platform can be verified at all (e.g. no bootable
// module found anywhere in the diff).
import { execSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const REPO = process.argv[2];
const OUT_DIR = process.argv[3];

function die(msg) {
  console.error('FAIL: ' + msg);
  process.exit(1);
}

function changedFiles() {
  const a = execSync('git diff --name-only HEAD', { cwd: REPO, encoding: 'utf8' });
  const b = execSync('git ls-files --others --exclude-standard', { cwd: REPO, encoding: 'utf8' });
  return [...new Set([...a.split('\n'), ...b.split('\n')].map(s => s.trim()).filter(Boolean))]
    .filter(f => fs.existsSync(path.join(REPO, f)));
}

const changed = changedFiles();
if (changed.length === 0) die('no changes detected against HEAD (nothing to validate)');

const KEYWORDS = /request-?id|correlation-?id|x-request-id|x-correlation-id/i;

const specFiles = changed.filter(f => f.endsWith('.spec.ts'));

function readSafe(f) {
  try {
    return fs.readFileSync(path.join(REPO, f), 'utf8');
  } catch {
    return '';
  }
}

const fastifySpec = specFiles.find(f => {
  const c = readSafe(f);
  return /FastifyAdapter|platform-fastify/.test(c) && KEYWORDS.test(c);
});
const expressSpec = specFiles.find(f => {
  const c = readSafe(f);
  if (!KEYWORDS.test(c)) return false;
  return /ExpressAdapter|platform-express/.test(c) || /createNestApplication\(\)/.test(c);
});

const plan = { express: null, fastify: null };

if (expressSpec) {
  plan.express = { mode: 'diff-own', spec: expressSpec };
}
if (fastifySpec) {
  plan.fastify = { mode: 'diff-own', spec: fastifySpec };
}

// --- Synthesize whichever platform(s) still need a probe -----------------
if (!plan.express || !plan.fastify) {
  const moduleFile = changed.find(f => /^integration\/[^/]+\/src\/.*\.module\.ts$/.test(f));
  if (!moduleFile) {
    if (!plan.express && !plan.fastify) {
      die(
        'the diff has no test file that bootstraps either platform and asserts a request/correlation-id ' +
          'header, AND no *.module.ts under an integration/*/src/ directory could be found to synthesize ' +
          'a probe against -- cannot functionally verify this task at all',
      );
    }
    // At least one platform is covered by the diff's own spec; the other
    // will simply be reported as FAIL below (no way to probe it).
  } else {
    const srcDir = path.dirname(moduleFile);
    const moduleContent = fs.readFileSync(path.join(REPO, moduleFile), 'utf8');
    const moduleClassMatch = moduleContent.match(/export\s+class\s+(\w+)/);
    if (!moduleClassMatch) die(`found ${moduleFile} but could not determine its exported module class name`);
    const moduleClass = moduleClassMatch[1];
    const moduleUrl = pathToFileURL(fs.realpathSync(path.join(REPO, moduleFile))).href;

    let routePath = null;
    const controllerCandidates = changed.filter(
      f => f.startsWith(srcDir + '/') && f.endsWith('.controller.ts'),
    );
    for (const cf of controllerCandidates) {
      const content = readSafe(cf);
      const m = content.match(/@Get\(\s*['"]([^'"]*)['"]\s*\)/);
      if (m) {
        routePath = m[1];
        break;
      }
    }
    routePath = routePath || 'hello';
    if (!routePath.startsWith('/')) routePath = '/' + routePath;

    fs.mkdirSync(OUT_DIR, { recursive: true });

    const CANDIDATE_HEADERS_TS = JSON.stringify([
      'x-request-id',
      'x-correlation-id',
      'request-id',
      'correlation-id',
    ]);

    if (!plan.express) {
      const specPath = path.join(OUT_DIR, 'synth-express.spec.ts');
      fs.writeFileSync(
        specPath,
        `// AUTO-GENERATED by task_D_discover.mjs -- deleted automatically after the run.
import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';

const CANDIDATE_HEADERS = ${CANDIDATE_HEADERS_TS};
const ROUTE_PATH = ${JSON.stringify(routePath)};

describe('Synthesized Express probe (platform-express / default adapter)', () => {
  let app: INestApplication;

  beforeAll(async () => {
    const mod: any = await import(${JSON.stringify(moduleUrl)});
    const ModuleClass = mod[${JSON.stringify(moduleClass)}];
    const moduleRef = await Test.createTestingModule({ imports: [ModuleClass] }).compile();
    app = moduleRef.createNestApplication();
    await app.init();
  }, 20000);

  afterAll(async () => {
    if (app) await app.close();
  });

  it('returns a non-empty request/correlation id header under Express when none is supplied', async () => {
    const res = await request(app.getHttpServer()).get(ROUTE_PATH);
    const found = CANDIDATE_HEADERS.map(h => [h, res.headers[h]]).find(
      ([, v]) => typeof v === 'string' && v.length > 0,
    );
    if (!found) {
      throw new Error('No request/correlation id header found under Express. Headers seen: ' + JSON.stringify(res.headers));
    }
    expect(found[1]).toBeTruthy();
  });

  it('echoes back an incoming request id unchanged under Express', async () => {
    const incomingId = 'functional-check-express-incoming-id';
    const res = await request(app.getHttpServer()).get(ROUTE_PATH).set('X-Request-Id', incomingId);
    const echoed = res.headers['x-request-id'];
    if (echoed !== incomingId) {
      throw new Error(\`Expected incoming x-request-id to be echoed back unchanged under Express, got: \${JSON.stringify(echoed)}\`);
    }
  });
});
`,
      );
      plan.express = { mode: 'synthesized', spec: path.relative(REPO, specPath) };
    }

    if (!plan.fastify) {
      const specPath = path.join(OUT_DIR, 'synth-fastify.spec.ts');
      fs.writeFileSync(
        specPath,
        `// AUTO-GENERATED by task_D_discover.mjs -- deleted automatically after the run.
import { FastifyAdapter, NestFastifyApplication } from '@nestjs/platform-fastify';
import { Test } from '@nestjs/testing';

const CANDIDATE_HEADERS = ${CANDIDATE_HEADERS_TS};
const ROUTE_PATH = ${JSON.stringify(routePath)};

describe('Synthesized Fastify probe (platform-fastify)', () => {
  let app: NestFastifyApplication;

  beforeAll(async () => {
    const mod: any = await import(${JSON.stringify(moduleUrl)});
    const ModuleClass = mod[${JSON.stringify(moduleClass)}];
    const moduleRef = await Test.createTestingModule({ imports: [ModuleClass] }).compile();
    app = moduleRef.createNestApplication<NestFastifyApplication>(new FastifyAdapter());
    await app.init();
  }, 20000);

  afterAll(async () => {
    if (app) await app.close();
  });

  it('returns a non-empty request/correlation id header under Fastify when none is supplied', async () => {
    const res = await app.inject({ method: 'GET', url: ROUTE_PATH });
    const found = CANDIDATE_HEADERS.map(h => [h, res.headers[h]]).find(
      ([, v]) => typeof v === 'string' && v.length > 0,
    );
    if (!found) {
      throw new Error('No request/correlation id header found under Fastify. Headers seen: ' + JSON.stringify(res.headers));
    }
    expect(found[1]).toBeTruthy();
  });

  it('echoes back an incoming request id unchanged under Fastify', async () => {
    const incomingId = 'functional-check-fastify-incoming-id';
    const res = await app.inject({ method: 'GET', url: ROUTE_PATH, headers: { 'x-request-id': incomingId } });
    const echoed = res.headers['x-request-id'];
    if (echoed !== incomingId) {
      throw new Error(\`Expected incoming x-request-id to be echoed back unchanged under Fastify, got: \${JSON.stringify(echoed)}\`);
    }
  });
});
`,
      );
      plan.fastify = { mode: 'synthesized', spec: path.relative(REPO, specPath) };
    }
  }
}

console.error('Plan:');
console.error(JSON.stringify(plan, null, 2));
console.log(JSON.stringify(plan));
process.exit(0);
