---
name: run-dependency-review
description: >-
  Actually CARRY OUT an AI-assisted dependency analysis of an R package and
  produce a transparent, reproducible report. Use this when someone says "review
  the dependencies", "which dependencies could we drop", "can base R replace
  this import", "is this dependency worth it", or wants an evidence-backed
  dependency write-up for an rOpenSci review. This DRIVES the analysis (walks the
  recursive dependency tree, separates prunable leaves from pinned packages,
  counts real usage, checks base-R feasibility) and emits a report; it does not
  edit the package. It is the dependency pass of a review — one of the `run-*`
  review-runner skills. For the reviewer checklist and the other passes, see
  `package-review` / `run-package-review`.
---

# Run a Dependency Review (AI-assisted, reporting)

An **action** skill: it decides which of a package's dependencies are genuinely
worth removing and writes a trustworthy report. The governing insight — **a
dependency is only worth removing if doing so actually prunes the install
tree** — keeps the analysis honest: dropping a direct import that a package you
must keep also requires changes nothing on disk.

This is the dependency pass of an rOpenSci review. For the full reviewer context
see `package-review`; for the dependency-choice standards see `package-standards`.

## Ground rules (these make the report trustworthy)

- **Prune the tree, not the count.** Only recommend removing a dependency when
  (a) it is reachable **only** through this package's own direct import (a
  prunable leaf), and (b) its usage is light enough to replace without losing
  correctness or readability. Removing a package that `httr2`/`dplyr`/etc. also
  pull in is cosmetic.
- **Count real usage.** Base recommendations on how many times, and where, each
  imported function is actually called — not on reputation.
- **Base-R replacement must preserve behaviour and readability.** A two-line
  helper that reads worse than the dependency is not a win.
- **Respect the maintainer's stated preferences** (e.g. a deliberate tidyverse
  or zero-dependency stance).
- **Read-only.** Don't edit `DESCRIPTION` or `R/` to prove a point; propose,
  with evidence.

## Method

1. **Build the recursive dependency tree** (e.g. `pkgnet::DependencyReporter`,
   or `tools::package_dependencies(recursive = TRUE)` / `pak::pkg_deps_tree()`).
   Record the node/edge counts.
2. **Reverse-dependency analysis** over that edge list: for each candidate,
   _which_ packages require it? This separates **prunable leaves** (reachable
   only via this package's import) from packages **pinned** by core dependencies
   you must keep. Cutting a pinned package prunes nothing.
3. **Usage counts** of every imported function across `R/*.R` — how many call
   sites, and in which functions.
4. **Base-R feasibility** of replacing each usage, judged on correctness and
   readability. Note where a replacement rides along with a refactor recommended
   elsewhere (e.g. an engine that collapses N call sites to one).
5. **Weigh footprint**: compiled/large dependencies (e.g. a `stringi` pulled in
   only via `stringr`) are higher-value cuts than tiny pure-R ones.

## Report

Write `Review_AI_dependencies.qmd` from the **shared report template** at
`../run-package-review/references/report-template.md` (one template across all
`run-*` passes, for consistency; if the user supplies their own, use theirs).
Fill the transparency header first (**Prompt**; the **Skill**/method used — say
so plainly if done by direct analysis rather than a named skill; the **Method**
with tools/versions and an explicit "no files modified"), then:

- A **Summary** table: dep · uses · functions used · prunable? · base-R
  replacement · verdict.
- **Tier 1 — clear wins** (small change, real footprint reduction — flag any
  that also eliminate a heavy transitive dependency).
- **Tier 2 — worth doing** (moderate effort, often bundled with another
  refactor).
- **Tier 3 — defer** (real benefit, large rewrite).
- **Keep — removal buys nothing** (pinned by a core dependency, or the return-
  type contract) — say _why_ each stays.
- **Recommendation** (the shortlist) and a **Caveat** that tree membership
  reflects the versions installed at review time.

Every claim cites evidence: the edge count, a usage count, or the specific
functions replaced.

## Related skills

- The umbrella review runner → `run-package-review`.
- The sibling review passes, runnable one at a time → `run-test-audit`,
  `run-complexity`, `run-performance-review`.
- The reviewer checklist & "what to evaluate" → `package-review`.
- The standards being checked → `package-standards`; statistical → `stats-standards`.
