# Test-suite audit: `ggseg.formats`

Package version 0.0.4. Audit prepared for attachment to an rOpenSci software-review issue.

## How to reproduce this report

All findings below were produced from a clean checkout of the working tree with the commands shown. Everything is deterministic (verified: two consecutive runs give identical counts). Toolchain used:

| Component | Version            |
| --------- | ------------------ |
| R         | 4.5.2 (2025-10-31) |
| testthat  | 3.3.2 (edition 3)  |
| covr      | 3.6.5              |
| cyclocomp | 1.1.2.9000         |

Reproduction (run from the package root):

```r
# 1. Run the suite
suppressMessages(devtools::load_all("."))
res <- as.data.frame(testthat::test_local(".", reporter = "silent", stop_on_failure = FALSE))
c(tests = nrow(res), pass = sum(res$passed), fail = sum(res$failed),
  warn = sum(res$warning), skip = sum(res$skipped))

# 2. Line coverage
cov <- covr::package_coverage(".", quiet = TRUE)
covr::percent_coverage(cov)          # total
covr::coverage_to_list(cov)$filecoverage   # per file
covr::zero_coverage(cov)             # any unhit lines

# 3. Cyclomatic complexity
cyclocomp::cyclocomp_package_dir(".")
```

Static counts (LOC, expectation types, anti-pattern greps, file mapping) were taken by
reading each `R/*.R` and `tests/testthat/test-*.R` file with `readLines()` and tallying
with `grepl()`/`regmatches()` — no external state.

## Headline results

| Metric                                    | Value                                                           | Evidence                   |
| ----------------------------------------- | --------------------------------------------------------------- | -------------------------- |
| Test outcome                              | **679 `it()` tests, 925 assertions, 0 fail, 0 warning, 0 skip** | `testthat::test_local()`   |
| Line coverage                             | **100.00%** (16/16 code files)                                  | `covr::package_coverage()` |
| Zero-hit lines                            | **0**                                                           | `covr::zero_coverage()`    |
| Exported functions referenced by tests    | **61 / 61**                                                     | NAMESPACE vs test text     |
| R source files with a matching `test-*.R` | **17 / 17**                                                     | filename mapping           |
| Explicit `expect_*` calls                 | **917** across **24** distinct expectation types                | regex tally                |
| Error/condition-path assertions           | **181** (`expect_error`/`warning`/`message`/`deprecated`)       | regex tally                |
| Max cyclomatic complexity                 | **14** (0 functions > 15)                                       | `cyclocomp`                |
| Full-suite wall time                      | ~37 s (load + run); ~22 s pure test time                        | timed run                  |
| Determinism                               | identical counts across 2 runs                                  | repeated run               |

**Bottom line: this is a strong, mature test suite.** Coverage is complete, the public
API is fully exercised, error paths are tested, tests are deterministic and fast, and CI
runs them across five OS/R combinations. The findings below are almost entirely positive;
the two "weaknesses" are inherent limitations of line-coverage as a metric, not defects in
the suite, and are noted so the report is honest rather than to demand changes.

## 1. Test execution

Running `testthat::test_local(".")` after `devtools::load_all()`:

```
n test files : 19
n it() tests : 679
assertions   : 925 pass / 0 fail / 0 warn / 0 skip
```

- **0 failures, 0 warnings.** The suite is green as shipped.
- **Only 1 conditional skip in the entire suite** (`skip_if_not_installed("sf")` in
  `test-sf_availability.R`), and it did not fire in this environment because `sf` is
  installed. There are **no** `skip_on_cran`/`skip_on_ci` guards hiding untested code.
- The 925-vs-917 gap between executed assertions and literal `expect_*` calls in source is
  expected: some expectations run inside loops/helper functions.

### Structure and style

Tests use the testthat 3e `describe()`/`it()` BDD style **exclusively** (167 `describe`
blocks, 512 `it` blocks; **0** legacy `test_that()`). This is internally consistent.
Two helper files (`helper-graphics.R` for a null-PDF device, `helper-polygons.R` for sf
polygon fixtures) provide shared setup.

### Speed (maintainability)

Pure test time is ~22 s; no single file or test dominates:

| Slowest files (s)          |     | Slowest `it()` blocks (s)              |
| -------------------------- | --- | -------------------------------------- |
| test-atlas_utils.R         | 5.9 | migrate: reports migrated files (0.54) |
| test-ggseg_atlas.R         | 2.8 | atlas_sf: returns sf data (0.50)       |
| test-atlas_polygons.R      | 2.7 | atlas_region_op difference (0.47)      |
| test-migrate_atlas_files.R | 1.9 | polygons_remove_small (0.37)           |

No slow test warrants a `skip_on_cran`. Suite is comfortably within CRAN/rOpenSci norms.

## 2. Coverage

`covr::package_coverage(".")` reports **100.00%** total line coverage. Every one of the 16
code-bearing files in `R/` is at 100%, and `covr::zero_coverage()` returns **zero rows** —
every recorded line executes at least once.

The 17th file, `R/ggseg.formats_package.R`, does not appear in the coverage table because
it contains only the `"_PACKAGE"` documentation sentinel (no executable code). This is
correct behaviour, not a gap.

**Caveat (honest reading of the number):** `covr` measures _line_ coverage, not _branch_
or _condition_ coverage. 100% line coverage means every line ran, not that every logical
branch or boundary was asserted. See finding 5 for how much of that risk the suite already
mitigates.

## 3. API coverage and the internal/public boundary

- **All 61 exported functions** (61 `export()` + 24 `S3method()` entries in NAMESPACE) are
  referenced by name in the tests. No exported symbol is untested.
- Every `R/*.R` implementation file has a sibling `tests/testthat/test-*.R`. Two extra test
  files add behavioural coverage beyond a 1:1 mapping:
  - `test-ggseg-atlas-plots.R` — rendering behaviour,
  - `test-reposition-parity.R` — a genuine regression guard (see finding 5).
- The package namespace has 201 functions: 61 exported, 140 internal. **71 internal
  functions are called directly in tests; 69 are not named but still reach 100% coverage
  transitively through the public API.** The 69 untested-by-name internals are mostly S3
  method dispatchers and `print.*` methods (e.g. `print.ggseg_data_cortical`,
  `atlas_regions.brain_atlas`, `validate_ggseg_atlas`), which are correctly exercised
  through their public entry points rather than by reaching past the API. This is the
  _recommended_ pattern; it is noted only so a reviewer knows coverage of these internals
  is indirect.

## 4. Assertion quality

The suite does not lean on weak "did it run" checks. Breakdown of all 917 `expect_*` calls:

| Expectation      | n   |     | Expectation       | n   |
| ---------------- | --- | --- | ----------------- | --- |
| expect_identical | 199 |     | expect_type       | 21  |
| expect_s3_class  | 161 |     | expect_deprecated | 16  |
| expect_true      | 117 |     | expect_named      | 15  |
| expect_false     | 98  |     | expect_setequal   | 14  |
| expect_error     | 91  |     | expect_gt         | 13  |
| expect_null      | 45  |     | expect_length     | 11  |
| expect_warning   | 36  |     | expect_lt         | 9   |
| expect_snapshot  | 24  |     | expect_no_error   | 9   |
| expect_message   | 23  |     | (10 more types)   | ... |

Observations:

- **Value-level assertions dominate.** `expect_identical` (199) is the single most common
  expectation — the suite checks concrete return values, not just class/shape.
- **Error and condition paths are well covered:** 91 `expect_error`, 36 `expect_warning`,
  23 `expect_message`, 16 `expect_deprecated` — **181 condition-path assertions total.**
  Lifecycle deprecations are explicitly tested.
- **24 `expect_snapshot` calls** back 5 snapshot files (`_snaps/*.md`). Inspection of
  `_snaps/ggseg_atlas_data.md` shows they capture human-readable `print` output for each
  data variant (cortical/subcortical/tract/cerebellar, with and without sf) — appropriate
  use of snapshots for formatted output, not a substitute for value assertions.

## 5. Robustness of the test design (branch/edge risk)

Because line coverage cannot prove branch coverage, I inspected how the suite guards the
riskiest logic. It holds up well:

- **Representation parity is explicitly regression-tested.** `test-reposition-parity.R`
  builds the same geometry as both an `sf` object and a polygon object, runs
  `atlas_view_gather`/`atlas_view_reorder`, and asserts the two representations produce
  identical layouts (`expect_equal(..., tolerance = 1e-9)`). This directly guards the
  sf-optional design that is central to the package.
- **The "sf not installed" branch is tested without uninstalling sf**, via
  `rlang::local_mocked_bindings(is_installed = function(...) FALSE)` in
  `test-sf_availability.R`. Mocking is used deliberately: **15 `local_mocked_bindings`
  calls** across the suite exercise otherwise-hard-to-reach branches.
- **Real fixtures, not synthetic-only.** `tests/testthat/data/` ships FreeSurfer stats
  fixtures (`bert/stats/{aseg,lh.aparc,rh.aparc}.stats`) and `.table` files, referenced via
  `test_path()` (11 uses) — so the FreeSurfer readers are tested against genuine input
  formats.

## 6. Hygiene / anti-pattern scan (clean)

Grepping every test file for common fragility patterns:

| Pattern                            | Count             | Verdict                            |
| ---------------------------------- | ----------------- | ---------------------------------- |
| `:::` internal access              | 0                 | clean (no reaching past namespace) |
| absolute paths (`/Users`, `/home`) | 0                 | clean (portable)                   |
| `setwd()`                          | 0                 | clean                              |
| network / `download.file` / URLs   | 0                 | clean (offline, deterministic)     |
| `set.seed` / `sample()`            | 0                 | clean (no unseeded randomness)     |
| `Sys.sleep`                        | 0                 | clean                              |
| `browser()` / debug leftovers      | 0                 | clean                              |
| `tempfile`/`tempdir`               | 14                | good (isolated temp state)         |
| `withr::` local helpers            | 16 + 43 `local_*` | good (state cleanup)               |
| `test_path()`                      | 11                | good (portable fixture paths)      |

R source was scanned too: **0** network calls, **0** `TODO/FIXME/HACK` markers, **0**
`browser()` calls in `R/`.

## 7. Complexity vs. test burden

`cyclocomp` over 203 functions: median complexity 3, mean 3.7, **max 14**, and **zero**
functions above 15. The most complex functions (`as_ggseg_atlas.*` at 13–14,
`migrate_atlas_files` at 13, `validate_legacy_inputs` at 13) all sit in files that are at
100% coverage and have dedicated test files. There is no pocket of high-complexity,
lightly-tested code — the usual risk area — in this package.

## 8. CI integration

Tests are wired into CI as rOpenSci expects:

- **`R-CMD-check.yaml`** runs on a 5-way matrix — macOS-release, Windows-release,
  Ubuntu-devel, Ubuntu-release, Ubuntu-oldrel-1 — on push, PR, **and a weekly schedule**,
  using `r-lib/actions`. Snapshots are uploaded on failure (`upload-snapshots: true`).
- **`test-coverage.yaml`** runs `covr` on every push/PR and publishes a coverage badge.

## Findings summary and recommendations

**Strengths (evidence-backed):**

1. 100% line coverage, 0 zero-hit lines, 0 failing/skipped tests.
2. All 61 exported functions and all 17 source files are tested.
3. Strong value-level and condition-path assertions (917 expectations, 181 error/warning).
4. Deterministic, offline, fast (~22 s), with no anti-patterns.
5. Genuine regression guards (representation parity) and disciplined mocking for
   hard-to-reach branches.
6. Multi-OS / multi-R CI plus a scheduled run.

**Weaknesses / caveats (minor, mostly inherent to the metric):**

1. **Coverage is line-level, not branch-level.** 100% does not prove every conditional
   boundary is asserted. The suite mitigates this well in practice (finding 5), but a
   reviewer should read "100%" as "no dead lines," not "exhaustive branch testing."
   _Optional_ improvement: measure branch/condition coverage with an external tool if the
   review wants a stronger guarantee.
2. **69 internal functions are covered only transitively** (not asserted by name). This is
   an accepted, even preferred, pattern (test through the public API) — flagged only for
   transparency.

**No blocking test-suite issues were found for rOpenSci review.**
