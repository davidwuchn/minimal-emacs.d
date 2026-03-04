# STATE: Current Emacs Project Configuration

> Last updated: 2026-03-04 (commit 86fb489, tag v0.5.8)

## Architecture Overview

Custom gptel + nucleus Emacs configuration. gptel provides the LLM chat/FSM engine; nucleus layers on tool management, agent presets, prompts, and UI.

### Module Structure (`lisp/modules/`)

| Module | Purpose | Lines |
|--------|---------|-------|
| `gptel-ext-core.el` | Core advice/hooks: retry, FSM recovery, streaming, tool sanitization | ~1470 |
| `gptel-ext-backends.el` | Backend configuration (DashScope, etc.) | |
| `gptel-ext-context.el` | Context management extensions | |
| `gptel-ext-learning.el` | Learning integration | |
| `gptel-ext-security.el` | ACL router advice on gptel-make-tool | ~110 |
| `gptel-tools.el` | Tool registration orchestrator, readonly/action tool lists | ~320 |
| `gptel-tools-agent.el` | RunAgent tool + subagent delegation + upstream Agent deregistration | ~310 |
| `gptel-tools-apply.el` | ApplyPatch tool | |
| `gptel-tools-bash.el` | Async Bash tool | |
| `gptel-tools-code.el` | Code_Map, Code_Inspect, Code_Replace, Diagnostics, Code_Usages | ~460 |
| `gptel-tools-edit.el` | Async Edit tool | |
| `gptel-tools-glob.el` | Async Glob tool | |
| `gptel-tools-grep.el` | Async Grep tool | |
| `gptel-tools-introspection.el` | Emacs introspection tools (describe_symbol, get_symbol_source, find_buffers_and_recent) | |
| `gptel-tools-preview.el` | Unified Preview tool (diff display in side window) | ~290 |
| `nucleus-analytics.el` | Usage analytics | |
| `nucleus-mode-switch.el` | Plan/Agent mode switching | |
| `nucleus-presets.el` | Preset management, agent patching, tool contract validation | ~360 |
| `nucleus-prompts.el` | Prompt loading from assistant/prompts/ | ~280 |
| `nucleus-tools.el` | Toolset definitions (nucleus-toolsets constant), tool filtering | ~600 |
| `nucleus-tools-validate.el` | Tool signature validation (M-x nucleus-validate-tool-signatures) | |
| `nucleus-tools-verify.el` | Tool registration verification (M-x nucleus-verify-tools-interactively) | |
| `nucleus-ui.el` | Header-line, UI helpers | ~100 |

### Confirmation UI (`lisp/gptel-tool-ui.el`)

3 tiers mapping to upstream `gptel-confirm-tool-calls`:

| Level | Upstream value | Behavior |
|-------|---------------|----------|
| `auto` | `nil` | No confirmation ever |
| `normal` | `'auto` | Confirm tools with `:confirm t` (default) |
| `confirm-all` | `t` | Confirm every tool call |

Minibuffer dispatch: `y/n/k/a/i/p/q`. Upstream `n` = "defer" (FSM stays paused, overlay stays active — intentional upstream behavior).

### Toolsets (`nucleus-toolsets`)

| Set | Tools | Used by |
|-----|-------|---------|
| `:readonly` | 18 | Plan mode, introspector subagent |
| `:researcher` | 19 | Researcher subagent |
| `:nucleus` | 30 | Agent mode, executor subagent |
| `:explorer` | 3 | Explorer subagent (Glob/Grep/Read) |
| `:reviewer` | 3 | Reviewer subagent (Glob/Grep/Read) |
| `:snippets` | (= `:nucleus`) | Derived from `:nucleus`; tools with supplemental prompts |

### Advice/Hook Chain

| Advice | Target | Type | File | Purpose |
|--------|--------|------|------|---------|
| `my/gptel--sanitize-tool-calls` | `gptel--handle-tool-use` | `:before` | gptel-ext-core.el | Pre-filter nil tool calls |
| `my/gptel--detect-doom-loop` | `gptel--handle-tool-use` | `:before` | gptel-ext-core.el | Abort repeated identical tool calls |
| `my/gptel--display-tool-calls` | `gptel--display-tool-calls` | `:override` | gptel-ext-core.el | Enhanced tool confirmation UI |
| `my/gptel-auto-retry` | `gptel--fsm-transition` | `:around` | gptel-ext-core.el | Exponential backoff retry |
| `my/gptel-fix-fsm-stuck-in-type` | `gptel-curl--stream-cleanup` | `:around` | gptel-ext-core.el | Unstick FSM from TYPE state |
| `my/gptel--stream-set-flag` | `gptel-curl--stream-insert-response` | `:before` | gptel-ext-core.el | Set streaming flag for jit-lock protection |
| `my/gptel--jit-lock-safe` | `jit-lock-function` | `:around` | gptel-ext-core.el | Suppress jit-lock errors in gptel-mode buffers |
| `my/gptel-agent--task-override` | `gptel-agent--task` | `:override` | gptel-tools-agent.el | Parent-buffer tracking, large-result truncation |
| `my/gptel--deregister-upstream-agent` | `gptel-agent-update` | `:after` | gptel-tools-agent.el | Remove upstream "Agent" tool (RunAgent is superior) |

### Code Tools Pipeline

```
treesit-agent-tools.el (core AST engine)
    ├── treesit-agent-tools-workspace.el (workspace-wide search)
    └── gptel-tools-code.el (gptel tool registration + preview)
            ├── Code_Map     (file structure via get-file-map)
            ├── Code_Inspect (node extraction via extract-node + find-workspace)
            ├── Code_Replace (structural editing via replace-node)
            ├── Code_Usages  (references via LSP/ripgrep cascade)
            └── Diagnostics  (project-wide via flymake/LSP/CLI linters)
```

### Upstream gptel

Version 0.9.9.4 installed, but `.elc` files contain a **newer unreleased version** with the full FSM architecture (`gptel-fsm` struct). The `.el` source files are stale and don't match the compiled bytecode. DO NOT edit upstream files under `var/elpa/`.

## Known Issues

None currently. All identified bugs have been fixed and committed.

### Recent Changes (v0.5.8)

- **Dead code cleanup** (e81886e): Removed unused `:core` toolset, derived `:snippets` from `:nucleus`, deleted `nucleus-register-tool` helper, removed dead `gptel-tools.el` variables. Added `:depth` to advice ordering.
- **jit-lock timing gap fix** (de8e1b5): Changed `my/gptel--jit-lock-safe` gate from `my/gptel--streaming-p` to `(bound-and-true-p gptel-mode)` — eliminates post-response refontification gap.
- **INTRO.md** (255d4af): Fork overview and nucleus architecture summary for GitHub.
- **Unified nucleus engage header** (86fb489): All 28 agent/prompt/skill/doc files now use canonical `[phi fractal euler tao pi mu ∃ ∀] | [Δ λ Ω ∞/0 | ε/φ Σ/μ c/h] | OODA`. Collaboration lines preserved per-file (`Human ⊗ AI`, `Human ∧ AI` for nucleus-tutor, `Human ⊗ AI ⊗ REPL` for clojure-expert and reference docs).
- **Restore upstream init.el**: Reverted `init.el` to exact upstream `jamescherti/minimal-emacs.d`, deleted redundant `lisp/init-defaults.el`. All customizations now live exclusively in `post-init.el` / `post-early-init.el` / `pre-early-init.el` as intended. Added missing `no-byte-compile: t` to `post-early-init.el`.

### Phantom Issues (DO NOT attempt to fix)

These were hallucinated by prior AI sessions — verified as non-issues:

- `my/gptel--deliver-subagent-result` "truncation risk" — the 4000 char truncation IS the fix
