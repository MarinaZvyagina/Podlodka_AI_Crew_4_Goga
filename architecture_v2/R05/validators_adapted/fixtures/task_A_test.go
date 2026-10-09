// Functional validator fixture for R05-TA (relabeling `trim` action).
//
// This file is copied by task_A_functional.sh into <repo>/lib/promrelabel/ before running
// `go test`, and removed again afterward. It is intentionally an EXTERNAL test package
// (promrelabel_test) so it only exercises promrelabel's public API - the same API any
// scrape-time (relabel_configs) or remote-write relabeling consumer necessarily goes
// through - rather than any internal helper specific to one candidate implementation.
package promrelabel_test

import (
	"testing"

	"github.com/VictoriaMetrics/VictoriaMetrics/lib/promrelabel"
	"github.com/VictoriaMetrics/VictoriaMetrics/lib/promutil"
)

// TestFunctional_TrimRelabelAction is a black-box functional check for ticket R05-TA:
// "Support trimming whitespace from label values during relabeling".
//
// It does not assume which of the two action names the ticket allows ("trim" or
// "trim_space") a given implementation chose - it tries both and uses whichever one
// lib/promrelabel actually accepts.
func TestFunctional_TrimRelabelAction(t *testing.T) {
	tryAction := func(action string) (*promrelabel.ParsedConfigs, error) {
		config := "- action: " + action + "\n  source_labels: [\"foo\"]\n  target_label: foo\n"
		return promrelabel.ParseRelabelConfigsData([]byte(config))
	}

	var pcs *promrelabel.ParsedConfigs
	var lastErr error
	usedAction := ""
	for _, action := range []string{"trim", "trim_space"} {
		p, err := tryAction(action)
		if err == nil {
			pcs = p
			usedAction = action
			break
		}
		lastErr = err
	}
	if pcs == nil {
		t.Fatalf("FUNCTIONAL FAIL: neither `action: trim` nor `action: trim_space` is accepted "+
			"by lib/promrelabel.ParseRelabelConfigsData - the ticket requires a new relabel_configs "+
			"action reachable through this exact public API (shared by scrape-time and remote-write "+
			"relabeling); last parse error: %s", lastErr)
	}

	// Case 1: single source_label, leading/trailing whitespace must be trimmed.
	labels := promutil.MustNewLabelsFromString(`{foo="   bar   "}`)
	result := pcs.Apply(labels.GetLabels(), 0)
	promrelabel.SortLabels(result)
	if got, want := promrelabel.LabelsToString(result), `{foo="bar"}`; got != want {
		t.Fatalf("FUNCTIONAL FAIL: action=%s did not trim whitespace as expected; got %s, want %s", usedAction, got, want)
	}

	// Case 2: multiple source_labels concatenated with the default separator, mirroring how
	// `uppercase`/`lowercase` already combine source_labels before transforming the value.
	labels2 := promutil.MustNewLabelsFromString(`{foo=" BaR ",bar=" fOO"}`)
	config2 := "- action: " + usedAction + "\n  source_labels: [\"foo\", \"bar\"]\n  target_label: baz\n"
	pcs2, err := promrelabel.ParseRelabelConfigsData([]byte(config2))
	if err != nil {
		t.Fatalf("FUNCTIONAL FAIL: action=%s failed to parse with multiple source_labels: %s", usedAction, err)
	}
	result2 := pcs2.Apply(labels2.GetLabels(), 0)
	promrelabel.SortLabels(result2)
	if got, want := promrelabel.LabelsToString(result2), `{bar=" fOO",baz="BaR ; fOO",foo=" BaR "}`; got != want {
		t.Fatalf("FUNCTIONAL FAIL: action=%s multi-source-label concatenation+trim mismatch; got %s, want %s", usedAction, got, want)
	}

	// Case 3: config validation must reject the action at load time (not just at runtime)
	// when target_label is missing, consistent with how uppercase/lowercase are validated.
	badConfig := "- action: " + usedAction + "\n  source_labels: [\"foo\"]\n"
	if _, err := promrelabel.ParseRelabelConfigsData([]byte(badConfig)); err == nil {
		t.Fatalf("FUNCTIONAL FAIL: action=%s config with missing target_label must be rejected at "+
			"load time by ParseRelabelConfigsData, but no error was returned", usedAction)
	}

	// Case 4: same for missing source_labels.
	badConfig2 := "- action: " + usedAction + "\n  target_label: foo\n"
	if _, err := promrelabel.ParseRelabelConfigsData([]byte(badConfig2)); err == nil {
		t.Fatalf("FUNCTIONAL FAIL: action=%s config with missing source_labels must be rejected at "+
			"load time by ParseRelabelConfigsData, but no error was returned", usedAction)
	}
}
