Operators managing large fleets of minions have no easy way to tell, from the command line,
whether a given minion's configured beacons are actually running and firing, or have gone
silent — for example because a watched file was deleted, a monitored process stopped existing,
or a dependency the beacon relies on started erroring out. Today the only way to check is to
dig through minion logs directly on the box, which doesn't scale past a handful of machines and
often isn't practical at all for a remote fleet.

Add a way to ask a minion, the same way you'd ask it to list its currently configured beacons or
check on a running job, when each of its beacons last actually executed, and whether that last
execution produced an error. This should reflect real beacon activity as it happens — not
require waiting for a new probe cycle, not require reading log files, and not require restarting
the minion or touching the beacon configuration to start collecting this information.

If a particular beacon hasn't fired even once yet, the answer should clearly say so rather than
returning a stale or made-up value.
