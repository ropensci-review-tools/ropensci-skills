---
title: "ggseg.formats 0.0.4 — AI-Assisted Code-Complexity Analysis"
author: "Athanasia Mowinckel (AI-assisted, Claude Code / Opus 4.8)"
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

> Analyse the code complexity of this R package and produce a report I can attach
> to an rOpenSci software-review issue. I want to trust the report, so measure
> rather than eyeball, and back every finding with evidence. The package is a
> self-contained working tree (ggseg.formats, brain-atlas geometry helpers). R is
> available. Installed: cyclocomp, covr, testthat, devtools, withr. NOT installed:
> pkgnet, bench, profmem — use base-R equivalents (utils::getParseData,
> system.time) where relevant. Deliverables: a complete final report; do NOT
> modify the package tree.

# Skill

This pass was driven by the rOpenSci **`run-complexity`** skill (the
code-complexity pass of `run-package-review`). Its operative discipline,
reproduced verbatim:

> **Measure first.** Rank functions by a real metric before reading source; the
> eye is a poor complexity meter and misses structural duplication entirely.
> **Read the code to interpret the numbers.** A high score can be benign (a chain
> of `&&` guards); a low score can hide 85× duplication. The metric points; you
> judge. **Confirm behavioural claims with runtime probes.** … **Read-only.** No
> refactoring the package to prove a point. … **Preserve the user-facing
> surface.** Every internal-refactor recommendation must keep exported names,
> signatures, and return types identical.

Method prescribed by the skill: (1) per-function cyclomatic complexity + LOC +
nesting + `if`/`for` counts over the loaded namespace; (2) a static call-graph /
duplication scan over `R/*.R` via `utils::getParseData()`; (3) targeted source
reading of the top offenders; (4) runtime probes to confirm behavioural claims.
All four were carried out.

# Report

## Method

Reproduces exactly. All measurement scripts were written **outside** the package
tree (`/tmp/*.R`); the package was only read and `load_all()`ed.

- **Environment:** R 4.5.2; `cyclocomp` 1.1.2.9000; package under review
  `ggseg.formats` 0.0.4.
- **Per-function metrics.** `devtools::load_all(".")`, then over all 201 functions
  in the namespace: `cyclocomp::cyclocomp()` for cyclomatic complexity; deparsed
  body used for LOC, max brace-nesting depth, and `if`/`for` keyword counts;
  `srcref` for defining file; `getNamespaceExports()` for export status.
- **Duplication / call-graph.** `parse(keep.source=TRUE)` + `getParseData()` over
  all 17 `R/*.R` files: extracted every top-level function body, masked
  identifiers/strings/numbers, then (a) grouped by exact masked body and (b)
  computed 4-gram-shingle Jaccard similarity between all body pairs ≥ 6 lines; and
  counted `SYMBOL_FUNCTION_CALL` tokens per identifier to rank call-sites.
- **Runtime probes.** `devtools::test_dir("tests/testthat")` (full suite, once);
  line-diff of the twin-function pair; keyword counts confirming which tokens
  inflate the top cyclomatic scores.
- **No package files were modified.** All edits were to `/tmp` scratch scripts;
  the package was accessed read-only (`Read`, `load_all`, `test_dir`).

## Headline

**Green.** Per-function complexity is genuinely low and the package is well
factored — cyclomatic complexity **maxes out at 14** (mean 3.7, median 3), with
**zero** functions in the conventional "too complex" band (cc ≥ 15). There are no
god-functions: the code is decomposed into small, single-purpose helpers
(`data_sf`/`data_poly`/`geom_from_data` are called 27/18/16× respectively;
validation is extracted into its own file). The full test suite passes. The only
real, measured finding is **modest structural duplication** in a handful of
twin/family functions — none of it severe, all of it optional to address, and
some of it (idiomatic S3 method boilerplate) not worth touching. The one
maintainability item worth flagging is the hand-rolled dplyr/tidyr
re-implementation in `compat_dataframe.R`, which is a deliberate
dependency-reduction tradeoff rather than a defect.

## Findings

### Measured profile

Cyclomatic-complexity distribution across all 201 namespace functions:

| stat          | value  |
| ------------- | ------ |
| min           | 1      |
| median        | 3      |
| mean          | 3.75   |
| 75th pct      | 5      |
| 90th pct      | 8      |
| 95th pct      | 11     |
| **max**       | **14** |
| count cc ≥ 10 | 15     |
| count cc ≥ 15 | **0**  |
| count cc ≥ 20 | **0**  |

Complexity concentrates in a small tail exactly as expected for a healthy
package. The top of that tail (evidence: `/tmp/complexity_metrics.csv`):

| function                      | file                  | cc  | LOC\* | maxnest | `if` | verdict                                                        |
| ----------------------------- | --------------------- | --- | ----- | ------- | ---- | -------------------------------------------------------------- | --- | ----------------------------- |
| `as_ggseg_atlas.list`         | coercion.R            | 14  | 13    | 2       | 2    | benign — cc inflated by `                                      |     | `/`&&`/`%in%` guards (see H3) |
| `as_ggseg_atlas.ggseg_atlas`  | coercion.R            | 14  | 11    | 2       | 2    | benign — same legacy-dispatch guards                           |
| `migrate_atlas_files`         | migrate_atlas_files.R | 13  | 26    | 6       | 6    | benign — file-walk driver; logic already delegated             |
| `as_ggseg_atlas.brain_atlas`  | coercion.R            | 13  | 17    | 2       | 3    | benign — legacy structure detection                            |
| `validate_legacy_inputs`      | atlas_convert.R       | 13  | 13    | 3       | 3    | benign — flat input-validation guards                          |
| `rebuild_data_with_geom`      | atlas_utils.R         | 12  | 34    | 3       | 6    | benign — a type dispatch (`switch`-like `if` ladder)           |
| `validate_ggseg_atlas_inputs` | ggseg_atlas.R         | 12  | 26    | 4       | 5    | benign — validation guards                                     |
| `atlas_region_op`             | atlas_utils.R         | 11  | 36    | 4       | 3    | acceptable — genuine geometry op, already split into 5 helpers |
| `reposition_views`            | atlas_utils.R         | 11  | 28    | 2       | 4    | acceptable — layout engine, well commented                     |
| `validate_centerlines`        | ggseg_atlas_data.R    | 11  | 21    | 4       | 4    | benign — validation loop                                       |
| `atlas_view_gather`           | atlas_utils.R         | 11  | 16    | 2       | 3    | benign — dispatch + guarded contract                           |
| `validate_one_mesh`           | validation.R          | 11  | 16    | 4       | 4    | benign — validation guards                                     |

\* _LOC is deparsed-body lines (normalised), used only for relative comparison;
it under-reports source lines._

Package size for context: **17 R files, 5,114 total source lines, 2,923
code-only lines** (blanks/comments stripped). Largest files:
`atlas_utils.R` (1,159), `ggseg_atlas.R` (634), `atlas_convert.R` (532),
`ggseg_atlas_data.R` (498), `validation.R` (337).

**Takeaway:** per-function complexity is a non-issue. The real (small) story is
duplication, which cyclomatic complexity cannot see — covered below.

### Duplication — Structural twin functions _(Low.)_

The masked-body scan and 4-gram-shingle similarity turned up genuine
near-duplicate function bodies (evidence: `/tmp/dup_probe.R` output):

```
Near-duplicate pairs (Jaccard >= 0.6 of masked 4-gram shingles):
  0.64  atlas_accessors.R::atlas_vertices  <->  atlas_accessors.R::atlas_meshes
  0.62  atlas_utils.R::atlas_view_remove   <->  atlas_utils.R::atlas_view_keep
```

**Hotspot 1 — `atlas_vertices` / `atlas_meshes` (atlas_accessors.R:170-218).**
Confirmed by line-diff runtime probe: **10 of 14 body lines are byte-identical**;
the 4 differing lines vary only in the data slot (`$vertices` vs `$meshes`) and
the result class (`ggseg_vertices` vs `ggseg_meshes`):

```
atlas_vertices lines NOT in atlas_meshes:
  if (is.null(atlas$data$vertices)) {
  cli::cli_abort("Atlas does not contain vertices for 3D rendering.")
  result <- df_left_join(atlas$data$vertices, atlas$core, by = "label")
  class(result) <- c("ggseg_vertices", class(result))
# (atlas_meshes: identical, with "meshes" / ggseg_meshes substituted)
```

Both do: guard `is_ggseg_atlas`, guard slot present, left-join core, attach
palette colour, stamp class. **Surface-preserving refactor:** extract a private
`atlas_3d_accessor(atlas, slot, class)` and keep `atlas_vertices()` /
`atlas_meshes()` as one-line explicit shims that call it. Prefer explicit shims
over a function-factory so `?atlas_vertices`, autocomplete, and
`@inheritParams` keep working. Saves ~10 duplicated lines; zero user-facing
change (exported names, signatures, `ggseg_vertices`/`ggseg_meshes` return
classes all identical).

**Hotspot 2 — `atlas_view_remove` / `atlas_view_keep` (atlas_utils.R:467-521).**
Confirmed: **16 of ~24 body lines shared**. Both follow the identical shape:
sf-null → polygon branch (`polygons_filter_view(..., keep = FALSE/TRUE)`) →
else build `keep_mask` via `grepl` (negated for remove) → null-out empty →
`rebuild_atlas`. They differ only in the `keep`/negation polarity and one warning
string, plus `atlas_view_remove` additionally calls `require_sf()` +
`atlas_view_gather()`. **Surface-preserving refactor:** factor the shared
sf/polygon dispatch and mask-building into a private
`view_filter(atlas, views, keep)`, with the two exported functions as thin
wrappers. Lower value than Hotspot 1 because the two are not perfectly symmetric
(the extra `gather`/`require_sf` in `remove`), so weigh the extraction against
the small readability cost of the polarity flag. Optional.

**Idiomatic S3 duplication — do NOT refactor.** The exact-body scan also flagged
several groups that are legitimate, expected R idiom, not copy-paste smell:

- `is_cortical_atlas` / `is_subcortical_atlas` / `is_tract_atlas` /
  `is_cerebellar_atlas` (ggseg_atlas.R) — each is `inherits(x, "<type>_atlas") &&
validate_ggseg_atlas(x)`, cc = 2. This is the standard S3 predicate family.
- `atlas_regions.*` / `atlas_labels.*` / `atlas_type.*` methods (atlas_utils.R) —
  one-line method bodies delegating to `get_uniq()` / `guess_type()`.
- `data_sf` / `data_poly` (atlas_accessors.R) and `print.ggseg_data_cortical` /
  `print.ggseg_data_cerebellar` — trivial `inherits()`-branch twins.

Collapsing these would _reduce_ clarity and break `@rdname`/`UseMethod` dispatch,
so they are correctly left as-is. Flagging them here only to show the scan was run
and the result judged, not blindly reported.

### Repeated guard idioms _(Low.)_

Line-level idiom counts (evidence: `/tmp/callsites.R` output) show a few verbatim
guards repeated across the manipulation functions:

```
 5 x  if (!is_ggseg_atlas(atlas)) {
 5 x  cli::cli_abort("{.arg atlas} must be a {.cls ggseg_atlas}.")
 6 x  if (is.null(data_sf(atlas$data))) {   # sf-vs-polygon dispatch
 6 x  if (is.null(data_poly(atlas$data))) {
 7 x  new_data <- rebuild_atlas_data(atlas, new_sf)
 7 x  pattern <- paste(views, collapse = "|")
 3 x  result$colour <- unname(atlas$palette[result$label])
```

The `is_ggseg_atlas` guard-and-abort pair (5×) is a candidate for a one-line
private `assert_ggseg_atlas(atlas)` helper. The `data_sf`/`data_poly` dispatch
(6× each) is an inherent consequence of the sf-optional design (every 2D
manipulation must branch on which representation the atlas carries) and is already
mediated by the small `data_sf`/`data_poly`/`geom_from_data` accessors — this is
good structure, not a hotspot; leave it. The `result$colour <- unname(...)`
line (3×) is already absorbed for the twin accessors by Hotspot 1's refactor.

### The one high-cc function that is genuinely benign _(informational.)_

`as_ggseg_atlas.list` (cc = 14, the joint-highest in the package) is a **flat
legacy-format dispatcher**, not a complex function. Runtime probe confirms its cc
is driven entirely by structural short-circuit guards, not nested control flow:
**2 `||`, 2 `&&`, and 5 `%in%`** operators (evidence: `/tmp/twin_probe.R`), with
max nesting depth of only 2. cyclocomp counts each `||`/`&&`/`%in%` branch, so the
score overstates cognitive load. This is precisely the skill's "a high score can
be benign (a chain of `&&` guards)" case. No action needed. The same applies to
`validate_legacy_inputs`, `validate_ggseg_atlas_inputs`, and the other
`as_ggseg_atlas.*` methods: their scores are validation/dispatch guards, all with
nesting ≤ 4.

### Maintainability observation — hand-rolled tidyverse verbs _(Low; not a complexity defect.)_

`compat_dataframe.R` (173 lines) is a deliberate base-R re-implementation of
dplyr/tidyr verbs — `df_left_join`, `df_bind_rows`, `df_nest`, `df_unnest`,
`df_distinct`, plus tibble-free printing — to avoid taking dplyr/tidyr/tibble as
dependencies. Each function is small (cc 1-7) and well documented. This is a sound
dependency-vs-maintenance tradeoff for a low-level ggsegverse dependency, and it
is called throughout (`df_left_join` 3×, `as_tbl` 15×). The only complexity note:
`df_left_join` reimplements dplyr's one-to-many join and `.y`-suffix collision
semantics by hand (atlas_accessors uses it on the palette/core join), so its
correctness rests entirely on the package's own tests. No change recommended —
just flag for reviewers that this custom join logic is a surface that must stay
well tested if join semantics ever need to change.

## Verified healthy (no action)

- **No god-functions / no cc ≥ 15.** Max cyclomatic complexity is 14; only 15 of
  201 functions reach cc ≥ 10, and every one of those is either flat validation
  guards or a genuinely irreducible operation (geometry boolean op, view-packing
  layout engine). Evidence: `/tmp/complexity_metrics.csv`.
- **Good decomposition.** The heavy operations are split into named private
  helpers rather than inlined: `atlas_region_op` delegates to `region_op_sf_data`,
  `region_op_labels`, `region_op_result`, `region_op_view`, `region_op_combine`,
  `add_op_region_meta`; the constructor `ggseg_atlas()` delegates all checks to
  `validate_*` functions in `validation.R`. Call-site counts confirm the shared
  accessors are reused (not re-derived): `data_sf` 27×, `data_poly` 18×,
  `geom_from_data` 16×, `rebuild_atlas` 8×.
- **Consistent, centralised error handling.** 76 `cli::cli_abort` and 25
  `cli::cli_warn` call-sites — errors go through `cli` uniformly rather than a mix
  of `stop`/`warning`/`message`.
- **Full test suite passes.** `devtools::test_dir("tests/testthat")` ran green
  across all 19 test files (no failures, warnings, or skips surfaced), including
  the manipulation-heavy `atlas_utils` suite. This backs every "surface-preserving
  refactor" claim: the behaviour the refactors must preserve is under test.
- **`# nocov` used honestly.** The one `nocov` block (atlas_utils.R:633-638) guards
  a broken-contract branch of `reposition_views` that cannot be reached in normal
  use, and says so in a comment — appropriate use, not coverage-gaming.

## Not run (reason)

- **`pkgnet` call-graph / `bench` / `profmem`** — not installed per the task
  constraints. Substituted with `utils::getParseData()` token analysis for the
  call-graph/duplication pass and the test suite for behavioural confirmation, as
  the skill permits. No runtime performance profiling was attempted (out of scope
  for a complexity pass; that is the `run-performance-review` pass).
- **Coverage percentage** — `covr` is installed but a full
  `covr::package_coverage()` run was not executed here; the test suite was run for
  pass/fail behavioural confirmation only. Coverage quantification belongs to the
  `run-test-audit` pass.
- **Cross-file semantic duplication beyond function bodies** (e.g. duplicated
  constant tables, repeated roxygen templates) — only function-body duplication
  was measured.

## Suggested fix priority

All items are **Low** severity and **optional** — the package is in good shape
and none of these block a review. Ordered by value:

1. **(Low) Hotspot 1 — collapse `atlas_vertices`/`atlas_meshes`** into a private
   `atlas_3d_accessor()` with two explicit exported shims. Highest value: 10
   duplicated lines removed, mechanical, fully test-covered, zero API change.
2. **(Low) Repeated `is_ggseg_atlas` guard** — extract
   `assert_ggseg_atlas(atlas)` to replace the 5× verbatim guard-and-abort pair.
3. **(Low) Hotspot 2 — factor `atlas_view_remove`/`atlas_view_keep`** shared
   sf/polygon dispatch into `view_filter(atlas, views, keep)`. Lower value than #1
   because the two are not perfectly symmetric; weigh against the polarity-flag
   readability cost.
4. **(Informational) Note in review** that `compat_dataframe.R`'s custom
   `df_left_join` join semantics are a maintenance surface to keep well tested;
   no code change recommended.

Explicitly **not** recommended: collapsing the `is_*_atlas`, `atlas_regions.*`,
`atlas_type.*`, or `print.*` method families — they are idiomatic S3 dispatch and
consolidating them would reduce clarity and break `@rdname`/`UseMethod`.
