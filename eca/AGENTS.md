# ECA AGENTS.md

> ECA (AI Code Assistant) configuration for minimal-emacs.d + gptel-nucleus.

## Architecture

ECA provides:
- Multi-provider support (DashScope, OpenRouter, DeepSeek, Moonshot, Google, etc.)
- Subagent delegation
- Encrypted credential management
- Tool orchestration

## Subagents

Dedicated subagents for specialized tasks:

| Subagent | Purpose | Model | Prompt |
|----------|---------|-------|--------|
| `code` | Primary coding agent | `claude-opus-4.6` | `prompts/code_agent.md` |
| `plan` | Planning/analysis | `gpt-5.4` | `prompts/plan_agent.md` |
| `executor` | Tests, docs, linting | `gpt-5.4-mini` | Inline (grunt work) |
| `reviewer` | Code review (multi-scale) | `gpt-5.4` | `prompts/reviewer_agent.md` |
| `explorer` | Deep codebase analysis | `gpt-5.4` | `prompts/explorer_agent.md` |
| `dangerous` | Full tool access | `gemini-3.1-pro` | Inline (trusted) |

### Subagent Decision Matrix

| Task | Subagent | Why |
|------|----------|-----|
| Code implementation | `code` | Primary agent |
| Planning/analysis | `plan` | Large context, reasoning |
| Fix tests/lint | `executor` | Cheaper, fast |
| Review PR | `reviewer` | Context isolation |
| Explore codebase | `explorer` | Multi-file synthesis |
| Dangerous ops | `dangerous` | Full tool access |

## Prompts

Located in `prompts/`:

| Prompt | Purpose |
|--------|---------|
| `code_agent.md` | Primary coding agent |
| `plan_agent.md` | Planning agent |
| `reviewer_agent.md` | Code review protocol |
| `explorer_agent.md` | Codebase exploration |
| `title.md` | Chat title generation |
| `compact.md` | Context compaction |
| `init.md` | Session initialization |

## Keybindings

| Key | Command | Description |
|-----|---------|-------------|
| `C-c e` | `eca-prefix` | ECA command prefix |
| `C-c e c` | `eca-chat` | Open chat |
| `C-c e s` | `eca-server` | Start server |
| `C-c e ?` | `ai-code-eca-which-session` | Show current session |

## Custom Tools

Defined in `config.json`:

| Tool | Purpose |
|------|---------|
| `clj-paren-repair` | Fix delimiter errors, format Clojure |
| `clj-nrepl-eval` | Evaluate Clojure in runtime REPL |

## Hooks

Pre-request hooks in `hooks/`:

| Hook | Type | Purpose |
|------|------|---------|
| `nucleus-behaviors.sh` | preRequest | Inject nucleus behaviors |

## Security

See `README.md` for security architecture:
- Encrypted storage in `~/.authinfo.gpg`
- Zero-footprint decryption via `eca-secure` wrapper
- RAM-backed temp files with `shred` on exit

## Configuration

Single source of truth: `config.json`

### Default Models

| Use Case | Model |
|----------|-------|
| Chat | `claude-sonnet-4.6` |
| Code agent | `claude-opus-4.6` |
| Plan agent | `gpt-5.4` |
| Rewrite | `gpt-5.4` |
| Completion | `gpt-5.4-mini` |

### Providers

| Provider | Models |
|----------|--------|
| `dashscope` | qwen3.5-plus, kimi-k2.5, glm-5, deepseek-v3.2 |
| `openrouter` | claude-sonnet-4.6, gpt-5.4 |
| `deepseek` | deepseek-v4-flash, deepseek-v4-pro |
| `moonshot` | kimi-k2.5, kimi-for-coding |
| `google` | gemini-3.1-pro-preview |
| `minimax` | minimax-m2.7-highspeed, minimax-m2.7 |
| `z-ai` | glm-4.7, glm-5 |
