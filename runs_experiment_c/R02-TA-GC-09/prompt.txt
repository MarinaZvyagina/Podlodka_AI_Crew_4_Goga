The disk usage beacon lets operators get an alert when a mount point's usage climbs above a
configured percentage — useful for catching a filling disk before it becomes a real problem.

Support engineers have also asked for the opposite case: alert when a mount that is normally
busy suddenly shows very low usage. In practice this almost always means the filesystem
silently failed to mount (so what looks like the real disk is actually an empty directory on
the root filesystem), rather than that someone genuinely freed up a lot of space, and it's
been the cause of a few confusing incidents where "everything looks fine" dashboards missed a
mount that quietly fell off.

Add a way to configure a "usage dropped below expected" style alert for a mount, alongside the
existing "usage rose above threshold" alerts, so both can be configured for the same or
different mounts. Existing configuration that operators already have in production for the
current high-usage alerting must keep working exactly as it does today, with no changes
required on their end.
