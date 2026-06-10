---
title: "Research: DeepSeek-Reasonix Context Cache Architecture — Implemented in OV5"
status: done
category: research
tags: [context-cache, prefix-cache, ov5, deepseek, reasonix, architecture]
related: [research-planning-graph-plansearch-ov5, research-attention-residuals-ov5, research-openmythos-looped-ov5]
depends-on: []
---

# DeepSeek-Reasonix vs OV5: Context Cache Architecture Analysis

## Executive Summary

DeepSeek-Reasonix (20.5k stars, Go-based coding agent) is engineered **from the ground up around prefix-cache stability**. Every architectural decision — from two-model collaboration to context compaction to session design — serves a single purpose: keep the system prompt prefix byte-stable across turns so DeepSeek's automatic prefix cache stays warm.

OV5, by contrast, treats context as **disposable per-experiment state**. Each experiment cycle rebuilds the full prompt from scratch, with no awareness of whether the LLM can cache the prefix. This is a significant gap that costs tokens, increases latency, and limits how long OV5 can run autonomously before hitting context window limits.

This analysis identifies **6 architectural gaps** and proposes concrete implementations for OV5.

---

## 1. What DeepSeek-Reasonix Does (The Gold Standard)

### 1.1 Prefix-Cache Stability as Core Design Principle

Reasonix's entire architecture is built around one invariant:

> **"The system-prompt prefix (base prompt + tools + memory) must stay byte-stable across turns so DeepSeek's automatic prefix cache stays warm. Never mutate it mid-session — ride the turn tail instead."**
> — REASONIX.md § Conventions

This is not an optimization — it's the **foundational constraint** that shapes every other decision.

### 1.2 Two-Model Collaboration with Separate Sessions

When using a planner + executor model pair:

- **Planner** runs in its own session with read-only tools
- **Executor** runs in its own session with full tool access
- **Sessions never mix** — neither model's prefix is disturbed by the other's turns
- Both grow **prepend-only** and stay cache-friendly

> "The sessions never mix, so neither model's prefix is disturbed by the other's turns; both grow prepend-only and stay cache-friendly." — SPEC.md §3.5

### 1.3 Low-Frequency Context Compaction

When prompt tokens reach `compactRatio` (default 0.8) of context window:

1. **Compacts once** before next turn
2. Summarizes older middle of session into single briefing
3. Replaces in place: `system + summary + recentKeep` (default 8) verbatim messages
4. **Boundary aligned** backward off any tool result so recent tail never begins with orphan tool message
5. **Dropped originals archived** to `~/.config/reasonix/archive/<timestamp>.jsonl`

> "This is the **only** point where the prompt prefix changes — a deliberate, rare 'cache-reset point'. Between compactions the session grows prepend-only and stays cache-friendly." — SPEC.md §3.6

### 1.4 Context Window Tracking Per Provider

Each provider declares its `context_window` in config:

```toml
[[providers]]
name = "deepseek-flash"
kind = "openai"
context_window = 1000000  # tokens; harness compacts near this limit
```

### 1.5 Session Persistence + Resume

Sessions can be saved and resumed across restarts. Previous transcript saved for history/resume via `/new` or `/clear`.

### 1.6 Project Memory (REASONIX.md)

Loaded into **every session's system prompt** (the cache-stable prefix). Hierarchical docs:
- `REASONIX.md` (committed/shared)
- `REASONIX.local.md` (personal, git-ignored)
- `~/.config/reasonix/REASONIX.md` (user-global)
- Any `REASONIX.md` in ancestor dir

---

## 2. OV5 Current Context Management

### 2.1 What OV5 Has

1. **Reactive payload compaction** (`my/gptel--compact-payload` in `gptel-ext-retry.el`)
   - 9 compaction passes + LLM-based system prompt compaction (pass 10)
   - Triggers when JSON payload exceeds byte limit (~200KB default)
   - **Problem**: This is about HTTP payload size, not LLM context window. It doesn't track tokens.

2. **Knowledge cache** (`gptel-auto-workflow--knowledge-cache`)
   - Hash table mapping knowledge keys to cached content
   - Time-based invalidation (1 hour max age)
   - **Problem**: Caches content, not LLM context state. Each experiment still rebuilds the full prompt.

3. **Context window config** (`gptel-ext-retry.el` line 13)
   - `context-window` property in backend registry
   - Used to compute payload byte limits
   - **Problem**: Only used for payload size, not proactive context management

4. **Allium research caching**
   - Distills research findings to compact statechart format
   - 5-10x smaller than English prose
   - **Problem**: Compression is good, but still rebuilt each experiment

### 2.2 What OV5 Lacks

1. **No prefix-cache awareness** — Prompts are rebuilt fresh each experiment with no consideration of whether the LLM can cache the stable prefix

2. **No turn-based prepend-only growth** — Each experiment cycle is independent; no session continuity

3. **No context window tracking** — Doesn't know how many tokens are in the current context or when to compact

4. **No proactive compaction** — Only reactive payload size compaction; no context-window-aware summarization

5. **No session separation** — Planner, executor, grader, reviewer all potentially share the same process state (though they run as subagents)

6. **No context state persistence** — Can't resume a "session" across daemon restarts

---

## 3. Six Gaps and Implementation Proposals

### Gap 1: No Prefix-Stable Prompt Structure

**Current behavior**: `gptel-auto-experiment-build-prompt` (line 1502) assembles a monolithic prompt string each experiment:
- System instructions
- Tool definitions
- Project context (AGENTS.md, mementum)
- Target file content
- Historical analysis
- Hypothesis suggestions
- Task hints
- Review feedback

All of this is concatenated fresh each time. The LLM sees a completely new prompt every experiment.

**What Reasonix does**: Separates prompt into:
- **Cache-stable prefix**: system prompt + tools + REASONIX.md memory (never changes mid-session)
- **Dynamic suffix**: current turn's user message + context (changes each turn)

**Proposed implementation for OV5**:

```elisp
;; New module: gptel-ext-prefix-cache.el

(defcustom gptel-auto-workflow-prefix-stable-p t
  "When non-nil, keep system prompt + tools + memory byte-stable across experiments.")

(defvar gptel-auto-workflow--prefix-cache-content nil
  "The cache-stable prefix content. Computed once per run, reused across experiments.")

(defun gptel-auto-workflow--compute-prefix-cache (target)
  "Compute the byte-stable prefix for experiments on TARGET.
This includes: system prompt, tool schemas, AGENTS.md summary, mementum state.
The result is cached and reused across all experiments in this run.")

(defun gptel-auto-experiment-build-prompt (target ...)
  "Build prompt with prefix-cache separation.
Static prefix is prepended by gptel-send; only dynamic content goes here.")
```

**Key insight**: With gptel, the `:system` parameter is the prefix. OV5 should compute the system prompt once per run and reuse it. Only the `:prompt` (user message) should change per experiment.

---

### Gap 2: No Context Window Tracking

**Current behavior**: OV5 doesn't know how many tokens are in the prompt. The `context-window` property exists in backend registry but is only used for payload byte limit calculation.

**What Reasonix does**: Tracks `prompt_tokens` reported by provider after each turn. Triggers compaction at 0.8 ratio.

**Proposed implementation**:

```elisp
;; Extend gptel-backend-registry with context-window tracking

(defcustom gptel-auto-workflow-context-window-limit 0.8
  "Ratio of context window at which to trigger compaction.")

(defvar gptel-auto-workflow--current-context-tokens 0
  "Estimated token count in current session context.")

(defvar gptel-auto-workflow--context-window-size 100000
  "Context window size for current backend.")

(defun gptel-auto-workflow--update-context-usage (response-info)
  "Update token count from RESPONSE-INFO plist.
Called after each LLM response to track cumulative context usage.")

(defun gptel-auto-workflow--context-compaction-needed-p ()
  "Return non-nil when context size exceeds compaction threshold.")
```

**Challenge**: gptel may not expose token usage in all backends. Need to implement token estimation fallback (e.g., ~3.5 bytes/token as used in `gptel-ext-retry.el`).

---

### Gap 3: No Proactive Context Compaction

**Current behavior**: Only reactive compaction when HTTP payload is too large. No summarization of older experiment history.

**What Reasonix does**: 
- Summarizes older middle of session into single briefing
- Replaces in place: `system + summary + recentKeep`
- Archives dropped originals
- Boundary aligned off tool results

**Proposed implementation for OV5**:

```elisp
;; Context compaction for experiment history

(defun gptel-auto-workflow--compact-experiment-history (results &optional keep-recent)
  "Summarize older experiment RESULTS into compact briefing.
Keeps KEEP-RECENT (default 3) most recent experiments verbatim.
Returns (summary . kept-results) cons.")

(defun gptel-auto-experiment-build-prompt (target experiment-id ... previous-results)
  "Build prompt with compacted history.
If previous-results > threshold, compact older ones before inclusion.")
```

**Implementation details**:
1. Keep last 3 experiment results verbatim (like Reasonix's `recentKeep = 8`)
2. Summarize older results into categories: kept patterns, failure modes, common errors
3. Archive full history to TSV (already done via `gptel-auto-experiment-log-tsv`)
4. Align compaction boundaries at experiment boundaries (not mid-experiment)

---

### Gap 4: No Session Separation

**Current behavior**: All subagents (executor, grader, reviewer, comparator) run in the same Emacs process. While they use different gptel buffers, there's no explicit session isolation for prefix cache.

**What Reasonix does**: Planner and executor run in **separate sessions** (separate conversation contexts). Neither's prefix is disturbed.

**Proposed implementation**:

```elisp
;; Session isolation for subagents

(defvar gptel-auto-workflow--executor-session-id nil
  "Session ID for executor subagent (cache-stable prefix).")

(defvar gptel-auto-workflow--grader-session-id nil
  "Session ID for grader subagent (separate prefix).")

(defun gptel-auto-workflow--create-isolated-session (role)
  "Create a new isolated gptel session for ROLE.
Each session has its own cache-stable prefix, preventing cross-contamination.")
```

**Note**: This may require changes to how gptel manages conversation state. The key is ensuring that each subagent's system prompt + tools are computed once and then prepended-only.

---

### Gap 5: No Token-Aware Prompt Building

**Current behavior**: Prompt sections are included based on A/B testing selection and strategy, with no consideration of token budget.

**What Reasonix does**: Prompt sections are always included (they're in the stable prefix). Dynamic content is the user's turn only.

**Proposed implementation**:

```elisp
;; Token budget management for dynamic prompt content

(defcustom gptel-auto-workflow-dynamic-token-budget 4000
  "Max tokens for dynamic content per experiment turn.")

(defun gptel-auto-experiment-build-prompt (target ...)
  "Build prompt respecting token budget.
Prioritize sections: target content > hypothesis > analysis > history.
Drop lower-priority sections if budget exceeded.")
```

**Priority order** (highest to lowest):
1. Target file content (essential)
2. Current hypothesis/suggestion (essential)
3. Task hint (high value)
4. Recent experiment results (3 most recent)
5. Analysis patterns (medium)
6. Mementum recall (low — already in stable prefix)
7. Git history (low)
8. Research findings (low — already in stable prefix)

---

### Gap 6: No Context State Persistence

**Current behavior**: If the daemon restarts, all experiment context is lost. Each new run starts from scratch.

**What Reasonix does**: Sessions persisted to disk. `/new` or `/clear` saves previous transcript. Can resume across restarts.

**Proposed implementation**:

```elisp
;; Session persistence

(defvar gptel-auto-workflow--session-state-file
  "var/tmp/session-state.json"
  "File to persist session context across daemon restarts.")

(defun gptel-auto-workflow--save-session-state ()
  "Save current session state (prefix cache, recent history) to disk.")

(defun gptel-auto-workflow--load-session-state ()
  "Load session state from disk on daemon startup.
Restores prefix cache and recent experiment context.")
```

**What to persist**:
- Prefix cache content (stable system prompt)
- Recent experiment results (last 3-5)
- Compaction summary of older history
- Current target and run ID

---

## 4. Implementation Priority

| Priority | Gap | Effort | Impact |
|----------|-----|--------|--------|
| P0 | Gap 1: Prefix-stable structure | Medium | High — immediate token savings |
| P0 | Gap 3: Proactive compaction | Medium | High — enables longer autonomous runs |
| P1 | Gap 2: Context window tracking | Low | Medium — foundation for compaction |
| P1 | Gap 5: Token-aware prompt building | Low | Medium — prevents context overflow |
| P2 | Gap 4: Session separation | High | Medium — cleaner architecture |
| P2 | Gap 6: Context state persistence | Medium | Low — nice to have |

---

## 5. Implementation Status

All 6 gaps have been implemented in `lisp/modules/gptel-ext-prefix-cache.el` (610 lines, 30 tests).

| Gap | Implementation | Commit |
|-----|---------------|--------|
| Gap 1: Prefix-stable structure | `gptel-prefix-cache-compute`, `gptel-prefix-cache-prepend` | a1dd8ca10 |
| Gap 2: Context window tracking | `gptel-prefix-cache-sync-from-backend` | b84f95d86 |
| Gap 3: Proactive compaction | `gptel-prefix-cache-compact-dynamic` | b84f95d86 |
| Gap 4: Session separation | `gptel-prefix-cache--role-caches`, per-role compute | 768e2d150 |
| Gap 5: Token-aware building | `gptel-prefix-cache-build-with-budget` | 0ca83385a |
| Gap 6: State persistence | `gptel-prefix-cache-save-to-file`, `load-from-file` | d6cc490e1 |

### Architecture

```
┌─────────────────────────────────────────┐
│  STABLE PREFIX (computed once per run)  │
│  - AGENTS.md conventions                │
│  - Tool schemas                         │
│  - Standing mementum knowledge          │
│  - OV5 architecture context             │
│  ~4KB, byte-stable across experiments   │
├─────────────────────────────────────────┤
│  ROLE-SPECIFIC PREFIX (per subagent)    │
│  - Executor: code improvement focus     │
│  - Grader: evaluation focus             │
│  - Reviewer: merge readiness focus      │
│  - Comparator: keep/discard focus       │
│  ~200 chars added to base prefix        │
├─────────────────────────────────────────┤
│  DYNAMIC SUFFIX (changes per experiment)│
│  - Target file content                  │
│  - Current hypothesis                   │
│  - Recent results (last 3 verbatim)     │
│  - Compacted older results (if >80%)    │
│  Budget-managed: 4000 tokens default    │
└─────────────────────────────────────────┘
```

### Key Invariants

1. **Prefix never mutates mid-run** — only the dynamic suffix changes per experiment
2. **Context window synced from backend** — DeepSeek 1M, moonshot 262k, Z-AI 200k
3. **Compaction at 80% threshold** — summarizes older results into categories
4. **Role isolation** — each subagent gets its own prefix cache
5. **State persists across restarts** — saved to `var/tmp/prefix-cache-state.eld`

---

## 6. Metrics to Track

After implementing these changes, track:

1. **Cache hit rate**: Estimated based on prompt structure (stable prefix ratio)
2. **Tokens per experiment**: Before/after comparison
3. **Context compactions per run**: Should be rare (only at 0.8 threshold)
4. **Max experiments before compaction**: Should increase significantly
5. **Average prompt size**: Should decrease for dynamic content

---

## 6. Key Insight: OV5's Architecture Is Actually Close

OV5 already has many of the pieces:
- `gptel-ext-retry.el` has compaction infrastructure (just needs to target context window, not payload size)
- `gptel-auto-workflow--knowledge-cache` exists (just needs to persist across experiments as prefix)
- `gptel-auto-experiment-log-tsv` archives history (just needs to be consulted for compaction)
- Backend registry has `context-window` property (just needs to be used proactively)

The gap is **architectural focus**, not missing infrastructure. Reasonix is designed *from* prefix-cache stability outward. OV5 needs to elevate this from an optimization to a core invariant.

---

## References

- DeepSeek-Reasonix: https://github.com/esengine/deepseek-reasonix
- SPEC.md (context management): §3.5 (two-model), §3.6 (compaction)
- REASONIX.md (project memory): Conventions + Memory sections
- OV5: `lisp/modules/gptel-ext-retry.el`, `lisp/modules/gptel-tools-agent-prompt-build.el`

---

*Gap count: 6 | Status: All implemented | Module: `lisp/modules/gptel-ext-prefix-cache.el` | Tests: 30/30 passing*
