---
name: run-package-review
description: >-
  Actually CARRY OUT an AI-assisted rOpenSci review pass on a package working
  tree and produce a transparent, reproducible report — as opposed to just
  providing review context. Use this when someone says "run the review",
  "audit this package's tests / dependencies / complexity / performance",
  "produce a review report", or wants an evidence-backed write-up they can
  attach to a `ropensci/software-review` issue. This skill DRIVES the work and
  emits a report; the sibling `package-review` skill supplies the reviewer
  checklist and "what to evaluate" context that this skill reads to decide what
  to check. For a human deciding *how* to review, use `package-review`; to make
  an agent *do* a review and report on it, use this.
---

# Run an rOpenSci Review (AI-assisted, reporting)

This is an **action** skill. Where `package-review` tells a reviewer _what_ to
evaluate, this skill _does_ one or more review passes on a package's working
tree and writes a **transparent, reproducible report** for each — the kind a
reviewer can inspect, trust, and attach to the public
`ropensci/software-review` issue.

Load `package-review` for the reviewer checklist / "evaluate beyond the
checkboxes" list and `package-standards` for the standards being checked. This
skill adds the _run it and report it_ layer on top.

## Ground rules (non-negotiable — these make the report trustworthy)

- **Read-only.** Do not edit, fix, or add to the package to make a check pass.
  Throwaway probes in a scratch session are fine; changes to the package tree
  are not.
- **Run it for real.** Don't review from reading alone. Execute the suite,
  measure coverage, run the analysis tools — repeatedly and, where cheap,
  shuffled / re-seeded to surface flakiness.
- **Evidence, not assertion.** Every finding cites what proves it: a
  `file.R:line`, a command's output, a reproduced probe. No hand-waving.
- **Non-destructive & authorized.** Never run destructive, paid, or network
  operations without explicit authorization. Note the offline path and mark
  live paths **"not run."**
- **Coverage numbers are evidence, not the verdict.** High line coverage can
  mean breadth, not depth — say so.
- **Full transparency in the output.** The report reproduces the _prompt_ that
  triggered it, the _skill text_ used (skills change over time, so capture the
  version that ran), the _model_, the _method_ (exact commands, tool versions,
  what was and wasn't modified), and what was **not run** and why. See
  `references/report-template.md`.

## Workflow

1. **Confirm scope & authorization.** Which package (path / working tree)?
   Which review pass(es)? Is network / paid / live-API access authorized, or
   offline-only? Note any conflict of interest (see `package-review`).
2. **(Optional) Establish design context first.** For an unfamiliar package,
   extract its design history from the git log before reviewing — it surfaces
   the architecture, the churn hotspots, and the decisions behind the code.
   Follow `references/git-design-history.md`.
3. **Pick the review pass(es).** Each is an independent, focused report. The
   dimensions below come straight from `package-review`'s "evaluate beyond the
   checkboxes" list, and mirror real rOpenSci review reports.
4. **Run the pass for real** under the ground rules above, capturing evidence
   as you go (commands, versions, timings, skips, warnings, reproduced probes).
5. **Write the report** from `references/report-template.md`, one file per pass
   (`Review_AI_<pass>.qmd`). Fill the transparency header, then the findings.
6. **Link it back.** Reports are meant to be attached to / linked from the
   public review issue. Keep them self-contained (`embed-resources: true`).

## The review passes

Each pass is available as its own focused `run-*` skill and produces one
self-contained report. Run them **one at a time** (invoke the dedicated skill),
or orchestrate several from here. Start from the checklist item in
`package-review`; the notes below say what "running it" concretely means.

- **Test-suite audit** → `run-test-audit`. The implementation is the contract, the tests are the
  artifact under review. Enumerate public surface vs. tested set; run the suite
  more than once (shuffled/re-seeded where cheap); check coverage _depth_ (happy
  path, `NULL`/`NA`/empty/boundary, every error branch, each meaningful
  conditional); flag weak assertions (tautologies, no-assertion tests, bare
  `expect_error()`, over-mocked tests that only verify the mock); hunt flakiness
  (time, unseeded randomness, global state, order-dependence, hidden skips).
  Report buckets: **A** coverage gaps, **B** weak/meaningless tests, **C**
  instability/flakiness, **D** consistency/maintainability — plus a verified-
  healthy list, a coverage snapshot, a not-run list, and a fix priority.
- **Code-complexity analysis** → `run-complexity`. Measure, don't eyeball.
  Cyclomatic complexity per function (e.g. `cyclocomp`), LOC, nesting depth,
  `if`/`for` counts; a static call-graph over `R/` to find duplication and
  call-site counts. Confirm behavioural findings with runtime probes. Recommend
  simplifications that keep the **user-facing surface unchanged**; flag genuine
  API/UX issues separately.
- **Dependency review** → `run-dependency-review`. Could base R or a lighter
  dependency replace a heavy or transitive one? Tier the recommendations (clear
  wins → worth-doing → defer), note what removal buys nothing, and respect the
  maintainer's stated preferences. Weigh whether a cut actually **prunes the
  install tree**, not just the dependency count.
- **Performance review** → `run-performance-review`. Trace the hot path, measure
  on representative inputs (or recorded fixtures), extrapolate to large queries,
  and flag risks (memory-bound pulls, silent truncation). Distinguish measured
  wins from speculative ones; keep behaviour identical.

Other `package-review` items (documentation, API design, real-world testing,
UI/UX) can be run the same way and reported with the same shared template. New
passes should follow the `run-<thing>` convention and reuse
`references/report-template.md` so every report stays consistent.

## Statistical packages

For a package under the statistical-software track, also run the `srr` /
`autotest` machinery (see `stats-standards`) and report standards compliance in
the same transparent format.

## Related skills

- The focused per-dimension passes → `run-test-audit`, `run-complexity`,
  `run-dependency-review`, `run-performance-review`.
- The reviewer checklist & "what to evaluate" this skill acts on → `package-review`.
- The standards being checked → `package-standards`; statistical → `stats-standards`.
- The author's side (preparing a package for these checks) → `peer-review-author`.
