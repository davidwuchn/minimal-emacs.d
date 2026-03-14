# minimal-emacs.d + gptel-nucleus

A fork of [jamescherti/minimal-emacs.d](https://github.com/jamescherti/minimal-emacs.d)
extended with a full AI agent system built on
[gptel](https://github.com/karthink/gptel).

## Before you use this repo

This setup expects the ECA config and wrapper paths below to exist before you
use the project:

```bash
scripts/setup-eca-links.sh
```

Equivalent manual setup:

```bash
mkdir -p ~/.emacs.d ~/.config ~/bin
ln -sfn ~/.emacs.d/eca ~/.config/eca
ln -sfn ~/.emacs.d/eca/eca-secure ~/bin/eca
```

Required path layout:

- `~/.config/eca` -> `~/.emacs.d/eca`
- `~/bin/eca` -> `~/.emacs.d/eca/eca-secure`

Without these links, ECA-backed secure provider flows may not resolve the
expected config and wrapper locations.

Important: `~/.emacs.d/eca` is the real directory used by this setup. The
`~/.config/eca` path should be the symlink that points back to it.

## What this fork adds

**gptel** provides the chat engine and FSM-based tool execution. **nucleus**
adds tool management, preset routing, security ACLs, prompt infrastructure,
payload resilience, and an agent workflow inside Emacs.

## Upstream init chain note

Recent upstream `minimal-emacs.d` now exposes four startup-stage toggles:

- `minimal-emacs-load-pre-early-init`
- `minimal-emacs-load-post-early-init`
- `minimal-emacs-load-pre-init`
- `minimal-emacs-load-post-init`

These let you temporarily skip hook files while debugging startup issues or
bisecting configuration problems. In practice, `pre-early-init.el` is the best
place to disable the later three stages:

```elisp
(setq minimal-emacs-load-post-early-init nil
      minimal-emacs-load-pre-init nil
      minimal-emacs-load-post-init nil)
```

Important caveat: `minimal-emacs-load-pre-early-init` is checked before
`pre-early-init.el` itself is loaded, so it only helps if you set it from an
earlier external startup path.

## Key capabilities

- **Agent and Plan modes** - separate presets with different capability
  profiles. `gptel-agent` gets the full action toolset; `gptel-plan` stays
  readonly but can still bundle readonly Programmatic workflows.
- **31-tool nucleus stack** - Bash, Glob, Grep, Read, Write, Edit,
  ApplyPatch, Preview, Programmatic, RunAgent, structural Code_* tools, and
  Emacs introspection tools.
- **Programmatic orchestration** - restricted Emacs Lisp programs can chain
  multiple tools in one call. Agent mode supports preview-backed mutating runs;
  plan mode gets a separate readonly profile.
- **Aggregate mutating preview** - multi-step mutating Programmatic runs now
  show one aggregate approval summary before the existing per-tool preview and
  confirmation flow.
- **Subagent delegation** - `RunAgent` can spawn explorer, researcher,
  reviewer, and executor subagents with scoped toolsets.
- **Security ACLs** - hard capability filtering by preset. Readonly plan mode
  physically cannot reach mutating tools.
- **Payload resilience** - pre-send payload compaction, retry-time tool-result
  truncation, tool-array reduction, and reasoning repair for thinking-enabled
  models like Moonshot/Kimi.
- **Tree-sitter code tooling** - structural map, inspect, replace, usages, and
  diagnostics across a multi-language workspace.
- **Backend indirection** - one backend/model source of truth in
  `lisp/gptel-config.el` for presets, subagents, and routing.
- **CI and regression coverage** - dedicated suites for Programmatic flows,
  confirmation UI, payload trimming, and nucleus tool validation.

## Architecture

```text
lisp/modules/
  gptel-ext-backends.el      Backend definitions
  gptel-ext-fsm.el           FSM recovery / stuck-state fixes
  gptel-ext-reasoning.el     Thinking-model reasoning capture/injection
  gptel-ext-retry.el         Retry logic + payload compaction
  gptel-ext-security.el      Preset ACL routing
  gptel-ext-streaming.el     Streaming safety helpers
  gptel-ext-tool-confirm.el  Confirmation UI + permit memory
  gptel-ext-tool-sanitize.el Nil-tool filtering / doom-loop detection
  gptel-tools.el             Tool registration orchestrator
  gptel-tools-agent.el       RunAgent + subagent delegation
  gptel-tools-code.el        Code_Map / Inspect / Replace / Usages / Diagnostics
  gptel-tools-preview.el     Unified diff preview layer
  gptel-tools-programmatic.el
                             Programmatic tool registration
  gptel-sandbox.el           Restricted Programmatic evaluator
  gptel-programmatic-benchmark.el
                             Benchmark harness for Programmatic workflows
  nucleus-tools.el           Toolset definitions and filtering
  nucleus-presets.el         Preset management + contract validation
  nucleus-prompts.el         Prompt loading from `assistant/prompts/`

assistant/prompts/           Agent and plan system prompts
tests/                      ERT suites for Programmatic, trim, and UI flows
.github/workflows/ci.yml    Compile + Programmatic/trim/nucleus CI
```

## Multi-backend support

Configured for Moonshot/Kimi (default), DashScope/Qwen, DeepSeek, Gemini,
OpenRouter, GitHub Copilot, MiniMax, and Cloudflare Workers AI. Backend/model
selection is centralized so presets and subagents inherit the active default
instead of hardcoding provider-specific values.

## ECA + ai-code Integration

[ECA](https://github.com/editor-code-assistant/eca-emacs) (Editor Code Assistant)
integrates with [ai-code](https://github.com/tninja/ai-code) via a thin extension
layer that delegates to upstream packages where possible.

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        ai-code (frontend)                        │
│   ai-code-select-backend → 'eca                                  │
└───────────────────────────┬─────────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────────┐
│                   ai-code-eca.el (upstream)                      │
│   :start, :switch, :send, :resume                                │
└───────────────────────────┬─────────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────────┐
│                ai-code-eca-bridge.el (extensions)                │
│   Session mgmt, context commands, keybindings, health verify     │
│   15 autoloaded commands, ~370 lines                             │
└───────────────────────────┬─────────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────────┐
│                     eca-ext.el (support)                         │
│   Programmatic context API, session multiplexing                 │
│   ~290 lines                                                     │
└───────────────────────────┬─────────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────────┐
│                    ECA (upstream package)                        │
│   eca-chat-add-workspace-root, eca--session-for-worktree,       │
│   automatic worktree detection                                   │
└─────────────────────────────────────────────────────────────────┘
```

### What's in upstream vs extensions

| Feature | Source | Location |
|---------|--------|----------|
| Core backend (start/switch/send/resume) | upstream | `ai-code-eca.el` |
| Add workspace folder | upstream | `eca-chat-add-workspace-root` |
| Worktree detection | upstream | `eca--session-for-worktree` |
| Session list/switch | bridge | `ai-code-eca-list-sessions`, `ai-code-eca-switch-session` |
| Context commands | bridge | `ai-code-eca-add-file-context`, etc. |
| Keybindings | bridge | `ai-code-eca-keymap`, `C-c e` prefix |
| Health verification | bridge | `ai-code-eca-verify-health` |
| Context sync | bridge | `ai-code-eca-sync-context` |
| Programmatic context API | eca-ext | `eca-chat-add-file-context`, etc. |

### Setup

In `init-ai.el`:

```elisp
(with-eval-after-load 'ai-code
  (with-eval-after-load 'eca
    (require 'ai-code-eca-bridge)))
```

### Keybindings

| Key | Command |
|-----|---------|
| `C-c e l` | List sessions |
| `C-c e s` | Switch session |
| `C-c e f` | Add file context |
| `C-c e c` | Add cursor context |
| `C-c e m` | Add repo map |
| `C-c e y` | Add clipboard |
| `C-c e a` | Add workspace folder |
| `C-c e v` | Verify health |

In `eca-chat-mode`:

| Key | Command |
|-----|---------|
| `C-c C-f` | Add file context |
| `C-c C-c` | Add cursor context |
| `C-c C-m` | Add repo map |
| `C-c C-y` | Add clipboard |
| `C-c C-a` | Add workspace folder |

---

This fork builds on
[minimal-emacs.d](https://github.com/jamescherti/minimal-emacs.d) by James
Cherti. See the upstream `README.md` for the base Emacs configuration.
