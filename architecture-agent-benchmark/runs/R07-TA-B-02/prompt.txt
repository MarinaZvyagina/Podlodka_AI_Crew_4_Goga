## Reject invalid custom extension repository URLs early

Users can add custom extension repository URLs in the app so they can install extensions from
catalogs beyond the official one. Right now, if someone pastes in something that isn't actually a
usable repository URL — a plain word, a copy-paste mistake, or a URL using a scheme that could
never point at a valid repository index — the app still tries to reach it over the network and
only fails several steps later with a raw, technical-looking error that doesn't really tell the
user what went wrong.

Please make the app reject obviously invalid repository URLs immediately, before making any
network request, and show a clear, understandable message explaining that the entered value isn't
a valid repository URL. Only proper `http://` or `https://` URLs should be accepted; anything else
(empty input, missing scheme, a non-http(s) scheme, obviously malformed text, etc.) should be
rejected with a friendly error instead of a confusing network failure.

Existing behavior for adding, refreshing, and removing valid repositories should not change.
