---
title: "ggseg.formats 0.0.4 — AI-Assisted Performance & Memory Review"
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

> Analyse the performance and memory behaviour of this R package and produce a
> report I can attach to an rOpenSci software-review issue. Anchor claims on real
> measurements and be explicit about what is measured versus extrapolated.
> The package is a self-contained working tree (ggseg.formats, brain-atlas
> geometry helpers that convert/operate on polygon & mesh atlas data). R is
> available. Installed: testthat, devtools, withr. NOT installed: bench, profmem
> — use base-R equivalents (system.time, Rprof, gc, object.size) for measurement.

# Skill

This pass was driven by the `run-performance-review` skill (the performance pass
of the rOpenSci `run-*` review-runner family). Its operative instructions:

> An **action** skill: it characterises where a package spends time and memory,
> how it scales, and where it will fall over — then writes a trustworthy report.
> The discipline is **measure a real anchor, then extrapolate transparently**:
> never assert a scaling claim you can't tie back to a measured figure.
>
> - **Trace before you profile.** Understand the data/compute path end to end.
> - **Anchor on measured data.** Profile real inputs, or measure the package's
>   own recorded fixtures (`object.size()`, row/column counts, per-row cost).
>   State which figures are _measured_ and which are _extrapolated_.
> - **Extrapolate explicitly.** Show the multipliers so a reader can check the
>   arithmetic.
> - **Distinguish the persistent result from the transient peak.**
> - **Measured wins only.** Recommend an optimization only where the trace or a
>   measurement shows it matters; keep behaviour identical.
> - **Read-only.** Don't edit the package; propose, with evidence.
>
> Method: (1) trace the hot path over `R/*.R`; (2) measure anchors with `Rprof`,
> `gc()`, `object.size()`; (3) identify what scales; (4) extrapolate scenarios
> from measured per-unit anchors; (5) enumerate risks.

Report structure follows the shared review template
(`run-package-review/references/report-template.md`).

# Report

## Method

Reproducible measurement setup:

- **Tooling:** R 4.5.2. Package deps as installed: cli 3.6.6, lifecycle 1.0.5,
  rlang 1.2.0, sfheaders 0.4.5. `sf` 1.1.0 **was in fact installed** in this
  environment (the task brief said it might not be), which let me exercise both
  the sf-backed and sf-optional paths. `bench` / `profmem` were not installed,
  so timing used `system.time()` over repeated loops (mean ms/call), allocation
  used `Rprof(memory.profiling = TRUE)` and `object.size()` / `gc()`.
- **Package loaded** with `devtools::load_all()`; internal functions reached via
  `asNamespace("ggseg.formats")`.
- **Inputs:** the four bundled atlases (`dk()`, `aseg()`, `tracula()`, `suit()`)
  as real fixtures, plus synthetic flat coordinate tables and join tables to
  probe scaling beyond the bundled sizes (which are all small and fixed).
- **Commands:** per-operation timing (200/100/50 reps each); a scaling sweep of
  `polygon_geometry_areas`, `df_left_join`, `df_bind_rows`, `df_unnest`; one
  `Rprof` run of 300 iterations of a composite polygon workflow on `dk()`; a
  `gc()` / `object.size()` transient-peak probe of the sf ↔ polygon round trip.
- **No package files were modified.** All probe scripts were written to `/tmp`.

## Headline

**Green for the shipped use case; amber for the general-purpose primitives.**
Every bundled atlas is tiny and fixed — the largest flat geometry is `dk()` at
6,254 points / 191 label×view groups, and the whole persistent object is
416 Kb (`aseg()` is 7.4 Mb, dominated by pre-computed 3D meshes, not compute).
On these fixtures every operation is well under 10 ms and there is no memory
concern whatsoever. The amber is that three internal primitives —
`polygon_geometry_areas()`, `df_left_join()`, and `df_bind_rows()` — are
**super-linear (≈ O(n²))** in ways that don't bite the bundled atlases but
would bite a materially larger atlas or a `read_atlas_files()` run over many
subjects. The single measured transient-memory concern is `sf_to_polygons()`,
whose peak is ~4.4× the persistent result because it accumulates a per-row
fragment list before one `do.call(rbind, …)`. None of this is urgent at shipped
scale; all of it is cheap to fix and worth documenting as a known ceiling.

## Findings

### Architecture of the hot path

The package has **no I/O-bound or network hot path** — it is pure in-memory
geometry transformation. `read_freesurfer.R` reads local stats files, but the
compute weight lives in the polygon/mesh operations. Two representations exist
for 2D geometry and everything routes through conversions between them:

- **`brain_polygons`** — a nested data.frame, one row per `label`, with a
  `geometry` list-column of flat coordinate tables
  (`view, x, y, group, subgroup`). This is the sf-free shipped format.
- **sf** — MULTIPOLYGON geometry, rehydrated on demand.

The universal shape of every polygon operation is **unnest → operate on the
flat table → renest** (`atlas_polygon_ops.R:34–52`):

```
brain_polygons ─ polygons_unnest() ─▶ flat (label,view,x,y,group,subgroup)
   flat ─ <filter | area | reposition> ─▶ flat'
   flat' ─ polygons_renest() ─▶ brain_polygons'
```

`polygons_unnest()` → `df_unnest()` (`compat_dataframe.R:164`) and
`polygons_renest()` → `df_nest()` (`compat_dataframe.R:150`) are the entry/exit
chokepoints. They are **linear and cheap** (measured below). The cost is not in
the plumbing — it is in three per-group / per-row loops that re-scan the whole
table:

- `polygon_geometry_areas()` (`atlas_polygon_ops.R:134`): a `vapply` over each
  label×view, and **inside** it `flat[flat$label == … & flat$view == …, ]`
  re-filters the entire flat table once per group → O(groups × rows).
- `df_left_join()` (`compat_dataframe.R:77`): `matches <- lapply(xkey, function(k)
which(ykey == k))` scans all of `ykey` once per row of `x` → O(nx × ny).
- `df_bind_rows()` (`compat_dataframe.R:108`): `Reduce(union, …)` +
  per-fragment `setequal()` column check, then `do.call(rbind, dfs)` — the rbind
  copies the growing accumulator repeatedly.

The conversions accumulate-then-concatenate rather than streaming:
`sf_to_polygons()` (`atlas_polygons.R:48–62`) builds a per-row list via `lapply`

- `sf::st_coordinates()` then `df_bind_rows()`; `polygons_to_sf()`
  (`atlas_polygons.R:87–113`) is a single vectorised `sfheaders::sf_multipolygon()`
  call and is comparatively cheap.

### Measured anchors

**Bundled-atlas fixtures** (real inputs; `object.size()` / row counts measured):

| Atlas     | Type        | Object size | Core labels | Geom rows | Flat points | label×view groups |
| --------- | ----------- | ----------- | ----------- | --------- | ----------- | ----------------- |
| `dk`      | cortical    | 416.6 Kb    | 70          | 72        | 6,254       | 191               |
| `aseg`    | subcortical | 7.4 Mb¹     | 47          | 30        | 5,137       | 159               |
| `tracula` | tract       | 512.1 Kb    | 42          | 45        | 5,783       | 114               |
| `suit`    | cerebellar  | 420.9 Kb    | 34          | 34        | 4,392       | 34                |

¹ `aseg`'s 7.4 Mb is pre-computed 3D subcortical **meshes** stored in the object,
not a compute cost; its 2D `brain_polygons` geom is only 213.7 Kb.

**Per-operation timing on `dk()`** (measured, mean ms/call):

| Operation                       | ms/call | reps   |
| ------------------------------- | ------- | ------ |
| `polygons_unnest(dk)`           | 0.05    | 200    |
| `polygons_renest(dk)`           | 0.09    | 200    |
| `reposition_flat(dk, cortical)` | 0.04    | 200    |
| `atlas_polygons(dk)`            | 0.005   | 200    |
| `polygons_to_sf(dk)`            | 0.51    | 100    |
| `atlas_sf(dk)`                  | 0.94    | 50     |
| `polygon_geometry_areas(dk)`    | 1.4–2.6 | 100/50 |
| `polygons_remove_small(dk)`     | 4.5     | 100    |
| `sf_to_polygons(dk)`            | 6.9     | 100    |

`polygon_geometry_areas` across atlases (measured): dk 2.64 ms (191 groups),
aseg 2.32 ms (159), tracula 1.74 ms (114), suit 0.40 ms (34) — cost tracks
group count, as the trace predicts.

**Rprof over a 300-iteration composite `dk()` workflow** (self/total %):

- `==` 24.96% self · `[.data.frame` 56.68% total — the per-group/per-row
  row-filter scans dominate everything.
- Hottest whole functions by total time: `polygons_remove_small` 33.4%,
  `sf_to_polygons` 31.6%, `polygon_geometry_areas` 27.3%.
- `as_tbl` / `as.data.frame` coercion 28.9% total — repeated data.frame
  re-tagging inside `df_nest`/`df_unnest`/`df_bind_rows` is a visible secondary
  cost.

**Transient memory — `sf_to_polygons(dk)`** (measured via `object.size()`):

| Quantity                                         | Size      |
| ------------------------------------------------ | --------- |
| Persistent `brain_polygons` result               | 310.8 Kb  |
| Intermediate per-row fragment list (191 tbls)    | 527.9 Kb  |
| Input sf                                         | 304.9 Kb  |
| Rough transient peak (input + list + rbind copy) | ≈ 1.36 Mb |

So the round trip peaks at **~4.4× the persistent result**, driven by the
accumulated fragment list, not the final object. The reverse
(`polygons_to_sf`) is a single vectorised call and does not show this pattern.

### What scales / what doesn't

**Linear (safe to scale) — measured:**

- `df_unnest`: rows 50→400 (2k→16k flat) gives 0.067→0.600 ms — ~linear.
- `polygons_unnest` / `polygons_renest` / `reposition_flat` — sub-0.1 ms on dk,
  dominated by the linear unnest/renest.

**Super-linear (the scaling risk) — measured sweeps:**

- `polygon_geometry_areas` (synthetic, 30 pts/group): doubling groups gives
  ×1.7 → ×3.2 → ×3.36 in time (50→100→200→400→800 groups: 0.75 → 1.5 → 2.55 →
  8.15 → 27.4 ms). ms/group climbs 0.015 → 0.034 — clear O(n²) tail.
- `df_left_join` (one-to-one): 100→4000 rows is 40× the rows for ~124× the time
  (0.10 → 12.4 ms); the last doubling (2000→4000) is ×4.3 for ×2 rows.
- `df_bind_rows`: 50→400 fragments is 14.8 → 54.8 ms; the last doubling
  (200→400) is ×2.4 for ×2 fragments.

Callers that inherit these: `polygon_geometry_areas` feeds
`polygons_remove_small` (`atlas_polygon_ops.R:180`); `df_left_join` feeds
`atlas_vertices` / `atlas_meshes` (`atlas_accessors.R:179,210`) and
`atlas_core_add` (`atlas_utils.R:418`); `df_bind_rows` feeds `sf_to_polygons`
(`atlas_polygons.R:61`) and `read_atlas_files` (`read_freesurfer.R:73,85`).

### Extrapolated scenarios

Estimates from the measured per-unit anchors above. **Labelled estimates — not
measured at these sizes.** Assumes the same ~30 pts/group and the observed
super-linear trend continuing.

| Scenario                                     | Groups / rows                       | Basis                                                            | Est. time                               | Est. transient peak |
| -------------------------------------------- | ----------------------------------- | ---------------------------------------------------------------- | --------------------------------------- | ------------------- |
| Bundled atlas (`dk`)                         | 191 groups / 6.3k pts               | **measured**                                                     | 2.6 ms                                  | ~1.4 Mb             |
| Fine parcellation (~1,000 regions × 4 views) | ~4,000 groups                       | extrapolate `polygon_geometry_areas` O(n²) from 800-group anchor | ~0.7–1.0 s                              | ~7–10 Mb            |
| High-res dense atlas                         | ~10,000 groups / 300k pts           | extrapolate O(n²)                                                | ~4–6 s (dominated by area/remove-small) | tens of Mb          |
| `read_atlas_files`, 500 subjects × 2 hemi    | 1,000 stats frames → `df_bind_rows` | extrapolate `df_bind_rows` from 400-frag anchor                  | ~0.3–0.5 s                              | ~2–3× final table   |
| `atlas_core_add` on a 10k-region atlas       | 10k×10k `which` join                | extrapolate `df_left_join` O(n²)                                 | seconds                                 | linear in result    |

None of these is a hard OOM at plausible neuroimaging sizes — the objects stay
in the low tens of Mb — but the **time** on a fine/high-res atlas moves from
milliseconds into seconds, and the transient peak is a fixed ~4× multiple of the
result for `sf_to_polygons`.

### Risks identified

- **R1 (Medium). `polygon_geometry_areas()` is O(groups × rows).** The inner
  `flat[flat$label == lv$label[k] & flat$view == lv$view[k], ]`
  (`atlas_polygon_ops.R:143`) re-scans the entire flat table for every group.
  Evidence: Rprof `==` 24.96% self, `[.data.frame` 56.68% total; scaling sweep
  ×3.36 per group-doubling at 800 groups. Harmless on bundled atlases (≤ 2.6 ms),
  costly on a fine parcellation (extrapolated ~1 s at 4,000 groups).
- **R2 (Medium). `df_left_join()` is O(nx × ny).** `lapply(xkey, function(k)
which(ykey == k))` (`compat_dataframe.R:88`). Evidence: 2000→4000 rows is ×4.3
  time for ×2 rows. Bounded today (atlas cores are ≤ 70 rows) but on the public
  `atlas_core_add` / `atlas_vertices` / `atlas_meshes` API path, so a large
  user-supplied metadata join scales badly.
- **R3 (Low/Medium). `df_bind_rows()` rbind-accumulation.** `do.call(rbind, dfs)`
  after a `Reduce(union)` + per-fragment `setequal()` ragged check
  (`compat_dataframe.R:126–144`). Evidence: 200→400 fragments ×2.4 time. Hits
  `read_atlas_files()` over many subjects and `sf_to_polygons()` (191 fragments
  for dk).
- **R4 (Low). `sf_to_polygons()` transient peak ≈ 4.4× the result.** Measured:
  527.9 Kb intermediate fragment list + rbind copy vs 310.8 Kb result. The peak,
  not the result, is what would OOM at scale; it is a fixed multiple, so it only
  matters once single-atlas geometry reaches hundreds of Mb (not a shipped
  concern). Evidence: `object.size()` probe above.
- **R5 (Low). Repeated `as_tbl()` / `as.data.frame()` coercion.** 28.9% total
  Rprof time is spent re-tagging frames as `tbl_df` inside the df\_\* primitives
  (`compat_dataframe.R:4`). Pure overhead — cosmetic class tagging on every
  intermediate — with no correctness value in the hot loop.

## Verified healthy (no action)

- **Shipped scale is comfortably fast and small.** Every bundled atlas is
  ≤ 6,254 flat points; every operation on them is ≤ 6.9 ms (`sf_to_polygons`);
  most are < 1 ms. No caching, streaming, or checkpointing is needed at this
  size — the analysis confirms it, it is not assumed.
- **`polygons_to_sf()` is the right shape.** It is a single vectorised
  `sfheaders::sf_multipolygon()` call (`atlas_polygons.R:98`), 0.51 ms on dk, and
  does **not** exhibit the per-row accumulation of its inverse. Good asymmetry to
  keep.
- **The unnest/renest plumbing is linear** (`df_unnest` measured linear to 16k
  rows) — the representation choice itself imposes no super-linear tax; the tax
  is only in the three specific loops flagged in R1–R3.
- **No memory blow-ups measured.** The heaviest persistent object (`aseg` 7.4 Mb)
  is pre-computed mesh data, and the heaviest transient (`sf_to_polygons` ~1.4 Mb
  on dk) is a bounded 4.4× multiple — there is no unbounded accumulation, no
  silent partial-result truncation, and no repeated re-parse on repeated calls.
- **`sfheaders` (not full `sf`) for the pure conversion** keeps the sf-optional
  promise real — the polygon↔sf conversion needs no GDAL/GEOS/PROJ
  (`atlas_polygons.R:70–73` docstring, confirmed by the conversion running with
  only sfheaders in the compute path).

## Not run (reason)

- **`bench` / `profmem`** — not installed; substituted `system.time()` loops and
  `Rprof(memory.profiling=TRUE)` + `object.size()`/`gc()`. Timings are therefore
  mean-of-N loop figures, not `bench`'s min/median with GC accounting; treat the
  ms/call numbers as ±20% not high-precision.
- **`read_atlas_files()` on a real many-subject FreeSurfer tree** — no such tree
  is available (only 3 tiny bundled stats fixtures). The many-subject
  `df_bind_rows` scenario is **extrapolated** from the synthetic fragment sweep,
  not measured on real stats files.
- **Fine/high-resolution atlases (1k–10k regions)** — none exist in or ship with
  the package; the fine-parcellation rows in the scenarios table are
  extrapolations from the synthetic scaling sweep, explicitly labelled.
- **`aseg` 3D mesh operations / `infer_vertices_from_meshes`** — the vertex-hash
  inference path (`atlas_convert.R:351`) needs a legacy ggseg3d atlas as input,
  not present here; its O(n+m) hash design was read but not timed.
- **Downstream `ggseg` plotting** — out of scope (different package); only the
  data-preparation cost owned by `ggseg.formats` was measured.

## Suggested fix priority

1. **R1 — de-quadratic `polygon_geometry_areas()`** (Medium, highest measured
   Rprof share). Replace the per-group `flat[flat$label == … & flat$view == …]`
   re-scan with a single `split()` on a precomputed label×view key (or
   `by()` / `tapply`), so the table is partitioned once. Keeps the shoelace math
   and hole handling identical; removes the dominant `==` / `[.data.frame` cost.
2. **R2 — index `df_left_join()`** (Medium, on public API). Replace the per-row
   `which(ykey == k)` with a `match()` / `split(seq_along(ykey), ykey)` lookup to
   get O(nx + ny). Behaviour (one-to-many recycling, `.y` suffixing) unchanged.
3. **R3 — single-pass `df_bind_rows()`** (Low/Medium). Skip the `setequal`
   per-fragment ragged check on the common equal-columns path (compare against
   the first fragment's names once), and keep the single `do.call(rbind, …)`.
4. **R4 — document the `sf_to_polygons` ~4× transient** in the function docs and,
   if very large atlases become a target, build the coordinate table in one
   vectorised pass (mirror `polygons_to_sf`'s single-call shape) instead of a
   per-row `lapply` + `df_bind_rows`.
5. **R5 — drop redundant `as_tbl()` re-tagging** inside the hot df\_\* loop
   (tag once at the boundary, not on every intermediate) to reclaim the ~29%
   coercion overhead.
6. **Documentation (all severities).** Add a short "scales to ~hundreds of
   regions; not tuned for 1k+-region high-res atlases" note, and — if
   `read_atlas_files` is meant for large cohorts — a network/large-input-gated
   benchmark test so the O(n²) primitives can't silently regress.
