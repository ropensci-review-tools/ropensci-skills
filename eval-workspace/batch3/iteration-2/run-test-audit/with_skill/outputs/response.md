---
title: "ggseg.formats 0.0.4 — AI-Assisted Test-Suite Audit"
author: "Athanasia Mo Mowinckel (AI-assisted, Claude Code / Opus 4.8)"
date: 2026-07-02
format:
  html:
    toc: true
    toc-depth: 3
    embed-resources: true # self-contained: attachable to the review issue
execute:
  eval: false # a record of a run, not a live notebook
---

# Prompt

> Audit the test suite of this R package and produce a report I can attach to an
> rOpenSci software-review issue. I want to trust the report, so make it
> reproducible and back every finding with evidence.
>
> Environment: the package is a self-contained working tree at
> `/tmp/eval-runs/run-test-audit__with_skill` (ggseg.formats, brain-atlas
> geometry helpers). R is available. Installed: cyclocomp, covr, testthat,
> devtools, withr. NOT installed: pkgnet, bench, profmem — use base-R
> equivalents where relevant. Write a complete report; do not modify the
> package tree.

# Skill

This pass was driven by the `run-test-audit` skill (rOpenSci review-runner
collection), using the shared report template from `run-package-review`. The
operative instructions, reproduced verbatim:

> An **action** skill: it audits the _quality_ of an existing test suite and
> writes a trustworthy report. The premise — **the implementation is the
> contract and the tests are the artifact under review** — judged on whether
> they cover what matters, mean anything, and stay stable.
>
> Ground rules (these make the report trustworthy):
>
> - **Read the tests _and_ the code.** You cannot judge branch coverage from the
>   tests alone.
> - **Run the suite for real, more than once** — and shuffled / re-seeded where
>   cheap — to surface flakiness.
> - **Read-only.** No edits to fix or add tests. Throwaway probes in a scratch
>   session are fine; changes to the package tree are not.
> - **Non-destructive & authorized.** Don't run destructive, paid, or network
>   operations without authorization — note the offline path and mark live paths
>   **"not run."**
> - **Coverage is evidence, not the verdict.** High line coverage can mean
>   breadth (lines execute), not depth (outputs are checked). Say which.
>
> Method: (1) Map the surface — exported set vs. functions referenced by tests;
> note untested exports. (2) Run it, repeatedly (twice; shuffled/re-seeded),
> capturing pass/fail/warn/**skip** counts, timing, silent skips; measure
> coverage via `covr::package_coverage()`. (3) Check coverage depth — happy
> path, edge cases (`NULL`/`NA`/empty/boundary), every error branch, each
> meaningful conditional. (4) Check the assertions mean something — flag
> tautologies, no-assertion tests, over-loose matchers (bare `expect_error()`
> with no `class=`/`regexp=`), over-mocked tests. (5) Hunt flakiness sources —
> wall-clock/time dependence, unseeded randomness, global state,
> order-dependence, hidden skips; review snapshots. (6) Reproduce suspected
> defects with throwaway probes. (7) Review consistency & maintainability.
>
> Findings in four buckets — **A. Coverage gaps**, **B. Weak or meaningless
> tests**, **C. Instability / flakiness**, **D. Consistency / maintainability** —
> each carrying a severity and cited evidence. Then a **Verified healthy** list,
> a **Coverage snapshot** table, a **Not run** list, and an ordered **Suggested
> fix priority**.

# Report

## Method

Reproducible steps, all run from the package root
(`/tmp/eval-runs/run-test-audit__with_skill`). **No package files were
modified**; all probes were throwaway scripts written to `/tmp`.

Tool versions (from `sessionInfo()` / `packageVersion()`):

| Tool      | Version                                 |
| --------- | --------------------------------------- |
| R         | 4.5.2 (2025-10-31)                      |
| testthat  | 3.3.2                                   |
| covr      | 3.6.5                                   |
| devtools  | 2.4.6                                   |
| withr     | 3.0.2                                   |
| cli       | 3.6.6                                   |
| lifecycle | 1.0.5                                   |
| rlang     | 1.2.0                                   |
| sfheaders | 0.4.5                                   |
| sf        | 1.1.0 (a Suggests; present in this env) |

What was executed:

1. **Surface map** — `getNamespaceExports("ggseg.formats")` (61 exports) checked
   by fixed-string presence against the concatenated text of all 19
   `test-*.R` files.
2. **Full suite, twice** — `devtools::test(reporter = "silent")`, once
   unseeded and once with `set.seed(20260702)`, capturing per-file
   pass/fail/warn/skip and wall time.
3. **Order-dependence probe** — every test file run in isolation via
   `testthat::test_file()` in reversed order (a third independent execution of
   all 19 files).
4. **Line coverage** — `covr::package_coverage()`; `percent_coverage()`,
   `coverage_to_list()$filecoverage`, and `tally_coverage()` for zero-hit lines.
5. **Assertion / flakiness statics** — grep-based inventories over the test
   corpus for `expect_error`/`expect_warning` matcher quality, tautologies,
   snapshots, `skip*`, wall-clock calls (`Sys.time`/`Sys.Date`/`date()`),
   unseeded random draws, mocking, global-state mutation (`<<-`, `options(`,
   `par(`), and filesystem side effects.
6. **Manual read** of all 18 executable source files and every test file to
   judge branch depth, not just line hits.

`pkgnet`, `bench`, and `profmem` were not needed for a test-suite audit and
were not used.

## Headline

**Green.** 925 tests across 19 files, **all passing**, with **0 failures, 0
warnings, and 0 skips** on every run. Line coverage is **100.0%** with **no
zero-hit lines** in any executable file. Crucially, this is depth, not just
breadth: 88 of 91 `expect_error()` calls carry a `regexp` matcher, error
branches and edge cases are exercised explicitly, deprecation paths are
asserted with `lifecycle::expect_deprecated()`, and the sf-missing code path is
covered by mocking rather than skipping. The suite is stable across an unseeded
run, a re-seeded run, and a reversed per-file isolation run (three independent
executions). Findings below are all **Low** — polish items, not defects.

## Findings

### A. Coverage gaps

- **A1 _(Low.)_ Two `match.arg`-style error branches are asserted only by
  "does it error", not by which error.** `test-atlas_utils.R:309`
  (`expect_error(get_uniq(data.frame(), "invalid"))`) and
  `test-brain_mesh.R:30` (`expect_error(get_brain_mesh(hemisphere = "invalid"))`)
  fire but pin no message. They pass today because `match.arg()` raises, but a
  future refactor that removed the guard while still erroring for an unrelated
  reason would keep them green. Adding a `regexp =` would tie them to the
  intended failure. (Both are otherwise real branch coverage — the branch does
  execute.)

- **A2 _(Low.)_ `test-validation.R:189`
  (`expect_error(ggseg_data_tract(meshes = meshes))`) does not pin the message.**
  The sibling test at `test-validation.R:415` for the same code path _does_
  assert `"should be a list"`, so the branch's intent is captured elsewhere;
  this specific call is just looser than its neighbours. Adding the matcher
  makes it self-documenting and refactor-safe.

No untested exports: all **61** exported symbols are referenced by name in the
test corpus (surface-map probe, `select`-style fixed-string match). No zero-hit
executable lines (`tally_coverage()`; the only file absent from the coverage
table, `R/ggseg.formats_package.R`, is the 33-byte `"_PACKAGE"` doc stub with
no executable code).

### B. Weak or meaningless tests

- **B1 _(Low.)_ Plot smoke tests assert "no error / no warning" rather than
  output.** `test-ggseg-atlas-plots.R:4,9,15,16,21` and
  `test-ggseg_atlas.R:381–456` use `expect_no_error(plot(...))` /
  `expect_no_warning(plot(...))` against a null PDF device
  (`local_null_pdf()`, `tests/testthat/helper-graphics.R`). This is the
  conventional and reasonable way to test base-graphics side-effect functions —
  but by nature it verifies the call _runs_, not that it _draws the right
  thing_. Mitigating: the numeric layout logic underneath (`plot_cells`,
  `gap_groups`, `order_context_behind`, `resolve_fill_colors`,
  `reposition_flat`) is tested separately with exact `expect_identical` /
  `expect_equal` assertions (`test-ggseg-atlas-plots.R:38–145`,
  `test-reposition-parity.R`), so the smoke tests sit on top of well-asserted
  primitives. No action strictly required; a snapshot of `recordPlot()` or a
  vdiffr baseline would be the only way to raise this from smoke to depth, and
  vdiffr is not a current dependency.

- **No tautologies, no hollow tests.** Zero `expect_true(TRUE)` /
  `expect_false(FALSE)`; zero bare `expect_error()`/`expect_warning()` with the
  call closing on the same line and no argument (the 46 flagged by a naive
  first pass all turned out to carry a positional `regexp` string, e.g.
  `expect_error(atlas_palette("dk"), "must be a.*ggseg_atlas")`).
- **Mocking is not over-mocking.** The 117 mock references
  (`local_mocked_bindings`) are of two kinds: (a) input _fixtures_ named
  `mock_2d`/`mock_3d` — legacy-format data structures the function under test
  actually transforms, then asserts the real result (class, `$atlas`, message);
  (b) silencing `lifecycle::signal_stage` / `rlang::is_installed` so the real
  code path can be exercised. No test verifies only a mock.

### C. Instability / flakiness

- **C1 _(Low, and mitigated.)_ `print`-method snapshots capture cli-formatted
  output.** 24 `expect_snapshot()` calls, several of which record cli glyphs
  (e.g. `Palette: v`, `Rendering: v ggseg` where `v` is a rendered checkmark) —
  see `tests/testthat/_snaps/ggseg_atlas.md`. cli output can drift across cli
  versions/locales/terminal width, a classic snapshot-brittleness source. In
  practice testthat's snapshot harness fixes width/colour, and the package
  deliberately routes tabular output through its own `print_data_head()`
  (`R/compat_dataframe.R:21`) precisely to avoid tibble-printer drift — a
  documented, thoughtful defence. Worth a note to the author to keep an eye on
  cli-glyph lines if a cli bump ever reflows them, but not an active problem.

- **No wall-clock coupling** — zero `Sys.time()` / `Sys.Date()` / `date()` in
  the test corpus.
- **Unseeded `rnorm()` is not a flakiness risk.** 12 `rnorm(30)` calls
  (`test-atlas_convert.R:831–832`, `test-ggseg_atlas_data.R:176–477`,
  `test-validation.R:430–431`) all feed _filler_ centerline/tangent coordinates
  into mesh metadata; the assertions that follow only check structure (`nrow`,
  s3 class) and never inspect the random values. Verified by reading each site.
  A `set.seed()` would be tidier but changes nothing about pass/fail.
- **No global-state leakage** — zero `<<-`, zero `options(`/`par(` mutation
  outside `withr::local_options()`; filesystem work uses
  `withr::local_tempdir()` (auto-cleaned) or paired `unlink()`.
- **No order-dependence** — all 19 files pass in isolation and in reversed
  order.

### D. Consistency / maintainability

- **D1 _(Low.)_ One test file uses manual `tempfile()` + `unlink()` while the
  rest use `withr::local_tempdir()`.** `test-read_freesurfer.R:147–180` calls
  `unlink(tmp)` at the end of the block; every other file
  (`test-migrate_atlas_files.R`, `test-atlas_polygons.R`,
  `test-read_freesurfer.R:207`) uses the withr helper, which cleans up even on
  early exit. Since testthat expectations don't abort the block, the `unlink`
  still runs and tempfiles are OS-cleaned regardless — cosmetic consistency
  only.

- **Structure is clean.** No mega-`test_that()` blocks: the suite uses the
  `describe()`/`it()` (BDD) style throughout, with tight
  block-to-expectation ratios (e.g. `test-atlas_utils.R`: 202 blocks / 275
  expectations). Two shared helper files (`helper-graphics.R`,
  `helper-polygons.R`) hold the common bootstrap; no duplicated setup sprawl.
- **No dead or `.blob` test files, no misleading tags.** Every `test-*.R` maps
  to an `R/*.R` source file of the same stem; test data under
  `tests/testthat/data/` (FreeSurfer stats/table fixtures) is all consumed.

## Verified healthy (no action)

- **Error branches are genuinely exercised, not just present.** 91
  `expect_error()` calls, **88 with a `regexp` matcher** tying the assertion to
  the specific failure (e.g. `"must be a.*ggseg_atlas"`, `"missing columns"`,
  `"does not contain vertices"`, `"migrate_atlas_files"`). 36 `expect_warning`,
  23 `expect_message` similarly.
- **Deprecation lifecycle is tested.** `lifecycle::expect_deprecated()` covers
  the `as_brain_atlas`, `brain_atlas`, `is_brain_atlas`, `unify_legacy_atlases`,
  `brain_data_*`, and `sf=`-argument paths (`test-coercion.R`,
  `test-atlas_convert.R`, `test-ggseg_atlas.R`, `test-ggseg_atlas_data.R`,
  `test-atlas_polygons.R`).
- **The sf-optional design is tested on both paths.** `has_sf()` /
  `require_sf()` are covered with sf present _and_ mocked-absent
  (`test-sf_availability.R:8,24`), and `as_polygon_atlas()` on an sf-backed
  atlas with sf mocked away asserts the `migrate_atlas_files` pointer
  (`test-atlas_polygon_converters.R:37`). This is the one place a `skip_if_not_installed("sf")`
  is used (`test-sf_availability.R:18`) — appropriately, only for the
  sf-present assertion.
- **Representation parity is proven, not assumed.** `test-reposition-parity.R`
  builds the same geometry as sf and as `brain_polygons` and asserts identical
  layout (`expect_equal(..., tolerance = 1e-9)`) and identical group ordering —
  exactly the invariant the sf-optional refactor needs.
- **Edge cases are covered explicitly:** empty geometry, `NA` palette entries,
  duplicate labels, ragged row-binds, one-to-many joins, holes/multi-ring
  polygons, regex-metacharacter subject dirs (`a+b`), trailing-vs-mid-label
  measure stripping, and dot-to-hyphen label rewrites.
- **Deterministic printing by design.** `print_data_head()` strips to a base
  data.frame and summarises list-columns as `<type [n]>` so snapshots don't
  depend on whether tibble is installed (`R/compat_dataframe.R:11–36`).
- **100.0% line coverage with no zero-hit lines**, and the suite is **stable
  across three independent executions** (unseeded, re-seeded, reversed-isolated).

## Coverage snapshot

Total line coverage: **100.0%** (`covr::package_coverage()`). Zero-hit
executable lines: **none** (`tally_coverage()`).

| File                         | Line coverage                            |
| ---------------------------- | ---------------------------------------- |
| R/atlas_accessors.R          | 100%                                     |
| R/atlas_convert.R            | 100%                                     |
| R/atlas_polygon_converters.R | 100%                                     |
| R/atlas_polygon_ops.R        | 100%                                     |
| R/atlas_polygons.R           | 100%                                     |
| R/atlas_utils.R              | 100%                                     |
| R/atlases.R                  | 100%                                     |
| R/brain_mesh.R               | 100%                                     |
| R/coercion.R                 | 100%                                     |
| R/compat_dataframe.R         | 100%                                     |
| R/ggseg_atlas_data.R         | 100%                                     |
| R/ggseg_atlas.R              | 100%                                     |
| R/migrate_atlas_files.R      | 100%                                     |
| R/read_freesurfer.R          | 100%                                     |
| R/sf_availability.R          | 100%                                     |
| R/validation.R               | 100%                                     |
| R/ggseg.formats_package.R    | (no executable code — `"_PACKAGE"` stub) |

Run summary (per `devtools::test()`):

| Run                              | tests | pass | fail | warn | skip | wall time |
| -------------------------------- | ----- | ---- | ---- | ---- | ---- | --------- |
| 1 (unseeded)                     | 925   | 925  | 0    | 0    | 0    | ~36 s     |
| 2 (`set.seed(20260702)`)         | 925   | 925  | 0    | 0    | 0    | ~21 s     |
| 3 (per-file, reversed, isolated) | 925   | 925  | 0    | 0    | 0    | —         |

Assertion inventory: 91 `expect_error` (88 with `regexp`), 36 `expect_warning`,
23 `expect_message`, 24 `expect_snapshot`, ~14 `lifecycle::expect_deprecated`,
1 `skip_if_not_installed`, 0 tautologies, 0 wall-clock calls, 0 `<<-`.

## Not run (reason)

- **No live / network / paid paths exist to run.** The package touches only the
  local filesystem (FreeSurfer file readers, atlas-file migration); those are
  tested against bundled fixtures under `tests/testthat/data/` and
  `withr::local_tempdir()`. Nothing was gated behind authorization.
- **`vdiffr` / graphical snapshot testing — not run (not a dependency).** Plot
  correctness is therefore verified at the layout-primitive level, not
  pixel-level (see B1).
- **`pkgnet`, `bench`, `profmem` — not used.** Out of scope for a test-suite
  audit and not installed; base-R timing (`Sys.time()` deltas around
  `devtools::test()`) and base grep sufficed.
- **`R CMD check` — not run.** This pass audits the test suite, not the full
  package build; the run-package-review umbrella covers that separately.

## Suggested fix priority

All items are **Low** — the suite is in strong shape; these are polish, not
blockers.

1. **A1 / A2 (Low)** — add `regexp =` (or `class =`) to the three bare
   `expect_error()` calls (`test-atlas_utils.R:309`, `test-brain_mesh.R:30`,
   `test-validation.R:189`) so each pins the intended failure and stays
   refactor-safe.
2. **C1 (Low)** — keep an eye on the cli-glyph lines in the print snapshots
   (`_snaps/ggseg_atlas.md`) across cli upgrades; optionally wrap
   snapshot-producing prints in `testthat::local_reproducible_output()` if any
   drift appears.
3. **C (Low, cosmetic)** — add a `set.seed()` (or replace `rnorm(30)` with a
   fixed matrix) at the 12 filler-geometry sites for tidiness; behaviourally a
   no-op.
4. **D1 (Low, cosmetic)** — migrate the manual `tempfile()` + `unlink()` in
   `test-read_freesurfer.R:147–180` to `withr::local_tempdir()` for
   consistency with the rest of the suite.
5. **B1 (Low, optional)** — if graphical regressions ever matter, introduce a
   `vdiffr` baseline for `plot.ggseg_atlas`; otherwise the current
   smoke-over-asserted-primitives arrangement is acceptable.
