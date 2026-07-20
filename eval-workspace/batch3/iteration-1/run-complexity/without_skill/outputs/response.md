# Code Complexity Report: `ggseg.formats` (v0.0.4)

Prepared for an rOpenSci software-review issue. All figures are **measured**
with tooling (not eyeballed); the tool and command behind each number are
named so the analysis is reproducible.

## Summary

`ggseg.formats` is a small-to-medium package (2,923 lines of R code across 16
source files, 203 functions) whose complexity is **low and well-controlled**.
Mean cyclomatic complexity is 3.72 and the median is 3; the single most complex
function scores 14, which is comfortably below the threshold (15) at which
`cyclocomp`/`lintr` flag a function by default. No function is a runaway. The
main structural observation is one large file (`atlas_utils.R`, 702 code
lines / 48 functions) that mixes several concerns, and a package `.lintr` that
disables the cyclomatic-complexity linter. Test coverage is 100% and the full
test suite passes, so the more complex functions are all exercised.

**Verdict for review: complexity is not a barrier to acceptance.** The findings
below are refinements, not blockers.

---

## 1. Method

| Dimension                             | Tool / command                                                    | Notes                                                                                                 |
| ------------------------------------- | ----------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| Cyclomatic complexity (whole package) | `cyclocomp::cyclocomp_package_dir(".")`                           | Installs the package and measures every function, exported and internal (203 functions).              |
| Cyclomatic complexity (per file)      | `cyclocomp::cyclocomp()` on each parsed top-level function        | Attributes each function to its source file (202 top-level functions; the 203rd is a nested closure). |
| Source lines of code                  | `readLines()` + blank/comment classification                      | Distinguishes code / comment / blank per file.                                                        |
| Function length                       | `getParseData()` / srcref line spans                              | Lines per function definition.                                                                        |
| Nesting depth                         | Recursive walk of the parse tree counting control-flow constructs | Relative ranking of the deepest functions.                                                            |
| Test coverage                         | `covr::package_coverage(".", type = "tests")`                     | Per-file and overall line coverage.                                                                   |
| Test pass state                       | `testthat::test_dir()` via `devtools::load_all()`                 | Confirms the measured code runs green.                                                                |

Not installed in this environment: `pkgnet`, `bench`, `profmem`. Dependency-graph
and runtime-profiling metrics were therefore out of scope; the analysis is
static-complexity plus coverage. Base-R parsing (`parse`, `getParseData`) was
used where those packages would otherwise have helped.

---

## 2. Cyclomatic complexity

Measured with `cyclocomp_package_dir()` over all **203** functions.

| Statistic               | Value       |
| ----------------------- | ----------- |
| Mean                    | 3.72        |
| Median                  | 3           |
| Std. dev.               | 3.11        |
| Maximum                 | 14          |
| Functions with CC <= 5  | 160 (78.8%) |
| Functions with CC <= 10 | 191 (94.1%) |
| Functions with CC > 10  | 12 (5.9%)   |
| Functions with CC >= 15 | 0           |

Distribution:

| Complexity band | Count |
| --------------- | ----- |
| 1-5 (simple)    | 160   |
| 6-10 (moderate) | 31    |
| 11-15 (complex) | 12    |
| 16-20 (high)    | 0     |
| 21+ (very high) | 0     |

**Reading of the data:** the distribution is healthy and right-skewed with a
short tail. Nearly four in five functions are trivially simple; the "complex"
band tops out at 14. For context, `lintr::cyclocomp_linter()` defaults to
warning at 15 and `cyclocomp`'s own package default is 15 — **no function in
this package would trip either default.**

### The 12 most complex functions (CC > 10)

Combined with function length (lines) so reviewers can judge whether the
complexity is dense or merely branchy:

| File                    | Function                      |  CC | Lines |
| ----------------------- | ----------------------------- | --: | ----: |
| `coercion.R`            | `as_ggseg_atlas.list`         |  14 |    24 |
| `coercion.R`            | `as_ggseg_atlas.ggseg_atlas`  |  14 |    14 |
| `coercion.R`            | `as_ggseg_atlas.brain_atlas`  |  13 |    29 |
| `migrate_atlas_files.R` | `migrate_atlas_files`         |  13 |    29 |
| `atlas_convert.R`       | `validate_legacy_inputs`      |  13 |    19 |
| `ggseg_atlas.R`         | `validate_ggseg_atlas_inputs` |  12 |    41 |
| `atlas_utils.R`         | `rebuild_data_with_geom`      |  12 |    31 |
| `atlas_utils.R`         | `atlas_region_op`             |  11 |    58 |
| `atlas_utils.R`         | `reposition_views`            |  11 |    44 |
| `ggseg_atlas_data.R`    | `validate_centerlines`        |  11 |    28 |
| `validation.R`          | `validate_one_mesh`           |  11 |    21 |
| `atlas_utils.R`         | `atlas_view_gather`           |  11 |    19 |

**What drives the complexity (evidence from reading the code):**

- **S3 coercion dispatch** (`coercion.R`, the three highest scorers). The branching
  is structural type-detection: an object may carry a modern `data` slot, a
  legacy `core` + `sf`/`vertices`/`meshes` layout, or a legacy `brain_atlas`
  `$data` frame, each routed to a different converter with a `cli::cli_abort`
  fallback (`R/coercion.R:23-107`). The high CC reflects the number of legacy
  shapes the class must accept, not tangled logic — each branch is a couple of
  lines with an early `return()`.
- **Input validation** (`validate_legacy_inputs`, `validate_ggseg_atlas_inputs`,
  `validate_centerlines`, `validate_one_mesh`). These are guard-clause chains:
  check `is.data.frame`, check required columns via `setdiff`, check column
  types, `cli::cli_abort` on each failure (see the repeated idiom at
  `R/validation.R:6-60`). Each guard adds a branch; the pattern is idiomatic and
  readable.
- **Legacy migration** (`migrate_atlas_files`, CC 13) is already decomposed into
  small single-purpose helpers — `migration_target_geom`, `migrate_atlas_object`,
  `migrate_rda_file`, `is_atlas_for_migration` (`R/migrate_atlas_files.R:66-137`).
  The top-level CC comes from the directory-walk / status-message loop, not from
  a monolith.

**Assessment:** none of the 12 warrant refactoring for correctness. If the
maintainer wants to shave the peaks, the cleanest wins are (a) the validation
functions, which could share a small `require_columns()` / `require_type()`
helper to collapse repeated guard clauses, and (b) `atlas_region_op` (58 lines,
the longest function), which is a candidate for extracting its inner branches.

---

## 3. Per-file complexity

`cyclocomp` per parsed top-level function, aggregated by file, sorted by total
complexity.

| File                         | Funcs | Total CC | Max CC | Mean CC | Code lines |
| ---------------------------- | ----: | -------: | -----: | ------: | ---------: |
| `atlas_utils.R`              |    48 |      166 |     12 |    3.46 |        702 |
| `atlas_convert.R`            |    22 |      100 |     13 |    4.55 |        363 |
| `ggseg_atlas.R`              |    27 |       87 |     12 |    3.22 |        376 |
| `ggseg_atlas_data.R`         |    16 |       72 |     11 |    4.50 |        287 |
| `validation.R`               |    12 |       64 |     11 |    5.33 |        198 |
| `coercion.R`                 |    13 |       59 |     14 |    4.54 |        174 |
| `atlas_accessors.R`          |    15 |       47 |      6 |    3.13 |        149 |
| `migrate_atlas_files.R`      |     5 |       40 |     13 |    8.00 |         75 |
| `atlas_polygon_ops.R`        |    14 |       32 |      5 |    2.29 |        155 |
| `atlas_polygons.R`           |     7 |       30 |      9 |    4.29 |        148 |
| `compat_dataframe.R`         |     8 |       29 |      7 |    3.62 |        126 |
| `atlas_polygon_converters.R` |     2 |        9 |      5 |    4.50 |         51 |
| `read_freesurfer.R`          |     5 |        9 |      3 |    1.80 |         77 |
| `brain_mesh.R`               |     2 |        7 |      6 |    3.50 |         24 |
| `atlases.R`                  |     4 |        4 |      1 |    1.00 |          4 |
| `sf_availability.R`          |     2 |        3 |      2 |    1.50 |         13 |

**Findings:**

- **`atlas_utils.R` is a "god file"** — 702 code lines and 48 functions, more
  than double the next-largest file. Its _per-function_ complexity is fine
  (mean 3.46, max 12), so this is an **organisation** concern, not a
  complexity one. The file already carries two internal section headers
  (`# Atlas manipulation functions ----` at line 100 and
  `# Atlas view manipulation ----` at line 430), which is a natural seam:
  splitting into `atlas_region_ops.R` and `atlas_view_ops.R` would improve
  navigability without touching behaviour.
- **`migrate_atlas_files.R` has the highest mean CC (8.0)** but only because it
  is 5 functions and two of them are the legacy-migration branchers. In absolute
  terms it is a 75-line file — low risk.
- The remaining files are small and simple.

---

## 4. Function size and nesting

Measured with srcref line spans and a parse-tree walk.

- Mean function length: **16.1 lines**; median **14.5**; max **58**.
- Functions over 50 lines: **1** (`atlas_region_op`, `atlas_utils.R`).
- Longest functions: `atlas_region_op` (58), `plot.ggseg_atlas` (45),
  `reposition_views` (44), `atlas_region_contextual` (43),
  `atlas_view_remove_small` (43).

Because the highest-CC functions are also short (the two CC-14 functions are 24
and 14 lines), complexity here comes from **branching breadth, not depth or
length** — the code is wide-but-shallow, which is much easier to review and test
than deep, long functions.

Nesting depth (relative ranking; the metric counts `function` and `{` as depth,
so a flat body reads as ~2-4): the deepest bodies are `df_bind_rows`
(`compat_dataframe.R`) and `migrate_atlas_files`, followed by
`polygon_geometry_areas` and `rebuild_data_with_geom`. None showed pathological
nesting on inspection.

---

## 5. Test coverage (complexity risk mitigation)

Measured with `covr::package_coverage(".", type = "tests")`.

- **Overall line coverage: 100%.**
- **Every one of the 16 source files is at 100%.**
- The full `testthat` suite runs green (0 failures) via `devtools::load_all()`.
- Test-to-code line ratio: ~6,982 test lines vs 5,114 R lines (incl. comments),
  i.e. tests slightly outweigh source.

This is the single most reassuring finding for a reviewer: the 12 higher-CC
functions are not under-tested corners — they are fully covered, so the
branching they contain is verified.

---

## 6. Tooling / config observations

- **`cyclocomp_linter` is disabled in `.lintr`.** The package's `.lintr`
  sets `cyclocomp_linter = NULL` (alongside `object_usage_linter = NULL`).
  In practice the code is well within the default threshold anyway (max CC 14
  vs threshold 15), so nothing is being hidden today — but disabling the linter
  removes the guardrail that would catch a future regression. **Recommendation:**
  either re-enable `cyclocomp_linter` with an explicit `complexity_limit` (e.g.
  15, which the code already satisfies), or document in a comment why it is off.
- No `pkgnet` dependency graph was produced (package not installed); the
  package is small enough (4 hard `Imports`: cli, lifecycle, rlang, sfheaders)
  that dependency complexity is not a concern.

---

## 7. Recommendations (priority order)

1. **Low effort, optional — split `atlas_utils.R`.** Use the existing section
   headers to break it into `atlas_region_ops.R` / `atlas_view_ops.R`. Pure
   file move; improves navigability of the largest file.
2. **Low effort — reconsider disabling `cyclocomp_linter` in `.lintr`.**
   Re-enable with an explicit limit so future growth is caught.
3. **Optional — factor shared validation guards.** The `validate_*` family
   repeats the "is.data.frame -> required columns -> column types" pattern; a
   couple of small internal helpers would lower CC on several of the top-12
   functions and reduce duplication.
4. **Optional — extract branches from `atlas_region_op`** (the only function
   over 50 lines) if the maintainer wants to eliminate the length outlier.

None of these are required for rOpenSci acceptance on complexity grounds. The
package is small, its complexity distribution is healthy (max CC 14, mean 3.72),
and it is comprehensively tested (100% coverage, green suite).

---

_Reproducibility: metrics generated with `cyclocomp::cyclocomp_package_dir()`,
`cyclocomp::cyclocomp()`, `covr::package_coverage()`, and base-R
`parse`/`getParseData` over the working tree at package version 0.0.4._
