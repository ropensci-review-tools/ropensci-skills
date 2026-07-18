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
  eval: false # a record of a run, not a live notebook
---

# Prompt

> Analyse the dependencies of this R package and produce a report I can attach to an rOpenSci software-review issue. Tell me which dependencies are genuinely worth removing, and back every recommendation with evidence.
>
> The package is a self-contained working tree (ggseg.formats, brain-atlas geometry helpers; Imports: cli, lifecycle, rlang, sfheaders). R is available. pkgnet is NOT installed — use base-R equivalents (`tools::package_dependencies(recursive=TRUE)`, utils) for the recursive dependency tree and reverse-dependency analysis. Do NOT modify the package tree.

# Skill

Driven by the `run-dependency-review` skill (rOpenSci-skills collection), the dependency pass of `run-package-review`. Its governing rule, reproduced verbatim:

> **Prune the tree, not the count.** Only recommend removing a dependency when (a) it is reachable **only** through this package's own direct import (a prunable leaf), and (b) its usage is light enough to replace without losing correctness or readability. Removing a package that `httr2`/`dplyr`/etc. also pull in is cosmetic.

> **Count real usage.** Base recommendations on how many times, and where, each imported function is actually called — not on reputation.

> **Base-R replacement must preserve behaviour and readability.** A two-line helper that reads worse than the dependency is not a win.

Report skeleton from the shared template at `run-package-review/references/report-template.md`. `pkgnet` was unavailable, so the recursive tree and reverse-dependency map were built with base R (`tools::package_dependencies(recursive = TRUE)`), per the task instructions.

# Report

## Method

Reproducible; run from the package root with **R 4.5.2**.

- **Recursive dependency tree + reverse-dependency map:** `tools::package_dependencies(recursive = TRUE, which = c("Depends","Imports","LinkingTo"))` over each of the four direct imports, then an edge list built per node to derive, for every package in the tree, the set of parents that require it. Base/recommended packages excluded via `installed.packages(priority = "base")`.
- **Footprint:** `installed.packages()` for `NeedsCompilation`, version, and on-disk size (`file.info()` sum over the installed package directory).
- **Usage counts:** `grep -rEno "<pkg>::[A-Za-z0-9_.]+" R/` across all 18 `R/*.R` files, plus `importFrom` inspection of `NAMESPACE`, plus a scan for unqualified `library()`/`requireNamespace()` and for the imported infix `%||%`.
- **Base-R / sf feasibility:** each call site read in context to judge whether removal preserves behaviour and readability, and whether the call sits on an `sf`-guarded path.
- Tools: `tools`, `utils`, base R only. `pkgnet` not installed (base-R equivalents used as instructed).
- **No package files were modified.** DESCRIPTION, NAMESPACE, and `R/` were read only; all scratch scripts were written to `/tmp`.

## Headline

**Green, with one worthwhile-but-optional cut.** The dependency footprint is already lean and honest: exactly four imports, all genuinely used, and **only two of the four are prunable leaves** (`lifecycle`, `sfheaders`) — `cli` and `rlang` are pinned by `lifecycle`, so removing them prunes nothing. The single high-value candidate is **`sfheaders`**: it is used at just **3 call sites** (one function, `sfheaders::sf_multipolygon`) yet it is the _only_ import that drags in a compiled transitive subtree (`sfheaders` + `geometries` + `Rcpp`, all `NeedsCompilation=yes`, **~23 MB installed combined**). Whether it is worth removing hinges on one deliberate design point (see Tier 2). `lifecycle`, `cli`, `rlang` should all stay.

## Findings

### Recursive dependency tree (non-base nodes)

`tools::package_dependencies(recursive = TRUE)` over the four imports yields **6 non-base packages** total:

```
cli        -> utils
lifecycle  -> cli, rlang, utils
rlang      -> utils
sfheaders  -> geometries, methods, Rcpp, utils
```

Full non-base tree (6 nodes): `cli, geometries, lifecycle, Rcpp, rlang, sfheaders`. No other tree exists — `sf` is **Suggests**, not Imports, so GDAL/GEOS/PROJ are never pulled by an install of ggseg.formats.

### Reverse-dependency map (who requires each node)

```
cli         <- ggseg.formats, lifecycle
geometries  <- sfheaders
lifecycle   <- ggseg.formats
Rcpp        <- geometries, sfheaders
rlang       <- ggseg.formats, lifecycle
sfheaders   <- ggseg.formats
```

Prunability of the four direct imports:

| Import      | Prunable leaf?  | Why                                                                                                                                                                                                                                  |
| ----------- | --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `cli`       | **No — PINNED** | also required by `lifecycle` (which stays). Dropping the direct import prunes nothing.                                                                                                                                               |
| `rlang`     | **No — PINNED** | also required by `lifecycle`. Prunes nothing.                                                                                                                                                                                        |
| `lifecycle` | **Yes — leaf**  | reachable only via ggseg.formats. But it _pins_ cli+rlang, so removing it does **not** shrink the tree (cli/rlang stay as its parents… wait — it is their only _extra_ parent; ggseg.formats imports them directly too). See "Keep". |
| `sfheaders` | **Yes — leaf**  | reachable only via ggseg.formats; removing it prunes `sfheaders` **+ geometries + Rcpp** — nothing else in the tree needs them (verified: none of cli/lifecycle/rlang's recursive deps include any of the three).                    |

### Footprint (installed size, compiled?)

| Package    | Version | Compiled                                  | Installed size |
| ---------- | ------- | ----------------------------------------- | -------------- |
| sfheaders  | 0.4.5   | yes                                       | **8,728 KB**   |
| geometries | 0.2.5   | yes (transitive via sfheaders)            | **5,316 KB**   |
| Rcpp       | 1.1.1   | yes (transitive via sfheaders/geometries) | **9,105 KB**   |
| cli        | 3.6.6   | yes                                       | 2,321 KB       |
| rlang      | 1.2.0   | yes                                       | 2,921 KB       |
| lifecycle  | 1.0.5   | no (pure R)                               | 257 KB         |

The `sfheaders → geometries → Rcpp` chain is **~23 MB and three compiled packages** — by far the heaviest thing ggseg.formats requires, and it exists to serve 3 call sites.

### Per-import usage counts

| Import      | Call sites | Distinct functions used                                                                                                 | Where                                                                        |
| ----------- | ---------- | ----------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------- | --------------------------------------- | --- | ----- | --------------------------------------------------------------- | --- | --- |
| `cli`       | **147**    | `cli_abort`, `cli_warn`, `cli_inform`, `cli_alert_*`, `cli_text`, `cli_h1/h2`, `cli_rule`, `symbol`, `col_red/green`, … | all over `R/` (validation, atlas_utils, atlas_convert, print methods)        |
| `lifecycle` | **15**     | `deprecate_warn` (13), `signal_stage` (1), `badge` (1)                                                                  | atlas_utils, coercion, ggseg_atlas(\_data), atlas_polygons, atlas_convert    |
| `rlang`     | **2 + 7**  | `is_installed` (2); infix `%                                                                                            |                                                                              | %`(7, imported via`importFrom(rlang, "% |     | %")`) | sf_availability.R (`is_installed`); coercion, atlas_convert (`% |     | %`) |
| `sfheaders` | **3**      | `sf_multipolygon` only                                                                                                  | atlas_polygons.R:69/98, atlas_polygon_converters.R:69 (via `polygons_to_sf`) |

### Summary table

| Dep           | Uses  | Functions used                            | Prunable leaf?                                                       | Base-R / sf replacement                                                                                                                            | Verdict                                          |
| ------------- | ----- | ----------------------------------------- | -------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------ | -------------------------------------------------------------------- | --- | ----------------------------------------------------------------------- | -------------------------------------------------------- |
| **cli**       | 147   | ~12 cli\_\* helpers, glued interpolation  | No (pinned by lifecycle)                                             | Would require re-implementing `{.arg}`/`{.cls}` glue-style interpolation across 147 sites → net loss of readability + still on disk                | **Keep**                                         |
| **rlang**     | 2 + 7 | `is_installed`; `%                        |                                                                      | %`                                                                                                                                                 | No (pinned by lifecycle)                         | `is_installed` → `requireNamespace(..., quietly=TRUE)` (trivial); `% |     | %` is in base R **only from R 4.4.0**, but DESCRIPTION allows R ≥ 4.1.0 | **Keep** (pinned; removing direct import prunes nothing) |
| **lifecycle** | 15    | `deprecate_warn`, `signal_stage`, `badge` | Yes (leaf) but pure-R & 257 KB                                       | `deprecate_warn` gives a well-known, standards-endorsed deprecation UX; hand-rolling 13 sites is a readability/consistency loss                    | **Keep**                                         |
| **sfheaders** | 3     | `sf_multipolygon`                         | **Yes** — prunes sfheaders+geometries+Rcpp (~23 MB, 3 compiled pkgs) | Replaceable by `sf::st_multipolygon()/st_sf()` **on the sf-guarded paths**; one path (`as_sf_atlas`) is _deliberately_ sf-free — that is the catch | **Tier 2 — worth doing, with a design decision** |

## Verified healthy (no action)

- **No undeclared dependencies.** Every `pkg::` in `R/` resolves to a declared Imports, a base package, or a doc-only mention. The only non-declared namespaces that appear (`ggsegExtra::` ×2, `ggseg.formats::` ×2) are all inside roxygen `#'` comments / `\dontrun{}` examples, not executable code (`atlas_convert.R:12-13`, `migrate_atlas_files.R:27`, `atlas_polygon_converters.R:49`). The one `library(sf)` (`atlas_polygon_converters.R:84`) is inside a `\dontrun{}` example block.
- **`sf` is correctly in Suggests, not Imports**, and gated by an `is_installed`-based guard (`require_sf()` / `has_sf()` in `sf_availability.R`), used at ~11 call sites before any `sf::` call. This is exactly the sf-optional pattern rOpenSci wants and keeps GDAL/GEOS/PROJ out of the hard dependency set. 29 `sf::` call sites, all guarded.
- **Four imports, all real.** No dead weight: even the lightest-used import (`sfheaders`, 3 sites) is genuinely called. There is nothing to remove purely for being unused.
- **`rlang` is used minimally and idiomatically** (`is_installed`, `%||%`) — no over-reliance on a large framework.

## Not run (reason)

- **`pkgnet::DependencyReporter`** — not installed; substituted with `tools::package_dependencies(recursive = TRUE)` + a hand-built reverse-dependency edge map, per the task's explicit instruction. Node/edge counts reported above.
- **`covr` coverage of the replacement paths** — out of scope for a dependency pass; no code was changed, so nothing to cover.
- **Reverse dependencies of ggseg.formats itself** (i.e. which ggsegverse packages import it) — not queried; the package is not on CRAN and its reverse users live in the ggsegverse GitHub org, outside this working tree. This does not affect the _forward_ prune analysis above.
- **No install/build was performed**; sizes are read from the already-installed library.

## Suggested fix priority

Ordered highest-impact first.

### Tier 1 — clear wins

_None._ No import is both prunable and free-to-replace. The one prunable-and-heavy candidate (`sfheaders`) carries a real design trade-off, so it belongs in Tier 2, not Tier 1.

### Tier 2 — worth doing (moderate effort + a design decision) — `sfheaders`

**The case for removal (evidence).** `sfheaders` is a **prunable leaf** used at exactly **3 call sites**, all of a single function `sf_multipolygon`, all funnelled through the internal `polygons_to_sf()` helper (`atlas_polygons.R:98`). Removing it prunes **three compiled packages** — `sfheaders` (8.7 MB) + `geometries` (5.3 MB) + `Rcpp` (9.1 MB), **~23 MB** — from every install of ggseg.formats. The reverse-dependency map confirms nothing else in the tree needs them. This is the single largest footprint reduction available anywhere in the dependency set.

**The natural replacement.** Every consumer of a `polygons_to_sf()` result immediately hands it to `sf` (`atlas_sf()` at `atlas_accessors.R:106` then `sf::st_as_sf` at :111; `region_op_sf_data()` at `atlas_utils.R:753`; `as.data.frame.ggseg_atlas` at `ggseg_atlas.R:320`). All of these are reached only _after_ a `require_sf()` guard, so **`sf` is guaranteed installed on those paths** — meaning `sf::st_multipolygon()` + `sf::st_sf()` are available and could build the identical MULTIPOLYGON object without `sfheaders`. On those paths the swap is behaviour-preserving.

**The catch (why this is Tier 2, not Tier 1).** One public entry point, **`as_sf_atlas()`**, calls `polygons_to_sf()` at `atlas_polygon_converters.R:101` **without a preceding `require_sf()`** — and its roxygen (`:69-73`) states this deliberately: _"sfheaders is pure Rcpp with no GDAL/GEOS/PROJ dependencies, so the conversion itself does not require a full sf installation."_ So `sfheaders` is a **considered choice**: it lets the polygon→sf conversion run even when `sf` (and its system libraries) is absent. Dropping `sfheaders` in favour of `sf::st_*` would move that one conversion behind the `sf` guard — a small behaviour change (you'd then need `sf` installed to _produce_ an sf object, which is arguably reasonable since the output is an sf object anyway).

**Recommendation for the author (respect the maintainer's stated preference).** This is a judgement call the maintainer should make explicitly, not a defect:

- If the "build sf objects without sf installed" capability is intentional and worth ~23 MB of compiled transitive deps for downstream/CI convenience → **keep `sfheaders`** and document that rationale (the roxygen already half-does).
- If not → replace the single `sfheaders::sf_multipolygon` call in `polygons_to_sf()` with `sf::st_multipolygon()`/`sf::st_sf()`, add a `require_sf()` guard at the top of `polygons_to_sf()` (or in `as_sf_atlas()` before line 101), and drop `sfheaders` from Imports. Net: −1 direct import, **−3 compiled packages / ~23 MB** off the install tree, at the cost of one guarded behaviour change and a modest rewrite of one internal helper.

Effort: low-moderate (one helper + one guard + tests for the `as_sf_atlas` no-sf path). Payoff: the largest footprint cut in the package.

### Tier 3 — defer

_None._ No candidate needs a large rewrite.

### Keep — removal buys nothing

- **`cli` (147 uses).** Pinned by `lifecycle` regardless, so a direct-import removal prunes nothing (it stays on disk as lifecycle's dep). Independently, replacing 147 `cli_abort/warn/inform` sites with `stop()/warning()` would lose the `{.arg}`/`{.cls}`/`{.fn}` semantic markup and message consistency for zero footprint gain. **Keep.**
- **`rlang` (2 + 7 uses).** Pinned by `lifecycle` — cutting the direct import prunes nothing. `is_installed` maps cleanly to `requireNamespace()`, but `%||%` is only in base R from **R 4.4.0** while DESCRIPTION targets **R ≥ 4.1.0**; dropping rlang would either force an R-version bump or a hand-rolled infix. Not worth it while rlang is pinned anyway. **Keep.**
- **`lifecycle` (15 uses).** A prunable leaf, but pure-R and only 257 KB, and it provides the standards-endorsed deprecation UX (`deprecate_warn` ×13, plus `badge`/`signal_stage`). Removing it would also remove the _reason_ cli and rlang are pinned — but since ggseg.formats imports cli and rlang directly and heavily anyway, that yields no tree reduction. Hand-rolling consistent deprecation across 13 sites is a net readability loss. **Keep.**

## Recommendation (shortlist)

1. **Decide on `sfheaders`** (Tier 2). It is the only cut that meaningfully shrinks the install tree (−3 compiled packages, ~23 MB). Removal is technically clean on the `sf`-guarded paths; the only trade-off is the deliberate "convert-without-sf" behaviour of `as_sf_atlas()`. Make the call explicitly and document it either way.
2. **Keep cli, rlang, lifecycle.** cli and rlang are pinned by lifecycle (removal prunes nothing); lifecycle is tiny and provides standards-aligned deprecation. None is worth removing.
3. **No hygiene issues to fix** — no undeclared or unused imports; `sf` is correctly optional.

## Caveat

Tree membership, versions, `NeedsCompilation` flags, and installed sizes reflect the packages installed at review time (R 4.5.2; cli 3.6.6, lifecycle 1.0.5, rlang 1.2.0, sfheaders 0.4.5, geometries 0.2.5, Rcpp 1.1.1). Recursive-dependency edges can change as upstream `DESCRIPTION` files change (e.g. if a future `lifecycle` drops `cli`/`rlang`, the pinning analysis for those two would shift). The `%||%`-in-base-R note assumes the stated `R (>= 4.1.0)` floor. Reverse dependencies of ggseg.formats within the ggsegverse were not enumerated and do not affect the forward prune analysis.
