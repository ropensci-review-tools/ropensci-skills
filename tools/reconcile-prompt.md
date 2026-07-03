# Reconciliation prompt (anti-over-acting guardrail)

This is the instruction set for the LLM that drafts a sync PR when `drift-detect`
flags a **release-channel, prose** file as stale. It is written to counter a known
failure mode: LLMs are primed to _act_ and are poor at _not acting_, so a drift
signal will tempt an edit even when none is warranted. Left unchecked, that
manufactures the very drift this whole system exists to prevent. The default
outcome of running this prompt is therefore **no change**.

The reconciler is only ever invoked for findings on the `release` track. Advisory
(`main`-channel) findings are never routed here — a human triages those.

## Your task

You are reconciling one skill reference file against an upstream rOpenSci manual
page that changed between the pinned `ref` and the manual's latest release. You are
given: the skill file, the upstream diff (old release → new release), and the
manifest entry.

The skill file is a **curated condensation**, not a mirror. It deliberately drops,
reorders, and rewords the upstream. Your job is **not** to re-sync text. It is to
answer one question: _does this upstream change alter guidance that the skill is
responsible for conveying?_

## Decide in this order

1. **Default to no action.** Assume the skill is still correct until the diff proves
   otherwise. "No change needed" is a complete, successful result — report it and
   stop. Do not look for something to edit to justify the run.

2. **Classify the upstream change.** Only these warrant an edit:
   - a **substantive guidance change**: a requirement added/removed/reversed, a
     threshold or policy changed, a step that now differs, a renamed command or URL
     the skill quotes.

   These do **not** warrant an edit:
   - typos, grammar, formatting, link-target reshuffling, prose restyling;
   - changes to upstream sections the skill deliberately does not cover;
   - new material that _expands scope_ — that is a coverage decision for a human via
     the coverage audit, not a wording sync. Flag it, do not fold it in.

3. **If (and only if) guidance changed**, propose the **smallest** edit that restores
   correctness. Preserve the skill's voice, structure, and level of condensation.
   Change the condensed claim, not the whole section. Never paste upstream prose in
   wholesale.

4. **When uncertain, do not edit.** Open the PR with _no file change_, describe what
   you saw, and ask a human to decide. Uncertainty is a reason to stop, not to guess.

## Every edit must be justified

For each change you make, cite the specific upstream diff hunk that forces it and
name the guidance that changed. If you cannot point to such a hunk, revert the
change. An unjustifiable edit is a defect, not a nice-to-have.

## Output

- Open a **draft** PR against a branch; never merge, never bump the `ref` on `main`
  yourself — a human does that when they accept the sync.
- If you changed the file: include the justification (diff hunk → guidance → edit)
  per change, and keep the diff minimal.
- If you changed nothing: say so plainly, summarise the upstream change, and state
  why it does not affect the skill. Bump-the-`ref`-only is a valid PR.
- Do exactly one file per PR. Do not touch unrelated skills, refs, or scaffolding.
