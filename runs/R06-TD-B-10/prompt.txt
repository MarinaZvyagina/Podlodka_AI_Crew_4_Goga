Several users have reported that their workloads issue the exact same read request over and
over in short bursts — for example, many application replicas all requesting the same small set
of keys at startup and then again periodically — and this is adding avoidable load to the
cluster for no real benefit, since the data usually hasn't changed between those reads.

Please add caching for repeated read requests that use identical parameters, so that repeated
reads don't have to go all the way through the normal read path every time. The cache must be
invalidated appropriately whenever the underlying data changes, so that clients never observe
results that are more stale than what a normal, uncached read would have returned at the time of
the request.

Requirements:
- Repeated read requests with identical parameters (same key/range, same options) issued shortly
  after one another can be served without redoing the full read work every time.
- A client must never see a value that is older than what an equivalent non-cached read would
  have returned at the time it was made — this includes reads that ask for the strongest
  consistency guarantee etcd offers, as well as reads that accept a relaxed guarantee.
- Any write or deletion that affects a previously-cached range must be reflected in subsequent
  reads promptly — relying on a short fixed expiration timer alone, which could still hand back
  stale data during a legitimate concurrent write, is not acceptable.
- Requests that aren't served from the cache (cache misses) must behave exactly as before.
