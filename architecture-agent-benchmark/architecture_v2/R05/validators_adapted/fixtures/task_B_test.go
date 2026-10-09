// Functional validator fixture for R05-TB (per-job max-scrape-targets cap).
//
// This file is copied by task_B_functional.sh into <repo>/lib/promscrape/ before running
// `go test`, and removed again afterward. It is an INTERNAL test file (package promscrape)
// because there is no single exported function that drives config-loading all the way to
// scrape-work assembly - but every symbol it touches beyond the discovered flag itself
// (Config.parseData, Config.getStaticScrapeWork, droppedTargetsMap, WriteAPIV1Targets) is
// pre-existing, shared production code that predates any candidate's change, not an
// internal helper invented by one specific implementation.
//
// The one genuinely implementation-chosen name - the new -promscrape.* flag controlling the
// per-job_name target cap - is discovered dynamically by name pattern instead of being
// hardcoded, so this test does not depend on a candidate having picked exactly
// "-promscrape.maxTargetsPerJob".
package promscrape

import (
	"bytes"
	"flag"
	"fmt"
	"regexp"
	"strconv"
	"strings"
	"testing"
)

// findMaxTargetsPerJobFlag locates the -promscrape.* flag that implements the per-job_name
// target cap required by ticket R05-TB. The ticket requires a "global default" that applies
// "regardless of discovery mechanism", and the architecture constraints require it to live
// in lib/promscrape and follow the existing descriptive flag-naming convention (e.g.
// -promscrape.maxScrapeSize, -promscrape.seriesLimitPerTarget) - so any correct
// implementation is expected to register a flag under -promscrape. whose name mentions both
// "target" and "job".
func findMaxTargetsPerJobFlag(t *testing.T) *flag.Flag {
	t.Helper()
	nameRe := regexp.MustCompile(`(?i)^promscrape\..*target.*`)
	var candidates []*flag.Flag
	var allTargetFlags []string
	flag.VisitAll(func(f *flag.Flag) {
		if !nameRe.MatchString(f.Name) {
			return
		}
		allTargetFlags = append(allTargetFlags, f.Name)
		lname := strings.ToLower(f.Name)
		if strings.Contains(lname, "job") && (strings.Contains(lname, "max") || strings.Contains(lname, "limit")) {
			candidates = append(candidates, f)
		}
	})
	if len(candidates) == 0 {
		t.Fatalf("FUNCTIONAL FAIL: no -promscrape.* flag found whose name mentions a per-job target "+
			"cap (expected something like -promscrape.maxTargetsPerJob); -promscrape.* flags "+
			"mentioning \"target\" found: %v", allTargetFlags)
	}
	if len(candidates) > 1 {
		var names []string
		for _, f := range candidates {
			names = append(names, f.Name)
		}
		t.Logf("multiple candidate flags matched, using the first: %v", names)
	}
	return candidates[0]
}

func buildStaticConfigYAML(jobName string, n int) string {
	var sb strings.Builder
	fmt.Fprintf(&sb, "scrape_configs:\n- job_name: %s\n  static_configs:\n  - targets:\n", jobName)
	for i := 0; i < n; i++ {
		fmt.Fprintf(&sb, "    - \"10.77.55.%d:9100\"\n", i+1)
	}
	return sb.String()
}

func parseAndGetStaticSWs(t *testing.T, data string) []*ScrapeWork {
	t.Helper()
	var cfg Config
	if err := cfg.parseData([]byte(data), "task_B_functional_test.yml"); err != nil {
		t.Fatalf("cannot parse generated scrape config: %s", err)
	}
	return cfg.getStaticScrapeWork()
}

func countByJob(sws []*ScrapeWork, job string) int {
	n := 0
	for _, sw := range sws {
		if sw.jobNameOriginal == job {
			n++
		}
	}
	return n
}

func TestFunctional_MaxTargetsPerJob(t *testing.T) {
	fl := findMaxTargetsPerJobFlag(t)
	origVal := fl.Value.String()
	defer func() {
		if err := flag.Set(fl.Name, origVal); err != nil {
			t.Logf("warning: could not restore -%s to %q: %s", fl.Name, origVal, err)
		}
	}()

	// Reset the shared dropped-targets tracker so the counts asserted below are attributable
	// only to this test.
	droppedTargetsMap.mu.Lock()
	droppedTargetsMap.m = make(map[uint64]droppedTarget)
	droppedTargetsMap.totalTargets = 0
	droppedTargetsMap.mu.Unlock()

	const limit = 2
	if err := flag.Set(fl.Name, strconv.Itoa(limit)); err != nil {
		t.Fatalf("cannot set -%s=%d: %s", fl.Name, limit, err)
	}

	// Case 1: a job under the limit must be completely unaffected.
	underSWs := parseAndGetStaticSWs(t, buildStaticConfigYAML("b_under_job", 1))
	if got := countByJob(underSWs, "b_under_job"); got != 1 {
		t.Fatalf("FUNCTIONAL FAIL: job under the limit (1 target, limit=%d) should be unaffected; got %d scrape targets", limit, got)
	}

	// Case 2: a job over the limit must be truncated to exactly the limit - not dropped
	// entirely, and not left unbounded.
	const overCount = 5
	overSWs := parseAndGetStaticSWs(t, buildStaticConfigYAML("b_over_job", overCount))
	if got := countByJob(overSWs, "b_over_job"); got != limit {
		t.Fatalf("FUNCTIONAL FAIL: job over the limit (%d targets, limit=%d) must be truncated to "+
			"exactly %d scrape targets; got %d", overCount, limit, limit, got)
	}

	// The truncated/excluded targets must be visible via the EXISTING target-status surfaces:
	// droppedTargetsMap (backing both /targets and /api/v1/targets).
	wantDropped := overCount - limit
	if got := droppedTargetsMap.getTotalTargets(); got < wantDropped {
		t.Fatalf("FUNCTIONAL FAIL: expected at least %d dropped targets to be recorded in the "+
			"existing target-status tracking (droppedTargetsMap) after truncating job_name=b_over_job "+
			"to limit=%d, got %d", wantDropped, limit, got)
	}
	var buf bytes.Buffer
	WriteAPIV1Targets(&buf, "dropped", "")
	droppedJSON := buf.String()
	if addrCount := strings.Count(droppedJSON, "__address__"); addrCount < wantDropped {
		t.Fatalf("FUNCTIONAL FAIL: expected WriteAPIV1Targets(state=\"dropped\") to list at least %d "+
			"excluded targets, found %d occurrences of \"__address__\" in: %s", wantDropped, addrCount, droppedJSON)
	}

	// Case 3: default/unlimited behavior. Restore the flag to its documented default (the
	// ticket requires it to be off/unlimited by default) and confirm a job with more targets
	// than our test limit is fully scraped, i.e. existing setups are unaffected.
	if err := flag.Set(fl.Name, origVal); err != nil {
		t.Fatalf("cannot restore -%s to %q: %s", fl.Name, origVal, err)
	}
	defaultSWs := parseAndGetStaticSWs(t, buildStaticConfigYAML("b_default_job", overCount))
	if got := countByJob(defaultSWs, "b_default_job"); got != overCount {
		t.Fatalf("FUNCTIONAL FAIL: with the flag at its documented default (%q, expected "+
			"unlimited/off), a job with %d targets must not be truncated; got %d scrape targets",
			origVal, overCount, got)
	}
}
