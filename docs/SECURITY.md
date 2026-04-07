# Security Model

This document describes the security architecture of the nucleus Emacs configuration.

## Overview

Nucleus implements a multi-layer security model for AI agent tool execution:

1. **ACL Router** — Permission-based tool access control
2. **Sandbox** — Restricted execution environment for untrusted operations
3. **Permit System** — User-controlled tool authorization

## ACL Router

Located in `lisp/modules/gptel-ext-security.el`, the ACL router intercepts tool creation via `gptel-make-tool` advice.

### Deny Rules

Tools matching deny rules are blocked from execution:

```elisp
(defvar my/gptel-tool-deny-rules
  '((:tool "Bash" :args (("command" . "rm\\(-rf\\|.*-rf\\)")))
    (:tool "Bash" :args (("command" . "sudo")))
    (:tool "Bash" :args (("command" . "chmod")))
    (:tool "Bash" :args (("command" . "eval\\|exec")))
    (:tool "Edit" :args (("file_path" . "\\.git/")))))
```

### Mode-Based Restrictions

Plan mode operates under stricter constraints than Agent mode:

| Mode | Allowed Toolsets | Restrictions |
|------|------------------|--------------|
| Plan | `:readonly` | No file modification, no Bash |
| Agent | `:nucleus` | Full tool access with confirmation |

## Sandbox

The `Programmatic` tool (`lisp/modules/gptel-sandbox.el`) provides a restricted Lisp subset for tool orchestration:

### Allowed Forms

```elisp
;; Control flow
(if when unless)

;; Local binding
(let let*)

;; Data access
(plist-get alist-get assoc cons)

;; Tool invocation
(tool-call result)
```

### Limits

- **Max tool calls**: 20 per orchestration
- **Timeout**: 60 seconds
- **Result truncation**: 4000 chars for subagent results

### Evaluation

The sandbox uses a whitelist approach — only explicitly allowed forms are evaluated. All other Lisp forms result in rejection.

## Permit System

Located in `lisp/modules/gptel-ext-tool-permits.el`, the permit system manages tool authorization.

### Tiers

| Level | Upstream | Behavior |
|-------|----------|----------|
| `auto` | `nil` | No confirmation ever |
| `normal` | `'auto` | Confirm tools with `:confirm t` |
| `confirm-all` | `t` | Confirm every tool call |

### Commands

- `M-x my/gptel-toggle-confirm` — Cycle through tiers
- `M-x my/gptel-show-permits` — Display permitted tools
- `M-x my/gptel-emergency-stop` — Abort all requests, clear permits, lock down

### Minibuffer Dispatch

During tool confirmation:

| Key | Action |
|-----|--------|
| `y` | Accept once |
| `n` | Defer (FSM stays paused) |
| `k` | Kill request |
| `a` | Accept and add to permits |
| `i` | Show tool info |
| `p` | Preview (for Edit/ApplyPatch) |
| `q` | Quit |

## Preview System

Located in `lisp/modules/gptel-tools-preview.el`, the preview system shows diffs before applying:

- **Edit tool** — Unified diff preview
- **ApplyPatch tool** — Patch preview with rejection handling
- **Programmatic** — Aggregate preview for multi-step plans

Preview is controlled by `gptel-tools-preview-enabled` (default: `t`).

## Best Practices

1. **Start in Plan mode** for exploration and analysis
2. **Switch to Agent mode** only when changes are needed
3. **Use `M-x my/gptel-emergency-stop`** if the agent behaves unexpectedly
4. **Review permits** with `M-x my/gptel-show-permits` before long sessions
5. **Enable confirmation** with `M-x my/gptel-toggle-confirm` for untrusted contexts

## Architecture

```
User Input
    │
    ▼
┌─────────────────┐
│   ACL Router    │ ◄── Deny rules check
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Permit Check   │ ◄── my/gptel-permitted-tools
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Confirmation UI │ ◄── Minibuffer/Overlay
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Tool Execution │
└─────────────────┘
```

## File Reference

| File | Purpose |
|------|---------|
| `gptel-ext-security.el` | ACL router, deny rules |
| `gptel-ext-tool-permits.el` | Permit management, confirmation UI |
| `gptel-sandbox.el` | Restricted Lisp evaluation |
| `gptel-tools-preview.el` | Diff preview system |
| `nucleus-tools.el` | Toolset definitions |
| `nucleus-presets.el` | Mode presets, tool contracts |