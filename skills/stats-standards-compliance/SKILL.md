---
name: stats-standards-compliance
description: >-
  Assess whether an R package is likely to comply with enough of rOpenSci's
  Statistical Software peer review standards (stats-devguide.ropensci.org) to
  be accepted into review, and which category (Bayesian, regression, machine
  learning, EDA/summary stats, time series, spatial, dimensionality
  reduction/clustering, probability distributions) it best fits. Downloads
  the relevant General and category-specific standards, judges every
  individual standard against the package's actual source as met, unmet, or
  not-applicable, and writes a scored report to srr/standards-compliance.md.
  Use this before a package has done any formal srr compliance work, to
  estimate feasibility and pick a submission category. Scores conservatively
  as Y / (Y + N + NA) — not-applicable standards count against the
  proportion rather than being excluded, unlike rOpenSci's own official
  "applicable standards" convention — since at this early, pre-implementation
  stage NA calls are estimates rather than developer-asserted
  `@srrstatsNA` tags.
---

# rOpenSci Statistical Software Standards Compliance

## Step 1: Identify categories and download standards

Implement the following as an immediate first step, noting that all code is
`Rscript`:

1. Ensure that the `srr` R package is installed.
2. Identify category information from `srr::srr_stats_categories()`.
3. Clarify with the user which categories of statistical software are being
   considered. Do not proceed until categories have been explicitly
   identified. A package may plausibly fit one, two, or more categories;
   don't force it to exactly two. Ensure chosen categories match those listed
   in `srr_stats_categories()`, and keep a note of the exact category names
   chosen — Step 2 refers back to them.
4. Make a sub-directory, `srr/` in current repository.
5. For example categories "eda" and "ml", run
   `x <- srr::srr_stats_checklist(c("eda", "ml"))`. The result, `x`, which is
   also written to the system clipboard, is a checklist of all general and
   category-specific standards which should be written to
   `srr/srr-standards.md`.
6. Download the full text of _General_ standards from
   https://github.com/ropensci/statistical-software-review-book/raw/refs/heads/main/standards/general.Rmd
   and save to `srr/general.Rmd`.
7. Download equivalent category-specific standards into the `srr/` directory,
   one file per chosen category, by replacing `general` with each value given
   in the `category` column of `srr::srr_stats_categories()` (e.g.
   `srr/ml.Rmd`, `srr/regression.Rmd`, `srr/eda.Rmd`, ...).

## Step 2: Assess compliance

Your primary task here is to consider the following two questions:

1. Is the package in scope? The answer is entirely determined by whether the
   package is able to comply with at least 50% of applicable standards.
2. In which category does the package fit? The answer is entirely determined
   as the category in which the greatest proportion of standards are able to
   be met.

The standards are entirely documented within the `srr/` sub-directory. The
full standards texts are in `srr/general.Rmd` — the general standards which
**must** be complied with regardless of category — along with one
category-specific `srr/<category>.Rmd` file per category identified in Step
1. At least one category-specific set must be complied with, though
compliance with multiple categories is possible and should be reported if it
occurs. `srr/srr-standards.md` is the canonical checklist: use it to count
standards and enumerate individual standard IDs (e.g. `G1.0`, `ML3.2`,
`RE4.5`) — the prose `.Rmd` files are for reading the full standard text and
rationale, not for counting.

### Assessment methodology

Assess every standard's ID individually with one of three verdicts. Do not
skip this step or assess only at subsection granularity — proportions must be
computed from individual standard-level verdicts.

- **Y** — Already satisfied, or clearly achievable with reasonable additional
  engineering effort given the package's current architecture. Compliance
  must be assessed on *potential* compliance, not current-code compliance:
  if a suitable modification to the existing software could plausibly
  achieve it, mark `Y` even if nothing has been implemented yet. Note in
  your write-up which `Y` verdicts are already-done versus feasible-but-not-
  yet-done — this distinction matters to the reader even though both count
  identically toward the proportion.
- **N** — Would require a fundamentally new capability that conflicts with,
  or sits well outside, the package's current statistical or architectural
  scope (e.g. would require bolting on an entire new inferential framework).
  Reserve this for standards that are genuinely hard to reconcile with the
  package's design, not merely unimplemented — most gaps found in practice
  should be `Y` (feasible), not `N`. A credible assessment usually has few
  `N` verdicts; if you have none at all, look harder before concluding that.
- **NA** — Does not apply, because the relevant workflow stage is
  deliberately delegated elsewhere (e.g. pre-processing delegated to
  `{recipes}`, resampling delegated to `{rsample}`), or the underlying
  concept is entirely absent from the package's scope (e.g. covariance
  calculations, forecasting, file-based output). `NA` verdicts still count
  in the denominator (see below) — they are not failures, but they are not
  free passes either, so do not assess them generously just to inflate the
  proportion. If a whole subsection is NA'd, say so explicitly and justify
  why in one sentence.

For each of General and every identified category, report a single
proportion: **Y / (Y + N + NA)**. Every standard in the checklist counts in
the denominator, whether met, unmet, or not applicable — there is no
"applicable-only" denominator here (that inflated variant, Y / (Y + N), is
never relevant and should not be computed or reported). A category with a
lot of NA'd standards is thus a genuinely lower-scoring category, not a
strong one with an inflated look — this is intentional: a category that
mostly doesn't apply to the package isn't really "fit for" that category.

### What to inspect before assessing

Every category's `.Rmd` groups its standards under broadly similar headings,
even though exact wording varies (e.g. "Algorithms" vs. "Analytic
Algorithms", "Return Results" vs. "Return Values", "Input Structures" vs.
"Input Data Structures and Validation"). `srr/srr-standards-all.md` lists
the checklists for all categories side by side and is the fastest way to see
this shared shape — skim the section headings there for whichever
category(ies) were identified in Step 1 before you start reading source, so
you know what kind of standard to expect from each part of the codebase.
The recurring pattern is roughly: Documentation → Input data/structures and
validation → Pre-processing/transformation → Algorithms → Return
results/values → Visualization (where applicable) → Testing. Use that
pattern, not any single category's specific IDs, as your reading guide.

With that structure in mind, build a working understanding of the package
by reading (not exhaustively, but enough to ground every verdict in
something you actually saw):

- `DESCRIPTION` / `NAMESPACE` — dependencies, exports, stated purpose.
- `README` — intended workflow and audience.
- The main R source files implementing the public API (entry-point
  functions users actually call) — this is where most Input
  data/structures, Pre-processing, and Algorithms standards live or die,
  whatever they happen to be called in the relevant category's `.Rmd`.
- `tests/testthat/` — don't just check that tests exist; check *what* they
  cover (error/warning messages, edge cases, seeds, missing data) since this
  drives every category's Testing section directly.
- Vignettes — often the fastest way to confirm Documentation-section
  standards (comparisons with other packages, workflow embedding, assumption
  or terminology statements) without re-deriving them from source.
- `.github/workflows/`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md` — CI,
  coverage, life-cycle statement, extended-test scaffolding (General
  standards).
- Print/plot/summary S3 methods and any accessor functions — these map onto
  each category's Return Results/Values and Visualization sections.

This is a long task (category standard sets typically run 50-100 standards
each, on top of ~70 General standards) and reading + judging all of them
against real source code is the bulk of the effort — budget for it
accordingly. If the package is large, consider parallelizing: e.g. one
subagent per category doing a first-pass read of category-relevant source
files and returning candidate verdicts for you to verify and reconcile,
rather than serially re-reading the whole codebase per category yourself.

### Tasks

- [ ] **Task 1** Assess every General standard individually (Y/N/NA), and
  report number complied (Y), total number, and the proportion Y / (Y + N +
  NA) (see Assessment methodology above).
- [ ] **Task 2** For each identified category, assess every category-specific
  standard individually (Y/N/NA), and report the same numbers per category.
- [ ] **Task 3** Based on relative proportions, conclude:
  - whether the package is likely to comply with at least half of all
    standards (General plus category-specific), for General combined with
    each identified category;
  - which single category is the best fit (highest Y / (Y + N + NA)
    proportion, with qualitative reasoning — not just the number — for why
    the package's architecture does or doesn't naturally match that
    category's expected workflow);
  - whether any other identified category is also independently viable as a
    secondary category.

### Output

Write all details of your work, evidence, and conclusions to a new
`srr/standards-compliance.md` document. Structure it as:

1. A short intro: what the package is, what categories were assessed.
2. One section per standards set (General, then each category), each
   containing:
   - A per-subsection Y/N/NA count table (subsections as grouped in the
     `.Rmd` files, e.g. "Documentation", "Input Structures", "Testing").
   - The proportion Y / (Y + N + NA).
   - A short "key evidence and gaps" narrative: concrete file/function
     references for notable `Y` (already-done), notable `Y` (feasible but
     currently missing — flag these clearly, they're where real follow-up
     work would go), and every `N`/whole-subsection `NA` with its
     justification.
3. A final Task 3 section with the scope and category-fit conclusions and a
   clear recommendation of which category to submit under.

Avoid writing a bare unexplained list of 100+ standard IDs with no context —
the tables give the numbers, the narrative is what makes the assessment
verifiable and useful to a maintainer deciding whether to pursue review.
