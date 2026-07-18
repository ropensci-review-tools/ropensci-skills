---
name: run-performance-review
description: >-
  Actually CARRY OUT an AI-assisted performance and memory analysis of an R
  package and produce a transparent, reproducible report. Use this when someone
  says "review the performance", "is this memory-safe on large inputs", "where
  are the hot paths", "does this scale", "will this OOM", or wants an
  evidence-backed performance write-up for an rOpenSci review. This DRIVES the
  analysis (traces the hot path, measures real anchors, extrapolates to large
  inputs, identifies risks) and emits a report; it does not edit the package. It
  is the performance pass of a review — one of the `run-*` review-runner skills.
  For the reviewer checklist and the other passes, see `package-review` /
  `run-package-review`.
---

# Run a Performance Review (AI-assisted, reporting)

An **action** skill: it characterises where a package spends time and memory,
how it scales, and where it will fall over — then writes a trustworthy report.
The discipline is **measure a real anchor, then extrapolate transparently**:
never assert a scaling claim you can't tie back to a measured figure.

This is the performance pass of an rOpenSci review. For the full reviewer
context see `package-review`; for the standards see `package-standards`.

## Ground rules (these make the report trustworthy)

- **Trace before you profile.** Understand the data/compute path end to end —
  where I/O happens, where results accumulate — before quoting numbers.
- **Anchor on measured data.** Profile real inputs, or measure the package's own
  recorded fixtures (`object.size()`, row/column counts, per-row cost). State
  which figures are _measured_ and which are _extrapolated_.
- **Extrapolate explicitly.** Show the multipliers (rows/site/year, bytes/row,
  transient vs. persistent) so a reader can check the arithmetic and see the
  assumptions.
- **Distinguish the persistent result from the transient peak** — the peak
  (in-flight parse + accumulated result + concatenation copy) is usually what
  OOMs, not the final object.
- **Measured wins only.** Recommend an optimization only where the trace or a
  measurement shows it matters; keep behaviour identical.
- **Read-only.** Don't edit the package; propose, with evidence.

## Method

1. **Trace the hot path** over `R/*.R`: every I/O / HTTP egress point, the
   chunking strategy, any caching / temp files / streaming, and where results
   are accumulated vs. flushed. Sketch the call chain.
2. **Measure anchors.** Profile representative inputs (`Rprof`,
   `bench::mark()`, `profmem`/`gc()` for allocation), or measure the recorded
   fixtures: sizes, parsed rows/cols, in-memory `object.size()`, per-row bytes,
   resolution.
3. **Identify what scales** and what doesn't — separate the cheap summary paths
   from the ones whose cost grows with input.
4. **Extrapolate scenarios** from the measured per-unit anchors to realistic
   large queries, tabulating rows · final size · **peak transient**.
5. **Enumerate risks**: memory-bound large operations (no streaming/incremental
   flush), silent partial results on truncation, no caching → repeated work, no
   resumability/checkpointing.

## Report

Write `Review_AI_performance.qmd` from the **shared report template** at
`../run-package-review/references/report-template.md` (one template across all
`run-*` passes, for consistency; if the user supplies their own, use theirs).
Fill the transparency header first (**Prompt**; the **Skill**/method used — say
so plainly if done by direct analysis rather than a named skill; the **Method**
with tools/versions and an explicit "no files modified"), then:

- **Architecture of the hot path** — in-memory vs. streamed, the single
  chokepoint(s), the chunking strategy, accumulate-then-concatenate vs.
  incremental. Include the call-chain sketch.
- **Measured anchors** — a table from fixtures/profiling (rows · in-memory ·
  bytes/row · resolution), separating persistent from transient cost.
- **What scales / what doesn't**, then **Extrapolated scenarios** (a table:
  input · rows · final size · peak transient), clearly labelled as estimates.
- **Risks identified** — each with the evidence that implies it.
- **Recommendations** (document limits, detect truncation, optional caching,
  incremental concatenation, a network-gated large-pull test) and **Caveats**
  on the estimate (dominant unknowns).

Every claim cites evidence: a `file.R:line` in the trace, a measured size, or a
profile.

## Related skills

- The umbrella review runner → `run-package-review`.
- The sibling review passes, runnable one at a time → `run-test-audit`,
  `run-complexity`, `run-dependency-review`.
- The reviewer checklist & "what to evaluate" → `package-review`.
- The standards being checked → `package-standards`; statistical → `stats-standards`.
