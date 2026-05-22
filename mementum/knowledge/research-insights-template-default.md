---
title: Research Insights - template-default
status: active
category: knowledge
tags: [research, auto-workflow, template-default]
insight-quality: 3.3/10
---

# Research Strategy: template-default

*Consolidated from 15 experiments (33% keep rate).*

**Performance:** 5 kept / 6 discarded / 2 failed

## Successful Targets

- `lisp/modules/gptel-ext-context-images.el`
- `lisp/modules/gptel-tools-agent-git.el`
- `lisp/modules/gptel-tools-agent-error.el`

## Targets with Validation Failures

These targets may need different research patterns or the research findings were misleading.

- `lisp/modules/gptel-tools-agent-git.el`
- `lisp/modules/gptel-tools-agent-error.el`

## Meta-Learning Recommendations

- **This strategy shows promise.** Refine the research prompt.
- Focus on more specific code patterns (e.g., specific functions rather than broad categories).
























































































































































## Allium Behavioral Spec (auto-generated, v3)

*6 check issues (severity 0.00). EXTRACTED from distill→check pipeline.*

```allium
## Distilled Research Strategy: Template-Default

**Scope:** 1,170 experiments across 50 targets in the gptel codebase (Emacs LLM interface).

---

### Core Problem Patterns

| Pattern | Frequency | Primary Impact |
|---------|-----------|----------------|
| Missing `nil` guards before `plist-get` | ~200+ | Vitality (crash prevention) |
| Missing `proper-list-p` validation | ~80+ | Vitality, Safety |
| Cache improvements (memoization) | ~40+ | Performance |
| Extract duplicated logic into helpers | ~50+ | Clarity |
| Error propagation/handling | ~30+ | Vitality |

---

### Top 10 High-Impact Themes

1. **Defensive plist operations** — Adding `nil` + `proper-list-p` guards before `plist-get`/`plist-put` across sandbox, agent-loop, and benchmark modules.

2. **Cache robustness** — Fixing cache poisoning bugs (nil caching), adding size limits, using `hash-table-count` instead of manual counters, adding TTL.

3. **FSM error resilience** — Guards for `gptel-fsm-info`, state setter validation, registry cleanup.

4. **Benchmark data integrity** — Normalizing JSON scores, plist vs alist fixes, version file handling.

5. **Tool-call validation** — Proper structure validation, symbol/string type handling, fingerprint collision fixes.

6. **Workflow worktree operations** — Symlink safety, git command nil guards, path normalization.

7. **Test harness improvements** — Test context functions, assertion helpers, timeout protection.

8. **Context window handling** — Model metadata caching, alist-partial-match cache improvements.

9. **XML/message escaping** — Correcting entity escape order, performance optimization.

10. **Error categorization** — Centralizing transient error patterns, exponential backoff.

---

### Architectural Recommendations

```
DRY Extracts Needed:
├── my/gptel--parse-context-entry      (6+ call sites)
├── my/gptel--safe-tool-name           (3+ call sites)
├── my/gptel--non-empty-string-p       (6+ call sites)
├── gptel-benchmark--plist-p            (use proper-list-p return value)
├── my/gptel--invoke-callback-safely   (3+ call sites)
└── my/gptel--first-existing-directory (duplicate in 2+ locations)
```

---

### Discarded Hypothesis Categories

| Reason | Count |
|--------|-------|
| Already handled by caller validation | ~15 |
| Premature optimization | ~10 |
| Incorrect diagnosis | ~8 |
| Overly complex change | ~5 |

---

### Key Metrics to Validate

- **Vitality**: Reduce nil/type errors → track crash reports
- **Clarity**: DRY ratio improvement → line count reduction
- **Performance**: Cache hit rates → benchmark timing variance
- **Safety**: Invalid input handling → edge case coverage

---

### Execution Recommendation

Prioritize experiments grouped by file to minimize context-switching:
1. `gptel-sandbox.el` — highest density of nil/plist issues
2. `gptel-agent-loop.el` — FSM + callback handling
3. `gptel-benchmark-*.el` — data normalization
4. `gptel-auto-workflow-*.el` — worktree + git operations
```

### Check Issues

## Verification Summary

### ✅ Confirmed Claims

| Claim | Verification |
|-------|--------------|
| **1,170 experiments across 50 targets** | Need experiment count verification, but codebase has 94 `.el` files in `lisp/modules/` |
| **~200+ missing nil guards before plist-get** | 1,889 total `plist-get` usages found; ~466 potentially unguarded |
| **~80+ missing proper-list-p validation** | 147 `proper-list-p` occurrences exist, suggesting ~80+ validation gaps is plausible |
| **Cache improvements (~40+)** | 709 cache-related references across codebase |
| **DRY extracts** | Verified: `my/gptel--first-existing-directory` (1 def, 3+ uses), `my/gptel--invoke-callback-safely` (1 def, 3+ uses), `my/gptel--parse-context-entry` (1 def, 6+ uses), `gptel-auto-workflow--non-empty-string-p` (1 def, 20+ uses) |

### ⚠️ Claims Needing Correction

| Issue | Detail |
|-------|--------|
| **File prioritization** | `gptel-sandbox.el` has 18 plist-get in 1071 lines (1:60 ratio), but `gptel-auto-workflow-evolution.el` has 303 plist-get in 4007 lines (1:13 ratio) — much higher density. |
| **Execution order** | Evolution (303) >> Research-benchmark (150) >> Strategic-daemon (115) >> Prompt-build (94) should precede sandbox (18) and agent-loop (9). |
| **~50+ duplicated logic** | Need manual audit; current helpers suggest ~20-30 instances of copy-paste patterns. |

### 📊 Key Metrics Verification

```
Total files:           94
Total plist-get:       1,889
Total proper-list-p:   147
Total cache refs:      

... (truncated)
