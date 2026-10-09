# R05 — VictoriaMetrics/VictoriaMetrics recon notes

Repository: `VictoriaMetrics/VictoriaMetrics`
Pinned commit: `f65ae841ace8f686ddc0dc17fe936d0bf38e568c`

## Method

Disk on this machine actually showed ~28GB free (`df -h /`), well above the ~4GB the task
description warned about, but recon still avoided a full clone. Used:
`git clone --filter=blob:none --no-checkout`, then `git config core.sparseCheckout true` with a
sparse-checkout list limited to `lib/storage/`, `lib/promscrape/`, `app/`, `*.md`, `Makefile`,
`docs/` at `/tmp/vm-recon`, plus targeted `curl` fetches of raw file contents at the pinned
commit for anything outside the sparse set (e.g. `lib/bloomfilter/limiter.go`,
`lib/timeserieslimits/timeseries_limits.go`, `lib/promrelabel/*.go`). GitHub's code-search API
(`gh api search/code?q=...+repo:...`) was used to find cross-file call sites cheaply. The
`/tmp/vm-recon` clone is removed at the end of this task (see cleanup command below) — no
lasting local copy of the repository is kept.

## Confirmed facts used as grounding

### Module layout
- `app/` has 21 binaries (confirmed via `contents/app`): victoria-logs, victoria-metrics,
  vlagent, vlinsert, vlogscli, vlogsgenerator, vlselect, vlstorage, vmagent, vmalert-tool,
  vmalert, vmauth, vmbackup, vmbackupmanager, vmctl, vmgateway, vminsert, vmrestore, vmselect,
  vmstorage, vmui.
- `lib/` has ~100 shared packages (confirmed listing).
- `lib/promscrape/discovery/` has exactly 22 backend packages: azure, consul, consulagent,
  digitalocean, dns, docker, dockerswarm, ec2, eureka, gce, hetzner, http, kubernetes, kuma,
  linode, marathon, nomad, openstack, ovhcloud, puppetdb, vultr, yandexcloud.
- `lib/storage/` is confirmed as a large, flat package: `storage.go` = 2687 lines, `index_db.go`
  = 3482 lines, `partition.go` = 1955 lines, `table.go` = 732 lines, `search.go` = 607 lines
  (measured via `wc -l` on the raw pinned-commit content), all in one Go package with 34 files.

### Task C — the SD extension point (verified, not assumed)
- `lib/promscrape/config.go` line ~851-853 defines an unnamed interface:
  ```go
  type targetLabelsGetter interface {
      GetLabels(baseDir string) ([]*promutil.Labels, error)
  }
  ```
- Every one of the 22 `lib/promscrape/discovery/<name>` packages exposes an `SDConfig` struct
  implementing `GetLabels(baseDir string) ([]*promutil.Labels, error)` — confirmed directly by
  reading `lib/promscrape/discovery/digitalocean/digitalocean.go`.
- `ScrapeConfig` (lib/promscrape/config.go ~line 292-343) has one field per backend, e.g.
  `DigitaloceanSDConfigs []digitalocean.SDConfig \`yaml:"digitalocean_sd_configs,omitempty"\``.
- Each backend gets a `getXXXSDScrapeWork` function (e.g. `getDigitalOceanDScrapeWork`,
  line ~632) that builds a `visitConfigs` closure and calls the shared
  `cfg.getScrapeWorkGeneric(visitConfigs, "<name>_sd_config", prev)` (defined ~line 855).
- Each backend is registered once via `scs.add("<name>_sd_configs", *<pkg>.SDCheckInterval,
  func(cfg *Config, swsPrev []*ScrapeWork) []*ScrapeWork { return
  cfg.get<Name>SDScrapeWork(swsPrev) })` inside `runScraper()` in `lib/promscrape/scraper.go`
  (~lines 129-152) — confirmed by reading the full block of 22 `scs.add(...)` calls.
- Only `KubernetesSDConfigs` and `HTTPSDConfigs` get `MustStart` calls (stateful watch/long-poll
  backends); nearly all 22 get `MustStop` calls — confirmed by reading the `mustStart`/`mustStop`
  methods on `ScrapeConfig`.
- Confirmed **not yet implemented**: Scaleway is absent from the 22-backend list, making it a
  realistic, ungrounded-in-existing-code feature request for Task C (checked the directory
  listing directly; no scaleway/triton/uyuni/ionos/cloudfoundry package exists at this commit).

### Task D — the god-package boundary discipline (verified, not assumed)
- `lib/storage/` contains two subpackages that pre-date this task and demonstrate real
  boundary discipline inside the otherwise-flat "god package":
  - `lib/storage/metricnamestats/tracker.go` — a `Tracker` struct with its own
    mutex-protected `map[statKey]*statItem`, an explicit `maxSizeBytes` bound with
    `storeOverhead` accounting, disk persistence (`MustLoadFrom`/`loadFrom`), and a narrow
    method API (`RegisterIngestRequest`, `GetStats`, `GetStatRecordsForNames`, `UpdateMetrics`,
    `MustClose`, `Reset`).
  - `lib/storage/metricsmetadata/storage.go` — a `Storage` struct with sharded buckets
    (`bucketsCount = 8`), a `maxSizeBytes` bound, and a background `cleaner` goroutine.
  - `lib/storage/storage.go` wires both in via single pointer fields:
    `metricsTracker *metricnamestats.Tracker` (line ~149) and (confirmed via grep)
    `metadataStorage *metricsmetadata.Storage`, each touched only at a handful of narrow call
    sites (e.g. `s.metricsTracker.RegisterIngestRequest(0, 0, mn.MetricGroup)` at line ~2065,
    `s.metricsTracker.GetStats(...)` inside the exported `GetMetricNamesStats` at line ~2662).
  - `Storage.UpdateMetrics` (line ~610-690) shows the pattern explicitly: it calls
    `s.metricsTracker.UpdateMetrics(&tm)` and `s.metadataStorage.UpdateMetrics(&mr)` rather than
    directly maintaining those counters as `Storage` fields.
- The exact hook point for the trap ticket's "drop tracking" feature is confirmed real: the
  existing hourly/daily series-limit rejection path already exists at
  `lib/storage/storage.go` ~lines 2152-2166:
  ```go
  if sl := s.hourlySeriesLimiter; sl != nil && !sl.Add(metricID) {
      ...
      logSkippedSeries(metricNameRaw, "-storage.maxHourlySeries", sl.MaxItems())
  }
  if sl := s.dailySeriesLimiter; sl != nil && !sl.Add(metricID) {
      ...
      logSkippedSeries(metricNameRaw, "-storage.maxDailySeries", sl.MaxItems())
  }
  ```
  `metricNameRaw` (the metric name) is already in scope at this exact point, making
  per-metric-name drop tracking a natural, minimal addition *if* the agent follows the existing
  subpackage pattern — or a tempting place to bolt on a raw `map[string]uint64` field directly
  onto `Storage` if it doesn't.
- Note: `HourlySeriesLimitCurrentSeries`/`HourlySeriesLimitMaxSeries` (aggregate, not
  per-metric-name) **already exist** in `Storage.UpdateMetrics` — this was checked explicitly to
  avoid designing a task around an already-shipped feature. The per-metric-name breakdown is
  confirmed absent (no such field/tracking found anywhere in storage.go).

### Task B — cross-module grounding
- `app/vmagent/main.go` registers HTTP routes that call directly into `lib/promscrape`
  functions: `promscrape.WriteHumanReadableTargetsStatus`, `promscrape.WriteAPIV1Targets`,
  `promscrape.WriteServiceDiscovery`, `promscrape.Init`/`promscrape.Stop` — confirmed via grep
  on `app/vmagent/main.go`. This is a real, distinct layer from `lib/promscrape` itself.
  vmagent does **not** redeclare promscrape's flags; all `-promscrape.*` flags live inside
  `lib/promscrape` (e.g. `noStaleMarkers`, `seriesLimitPerTarget`, `maxScrapeSize` are all
  `flag.*` calls inside `lib/promscrape/config.go`), confirmed by reading the top of
  `config.go`.
- `lib/promscrape/targetstatus.go` already has a per-request-tracked `-promscrape.maxDroppedTargets`
  flag and `tsmGlobal` target-status map — the natural place to extend for "which jobs are over
  the new per-job target cap," confirmed by reading the top of `targetstatus.go`.
- Confirmed **no existing cap** on the number of targets a single job can register from service
  discovery (searched for `maxDroppedTargets`-adjacent flags; that flag limits how many
  *dropped-by-relabeling* targets are remembered for display, a different concern from capping
  *active* target count per job).
- `lib/storage.TSID` (lib/storage/tsid.go) was checked directly and confirmed to have **no**
  `AccountID`/`ProjectID` fields in this version — ruled out designing Task B around
  "per-tenant series limiter" since single-node/storage-layer multi-tenancy isn't a first-class
  concept at the TSID level in this codebase; that would have required inventing architecture
  not actually present.

### Task A — grounding
- `lib/promrelabel/relabel.go` implements a single `(prc *parsedRelabelConfig) apply(...)`
  method with a big `switch prc.Action`, including `case "uppercase":` / `case "lowercase":`
  (confirmed at ~lines 411-425) — value-transforming actions with the exact shape needed
  (`concatLabelValues(source_labels, separator)` → transform → `setLabelValue(target_label)`).
  Confirmed via `grep -in trim` that no whitespace-trimming action exists yet.
- `lib/promrelabel/config.go` has a second, separate validation `switch action` (~lines 269-393)
  that must also be extended, ending in `default: return nil, fmt.Errorf("unknown \`action\` %q",
  action)` — confirmed exact validation shape for `uppercase`/`lowercase`
  (`missing source_labels for action=%s` / `missing target_label for action=%s`).
- `RelabelConfig` struct fields (`SourceLabels`, `Separator`, `TargetLabel`, etc.) confirmed by
  reading `lib/promrelabel/config.go` lines 1-45 — the new action can reuse these without any
  schema change.

## Confirmation: no task prompt names the extension point or internal identifiers

Ran `grep -inE "lib/|app/|\.go\b|struct|interface|package|SDConfig|GetLabels|targetLabelsGetter|
promrelabel|promscrape|metricnamestats|metricsmetadata|scs\.add|getScrapeWork|ScrapeConfig|
Storage struct|IndexDB|tsmGlobal|relabel\.go|config\.go|scraper\.go"` against all four
`task_*.md` files. The only hit was the substring `struct` inside the English word
"infrastructure" in task_C.md — not an actual identifier leak. All four task prompts read as
plain natural-language engineering tickets, name only real external systems (Scaleway,
`-storage.maxHourlySeries`/`-storage.maxDailySeries` — these are documented, user-facing
command-line flags, not internal architecture, so naming them is equivalent to naming a public
config option a user would already know about) and never name Go package paths, struct/interface
names, function names, or the word "registry"/"plugin"/"extension point".

Task C in particular was checked against Research.md section 18's rule most carefully: the
prompt never says "service discovery," "discovery backend," "SDConfig," "interface," or
"registry" — it only describes the desired user-facing behavior (auto-discover Scaleway
instances, label them, refresh periodically) and asks the agent to "follow whatever conventions
the codebase already uses for integrations of this kind," which is realistic ticket language
that does not reveal *where* or *what* those conventions are.

## Cleanup

`/tmp/vm-recon` (the sparse partial clone used for recon) is removed after this file is written;
no full or partial local clone of VictoriaMetrics is retained on disk.
