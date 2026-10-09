## Sync reading progress with a self-hosted library server

Some of our users run their own self-hosted manga/comic server at home (in the same general spirit
as a few similar setups the app already talks to) and want their reading progress to stay in sync
with it: when they read a chapter in the app, the server should know about it too, and the app
should be able to reflect status/progress information coming back from that server.

Please add support for logging into this kind of self-hosted server from within the app (whichever
credential scheme fits best — username/password, an API key, etc.) and keeping reading progress
synced for library entries going forward as the user reads new chapters. Users should be able to
log in, log out, and see which of their library entries are currently linked to an account on that
server. The new integration should sit naturally alongside whatever similar syncing options the
app already offers, without disrupting any of them.
