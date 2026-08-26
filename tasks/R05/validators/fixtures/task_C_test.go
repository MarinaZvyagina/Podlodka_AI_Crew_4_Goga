// Functional validator fixture for R05-TC (Scaleway service-discovery backend).
//
// This file is copied by task_C_functional.sh into <repo>/lib/promscrape/ before running
// `go test`, and removed again afterward. It is an EXTERNAL test package (promscrape_test)
// so it only exercises promscrape's public API: the -promscrape.config flag plus
// promscrape.CheckConfig(), which is the exact same config-loading path used by
// -promscrape.config.dryRun in every binary that imports lib/promscrape (app/vmagent,
// app/victoria-metrics, ...). This does not assume any internal type/function names from
// a candidate's own discovery/scaleway package - only that `scaleway_sd_configs` becomes a
// first-class, strictly-parsed key inside `scrape_configs`, per the ticket's explicit
// requirement that it work "the same way they already configure discovery for the cloud
// providers we support today".
package promscrape_test

import (
	"flag"
	"os"
	"path/filepath"
	"testing"

	"github.com/VictoriaMetrics/VictoriaMetrics/lib/promscrape"
)

func TestFunctional_ScalewaySDConfigsIsFirstClass(t *testing.T) {
	const flagName = "promscrape.config"
	fl := flag.Lookup(flagName)
	if fl == nil {
		t.Fatalf("FAIL: -%s flag not found in lib/promscrape - has the package's flag registration changed?", flagName)
	}
	origVal := fl.Value.String()
	defer func() {
		if err := flag.Set(flagName, origVal); err != nil {
			t.Logf("warning: could not restore -%s to %q: %s", flagName, origVal, err)
		}
	}()

	writeConfig := func(t *testing.T, data string) string {
		t.Helper()
		dir := t.TempDir()
		path := filepath.Join(dir, "scrape.yml")
		if err := os.WriteFile(path, []byte(data), 0o644); err != nil {
			t.Fatalf("cannot write temp config: %s", err)
		}
		return path
	}

	// Environment sanity check: an unrelated, always-valid config must load fine, so that a
	// failure below can be attributed to scaleway_sd_configs specifically rather than to some
	// unrelated config-loading problem.
	sanityPath := writeConfig(t, "scrape_configs:\n- job_name: sanity\n  static_configs:\n  - targets: [\"127.0.0.1:9100\"]\n")
	if err := flag.Set(flagName, sanityPath); err != nil {
		t.Fatalf("cannot set -%s: %s", flagName, err)
	}
	if err := promscrape.CheckConfig(); err != nil {
		t.Fatalf("FAIL (environment sanity check): a scrape config with no scaleway_sd_configs at all failed to load: %s", err)
	}

	// The actual functional check: a scrape_configs entry with a minimal scaleway_sd_configs
	// block must be accepted (not rejected as an unknown field) by strict config parsing.
	scalewayPath := writeConfig(t, "scrape_configs:\n- job_name: scaleway_probe\n  scaleway_sd_configs:\n  - {}\n")
	if err := flag.Set(flagName, scalewayPath); err != nil {
		t.Fatalf("cannot set -%s: %s", flagName, err)
	}
	if err := promscrape.CheckConfig(); err != nil {
		t.Fatalf("FUNCTIONAL FAIL: a scrape_configs entry with a `scaleway_sd_configs` block was "+
			"rejected by promscrape.CheckConfig (the same config-loading path used by "+
			"-promscrape.config.dryRun in every VictoriaMetrics binary): %s", err)
	}

	// A slightly richer block (bearer_token, following the same promauth.HTTPClientConfig
	// inline convention every other cloud backend uses for API tokens) should also be
	// accepted. This is best-effort/informational: the ticket does not fix the exact field
	// name for the auth token, so a failure here is logged but does not fail the test on its
	// own - the primary assertion above already confirms scaleway_sd_configs is first-class.
	richPath := writeConfig(t, "scrape_configs:\n- job_name: scaleway_probe2\n  scaleway_sd_configs:\n  - bearer_token: \"test-token\"\n"+
		"    proxy_url: \"http://proxy.example.com:8080\"\n")
	if err := flag.Set(flagName, richPath); err != nil {
		t.Fatalf("cannot set -%s: %s", flagName, err)
	}
	if err := promscrape.CheckConfig(); err != nil {
		t.Logf("informational: a scaleway_sd_configs block with bearer_token/proxy_url failed to "+
			"parse (%s); this does not fail the test since the ticket does not mandate these exact "+
			"field names, but it is worth a human double-checking the auth/proxy field naming", err)
	}
}
