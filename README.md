# rOpenSci Skills

A collection of [Agent Skills](https://www.anthropic.com/news/skills) that help R developers follow [rOpenSci](https://ropensci.org/)'s guides and books — from writing a package that meets the standards, through peer review, release, and long-term maintenance, to blogging about it.

Each skill packages the relevant chapters of the rOpenSci [Developer Guide](https://devguide.ropensci.org/), [Statistical Software Guide](https://stats-devguide.ropensci.org/), and [Blog Guide](https://blogguide.ropensci.org/) into focused, on-demand guidance that an LLM agent (e.g. Claude) can load only when it's actually needed.

## The skills

| Skill                        | What it helps with                                                                                                                                                                                                                                                                                              |
| ---------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **`package-standards`**      | Build or audit an R package against rOpenSci's package development standards: naming, `DESCRIPTION`/`Authors@R`, dependency choices, roxygen2 docs, README, testing & coverage, code style, CI, and security. The foundation the other skills build on.                                                         |
| **`peer-review-author`**     | Prepare and submit a package to rOpenSci software peer review: scope/fit and overlap policy, the pre-submission checklist, running `pkgcheck`, the submission template, and what to expect from `@ropensci-review-bot`.                                                                                         |
| **`package-review`**         | Conduct a review as a reviewer or editor: the official reviewer checklist and template, what to evaluate beyond the checkboxes, reviewer conduct/timing, `pkgreviewr`, and the editor checks.                                                                                                                   |
| **`stats-standards`**        | Apply the Statistical Software peer-review standards to a package implementing a statistical method: standard categories, documenting standards with the `srr` package (`@srrstats` tags), running `srr`/`autotest`, and the graded badges. Extends `package-standards`.                                        |
| **`package-release`**        | Release a new version the rOpenSci way: updating `NEWS.md`, semantic versioning, CRAN release checks, tagging, GitHub release notes, and announcing it.                                                                                                                                                         |
| **`package-maintenance`**    | Maintain a package over its lifetime: community files (`CONTRIBUTING`, code of conduct), repo grooming, maintainer takeover, deprecating/renaming, lifecycle management, and archiving.                                                                                                                         |
| **`blog-post`**              | Write and submit a post (blog post or tech note) to the rOpenSci blog: drafting `index.Rmd`/`index.qmd` for `roweb3`, YAML frontmatter and author metadata, alt text and images, the `roblog` checks, and the submission PR workflow.                                                                           |
| **`run-package-review`**     | _Action skill._ Actually carry out an AI-assisted review pass on a package working tree and emit a transparent, reproducible report (prompt + skill text + model + method + evidence + not-run), attachable to the `software-review` issue. Reads `package-review` for the "what to check".                     |
| **`run-test-audit`**         | _Action skill._ The test-suite pass of a review: read the tests and the code, run the suite for real (repeatedly, re-seeded), measure coverage depth, hunt flakiness, and report findings with cited evidence. Emits `Review_AI_test_audit.qmd`.                                                                |
| **`run-complexity`**         | _Action skill._ The code-complexity pass of a review: measure cyclomatic complexity per function, build a static call-graph to find duplication, confirm behavioural findings with runtime probes, and recommend simplifications that keep the user-facing surface unchanged. Emits `Review_AI_complexity.qmd`. |
| **`run-dependency-review`**  | _Action skill._ The dependency pass of a review: walk the recursive dependency tree, separate prunable leaves from packages pinned by core deps, count real usage, and check base-R feasibility — only recommending cuts that actually prune the install tree. Emits `Review_AI_dependencies.qmd`.              |
| **`run-performance-review`** | _Action skill._ The performance/memory pass of a review: trace the hot path, measure real anchors, extrapolate to large inputs, and flag risks (memory-bound pulls, silent truncation). Emits `Review_AI_performance.qmd`.                                                                                      |

They're designed to compose. `package-standards` is the base; `stats-standards` layers the statistical standards on top; `peer-review-author` and `package-review` cover the two sides of review; `package-release`, `package-maintenance`, and `blog-post` cover what comes after. Most skills provide _context_ (what to do); the `run-*` skills are _action_ skills that drive the work and produce a report — `run-package-review` orchestrates the review, with `run-test-audit`, `run-complexity`, `run-dependency-review`, and `run-performance-review` as focused per-dimension passes that share one report template and can be run individually.

## Layout

The repo is packaged as a single Claude Code plugin (`ropensci-skills`) that bundles all twelve skills, and doubles as a one-plugin marketplace:

```
ropensci-skills/
├── .claude-plugin/
│   ├── marketplace.json   # the marketplace catalog (lists the plugin below)
│   └── plugin.json        # the plugin manifest
├── skills/
│   ├── package-standards/
│   │   ├── SKILL.md        # frontmatter (name + when-to-use description) + body
│   │   └── references/     # detailed material loaded on demand
│   │       ├── description-naming-deps.md
│   │       ├── documentation.md
│   │       ├── testing-style-ci.md
│   │       └── security.md
│   ├── peer-review-author/
│   ├── package-review/
│   ├── stats-standards/
│   ├── package-release/
│   ├── package-maintenance/
│   ├── blog-post/
│   ├── run-package-review/  # action skill: runs a review, emits a report
│   │   ├── SKILL.md
│   │   └── references/
│   │       ├── report-template.md
│   │       └── git-design-history.md
│   ├── run-test-audit/      # action skill: the test-suite review pass
│   ├── run-complexity/      # action skill: the code-complexity review pass
│   ├── run-dependency-review/   # action skill: the dependency review pass
│   └── run-performance-review/  # action skill: the performance review pass
└── eval-workspace/         # the validation harness (not shipped with the plugin)
```

Each skill follows the Agent Skills format: `SKILL.md` carries the lightweight guidance that's always loaded once the skill triggers, while the `references/` files hold the deeper detail the agent reads only when a task calls for it.

## Installing the skills

### As a Claude Code plugin (recommended)

In [Claude Code](https://docs.claude.com/en/docs/claude-code), add this repo as a marketplace and install the plugin:

```text
/plugin marketplace add ropensci-review-tools/ropensci-skills
/plugin install ropensci-skills@ropensci-skills
```

That installs all twelve skills at once. `/plugin marketplace update` pulls in newer versions later, and `/plugin` opens the manager UI to enable, disable, or uninstall.

### By copying the skill directories

Without the plugin system, copy (or symlink) the skill directories into your skills folder:

```bash
# user-level, available in every project
cp -r skills/* ~/.claude/skills/
```

### Triggering

However you install them, the skills trigger automatically when your request matches their description — e.g. "is this package ready to submit to rOpenSci?" loads `peer-review-author`, "deprecate this function" loads `package-maintenance`. Installed via the plugin, they're namespaced (`ropensci-skills:peer-review-author`) and can also be invoked explicitly.

## How these were validated

`eval-workspace/` contains the evaluation harness used while developing the skills: for each test prompt, an agent ran the task _with_ the skill and _without_ it, the two outputs were graded against assertions, and the results were aggregated into a benchmark (`grade*.py`, `aggregate.py`, and the `iteration-*` / `batch2` result sets). It documents how each skill earned its place.

## License & source

The guidance distilled here comes from rOpenSci's openly licensed guides and books. See [ropensci.org](https://ropensci.org/) and the [rOpenSci Dev Guide](https://devguide.ropensci.org/) for the authoritative, always-current source.
