#!/usr/bin/env Rscript

# Coverage audit (issue #4). Inverse of drift-detect.R: instead of asking whether
# a cited page changed, it asks whether the upstream manuals contain content pages
# that NO skill covers yet — so completely new pages/chapters get evaluated for
# incorporation rather than silently ignored.
#
# For each repo in tools/coverage.yml: enumerate content pages at HEAD, drop the
# excluded scaffolding, drop everything already referenced by a skills/*/sources.yml
# manifest, drop the reviewed-and-skipped out_of_scope entries. Whatever remains is
# "unaccounted for" — a page a human must triage (incorporate or mark out of scope).
#
# Emits coverage-report.md and sets `coverage=true|false` in $GITHUB_OUTPUT.

suppressPackageStartupMessages({
  library(yaml)
  library(gh)
  library(glue)
  library(cli)
})

`%||%` <- function(a, b) if (is.null(a)) b else a

cfg <- yaml::read_yaml("tools/coverage.yml")

# --- manifested paths, grouped by upstream repo ----------------------------

manifested <- new.env(parent = emptyenv())
for (m in Sys.glob("skills/*/sources.yml")) {
  man <- yaml::read_yaml(m)
  for (f in man$files) {
    repo <- f$upstream$repo
    srcs <- vapply(f$upstream$pages, `[[`, character(1), "source")
    manifested[[repo]] <- union(manifested[[repo]], srcs)
  }
}

# --- glob matchers ---------------------------------------------------------

# include: anchored full-path match; `*` spans a single path segment.
include_match <- function(pattern, path) {
  rx <- gsub(
    "\\*",
    "[^/]*",
    gsub("([.^$+?()\\[\\]{}|])", "\\\\\\1", pattern, perl = TRUE)
  )
  grepl(glue("^{rx}$"), path)
}

# exclude: `dir/**` = subtree prefix; a slash-less pattern matches the basename
# anywhere; otherwise anchored full-path match.
exclude_match <- function(pattern, path) {
  if (endsWith(pattern, "/**")) {
    return(startsWith(path, sub("\\*\\*$", "", pattern)))
  }
  target <- if (grepl("/", pattern)) path else basename(path)
  rx <- gsub(
    "\\*",
    "[^/]*",
    gsub("([.^$+?()\\[\\]{}|])", "\\\\\\1", pattern, perl = TRUE)
  )
  grepl(glue("^{rx}$"), target)
}

repo_head_tree <- function(repo) {
  branch <- gh::gh("GET /repos/{repo}", repo = repo)$default_branch
  tr <- gh::gh(
    "GET /repos/{repo}/git/trees/{branch}",
    repo = repo,
    branch = branch,
    recursive = 1
  )
  vapply(tr$tree, `[[`, character(1), "path")
}

# --- audit -----------------------------------------------------------------

uncovered <- list()
for (r in cfg$repos) {
  paths <- repo_head_tree(r$repo)
  included <- paths[vapply(
    paths,
    function(p) any(vapply(r$include, include_match, logical(1), p)),
    logical(1)
  )]
  included <- included[
    !vapply(
      included,
      function(p) any(vapply(r$exclude, exclude_match, logical(1), p)),
      logical(1)
    )
  ]

  oos <- vapply(r$out_of_scope %||% list(), `[[`, character(1), "path")
  gap <- setdiff(included, union(manifested[[r$repo]] %||% character(0), oos))
  if (length(gap)) uncovered[[r$repo]] <- sort(gap)
}

# --- report ----------------------------------------------------------------

lines <- c(
  "# Skill coverage audit",
  "",
  glue("Checked {length(cfg$repos)} source repo(s) on {format(Sys.Date())}."),
  ""
)

if (length(uncovered) == 0) {
  lines <- c(
    lines,
    "Full coverage: every upstream content page is either covered by a skill or marked out of scope."
  )
  coverage <- "false"
} else {
  coverage <- "true"
  n <- sum(lengths(uncovered))
  lines <- c(
    lines,
    glue(
      "**{n} upstream page(s) are unaccounted for** — neither covered by a skill nor listed in `tools/coverage.yml` out_of_scope. Triage each: incorporate into a skill, or add to out_of_scope with a reason."
    ),
    ""
  )
  for (repo in names(uncovered)) {
    lines <- c(lines, glue("### {repo}"))
    for (p in uncovered[[repo]]) {
      lines <- c(lines, glue("- `{p}`"))
    }
    lines <- c(lines, "")
  }
}

writeLines(lines, "coverage-report.md")
cli::cli_alert(
  if (coverage == "true") "Uncovered pages found." else "Full coverage."
)
cat(
  glue("coverage={coverage}\n"),
  file = Sys.getenv("GITHUB_OUTPUT", "/dev/stdout"),
  append = TRUE
)
