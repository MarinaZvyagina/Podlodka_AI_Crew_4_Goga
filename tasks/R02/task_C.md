Some Salt masters run on small, single-node setups where operators don't want to install and
operate a separate database service (Redis, MySQL, and similar) just to get durable, persistent
storage for the master's cached minion data — things like cached grains snapshots, mine data,
and job return information — that needs to survive a restart of the master process.

Add the ability to keep this cached data in a single ordinary SQLite database file on disk
instead, selectable through normal master configuration. An operator who turns this option on
should be able to restart the master and still have their previously cached data available
afterward, using only what already ships with a standard Python installation — no extra
services or third-party packages to install.

Deployments that don't opt into this new option must keep behaving exactly as they do today.
