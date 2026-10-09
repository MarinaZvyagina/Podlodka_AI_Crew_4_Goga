# Extended Study Statistical Analysis — B″ and C vs. Primary Baseline

Formal paired comparison of Condition B″ (Goga Forced Workflow, 400/400 valid) and Condition C (Goga-Native Architecture, 400/400 valid) against the primary study's Condition A (Baseline) cells for the same (repository, task), using the identical methodology as `results/PHASE13_STATISTICAL_ANALYSIS.md`: paired Wilcoxon signed-rank (zero_method='pratt'), paired t-test, exact sign test, percentile bootstrap 95% CI on the 40 cell-level deltas (n=40 paired cells each, 10 repetitions per cell, never pseudoreplicated), and cluster-robust GEE logistic regression at the run level (clustered by task cell). Condition B′ is excluded (stopped by design at 91/400 with uneven, often-zero repetitions per cell -- see `report/final_report.md` §11 for its pooled descriptive numbers instead).

**This is a separate test from the primary A-vs-B comparison, not a pooling of data into it**, per `TREATMENT_DESIGN_EXPERIMENT_B.md` §3's explicit non-pooling rule. Each extended condition mixes multiple confounded changes at once (tooling access, prompt instruction, and/or actual codebase restructuring, on top of the same CODEMANIFEST format change Condition B already tested) -- a significant result here shows *that* something changed relative to no-Goga-at-all, not *which* ingredient of that condition caused it.

## Condition B″ (Goga Forced Workflow)

#### Functional Success Rate

Baseline mean: 0.4700  |  Extended-condition mean: 0.2325  |  Mean delta: -0.2375 (95% bootstrap CI [-0.3275, -0.1500])
Direction: condition > Baseline in 1/40, condition < Baseline in 22/40, tied in 17/40.
Wilcoxon signed-rank (pratt): W=23.00, p=0.0000
Paired t-test: t(39)=-5.138, p=0.0000
Exact sign test (excludes ties): 22/23 favor Baseline (condition<Baseline), p=0.0000

GEE logistic regression (cluster-robust by cell, `functional_success ~ condition`): OR(Condition B″ (Goga Forced Workflow) vs Baseline) = 0.342 (95% CI [0.237, 0.492]), Wald p = 0.0000

#### Full Architecture Conformance Rate

Baseline mean: 0.2975  |  Extended-condition mean: 0.1200  |  Mean delta: -0.1775 (95% bootstrap CI [-0.2725, -0.0925])
Direction: condition > Baseline in 2/40, condition < Baseline in 15/40, tied in 23/40.
Wilcoxon signed-rank (pratt): W=53.00, p=0.0010
Paired t-test: t(39)=-3.764, p=0.0006
Exact sign test (excludes ties): 15/17 favor Baseline (condition<Baseline), p=0.0023

GEE logistic regression (cluster-robust by cell, `full_architecture_conformance ~ condition`): OR(Condition B″ (Goga Forced Workflow) vs Baseline) = 0.322 (95% CI [0.184, 0.562]), Wald p = 0.0001

#### Dangerous Success Rate (lower = better)

Baseline mean: 0.2900  |  Extended-condition mean: 0.1675  |  Mean delta: -0.1225 (95% bootstrap CI [-0.1975, -0.0525])
Direction: condition > Baseline in 3/40, condition < Baseline in 17/40, tied in 20/40.
Wilcoxon signed-rank (pratt): W=89.00, p=0.0018
Paired t-test: t(39)=-3.255, p=0.0023
Exact sign test (excludes ties): 17/20 favor Baseline (condition<Baseline), p=0.0026

GEE logistic regression (cluster-robust by cell, `dangerous_success ~ condition`): OR(Condition B″ (Goga Forced Workflow) vs Baseline) = 0.493 (95% CI [0.331, 0.734]), Wald p = 0.0005


## Condition C (Goga-Native Architecture)

#### Functional Success Rate

Baseline mean: 0.4700  |  Extended-condition mean: 0.3675  |  Mean delta: -0.1025 (95% bootstrap CI [-0.1625, -0.0500])
Direction: condition > Baseline in 3/40, condition < Baseline in 17/40, tied in 20/40.
Wilcoxon signed-rank (pratt): W=80.00, p=0.0012
Paired t-test: t(39)=-3.485, p=0.0012
Exact sign test (excludes ties): 17/20 favor Baseline (condition<Baseline), p=0.0026

GEE logistic regression (cluster-robust by cell, `functional_success ~ condition`): OR(Condition C (Goga-Native Architecture) vs Baseline) = 0.655 (95% CI [0.521, 0.823]), Wald p = 0.0003

#### Full Architecture Conformance Rate

Baseline mean: 0.2975  |  Extended-condition mean: 0.1950  |  Mean delta: -0.1025 (95% bootstrap CI [-0.1825, -0.0350])
Direction: condition > Baseline in 3/40, condition < Baseline in 13/40, tied in 24/40.
Wilcoxon signed-rank (pratt): W=90.50, p=0.0098
Paired t-test: t(39)=-2.652, p=0.0115
Exact sign test (excludes ties): 13/16 favor Baseline (condition<Baseline), p=0.0213

GEE logistic regression (cluster-robust by cell, `full_architecture_conformance ~ condition`): OR(Condition C (Goga-Native Architecture) vs Baseline) = 0.572 (95% CI [0.390, 0.838]), Wald p = 0.0041

#### Dangerous Success Rate (lower = better)

Baseline mean: 0.2900  |  Extended-condition mean: 0.2425  |  Mean delta: -0.0475 (95% bootstrap CI [-0.1000, +0.0025])
Direction: condition > Baseline in 5/40, condition < Baseline in 12/40, tied in 23/40.
Wilcoxon signed-rank (pratt): W=159.00, p=0.0903
Paired t-test: t(39)=-1.805, p=0.0787
Exact sign test (excludes ties): 12/17 favor Baseline (condition<Baseline), p=0.1435

GEE logistic regression (cluster-robust by cell, `dangerous_success ~ condition`): OR(Condition C (Goga-Native Architecture) vs Baseline) = 0.784 (95% CI [0.606, 1.014]), Wald p = 0.0641

