---
title: "ggseg.formats 0.0.4 — AI-Assisted Dependency Review"
author: "Athanasia Mo Mowinckel (AI-assisted, Claude Code / Opus 4.8)"
date: 2026-07-02
format:
  html:
    toc: true
    toc-depth: 3
    embed-resources: true # self-contained: attachable to the review issue
execute:
  eval: false # the report records results; it is not re-run
---

# Prompt

> Analyse the dependencies of this R package and produce a report I can attach to
> an rOpenSci software-review issue. Tell me which dependencies are genuinely
> worth removing, and back every recommendation with evidence.
>
> The package is a self-contained working tree of ggseg.formats (brain-atlas
> geometry helpers; Imports: cli, lifecycle, rlang, sfheaders). pkgnet is not
> installed — use base-R equivalents (`tools::package_dependencies`, `utils`) for
> the recursive dependency tree and reverse-dependency analysis.

# Skill

This pass was driven by the `run-dependency-review` skill (rOpenSci skills
collection, `skills/run-dependency-review/SKILL.md`), which enforces one governing
insight and five ground rules, reproduced here verbatim so the report is
self-contained:

> **Prune the tree, not the count.** Only recommend removing a dependency when
> (a) it is reachable **only** through this package's own direct import (a prunable
> leaf), and (b) its usage is light enough to replace without losing correctness or
> readability. Removing a package that `httr2`/`dplyr`/etc. also pull in is cosmetic.
>
> **Count real usage.** Base recommendations on how many times, and where, each
> imported function is actually called — not on reputation.
>
> **Base-R replacement must preserve behaviour and readability.** A two-line helper
> that reads worse than the dependency is not a win.
>
> **Respect the maintainer's stated preferences** (e.g. a deliberate tidyverse or
> zero-dependency stance).
>
> **Read-only.** Don't edit `DESCRIPTION` or `R/` to prove a point; propose, with
> evidence.

The report follows the shared `run-*` report template.

# Report

## Method

Reproducible steps, all read-only:

- **Tools/versions:** R 4.5.2. Dependency tree built with
  `tools::package_dependencies(recursive = TRUE, which = c("Depends","Imports","LinkingTo"))`;
  reverse-dependency edges with the same function at `recursive = FALSE`; package
  priorities from `utils::installed.packages()[, "Priority"]`. pkgnet was not
  installed, so base-R equivalents were used as instructed.
- **Usage counts:** `grep -rn` over `R/*.R` for each `pkg::` qualified call plus the
  one non-`::` import (`rlang::"%||%"`, declared via `importFrom` in `NAMESPACE`).
- **Package versions** reflect what was installed at review time; see Caveat.
- **No package files were modified.** All inspection was via `Read`, `grep`, and
  `Rscript` invoking already-installed tooling. `DESCRIPTION`, `NAMESPACE`, and
  `R/` are untouched.

## Headline

**Green, with one deliberately-declined cut.** ggseg.formats declares four
Imports — `cli`, `lifecycle`, `rlang`, `sfheaders` — and the whole install tree is
only **8 non-base nodes** (the four imports plus `geometries`, `Rcpp`, and base
`methods`/`utils`). There is **no clear win here**: three of the four imports are
either used pervasively or pinned by a package that must stay, and the fourth
(`sfheaders`) is the _only_ thing giving the package an sf-free geometry path — its
removal would either re-introduce the heavy `sf` (GDAL/GEOS/PROJ) system stack or
force a hand-rolled MULTIPOLYGON assembler. The single genuinely defensible change
is **cosmetic, not a prune**: drop `cli` and `rlang` from `Imports` in `DESCRIPTION`
because `lifecycle` already pins both (removing them changes nothing on disk). Net
recommendation: **keep all four**; optionally tidy the two redundant direct-import
declarations. The dependency footprint is already close to minimal for what the
package does.

## Findings

### Summary table

| Dep         | Uses (call sites)                                                      | Functions used                                                                                                        | Recursive deps it adds                       | Prunable leaf?                                 | Base-R replacement                                                               | Verdict                   |
| ----------- | ---------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- | -------------------------------------------- | ---------------------------------------------- | -------------------------------------------------------------------------------- | ------------------------- | ----------------------- | -------------------------------- | --- | --------------------------------------- | ------------------------------ | -------- |
| `cli`       | 145 (`cli::` across 12 files) + it is a leaf's transitive dep          | `cli_abort`, `cli_warn`, `cli_inform`, `cli_alert_*`, `cli_h1/h2`, `cli_rule`, `cli_text`, `col_green/red`, `symbol$` | none new (`utils` only)                      | **No** — pinned by `lifecycle`                 | infeasible at 145 sites; loses `{.arg}`/`{.cls}` semantics                       | **Keep**                  |
| `lifecycle` | 15 (`deprecate_warn` ×12, `signal_stage`, `badge`, plus roxygen badge) | `deprecate_warn`, `signal_stage`, `badge`                                                                             | `cli`, `rlang` (both already pinned/present) | No (adds nothing over cli+rlang)               | none — it _is_ the deprecation contract                                          | **Keep**                  |
| `rlang`     | 2 `rlang::is_installed` + 7 `%                                         |                                                                                                                       | %` (imported)                                | `is_installed`, `%                             |                                                                                  | %`                        | none new (`utils` only) | possible (`requireNamespace`; `% |     | %` native only R≥4.4) but pinned anyway | **No** — pinned by `lifecycle` | **Keep** |
| `sfheaders` | 3 (`sf_multipolygon` ×1 call + 2 doc refs)                             | `sf_multipolygon`                                                                                                     | **`geometries`, `Rcpp`** (compiled/C++)      | **Yes** — only import reaching Rcpp/geometries | only via re-adding heavy `sf`, or a non-trivial hand-rolled multipolygon builder | **Keep (Tier 3 at best)** |

### The tree (evidence)

Recursive dependencies (`Depends`+`Imports`+`LinkingTo`) contributed by each direct
import:

```
cli        -> 1 recursive dep : utils
lifecycle  -> 3 recursive deps: cli, rlang, utils
rlang      -> 1 recursive dep : utils
sfheaders  -> 4 recursive deps: geometries, methods, Rcpp, utils
```

Full non-base install tree beyond the four imports: **geometries, Rcpp** (plus base
`methods`, `utils`). Total non-base nodes: **8**. Priorities confirm only `methods`
and `utils` are base; `geometries` and `Rcpp` are CRAN packages, and `Rcpp` +
`geometries` are compiled (C++), so they are the heaviest part of the footprint.

Reverse-dependency analysis within the tree (who pulls each transitive package):

```
geometries <- pulled by: sfheaders
Rcpp       <- pulled by: geometries, sfheaders
utils      <- pulled by: cli, Rcpp, rlang
methods    <- pulled by: Rcpp
```

The load-bearing fact for the whole review: **`lifecycle` Imports `cli` and
`rlang`** (`tools::package_dependencies("lifecycle")` → `cli`, `rlang`). So while
`cli` and `rlang` appear as direct `Imports` in `DESCRIPTION`, they are _also_
pinned transitively by `lifecycle`. Dropping either as a direct import prunes
**zero** nodes from the install tree.

### Tier 1 — clear wins

_None._ There is no direct import whose removal both prunes a node and is safe to
replace. (This is a good outcome, not a gap — the tree is already lean.)

### Tier 2 — worth doing

**T2-1. Remove `cli` and `rlang` from `Imports` in `DESCRIPTION` — bookkeeping only.**
_(Low.)_ Because `lifecycle` pins both (`reverse-dep` evidence above), listing them
as direct imports is redundant. Two arguments cut against acting, and they are
strong:

- **It prunes nothing** — `cli` (145 sites) and `rlang` (`%||%`, `is_installed`) are
  used directly throughout `R/`. rOpenSci and `R CMD check` both expect a package to
  declare every namespace it references directly, regardless of transitive pinning.
  Removing them would trigger `checking dependencies ... undeclared imports` NOTEs.
- Therefore this is **not** a recommended change. It is listed here only to record
  that the redundancy was examined and is _correct_ to keep: direct use ⇒ direct
  declaration. (See "Keep" below.)

### Tier 3 — defer (real benefit, large rewrite)

**T3-1. `sfheaders` is the only import pulling compiled code (`Rcpp`, `geometries`).**
_(Medium.)_ On pure footprint grounds it is the highest-value target: it is the sole
prunable leaf and the only path to the two C++ dependencies. But usage and design
argue strongly for keeping it:

- **Single real call site:** `R/atlas_polygons.R:98`, `polygons_to_sf()` uses
  `sfheaders::sf_multipolygon()` to assemble a MULTIPOLYGON sf data frame from a
  flat table, keyed by `multipolygon_id`/`polygon_id`/`linestring_id` with
  `keep = TRUE`. This is non-trivial nested-ring geometry construction, not a
  one-liner.
- **It is what makes the package sf-optional.** The package deliberately moved `sf`
  to `Suggests` (guarded everywhere by `require_sf()`/`has_sf()` in
  `R/sf_availability.R`) and documents (`R/atlas_polygons.R:69-73`) that
  _"sfheaders is pure Rcpp and has no GDAL/GEOS/PROJ system dependencies, so the
  conversion itself does not require a full sf installation."_ Replacing `sfheaders`
  with `sf::st_*` would re-introduce the entire GDAL/GEOS/PROJ system-library stack
  as a hard requirement — a far heavier footprint than `Rcpp` + `geometries`.
- The only footprint-reducing alternative is a hand-written MULTIPOLYGON builder
  emitting `sfg`/`sfc` structures, which duplicates well-tested C++ geometry code in
  R for one call site — a correctness and maintenance liability that violates the
  "must preserve behaviour and readability" rule.

**Verdict: defer / keep.** Cutting `sfheaders` trades two small compiled CRAN
packages for the much larger `sf` system stack, or for bespoke geometry code. That
is a net loss.

### Keep — removal buys nothing

- **`cli` — used at 145 sites; pinned by `lifecycle`.** Pervasive across 12 files for
  all user-facing conditions and `print` methods, relying on cli's inline markup
  (`{.arg}`, `{.cls}`, `{.field}`, `{.val}`, pluralisation `{?s}`). Replacing with
  `stop()`/`warning()`/`message()` at 145 sites would lose semantics and readability,
  and would still not prune cli (pinned by lifecycle). **Keep.**
- **`rlang` — 9 uses; pinned by `lifecycle`.** `%||%` (7×, imported via
  `importFrom(rlang, "%||%")` in `NAMESPACE`) and `is_installed()` (2×, in
  `require_sf()`/`has_sf()`). Base equivalents exist (`requireNamespace(..., quietly
= TRUE)`; native `%||%`), **but** native `%||%` only exists in R ≥ 4.4.0 while
  `DESCRIPTION` declares `Depends: R (>= 4.1.0)` — so it cannot be relied on without
  bumping the floor. Either way rlang stays in the tree via lifecycle, so any swap
  prunes nothing. **Keep.**
- **`lifecycle` — 15 deliberate uses.** `deprecate_warn()` ×12 (`R/atlas_utils.R`,
  `R/coercion.R`, `R/ggseg_atlas.R`, `R/atlas_polygons.R`, `R/ggseg_atlas_data.R`,
  `R/atlas_convert.R`), plus `signal_stage("superseded", …)` and a
  `lifecycle::badge()` in roxygen. This is an intentional, maintained deprecation
  contract — exactly what lifecycle is for. Removing it would mean re-implementing
  staged deprecation by hand. **Keep.**

## Verified healthy (no action)

- **Minimal, well-chosen tree.** 8 non-base nodes for a package that ships four
  atlases and a geometry API is lean. Only two nodes are compiled (`Rcpp`,
  `geometries`), and both arrive through a single, justified import.
- **sf-optional design is exemplary.** `sf` is correctly in `Suggests`, and every
  runtime `sf::` call (29 references, all in `R/atlas_utils.R` and friends) sits
  behind a `require_sf()` / `has_sf()` guard (`R/sf_availability.R`), with a
  documented polygon fallback via `as_polygon_atlas()`. This is precisely how
  rOpenSci wants heavy system-dependency packages handled.
- **Own base-R data-frame compat layer.** `R/compat_dataframe.R` defines
  `as_tbl`, `df_bind_rows`, `df_nest`, `df_unnest`, `df_distinct`, `df_left_join` —
  the package avoids `dplyr`/`tidyr` deliberately, keeping the tree free of the
  tidyverse. Respect this stated zero-tidyverse stance; do not suggest adding them.
- **No undeclared runtime dependencies.** The only "extra" namespaces referenced are
  `ggsegExtra::` (2×) — both in roxygen `@description` cross-references in
  `R/atlas_convert.R`, not executable code — so no missing `Imports`/`Suggests`
  entry is needed. Base-package imports (`stats`, `utils`, `graphics`, `grDevices`)
  are all declared via `importFrom` in `NAMESPACE`.

## Not run (reason)

- **pkgnet `DependencyReporter`** — not installed; substituted with
  `tools::package_dependencies()` + manual reverse-dep edge analysis per the task
  instructions. Node/edge counts above are equivalent for this purpose.
- **Live CRAN/Bioconductor size or install-time benchmarking** — out of scope for a
  static dependency pass; footprint judgements are based on tree membership and
  compiled-vs-pure-R status, not measured install bytes.
- **`R CMD check`** — not run; the redundant-import observation (T2-1) is based on
  reverse-dep evidence, not a check log. No package files were modified.

## Suggested fix priority

1. **(Low / optional) Do NOT remove `cli` or `rlang` from `Imports`.** They are used
   directly (145 and 9 sites) so they must stay declared; the fact that `lifecycle`
   also pins them means their removal would prune nothing _and_ would produce
   undeclared-import NOTEs. Recorded here so the reviewer knows the redundancy was
   examined and is correct. (Finding T2-1.)
2. **(Medium / defer) Keep `sfheaders`.** It is the only prunable leaf and the only
   compiled-code path, but it is precisely what keeps the package sf-optional;
   removing it re-introduces the far heavier `sf`/GDAL stack or bespoke geometry
   code. Revisit only if the single `sf_multipolygon()` call is ever dropped.
   (Finding T3-1.)
3. **(None) `lifecycle` — keep as-is.** Deliberate deprecation contract, 15 sites.

**Bottom line for the review issue:** there is no dependency here genuinely worth
removing. The tree is minimal, the one compiled import (`sfheaders`) is load-bearing
for the sf-optional design, and the other three are either pervasive or pinned by
`lifecycle`. Recommend accepting the dependency set as declared.

## Caveat

Tree membership and pinning relationships reflect the package **versions installed
at review time** (R 4.5.2; `lifecycle` currently Imports `cli` + `rlang`). If a
future `lifecycle` drops its `cli`/`rlang` imports, the "pinned" reasoning for those
two would change — re-run `tools::package_dependencies("lifecycle")` before acting.
