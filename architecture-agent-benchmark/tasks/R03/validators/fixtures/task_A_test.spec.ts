// Task A functional validator fixture.
//
// Injected (by task_A_functional.sh) as a throwaway file inside
// packages/common/test/exceptions/, so it is picked up by the repo's own
// vitest.config.mts (`include: ['packages/**/*.spec.ts']`) exactly like any
// sibling *.exception.spec.ts file, and resolves relative imports the same
// way they do.
//
// Black-box / implementation-agnostic notes:
//   - The only assumption this test makes about the candidate's solution is
//     the one the task itself mandates by name: a class called
//     `TooManyRequestsException`, exported from the exceptions barrel
//     (packages/common/exceptions/index.ts) the same way every sibling
//     built-in HTTP exception is. That is a direct, literal requirement of
//     task_A.md / metadata_A.yaml's functional_check_command, not an
//     internal helper name specific to one candidate's implementation.
//   - The e2e portion boots a real Nest HTTP application (platform-express)
//     through the public NestFactory/ExpressAdapter entry point and issues
//     a real HTTP request via supertest -- it does not reach into any
//     candidate-specific internals (e.g. it does not care whether the
//     candidate solution also touches base-exception-filter.ts, as long as
//     the resulting HTTP response is correct).
import request from 'supertest';
import { NestFactory } from '@nestjs/core';
import { ExpressAdapter } from '@nestjs/platform-express';
import {
  Controller,
  Get,
  Module,
  HttpException,
} from '@nestjs/common';
import { TooManyRequestsException } from '../../exceptions/index.js';

@Controller()
class __FunctionalCheckController {
  @Get('too-many-requests')
  throwTooMany(): never {
    throw new TooManyRequestsException();
  }
}

@Module({ controllers: [__FunctionalCheckController] })
class __FunctionalCheckModule {}

describe('Task A functional check: TooManyRequestsException (429)', () => {
  it('extends HttpException and reports status 429 when instantiated directly (no server)', () => {
    const exc = new TooManyRequestsException();
    expect(exc).toBeInstanceOf(HttpException);
    expect(exc.getStatus()).toBe(429);
    const body = exc.getResponse() as any;
    expect(body.statusCode).toBe(429);
    expect(typeof body.message).toBe('string');
    expect(body.message.length).toBeGreaterThan(0);
  });

  it('supports overriding the message via the first constructor argument', () => {
    const exc = new TooManyRequestsException('slow down');
    const body = exc.getResponse() as any;
    expect(body.statusCode).toBe(429);
    expect(body.message).toBe('slow down');
  });

  it('supports the cause-option pattern shared with sibling exceptions', () => {
    const cause = new Error('root cause');
    const exc = new TooManyRequestsException('rate limited', { cause });
    expect((exc as any).cause).toBe(cause);
  });

  it('boots a real platform-express HTTP app and returns HTTP 429 with a statusCode:429 body when thrown uncaught from a route handler', async () => {
    const app = await NestFactory.create(
      __FunctionalCheckModule,
      new ExpressAdapter(),
      { logger: false },
    );
    await app.init();
    try {
      const server = app.getHttpServer();
      const res = await request(server).get('/too-many-requests');
      expect(res.status).toBe(429);
      expect(res.body.statusCode).toBe(429);
    } finally {
      await app.close();
    }
  });
});
