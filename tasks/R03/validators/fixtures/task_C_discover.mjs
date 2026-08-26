// Task C functional validator -- discovery + spec-generation script.
//
// Not a fixture in the "static file copied verbatim" sense used by the
// other tasks: Task C's functional requirement ("a developer can mark ANY
// handler/controller as maintenance-protected") does not fix a class name,
// decorator name, or service API, so a single static spec file cannot
// exercise an arbitrary candidate's demo app. Instead this script:
//
//   1. Reads the diff (git diff --name-only HEAD + untracked files, same
//      method the architecture validators use) to locate the candidate's
//      own demo application: a *.module.ts under an integration/*/src/
//      directory (same discovery convention as task_D_AC5.sh), plus a
//      sibling *.controller.ts and *.gateway.ts in the same directory.
//   2. Parses (via lightweight regex over the source, not a full TS
//      compiler) which controller route / gateway message handler carries
//      an *extra* decorator beyond the standard HTTP/WS ones -- that extra
//      decorator is assumed to be the "maintenance protected" marker,
//      whatever it is actually called.
//   3. Locates the maintenance-toggle service (by walking the discovered
//      guard's constructor parameter types if a `implements CanActivate`
//      class exists in the diff, else by name heuristic `*Service`/
//      `*Maintenance*` among changed files) -- again without assuming a
//      specific class name.
//   4. Emits a self-contained vitest e2e spec that boots the *discovered*
//      module for real (Test.createTestingModule + a real HTTP listener +
//      a real socket.io client), and at runtime -- via plain object
//      reflection over the discovered service instance, not by guessing
//      method names -- finds whichever zero-arg method flips a
//      boolean-returning zero-arg "state" method from false to true (the
//      "enable" toggle) and back (the "disable" toggle). It never imports
//      or calls anything by an assumed name like `enable()`/`isEnabled()`.
//   5. That generated spec independently asserts (not by trusting any
//      call-log/spy the candidate's own diff may have added, since a trap
//      implementation could write self-serving assertions):
//        - HTTP: the protected route returns a non-2xx status while
//          maintenance is toggled on; the unprotected route keeps
//          returning 2xx.
//        - WS: emitting the protected message produces NO reply within a
//          timeout while maintenance is on; emitting the unprotected
//          message still produces some reply.
//        - Toggling maintenance back off restores 2xx / a reply for the
//          previously-blocked handler, with no app restart.
//
// Usage: node task_C_discover.mjs <repoAbsPath> <outSpecPath>
// Exits 0 and writes outSpecPath on success; exits 1 and prints a
// diagnostic to stderr if the candidate's demo app cannot be located or
// parsed well enough to build an independent functional check.
import { execSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const REPO = process.argv[2];
const OUT_SPEC = process.argv[3];

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

function realUrl(relFile) {
  return pathToFileURL(fs.realpathSync(path.join(REPO, relFile))).href;
}

const changed = changedFiles();
if (changed.length === 0) die('no changes detected against HEAD (nothing to validate)');

// --- 1. Locate the demo module -----------------------------------------
const moduleFile = changed.find(f => /^integration\/[^/]+\/src\/.*\.module\.ts$/.test(f));
if (!moduleFile) {
  die(
    'could not locate a *.module.ts under an integration/*/src/ directory in the diff -- ' +
      'cannot boot a demo app to functionally verify maintenance-mode behavior',
  );
}
const moduleContent = fs.readFileSync(path.join(REPO, moduleFile), 'utf8');
const moduleClassMatch = moduleContent.match(/export\s+class\s+(\w+)/);
if (!moduleClassMatch) die(`found ${moduleFile} but could not determine its exported module class name`);
const moduleClass = moduleClassMatch[1];
const srcDir = path.dirname(moduleFile);

// --- helper: parse "method -> decorators" pairs from a class body ------
function parseDecoratedMethods(content) {
  const lines = content.split('\n');
  const methods = [];
  let pending = [];
  for (const line of lines) {
    const decoratorMatch = line.match(/^\s*@(\w+)\(([^)]*)\)\s*$/);
    if (decoratorMatch) {
      pending.push({ name: decoratorMatch[1], arg: decoratorMatch[2] });
      continue;
    }
    const methodMatch = line.match(
      /^\s*(?:public\s+|private\s+|protected\s+|async\s+|static\s+)*(\w+)\s*\(/,
    );
    if (methodMatch && methodMatch[1] !== 'constructor') {
      if (pending.length > 0) {
        methods.push({ name: methodMatch[1], decorators: pending });
      }
      pending = [];
    } else if (line.trim() !== '' && !decoratorMatch) {
      pending = [];
    }
  }
  return methods;
}

function stripQuotes(s) {
  return (s || '').trim().replace(/^['"]|['"]$/g, '');
}

// --- 2a. Locate + parse the controller ----------------------------------
const KNOWN_HTTP_DECORATORS = new Set([
  'Get', 'Post', 'Put', 'Delete', 'Patch', 'Options', 'Head', 'All',
  'HttpCode', 'Header', 'Redirect', 'UseGuards', 'UseInterceptors',
  'UseFilters', 'UsePipes', 'Render', 'Sse', 'Controller',
]);

const controllerCandidates = changed.filter(
  f => f.startsWith(srcDir + '/') && f.endsWith('.controller.ts'),
);
let httpProtected = null;
let httpUnprotected = null;
for (const cf of controllerCandidates) {
  const content = fs.readFileSync(path.join(REPO, cf), 'utf8');
  const methods = parseDecoratedMethods(content).filter(m =>
    m.decorators.some(d => d.name === 'Get'),
  );
  for (const m of methods) {
    const getDec = m.decorators.find(d => d.name === 'Get');
    const routePath = stripQuotes(getDec.arg) || '/';
    const hasCustomDecorator = m.decorators.some(d => !KNOWN_HTTP_DECORATORS.has(d.name));
    const entry = { file: cf, method: m.name, path: routePath.startsWith('/') ? routePath : '/' + routePath };
    if (hasCustomDecorator && !httpProtected) httpProtected = entry;
    else if (!hasCustomDecorator && !httpUnprotected) httpUnprotected = entry;
  }
}
if (!httpProtected || !httpUnprotected) {
  die(
    'could not find, in the diff\'s own demo controller, one @Get route carrying an extra ' +
      '(non-standard) decorator and one plain @Get route to compare it against',
  );
}

// --- 2b. Locate + parse the gateway --------------------------------------
const KNOWN_WS_DECORATORS = new Set([
  'SubscribeMessage', 'UseGuards', 'UseInterceptors', 'UseFilters', 'UsePipes', 'WebSocketGateway',
]);
const gatewayCandidates = changed.filter(
  f => f.startsWith(srcDir + '/') && f.endsWith('.gateway.ts'),
);
let wsProtected = null;
let wsUnprotected = null;
let gatewayPort = null;
for (const gf of gatewayCandidates) {
  const content = fs.readFileSync(path.join(REPO, gf), 'utf8');
  const portMatch = content.match(/@WebSocketGateway\((\d+)/);
  if (portMatch) gatewayPort = Number(portMatch[1]);
  const methods = parseDecoratedMethods(content).filter(m =>
    m.decorators.some(d => d.name === 'SubscribeMessage'),
  );
  for (const m of methods) {
    const subDec = m.decorators.find(d => d.name === 'SubscribeMessage');
    const messageName = stripQuotes(subDec.arg);
    const hasCustomDecorator = m.decorators.some(d => !KNOWN_WS_DECORATORS.has(d.name));
    const entry = { file: gf, method: m.name, message: messageName };
    if (hasCustomDecorator && !wsProtected) wsProtected = entry;
    else if (!hasCustomDecorator && !wsUnprotected) wsUnprotected = entry;
  }
}
if (!wsProtected || !wsUnprotected) {
  die(
    'could not find, in the diff\'s own demo gateway, one @SubscribeMessage handler carrying an ' +
      'extra (non-standard) decorator and one plain @SubscribeMessage handler to compare it against ' +
      '-- this by itself means the WebSocket side of the maintenance-mode requirement is not ' +
      'independently verifiable as implemented',
  );
}

// --- 3. Locate the maintenance-toggle service ---------------------------
let serviceFile = null;
let serviceClass = null;

const guardFile = changed.find(f => {
  if (!f.endsWith('.ts') || f.endsWith('.spec.ts')) return false;
  const c = fs.readFileSync(path.join(REPO, f), 'utf8');
  return /implements\s+CanActivate\b/.test(c);
});
if (guardFile) {
  const content = fs.readFileSync(path.join(REPO, guardFile), 'utf8');
  const ctorMatch = content.match(/constructor\s*\(([\s\S]*?)\)\s*\{/);
  if (ctorMatch) {
    const params = ctorMatch[1].split(',');
    for (const p of params) {
      const typeMatch = p.match(/:\s*([A-Za-z0-9_]+)/);
      if (typeMatch && typeMatch[1] !== 'Reflector') {
        const candidateClass = typeMatch[1];
        const candidateFile = changed.find(f => {
          if (!f.endsWith('.ts') || f.endsWith('.spec.ts')) return false;
          const c = fs.readFileSync(path.join(REPO, f), 'utf8');
          return new RegExp(`class\\s+${candidateClass}\\b`).test(c);
        });
        if (candidateFile) {
          serviceClass = candidateClass;
          serviceFile = candidateFile;
          break;
        }
      }
    }
  }
}
if (!serviceClass) {
  // Fallback: no CanActivate guard in the diff at all (e.g. the negative
  // control's Express-middleware trap) -- look for a plausible toggle
  // service by name among changed files instead, so the functional check
  // can still independently drive the app's maintenance state.
  const nameCandidate = changed.find(f => {
    if (!f.endsWith('.ts') || f.endsWith('.spec.ts')) return false;
    if (!/service\.ts$/i.test(f) && !/maintenance/i.test(f)) return false;
    const c = fs.readFileSync(path.join(REPO, f), 'utf8');
    return /export\s+class\s+\w+/.test(c);
  });
  if (nameCandidate) {
    const c = fs.readFileSync(path.join(REPO, nameCandidate), 'utf8');
    const m = c.match(/export\s+class\s+(\w+)/);
    if (m) {
      serviceClass = m[1];
      serviceFile = nameCandidate;
    }
  }
}
if (!serviceClass) {
  die('could not locate any maintenance-mode toggle service/provider among the diff\'s changed files');
}

const info = {
  moduleFile, moduleClass, moduleUrl: realUrl(moduleFile),
  serviceFile, serviceClass, serviceUrl: realUrl(serviceFile),
  httpProtectedPath: httpProtected.path,
  httpUnprotectedPath: httpUnprotected.path,
  wsProtectedMessage: wsProtected.message,
  wsUnprotectedMessage: wsUnprotected.message,
  gatewayPort,
};

console.error('Discovered demo app:');
console.error(JSON.stringify(info, null, 2));

const spec = `// AUTO-GENERATED by task_C_discover.mjs -- deleted automatically after the run.
import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { io } from 'socket.io-client';
import request from 'supertest';

const HTTP_PROTECTED_PATH = ${JSON.stringify(info.httpProtectedPath)};
const HTTP_UNPROTECTED_PATH = ${JSON.stringify(info.httpUnprotectedPath)};
const WS_PROTECTED_MESSAGE = ${JSON.stringify(info.wsProtectedMessage)};
const WS_UNPROTECTED_MESSAGE = ${JSON.stringify(info.wsUnprotectedMessage)};
const GATEWAY_PORT = ${info.gatewayPort === null ? 'null' : info.gatewayPort};

function getMethodNames(obj: any): string[] {
  const proto = Object.getPrototypeOf(obj);
  return Object.getOwnPropertyNames(proto).filter(
    name => name !== 'constructor' && typeof obj[name] === 'function' && obj[name].length === 0,
  );
}

/**
 * Finds, purely via runtime reflection over the discovered service
 * instance (no assumed method names), a boolean-returning zero-arg
 * "getter", plus whichever zero-arg method flips it true ("enable") and
 * whichever flips it back false ("disable").
 */
function discoverToggle(serviceInstance: any) {
  const methods = getMethodNames(serviceInstance);
  let getterName: string | null = null;
  for (const name of methods) {
    try {
      const val = serviceInstance[name]();
      if (typeof val === 'boolean') {
        getterName = name;
        break;
      }
    } catch {
      /* not a pure getter -- ignore */
    }
  }
  if (!getterName) {
    throw new Error(
      'Could not find a boolean-returning zero-arg state method on the discovered service ' +
        '(tried: ' + methods.join(', ') + ')',
    );
  }
  let enableName: string | null = null;
  let disableName: string | null = null;
  // Ensure a known baseline (disabled) before probing.
  for (const name of methods) {
    if (name === getterName) continue;
    try {
      const before = serviceInstance[getterName]();
      serviceInstance[name]();
      const after = serviceInstance[getterName]();
      if (before === false && after === true && !enableName) enableName = name;
      if (before === true && after === false && !disableName) disableName = name;
    } catch {
      /* ignore -- unrelated method */
    }
  }
  if (!enableName || !disableName) {
    throw new Error(
      \`Could not identify both an "enable" and a "disable" toggle method on the discovered \` +
        \`service via reflection (getter=\${getterName}, enable=\${enableName}, disable=\${disableName})\`,
    );
  }
  return { getterName, enableName, disableName };
}

describe('Task C functional check (dynamic discovery): maintenance-mode guard, HTTP + WS', () => {
  let app: INestApplication;
  let httpServer: any;
  let toggle: { getterName: string; enableName: string; disableName: string };
  let serviceInstance: any;
  let wsPort: number;
  let ws: ReturnType<typeof io>;

  beforeAll(async () => {
    const moduleMod: any = await import(${JSON.stringify(info.moduleUrl)});
    const ModuleClass = moduleMod[${JSON.stringify(info.moduleClass)}];
    const serviceMod: any = await import(${JSON.stringify(info.serviceUrl)});
    const ServiceClass = serviceMod[${JSON.stringify(info.serviceClass)}];

    const moduleRef = await Test.createTestingModule({ imports: [ModuleClass] }).compile();
    app = moduleRef.createNestApplication();
    await app.listen(0);
    httpServer = app.getHttpServer();

    serviceInstance = app.get(ServiceClass);
    toggle = discoverToggle(serviceInstance);
    // Force a known baseline: disabled.
    if (serviceInstance[toggle.getterName]()) {
      serviceInstance[toggle.disableName]();
    }

    wsPort = GATEWAY_PORT ?? httpServer.address().port;
    ws = io(\`http://localhost:\${wsPort}\`, { reconnection: false, forceNew: true });
    await new Promise<void>((resolve, reject) => {
      ws.on('connect', () => resolve());
      ws.on('connect_error', reject);
    });
  }, 20000);

  afterAll(async () => {
    if (ws) ws.close();
    if (app) await app.close();
  });

  it('sanity: both routes/messages work normally while maintenance mode is off', async () => {
    await request(httpServer).get(HTTP_PROTECTED_PATH).expect(res => {
      if (res.status < 200 || res.status >= 300) {
        throw new Error(\`expected protected route to work while maintenance is off, got \${res.status}\`);
      }
    });
    await request(httpServer).get(HTTP_UNPROTECTED_PATH).expect(res => {
      if (res.status < 200 || res.status >= 300) {
        throw new Error(\`expected unprotected route to work, got \${res.status}\`);
      }
    });
  });

  it('HTTP: the marked route is rejected while maintenance mode is on; the unmarked route keeps working', async () => {
    serviceInstance[toggle.enableName]();
    try {
      const protectedRes = await request(httpServer).get(HTTP_PROTECTED_PATH);
      expect(protectedRes.status).toBeGreaterThanOrEqual(400);

      const unprotectedRes = await request(httpServer).get(HTTP_UNPROTECTED_PATH);
      expect(unprotectedRes.status).toBeGreaterThanOrEqual(200);
      expect(unprotectedRes.status).toBeLessThan(300);
    } finally {
      serviceInstance[toggle.disableName]();
    }
  });

  it('WS: the marked message handler produces no reply while maintenance mode is on; the unmarked handler keeps replying', async () => {
    serviceInstance[toggle.enableName]();
    try {
      // NOTE: 'exception' is excluded on purpose -- it is the framework's
      // own, stable (not candidate-specific) event name that
      // BaseWsExceptionFilter emits back to the client whenever a guard
      // (or anything else) throws inside the WS pipeline (see
      // packages/websockets/exceptions/base-ws-exception-filter.ts). A
      // correct guard-based rejection is *expected* to produce exactly
      // that event instead of the handler's own reply, so counting it as
      // "the handler replied" would be wrong.
      let protectedReplyReceived = false;
      const onAnyDuringProtected = (event: string) => {
        if (event !== 'exception') protectedReplyReceived = true;
      };
      ws.onAny(onAnyDuringProtected);
      ws.emit(WS_PROTECTED_MESSAGE, { probe: true });
      await new Promise(resolve => setTimeout(resolve, 600));
      ws.offAny(onAnyDuringProtected);
      expect(protectedReplyReceived).toBe(false);

      const unprotectedReply = new Promise<void>((resolve, reject) => {
        const timer = setTimeout(() => reject(new Error('timed out waiting for unprotected reply')), 3000);
        ws.onAny((event: string) => {
          if (event === 'exception') return;
          clearTimeout(timer);
          resolve();
        });
      });
      ws.emit(WS_UNPROTECTED_MESSAGE, { probe: true });
      await unprotectedReply;
    } finally {
      serviceInstance[toggle.disableName]();
    }
  }, 10000);

  it('toggling maintenance mode off restores normal behavior for the previously-blocked handler, with no restart', async () => {
    serviceInstance[toggle.enableName]();
    const blockedRes = await request(httpServer).get(HTTP_PROTECTED_PATH);
    expect(blockedRes.status).toBeGreaterThanOrEqual(400);

    serviceInstance[toggle.disableName]();
    const restoredRes = await request(httpServer).get(HTTP_PROTECTED_PATH);
    expect(restoredRes.status).toBeGreaterThanOrEqual(200);
    expect(restoredRes.status).toBeLessThan(300);
  });
});
`;

fs.mkdirSync(path.dirname(OUT_SPEC), { recursive: true });
fs.writeFileSync(OUT_SPEC, spec);
console.error(`Generated spec at: ${OUT_SPEC}`);
process.exit(0);
