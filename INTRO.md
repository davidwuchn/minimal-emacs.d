# minimal-emacs.d + gptel-nucleus

A fork of [jamescherti/minimal-emacs.d](https://github.com/jamescherti/minimal-emacs.d)
extended with a full AI agent system built on
[gptel](https://github.com/karthink/gptel).

## Quick Start

```bash
# 1. Install required packages from Git
./scripts/setup-packages.sh

# 2. Setup ECA symlinks
./scripts/setup-eca-links.sh
```

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

## Package Installation

This fork uses **Git main branches** for `gptel` and `gptel-agent` (44 commits
ahead of ELPA) to get the latest features:

```bash
./scripts/setup-packages.sh          # Install if missing
./scripts/setup-packages.sh --force  # Reinstall
```

This clones to `var/elpa/`:
- `gptel` - Chat engine and FSM-based tool execution
- `gptel-agent` - Subagent delegation and tool orchestration

**Why Git main?** ELPA's `gptel-0.9.9.4` is missing functions required by
`gptel-agent` (e.g., `gptel--handle-pre-tool`). Git main has these fixes.

## Model Configuration

| Use Case | Model | Backend | Context | Pricing |
|----------|-------|---------|---------|---------|
| **Global default** | `qwen3-coder-next` | DashScope | 131k | $0.30/$1.20 |
| **Plan preset** | `qwen3.5-plus` | DashScope | 1M | $0.80/$4.80 |
| **Agent preset** | `glm-5` | DashScope | 131k | $0.50/$0.50 |
| **Subagents** | `qwen3-coder-next` | DashScope | 131k | $0.30/$1.20 |
| **ai-code helper** | `qwen3-coder-next` | DashScope | 131k | $0.30/$1.20 |

All models use DashScope backend (阿里云百炼). Requires `coding.dashscope.aliyuncs.com` API key in auth-source.

Configured in `lisp/gptel-config.el` and `lisp/modules/nucleus-presets.el`.

## Directory Structure

Follows upstream `minimal-emacs.d` with `user-emacs-directory` set to `var/`:

```
var/
├── autosave/        - Auto-save crash recovery [upstream]
├── backup/          - Versioned backups (.~1~) [upstream]
├── tramp-autosave/  - TRAMP auto-save [upstream]
├── cache/           - Cache files
├── elpa/            - Packages (gptel, gptel-agent)
├── lockfiles/       - Lock files
├── savefile/        - gptel context cache
├── tmp/             - Temp files (gptel tools)
├── history          - Command history
├── projects         - Project list
├── recentf          - Recent files
├── saveplace        - File positions [upstream]
└── tramp            - TRAMP persistence
```

Files in `var/` (not subdirectories) match upstream pattern.

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
| Workspace management | bridge | `ai-code-eca-list-workspace-folders`, `ai-code-eca-remove-workspace-folder`, `ai-code-eca-sync-project-workspaces` |
| Keybindings | bridge | `ai-code-eca-keymap`, `C-c e` prefix |
| Health verification | bridge | `ai-code-eca-verify-health` |
| Context sync | bridge | `ai-code-eca-sync-context` |
| Programmatic context API | eca-ext | `eca-chat-add-file-context`, etc. |
| Workspace provenance | eca-ext | `eca-workspace-folder-for-file`, `eca-workspace-provenance` |

### Setup

In `init-ai.el`:

```elisp
(with-eval-after-load 'ai-code
  (with-eval-after-load 'eca
    (require 'ai-code-eca-bridge)))
```

### ai-code-menu Integration

**Primary UX**: All ECA commands accessible via `M-x ai-code-menu` (typically `C-c a`).

When ECA is selected as the backend, press **E** to open the ECA submenu:

```
AI Code Menu (C-c a)
│
│ ...existing menu items...
│ N   Toggle notifications
│
└─E   ECA commands ─────────────────────┐
                                        │
                    ┌───────────────────┘
                    │
                    ▼
              ECA Commands
              ┌─ Workspace ─────────────────────
              │ m   Multi-Project Mode
              │ a   Add workspace folder
              │ A   Add to ALL sessions
              │ l   List workspace folders
              │ r   Remove workspace folder
              │ s   Sync project roots
              │ d   Session dashboard
              │ t   Toggle auto-switch
              ├─ Context ───────────────────────
              │ f   Add file context
              │ c   Add cursor context
              │ M   Add repo map
              │ y   Add clipboard
              │ S   Start context sync
              │ X   Stop context sync
              ├─ Shared Context ────────────────
              │ F   Share file
              │ R   Share repo map
              │ p   Apply shared context
              │ C   Clear shared context
              └─ Sessions ──────────────────────
                ?   Which session?
                L   List sessions
                w   Switch session
                v   Verify health
                u   Upgrade ECA
```

**No prefix key memorization needed** - all commands discoverable in menu.

### Multi-Project Mode

Quick toggle for multi-project workflows:

```
M-x ai-code-eca-multi-project-mode
```

Enables all auto-detection features at once:
- `eca-auto-switch-session` → `'prompt`
- `eca-auto-sync-workspace` → `t`
- `eca-auto-add-workspace-folder` → `t`
- `ai-code-eca-mode-line-indicator` → `t`

Available in menu: `wm` (ECA Workspace → Multi-Project Mode)

### Auto-Detection

Configure automatic behaviors:

```elisp
;; Auto-add project to workspace on file open (default: t)
(setq eca-auto-add-workspace-folder t)

;; Auto-switch session when project changes (default: 'prompt)
;; 'prompt = ask before switching (recommended)
;; t = switch automatically
;; nil = disabled
(setq eca-auto-switch-session 'prompt)

;; Auto-create session for new projects (default: nil)
(setq eca-auto-create-session t)

;; Auto-sync workspace on project switch (default: t)
(setq eca-auto-sync-workspace t)
```

These settings enable "just work" multi-project workflows:
- Open a file → project auto-added to workspace
- Switch to another project → prompted to switch session
- Open file in new project → session created automatically

### Visual Indicators

**Mode-line**: When `ai-code-eca-mode-line-indicator` is enabled (default), the mode-line shows:
```
ECA:1[2]  ; Session 1 with 2 workspace folders
```

**Which session?**: `M-x ai-code-eca-which-session` or `C-c e ?` shows:
```
ECA Session 1 (ready) for /path/to/project | Workspace: /project, /shared-lib
```

### Keybindings (Alternative)

Direct keybindings available under `C-c e` prefix for power users:

| Key | Command |
|-----|---------|
| `C-c e d` | Session dashboard |
| `C-c e s` | Switch session |
| `C-c e a` | Add workspace folder |
| `C-c e w` | List workspace folders |
| `C-c e f` | Add file context |
| `C-c e v` | Verify health |

In `eca-chat-mode`:

| Key | Command |
|-----|---------|
| `C-c C-f` | Add file context |
| `C-c C-c` | Add cursor context |
| `C-c C-m` | Add repo map |
| `C-c C-y` | Add clipboard |
| `C-c C-a` | Add workspace folder |
| `C-c C-w` | List workspace folders |

### Multi-Project Workspace

ECA supports multiple projects in a single session. Use these workflows:

```elisp
;; Add another project to current session
M-x ai-code-eca-add-workspace-folder RET /path/to/project RET

;; List all workspace folders
M-x ai-code-eca-list-workspace-folders

;; Sync current project roots to workspace
M-x ai-code-eca-sync-project-workspaces

;; Remove a workspace folder
M-x ai-code-eca-remove-workspace-folder RET /path/to/project RET
```

Context added from files includes workspace provenance:

```elisp
;; File context now includes :workspace property
(:type "file" :path "/project/src/file.el"
 :workspace (:workspace "/project" :relative-path "src/file.el" :folder-name "project"))
```

This enables the AI to understand which project each file belongs to when working
across multiple repositories.

### Auto Workspace Detection

When `eca-auto-add-workspace-folder` is enabled (default `t`), opening a file
outside the current session's workspace automatically adds its project root:

```elisp
;; Configure auto-detection behavior
(setq eca-auto-add-workspace-folder t)       ; Auto-add (default)
(setq eca-auto-add-workspace-folder 'prompt) ; Ask before adding
(setq eca-auto-add-workspace-folder nil)     ; Disable
```

This ensures your ECA session always has the right context when working across
multiple projects.

### Auto Session Switching

Enable automatic session switching based on project:

```elisp
;; Auto-switch to session matching current project
(setq eca-auto-switch-session t)       ; Auto-switch (disabled by default)
(setq eca-auto-switch-session 'prompt) ; Ask before switching
(setq eca-auto-switch-session nil)     ; Disabled
```

When enabled, switching to a buffer in a different project automatically
switches to the ECA session that owns that project.

### Cross-Session Context Sharing

Share common files/repo-maps across all sessions:

```elisp
;; Share a file (e.g., shared library docs)
M-x ai-code-eca-share-file RET /path/to/shared/docs.md RET

;; Share a repo map (e.g., shared library)
M-x ai-code-eca-share-repo-map RET /path/to/shared-lib RET

;; Apply all shared context to current session
M-x ai-code-eca-apply-shared-context RET
```

Keybindings: `C-c e F` (share file), `C-c e M` (share repo map), `C-c e p` (apply).

### Session Dashboard

Visual session management with `M-x ai-code-eca-dashboard` or `C-c e d`:

| Key | Action |
|-----|--------|
| `RET` | Switch to session |
| `d` | Delete session |
| `w` | List workspace folders |
| `g` | Refresh |
| `q` | Quit |

Shows session ID, status, workspace folders, and chat count in a table.

---

This fork builds on
[minimal-emacs.d](https://github.com/jamescherti/minimal-emacs.d) by James
Cherti. See the upstream `README.md` for the base Emacs configuration.
