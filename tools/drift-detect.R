#!/usr/bin/env Rscript

# Detect drift between the skills and the upstream rOpenSci manuals they
# condense. Reads every skills/*/sources.yml, and for each pinned source file
# asks the source repo (via the GitHub compare API) whether that path changed
# between the pinned `ref` and the repo's current HEAD. Deterministic: a source
# file is "drifted" iff it appears in the compare's changed-file set.
#
# Emits drift-report.md and sets `drift=true|false` in $GITHUB_OUTPUT.
#
# Skeleton status: detection (A) is implemented end-to-end. The hard equality
# check for `kind: structured` files (D) is stubbed in check_structured() with a
# TODO — the extraction rules are artifact-specific (reviewer template, editor
# checklist, bot cheatsheet) and need per-artifact normalisers.

suppressPackageStartupMessages({
  library(yaml)
  library(gh)
  library(glue)
  library(cli)
})

manifests <- Sys.glob("skills/*/sources.yml")
if (length(manifests) == 0) {
  cli::cli_alert_info(
    "No skills/*/sources.yml manifests found; nothing to check."
  )
  writeLines("No provenance manifests found.", "drift-report.md")
  cat(
    "drift=false\n",
    file = Sys.getenv("GITHUB_OUTPUT", "/dev/stdout"),
    append = TRUE
  )
  quit(status = 0)
}

# --- helpers ---------------------------------------------------------------

`%||%` <- function(a, b) if (is.null(a)) b else a

default_branch <- local({
  cache <- new.env(parent = emptyenv())
  function(repo) {
    if (is.null(cache[[repo]])) {
      cache[[repo]] <- gh::gh("GET /repos/{repo}", repo = repo)$default_branch
    }
    cache[[repo]]
  }
})

# One compare call per (repo, ref); returns the set of changed source paths and
# the human-readable diff URL. Cached so many files sharing a ref cost one call.
compare_changed <- local({
  cache <- new.env(parent = emptyenv())
  function(repo, ref) {
    key <- paste(repo, ref)
    if (is.null(cache[[key]])) {
      head <- default_branch(repo)
      cmp <- gh::gh(
        "GET /repos/{repo}/compare/{basehead}",
        repo = repo,
        basehead = glue("{ref}...{head}")
      )
      cache[[key]] <- list(
        changed = vapply(cmp$files, `[[`, character(1), "filename"),
        url = cmp$html_url,
        ahead_by = cmp$ahead_by
      )
    }
    cache[[key]]
  }
})

# TODO(D): fetch the upstream artifact at HEAD, normalise, and compare to the
# embedded copy. Returns TRUE when they still match, FALSE on mismatch, NA when
# not yet implemented for this artifact.
check_structured <- function(local_path, upstream) {
  NA
}

# --- scan ------------------------------------------------------------------

findings <- list()

for (mf in manifests) {
  man <- yaml::read_yaml(mf)
  skill <- man$skill %||% dirname(mf)
  for (f in man$files) {
    up <- f$upstream
    cmp <- compare_changed(up$repo, up$ref)
    srcs <- vapply(up$pages, `[[`, character(1), "source")
    drifted <- intersect(srcs, cmp$changed)
    if (length(drifted) == 0) {
      next
    }

    struct_ok <- if (identical(f$kind, "structured")) {
      check_structured(f$path, up)
    } else {
      NULL
    }
    findings[[length(findings) + 1]] <- list(
      skill = skill,
      file = f$path,
      kind = f$kind,
      repo = up$repo,
      ref = up$ref,
      drifted = drifted,
      url = cmp$url,
      ahead_by = cmp$ahead_by,
      struct_ok = struct_ok
    )
  }
}

# --- report ----------------------------------------------------------------

lines <- c(
  "# Skill drift report",
  "",
  glue("Checked {length(manifests)} manifest(s) on {format(Sys.Date())}."),
  ""
)

if (length(findings) == 0) {
  lines <- c(
    lines,
    "No drift: every pinned source file is unchanged since its `ref`."
  )
  drift <- "false"
} else {
  drift <- "true"
  lines <- c(lines, glue("**{length(findings)} file(s) may be stale.**"), "")
  for (fd in findings) {
    tag <- if (identical(fd$kind, "structured")) {
      if (isFALSE(fd$struct_ok)) {
        " — **structured artifact MISMATCH**"
      } else if (is.na(fd$struct_ok)) {
        " — structured (equality check TODO)"
      } else {
        " — structured (still matches)"
      }
    } else {
      ""
    }
    lines <- c(
      lines,
      glue("- `{fd$file}` ({fd$skill}){tag}"),
      glue(
        "  - upstream `{fd$repo}` moved: {paste(sprintf('`%s`', fd$drifted), collapse = ', ')}"
      ),
      glue("  - diff since sync: {fd$url}")
    )
  }
  lines <- c(
    lines,
    "",
    "Prose files: an LLM will draft a sync PR for human review.",
    "Structured mismatches: fix before the next review relies on the stale artifact."
  )
}

writeLines(lines, "drift-report.md")
cli::cli_alert(if (drift == "true") "Drift detected." else "No drift.")
cat(
  glue("drift={drift}\n"),
  file = Sys.getenv("GITHUB_OUTPUT", "/dev/stdout"),
  append = TRUE
)
