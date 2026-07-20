---
name: run-complexity
description: >-
  Actually CARRY OUT an AI-assisted code-complexity analysis of an R package and
  produce a transparent, reproducible report. Use this when someone says
  "analyse the complexity of this package", "which functions are too complex /
  could be simplified", "find the god-functions", "where's the duplication", or
  wants an evidence-backed simplification write-up for an rOpenSci review. This
  DRIVES the analysis (measures complexity per function, builds a static
  call-graph, confirms findings with runtime probes) and emits a report; it does
  not refactor the package. It is the code-complexity pass of a review — one of
  the `run-*` review-runner skills. For the reviewer checklist and the other
  passes, see `package-review` / `run-package-review`.
---

# Run a Code-Complexity Analysis (AI-assisted, reporting)

An **action** skill: it locates where a package's complexity actually
concentrates and recommends simplifications that **keep the user-facing surface
unchanged**, then writes a trustworthy report. The discipline is **measure,
don't eyeball** — cyclomatic complexity and a static call-graph point you at the
real offenders; targeted source-reading and runtime probes confirm what they
mean.

This is the code-complexity pass of an rOpenSci review. For the full reviewer
context see `package-review`; for the standards (code style, dependencies) see
`package-standards`.

## Ground rules (these make the report trustworthy)

- **Measure first.** Rank functions by a real metric before reading source; the
  eye is a poor complexity meter and misses structural duplication entirely.
- **Read the code to interpret the numbers.** A high score can be benign
  (a chain of `&&` guards); a low score can hide 85× duplication. The metric
  points; you judge.
- **Confirm behavioural claims with runtime probes.** If you say a function is
  inert or its error path is broken, reproduce it in a scratch session and paste
  the result.
- **Read-only.** No refactoring the package to prove a point. Throwaway probes
  are fine; changes to the package tree are not.
- **Preserve the user-facing surface.** Every internal-refactor recommendation
  must keep exported names, signatures, and return types identical. Genuine
  API/UX changes are flagged **separately** as optional, not folded into
  "simplification".

## Method

1. **Per-function metrics.** With `devtools::load_all()`, compute cyclomatic
   complexity for every function in the namespace (e.g. `cyclocomp::cyclocomp()`),
   plus lines-of-code, maximum brace-nesting depth, and `if`/`for` counts from
   the deparsed bodies. Rank; note the distribution (most functions are usually
   trivial — complexity concentrates in a few).
2. **Static call-graph.** Over `R/*.R`, use token analysis
   (`utils::getParseData()`) to measure **duplication** (near-identical bodies)
   and to count **call sites** of key helpers. Cyclomatic complexity is blind to
   copy-paste across files; this is where you find it.
3. **Targeted source reading** of the top offenders to characterise _why_ they
   are complex (god-function, deep nesting, repeated block) and whether it's
   genuine or measurement artefact.
4. **Runtime probes** to confirm behavioural findings surfaced while measuring
   (e.g. validation that never runs, an error path that throws the wrong error).

## Report

Write `Review_AI_complexity.qmd` from the **shared report template** at
`../run-package-review/references/report-template.md` (one template across all
`run-*` passes, for consistency; if the user supplies their own, use theirs).
Fill the transparency header first (**Prompt**; the **Skill**/method used — say
so plainly if a pass was done by direct measurement rather than a named skill;
the **Method** with tool versions and an explicit "no files modified"), then:

- **Measured profile** — a table (function · where · cc · LOC · `if` blocks ·
  verdict) and the cc distribution. Lead with the takeaway (e.g. "per-function
  complexity is fine except one outlier; the real issue is duplication").
- **Hotspot N** — one subsection per offender, each with a minimal reproducing
  snippet and a concrete refactor that keeps the user-facing surface identical
  (prefer explicit shims over function-factories so `?help`, autocomplete, and
  `@inheritParams` keep working). Note any latent bugs found while measuring.
- **Minor** — smaller simplifications not worth a hotspot.
- **User-facing recommendations (API unchanged, but worth noting)** — genuine
  discoverability / naming / UX points, kept clearly separate and marked
  optional.
- **Suggested fix priority** — ordered, highest-impact first, each with a
  severity and a pointer back to the hotspot.

Every claim cites evidence: a `file.R:line`, a metric, or a reproduced probe.

## Related skills

- The umbrella review runner → `run-package-review`.
- The sibling review passes, runnable one at a time → `run-test-audit`,
  `run-dependency-review`, `run-performance-review`.
- The reviewer checklist & "what to evaluate" → `package-review`.
- The standards being checked → `package-standards`; statistical → `stats-standards`.
