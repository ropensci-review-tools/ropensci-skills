---
title: "ggseg.formats 0.0.4 — AI-Assisted Test-Suite Audit"
author: "Athanasia Monika Mowinckel (AI-assisted, Claude Code / Opus 4.8)"
date: 2026-07-02
format:
  html:
    toc: true
    toc-depth: 3
    embed-resources: true
execute:
  eval: false
---

# Prompt

> Audit the test suite of this R package and produce a report I can attach to an
> rOpenSci software-review issue. I want to trust the report, so make it
> reproducible and back every finding with evidence.
>
> The package is a self-contained working tree at
> `/tmp/eval-runs/run-test-audit__with_skill` (this is ggseg.formats, brain-atlas
> geometry helpers). R is available. Installed: cyclocomp, covr, testthat,
> devtools, withr. NOT installed: pkgnet, bench, profmem. Deliver a complete
> report; do NOT modify the package tree.

# Skill

This pass was driven by the `run-test-audit` skill (rOpenSci review skills
collection). Its operative instructions, reproduced verbatim so this report is
self-contained:

> **Ground rules (these make the report trustworthy)**
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
> **Method**
>
> 1. **Map the surface.** Enumerate the public/exported set
>    (`getNamespaceExports()`) against the functions actually referenced by tests.
>    Note untested exports.
> 2. **Run it, repeatedly.** Execute with `devtools::test()` (twice; shuffled/
>    re-seeded where cheap), capturing pass/fail/warn/**skip** counts, timing, and
>    any silent skips. Measure line coverage with `covr::package_coverage()`.
> 3. **Check coverage depth**, not just the number: happy path, edge cases
>    (`NULL` / `NA` / empty / boundary), **every error branch**, each meaningful
>    conditional.
> 4. **Check the assertions mean something.** Flag tautologies, no-assertion
>    tests, over-loose matchers (bare `expect_error()` with no `class=`/`regexp=`),
>    and over-mocked tests that only verify the mock.
> 5. **Hunt flakiness sources**: wall-clock/time dependence, unseeded randomness,
>    global state, order-dependence between files, hidden skips. Review snapshots.
> 6. **Reproduce suspected defects** with throwaway probes and cite the result.
> 7. **Review consistency & maintainability**: duplicated setup, mega-`test_that()`
>    blocks, dead/`.blob` test files, misleading tags.

Findings are grouped into the four skill buckets (**A** coverage gaps, **B**
weak/meaningless tests, **C** instability/flakiness, **D** consistency/
maintainability), each with a severity and cited evidence.

# Report

## Method

Everything below was run from within the package working tree at
`/tmp/eval-runs/run-test-audit__with_skill`. **No package files were modified**;
all analysis scripts were written to `/tmp` and run against the tree read-only.

Tooling (versions captured live during the run):

| Tool      | Version                                                   |
| --------- | --------------------------------------------------------- |
| R         | 4.5.2 (2025-10-31)                                        |
| testthat  | 3.3.2 (edition 3, per `Config/testthat/edition: 3`)       |
| covr      | 3.6.5                                                     |
| cyclocomp | 1.1.2.9000                                                |
| devtools  | 2.4.6                                                     |
| withr     | 3.0.2                                                     |
| sf        | 1.1.0 (a `Suggests`; present, so sf-paths were exercised) |
| sfheaders | 0.4.5                                                     |

Commands executed:

1. **Surface map.** `getNamespaceExports("ggseg.formats")` (via
   `pkgload::load_all`) cross-referenced by regex against the concatenated text
   of all 21 `test-*.R` files.
2. **Suite run 1** — `devtools::test()` with `pkgload::load_all` sources, summary
   reporter. Captured pass/fail/warn/skip and per-block timing.
3. **Suite run 2** — `testthat::test_local(load_package = "installed")` against
   the installed 0.0.4 build with a fresh RNG seed (`set.seed(20260702)`) to
   surface seed/order dependence. Running against the _installed_ namespace
   rather than `load_all` is itself a second, independent execution path.
4. **Coverage** — `covr::package_coverage(type = "tests")`, then
   `tally_coverage(by = "line")` aggregated per file and scanned for zero-hit
   lines.
5. **Assertion / structure analysis** — brace-matched parsing of every
   `expect_error()` / `expect_warning()` call to detect bare matchers; brace-
   matched parsing of every `it()` block to detect assertion-free tests;
   frequency table of all `expect_*` types; scans for tautologies, unseeded
   randomness, network I/O, unguarded global state, and skips.

Live/paid/network paths: none exist in this suite (see **Not run**). Nothing
destructive was executed.

## Headline

**Green.** This is a strong, trustworthy test suite. The suite runs clean and
**deterministic across two independent executions** — 925 passing assertions,
**0 failures, 0 warnings, 0 skips** each time (36.7 s under `load_all`, 22.0 s
against the installed build). Line coverage is **100.00 %** — every one of the
5,114 R source lines executes — and, crucially, that breadth is backed by
**depth**: across 512 `it()` blocks and 756 `expect_*` calls, **zero** blocks
lack an assertion, **zero** tautologies exist, and error/warning branches are
almost universally pinned to a specific message (only **2** of 91
`expect_error()` calls are bare). Internal (non-exported) helpers are unit-tested
directly, and mocking (`local_mocked_bindings`) is used to reach the
sf-not-installed branch deterministically. The only issues found are minor
hygiene items (Low severity): unseeded `rnorm()` fixtures and a couple of
manual `tempfile()`/`unlink()` pairs. Nothing here blocks review.

## Findings

### A. Coverage gaps

- **A1 _(Low.)_ Two error branches are asserted only by "an error is thrown",
  not "the right error".** `test-brain_mesh.R:30`
  (`expect_error(get_brain_mesh(hemisphere = "invalid"))`) and
  `test-validation.R:189` (`expect_error(ggseg_data_tract(meshes = meshes))`)
  are the only 2 of 91 `expect_error()` calls with no `regexp=`/`class=`. They
  confirm _that_ the input is rejected but not _why_; a future refactor that
  fails for an unrelated reason (e.g. a typo upstream) would still pass. Adding a
  message/class fragment (as the other 89 calls do) closes the gap. Line
  coverage of these branches is already 100 %, so this is depth, not breadth.

- **A2 _(Informational — no gap.)_** All 61 exported symbols are referenced by
  name in the test files (surface-map: `N untested-by-name: 0`), and
  `covr::package_coverage()` reports **100.00 %** line coverage with **zero**
  zero-hit lines in every source file. There is no untested export and no
  unexercised line to report. This is unusually complete; the residual risk is
  entirely in assertion _depth_ (bucket B), which the suite also handles well.

### B. Weak or meaningless tests

- **B1 _(None found — verified.)_** Brace-matched parsing of all 512 `it()`
  blocks found **0** blocks lacking an `expect_*`/snapshot/mock assertion
  (`/tmp/audit_hollow.R`: "it() blocks with NO ... assertion: 0"). A literal
  tautology scan (`expect_true(TRUE)`, `expect_false(FALSE)`,
  `expect_null(NULL)`, `expect_identical(TRUE, TRUE)`) returned **no matches**.
  No smoke-only or hollow tests exist.

- **B2 _(None found — verified.)_** The single mocked-binding pattern
  (`local_mocked_bindings(is_installed = function(...) FALSE, .package = "rlang")`
  at `test-sf_availability.R:8` and `:24`) is used to force the
  _sf-not-installed_ branch and then assert real behaviour
  (`expect_false(has_sf())`, `expect_error(require_sf("atlas_sf()"), "sf")`),
  not merely to verify the mock. This is a legitimate use of mocking to reach an
  otherwise-unreachable branch on a machine where `sf` is installed.

  The 7 `expect_warning()` calls my first-pass whitespace heuristic flagged as
  "bare" are false positives — each carries a message on a wrapped line
  (`"Could not infer"`, `"ignoring"`, `"no 2D geometry"`, `"collide"`,
  `"differing columns"`, etc.), confirmed by brace-matched re-parse: **0** truly
  bare `expect_warning()`.

### C. Instability / flakiness

- **C1 _(Low.)_ Unseeded `rnorm()` in 12 fixture sites.** `rnorm(30)` is called
  without a preceding `set.seed()` at `test-atlas_convert.R:831-832`,
  `test-ggseg_atlas_data.R:176-177,290-291,373-374,476-477`,
  `test-validation.R:430-431`. I inspected every site: the random matrices are
  used **only as opaque payloads** (tract centerlines/tangents), and the
  assertions on them are purely structural — `expect_s3_class(result,
"ggseg_data_tract")`, `expect_identical(nrow(result), 1L)`,
  `expect_identical(ncol(...), 3L)`. **No assertion is value-sensitive**, so this
  is not a functional flakiness risk; any draw passes. It remains a reproducibility
  hygiene item: a hard-coded matrix (or `withr::local_seed()`) would make the
  fixtures deterministic and diff-stable. Both suite runs — including run 2 with a
  deliberately different global seed — produced byte-identical pass counts,
  empirically confirming no seed sensitivity.

- **C2 _(None found — verified.)_** No wall-clock/date coupling
  (`Sys.time`/`Sys.Date`/`Sys.getenv`/`Sys.setenv`: no hits in test files), no
  network or download I/O (`download.file`/`url(`/`http`/`curl`/`httr`: no hits),
  and no unguarded global-state mutation — `options()`, `par()`, and
  `Sys.setenv()` never appear outside a `withr::local_*` scope. State that _is_
  touched is scoped: 43 uses of `withr::local_*` / `local_mocked_bindings` /
  `local_null_pdf()`, the last sinking graphics to `pdf(NULL)` with a deferred
  `dev.off()` (`helper-graphics.R`) so plot tests leak no device.

- **C3 _(None found — verified.)_** Snapshot stability: 5 snapshot files
  (`_snaps/{atlas_accessors,atlas_polygons,compat_dataframe,ggseg_atlas_data,ggseg_atlas}.md`)
  capture `print()` output whose content is driven by the fixed bundled
  `sysdata.rda` (e.g. deterministic vertex/face counts like `47 × 6`, exact hex
  colours). Both runs reproduced them with 0 warnings, so no snapshot drift.

### D. Consistency / maintainability

- **D1 _(None found — verified.)_** Structure is uniform BDD: **167**
  `describe()` groups holding **512** `it()` blocks across 21 files (no legacy
  `test_that()` blocks). This matches the tidyverse describe/it convention and
  keeps individual `it()` blocks small and single-purpose (e.g.
  `test-ggseg-atlas-plots.R` splits `plot.ggseg_atlas` behaviour across 6 focused
  blocks). No mega-block anti-pattern.

- **D2 _(None found — verified.)_** No dead or `.blob` test files; every
  `test-*.R` maps to a real source file, plus 2 shared helpers
  (`helper-polygons.R`, `helper-graphics.R`) providing reusable geometry/graphics
  fixtures rather than duplicated per-file bootstrap. Test fixtures are realistic
  (`tests/testthat/data/bert/stats/*.stats`, `*.table`) rather than synthetic
  stubs, which strengthens the FreeSurfer-reader tests.

- **D3 _(Low.)_ Two manual `tempfile()` + `unlink()` pairs.**
  `test-read_freesurfer.R:147/161` and `:165/180` create a temp file and remove
  it at the end of the block by hand; the rest of the suite uses
  `withr::local_tempdir()` (auto-cleanup, e.g. all of `test-migrate_atlas_files.R`
  and `test-atlas_polygons.R:247+`). If an assertion in those two blocks fails
  before `unlink()`, the temp file lingers in `tempdir()`. Switching to
  `withr::local_tempfile()` would make cleanup unconditional and match the
  surrounding style. Cosmetic; no correctness impact.

## Verified healthy (no action)

- **Deterministic, clean, fast.** Two independent runs (`load_all` and installed
  namespace, different seeds): 925 passing assertions, **0 fail / 0 warn / 0
  skip** both times; 36.7 s / 22.0 s wall-clock. No hidden skips beyond the one
  intentional `skip_if_not_installed("sf")`.
- **100.00 % line coverage with genuine depth.** Every source line executes AND
  outputs are checked: 756 `expect_*` assertions, 0 assertion-free `it()` blocks,
  0 tautologies. Assertions pin concrete values — exact vertex/face counts
  (`10242L`, `20480L`, `30013L`), 0-based index invariants, exact colour
  fallbacks (`#CCCCCC`), stable-sort ordering.
- **Error/edge coverage is specific.** 89 of 91 `expect_error()` and 36 of 36
  `expect_warning()` calls assert a specific message; NULL/NA/empty/boundary
  inputs are exercised (`expect_null(...)` ×45, `expect_false(...)` ×98).
- **Internal helpers are unit-tested directly** — `gap_groups`, `plot_cells`,
  `order_context_behind`, `resolve_fill_colors`, `has_sf`, `require_sf`,
  `resolve_geom`, `df_left_join`, `df_bind_rows` — not just reached transitively
  through exports.
- **Branch reachability via mocking, not environment mangling.** The
  sf-absent path is tested with `local_mocked_bindings` while `sf` stays
  installed — the correct pattern for an optional-dependency package.
- **Reproducibility is itself asserted.** `test-ggseg-atlas-plots.R:139` has an
  explicit "is deterministic without a seed" test pinning
  `resolve_fill_colors(...)` equality across two calls.
- **Graphics and filesystem state are scoped** via `local_null_pdf()` and
  `withr::local_tempdir()`; no device or temp-dir leakage.

## Not run (reason)

- **Live / network / paid paths:** none exist in this suite — no
  `download.file`, `url()`, `http(s)`, `curl`, or `httr` calls in any test file,
  so there was nothing to authorize or defer.
- **`pkgnet`, `bench`, `profmem`:** not installed (per task constraints) and not
  needed for a test-suite audit; performance/dependency-graph passes are out of
  scope for this pass (see the sibling `run-performance-review` /
  `run-dependency-review` skills).
- **`R CMD check` / cyclomatic-complexity (`cyclocomp`):** out of scope for a
  test audit; not run.
- **Parallel test execution:** the suite runs single-threaded
  (`Config/testthat/edition: 3`, no `Config/testthat/parallel: true`); order-
  dependence across a parallel worker pool was therefore not applicable. Cross-
  file order-dependence was instead probed by the reseeded run 2 (no change).
- **`sf`-absent real environment:** `sf` is installed here, so the true
  uninstalled path runs only via mock (`test-sf_availability.R`), not by actually
  removing the package. The mock covers the code branch; a CI matrix leg without
  `sf` would additionally confirm the real load-failure path.

## Suggested fix priority

All items are Low severity; the suite is fit to attach to a review as-is.

1. **A1** — add a `regexp=`/`class=` to the 2 bare `expect_error()` calls
   (`test-brain_mesh.R:30`, `test-validation.R:189`) so those error branches
   assert _why_, not just _that_.
2. **C1** — seed or hard-code the 12 `rnorm()` fixtures (`withr::local_seed()` or
   literal matrices) for byte-stable, reproducible test inputs. No behaviour
   change; purely diff/repro hygiene.
3. **D3** — swap the 2 manual `tempfile()`/`unlink()` pairs in
   `test-read_freesurfer.R` for `withr::local_tempfile()` to match the rest of
   the suite and guarantee cleanup on assertion failure.
