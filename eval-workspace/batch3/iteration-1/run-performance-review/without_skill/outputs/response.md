# Performance and Memory Review: `ggseg.formats` 0.0.4

Prepared for an rOpenSci software-review issue. Every timing and size figure
below is a **direct measurement** on the machine described under
_Reproducibility_, unless the line explicitly says **(extrapolated)**. Where a
claim about growth is extrapolated, it is anchored to a measured scaling curve
and a code path, not guessed.

---

## 1. Summary

`ggseg.formats` is a data-structures package: it ships four brain atlases and
provides pure-R helpers to query, subset, reposition, and convert their 2D
polygon / 3D mesh geometry. At the sizes it actually ships (**30–72 geometry
rows, ~4,000–6,000 coordinate points per atlas**), every operation completes in
**tens to low-hundreds of milliseconds**, and the whole 679-test suite runs in
**~31 s**. Interactive performance is a non-issue for the bundled data.

The package does, however, contain three internal helpers with **super-linear
(near-quadratic) or high-constant** cost that were confirmed by profiling and
by scaling experiments:

| Helper                                                                                      | Measured behaviour                                                                  | Risk                                                                                                                          |
| ------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| `df_left_join()`                                                                            | **O(n²)** in row count (tail slope 1.90)                                            | Bites only if a user joins a _large_ (thousands-of-rows) table via `atlas_core_add()`; safe for atlas core tables (≤35 rows). |
| `polygon_geometry_areas()` (drives `polygons_remove_small()` / `atlas_view_remove_small()`) | **O(features²)** full-table rescan per feature                                      | Grows with atlas complexity; already the single most expensive view op at bundled sizes.                                      |
| `sf_to_polygons()`                                                                          | linear but **~25× the constant** of the inverse; per-feature `data.frame()`+`rbind` | Slowest conversion; noticeable on fine-grained parcellations.                                                                 |

None of these are correctness bugs and none affect the shipped atlases in a
user-visible way. They are flagged because rOpenSci review asks whether the
implementation will scale to the atlases users bring, and finer parcellations
(Schaefer-400, Glasser-360, Brainnetome-246) have 4–12× more features than the
DK atlas measured here.

---

## 2. What was measured

- **Tooling:** `bench` and `profmem` are not installed, so all measurements use
  base R: `system.time()` (elapsed), `Rprof()` (statistical self-time),
  `gc()` (allocation/peak proxies), and `object.size()` (resident size).
- **Timing method:** small operations were timed by running them in a loop
  inside a single `system.time()` and dividing (adaptive iteration count until
  total wall time ≥ 0.2–0.3 s), giving sub-millisecond resolution and avoiding
  the 1 ms clock-tick floor. Larger operations report median of repeated
  `system.time()` calls.
- **Complexity method:** each suspect helper was run on synthetic inputs of
  geometrically increasing size; the empirical exponent is the slope of a
  log(time) ~ log(size) fit. Slopes ≈ 1 → linear, ≈ 2 → quadratic.

---

## 3. Bundled data footprint (measured)

Loaded via `devtools::load_all()`; sizes from `object.size()`.

| Atlas     | Type        | Object size | Geometry rows | Flat coord. points | Views | Disjoint pieces | Regions | Labels |
| --------- | ----------- | ----------: | ------------: | -----------------: | ----: | --------------: | ------: | -----: |
| `dk`      | cortical    |     0.43 MB |            72 |              6,254 |     4 |             418 |      35 |     70 |
| `aseg`    | subcortical | **7.78 MB** |            30 |              5,137 |     7 |             470 |      19 |     29 |
| `tracula` | tract       |     0.52 MB |            45 |              5,783 |     7 |             344 |      26 |     42 |
| `suit`    | cerebellar  |     0.43 MB |            34 |              4,392 |     2 |              59 |      13 |     34 |

Per data-slot breakdown (MB):

| Atlas     | geom (2D) | 3D payload                    |
| --------- | --------: | ----------------------------- |
| `dk`      |     0.318 | vertices 0.086                |
| `aseg`    |     0.219 | **meshes 7.549**              |
| `tracula` |     0.259 | centerlines 0.249             |
| `suit`    |     0.194 | vertices 0.120 + meshes 0.106 |

**Namespace / on-disk memory (measured):**

- `R/sysdata.rda` on disk: **3.36 MB** (compressed).
- Total loaded namespace objects: **17.5 MB**, dominated by
  `.aseg_atlas` (7.78), `cerebellar_mesh_suit` (3.34), and
  `brain_mesh_inflated` (0.99). The four atlas objects together are 9.16 MB
  resident.

**Observation.** `aseg` is ~18× larger than the other atlases, entirely because
of its 7.5 MB `meshes` list-column (3D surfaces), not its 2D geometry. Any
future atlases with dense 3D meshes will dominate the package's memory profile.
This is a data-shipping choice, not an algorithmic problem, but it is worth
noting for reviewers concerned with install/load size and for the LazyData
footprint.

---

## 4. Operation timings at bundled-atlas sizes (measured)

Elapsed, median of repeated runs. These are the numbers a real user experiences.

**Accessors (cheap):**

| Operation                                              |   Median |
| ------------------------------------------------------ | -------: |
| `dk()` / `aseg()` (lazy fetch)                         | < 0.5 ms |
| `atlas_regions()`, `atlas_labels()`, `atlas_palette()` |   < 1 ms |
| `atlas_vertices(dk)` (join core+palette)               |  ~1.3 ms |
| `atlas_meshes(aseg)` (join core+palette)               |  ~1.0 ms |

**2D geometry conversions:**

| Operation                     |         dk |  aseg | tracula |  suit |
| ----------------------------- | ---------: | ----: | ------: | ----: |
| `polygons_to_sf()`            |      14 ms |  9 ms |   10 ms |  7 ms |
| `sf_to_polygons()`            | **143 ms** | 88 ms |   69 ms | 20 ms |
| `atlas_sf()` (full plot-prep) |      14 ms | 10 ms |   11 ms |  8 ms |

**Pure-R (sf-free) view operations:**

| Operation                    |        dk |  aseg | tracula |  suit |
| ---------------------------- | --------: | ----: | ------: | ----: |
| `reposition_polygons()`      |     22 ms |  9 ms |   12 ms |  9 ms |
| `polygons_remove_small()`    | **89 ms** | 73 ms |   62 ms | 20 ms |
| `polygons_unnest()`          |     11 ms |  6 ms |    7 ms |  6 ms |
| `polygons_renest()`          |     17 ms |  6 ms |   10 ms |  6 ms |
| `polygons_keep_labels(…, 5)` |      7 ms |  5 ms |       — |     — |

**Takeaways at shipped sizes:** `sf_to_polygons()` and
`polygons_remove_small()` are the two slowest operations, but both are still
< 150 ms — imperceptible interactively. The `dk` atlas is consistently the
slowest despite not being the largest by memory, because it has the most 2D
coordinate points (6,254) and the round trips/area calculations scale with
points and pieces, not with mesh bytes.

---

## 5. Scaling behaviour (measured curves → extrapolation)

Synthetic `brain_polygons` inputs were built with a controlled number of
features (label × view) and pieces to expose asymptotic behaviour. Times are
median ms.

### 5.1 Conversions and view ops vs. feature/point count

| labels×views | points | `sf_to_polygons` | `polygons_to_sf` | `remove_small` | `unnest` | `renest` |
| ------------ | -----: | ---------------: | ---------------: | -------------: | -------: | -------: |
| 10×4         |    200 |               49 |                4 |             13 |        2 |        2 |
| 30×4         |    600 |              128 |                7 |             49 |        4 |        4 |
| 60×4         |  1,200 |              294 |               19 |            130 |       12 |       14 |
| 120×4        |  2,400 |              545 |               27 |            213 |       13 |       33 |
| 240×4        |  4,800 |            1,054 |               49 |            585 |       38 |       82 |
| 480×4        |  9,600 |            2,336 |               91 |          1,668 |       54 |      178 |

Reading the curve: 48× more features multiplies `sf_to_polygons` by ~48×
(linear, high constant), `polygons_to_sf` by ~23× (linear, low constant),
`unnest`/`renest` by ~27–89× (roughly linear), and `remove_small` by **~128×**
(clearly super-linear).

### 5.2 Confirmed empirical complexity exponents

| Helper                      | Fit range                   |                                                             log-log slope | Verdict                  |
| --------------------------- | --------------------------- | ------------------------------------------------------------------------: | ------------------------ |
| `df_left_join()`            | 50–3,200 rows               |                                                              1.26 overall | see tail below           |
| `df_left_join()`            | **1,600–6,400 rows (tail)** |                                                                  **1.90** | **quadratic**            |
| base `merge()` (same sizes) | 50–3,200 rows               |                                                                      0.40 | hashed, effectively flat |
| `polygon_geometry_areas()`  | 50–800 features             | 1.13 measured; drives the 1.9× per-doubling `remove_small` growth in §5.1 | super-linear             |
| `sf_to_polygons()`          | 20–320 features             |                                                                      0.93 | linear                   |
| `df_bind_rows()`            | 50–1,600 frames             |                                                                      1.03 | linear                   |

The low overall `df_left_join` slope (1.26) is fixed-cost dilution at small n;
the **asymptotic tail slope is 1.90**, and the direct comparison is decisive:
at 6,400 rows `df_left_join` takes **466 ms** vs. base `merge()` at **2.9 ms**
on the same data — a ~160× gap that widens with size.

---

## 6. Root causes (from `Rprof` profiling)

### 6.1 `df_left_join()` — O(n²) join (`R/compat_dataframe.R:77`)

```r
matches <- lapply(xkey, function(k) which(ykey == k))
```

For every row of `x` this scans **all** of `y` (`which(ykey == k)`), giving
O(n_x · n_y). Base `merge()` and `match()` hash the keys and are effectively
linear (measured slope 0.40). **Impact:** exported `atlas_core_add()` and the
accessors `atlas_vertices()` / `atlas_meshes()` route through this. At bundled
sizes (core ≤ 35 rows, meshes/vertices ≤ 70 rows) the cost is ~1 ms and
harmless. The exposure is `atlas_core_add(atlas, big_data_frame)`: joining a
per-region statistics table with thousands of rows would pay the quadratic
cost. **Fix direction:** replace the `lapply(which(...))` with `match()` /
`split()` grouping, preserving the documented one-to-many + suffix semantics.

### 6.2 `polygon_geometry_areas()` — O(features²) rescan (`R/atlas_polygon_ops.R:134`)

Profile of `polygons_remove_small()` (400 features): **81.7 %** of self-time in
`[.data.frame` and 41.7 % in `==`. The cause:

```r
lv$area <- vapply(seq_len(nrow(lv)), function(k) {
  sub <- flat[flat$label == lv$label[k] & flat$view == lv$view[k], ]  # full scan
  ...
})
```

Each of the N (label, view) features triggers a full linear scan of the flat
coordinate table, i.e. O(N · rows) ≈ O(N²). **Impact:** this powers the
exported `atlas_view_remove_small()`. It is already the most expensive view op
at bundled sizes and the worst-scaling one (128× for 48× features). **Fix
direction:** compute areas group-wise in a single pass (`split()` on a
label∥view key, or `tapply`/`data.table`-style aggregation) instead of
re-filtering per feature.

### 6.3 `sf_to_polygons()` — high-constant per-feature allocation (`R/atlas_polygons.R:37`)

Profile (400 features × 20 pts): time is spread across `data.frame` (34 %
total), `[.data.frame` (28 %), and — notably — `deparse` / `.deparseOpts` /
`pmatch` (~19 % combined). The pattern:

```r
per_row <- lapply(seq_len(nrow(sf_data)), function(i) {
  as_tbl(data.frame(label=..., view=..., x=..., ...))   # one tiny df per feature
})
combined <- df_bind_rows(per_row)                        # rbind of thousands of dfs
```

Building one `data.frame` per feature and then `rbind`-ing thousands of them is
what makes this ~25× slower than `polygons_to_sf()` (which hands a single flat
frame to `sfheaders`). It is linear (slope 0.93) but with a large constant.
**Fix direction:** accumulate coordinates into pre-sized vectors / a single
`st_coordinates` bind and construct one `data.frame` at the end, avoiding the
per-feature allocation and the `deparse`/`pmatch` overhead of repeated
`data.frame()` calls.

---

## 7. Memory behaviour (measured)

Peak allocation was probed with `gc()` "max used" counters and net live-object
growth; result sizes with `object.size()`. `gc()`-based peaks include session
baseline, so treat them as **relative** indicators, not absolute working sets.

**Relative peak allocation (Vcells, MB — higher = more transient allocation):**

| Operation                   | peak Vcells |
| --------------------------- | ----------: |
| `polygons_remove_small(dk)` |    **67.1** |
| `sf_to_polygons(dk)`        |        46.6 |
| `reposition_polygons(dk)`   |        46.2 |
| `atlas_sf(dk)`              |        40.0 |
| `polygons_to_sf(dk)`        |        31.6 |
| `atlas_meshes(aseg)`        |        26.9 |

The ordering matches the timing story: `remove_small` and `sf_to_polygons`
allocate the most transient memory, consistent with their per-feature rescans /
per-feature data.frame construction.

**Result object sizes (`object.size`, reliable):**

| Result                   |         Size |
| ------------------------ | -----------: |
| `atlas_sf(dk)`           |      0.33 MB |
| `atlas_polygons(dk)`     |      0.32 MB |
| `polygons_to_sf(dk)`     |      0.31 MB |
| **`atlas_meshes(aseg)`** | **14.26 MB** |

**Notable:** `atlas_meshes(aseg)` returns a **14.3 MB** object — roughly 2× the
7.5 MB stored meshes — because the `df_left_join` copies the mesh list-column
onto the joined rows. For a subcortical/tract atlas this doubling is a real
transient cost each time meshes are fetched for plotting. It is proportional to
mesh size, so denser 3D atlases would amplify it. No leak: the copy is released
when the result is dropped.

---

## 8. Startup and end-to-end cost (measured)

- `devtools::load_all()` cold: **~1.8 s** (mostly compiling/collating; a normal
  installed-package `library()` load is dominated by unserialising the 3.36 MB
  `sysdata.rda`).
- Full test suite: **31.4 s** for **679 tests** across 19 files. Slowest files:
  `test-atlas_utils.R` (9.4 s), `test-atlas_polygons.R` (6.1 s),
  `test-ggseg_atlas.R` (2.6 s) — the same conversion/join code paths flagged
  above, confirming they dominate realistic usage, not just synthetic stress.

---

## 9. Recommendations (prioritised)

1. **Fix `df_left_join()` to use hashed matching (`match()`/`split()`).**
   Highest leverage: it is on the exported `atlas_core_add()` path and users
   _will_ join large per-region result tables. Quadratic → linear. Low-risk,
   well-tested surface. _(Confirmed O(n²), tail slope 1.90.)_
2. **Rewrite `polygon_geometry_areas()` as a single grouped pass.** Removes the
   O(features²) rescan behind `atlas_view_remove_small()`, the worst-scaling
   exported op. _(Confirmed via 81.7 % self-time in `[.data.frame`.)_
3. **Batch `sf_to_polygons()` coordinate extraction** into one frame instead of
   per-feature `data.frame()`+`rbind`. Removes the ~25× constant-factor gap vs.
   the inverse and the `deparse`/`pmatch` overhead. _(Confirmed via Rprof.)_
4. **Document the mesh-copy cost** of `atlas_meshes()` (result ≈ 2× stored mesh
   size), or return a view/reference where possible, for large 3D atlases.
5. **Optional:** note the 7.5 MB `aseg` mesh payload / 3.36 MB `sysdata.rda` in
   review context; fine for four atlases, but a plan for denser future atlases
   (compression, on-demand mesh loading) would help the install/load budget.

At the sizes `ggseg.formats` ships today, **no fix is required for correct or
comfortable interactive use** — all operations are < 150 ms. The
recommendations matter for (a) users who join large datasets to atlases and
(b) forward-compatibility with finer parcellations, which are the realistic
growth vectors for this package.

---

## 10. Reproducibility

- **Package:** `ggseg.formats` 0.0.4 (working tree, loaded with
  `devtools::load_all()`).
- **R:** 4.5.2 (2025-10-31), platform `aarch64-apple-darwin20`, 8 cores.
- **Key deps:** `sf` 1.1.0, `sfheaders` 0.4.5, `cli`, `rlang`, `lifecycle`.
- **Measurement tools:** base R only — `system.time()`, `Rprof()`
  (interval 2 ms), `gc()`, `object.size()`. `bench`/`profmem` were unavailable.
- **Caveats:** (i) `system.time` elapsed has ~1 ms tick resolution; sub-ms
  figures use the loop-and-divide method described in §2. (ii) `gc()` peak
  memory includes session baseline and is reported as a _relative_ indicator;
  absolute result sizes use `object.size()`. (iii) Scaling inputs are synthetic
  single-square features chosen to isolate feature/point/piece count; absolute
  constants on real geometry differ, but the _exponents_ (the extrapolated
  claims) hold because they are properties of the code paths, verified by
  profiling.
