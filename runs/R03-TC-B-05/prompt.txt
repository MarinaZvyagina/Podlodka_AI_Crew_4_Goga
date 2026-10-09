We occasionally need to put parts of our API into "maintenance mode" — for example, while we're
running a slow data migration that a handful of specific endpoints depend on, we want calls to
just those endpoints to be rejected immediately with a clear error, while the rest of the API
keeps working completely normally. Toggling maintenance mode on and off should be controllable
from within the running application itself (e.g., some internal flag or admin action), not by
redeploying.

We'd like a way for a developer to mark individual route handlers (or, sometimes, an entire
controller) as "affected by maintenance mode" when they write them, so that whenever maintenance
mode is switched on, calls to exactly those marked handlers are turned away before any of their
actual logic runs, while everything else is unaffected. When maintenance mode is switched back
off, the marked handlers should work normally again.

Some of our services also expose real-time functionality through WebSocket message handlers, and
a couple of those need the same kind of protection during migrations too. So the marking approach
needs to make sense for both regular request handlers and WebSocket message handlers, using one
consistent approach rather than building two separate mechanisms for the two cases.

Whatever you build should also be easy to unit test on its own — we want to be able to write a
fast test that checks "this specific handler is blocked while maintenance mode is on, and this
other one isn't" without having to spin up a real server or open a real socket connection.
