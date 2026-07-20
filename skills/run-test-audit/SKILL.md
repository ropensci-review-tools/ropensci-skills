---
name: run-test-audit
description: >-
  Actually CARRY OUT an AI-assisted audit of an R package's test suite and
  produce a transparent, reproducible report. Use this when someone says "audit
  the tests", "review the test suite", "how good are these tests", "are the
  tests actually testing anything", or wants an evidence-backed test-quality
  write-up for an rOpenSci review. This DRIVES the audit (reads the tests and
  the code, runs the suite for real, measures coverage depth, hunts flakiness)
  and emits a report; it does not fix or add tests. It is the test-suite pass of
  a review — one of the `run-*` review-runner skills. For the reviewer checklist
  and the other passes, see `package-review` / `run-package-review`.
---

# Run a Test-Suite Audit (AI-assisted, reporting)

An **action** skill: it audits the _quality_ of an existing test suite and writes
a trustworthy report. The premise — **the implementation is the contract and the
tests are the artifact under review** — judged on whether they cover what
matters, mean anything, and stay stable. (Mirror image of a docs audit, where
the docs are the contract.)

This is the test-suite pass of an rOpenSci review. For the full reviewer context
see `package-review`; for the standards see `package-standards`.

## Ground rules (these make the report trustworthy)

- **Read the tests _and_ the code.** You cannot judge branch coverage from the
  tests alone.
- **Run the suite for real, more than once** — and shuffled / re-seeded where
  cheap — to surface flakiness.
- **Read-only.** No edits to fix or add tests. Throwaway probes in a scratch
  session are fine; changes to the package tree are not.
- **Non-destructive & authorized.** Don't run destructive, paid, or network
  operations without authorization — note the offline path and mark live paths
  **"not run."**
- **Coverage is evidence, not the verdict.** High line coverage can mean
  breadth (lines execute), not depth (outputs are checked). Say which.

## Method

1. **Map the surface.** Enumerate the public/exported set
   (`getNamespaceExports()`) against the functions actually referenced by tests.
   Note untested exports.
2. **Run it, repeatedly.** Execute with `devtools::test()` (twice; shuffled/
   re-seeded where cheap), capturing pass/fail/warn/**skip** counts, timing, and
   any silent skips. Measure line coverage with `covr::package_coverage()`.
3. **Check coverage depth**, not just the number: happy path, edge cases
   (`NULL` / `NA` / empty / boundary), **every error branch**, each meaningful
   conditional.
4. **Check the assertions mean something.** Flag tautologies, no-assertion
   tests, over-loose matchers (bare `expect_error()` with no `class=`/`regexp=`),
   and over-mocked tests that only verify the mock.
5. **Hunt flakiness sources**: wall-clock/time dependence, unseeded randomness,
   global state, order-dependence between files, hidden skips. Review snapshots.
6. **Reproduce suspected defects** with throwaway probes and cite the result.
7. **Review consistency & maintainability**: duplicated setup, mega-`test_that()`
   blocks, dead/`.blob` test files, misleading tags.

## Report

Write `Review_AI_test_audit.qmd` from the **shared report template** at
`../run-package-review/references/report-template.md` (one template across all
`run-*` passes, for consistency; if the user supplies their own, use theirs).
Fill the transparency header first (**Prompt**, the operative **Skill** text
reproduced verbatim, the **Method** with tool versions and an explicit "no files
modified"), then the findings in four buckets, each finding carrying a severity
and cited evidence (`file.R:line`, command output, or a reproduced probe):

- **A. Coverage gaps** — untested exports, unasserted return values, unexercised
  branches.
- **B. Weak or meaningless tests** — smoke-only assertions, hollow tests,
  bare `expect_error()`, duplicates.
- **C. Instability / flakiness** — time-bombs, wall-clock coupling, unseeded
  randomness, order-dependence.
- **D. Consistency / maintainability** — duplicated bootstrap, oversized
  `test_that()` blocks, dead files, bogus tags.

Then a **Verified healthy (no action)** list, a **Coverage snapshot** table, a
**Not run (reason)** list, and an ordered **Suggested fix priority**.

## Related skills

- The umbrella review runner → `run-package-review`.
- The sibling review passes, runnable one at a time → `run-complexity`,
  `run-dependency-review`, `run-performance-review`.
- The reviewer checklist & "what to evaluate" → `package-review`.
- The standards being checked → `package-standards`; statistical → `stats-standards`.
