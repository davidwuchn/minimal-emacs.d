# minimal-emacs.d + gptel-nucleus

A fork of [jamescherti/minimal-emacs.d](https://github.com/jamescherti/minimal-emacs.d) extended with a full AI agent system built on [gptel](https://github.com/karthink/gptel).

## What this adds

**gptel** provides the LLM chat engine and FSM-based tool execution. **nucleus** layers on top with tool management, agent presets, security ACLs, prompt infrastructure, and payload resilience -- turning Emacs into an agentic coding environment comparable to Cursor or OpenCode, but running entirely inside Emacs.

### Key capabilities

- **Agent & Plan modes** -- two presets with different tool permissions. Agent mode gets full read/write/execute tools; Plan mode is sandboxed to read-only exploration.
- **30+ tools** -- Bash, Glob, Grep, Read, Write, Edit, ApplyPatch, Code_Map, Code_Inspect, Code_Replace, Code_Usages, Diagnostics, Preview, RunAgent, and Emacs introspection tools (describe_symbol, get_symbol_source, find_buffers_and_recent).
- **Subagent delegation** -- RunAgent spawns subordinate agents (explorer, researcher, reviewer, executor) with scoped toolsets and independent conversations.
- **Security ACL** -- hard tool filtering by preset. Plan mode physically cannot call Bash/Edit/Write regardless of what the LLM requests.
- **Tool confirmation UI** -- 3 tiers (auto / normal / confirm-all) with minibuffer dispatch (`y/n/k/a/i/p/q`).
- **Payload management** -- three-layer defense against oversized API payloads: pre-send compaction (byte estimation + 4-pass progressive trimming), retry-time tool result truncation, and aggressive reduction (strip reasoning, filter tools array to only used tools) on repeated failures.
- **Resilience** -- exponential backoff retry, doom-loop detection (identical tool calls x3 = abort), nil/hallucinated tool call sanitization, FSM stuck-state recovery, curl timeout hardening.
- **Thinking model support** -- reasoning_content injection for Moonshot/Kimi, DeepSeek, and other thinking-enabled models across multi-turn tool-calling conversations.
- **Tree-sitter powered code tools** -- structural code map, node extraction, and replacement via tree-sitter AST, with workspace-wide search across 10+ languages.
- **DRY backend config** -- single source of truth in `gptel-config.el`. Change one line to switch all presets, subagents, and tool routing to a different provider/model.

### Architecture

```
lisp/modules/
  gptel-ext-core.el        Core advice/hooks: retry, FSM recovery, streaming,
                           tool sanitization, progressive trimming, pre-send compaction
  gptel-ext-backends.el    Backend definitions (Moonshot, DashScope, DeepSeek, Gemini, etc.)
  gptel-ext-security.el    ACL router advice on gptel-make-tool
  gptel-tools.el           Tool registration orchestrator
  gptel-tools-agent.el     RunAgent + subagent delegation
  gptel-tools-*.el         Individual tool implementations
  nucleus-tools.el         Toolset definitions and filtering
  nucleus-presets.el       Preset management and tool contract validation
  nucleus-prompts.el       Prompt loading from assistant/prompts/
  nucleus-header-line.el     Header-line preset display

assistant/prompts/         System prompts and tool supplemental prompts
tests/test-gptel-trim.el   51 ERT tests for payload trimming and compaction
```

### Multi-backend support

Configured for Moonshot/Kimi (default), DashScope (Qwen), DeepSeek, Gemini, OpenRouter, GitHub Copilot, MiniMax, and Cloudflare Workers AI. Backend/model selection is centralized -- presets and subagents inherit from the global default rather than hardcoding provider-specific values.

---

*This fork builds on [minimal-emacs.d](https://github.com/jamescherti/minimal-emacs.d) by James Cherti. See the [upstream README](https://github.com/jamescherti/minimal-emacs.d#readme) for base Emacs configuration details.*
