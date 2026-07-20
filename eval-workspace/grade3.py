#!/usr/bin/env python3
"""Grade batch-3 rOpenSci run-* action-skill eval runs (the review-runner passes).

Same mechanics as grade.py/grade2.py: each assertion passes if ANY regex
alternative matches the response (case-insensitive, dotall). Writes grading.json
into each run dir and the assertion list back into eval_metadata.json.
Usage: python3 grade3.py [iter-dir]   (default: batch3/iteration-1)

Unlike the context-skill batches, these skills DRIVE an analysis of a real
package and emit a transparent report, so the assertions probe the report's
trust-making qualities: evidence actually measured, the transparency header
(prompt / skill / method / read-only), and the per-pass finding structure.
"""
import json, re, pathlib, sys

ITER = pathlib.Path(__file__).parent / (sys.argv[1] if len(sys.argv) > 1 else "batch3/iteration-1")

# shared across passes: the transparency-header fingerprints
PROMPT_REPRODUCED = [r"#+\s*prompt", r"\*\*prompt\*\*", r"\bprompt\s*:", r"triggering prompt", r"prompt that (triggered|produced)"]
READ_ONLY = [r"no (package )?files?[^\n]{0,20}(were )?(modified|changed|edited)", r"read[- ]only", r"did not (modify|edit|change)", r"nothing (was )?modified", r"no files (were )?modified", r"without (modifying|editing|changing) (the|any)"]
FILE_LINE = [r"[A-Za-z0-9_./-]+\.R:\d+", r"\bR/[A-Za-z0-9_]+\.R\b", r"test-[A-Za-z0-9_]+\.R"]

ASSERTIONS = {
    "run-test-audit": [
        ("Actually ran the test suite and reports pass/fail counts", [r"fail\s*\d+\s*\|", r"\|\s*pass\s*\d+", r"pass\s+\d+\s*\]", r"\d+\s+tests?\b", r"\d+\s+assertions?", r"\d+\s+(passed|passing|failures?|failed)", r"0\s+(fail|failures?|warn|skip)", r"fail\w*\s*[:=]\s*0"]),
        ("Reports a measured coverage figure from covr", [r"cover[a-z]*\s*[:=]?\s*\d+(\.\d+)?\s*%", r"\d+(\.\d+)?\s*%[^\n]{0,20}cover", r"covr::package_coverage", r"coverage[^\n]{0,25}\d+(\.\d+)?\s*%"]),
        ("Distinguishes coverage breadth from depth", [r"breadth", r"cover[a-z]*[^\n]{0,40}\bdepth\b", r"\bdepth\b[^\n]{0,40}cover", r"shallow[^\n]{0,20}cover", r"high[^\n]{0,25}coverage[^\n]{0,25}(not|isn't|shallow)"]),
        ("Cites concrete file/line or test-file evidence for findings", FILE_LINE),
        ("Reproduces the triggering prompt in the report", PROMPT_REPRODUCED),
        ("Names the skill/method that produced the report", [r"run-test-audit", r"\*\*skill\*\*", r"\bskill\s*:", r"ai-assisted"]),
        ("States no package files were modified (read-only)", READ_ONLY),
        ("Structures findings into coverage-gap / weak-test / flakiness buckets", [r"coverage gap", r"weak[- ]?(test|assertion)", r"flak(y|iness)", r"instabilit", r"no[- ]assertion test", r"tautolog"]),
        ("Includes a not-run list (skipped or unexecuted paths)", [r"not[- ]run", r"did not run", r"not executed", r"skipped[^\n]{0,25}(path|test|because|since)", r"could not (be )?run", r"left unrun"]),
        ("Gives a prioritised list of fixes", [r"priorit", r"fix priority", r"high[- ]priority", r"order of (importance|priority)", r"most important[^\n]{0,20}first"]),
    ],
    "run-complexity": [
        ("Reports measured cyclomatic complexity per function", [r"cyclomatic", r"cyclocomp", r"complexity\s*(score|of|=|:)\s*\d+", r"complexity[^\n]{0,15}\d+[^\n]{0,15}function"]),
        ("Measures more than one metric (LOC, nesting, or if/for counts)", [r"lines of code", r"\bLOC\b", r"nesting (depth|level)", r"nest(ing)? depth", r"if/for", r"number of (if|for|branch)", r"branch count", r"\bnloc\b"]),
        ("Builds or uses a static call-graph / duplication analysis", [r"call[- ]?graph", r"duplicat", r"getparsedata", r"call site", r"who calls", r"shared (helper|logic|code)"]),
        ("Cites concrete file/line evidence for hotspots", FILE_LINE),
        ("Reproduces the triggering prompt in the report", PROMPT_REPRODUCED),
        ("Names the skill/method that produced the report", [r"run-complexity", r"\*\*skill\*\*", r"\bskill\s*:", r"ai-assisted"]),
        ("States no package files were modified (read-only)", READ_ONLY),
        ("Recommends simplifications that keep the user-facing surface unchanged", [r"user-facing", r"public (api|interface|surface)", r"behaviou?r (unchanged|identical|preserved|the same)", r"same (api|interface|signature)", r"without changing[^\n]{0,30}(api|interface|behaviou?r|surface)", r"api (unchanged|stays|remains)"]),
        ("Confirms a behavioural finding with a runtime probe", [r"runtime probe", r"\bprobe[d]?\b", r"confirmed[^\n]{0,30}runtime", r"verified[^\n]{0,20}(at )?runtime", r"reproduced (this|the|it)", r"i (ran|executed)[^\n]{0,30}(confirm|verif|check)"]),
        ("Recommends specific, concrete simplifications", [r"simplif", r"refactor", r"extract[^\n]{0,20}(function|helper|method)", r"collapse[^\n]{0,20}(into|to)", r"deduplicat", r"split[^\n]{0,20}(into|function)"]),
    ],
    "run-dependency-review": [
        ("Builds the recursive dependency tree with node/edge counts", [r"recursive[^\n]{0,20}depend", r"dependency tree", r"\d+\s+(nodes?|edges?)", r"package_dependencies", r"pkgnet", r"pkg_deps_tree", r"transitive (dependenc|dep)"]),
        ("Separates prunable leaves from packages pinned by core deps", [r"prunable", r"pinned", r"reverse[- ]?depend", r"reachable[^\n]{0,20}only", r"pulled in by", r"also (require|pull|import)", r"leaf"]),
        ("Argues removal only counts if it prunes the install tree", [r"prune[sd]?[^\n]{0,20}(install )?tree", r"install tree", r"prunes nothing", r"cosmetic", r"still (pulled|installed|required)", r"buys nothing[^\n]{0,20}(disk|install|tree)"]),
        ("Counts real usage (call sites) of imported functions", [r"call site", r"used\s+\d+\s+time", r"\d+\s+(call|usage|use)s?\b", r"usage count", r"how many times[^\n]{0,20}(call|use)", r"\d+\s+call sites?"]),
        ("Assesses base-R feasibility of replacing a dependency", [r"base[- ]?R", r"base r replacement", r"replace[^\n]{0,25}base", r"stdlib", r"without[^\n]{0,20}dependency"]),
        ("Tiers recommendations (clear win / worth-doing / defer)", [r"tier\s*[123]", r"tier 1|tier 2|tier 3", r"clear win", r"worth[- ]doing", r"\bdefer\b"]),
        ("Reproduces the triggering prompt in the report", PROMPT_REPRODUCED),
        ("Names the skill/method that produced the report", [r"run-dependency-review", r"\*\*skill\*\*", r"\bskill\s*:", r"ai-assisted"]),
        ("States no package files were modified (read-only)", READ_ONLY),
        ("Keeps deps whose removal buys nothing and says why", [r"removal buys nothing", r"buys nothing", r"\bkeep\b[^\n]{0,45}(because|pinned|core|contract|require)", r"pinned by", r"return[- ]type contract", r"cannot (be )?remov"]),
    ],
    "run-performance-review": [
        ("Traces the hot path / sketches the call chain", [r"hot path", r"call chain", r"call[- ]?graph", r"data (flow|path)", r"trace[d]?[^\n]{0,20}path", r"end[- ]to[- ]end"]),
        ("Anchors on a real measurement (object.size, timing, or profiling)", [r"object\.size", r"\bRprof\b", r"system\.time", r"bench::mark|bench mark|microbenchmark", r"\d+(\.\d+)?\s*(ms|µs|us|mb|kb|gb|bytes)\b", r"measured[^\n]{0,20}\d", r"\d+(\.\d+)?\s*sec"]),
        ("Distinguishes the persistent result from the transient peak", [r"transient", r"\bpeak\b", r"persistent[^\n]{0,20}(result|object|footprint)", r"in[- ]flight", r"final (object|result)[^\n]{0,20}(vs|versus|smaller|larger)"]),
        ("Extrapolates to large inputs with explicit multipliers", [r"extrapolat", r"multiplier", r"per[- ](row|record|site|year|call)", r"bytes/row|bytes per row", r"scenario", r"\d+\s*[x×]\b", r"scal(e|es|ing)[^\n]{0,20}(with|linear|to)"]),
        ("Labels which figures are measured versus estimated", [r"estimat", r"measured versus|measured vs\.?", r"\(measured\)|\(estimated\)|\(extrapolated\)", r"measured[^\n]{0,30}extrapolat"]),
        ("Flags a concrete scaling risk (super-linear time, memory-bound, truncation, no caching)", [r"memory[- ]bound", r"\bOOM\b", r"out of memory", r"truncat", r"no (streaming|caching|resumab|checkpoint)", r"streaming", r"silent[^\n]{0,20}(partial|truncat)", r"quadratic", r"super[- ]?linear", r"O\([a-z]*\^?\s*2\)", r"memory (consideration|footprint|bound|payload)"]),
        ("Reproduces the triggering prompt in the report", PROMPT_REPRODUCED),
        ("Names the skill/method that produced the report", [r"run-performance-review", r"\*\*skill\*\*", r"\bskill\s*:", r"ai-assisted"]),
        ("States no package files were modified (read-only)", READ_ONLY),
        ("Gives recommendations plus caveats on the estimate", [r"caveat", r"recommend", r"limitation[s]? of (this|the) (estimate|analysis)", r"assumption", r"dominant unknown"]),
    ],
}


def grade_text(text, alts):
    for pat in alts:
        m = re.search(pat, text, re.IGNORECASE | re.DOTALL)
        if m:
            return True, m.group(0)[:160]
    return False, ""


for eval_dir, asserts in ASSERTIONS.items():
    base = ITER / eval_dir
    meta_path = base / "eval_metadata.json"
    if meta_path.exists():
        meta = json.loads(meta_path.read_text())
        meta["assertions"] = [a[0] for a in asserts]
        meta_path.write_text(json.dumps(meta, indent=2) + "\n")
    for config in ("with_skill", "without_skill"):
        resp = base / config / "outputs" / "response.md"
        if not resp.exists():
            print(f"MISSING {resp}")
            continue
        text = resp.read_text()
        expectations = []
        for atext, alts in asserts:
            passed, evidence = grade_text(text, alts)
            expectations.append({"text": atext, "passed": passed, "evidence": evidence})
        grading = {"expectations": expectations,
                   "passed_count": sum(1 for e in expectations if e["passed"]),
                   "total": len(expectations)}
        (base / config / "grading.json").write_text(json.dumps(grading, indent=2) + "\n")
        print(f"{eval_dir}/{config}: {grading['passed_count']}/{grading['total']}")
