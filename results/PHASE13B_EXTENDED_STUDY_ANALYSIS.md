# Extended Study Statistical Analysis — B″ and C vs. Primary Baseline

Formal paired comparison of Condition B″ (Goga Forced Workflow, 400/400 valid) and Condition C (Goga-Native Architecture, 400/400 valid) against the primary study's Condition A (Baseline) cells for the same (repository, task), using the identical methodology as `results/PHASE13_STATISTICAL_ANALYSIS.md`: paired Wilcoxon signed-rank (zero_method='pratt'), paired t-test, exact sign test, percentile bootstrap 95% CI on the 40 cell-level deltas (n=40 paired cells each, 10 repetitions per cell, never pseudoreplicated), and cluster-robust GEE logistic regression at the run level (clustered by task cell). Condition B′ is excluded (stopped by design at 91/400 with uneven, often-zero repetitions per cell -- see `report/final_report.md` §11 for its pooled descriptive numbers instead).

**This is a separate test from the primary A-vs-B comparison, not a pooling of data into it**, per `TREATMENT_DESIGN_EXPERIMENT_B.md` §3's explicit non-pooling rule. Each extended condition mixes multiple confounded changes at once (tooling access, prompt instruction, and/or actual codebase restructuring, on top of the same CODEMANIFEST format change Condition B already tested) -- a significant result here shows *that* something changed relative to no-Goga-at-all, not *which* ingredient of that condition caused it.

## Condition B″ (Goga Forced Workflow)

#### Functional Success Rate

Baseline mean: 0.4800  |  Extended-condition mean: 0.2325  |  Mean delta: -0.2475 (95% bootstrap CI [-0.3375, -0.1600])
Direction: condition > Baseline in 1/40, condition < Baseline in 23/40, tied in 16/40.
Wilcoxon signed-rank (pratt): W=22.00, p=0.0000
Paired t-test: t(39)=-5.381, p=0.0000
Exact sign test (excludes ties): 23/24 favor Baseline (condition<Baseline), p=0.0000

GEE logistic regression (cluster-robust by cell, `functional_success ~ condition`): OR(Condition B″ (Goga Forced Workflow) vs Baseline) = 0.328 (95% CI [0.227, 0.474]), Wald p = 0.0000

#### Full Architecture Conformance Rate

Baseline mean: 0.2975  |  Extended-condition mean: 0.1200  |  Mean delta: -0.1775 (95% bootstrap CI [-0.2725, -0.0925])
Direction: condition > Baseline in 2/40, condition < Baseline in 15/40, tied in 23/40.
Wilcoxon signed-rank (pratt): W=53.00, p=0.0010
Paired t-test: t(39)=-3.764, p=0.0006
Exact sign test (excludes ties): 15/17 favor Baseline (condition<Baseline), p=0.0023

GEE logistic regression (cluster-robust by cell, `full_architecture_conformance ~ condition`): OR(Condition B″ (Goga Forced Workflow) vs Baseline) = 0.322 (95% CI [0.184, 0.562]), Wald p = 0.0001

#### Dangerous Success Rate (lower = better)

Baseline mean: 0.2925  |  Extended-condition mean: 0.1675  |  Mean delta: -0.1250 (95% bootstrap CI [-0.2000, -0.0550])
Direction: condition > Baseline in 3/40, condition < Baseline in 18/40, tied in 19/40.
Wilcoxon signed-rank (pratt): W=88.50, p=0.0012
Paired t-test: t(39)=-3.332, p=0.0019
Exact sign test (excludes ties): 18/21 favor Baseline (condition<Baseline), p=0.0015

GEE logistic regression (cluster-robust by cell, `dangerous_success ~ condition`): OR(Condition B″ (Goga Forced Workflow) vs Baseline) = 0.487 (95% CI [0.327, 0.725]), Wald p = 0.0004


## Condition C (Goga-Native Architecture)

#### Functional Success Rate

Baseline mean: 0.4800  |  Extended-condition mean: 0.3675  |  Mean delta: -0.1125 (95% bootstrap CI [-0.1750, -0.0575])
Direction: condition > Baseline in 3/40, condition < Baseline in 18/40, tied in 19/40.
Wilcoxon signed-rank (pratt): W=77.00, p=0.0007
Paired t-test: t(39)=-3.724, p=0.0006
Exact sign test (excludes ties): 18/21 favor Baseline (condition<Baseline), p=0.0015

GEE logistic regression (cluster-robust by cell, `functional_success ~ condition`): OR(Condition C (Goga-Native Architecture) vs Baseline) = 0.629 (95% CI [0.497, 0.797]), Wald p = 0.0001

#### Full Architecture Conformance Rate

Baseline mean: 0.2975  |  Extended-condition mean: 0.1950  |  Mean delta: -0.1025 (95% bootstrap CI [-0.1825, -0.0350])
Direction: condition > Baseline in 3/40, condition < Baseline in 13/40, tied in 24/40.
Wilcoxon signed-rank (pratt): W=90.50, p=0.0098
Paired t-test: t(39)=-2.652, p=0.0115
Exact sign test (excludes ties): 13/16 favor Baseline (condition<Baseline), p=0.0213

GEE logistic regression (cluster-robust by cell, `full_architecture_conformance ~ condition`): OR(Condition C (Goga-Native Architecture) vs Baseline) = 0.572 (95% CI [0.390, 0.838]), Wald p = 0.0041

#### Dangerous Success Rate (lower = better)

Baseline mean: 0.2925  |  Extended-condition mean: 0.2425  |  Mean delta: -0.0500 (95% bootstrap CI [-0.1025, +0.0000])
Direction: condition > Baseline in 5/40, condition < Baseline in 13/40, tied in 22/40.
Wilcoxon signed-rank (pratt): W=157.50, p=0.0627
Paired t-test: t(39)=-1.900, p=0.0648
Exact sign test (excludes ties): 13/18 favor Baseline (condition<Baseline), p=0.0963

GEE logistic regression (cluster-robust by cell, `dangerous_success ~ condition`): OR(Condition C (Goga-Native Architecture) vs Baseline) = 0.774 (95% CI [0.598, 1.002]), Wald p = 0.0522

