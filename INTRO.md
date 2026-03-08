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

---

This fork builds on
[minimal-emacs.d](https://github.com/jamescherti/minimal-emacs.d) by James
Cherti. See the upstream `README.md` for the base Emacs configuration.
