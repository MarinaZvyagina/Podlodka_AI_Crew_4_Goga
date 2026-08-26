# Harness dry-run — excluded from the main 800-run sample

`R03-TC-G-07` here was the first real, live end-to-end test of the Phase 10 execution
harness (`scripts/execute_run.py`), run to validate the pipeline before scaling up.
It surfaced 4 real harness bugs (see `PROTOCOL.md` Amendment 3), which were fixed
*after* this run completed — so this run's recorded metrics were computed with
now-superseded, buggy validator-parsing logic and do not reflect the corrected
harness's behavior. It is preserved here for provenance/transparency, but excluded
from `results/runs.csv` and the official 800-run sample. Run number 3 in
`experiment_plan.csv` will be executed for real, with the fixed harness, as part of
the main batch.
