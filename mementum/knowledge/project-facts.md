---
title: Project Facts
status: active
category: knowledge
tags: [architecture, modules, backend, configuration]
related: [mementum/knowledge/patterns.md, mementum/knowledge/nucleus-patterns.md]
---

# Project Facts: minimal-emacs.d + gptel-nucleus

> Last updated: 2026-03-20 (tag v0.8.1)

## Architecture Overview

Custom gptel + nucleus Emacs configuration. gptel provides the LLM chat/FSM engine; nucleus layers on tool management, agent presets, prompts, and UI.

## Module Structure (`lisp/modules/`)

| Module | Purpose | Lines |
|--------|---------|-------|
| `gptel-ext-core.el` | Residual core: temp dir, markdown compat, model config, mode hook, tool registry audit, curl hardening, content sanitizer | 286 |
| `gptel-ext-abort.el` | Curl timeouts, abort-generation, keyboard-quit advice, prompt marker helpers | 187 |
| `gptel-ext-backends.el` | Backend configuration (Moonshot, DashScope, DeepSeek, Gemini, OpenRouter, etc.) | 82 |
| `gptel-ext-context.el` | Auto-compact, context window detection, `my/gptel-add-project-files` | 290 |
| `gptel-ext-context-cache.el` | Context-window caching: model tables, OpenRouter fetch, disk persistence | 699 |
| `gptel-ext-fsm.el` | FSM recovery: fix-stuck-in-type, agent handler fixes, recover-on-error | 83 |
| `gptel-ext-fsm-utils.el` | FSM utility functions | 26 |
| `gptel-ext-reasoning.el` | Reasoning/thinking model support: key detection, capture, inject, noop tool, nil-tool strip | 268 |
| `gptel-ext-retry.el` | Auto-retry with exponential backoff, progressive trimming, pre-send compaction | 476 |
| `gptel-ext-security.el` | ACL router advice on gptel-make-tool | 95 |
| `gptel-ext-streaming.el` | Streaming flag, jit-lock protection during gptel responses | 79 |
| `gptel-ext-tool-confirm.el` | Enhanced tool confirmation UI (display-tool-calls override, permit-and-accept) | 389 |
| `gptel-ext-tool-permits.el` | Permit management: toggle-confirm, show-permits, emergency-stop, health-check | 125 |
| `gptel-ext-tool-sanitize.el` | Nil-tool filtering, tool-call sanitization, doom-loop detection, dedup | 191 |
| `gptel-ext-transient.el` | Transient menu extensions: suffix-system-message, filter-directive, crowdsourced prompts | 195 |
| `gptel-tools.el` | Tool registration orchestrator, readonly/action tool lists | 283 |
| `gptel-tools-agent.el` | RunAgent tool + subagent delegation + upstream Agent deregistration | 360 |
| `gptel-tools-apply.el` | ApplyPatch tool (unified diff + OpenCode envelope format) | 335 |
| `gptel-tools-bash.el` | Async Bash tool | 202 |
| `gptel-tools-code.el` | Code_Map, Code_Inspect, Code_Replace, Diagnostics, Code_Usages | 596 |
| `gptel-tools-edit.el` | Async Edit tool (string replacement + patch mode) | 174 |
| `gptel-tools-glob.el` | Async Glob tool | 157 |
| `gptel-tools-grep.el` | Async Grep tool | 144 |
| `gptel-tools-introspection.el` | Emacs introspection tools | 111 |
| `gptel-tools-preview.el` | Unified Preview tool (minibuffer confirm, never-ask-again option) | 403 |
| `gptel-tools-programmatic.el` | Programmatic tool registration + restricted orchestration | 46 |
| `gptel-programmatic-benchmark.el` | Local benchmark harness | 386 |
| `gptel-sandbox.el` | Restricted evaluator for serial Programmatic tool orchestration | 593 |
| `nucleus-presets.el` | Preset management, agent patching, tool contract validation | 354 |
| `nucleus-prompts.el` | Prompt loading from assistant/prompts/ | 288 |
| `nucleus-tools.el` | Toolset definitions, tool filtering, agent-tool contracts | 559 |
| `nucleus-tools-validate.el` | Tool signature validation | 132 |
| `nucleus-tools-verify.el` | Tool registration verification | 95 |
| `nucleus-header-line.el` | Header-line preset display | 92 |
| `treesit-agent-tools.el` | Core AST engine for Code_* tools | 173 |
| `treesit-agent-tools-workspace.el` | Workspace-wide search for Code_* tools | 70 |
| `treesit-local-xref.el` | Local xref backend using tree-sitter | 42 |

## Active Backend

Default: `gptel--minimax` / `minimax-m2.7-highspeed` (`api.minimaxi.com`). Single source of truth in `gptel-config.el`. DashScope, Moonshot, DeepSeek, Gemini, OpenRouter, Copilot, and CF-Gateway remain defined in `gptel-ext-backends.el` as available alternatives.

## Toolsets (`nucleus-toolsets`)

| Set | Tools | Used by |
|-----|-------|---------|
| `:readonly` | 19 | Plan mode, introspector subagent |
| `:researcher` | 20 | Researcher subagent |
| `:nucleus` | 31 | Agent mode, executor subagent |
| `:explorer` | 5 | Explorer subagent |
| `:reviewer` | 4 | Reviewer subagent |
| `:snippets` | (= `:nucleus`) | Derived from `:nucleus` |

## Confirmation UI

3 tiers mapping to upstream `gptel-confirm-tool-calls`:

| Level | Upstream value | Behavior |
|-------|---------------|----------|
| `auto` | `nil` | No confirmation ever |
| `normal` | `'auto` | Confirm tools with `:confirm t` (default) |
| `confirm-all` | `t` | Confirm every tool call |

Commands: `my/gptel-toggle-confirm`, `my/gptel-show-permits`, `my/gptel-emergency-stop`, `my/gptel-health-check`

## Payload Management

Three-layer defense against oversized API payloads:

```
Layer 1 — Pre-send (retries=0): my/gptel--compact-payload
  → Estimates JSON bytes via gptel--json-encode
  → 4-pass trimming if over limit

Layer 2 — Retry (retries=1): my/gptel-auto-retry
  → Trim tool results

Layer 3 — Retry (retries=2+): my/gptel-auto-retry
  → Truncate ALL results + strip reasoning_content + reduce tools array
```

## Code Tools Pipeline

```
treesit-agent-tools.el (core AST engine)
    ├── treesit-agent-tools-workspace.el (workspace-wide search)
    └── gptel-tools-code.el (gptel tool registration + preview)
            ├── Code_Map     (file structure)
            ├── Code_Inspect (node extraction)
            ├── Code_Replace (structural editing)
            ├── Code_Usages  (references via LSP/ripgrep)
            └── Diagnostics  (project-wide)
```

## Path Resolution

| Variable | Value |
|----------|-------|
| `minimal-emacs-user-directory` | Repo root (`~/.emacs.d/`) |
| `user-emacs-directory` | `var/` |
| `package-user-dir` | `var/elpa` |
| `treesit-extra-load-path` | `var/tree-sitter` |
| `custom-file` | Repo root `custom.el` |

## Feature Evaluation Decisions

| Feature | Decision | Rationale |
|---------|----------|-----------|
| Three-layer defense | Skip | Already covered by retry/compaction system |
| ECA-style recovery | Skip | Pre-send compaction already covers |
| Per-mode model routing | Skip | MiniMax handles the default modes cleanly |
| @-mention context selection | Skip | gptel-context + nucleus tools already provide |
| Prompt caching | Skip | OpenAI-compatible backends cache automatically |
| Compaction agent | Skip | Rare edge case; complexity not justified |
| Per-tool output limits | Skip | Subagent truncation works fine |
