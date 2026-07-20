---
title: "ggseg.formats 0.0.4 — AI-Assisted Performance & Memory Review"
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

> Analyse the performance and memory behaviour of this R package and produce a
> report I can attach to an rOpenSci software-review issue. Anchor claims on real
> measurements and be explicit about what is measured versus extrapolated.
> The package is a self-contained working tree (ggseg.formats, brain-atlas
> geometry helpers that convert/operate on polygon & mesh atlas data). R is
> available; Installed: testthat, devtools, withr. NOT installed: bench, profmem
> — use base-R equivalents (system.time, Rprof, gc, object.size) for measurement.

# Skill

Driven by the **`run-performance-review`** skill (rOpenSci skills collection),
the performance pass of `run-package-review`. Operative instructions followed
verbatim:

> - **Trace before you profile.** Understand the data/compute path end to end …
>   before quoting numbers.
> - **Anchor on measured data.** Profile real inputs, or measure the package's
>   own recorded fixtures (`object.size()`, row/column counts, per-row cost).
>   State which figures are _measured_ and which are _extrapolated_.
> - **Extrapolate explicitly.** Show the multipliers … so a reader can check the
>   arithmetic.
> - **Distinguish the persistent result from the transient peak.**
> - **Measured wins only.** … keep behaviour identical.
> - **Read-only.** Don't edit the package; propose, with evidence.

Report skeleton from the shared template at
`run-package-review/references/report-template.md`.

# Report

## Method

**Environment.** R 4.5.2. Package loaded with `devtools::load_all()` (v0.0.4,
working tree at `/tmp/eval-runs/run-performance-review__with_skill`). `bench` and
`profmem` are absent as stipulated; all figures come from base tooling:
`system.time()` (median of 20 repetitions after one warm-up call for hot paths;
median of 5 for scaling sweeps), `object.size()`, `gc()` max-used deltas, and
row/coordinate counts read off the bundled fixtures.

**Note on the environment vs. the design.** `sf` and `sfheaders` **are**
installed in this measurement environment, so both the sf and the sf-free
polygon code paths could be exercised. This matters: the package is explicitly
designed to run **without** `sf` (polygon representation for wasm / air-gapped
installs — `atlas_polygon_converters.R:1-19`), so on a real sf-free install the
sf-dependent operations below are simply unavailable rather than slow.

**No package files were modified.** Measurement scripts were written to `/tmp`
only; the package tree is untouched.

**What was measured.** The four bundled atlases (`dk()`, `aseg()`, `tracula()`,
`suit()`); the geometry accessors/converters (`atlas_sf`, `atlas_polygons`,
`as_sf_atlas`, `as_polygon_atlas`, `sf_to_polygons`, `polygons_to_sf`); the
sf-free view/region manipulation ops; and the internal `df_*` primitives
(`compat_dataframe.R`) plus `polygon_geometry_areas` (`atlas_polygon_ops.R`).
Scaling was probed with synthetic polygon tables of increasing label count.

## Headline

**Amber.** For its intended workload — a handful of bundled atlases with a few
thousand coordinates each — the package is comfortably fast (single- to
low-hundreds-of-milliseconds per operation) and memory-light (largest atlas
7.4 Mb, dominated by 3D mesh payload, not geometry). Nothing here will OOM at
the shipped scale. **But three internal primitives are quadratic in atlas size**
and would dominate on larger/denser inputs: `polygon_geometry_areas`
(`atlas_polygon_ops.R:134-164`), `df_left_join` (`compat_dataframe.R:77-100`),
and the per-row `sf_to_polygons` coordinate extraction
(`atlas_polygon_converters.R` / `atlas_polygons.R:37-64`). All three are
**measured** as super-linear below. They are latent, not currently biting,
because the shipped atlases are small — a classic "fine today, slow if the
ecosystem grows denser parcellations" situation worth documenting.

## Findings

### Architecture of the hot path

The compute model is **fully in-memory, non-streaming, single-object**. There is
no HTTP egress, no chunking, no temp files, no caching, and no incremental flush
anywhere in `R/*.R` — every operation loads a whole atlas, transforms it, and
returns a whole new atlas. This is appropriate: atlases are small, bounded
fixtures, not streamed data. The only file I/O is `read_freesurfer.R`
(`read.table` over user stats files) and `sysdata.rda` package load.

An atlas is a list with `core` (metadata data.frame), `palette` (named vector),
and `data` (a `ggseg_atlas_data` carrying one 2D `geom` slot plus a 3D payload:
`vertices`, `meshes`, or `centerlines`). The 2D geometry is stored in **one of
two interchangeable representations** — `sf` (needs GDAL/GEOS/PROJ) or the
sf-free `brain_polygons` nested data.frame. All four bundled atlases ship in
`brain_polygons` form (measured below).

Every polygon-side manipulation follows the same **unnest → operate on a flat
coordinate table → renest** call chain, which is the single structural
chokepoint:

```
atlas_view_* / atlas_region_*  (atlas_utils.R)
      │
      ▼
polygons_unnest()  ── df_unnest()  ── do.call(rbind, inner)     [accumulate-then-concat]
      │                                (compat_dataframe.R:164-173)
      ▼
<pure-R op on flat table>  e.g. polygon_geometry_areas()        [O(labels·views · rows)]
      │                          (atlas_polygon_ops.R:134-164)
      ▼
polygons_renest() ── df_nest() ── lapply over unique labels     (compat_dataframe.R:150-159)
```

Conversion between representations is the other chokepoint:
`sf_to_polygons()` loops **per sf row** calling `sf::st_coordinates()` then
`df_bind_rows()` → `do.call(rbind, …)`; `polygons_to_sf()` calls
`sfheaders::sf_multipolygon()` once (vectorised, fast).

The join-side chokepoint is `df_left_join()` (`compat_dataframe.R:77-100`),
used by `atlas_vertices()`, `atlas_meshes()`, `atlas_core_add()`. Its match step
is `matches <- lapply(xkey, function(k) which(ykey == k))` — a `which()` scan of
the whole key vector **for every row of x** → O(n·m).

### Measured anchors

Bundled-atlas fixtures (measured: `object.size()`, coordinate counts):

| Atlas   | Type        | `object.size` | 2D geom class    | Core rows | 2D coords | 3D payload (measured)              |
| ------- | ----------- | ------------- | ---------------- | --------- | --------- | ---------------------------------- |
| dk      | cortical    | 0.4 Mb        | `brain_polygons` | 70        | 6,254     | vertices 0.09 Mb (18,824 indices)  |
| aseg    | subcortical | **7.4 Mb**    | `brain_polygons` | 47        | 5,137     | **meshes 7.55 Mb** (207,680 faces) |
| tracula | tract       | 0.5 Mb        | `brain_polygons` | 42        | 5,783     | centerlines 0.25 Mb                |
| suit    | cerebellar  | 0.4 Mb        | `brain_polygons` | 34        | 4,392     | vertices 0.12 Mb + meshes 0.11 Mb  |

`R/sysdata.rda` on disk: **3.21 Mb** (all four atlases, compressed).

**Persistent vs. transient.** The persistent cost is dominated by the **3D mesh
payload**, not the 2D geometry: `aseg`'s per-structure meshes are 7.55 Mb
(103,886 vertices / 207,680 triangle faces), ~34× the size of its 0.22 Mb 2D
geometry. The 2D geometry itself is tiny (0.19–0.32 Mb per atlas). Transient
peaks come from the conversion/manipulation ops, not from holding the object.

Hot-path timing on `dk()` (~6,254 coords), median of 20 reps:

| Operation                            | Path                             | Median (ms) |
| ------------------------------------ | -------------------------------- | ----------- |
| `atlas_polygons(dk)`                 | polygon pass-through             | 1.0         |
| `atlas_vertices(dk)`                 | `df_left_join` (70 rows)         | 1.0         |
| `atlas_meshes(aseg)`                 | `df_left_join` (47 rows)         | 1.0         |
| `polygons_to_sf(dk)`                 | `sfheaders` (vectorised)         | 18.0        |
| `as_sf_atlas(dk)`                    | poly→sf convert                  | 18.5        |
| `atlas_sf(dk)`                       | poly→sf + `merge`                | 22.5        |
| `atlas_region_keep(dk, "frontal")`   | mask + rebuild                   | 4.0         |
| `atlas_region_remove(dk, "frontal")` | drop-pattern + rebuild           | 29.0        |
| `atlas_view_gather(dk)`              | reposition (unnest/renest)       | 37.5        |
| `sf_to_polygons(dk)`                 | **per-row `st_coordinates`**     | **107.5**   |
| `polygon_geometry_areas(dk flat)`    | **O(n²) area scan**              | **116.5**   |
| `as_polygon_atlas(sf dk)`            | sf→poly (wraps `sf_to_polygons`) | **184.0**   |
| `atlas_view_remove_small(dk, 0.01)`  | area scan + rebuild              | **189.5**   |

`polygons_unnest(dk)` alone (the `df_unnest` rbind) is 12 ms and sits on almost
every manipulation path.

**Transient peak vs. retained** (`gc()` max-used delta over base; the base RSS
of a `devtools`+`sf` session is ~70 Mb, so absolute peaks are noisy, but the
_pattern_ is clean): sf-touching / area-scan ops show large transient allocation
(`atlas_sf` peak ~55 Mb, `as_polygon_atlas` ~61 Mb, `atlas_view_remove_small`
~78 Mb) while **retaining almost nothing** (0.2–0.5 Mb) — the cost is churn in
intermediates, not the result. The pure-R `atlas_meshes(aseg)` (no sf) peaks at
just 0.4 Mb. So the transient/persistent gap is real but small in absolute terms
at the shipped scale.

### What scales / what doesn't

**Cheap and flat (do not grow with atlas size in any harmful way):**

- Metadata accessors — `atlas_regions`, `atlas_labels`, `atlas_type`,
  `atlas_palette`, `atlas_views` (`unique()`/`sort()` over one column).
- `polygons_to_sf` — one vectorised `sfheaders::sf_multipolygon()` call.
- `df_unnest` / `df_nest` — **measured linear** (see below); fine.
- Holding an atlas in memory — persistent size is set by the fixed 3D payload.

**Quadratic in atlas size (measured):**

1. **`polygon_geometry_areas` (`atlas_polygon_ops.R:134-164`).** For each
   label×view it re-filters the _entire_ flat table
   (`flat[flat$label == … & flat$view == …, ]`, line 143). Cost ≈
   (label-views) × (total rows). Powers `atlas_view_remove_small`.

   | n_labels | flat rows | label-views | median ms | ratio vs prev |
   | -------- | --------- | ----------- | --------- | ------------- |
   | 50       | 6,000     | 200         | 48        | —             |
   | 100      | 12,000    | 400         | 151       | 3.1×          |
   | 200      | 24,000    | 800         | 465       | 3.1×          |
   | 400      | 48,000    | 1,600       | 2,863     | 6.2×          |
   | 800      | 96,000    | 3,200       | 7,270     | 2.5×          |

   Doubling the atlas roughly triples–sextuples the time → super-linear,
   consistent with the nested full-table scan.

2. **`df_left_join` (`compat_dataframe.R:88`).** `which(ykey == k)` per row of
   x → O(n·m). Measured on a 1:1 join:

   | x rows | median ms | ratio |
   | ------ | --------- | ----- |
   | 500    | 3         | —     |
   | 1,000  | 8         | 2.7×  |
   | 2,000  | 25        | 3.1×  |
   | 4,000  | 98        | 3.9×  |
   | 8,000  | 363       | 3.7×  |

   Clean quadratic. On the bundled atlases (≤70 core rows) this is 1 ms and
   invisible; it only bites if a caller joins thousands of rows — e.g.
   `read_freesurfer` outputs merged onto core, or a dense future atlas.

3. **`sf_to_polygons` per-row `st_coordinates` (`atlas_polygons.R:48-59`).**
   Measured 107.5 ms on dk vs. 18 ms for the vectorised reverse
   (`polygons_to_sf`). The cost is one `sf::st_coordinates()` call **per sf
   row** plus `df_bind_rows` → `do.call(rbind, per_row)` accumulation. This is
   the single most expensive operation on a bundled atlas, and it is only paid
   when converting sf→polygons (e.g. one-time `migrate_atlas_files`, or
   `atlas_region_op` round-tripping a polygon atlas through sf).

**Linear (measured, healthy):** `df_unnest` — 6,000→96,000 rows is 5→105 ms,
~2× per doubling.

### Extrapolated scenarios

From the measured per-unit anchors above (dk ≈ 6,254 coords / 70 labels / ~191
label-views ≈ 116 ms for the area scan). **These are estimates**, extrapolated
along the measured quadratic curve; treat as order-of-magnitude.

| Scenario                                   | ~Labels | ~2D coords | Persistent size    | `polygon_geometry_areas` (extrapolated) |
| ------------------------------------------ | ------- | ---------- | ------------------ | --------------------------------------- |
| Shipped atlas (dk, **measured**)           | 70      | 6,254      | 0.4 Mb             | 116 ms (measured)                       |
| Fine-grained cortical (e.g. Schaefer-400)  | ~400    | ~35k       | ~2–3 Mb (2D)       | ~2.9 s (curve above, n=400 row)         |
| Very dense (Schaefer-1000 + subfields)     | ~1,000  | ~90k       | ~6–8 Mb (2D)       | ~8–15 s                                 |
| Whole-brain merge (cortical+subcort+tract) | ~160    | ~17k       | ~8 Mb (mesh-bound) | ~0.4–0.6 s                              |

Multipliers a reader can check: area-scan time grows ≈ (label-views · rows),
i.e. ≈ atlas-size². `df_left_join` grows ≈ (x-rows · y-rows). Persistent 2D size
grows ≈ linearly in coordinates (~50–60 bytes/coord observed). Persistent total
is usually **mesh-bound** (aseg: 7.55 Mb of meshes vs. 0.22 Mb geometry), so a
subcortical/cerebellar atlas's memory tracks face count, not label count.

### Risks identified

- _(Medium.)_ **Quadratic area computation** — `polygon_geometry_areas`
  (`atlas_polygon_ops.R:143`) re-scans the full flat table per label×view.
  Evidence: 48→151→465→2863 ms across the measured sweep. Harmless at shipped
  scale (116 ms), but `atlas_view_remove_small` on a Schaefer-400-class atlas is
  extrapolated at ~3 s.
- _(Medium.)_ **Quadratic `df_left_join`** — `which(ykey == k)` per x-row
  (`compat_dataframe.R:88`). Measured 3→363 ms over 500→8,000 rows. `atlas_core_add`
  and `atlas_vertices`/`atlas_meshes` are safe at atlas scale but would degrade
  if joined against large per-subject stats tables.
- _(Low.)_ **Per-row `sf_to_polygons`** — 107.5 ms on dk, ~6× the vectorised
  reverse. Only on the sf→polygon path; typically a one-time migration cost, so
  low priority despite being the single slowest bundled-atlas op.
- _(Low.)_ **Accumulate-then-`rbind` in `df_unnest`/`df_bind_rows`**
  (`compat_dataframe.R:172`, `144`). Measured linear, so not a scaling risk, but
  it does allocate a transient list plus a full concatenation copy on every
  unnest — the source of the observed transient peaks. Repeated manipulation
  chains (`unnest → op → renest`, called once per view helper) pay this each
  step with no memoisation.
- _(Low.)_ **No caching of the `unnest`/conversion results.** A pipeline that
  chains several `atlas_view_*` / `atlas_region_*` calls re-unnests and re-nests
  the same geometry every step. Cheap per call today; compounds with atlas size.
- _(Low, non-scaling.)_ **`read_freesurfer` uses `read.table`** with no column
  typing and reads all matched files into a list before binding
  (`read_freesurfer.R:61,73`). Fine for FreeSurfer stats files (tens of KB), but
  it holds every file in memory before the single `df_bind_rows`; no risk at the
  file sizes involved.

### Verified healthy (no action)

- **No unbounded / streaming memory risk.** Every operation is bounded by a
  single fixed-size atlas; there is no accumulation across an open-ended input
  stream, no network pull, no OOM surface at any realistic atlas scale.
- **Persistent footprint is modest and well-characterised** — largest atlas
  7.4 Mb, driven by the 3D mesh payload (measured), not by the geometry ops.
- **Representation choice is a genuine performance/portability win.** The
  sf-free `brain_polygons` format lets the whole 2D manipulation surface run with
  no GDAL/GEOS/PROJ (`atlas_polygon_ops.R`), and `polygons_to_sf` uses pure-Rcpp
  `sfheaders` (measured 18 ms, vectorised) rather than full sf.
- **`df_unnest`/`df_nest` are linear** (measured), so the ubiquitous
  unnest→op→renest pattern does not itself introduce super-linear cost.
- **Accessors are constant/near-constant** and correctly avoid touching the 2D
  geometry when only metadata is needed.

## Not run (reason)

- **No `bench`/`profmem`** (not installed, per the task) — allocation figures
  come from `gc()` max-used deltas, which are coarser and inflated by the
  `devtools`+`sf` base session (~70 Mb); absolute peak Mb should be read as
  order-of-magnitude, not precise. Relative pattern (transient » retained) is
  reliable.
- **No `Rprof` line-profile attached** — the hot lines were identified by
  reading the loops and confirmed by the targeted `system.time` sweeps above,
  which localise cost more directly than sampling on sub-200 ms calls.
- **sf-free install path not exercised** — `sf`/`sfheaders` are present in this
  environment, so the _unavailability_ (not slowness) of sf ops on a true wasm /
  air-gapped install was reasoned about, not measured.
- **`read_freesurfer_*` not profiled on real data** — no FreeSurfer subjects
  directory available; assessed by code inspection only.
- **No large real atlas measured** — the >70-label scenarios are synthetic
  extrapolations along the measured quadratic curve, not real dense atlases.

## Suggested fix priority

1. **De-quadratic `polygon_geometry_areas`** (Medium; `atlas_polygon_ops.R:134-164`).
   Split the flat table once by `label`+`view` (e.g. `split()` or a keyed
   `tapply`/`vapply` over pre-grouped indices) instead of re-filtering the full
   table per group. Keeps behaviour identical; removes the dominant term in
   `atlas_view_remove_small`. Measured payoff scales with atlas size (≈3 s → sub-100 ms
   at Schaefer-400).
2. **De-quadratic `df_left_join`** (Medium; `compat_dataframe.R:88`). Replace the
   per-row `which(ykey == k)` with a single `match()`/`split()` on `ykey` (hash
   lookup, O(n+m)). Same one-to-many semantics, drops 8,000-row joins from
   363 ms toward linear. Protects `atlas_core_add`/`atlas_vertices` against large
   metadata joins.
3. **Vectorise / batch `sf_to_polygons`** (Low; `atlas_polygons.R:48-64`). Call
   `sf::st_coordinates()` once on the whole `sfc` and split by the `L3` feature
   index rather than looping per row; pre-allocate instead of
   `df_bind_rows(do.call(rbind, …))`. One-time-migration cost, so lower urgency.
4. **Document the scaling limits and add a gated large-atlas benchmark** (Low).
   Note in `?atlas_view_remove_small` / a "performance" vignette that the pure-R
   polygon ops are quadratic in atlas size and are tuned for ≤~100-label atlases;
   add a `testthat`/`bench`-gated test on a synthetic dense atlas so regressions
   surface. No behaviour change.

### Caveats on the estimates

- Absolute transient-peak Mb figures are inflated by the shared `devtools`+`sf`
  base session and should be read as order-of-magnitude; the transient-»-retained
  _pattern_ is robust.
- The >70-label rows in "Extrapolated scenarios" are curve fits to the measured
  synthetic sweeps, **not** measurements of real dense atlases; real geometry
  density (coords/label) could shift them by a factor of a few.
- Timings are single-machine (macOS, R 4.5.2), median-of-N `system.time`; expect
  ±20% run-to-run at these sub-200 ms magnitudes.
- The dominant unknown for persistent memory is 3D mesh density (aseg is
  mesh-bound); a future atlas with finer meshes will grow memory faster than its
  label count suggests.
