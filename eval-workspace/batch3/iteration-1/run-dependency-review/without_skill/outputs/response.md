# Dependency review: `ggseg.formats` (v0.0.4)

Prepared for the rOpenSci software-review issue. Analysis covers the four declared
`Imports`: **cli, lifecycle, rlang, sfheaders**. Every recommendation below is backed by
usage counts from `R/` and by the recursive dependency closure computed from the installed
package metadata.

## TL;DR

The dependency list is already lean and well-justified. **No dependency is strongly worth
removing.** The single defensible candidate for removal is **rlang**, and even that is a
marginal call. Full reasoning and evidence follow.

| Dep       | Direct calls in `R/` | Files | Extra non-base pkgs it pulls in           | Verdict                                   |
| --------- | -------------------: | ----: | ----------------------------------------- | ----------------------------------------- | ------------------------- | ------------------------------- |
| cli       |                  147 |    13 | **0** (only base `utils`)                 | **Keep** — heavily used, zero cost        |
| lifecycle |                   15 |     6 | **0** new (`cli`, `rlang` already direct) | **Keep** — free given cli+rlang           |
| rlang     |      2 (`::`) + 7 `% |       | %`                                        | 3                                         | **0** (only base `utils`) | **Removable, but low priority** |
| sfheaders |                    3 |     2 | Rcpp, geometries (+ LinkingTo)            | **Keep** — core to the sf-optional design |

Combined, the whole `Imports` block pulls in only **2** extra non-base packages
transitively: `Rcpp` and `geometries` (both via sfheaders). cli, lifecycle and rlang add
**nothing** beyond themselves.

---

## Method

- Usage counted with `grep` over `R/` for `pkg::fun` calls and the imported `%||%` operator.
- Recursive dependency closure (Imports + Depends + LinkingTo) computed from
  `installed.packages()` and reduced against the base-priority package set.
- Test-side usage checked separately across `tests/testthat/`.

Recursive **non-base** closure per dependency:

```
cli        -> (none)                 # Imports: utils only
lifecycle  -> cli, rlang             # both are already direct Imports of ggseg.formats
rlang      -> (none)                 # Imports: utils only
sfheaders  -> Rcpp, geometries       # LinkingTo: Rcpp, geometries
-----------------------------------------------------------------
Union of all four (non-base): Rcpp, geometries   (2 packages total)
```

This is an unusually cheap dependency graph. There is no bloat here.

---

## Per-dependency findings

### cli — KEEP (do not touch)

- **Usage:** 147 direct `cli::` calls across 13 of the 18 R files. Breakdown:
  `cli_abort` (78), `cli_warn` (25), `cli_text` (21), `cli_inform` (5), `cli_h2` (5),
  `cli_rule` (4), `cli_alert_info` (3), `symbol` (2), plus `col_red`, `col_green`,
  `cli_h1`, `cli_alert_success`.
- **Cost:** zero non-base transitive deps (`Imports: utils`). cli is effectively a
  foundational package in the R ecosystem and is already a transitive dep of most
  tidyverse/r-lib tooling.
- **Verdict:** removing it would mean re-implementing structured error/condition
  formatting by hand for 100+ call sites, at no dependency saving. Keep. This is exactly
  the kind of dependency rOpenSci encourages (`cli` for user-facing messages).

### lifecycle — KEEP (free given the rest)

- **Usage:** 15 calls in 6 files: `deprecate_warn` (13), `signal_stage` (1),
  `badge` (1, in a roxygen `\Sexpr`/inline-R doc block at `R/atlas_convert.R:6`).
- **Cost:** its only Imports are `cli` and `rlang` — **both already direct Imports of
  this package.** So lifecycle adds **zero** new packages to the install graph.
- **Why not remove it:** the 13 `deprecate_warn` sites implement the package's
  deprecation policy (legacy `brain_atlas` -> `ggseg_atlas` migration, released `sf`
  argument, etc.). Hand-rolling `.Deprecated`/`warning()` equivalents would lose the
  once-per-session throttling, structured advice, and the standard rOpenSci/tidyverse
  deprecation UX — for no dependency win.
- **Verdict:** Keep. It is the correct tool for the job and costs nothing extra.

### rlang — REMOVABLE, but low priority (the only real candidate)

This is the one dependency where removal is technically defensible.

- **Usage is minimal:** only two surfaces.
  1. `rlang::is_installed("sf")` — 2 calls, both in `R/sf_availability.R`
     (`require_sf()` and `has_sf()`), the guards for the sf-optional design.
  2. `%||%` (null-coalescing operator), imported via
     `#' @importFrom rlang %||%` — 7 uses in `R/coercion.R` (2) and `R/atlas_convert.R` (5).
- **Cost:** zero non-base transitive deps (`Imports: utils`).

**Base-R replacements exist:**

- `rlang::is_installed(pkg)` -> `requireNamespace(pkg, quietly = TRUE)`. Straightforward,
  behaviourally equivalent for this use.
- `%||%` -> base R has provided `%||%` natively **since R 4.4.0**. The package currently
  declares `Depends: R (>= 4.1.0)`. So dropping the rlang import means either (a) defining
  a one-line internal `%||%`, or (b) bumping the R floor to `>= 4.4.0` and using the base
  operator. Bumping the floor is the cleaner long-term fix but is a policy decision (it
  narrows supported R versions).

**Evidence-based recommendation:** rlang can be removed with a ~3-line change (internal
`%||%` + `requireNamespace`). However:

- The _saving is essentially nil_ — rlang has no onward non-base dependencies and is
  already installed almost everywhere as a transitive dep.
- Removing it slightly increases maintenance surface (you now own a `%||%` shim / an R
  version bump).

So this is a **"you may, not you must."** If the goal is the smallest possible declared
`Imports` list for review optics, drop rlang. If the goal is the smallest _install
footprint_, removing rlang changes nothing. I would only remove it if the maintainer also
wants to raise the R floor to 4.4.0 for the native `%||%`; otherwise the shim is churn for
no benefit.

### sfheaders — KEEP (load-bearing for the sf-optional architecture)

- **Usage:** 3 calls, all `sfheaders::sf_multipolygon()`; the functional one is in
  `polygons_to_sf()` at `R/atlas_polygons.R:98` (the other two are doc references at
  `R/atlas_polygons.R:69` and `R/atlas_polygon_converters.R:69`).
- **Cost:** this is the _only_ dependency that adds packages to the closure — `Rcpp` and
  `geometries` (declared via `LinkingTo: geometries, Rcpp`).
- **Why it is deliberately chosen (and should stay):** the package's central design
  goal is to make **`sf` optional** (moved to `Suggests`; see `R/sf_availability.R` and
  `as_polygon_atlas()`/`as_sf_atlas()`). `sfheaders` is pure Rcpp with **no GDAL / GEOS /
  PROJ system libraries**, so it can build MULTIPOLYGON `sf` objects from plain
  data.frames without dragging in the heavy sf system-dependency stack. This is documented
  in-code (`R/atlas_polygons.R:70-73`, `R/atlas_polygon_converters.R:69-73`).
- **Could it be removed?** Only by either (a) hand-constructing `sf`/`sfc` MULTIPOLYGON
  objects, which requires `sf` itself and thus _reintroduces the heavy GDAL/GEOS/PROJ
  stack you were trying to avoid_ — a net regression against the package's stated purpose;
  or (b) writing a bespoke WKB/geometry builder, which is exactly what sfheaders already
  provides. Neither is worth it.
- **Verdict:** Keep. Trading 2 lightweight compiled packages (Rcpp, geometries) for
  avoiding the entire sf system-library stack is the right call and is the architectural
  point of the package.

---

## Cross-checks

- **No hidden `sf::` usage in `R/`.** The package never calls `sf::` directly in source;
  sf-touching code paths are all guarded by `require_sf()`/`has_sf()`, consistent with sf
  living in `Suggests`. sf is exercised only in tests and vignettes (e.g. `sf::st_sf`,
  `sf::st_sfc`, `sf::st_polygon` appear heavily in `tests/testthat/`), which is correct.
- **Test-side dependency use** is limited to `sf::*` (test fixtures) and
  `lifecycle::expect_deprecated` (16 uses) — both appropriate and already covered by
  `Suggests` (sf, lifecycle is in Imports).
- **Base imports** (`graphics`, `stats::na.omit`, `utils::read.table`) are standard and
  add no third-party cost.

## Bottom line for the review issue

- The declared dependency set is **minimal and each entry is justified**. There is no
  dependency bloat: the entire `Imports` block adds only 2 non-base packages to the
  install graph (Rcpp, geometries), both from sfheaders.
- **Keep cli, lifecycle, sfheaders** — each is well-used and/or free, and sfheaders is
  central to the package's sf-optional design.
- **rlang is the only removable dependency**, and only marginally: it has 9 lightweight
  usages replaceable by base R (`requireNamespace` + a native/shim `%||%`), but removing
  it saves **zero** install footprint and would ideally be paired with raising the R floor
  to `>= 4.4.0`. Recommend removal _only_ if the maintainer wants the tightest possible
  declared `Imports` list and is comfortable with the R-version bump; otherwise leave it.
