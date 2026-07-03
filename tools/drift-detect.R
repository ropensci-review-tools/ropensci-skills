#!/usr/bin/env Rscript

# Detect drift between the skills and the upstream rOpenSci manuals they
# condense. Reads every skills/*/sources.yml, and for each pinned source file
# asks the source repo (via the GitHub compare API) whether that path changed
# between the pinned `ref` and the channel this repo is watched on. Deterministic:
# a source file is "drifted" iff it appears in the compare's changed-file set.
#
# The watched channel is per upstream block (`track:`):
#   release -> compare against the latest published release/tag. Low-noise, so
#              prose drift here is eligible for automated LLM reconciliation.
#   main    -> compare against default-branch HEAD. For repos that don't cut
#              usable releases; findings are ADVISORY (human triage only) and are
#              never handed to the reconciler — a noisy channel must not drive
#              automated edits, or it manufactures the very drift we prevent.
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

`%||%` <- function(a, b) if (is.null(a)) b else a

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

default_branch <- local({
  cache <- new.env(parent = emptyenv())
  function(repo) {
    if (is.null(cache[[repo]])) {
      cache[[repo]] <- gh::gh("GET /repos/{repo}", repo = repo)$default_branch
    }
    cache[[repo]]
  }
})

# The comparison HEAD for a repo, per its watched channel. `release` resolves to
# the latest published release (falling back to the newest tag); `main` (or an
# unset track) resolves to the default branch. Cached per (repo, track).
resolve_head <- local({
  cache <- new.env(parent = emptyenv())
  function(repo, track) {
    key <- paste(repo, track)
    if (is.null(cache[[key]])) {
      cache[[key]] <- if (identical(track, "release")) {
        rel <- tryCatch(
          gh::gh("GET /repos/{repo}/releases/latest", repo = repo)$tag_name,
          error = function(e) NULL
        )
        rel %||%
          {
            tags <- gh::gh("GET /repos/{repo}/tags", repo = repo)
            if (length(tags) == 0) {
              cli::cli_abort(
                "track: release but {.val {repo}} has no releases or tags."
              )
            }
            tags[[1]]$name
          }
      } else {
        default_branch(repo)
      }
    }
    cache[[key]]
  }
})

# One compare call per (repo, ref, head); returns the set of changed source
# paths and the human-readable diff URL. Three-dot semantics: `changed` is what
# HEAD added relative to the merge-base with `ref`, so a release that is behind
# our pinned ref (skill baseline newer than the last release) yields nothing.
compare_changed <- local({
  cache <- new.env(parent = emptyenv())
  function(repo, ref, head) {
    key <- paste(repo, ref, head)
    if (is.null(cache[[key]])) {
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
    track <- up$track %||% "main"
    head <- resolve_head(up$repo, track)
    cmp <- compare_changed(up$repo, up$ref, head)
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
      track = track,
      head = head,
      advisory = !identical(track, "release"),
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
    if (isTRUE(fd$advisory)) {
      tag <- paste0(tag, " — _advisory: `main` channel, human triage only_")
    }
    lines <- c(
      lines,
      glue("- `{fd$file}` ({fd$skill}){tag}"),
      glue(
        "  - upstream `{fd$repo}` moved on `{fd$track}`: {paste(sprintf('`%s`', fd$drifted), collapse = ', ')}"
      ),
      glue("  - diff since sync: {fd$url}")
    )
  }
  reconcilable <- Filter(function(fd) !isTRUE(fd$advisory), findings)
  lines <- c(
    lines,
    "",
    glue(
      "Release-channel prose drift ({length(reconcilable)} file(s)): an LLM may draft a sync PR for human review — **or conclude no change is needed**, which is a valid outcome."
    ),
    "Advisory (`main`-channel) drift: never auto-reconciled — a human decides whether the upstream change warrants a sync.",
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
