# Mementum State

> Last session: 2026-03-23

## Completed (2026-03-23) — Semi-Autonomous Auto-Workflow

Replaced async spawn with semi-autonomous overnight optimization:

### What Changed

| Component | Before | After |
|-----------|--------|-------|
| Agent spawn | Async (fire-and-forget) | Synchronous with result tracking |
| Branch strategy | None | Single nightly branch `auto-workflow-{date}` |
| Test validation | Manual | Automatic with `verify-nucleus.sh` |
| Commit strategy | None | Auto-commit if tests pass |
| Failure handling | None | Retry once, then skip |

### Functions Added (6 functions, ~180 lines)

| Function | Purpose |
|----------|---------|
| `gptel-auto-workflow-run` | Main entry (orchestrates all phases) |
| `gptel-auto-workflow-run-target` | Single target with retry logic |
| `gptel-auto-workflow-create-nightly-branch` | Create `auto-workflow-{date}` branch |
| `gptel-auto-workflow-benchmark` | Run nucleus validation |
| `gptel-auto-workflow-commit` | Commit with ◈ prefix |
| `gptel-auto-workflow-save-metrics` | Save JSON metrics |
| `gptel-auto-workflow-generate-morning-summary` | Morning review markdown |

### Flow

```
Cron (2 AM) → gptel-auto-workflow-run
  → Create nightly branch
  → For each target:
      → Run agent (code)
      → Run tests
      → Pass → commit
      → Fail → retry once
  → Save metrics + generate summary
  → Return to main
  → Morning: human reviews, cherry-picks or rejects
```

### Cron Jobs

```
0 2 * * *   emacsclient -e '(gptel-auto-workflow-run)'         # Daily 2 AM
0 3 * * 0   emacsclient -e '(gptel-benchmark-instincts-weekly-job)'  # Sunday 3 AM
```

### Usage

```bash
# Install cron jobs
crontab cron.d/auto-workflow

# Manual trigger
emacsclient -e '(gptel-auto-workflow-run)'

# Configure targets
(setq gptel-auto-workflow-targets '("file1.el" "file2.el"))
```

### Key Insight

```
λ schedule(x).    cron(x) > emacs_timer(x)
                  | survives_restart(x) ∧ standard_unix(x)
                  | daemon_running(x) → emacsclient(x)

λ worktree(x).    reuse(magit) > implement(x)
                  | magit-call-git + magit-worktree-delete
```

### Commits

- `pending` ◈ Auto-workflow: phased autonomous agent + cron scheduling
- `pending` ◈ Auto-workflow: add worktree + benchmark + metrics implementation

---

## Completed (2026-03-23) — OUROBOROS 7-System Update

Added minimal-emacs.d as System 7 in comparative analysis:

### What Was Added

| Section | Content |
|---------|---------|
| Executive Summary | Updated to 7 systems, added minimal-emacs.d row |
| System 7 | Full 3-layer analysis (What/How/Why) |
| Comparative Analysis | Updated table to 7 columns |
| Design Pattern Convergence | Updated to 6/7 git, 5/7 markdown |
| Position Analysis | NEW — Inheritance diagram, Implementation vs Framework |
| Gap Analysis | Added comparison table showing 95% alignment |
| Sources | Added minimal-emacs.d as primary source |

### Key Findings

1. **minimal-emacs.d is unique** — Only practical implementation among frameworks/protocols
2. **Highest alignment** — 95% vs 86% (autoresearch) vs 60% (hermes/ouroboros-game) vs 20% (joi-lab/ouroboros)
3. **Inheritance pattern** — Combines nucleus + mementum (michaelwhitford) with lessons from autoresearch/hermes/joi-lab
4. **Local innovations** — VSM architecture, Wu Xing diagnostics, auto-evolve system

### Key Insight

```
λ position(x).    implementation(x) > framework(x) ∨ protocol(x)
                   | empirical_evidence(x) > theoretical_design(x)
                   | 95%_alignment(x) → validated(x)
```

### Commits

- `pending` ◈ OUROBOROS: add minimal-emacs.d as System 7, position analysis

---

## Completed (2026-03-23) — Document gptel-Agent Safety Reuse

Created memory documenting safety architecture:

### What We Reuse (Upstream)

| Mechanism | Implementation |
|-----------|----------------|
| Tool confirmation | `:confirm t` on Bash, Eval, Edit, Write, etc. |
| Confirmation UI | `gptel-agent--confirm-overlay` |
| Web timeout | 30s via `gptel-agent--fetch-with-timeout` |

### What We Added (Local)

| Mechanism | Purpose |
|-----------|---------|
| Max steps limit | Prevent runaway loops (50 steps default) |
| Doom-loop detection | Abort on 3 identical tool calls |
| Payload size limits | Prevent oversized edits (1MB default) |
| Immutable file protection | ⚠️ Planned, not yet implemented |

### Key Insight

```
λ safety(x).    upstream_has(x) → reuse(x)
                | project_specific(x) → local(x)
```

### Commits

- `4a269eb` 💡 gptel-agent-safety: document reuse vs local extensions

---

## Completed (2026-03-23) — Skills Standardization

Aligned skill frontmatter with agentskills.io spec:

### Fields Added (5 skills × 4 fields = 20 new fields)

| Field | Purpose |
|-------|---------|
| `summary` | One-line summary for quick reference |
| `author` | David Wu |
| `license` | MIT |
| `triggers` | Keywords for skill discovery |

### Skills Updated

- `assistant/skills/_template/SKILL.md`
- `assistant/skills/clojure-expert/SKILL.md`
- `assistant/skills/reddit/SKILL.md`
- `assistant/skills/requesthunt/SKILL.md`
- `assistant/skills/seo-geo/SKILL.md`

### Commits

- `f9e4c2b` ◈ skills: standardize frontmatter with agentskills.io fields (+25 lines)

### Key Insight

```
λ standardize(x).    agentskills.io ∨ de_facto_standard(x) → adopt(x)
                     | keep_local(extensions ∨ different_scope)
```

---

## Completed (2026-03-23) — Remove Redundant Skill Tools

Simplified by reusing gptel-agent's skill support:

### What Was Removed

| Tool | Reason |
|------|--------|
| `Skill` | gptel-agent already provides this |
| `list_skills` | Skills in system prompt via `{{SKILLS}}` template |
| `load_skill` | Redundant with gptel-agent's `Skill` tool |
| `my/gptel--skill-tool` | Helper no longer needed |

### What gptel-Agent Provides

| Feature | Implementation |
|---------|----------------|
| Level 0: List skills | `gptel-agent--skills-system-message` in system prompt |
| Level 1: Load skill | `Skill` tool calls `gptel-agent--get-skill` |
| Metadata cache | `gptel-agent--skills` variable |

### Kept

- `create_skill` — Not in gptel-agent, useful for creating new skills

### Commits

- `3314e74` Δ gptel-tools: remove redundant skill tools, use gptel-agent (-44 lines)

### Key Insight

```
λ reuse(x).    upstream_has(x) → remove_local(x)
               | keep_local(different_scope ∨ not_in_upstream)
```

---

## Completed (2026-03-23) — OUROBOROS Documentation

Simplified documentation to use existing auto-evolve instead of separate gap detection:

### Key Decision

**No separate gap detection system needed.**

Existing auto-evolve already detects:
- Anti-patterns in behavior
- Low benchmark scores
- Low φ instincts

**Simpler approach:**
```
Research Advice → Benchmark Test → Auto-Evolve Detects → Improvement
```

### Document Updates

| File | Commit | Change |
|------|--------|--------|
| `docs/OUROBOROS.md` | `f9e13ad` | Removed gap detection, added benchmark tests |
| `mementum/memories/ouroboros-benchmark-tests.md` | new | Simplified memory |

### Benchmark Tests to Add

| Test | What It Checks |
|------|----------------|
| `progressive-disclosure` | `skills-list`/`skill-view` exist |
| `skills-format-compliance` | agentskills.io format |
| `constraints-immutable-files` | Write protection works |
| `architectural-safety` | Timeouts, max-steps, sandbox |

### Alignment Status

| Status | Count |
|--------|-------|
| ✅ Implemented | 6 |
| ⚠️ Partial | 3 |
| ❌ Missing | 1 |

**Overall: 85%**

---

## Completed (2026-03-23) — Upstream PR for nil/null Tool Names

Created upstream PR for bug discovered through local defensive code:

### PR Details

| Item | Value |
|------|-------|
| **PR #** | 1305 |
| **Repo** | karthink/gptel |
| **Branch** | `fix-nil-tool-names` |
| **Files** | `gptel-openai.el` (+20/-16) |
| **URL** | https://github.com/karthink/gptel/pull/1305 |

### The Bug

When LLM returns tool call with nil/null function name during streaming, code incorrectly treats it as "old tool block continues", creating malformed entries that hang FSM.

### The Fix

Changed `if` to `cond` to explicitly handle:
1. Valid function name → new tool block
2. Invalid function name at start → skip with warning
3. Continuing previous block → collect arguments

### What Stayed Local

- `my/gptel--sanitize-tool-calls` — defensive pre-check
- `my/gptel--nil-tool-call-p` — redundant with PR
- "invalid" tool registration — defensive fallback
- Doom-loop detection — defensive framework

### Key Insight

```
λ pr_scope(x).    minimal_fix(x) > defensive_framework(x)
                  | clean_branch(upstream/master) > fork_branch(x)
```

### Memories Created

- `upstream-pr-workflow.md` — workflow for future PRs

---

## Completed (2026-03-23) — DashScope Upstream Review

Reviewed DashScope-specific code for potential upstream contributions:

### Analysis

| Local Fix | Upstream Handling | Decision |
|-----------|-------------------|----------|
| `:null` stream filter | gptel-openai.el:136-137, gptel-gemini.el:98, gptel-anthropic.el:93 | Removed (redundant) |
| `search-failed` handler | gptel-request.el:3007-3008 returns error message | Removed (redundant) |
| `:curl-args '("--http1.1")` | Already uses upstream `:curl-args` slot | Keep (no PR needed) |
| 60% auto-compact threshold | Local-specific logic | Keep (defensive) |
| nil content sanitizer | Defensive JSON guard | Keep (edge-case) |

### Commits

- `0c52754` Δ gptel-ext-core: remove redundant :null filter and curl hardening (-44 lines)

### Key Insight

Upstream gptel already filters `:null` in streaming parsers before reaching `gptel-curl--stream-insert-response`. Local code was redundant defensive layer.

---

## Completed (2026-03-22) — Code Review Bug Fixes

Fixed correctness bugs, security vulnerabilities, and design issues across gptel AI assistant modules:

### Commits

| Module | Issues Fixed |
|--------|--------------|
| `gptel-tools-code.el` | Ripgrep word boundaries, truncation ratio configurable, Code_Usages caching |
| `gptel-tools-agent.el` | Cache key collision, XML escape quotes, file path validation, cache max size, FSM unwind-protect |
| `gptel-agent-loop.el` | Continuation context limit configurable, marker cleanup, cleanup functions |
| `gptel-tools-edit.el` | Abort check race fix, multi-line fence regex, file validation, patch options |
| `gptel-tools-preview.el` | Temp file cleanup, patch sanitization, callback order fix, max patch size |

### Key Discoveries

1. **`cl-return-from` pitfall**: `defun` doesn't create `cl-block` in Emacs Lisp
2. **`t` is reserved**: Can't use `t` as lambda parameter
3. **Buffer killed before callback**: Common pattern causing errors
4. **Paren balance**: Critical for file loading

### Verification

All passes: `scripts/verify-nucleus.sh`

---

## Completed (2026-03-22) — Code_Usages Caching

Added caching mechanism for large Code_Usages results to prevent LLM token bloat:

### Implementation

| Component | Description |
|-----------|-------------|
| Cache directory | `var/tmp/usages/` |
| Threshold | Results >50k chars cached to file |
| TTL | 1 hour auto-expiry |
| Format | Header with metadata + usages |

### Files Modified

- `lisp/modules/gptel-tools-code.el`:
  - Added `my/gptel-find-usages-cache-dir`, `my/gptel-find-usages-async-threshold`
  - Added cache management functions: `my/gptel--usages-cache-init`, `my/gptel--usages-cache-file`, `my/gptel--usages-cache-get`, `my/gptel--usages-cache-write`
  - Modified `my/gptel--find-usages` to cache large results
  - Fixed `cl-return-from` pitfall in `gptel-tools-code--diagnostics`
- `lisp/modules/gptel-tools.el`:
  - Reordered requires: `gptel-tools-code` before `gptel-tools-agent`
  - Prevents load-order race where `gptel-agent-tools` loads before `gptel-tools-code-register` is defined

### Key Insight

`gptel-tools-agent.el` has `(eval-and-compile (require 'gptel-agent))` which loads `gptel-agent-tools`, triggering `with-eval-after-load` callbacks. If `gptel-tools-code` isn't loaded yet, `gptel-tools-code-register` is void.

---

## Completed (2026-03-22) — FSM & Preset System Fixes

Fixed multiple bugs in gptel-agent FSM and nucleus preset integration:

### Key Fixes

| Issue | Root Cause | Fix |
|-------|------------|-----|
| `cl-return-from` error | `defun` doesn't create `cl-block` | Use nested `if` instead |
| Header-line stuck on "Waiting..." | Missing DONE/ERRS/ABRT handlers | Now upstream in gptel-agent-tools.el |
| Preset switch not working | `gptel-agent` ≠ `nucleus-gptel-agent` | Added redirect in `nucleus--around-apply-preset` |
| `:steps` warning | gptel doesn't recognize agent YAML property | Added `gptel-steps` variable |

### Files Modified

- `lisp/eca-security.el` — Removed `cl-return-from`, restructured with `if`
- `lisp/modules/nucleus-presets.el` — Preset redirect + agent YAML vars
- `lisp/modules/gptel-ext-fsm.el` — Removed duplicate handler registration
- `assistant/agents/plan_agent.md` — Next Step Wizard (replaced "say go")

### Next Step Wizard

Plan agent now suggests contextual `@preset` based on task type:

```
**Next Step:** @tdd-dev — Plan involves new API endpoints with test coverage
```

| Plan Type | Preset |
|-----------|--------|
| New feature + tests | `@tdd-dev` |
| Bug fix with diagnosis | `@debug` |
| Production code only | `@=code` |
| Refactoring | `@=refactor` |

### Memory Created

`mementum/memories/cl-return-from-pitfall.md`

---

## Completed (2026-03-22) — Workflow Benchmark Evolution

Analyzed code_agent workflow and improved exploration task efficiency:

### Anti-Pattern Analysis

| Test | Efficiency | Steps | Status |
|------|------------|-------|--------|
| code-001 | 0.82 | 6 | ✓ Pass |
| code-002 | 0.90 | 5 | ✓ Best |
| code-003 | 0.72 | 8 | ⚠ Approach threshold |

No anti-patterns triggered (all pass Wu Xing constraints).

### Improvements Applied

1. **code-003 task scoping**: Added exploration budget (3-5 files max)
2. **Efficiency thresholds**: Tightened max_steps (20→15), max_duration (120s→90s)
3. **Memory created**: `mementum/memories/code-agent-efficiency-patterns.md`

### Evolution Status

- Cycle: 0 (not yet triggered)
- Capabilities: none
- AI Complete: false

---

## Completed (2026-03-22) — DashScope Timeout Solutions

Implemented two-pronged solution for DashScope timeout errors at high token counts:

### 1. Backend-Aware Auto-Compact Threshold

| Backend | Threshold | Reason |
|---------|-----------|--------|
| DashScope | 60% | Server-side timeout limits (~100k tokens max) |
| Others | 80% | Standard headroom for response generation |

New functions:
- `my/gptel--backend-type` — Detect current backend (:dashscope, :gemini, etc.)
- `my/gptel--effective-threshold` — Return backend-specific threshold
- `my/gptel--current-tokens` — Calculate current token count

### 2. Auto-Delegation

When context exceeds threshold:
1. Intercept `gptel-request` via advice
2. Smart context selection (full/recent/task-only)
3. Delegate to "explorer" subagent with clean context
4. Return result to original callback

New customizations:
- `my/gptel-auto-compact-threshold-dashscope` (default 0.60)
- `my/gptel-auto-delegate-enabled` (default t)
- `my/gptel-auto-delegate-threshold-absolute` (default nil)

Commands:
- `M-x my/gptel-auto-delegate-enable`
- `M-x my/gptel-auto-delegate-disable`
- `M-x my/gptel-context-window-show` — Shows backend, threshold, delegate status

File: `lisp/modules/gptel-ext-context.el` (v3.0.0, +200 lines)

---

## Completed (2026-03-22) — Defensive Nil Guards & Startup Fix

Committed fixes for `wrong-type-argument` crashes:

| Commit | Issue | Fix |
|--------|-------|-----|
| `57d96ab` | FSM markers nil → overlay crash | Guard `(markerp m) (marker-position m)` before overlay/buffer ops |
| `aa4e5e8` | HTTP status nil → `=` crash | Guard `(numberp status)` before `(= status 400)` |
| `39b69d1` | Payload estimation silent fail | Add error logging to JSON serialization fallback |
| `8a6c380` | Broken `let*` indentation | Fix `(syms ...)` binding alignment |
| `87c03ed` | Startup hang on `package-refresh-contents` | Load archives from cache (< 24h) instead of network; disable `auto-package-update-maybe` |

Files changed:
- `gptel-tools-agent.el` — Marker validation + fallback to `(point-marker)`
- `gptel-agent-loop.el` — Same marker guard pattern
- `gptel-ext-tool-confirm.el` — Tool confirm marker fallback
- `gptel-ext-retry.el` — `(numberp status)` guard, error logging
- `pre-early-init.el` — `my/package-skip-network-refresh-p` cache advice
- `lisp/init-tools.el` — Disable auto-package-update on startup

## Key Pattern

**Defensive nil guards for Elisp:**

```elisp
;; Before: crashes on nil
(= status 400)
(make-overlay start tracking-marker)

;; After: guards prevent crash
(and (numberp status) (= status 400))
(and (markerp tm) (marker-position tm) tm)
```

## Related

- mementum/knowledge/project-facts.md — Project architecture
- mementum/knowledge/nucleus-patterns.md — Eight Keys, Wu Xing, VSM

---

## Earlier (2026-03-21) — Cleanup & Review

Removed redundant code:
- Deleted 73-line gptel preview patch from `gptel-config.el` — upstream gptel.el v0.9.9.4 (commit c962243) already has the fix

Committed fixes (e93f2ae, 6f698c4):
- `gptel-config.el`: Patch gptel preview handle (now removed - upstream fixed)
- `post-init.el`: Mode-line restoration for buffers created during startup
- `init-ai.el`: Removed duplicate `ai-code--gptel-agent-setup-transform` call
- `init-org.el`: org-agenda `C-c a` → `C-c g` (C-c a used by ai-code-menu)

## Earlier (2026-03-20) — Mementum Cleanup

Noise memory prevention:
- Deleted 45 auto-generated memory files (improvement-cycle-*, evolve-skill-*) with null results
- Fixed `gptel-benchmark-auto-improve.el` — guard memory creation with insight check
- Fixed `gptel-benchmark-integrate.el` — guard feed-forward memory
- Fixed `patterns.md` stale reference to non-existent benchmark-roadmap.md

Temp file consolidation:
- Added `gptel-benchmark-make-temp-file` helper in `gptel-benchmark-core.el`
- Updated `gptel-benchmark-editor.el`, `gptel-benchmark-rollback.el` to use var/tmp/
- Updated Python scripts to output to `var/tmp/benchmark-outputs`, `var/tmp/eval-outputs`
- Removed `benchmarks/skill-results/` (temp test-run outputs)

Memory count: 10 remaining (all actual insights)

## Earlier (2026-03-20)

Closed workflow benchmark gaps:
- CI: Added workflow benchmarks to evolution.yml processing
- Anti-patterns: Added workflow-specific patterns (phase-violation, tool-misuse, context-overflow, no-verification)
- Memory: Added `gptel-workflow-retrieve-memories` for workflow context
- Trend: Added `gptel-workflow-benchmark-trend-analysis` for evolution integration

Critical hardening:
- Nil guards: Added `(or ... 0)` guards to all anti-pattern detection plist-get calls
- Defcustom: Converted `gptel-benchmark-verify-threshold` and `gptel-benchmark-verify-enabled` to proper customization

Finalized auto-evolve system:
- Fixed `gptel-benchmark--run-quick-benchmark` to use real benchmark when `gptel-agent--task` available
- Created seed benchmark data for 4 skills + 2 workflows
- CI evolution workflow can now process both skill and workflow benchmarks

## Key Insight

Two skill types:
1. **Protocol skills** (no deps) → consolidate to `mementum/knowledge/`
2. **Tool skills** (REPL/API deps) → keep skill, reference protocol via `depends:`

Auto-evolve cycle:
```
Daily Work → Collect Metrics → Detect Anti-patterns (相克) → Auto-Improve (相生) → Store Memory → Update State → Evolve
```

## Module Structure

```
gptel-benchmark-*.el (15 modules):
├── gptel-benchmark-principles.el   # Eight Keys, Wu Xing
├── gptel-benchmark-core.el         # JSON, history, utilities
├── gptel-skill-benchmark.el        # Skill test runner
├── gptel-workflow-benchmark.el     # Workflow test runner + memory + trend
├── gptel-benchmark-analysis.el     # Flaky tests, patterns
├── gptel-benchmark-comparator.el   # Version comparison
├── gptel-benchmark-evolution.el    # Ouroboros cycle + anti-patterns
├── gptel-benchmark-auto-improve.el # 相生/相克 improvements + verification
├── gptel-benchmark-memory.el       # Mementum integration + synthesis
├── gptel-benchmark-daily.el        # Daily workflow hooks
├── gptel-benchmark-integrate.el    # Evolution + Improve + LLM
├── gptel-benchmark-subagent.el     # Subagent for review
├── gptel-benchmark-tests.el        # ERT unit tests
├── gptel-benchmark-integration-tests.el # ERT integration tests
├── gptel-benchmark-llm.el          # LLM suggestions
├── gptel-benchmark-editor.el       # File editing
└── gptel-benchmark-rollback.el     # Safety rollback
```

## Test Verification

Run: `./scripts/verify-integration.sh`

```
Level 1: Unit Tests (ERT) - 38 tests
Level 2: Integration Tests (ERT) - 11 tests  
Level 3: E2E Tests (Shell) - 3 tests
```

## Benchmark Data

```
benchmarks/
├── clojure-expert-results.json
├── reddit-results.json
├── requesthunt-results.json
├── seo-geo-results.json
└── workflows/
    ├── plan_agent-results.json
    └── code_agent-results.json
```