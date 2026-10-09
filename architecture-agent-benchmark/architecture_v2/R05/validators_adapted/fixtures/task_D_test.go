// Functional validator fixture for R05-TD (per-metric-name drop tracking).
//
// This file is copied by task_D_functional.sh into <repo>/lib/storage/ before running
// `go test`, and removed again afterward. It is an INTERNAL test file (package storage).
//
// The ticket explicitly leaves the query API's "exact shape... up to you", so unlike tasks
// A/B/C there is no single guaranteed exported symbol name to call. Instead, this test:
//  1. Uses reflection to enable any NEW (non-baseline) boolean OpenOptions field, so it does
//     not need to guess the toggle's name (e.g. TrackDroppedSeries).
//  2. Induces drops for many distinct, uniquely-prefixed metric names via the pre-existing,
//     unmodified MustOpenStorage/AddRows/DebugFlush/UpdateMetrics production entry points.
//  3. Uses reflection to find any NEW (non-baseline) exported *Storage method - regardless of
//     its name or exact signature - whose return value, when walked recursively, contains a
//     metric name we injected paired with a positive drop count. That is the query API the
//     ticket requires, whatever a given implementation chose to call it.
//
// This approach only assumes the exported baseline API surface of lib/storage.Storage /
// lib/storage.OpenOptions at the pinned commit (hardcoded below) - not any candidate's own
// naming choices.
package storage

import (
	"math/rand"
	"reflect"
	"strings"
	"testing"
	"time"
)

// baselineStorageMethods lists every exported *Storage method that already existed at the
// pinned commit f65ae841ace8f686ddc0dc17fe936d0bf38e568c, before any R05-TD implementation.
var baselineStorageMethods = map[string]bool{
	"AddMetadataRows":          true,
	"AddRows":                  true,
	"DebugFlush":               true,
	"DeleteSeries":             true,
	"DeleteSnapshot":           true,
	"ForceMergePartitions":     true,
	"GetMetadataRows":          true,
	"GetMetricNamesStats":      true,
	"GetSeriesCount":           true,
	"GetTSDBStatus":            true,
	"IsReadOnly":               true,
	"MustClose":                true,
	"MustCreateSnapshot":       true,
	"MustDeleteStaleSnapshots": true,
	"MustListSnapshots":        true,
	"RegisterMetricNames":      true,
	"ResetMetricNamesStats":    true,
	"SearchGraphitePaths":      true,
	"SearchLabelNames":         true,
	"SearchLabelValues":        true,
	"SearchMetricNames":        true,
	"SearchTSIDs":              true,
	"SearchTagValueSuffixes":   true,
	"SetLogNewSeriesUntil":     true,
	"UpdateMetrics":            true,
}

// baselineOpenOptionsFields lists every OpenOptions field that already existed at the
// pinned commit, before any R05-TD implementation.
var baselineOpenOptionsFields = map[string]bool{
	"Retention":                   true,
	"FutureRetention":             true,
	"MaxBackfillAge":              true,
	"DenyQueriesOutsideRetention": true,
	"MaxHourlySeries":             true,
	"MaxDailySeries":              true,
	"DisablePerDayIndex":          true,
	"TrackMetricNamesStats":       true,
	"IDBPrefillStart":             true,
	"LogNewSeries":                true,
}

// buildOptsWithNewTogglesEnabled builds an OpenOptions value with maxHourlySeries set, plus
// every NEW (non-baseline) boolean field forced to true, so that whatever toggle a candidate
// added to opt into per-metric-name drop tracking gets enabled without needing to know its
// name.
func buildOptsWithNewTogglesEnabled(maxHourlySeries int) OpenOptions {
	opts := OpenOptions{MaxHourlySeries: maxHourlySeries}
	ov := reflect.ValueOf(&opts).Elem()
	ot := ov.Type()
	for i := 0; i < ot.NumField(); i++ {
		ft := ot.Field(i)
		if baselineOpenOptionsFields[ft.Name] {
			continue
		}
		fv := ov.Field(i)
		if fv.Kind() == reflect.Bool {
			fv.SetBool(true)
		}
		// Leave any new numeric bound field at its zero value, so the implementation's own
		// "sensible fixed default" (if any) is what gets exercised.
	}
	return opts
}

// newStorageMethodNames returns the names of all exported *Storage methods that are not part
// of the pre-existing baseline API.
func newStorageMethodNames(st reflect.Type) []string {
	var names []string
	for i := 0; i < st.NumMethod(); i++ {
		name := st.Method(i).Name
		if !baselineStorageMethods[name] {
			names = append(names, name)
		}
	}
	return names
}

// makeIntLike builds an addressable reflect.Value of type pt (assumed to be some int/uint
// kind) holding the given value.
func makeIntLike(pt reflect.Type, val int64) reflect.Value {
	rv := reflect.New(pt).Elem()
	switch rv.Kind() {
	case reflect.Int, reflect.Int8, reflect.Int16, reflect.Int32, reflect.Int64:
		rv.SetInt(val)
	case reflect.Uint, reflect.Uint8, reflect.Uint16, reflect.Uint32, reflect.Uint64:
		rv.SetUint(uint64(val))
	}
	return rv
}

// buildArgVariants builds a handful of plausible argument lists for a method with the given
// signature, without assuming which candidate-specific parameter shape (e.g.
// (*querytracer.Tracer, int) vs (int) vs ()) was chosen.
func buildArgVariants(mt reflect.Type) [][]reflect.Value {
	n := mt.NumIn()
	if n == 0 {
		return [][]reflect.Value{{}}
	}
	var variants [][]reflect.Value
	for _, limit := range []int64{1000, 0} {
		args := make([]reflect.Value, n)
		for i := 0; i < n; i++ {
			pt := mt.In(i)
			switch pt.Kind() {
			case reflect.Int, reflect.Int8, reflect.Int16, reflect.Int32, reflect.Int64,
				reflect.Uint, reflect.Uint8, reflect.Uint16, reflect.Uint32, reflect.Uint64:
				args[i] = makeIntLike(pt, limit)
			case reflect.Bool:
				args[i] = reflect.ValueOf(true)
			default:
				// Pointers, interfaces, maps, slices, strings, structs, etc: zero value
				// (e.g. a nil *querytracer.Tracer, which every querytracer-consuming method
				// in this codebase already treats as "no tracing").
				args[i] = reflect.Zero(pt)
			}
		}
		variants = append(variants, args)
	}
	return variants
}

// extractPositiveNumber returns (value, true) if v is a numeric kind holding a value > 0.
func extractPositiveNumber(v reflect.Value) (uint64, bool) {
	switch v.Kind() {
	case reflect.Int, reflect.Int8, reflect.Int16, reflect.Int32, reflect.Int64:
		if v.Int() > 0 {
			return uint64(v.Int()), true
		}
	case reflect.Uint, reflect.Uint8, reflect.Uint16, reflect.Uint32, reflect.Uint64, reflect.Uintptr:
		if v.Uint() > 0 {
			return v.Uint(), true
		}
	case reflect.Float32, reflect.Float64:
		if v.Float() > 0 {
			return uint64(v.Float()), true
		}
	}
	return 0, false
}

// scanForDropEvidence recursively walks v looking for a container (struct fields, or a
// map[string]<number>-style entry) that pairs a string containing the given prefix with a
// positive numeric value - i.e. "this metric name had this many drops", however the
// implementation chose to shape/name that result.
func scanForDropEvidence(v reflect.Value, prefix string, depth int) (name string, count uint64, ok bool) {
	if depth > 8 || !v.IsValid() {
		return "", 0, false
	}
	switch v.Kind() {
	case reflect.Ptr, reflect.Interface:
		if v.IsNil() {
			return "", 0, false
		}
		return scanForDropEvidence(v.Elem(), prefix, depth+1)
	case reflect.Slice, reflect.Array:
		for i := 0; i < v.Len(); i++ {
			if n, c, ok2 := scanForDropEvidence(v.Index(i), prefix, depth+1); ok2 {
				return n, c, true
			}
		}
	case reflect.Map:
		iter := v.MapRange()
		for iter.Next() {
			k := iter.Key()
			val := iter.Value()
			if k.Kind() == reflect.String && strings.Contains(k.String(), prefix) {
				if c, ok2 := extractPositiveNumber(val); ok2 {
					return k.String(), c, true
				}
			}
			if n, c, ok2 := scanForDropEvidence(val, prefix, depth+1); ok2 {
				return n, c, true
			}
		}
	case reflect.Struct:
		var nameCandidate string
		var countCandidate uint64
		var haveName, haveCount bool
		for i := 0; i < v.NumField(); i++ {
			ft := v.Type().Field(i)
			if ft.PkgPath != "" {
				continue // unexported field
			}
			fv := v.Field(i)
			if fv.Kind() == reflect.String && strings.Contains(fv.String(), prefix) {
				nameCandidate = fv.String()
				haveName = true
			}
			if c, ok2 := extractPositiveNumber(fv); ok2 {
				countCandidate = c
				haveCount = true
			}
		}
		if haveName && haveCount {
			return nameCandidate, countCandidate, true
		}
		for i := 0; i < v.NumField(); i++ {
			ft := v.Type().Field(i)
			if ft.PkgPath != "" {
				continue
			}
			if n, c, ok2 := scanForDropEvidence(v.Field(i), prefix, depth+1); ok2 {
				return n, c, true
			}
		}
	}
	return "", 0, false
}

// tryInvokeAndScan calls the named zero-or-more-argument, at-least-one-return-value method on
// s with a few plausible argument shapes, and reports whether any resulting return value
// contains drop evidence for a metric name containing prefix.
func tryInvokeAndScan(s *Storage, methodName string, prefix string) (bool, string) {
	mv := reflect.ValueOf(s).MethodByName(methodName)
	if !mv.IsValid() {
		return false, ""
	}
	mt := mv.Type()
	if mt.NumOut() == 0 {
		// Zero-output methods are almost certainly mutators (e.g. a Reset-style call) rather
		// than the query API we're looking for; skip invoking them so we don't risk
		// clobbering tracked state before the real getter is tried.
		return false, ""
	}
	for _, args := range buildArgVariants(mt) {
		var outs []reflect.Value
		panicked := false
		func() {
			defer func() {
				if r := recover(); r != nil {
					panicked = true
				}
			}()
			outs = mv.Call(args)
		}()
		if panicked {
			continue
		}
		for _, out := range outs {
			if name, cnt, ok := scanForDropEvidence(out, prefix, 0); ok && cnt > 0 {
				return true, name
			}
		}
	}
	return false, ""
}

func TestFunctional_PerMetricNameDropTracking(t *testing.T) {
	defer testRemoveAll(t)

	const (
		maxHourlySeries = 5
		numRows         = 3000
		prefix          = "zzzdropstatsprobe"
	)

	opts := buildOptsWithNewTogglesEnabled(maxHourlySeries)
	s := MustOpenStorage(t.Name(), opts)
	defer s.MustClose()

	rng := rand.New(rand.NewSource(1))
	minTimestamp := time.Now().UnixMilli()
	maxTimestamp := minTimestamp + 1000
	mrs := testGenerateMetricRowsWithPrefix(rng, numRows, prefix, TimeRange{MinTimestamp: minTimestamp, MaxTimestamp: maxTimestamp})
	s.AddRows(mrs, defaultPrecisionBits)
	s.DebugFlush()

	var m Metrics
	s.UpdateMetrics(&m)
	if m.HourlySeriesLimitRowsDropped == 0 {
		t.Fatalf("test setup problem (not the feature under test): expected some rows to be "+
			"dropped due to MaxHourlySeries=%d while ingesting %d distinct metric names, got "+
			"HourlySeriesLimitRowsDropped=0", maxHourlySeries, numRows)
	}

	st := reflect.TypeOf(s)
	newMethods := newStorageMethodNames(st)

	var foundMethod, foundName string
	found := false
	for _, name := range newMethods {
		if ok, matched := tryInvokeAndScan(s, name, prefix); ok {
			found = true
			foundMethod = name
			foundName = matched
			break
		}
	}

	if !found {
		t.Fatalf("FUNCTIONAL FAIL: after inducing drops for %d distinct metric names (all "+
			"prefixed %q) under -storage.maxHourlySeries=%d, no newly-added exported *Storage "+
			"method could be found whose return value reports a per-metric-name drop count for "+
			"any of them. Exported *Storage methods beyond the pre-existing baseline API that "+
			"were tried: %v", numRows, prefix, maxHourlySeries, newMethods)
	}
	t.Logf("found per-metric-name drop query method: Storage.%s (matched metric name %q)", foundMethod, foundName)
}
