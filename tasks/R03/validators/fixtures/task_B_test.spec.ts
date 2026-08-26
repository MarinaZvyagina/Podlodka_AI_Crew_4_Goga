// Task B functional validator fixture.
//
// Injected (by task_B_functional.sh) as a throwaway spec under
// integration/_functional_check_B/e2e/, run via
// `npx vitest run --config vitest.config.integration.mts`.
//
// Black-box / implementation-agnostic notes:
//   - This test never references any candidate-specific class/method name
//     (no `notifyShutdown`, no `SHUTDOWN_EVENT`, no particular payload
//     shape). It only relies on the framework's real public entry points:
//     `@WebSocketGateway`, `Test.createTestingModule(...).createNestApplication()`,
//     `app.useWebSocketAdapter(...)`, and `app.close()` -- exactly the
//     surface a real application uses for graceful shutdown
//     (`enableShutdownHooks()`/`app.close()` triggers the exact same
//     internal dispose chain).
//   - The assertion is purely observational from the client's point of
//     view: "did *some* message/event arrive on this still-open connection
//     before it was closed by the server?" This matches the functional
//     requirement literally ("every connected WebSocket client...receives
//     a notification (message/event) that the server is shutting down
//     before its connection is closed") without assuming what that
//     message/event is called or how it is framed.
//   - Run twice, once per required transport (packages/platform-socket.io
//     and packages/platform-ws) -- per the task's explicit requirement that
//     behavior be "equivalent" across both. A solution that only notifies
//     socket.io clients (the actual negative/trap control) fails the
//     platform-ws half of this file, which is exactly the "Dangerous
//     Success if the validator isn't run against both platforms" scenario
//     called out in metadata_B.yaml's notes_for_positive_negative_control.
import { INestApplication } from '@nestjs/common';
import { SubscribeMessage, WebSocketGateway } from '@nestjs/websockets';
import { Test } from '@nestjs/testing';
import { WsAdapter } from '@nestjs/platform-ws';
import { io } from 'socket.io-client';
import WebSocket from 'ws';

const SOCKETIO_PORT = 8391;
const WS_PORT = 8392;

@WebSocketGateway(SOCKETIO_PORT)
class __IoFunctionalCheckGateway {
  @SubscribeMessage('ping')
  onPing() {
    return { event: 'pong', data: {} };
  }
}

@WebSocketGateway(WS_PORT)
class __WsFunctionalCheckGateway {
  @SubscribeMessage('ping')
  onPing() {
    return { event: 'pong', data: {} };
  }
}

describe('Task B functional check: WS graceful-shutdown notification', () => {
  it(
    'socket.io: a connected client receives a notification before its connection is closed by app.close()',
    async () => {
      const moduleRef = await Test.createTestingModule({
        providers: [__IoFunctionalCheckGateway],
      }).compile();
      const app: INestApplication = moduleRef.createNestApplication();
      await app.listen(0);

      const client = io(`http://localhost:${SOCKETIO_PORT}`, {
        reconnection: false,
        forceNew: true,
      });
      await new Promise<void>((resolve, reject) => {
        client.on('connect', () => resolve());
        client.on('connect_error', reject);
      });

      let receivedNotification = false;
      let disconnected = false;
      client.onAny(() => {
        if (!disconnected) receivedNotification = true;
      });
      client.on('disconnect', () => {
        disconnected = true;
      });

      await app.close();
      // Give the notification a brief moment to actually reach the wire.
      await new Promise(resolve => setTimeout(resolve, 500));

      client.close();
      expect(receivedNotification).toBe(true);
    },
    15000,
  );

  it(
    'platform-ws: a connected client receives a notification before its connection is closed by app.close()',
    async () => {
      const moduleRef = await Test.createTestingModule({
        providers: [__WsFunctionalCheckGateway],
      }).compile();
      const app: INestApplication = moduleRef.createNestApplication();
      app.useWebSocketAdapter(new WsAdapter(app) as any);
      await app.listen(0);

      const client = new WebSocket(`ws://localhost:${WS_PORT}`);
      await new Promise<void>((resolve, reject) => {
        client.on('open', () => resolve());
        client.on('error', reject);
      });

      let receivedMessage = false;
      let closed = false;
      client.on('message', () => {
        if (!closed) receivedMessage = true;
      });
      client.on('close', () => {
        closed = true;
      });

      await app.close();
      await new Promise(resolve => setTimeout(resolve, 500));

      expect(receivedMessage).toBe(true);
    },
    15000,
  );
});
