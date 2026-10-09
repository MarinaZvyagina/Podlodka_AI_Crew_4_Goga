#!/usr/bin/env bash
# AC4: No workaround/parallel-mechanism implementation (e.g. sidecar-script-plus-
# http_sd_configs docs, or a bespoke external target providers plugin system invented
# for this one feature). This check is inherently judgement-based; we automate what we
# can by grepping for suspicious patterns and fall back to MANUAL REVIEW REQUIRED when
# the automated signals are inconclusive.
set -u

REPO="${1:-.}"
SUSPICIOUS=0
REASONS=()

# Signal 1: scaleway-flavored code living in app/ (vmagent/vmalert/etc) rather than
# purely inside lib/promscrape/discovery/scaleway. Legit implementations should have
# zero scaleway references under app/.
if [ -d "$REPO/app" ]; then
  APP_HITS="$(grep -rniIl 'scaleway' "$REPO/app" 2>/dev/null)"
  if [ -n "$APP_HITS" ]; then
    SUSPICIOUS=1
    REASONS+=("scaleway references found under app/: $(echo "$APP_HITS" | tr '\n' ' ')")
  fi
fi

# Signal 2: a goroutine/poller writing a temp file that is then consumed via
# file_sd_configs (a common trap shape), combined with scaleway references anywhere.
# lib/promscrape/config.go and lib/promscrape/scraper.go are excluded from this
# heuristic: they are the shared registration/parsing hubs for ALL ~23 SD backends
# (including the pre-existing file_sd_configs backend), so in ANY correct
# implementation - trap or not - those two files will legitimately contain both
# "scaleway" and "file_sd_configs" tokens without that being suspicious. What *is*
# suspicious is a scaleway-flavored file elsewhere in the tree that also deals with
# file_sd/temp-file mechanics.
FILESD_TRAP="$(grep -rniIl 'scaleway' "$REPO" --include=*.go 2>/dev/null \
  | grep -v -E '/lib/promscrape/(config|scraper)\.go$' \
  | xargs -I{} grep -l 'file_sd_configs\|FileSDConfig\|WriteFile' {} 2>/dev/null)"
if [ -n "$FILESD_TRAP" ]; then
  SUSPICIOUS=1
  REASONS+=("files mentioning scaleway also reference file_sd_configs/FileSDConfig/WriteFile (possible sidecar/file-based workaround): $(echo "$FILESD_TRAP" | tr '\n' ' ')")
fi

# Signal 3: a new generic external/plugin SD abstraction invented alongside this
# feature (e.g. external_sd_configs, a command-based plugin loader, or .so loading).
PLUGIN_TRAP="$(grep -rniI 'external_sd_configs\|plugin.Open\|LoadPlugin\|ExternalSDConfig' "$REPO" --include=*.go 2>/dev/null)"
if [ -n "$PLUGIN_TRAP" ]; then
  SUSPICIOUS=1
  REASONS+=("possible bespoke external/plugin SD abstraction found: $(echo "$PLUGIN_TRAP" | head -5 | tr '\n' ' | ')")
fi

# Signal 4: positive confirmation that scaleway_sd_configs is wired as a first-class
# key parsed directly by lib/promscrape (mirrors AC1-AC3). If this is true AND no
# suspicious signals were found, we can confidently PASS instead of punting to manual
# review.
FIRSTCLASS=0
if [ -f "$REPO/lib/promscrape/scraper.go" ] && grep -q 'scs.add("scaleway_sd_configs"' "$REPO/lib/promscrape/scraper.go" 2>/dev/null \
   && [ -d "$REPO/lib/promscrape/discovery/scaleway" ]; then
  FIRSTCLASS=1
fi

if [ "$SUSPICIOUS" -eq 0 ] && [ "$FIRSTCLASS" -eq 1 ]; then
  echo "PASS: scaleway_sd_configs appears first-class (scs.add registration + discovery/scaleway package present), no suspicious app/-level or file_sd/plugin workaround patterns found"
  exit 0
fi

if [ "$SUSPICIOUS" -eq 1 ] && [ "$FIRSTCLASS" -eq 0 ]; then
  echo "FAIL: workaround/parallel-mechanism signals found and no first-class scaleway_sd_configs wiring detected: ${REASONS[*]}"
  exit 1
fi

echo "MANUAL REVIEW REQUIRED: automated signals inconclusive (suspicious=$SUSPICIOUS, first_class_wiring=$FIRSTCLASS). Reasons: ${REASONS[*]:-none}. Manually inspect the diff and any new docs to confirm scaleway_sd_configs is parsed directly by lib/promscrape rather than documented/implemented as an external poller or new generic plugin mechanism."
exit 2
