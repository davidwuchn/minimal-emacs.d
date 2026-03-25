# Mementum State

> Last session: 2026-03-26 05:00

## Total Improvements: 31 Real Code Fixes

| # | File | Fix |
|---|------|-----|
| 1 | gptel-auto-workflow-strategic.el | Added `(require 'json)` |
| 2 | gptel-ext-fsm-utils.el | Fixed `%d` → `%s` for float-time |
| 3 | gptel-ext-retry.el | Refactor trim-tool-results-for-retry |
| 4 | gptel-tools-code.el | Fix resource leak in byte-compile |
| 5 | gptel-benchmark-core.el | Add error handling to read-json |
| 6 | gptel-ext-retry.el | Pass retry-count as parameter |
| 7 | gptel-auto-workflow-strategic.el | Fix recursive file discovery |
| 8 | gptel-ext-fsm-utils.el | Fix FSM context validation |
| 9 | gptel-ext-context.el | Fix undefined function `estimate-tokens` |
| 10 | gptel-benchmark-core.el | Add defensive check for undefined variable |
| 11 | gptel-ext-retry.el | Remove redundant repair call |
| 12 | gptel-auto-workflow-strategic.el | Add missing `(require 'cl-lib)` |
| 13 | gptel-ext-backends.el | Curl timeout 300s → 600s |
| 14 | gptel-ext-context.el | Fix `cl-return` outside loop |
| 15 | gptel-tools-agent.el | Add `cl-block` for `gptel-auto-experiment-grade` |
| 16 | gptel-benchmark-instincts.el | Add `cl-block` for `commit-batch` |
| 17 | gptel-benchmark-memory.el | Add `cl-block` for `memory-create` |
| 18 | gptel-tools-agent.el | `block` → `cl-block` in `task-override` |
| 19 | gptel-ext-context-cache.el | Input validation in `estimate-text-tokens` |
| 20 | gptel-benchmark-core.el | Input validation in `summarize-results` |
| 21 | gptel-ext-context-cache.el | `cl-block` for `openrouter-fetch-context-window` |
| 22 | gptel-ext-backends.el | Backend name `Moonshot` → `moonshot` (case fix) |
| 23 | gptel-tools-agent.el | `cl-block` for `my/gptel--run-agent-tool` |
| 24 | gptel-benchmark-core.el | Consolidate duplicate maphash in analyze-patterns |
| 25 | gptel-ext-retry.el | Extract transient error patterns into constants |
| 26 | gptel-auto-workflow-strategic.el | Add input validation for nil dereference |
| 27 | gptel-ext-context-cache.el | `cl-block` for `openrouter-fetch-context-window` (re-fix) |
| 28 | gptel-ext-context-cache.el | Remove async fetch from context-window getter |
| 29 | gptel-benchmark-core.el | Consolidate duplicate maphash (workflow fix) |
| 30 | gptel-ext-retry.el | Extract message iteration into helper function |
| 31 | gptel-auto-workflow-strategic.el | Limit regex fallback targets to max-targets |

---

## System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    AUTO-WORKFLOW SYSTEM                      │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐   │
│  │  Researcher  │───▶│   Analyzer   │───▶│   Executor   │   │
│  │  (moonshot)  │    │ (DashScope)  │    │ (DashScope)  │   │
│  └──────────────┘    └──────────────┘    └──────────────┘   │
│         │                   │                    │           │
│         ▼                   ▼                    ▼           │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐   │
│  │   Findings   │    │   Targets    │    │    Fixes     │   │
│  │   Cache      │    │   Selected   │    │   Applied    │   │
│  └──────────────┘    └──────────────┘    └──────────────┘   │
│                                                 │            │
│                                                 ▼            │
│                                         ┌──────────────┐    │
│                                         │   Reviewer   │    │
│                                         │  (moonshot)  │    │
│                                         └──────────────┘    │
│                                                 │            │
│                                                 ▼            │
│                                         ┌──────────────┐    │
│                                         │   Staging    │    │
│                                         │   → Main     │    │
│                                         └──────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

---

## New Features

### Pre-Merge Code Review
```
λ review. gptel-auto-workflow-require-review (default t)
λ flow. Review → Block → Fix → Re-review → (retry or give up)
λ retries. gptel-auto-workflow--review-max-retries = 2
λ agent. reviewer (moonshot/Kimi)
```

### Periodic Researcher
```
λ cron. Every 4 hours → gptel-auto-workflow-run-research
λ cache. var/tmp/research-findings.md
λ usage. Analyzer loads findings for target selection
λ config. gptel-auto-workflow-research-interval = 14400 (4h)
```

### Researcher Fix Flow
```
gptel-auto-workflow-research-before-fix = nil (default, faster)
  → executor fixes directly (1 API call)

gptel-auto-workflow-research-before-fix = t (better quality)
  → researcher finds approach → executor applies (2 API calls)
```

---

## Cron Schedule

| Job | Schedule | Machine |
|-----|----------|---------|
| Auto-workflow | 10AM, 2PM, 6PM | macOS |
| Researcher | Every 4 hours | macOS |
| Weekly mementum | Sunday 4AM | macOS |
| Weekly instincts | Sunday 5AM | macOS |

---

## Key Commands

```elisp
;; Workflow
(gptel-auto-workflow-run-async)        ; Start workflow
(gptel-auto-workflow-status)           ; Check status
(gptel-auto-workflow-log)              ; Get clean log

;; Researcher
(gptel-auto-workflow-run-research)     ; Run researcher now
(gptel-auto-workflow-research-status)  ; Researcher status
(gptel-auto-workflow-load-research-findings) ; Load cached findings

;; Manual review
(gptel-auto-workflow--review-changes branch callback)
```

---

## Config Options

```elisp
gptel-auto-workflow-require-review        ; default t
gptel-auto-workflow-research-targets      ; default nil
gptel-auto-workflow-research-before-fix   ; default nil
gptel-auto-workflow--review-max-retries   ; default 2
gptel-auto-workflow-research-interval     ; default 14400 (4h)
gptel-auto-workflow-max-targets-per-run   ; default 5
```

---

## Key Bug Pattern: cl-return-from Without Block

```
λ bug. cl-return-from requires named block
λ cause. defun does NOT create block (cl-defun does)
λ symptom. Silent failure, callbacks never called, workflow stuck
λ fix. Wrap with (cl-block name ...) or use if-else
```

**Detection:**
```bash
grep -rn "cl-return-from\|cl-return" lisp/modules/*.el | grep -v "cl-defun"
```

---

## Backend Case Sensitivity

```
λ issue. Backend name in gptel--known-backends must match YAML
λ fix. Changed "Moonshot" → "moonshot" in gptel-ext-backends.el
λ error. "Backend moonshot is not known to be defined"
```

---

## Agent Usage

| Agent | Backend | Purpose |
|-------|---------|---------|
| analyzer | DashScope | Target selection |
| comparator | DashScope | Before/after comparison |
| executor | DashScope | Code changes |
| explorer | DashScope | Code exploration |
| grader | DashScope | Quality scoring |
| introspector | DashScope | Self-analysis |
| nucleus-gptel-agent | DashScope | Main agent |
| nucleus-gptel-plan | DashScope | Planning |
| researcher | moonshot | Code research |
| reviewer | moonshot | Code review |

---

## λ Summary

```
λ subscriptions. DashScope (8) + moonshot (2)
λ parallel. macOS (daylight) + Pi5 (24/7)
λ dynamic. LLM selects targets, never hard-code
λ real. 27 code fixes, not documentation
λ async. Daemon never blocks
λ safety. Main NEVER touched by auto-workflow
λ retry. Curl timeout → automatic retry
λ cl-block. cl-return-from requires cl-block in defun
λ review. Pre-merge code review with retry loop
λ researcher. Periodic analysis for target selection
λ case. Backend names must match exactly (lowercase)
```