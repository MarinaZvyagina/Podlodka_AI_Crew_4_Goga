## Ticket: Identify which metrics are causing us to hit our series-limit settings

Some of our larger customers run with `-storage.maxHourlySeries` and/or
`-storage.maxDailySeries` configured to protect themselves from accidental cardinality
explosions. When one of these limits is hit, new series for that window simply stop being
written, and today we only expose a single aggregate counter of how many samples were dropped
because of it. When support gets a ticket about "missing data" from a customer with these
limits enabled, there is no way to tell them *which* metric name(s) were actually responsible
for hitting the limit — we have to ask the customer to go dig through their own instrumentation
or guess.

Please add a way to track, per metric name, how many samples were dropped because adding that
series would have exceeded the configured hourly or daily unique-series limit, and make that
information queryable (e.g., "show me the top N metric names by drop count since the last
reset").

Requirements:

- When a sample is dropped for exceeding `-storage.maxHourlySeries` or
  `-storage.maxDailySeries`, record which metric name it belonged to and increment a per-name
  counter for that metric.
- Expose a way to query the collected data (top offending metric names with their counts is
  enough; exact API shape is up to you).
- This tracking must not cause unbounded memory growth — installations with millions of
  distinct metric names must not be able to make this feature consume arbitrary amounts of
  memory. Make the memory bound configurable or bounded by a sensible fixed default.
- The feature should be able to be turned off with no measurable overhead on the ingestion hot
  path when disabled.
- Add tests that cover: recording drops for multiple metric names, querying the top offenders,
  and the memory bound actually being respected.

This only needs to work for single-node and the storage component of the cluster build — it
does not need to be tenant-aware.
