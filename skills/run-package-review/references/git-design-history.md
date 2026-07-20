# Extract a package's design history from its git log

Before reviewing an unfamiliar package, reconstruct how it got here. The git log
holds the architecture's evolution, the churn hotspots, and the decisions behind
the code — context that makes a review sharper and fairer.

This recipe is adapted from the deterministic design-history instructions in
[**designlens**](https://github.com/ropensci-review-tools/designlens)
(`lib/init.sh`), another rOpenSci review-tools project. It's a general-purpose
building block: run it at the start of a review pass to produce a short
`design-history.md`, then read that before the checklist work.

## How to run it

Run every command from the root of the package's working tree. Several commands
should be run in **three forms**, and each question below says which apply:

- **all-time** (the bare command),
- **recent** — add `--since="1 year ago"`,
- **by language** — append `'*.<ext>'` for the dominant one or two languages
  (identified in the first step). Comparing filtered vs. unfiltered results is
  itself informative.

A few commands pipe into `head -50`; raise that number where more lines would
add insight.

### What languages is this in?

```bash
cloc --json . | jq '[to_entries[1:5][] | select(.value | has("nFiles") and has("code")) | {key: .key, nFiles: .value.nFiles, code: .value.code}]'
```

Use the extensions of the one or two most common languages to filter the
language-sensitive commands below.

### Which files change the most? (all-time, recent, by language)

```bash
git log --format=format: --name-only | sort | uniq -c | sort -nr | head -50
```

Churn hotspots are prime review targets — high change frequency often marks
fragile or central code.

### Who built this? (single form — no time/language filter)

```bash
git shortlog -sn --no-merges
```

### Where have most bugs been? (all-time, recent, by language)

```bash
git log -i -E --grep="fix|bug|broken" --name-only --format='' | sort | uniq -c | sort -nr | head -50
```

### What has the pace of development looked like? (single form)

```bash
git log --format='%ad' --date=format:'%Y-%m' | sort | uniq -c
```

### What are the most common words in commit messages?

```r
f <- tempfile()
system2("git", list("log", "--oneline", "--pretty=format:%s"), stdout = f)
x <- suppressWarnings(readLines(f)) |>
  tokenizers::tokenize_words() |>
  unlist()
x <- x[which(!grepl("^[0-9]", x))]
freqs <- sort(table(x), decreasing = TRUE)
threshold <- 0.4
index <- which(cumsum(freqs) / sum(freqs) < threshold)
data.frame(token = names(freqs), n = as.integer(freqs))[index, ] |>
  jsonlite::toJSON() |>
  cat()
```

For words that likely reflect design decisions, dig in:

```bash
git log --oneline --grep="<word1>|<word2>"
```

Also grep the log for `feature`, `design`, `deci(d|s)`, `refactor`,
`architecture`.

## Produce the summary

Once every question is answered, write `design-history.md` with a YAML header
and two sections:

```yaml
---
created: <current UTC timestamp, ISO 8601, e.g. 2026-07-01T14:05:00Z>
agent: <your model identifier, e.g. claude-opus-4-8>
git-hash: <current HEAD hash>
---
```

1. **Project Evolution** — the major phases and how the architecture changed
   over time.
2. **Key Decisions** — the strategic choices: what was decided, why, and the
   impact.

Focus on initial architecture, major refactors, significant feature pivots, and
technology choices. Skip individual bug fixes, minor tweaks, and implementation
detail.
