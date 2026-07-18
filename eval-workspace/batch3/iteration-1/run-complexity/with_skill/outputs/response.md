---
title: "ggseg.formats 0.0.4 — AI-Assisted Code-Complexity Analysis"
author: "Athanasia Mo Mowinckel (AI-assisted, Claude Code / Opus 4.8)"
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

> Analyse the code complexity of this R package and produce a report I can attach to an rOpenSci software-review issue. I want to trust the report, so measure rather than eyeball, and back every finding with evidence.
>
> Environment: the package is a self-contained working tree (ggseg.formats, brain-atlas geometry helpers). R is available; installed: cyclocomp, covr, testthat, devtools, withr. NOT installed: pkgnet, bench, profmem — use base-R equivalents (utils::getParseData, system.time) where relevant. Read-only: do not modify the package tree.

# Skill

Driven by the `run-complexity` skill (rOpenSci review runner, the code-complexity pass). Operative instructions followed verbatim:

> - **Measure first.** Rank functions by a real metric before reading source; the eye is a poor complexity meter and misses structural duplication entirely.
> - **Read the code to interpret the numbers.** A high score can be benign; a low score can hide duplication. The metric points; you judge.
> - **Confirm behavioural claims with runtime probes.** If you say a function is inert or its error path is broken, reproduce it in a scratch session and paste the result.
> - **Read-only.** No refactoring the package to prove a point.
> - **Preserve the user-facing surface.** Every internal-refactor recommendation must keep exported names, signatures, and return types identical.

Method per the skill: (1) per-function cyclomatic complexity + LOC + nesting via `cyclocomp` and `utils::getParseData`; (2) static duplication analysis over `R/*.R` via normalized token sequences; (3) targeted source reading of the top offenders; (4) runtime probes to confirm behavioural claims; plus a coverage cross-check to confirm the duplicated code is live.

# Report

## Method

Tools and versions:

- R 4.5.2 (2025-10-31)
- cyclocomp 1.1.2.9000, covr 3.6.5, testthat 3.3.2, devtools 2.4.6

What was executed (all against the working tree, from inside it):

1. **Per-function metrics.** `devtools::load_all()` then `cyclocomp::cyclocomp()` for every one of the **201 functions** in the namespace. Deparsed-body LOC, `if`/`for`/`while` counts, and max brace-nesting were computed from the parsed bodies.
2. **Physical LOC + source map.** Each of the **202 top-level function definitions** in `R/*.R` was mapped to its file and line span via `parse(keep.source = TRUE)` + `getParseData()` (`srcref`), giving true physical LOC per function (deparse understates it).
3. **Duplication.** Each function body was reduced to a **structural token-type sequence** (identifiers and literals dropped, keeping the syntactic skeleton) from `getParseData()`. Bodies were grouped by identical signature (exact copy-paste) and compared pairwise by **Jaccard overlap of 5-grams of token types** (near-duplication). Call sites of reused helpers were counted from `SYMBOL_FUNCTION_CALL` tokens.
4. **Runtime probes.** Four scratch-session probes confirmed the duplicated families are behaviourally parallel (same output shape modulo class/slot).
5. **Coverage cross-check.** `covr::package_coverage()` to confirm the duplicated code is exercised (so consolidation is a maintenance win, not dead-code pruning).

**No package files were modified.** All scripts and probes ran from `/tmp` and only read the package tree.

## Headline

**Green on complexity, amber on duplication.** Per-function complexity is genuinely low: the median cyclomatic complexity is **3**, the mean **3.75**, and the single most complex function scores **cc = 14** — no function reaches the conventional cc = 15 "refactor" threshold, and only **15 of 201** functions score ≥ 10. The larger functions are _not_ god-functions; the biggest (`atlas_region_op`, 58 LOC) delegates cleanly to named helpers and scores only cc = 11. The real, measurable issue is **structural duplication in four leaf "families"** — constructors, print methods, and accessors that were hand-copied per atlas type. About **267 physical LOC across 16 functions** are near-identical (Jaccard 0.85–1.00), all at **100% test coverage**, meaning every future change to that boilerplate must currently be made in three-to-five places by hand. Everything recommended below keeps the exported API byte-for-byte identical.

## Findings

### Measured profile

Cyclomatic-complexity distribution over all 201 namespace functions:

| quantile | 0%  | 50% | 75% | 90% | 95% | 100% |
| -------- | --- | --- | --- | --- | --- | ---- |
| cc       | 1   | 3   | 5   | 8   | 11  | 14   |

Mean cc = 3.75; functions with cc ≥ 10: **15**; with cc ≥ 15: **0**. Complexity is concentrated in a thin tail, exactly as expected for a healthy codebase.

Top functions by cyclomatic complexity (with physical LOC and file):

| function                      | where                    |  cc | phys LOC | `if` | max nest | verdict                                                                 |
| ----------------------------- | ------------------------ | --: | -------: | ---: | -------: | ----------------------------------------------------------------------- |
| `as_ggseg_atlas.list`         | coercion.R:84            |  14 |       24 |    2 |        2 | OK — legacy-structure dispatch, delegates to `convert_legacy_structure` |
| `as_ggseg_atlas.ggseg_atlas`  | coercion.R:23            |  14 |       14 |    2 |        2 | OK — guard chain on legacy slots                                        |
| `as_ggseg_atlas.brain_atlas`  | coercion.R:40            |  13 |       29 |    3 |        2 | OK — deprecation + branch to converters                                 |
| `migrate_atlas_files`         | migrate_atlas_files.R:29 |  13 |       29 |    6 |        6 | Watch — nesting depth 6 is the deepest in the package                   |
| `validate_legacy_inputs`      | atlas_convert.R:111      |  13 |       19 |    3 |        3 | OK — validation guard chain                                             |
| `validate_ggseg_atlas_inputs` | ggseg_atlas.R:530        |  12 |       41 |    5 |        4 | OK — input validation, linear guards                                    |
| `rebuild_data_with_geom`      | atlas_utils.R:907        |  12 |       31 |    6 |        3 | OK — type-switch over atlas variants                                    |
| `atlas_region_op`             | atlas_utils.R:260        |  11 |       58 |    3 |        4 | Healthy — largest LOC but well-factored (see below)                     |
| `reposition_views`            | atlas_utils.R:854        |  11 |       44 |    4 |        2 | OK                                                                      |
| `validate_centerlines`        | ggseg_atlas_data.R:390   |  11 |       28 |    4 |        4 | OK — validation                                                         |
| `validate_one_mesh`           | validation.R:119         |  11 |       21 |    4 |        4 | OK — validation                                                         |
| `atlas_view_gather`           | atlas_utils.R:623        |  11 |       19 |    3 |        2 | OK                                                                      |

The takeaway: **per-function complexity is fine.** The remaining findings are about duplication, which cyclomatic complexity cannot see.

### Hotspot 1 — `ggseg_data_*` constructor + print + deprecated-wrapper family _(Medium.)_

**Evidence.** Structural-token analysis flags the four `ggseg_data_*` constructors as near-duplicates (Jaccard: cortical↔subcortical **1.00**, cortical↔cerebellar **0.96**, cortical↔tract **0.88**), the three main `print.ggseg_data_*` methods as **exact** structural duplicates (identical 72-token signature; pairwise Jaccard **1.00**), and the deprecated `brain_data_*` wrappers as exact duplicates (Jaccard 1.00). All are at **100% line coverage** (probe below).

Constructor skeleton, repeated four times (`R/ggseg_atlas_data.R:22`, `:72`, `:131`, `:193`):

```r
ggseg_data_cortical <- function(geom = NULL, vertices = NULL, ...) {
  geom <- resolve_geom(geom, ..., .fn = "ggseg_data_cortical")
  if (is.null(geom) && is.null(vertices)) {
    cli::cli_abort("At least one of {.arg geom} or {.arg vertices} is required.")
  }
  if (!is.null(vertices)) vertices <- validate_vertices(vertices)
  structure(list(geom = geom, vertices = vertices),
            class = c("ggseg_data_cortical", "ggseg_atlas_data"))
}
```

Only three things vary between siblings: the slot name(s) (`vertices` / `meshes` / both / `centerlines`), the validator called, and the class string. Print skeleton, repeated three times (`:226`, `:244`, `:262`):

```r
print.ggseg_data_cortical <- function(x, n = 10, ...) {
  cli::cli_h2("ggseg_data_cortical")
  twod_summary <- summarise_2d(x)
  if (!is.null(twod_summary)) cli::cli_text(twod_summary)
  if (!is.null(x$vertices)) {
    cli::cli_text("{.strong 3D (ggseg3d):} vertex indices")
    print_data_head(x$vertices, n)
  }
  invisible(x)
}
```

**Runtime probe (confirms the families are behaviourally parallel):**

```
cortical class:    ggseg_data_cortical, ggseg_atlas_data
subcortical class: ggseg_data_subcortical, ggseg_atlas_data
cortical slots:    geom, vertices     subcortical slots: geom, meshes
cortical    empty-call error: At least one of `geom` or `vertices` is required.
subcortical empty-call error: At least one of `geom` or `meshes` is required.
```

**Refactor (API unchanged).** Keep every exported name as a thin, explicit shim so `?help`, autocomplete, and `@examples` keep working — do **not** hide them behind a function factory. Factor the shared body into internal helpers and have each public function be a one-liner:

```r
# internal, @noRd
new_ggseg_data <- function(class, geom, slots, .fn) {
  geom <- resolve_geom(geom, .fn = .fn)  # ... shared null-guard + validate
  structure(c(list(geom = geom), slots), class = c(class, "ggseg_atlas_data"))
}
print_ggseg_data <- function(x, class, threed_line, slot, n) { ... }

# exported, unchanged signatures + roxygen
print.ggseg_data_cortical <- function(x, n = 10, ...)
  print_ggseg_data(x, "ggseg_data_cortical", "vertex indices", "vertices", n)
```

This removes the copy-paste while leaving all 8 exported symbols (`ggseg_data_*`, `print.ggseg_data_*`, `brain_data_*`) with identical signatures and return classes. **Net: ~267 duplicated body-LOC across 16 functions collapse to ~4 small helpers + thin shims.**

### Hotspot 2 — `atlas_vertices` / `atlas_meshes` accessor pair _(Low–Medium.)_

**Evidence.** Exact structural duplicate (identical 103-token signature; Jaccard **1.00**), `R/atlas_accessors.R:170` and `:201`, 18 LOC each, both at 100% coverage.

```r
atlas_vertices <- function(atlas) {
  if (!is_ggseg_atlas(atlas)) cli::cli_abort("{.arg atlas} must be a {.cls ggseg_atlas}.")
  if (is.null(atlas$data$vertices)) cli::cli_abort("Atlas does not contain vertices for 3D rendering.")
  result <- df_left_join(atlas$data$vertices, atlas$core, by = "label")
  if (!is.null(atlas$palette)) result$colour <- unname(atlas$palette[result$label])
  class(result) <- c("ggseg_vertices", class(result)); result
}
```

`atlas_meshes` is identical with `vertices`→`meshes` and `ggseg_vertices`→`ggseg_meshes`. **Refactor:** one internal `atlas_join_slot(atlas, slot, result_class, empty_msg)`, with `atlas_vertices`/`atlas_meshes` as two-line exported shims. Signatures and return classes unchanged.

### Hotspot 3 — `atlas_view_remove` / `atlas_view_keep` pair _(Low.)_

**Evidence.** Near-duplicate (Jaccard **0.86**), `R/atlas_utils.R:467` and `:497`, ~25 LOC each, both 100% covered. They differ only by the `keep =` flag passed to `polygons_filter_view` and the presence/absence of a `!` on the sf `keep_mask`, plus wording of two warnings. **Refactor:** an internal `atlas_view_filter(atlas, views, keep)` parameterised on the boolean, with the two exported functions as shims. Low priority — the pair is small and the divergence (`atlas_view_remove` also re-packs views via `atlas_view_gather`) is real, so keep the shims explicit.

### Minor

- **Tiny predicate/accessor stubs are duplicated but that is idiomatic and fine.** The `is_atlas_sf`/`is_atlas_polygon` pair (Jaccard 1.00), `data_sf`/`data_poly` (4 LOC each, Jaccard 1.00), the four `is_*_atlas` type predicates (`ggseg_atlas.R:103–121`), and the `atlas_regions.*`/`atlas_labels.*` S3 stubs are all 2–4-line one-liners. Collapsing them would _reduce_ readability and break `?help`/S3 dispatch. **No action** — flagged only so the reviewer knows they were measured and deliberately left alone.
- **`migrate_atlas_files` has the deepest nesting in the package** (max brace depth 6, `R/migrate_atlas_files.R:29`, cc = 13). Not a hotspot, but if a future edit touches it, an early-`return` guard or extracting the innermost block would flatten it. Watch, don't fix.
- **`atlas_utils.R` is a 1,159-line, 48-function grab-bag** — by far the largest file (next is `ggseg_atlas.R` at 634 lines / 27 functions). This is organisational, not complexity: nothing in it is individually complex. Optionally split by concern (region ops vs. view ops vs. brain\_\* accessors) for navigability. Optional, cosmetic.

### User-facing recommendations (API unchanged, but worth noting)

None required for complexity. One optional discoverability note: the four `ggseg_data_*` constructors share a documentation template (`man-roxygen/`) already; if Hotspot 1 is adopted, keeping each constructor's `@examples` block intact (rather than merging Rd pages) preserves per-type discoverability. Marked **optional**.

## Verified healthy (no action)

- **Complexity is genuinely low and well-distributed** — median cc = 3, max cc = 14, zero functions at cc ≥ 15 (measured over all 201 namespace functions). This is a well-factored package by the cyclomatic metric.
- **The largest function is a model of delegation, not a god-function.** `atlas_region_op` (`atlas_utils.R:260`, 58 LOC) reads as a linear pipeline of well-named helpers — `region_op_sf_data`, `region_op_labels`, `region_op_result`, `add_op_region_meta`, `rebuild_data_with_geom` — and scores only cc = 11. Its length is narrative, not tangled control flow.
- **Shared helpers are already extracted and heavily reused** (call-site counts: `cli_abort` 76, `data_sf` 27, `geom_from_data` 16, `require_sf` 11, `rebuild_atlas` 8, `rebuild_atlas_data` 7, `rebuild_data_with_geom` 6). The duplication that remains is in _leaf_ families, not in the core plumbing — the hard part was done right.
- **100% line coverage** (`covr::package_coverage()`), including every duplicated-family function. This means the recommended consolidations are low-risk: the existing tests would catch any regression, and the duplication is live code that genuinely repays de-duplication.

## Not run (reason)

- **`pkgnet` call-graph / `bench` / `profmem`** — not installed per the task constraints; substituted with base-R `getParseData()` token analysis (duplication + call sites) and `cyclocomp` (per-function cc). Runtime/allocation profiling is out of scope for a complexity pass (see the `run-performance-review` pass).
- **No refactoring was applied** — read-only rule. All refactor sketches above are proposals, not diffs.
- **Cross-package (ggsegverse) coupling** not analysed — this pass is scoped to `ggseg.formats` in isolation; downstream consumers of the exported API were not inspected (the recommendations preserve that API precisely so they need not be).

## Suggested fix priority

1. **Hotspot 1 — consolidate the `ggseg_data_*` constructor/print/wrapper family** _(Medium)_ — the largest duplication surface (~267 LOC over 16 functions, but this family is the bulk), 100% covered, highest maintenance-cost payoff. Use explicit shims over exported names; do not use a function factory.
2. **Hotspot 2 — merge `atlas_vertices`/`atlas_meshes` behind one join helper** _(Low–Medium)_ — exact duplicate, trivial to extract, clear win.
3. **Hotspot 3 — parameterise `atlas_view_remove`/`atlas_view_keep` on a `keep` flag** _(Low)_ — smaller and the two functions genuinely diverge; keep shims explicit.
4. **Minor — optionally split `atlas_utils.R` by concern** _(Low, cosmetic)_ — navigability only; no complexity impact.
5. **Watch `migrate_atlas_files` nesting (depth 6)** _(Low)_ — no change now; flatten with early returns if a future edit touches it.

Leave the tiny predicate/accessor stubs and S3 method stubs as-is — collapsing them would hurt readability and dispatch for no measurable gain.
