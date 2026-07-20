# Review report template (shared)

The shared, canonical skeleton for every `run-*` review pass (`run-test-audit`,
`run-complexity`, `run-dependency-review`, `run-performance-review`, …). One
skeleton keeps reports consistent and **auditable**: a reader sees what was
asked, which skill ran, which model, what executed, and what did not. Fill every
section — an empty "Not run" or "Skill" is itself information. Each pass swaps in
its own **Findings** buckets (named in that pass's skill). If the user supplies
their own template, use theirs. One pass → one file, `Review_AI_<pass>.qmd`.

Copy the skeleton, replace `<…>`, delete the parenthetical guidance.

```markdown
---
title: "<PKG> <VERSION> — AI-Assisted <Pass> (e.g. Test-Suite Audit)"
author: "<Your Name> (AI-assisted, <harness> / <model>, e.g. Claude Code / Opus 4.8)"
date: <YYYY-MM-DD>
format:
  html:
    toc: true
    toc-depth: 3
    embed-resources: true # self-contained: attachable to the review issue
execute:
  eval: false # a record of a run, not a live notebook
---

# Prompt

> <The verbatim prompt that triggered this pass — quote it exactly.>

# Skill

<Which skill(s) drove this pass, plus version/source. Skill text changes over
time, so reproduce the operative instructions verbatim (blockquoted). If no skill
was used, say so and describe the method that replaced it.>

# Report

## Method

<Exactly what was run, so it reproduces: tool + package versions; commands and how
many times (e.g. "suite run twice with `devtools::test()`"; coverage via
`covr::package_coverage()`); offline/mock vs. live path; and an explicit
"No package files were modified.">

## Headline

<One paragraph: the verdict and the key number(s). Green/amber/red first, then the
caveat that matters most.>

## Findings

<Group into labelled buckets for this pass (named in the pass's skill), each tagged
_(High.)_ / _(Medium.)_ / _(Low.)_ and citing evidence: a `path/file.R:line`,
command output, or a reproduced probe. Prefer tables for profiles/inventories,
fenced code for reproducing snippets. Never assert a defect you have not shown.>

## Verified healthy (no action)

<What is genuinely well done — a review that only lists problems is neither fair
nor trustworthy. Cite evidence here too.>

## Not run (reason)

<Everything NOT exercised and why: unauthorized live/paid/network paths,
unavailable environments, out-of-scope checks. Silence here overstates coverage.>

## Suggested fix priority

<Ordered, highest-impact first, each pointing back to a finding above with its
severity. This is what the author acts on.>
```

Attribution is required, not decorative: the `author` line names both the human
accountable for the review and the AI harness/model — rOpenSci reviews are signed.
