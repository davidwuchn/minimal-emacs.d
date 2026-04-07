---
title: Agent Architecture & Patterns
status: active
category: knowledge
tags: [agent, gptel, workflow, safety, efficiency, debugging]

# Agent Architecture & Patterns

## Overview

This page synthesizes patterns, safety mechanisms, and debugging techniques for the autonomous agent system built on gptel-agent. The agent framework enables LLM-powered code modification with safety guardrails, efficiency metrics, and autonomous research workflows.

**Maturity:** 60% production-ready (core loop functional, grading needs timeout handling)
**Key Files:** `lisp/modules/gptel-*.el`
**Last Updated:** 2026-03-24

---

## Architecture Layers

### Layer Stack

| Layer | Component | File | Purpose |
|-------|-----------|------|---------|
| 1 | Tools | `var/elpa/gptel-agent/gptel-agent-tools.el` | `:confirm t` tools from upstream |
| 2 | Safety | `lisp/modules/gptel-ext-*.el` | Local defensive patterns |
| 3 | Loop | `lisp/modules/gptel-agent-loop.el` | Max steps, hard loop limits |
| 4 | Workflow | `lisp/modules/gptel-auto-workflow.el` | Autonomous research orchestration |
| 5 | UI | `agent-shell-mode` | Interactive shell interface |

### Tool Confirmation Matrix

All dangerous tools use upstream's `:confirm t` mechanism:

```elisp
;; From gptel-agent-tools.el
(gptel--define-tool (name "Bash") (confirm t))
(gptel--define-tool (name "Eval") (confirm t))
(gptel--define-tool (name "Write") (confirm t))
```

| Tool | Danger Level | Confirmation |
|------|--------------|--------------|
| Bash | High | ✅ Required |
| Eval | Critical | ✅ Required |
| Mkdir | Medium | ✅ Required |
| Write | High | ✅ Required |
| Agent | High | ✅ Required |
| Read | Low | ❌ Not needed |

---

## Safety Mechanisms

### Reuse vs Local Decision Matrix

| Feature | Source | Why Local? |
|---------|--------|------------|
| `:confirm t` | Upstream | Already built-in |
| Web timeout (30s) | Upstream | Built-in for WebSearch/WebFetch |
| Max steps limit | **Local** | Project-specific (default: 50) |
| Doom-loop detection | **Local** | Defensive pattern, not upstream |
| Tool permits system | **Local** | Session-scoped approval memory |
| Payload size limits | **Local** | Project-specific threshold (1MB) |

### Max Steps Limit

```elisp
(defcustom gptel-agent-loop-max-steps 50
  "Maximum number of tool calls before forcing DONE state.")
```

### Doom-Loop Detection

Detects when the same tool call executes 3+ times consecutively:

```elisp
(defun gptel-ext-sanitize--check-doom-loop (tool-name args)
  "Abort if same tool+args called 3+ times consecutively."
  (let* ((key (cons tool-name args))
         (count (gethash key doom-loop-hash 0)))
    (puthash key (1+ count) doom-loop-hash)
    (when (> count 2)
      (user-error "[gptel] Doom loop detected: %s with %S" tool-name args count))))
```

### Tool Permits System

```elisp
;; Modes
(setq gptel-ext-permits-mode 'auto)       ;; No confirmation (trusted)
(setq gptel-ext-permits-mode 'confirm-all) ;; Every tool requires approval

;; Emergency stop
(defun my/gptel-emergency-stop ()
  "Abort all pending requests and clear permits."
  (interactive)
  (gptel-abort)
  (gptel-ext-permits-clear))
```

### Why Immutable File Protection is NOT Needed

| Protection Layer | Mechanism |
|------------------|-----------|
| Sandbox | Plan mode has Bash whitelist, Eval blacklist |
| Permit system | confirm-all mode requires approval |
| Git | Can revert any accidental change |
| Emergency stop | `my/gptel-emergency-stop` for disasters |
| Workspace boundary | Blocks out-of-workspace modifications |

---

## Efficiency Patterns

### Task Type Efficiency Matrix

| Task Type | Efficiency | Steps | Pattern |
|-----------|------------|-------|---------|
| Simple edit | 0.82-0.90 | 5-6 | read → edit (direct) |
| Exploration | 0.72 | 8 | glob → read×N → edit |

### Anti-Pattern Detection (Wu Xing Constraints)

| Anti-Pattern | Check | Threshold |
|--------------|-------|-----------|
| wood-
...[Result too large, truncated. Full result saved to: /Users/davidwu/.emacs.d/tmp/gptel-subagent-result-UjeNpD.txt. Use Read tool if you need more]...