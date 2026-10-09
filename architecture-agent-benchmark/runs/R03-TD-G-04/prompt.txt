Multiple teams are asking for the same thing: they want every HTTP response our services return
to include a unique request/correlation ID in a response header, so that when something goes
wrong they can grep logs across our various services for that one ID and see everything related
to a single incoming request. If the caller already sends in an ID of their own (some of our
internal services already forward one on their outgoing calls), we should reuse that value
instead of generating a new one, so a single ID can be traced across a whole chain of internal
calls.

The ID also needs to be available to application code while it's handling the request — for
example, so a log line written from inside a route handler can include the exact same ID that
ends up in the response header, without having to parse it back out of the outgoing response.

Some of our newer services are being built on the lighter, faster of the two HTTP server
integrations this framework supports, rather than the traditional one, and this needs to work
identically on both. This isn't a "mostly works, minor gap on the newer one is acceptable"
situation — both need to actually return the header, with the correct value, on every response,
and application code that reads the ID must not need to be written differently depending on which
of the two a given service happens to use.
