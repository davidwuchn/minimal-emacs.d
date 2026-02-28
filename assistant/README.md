# assistant/

AI assistant configuration for gptel — prompts, agents, skills, and tool policies.

## Directory Layout

```
assistant/
├── agents/          # gptel-agent agent definitions (.md)
├── prompts/         # System prompts loaded by nucleus-config
│   └── tools/       # Per-tool supplemental prompt snippets
└── skills/          # Loadable skill packages
```

## How It Works

`nucleus-config.el` is the loader. On startup it:

1. Scans `assistant/agents/` and registers them with `gptel-agent`.
2. Lazily reads `assistant/prompts/` into `nucleus-prompts` (keyed by symbol) on first use.
3. Lazily reads `assistant/prompts/tools/` into `nucleus-tool-prompts` on first use.
4. Overrides the upstream `gptel-agent` / `gptel-plan` presets with nucleus
   system prompts and the correct tool lists.

`gptel-config.el` wires everything into gptel: backends, tool overrides
(async Bash/Grep/Glob/Edit), FSM hardening, preview gates, auto-compaction,
doom-loop detection, and keybindings. See the table of contents at the top of
that file for a section map.

## Code_* Tools (Structural Editing)

The unified `Code_*` toolset provides KISS (Keep It Simple, Stupid) code intelligence and structural editing:

| Tool | Purpose | Key Feature |
|------|---------|-------------|
| **Code_Map** | File structure/outline | First tool for unfamiliar files |
| **Code_Inspect** | Extract function/class | Auto-searches project if file unknown |
| **Code_Replace** | Structural replacement | **REQUIRED** for .el/.clj/.py/.rs/.js |
| **Code_Usages** | Find all references | LSP → ripgrep fallback |
| **Code_Check** | Project diagnostics | LSP → CLI linter fallback |

**See [docs/CODE_TOOLS.md](../docs/CODE_TOOLS.md) for comprehensive documentation.**

### When to Use Code_* vs Standard Tools

```
┌─────────────────────────────────────────────────────────────┐
│ Task                          │ Use This                    │
├─────────────────────────────────────────────────────────────┤
│ Read file structure           │ Code_Map                    │
│ Read specific function        │ Code_Inspect                │
│ Modify function (Lisp/Py/Rust)│ Code_Replace (NOT Edit!)    │
│ Find where function is used   │ Code_Usages                 │
│ Verify changes                │ Code_Check                  │
│ Read arbitrary text file      │ Read                        │
│ Search text pattern           │ Grep                        │
│ Find files by name            │ Glob                        │
│ Create new file               │ Write                       │
│ Edit non-function text        │ Edit                        │
└─────────────────────────────────────────────────────────────┘
```

## Prompts (`assistant/prompts/`)

| File | Directive key | Purpose |
|------|---------------|---------|
| `code_agent.md` | `nucleus-gptel-agent` / `Agent` | Full agentic coding system prompt |
| `plan_agent.md` | `nucleus-gptel-plan` / `Plan` | Read-only planning system prompt |
| `explorer_agent.md` | `explorer` | Deep codebase exploration subagent |
| `init.md` | `init` | Bootstrap context injected into `default` directive |
| `init_AGENTS.md` | _(inlined by init)_ | Repo-level AGENTS.md template |
| `compact.md` | `compact` | Auto-compaction summary prompt |
| `inline_completion.md` | `completion` | Inline code completion |
| `rewrite.md` | `rewrite` | Targeted rewrite assistant |
| `skill_create.md` | `skillCreate` | Skill authoring assistant |
| `title.md` | `chatTitle` | Chat title generation |

`init.md` uses a `nucleus: <file>` directive to compose the default system
message from `init_AGENTS.md` + the project's `AGENTS.md` + `MEMENTUM.md`.

### Tool Prompts (`assistant/prompts/tools/`)

One `.md` file per tool, keyed by tool name (see `nucleus-tool-prompt-files`
in `nucleus-prompts.el`). These are supplemental — the schema-faithful
`<tool_usage_policy>` block in the main agent prompt is the primary contract.

#### Code_* Tool Prompts (Primary Interface)
| File | Tool | Description |
|------|------|-------------|
| `code_map.md` | Code_Map | File structure/outline |
| `code_inspect.md` | Code_Inspect | Extract function/class by name |
| `code_replace.md` | Code_Replace | AST structural replacement |
| `code_usages.md` | Code_Usages | Find all symbol references |
| `code_check.md` | Code_Check | LSP diagnostics + linter fallback |

#### LSP Tool Prompts (Specialized)
| File | Tool | Description | Status |
|------|------|-------------|--------|
| `lsp_hover.md` | lsp_hover | Type info at cursor | ✅ Keep - Quick type lookup |
| `lsp_rename.md` | lsp_rename | Cross-file symbol rename | ✅ Keep - LSP rename provider |
| ~~`lsp_diagnostics.md`~~ | ~~lsp_diagnostics~~ | ~~LSP errors~~ | ❌ Replaced by Code_Check |
| ~~`lsp_references.md`~~ | ~~lsp_references~~ | ~~Find references~~ | ❌ Replaced by Code_Usages |
| ~~`lsp_definition.md`~~ | ~~lsp_definition~~ | ~~Go to definition~~ | ❌ Replaced by Code_Inspect |
| ~~`lsp_workspace_symbol.md`~~ | ~~lsp_workspace_symbol~~ | ~~Workspace search~~ | ❌ Replaced by Code_Inspect |

#### Standard Tool Prompts
| File | Tool | Description |
|------|------|-------------|
| `agent.md` | Agent | Delegate to subagent |
| `apply_patch.md` | ApplyPatch | Apply unified diff patch |
| `ast_*.md` | AST_* | Legacy AST tools (deprecated by Code_*) |
| `bash_command.md` | Bash/BashRO | Execute shell commands |
| `edit_file.md` | Edit | Edit file with exact string match |
| `glob.md` | Glob | Find files by pattern |
| `grep.md` | Grep | Search file contents |
| `read_file.md` | Read | Read file contents |
| `write_file.md` | Write | Create new file |
| ... | ... | See `assistant/prompts/tools/` for full list |

Only the tools listed in `(:snippets ...)` within `nucleus-tools.el` are injected
into the agent system prompt (currently includes `Bash`, `Edit`, `LSP` mutators, etc.).

## Agents (`assistant/agents/`)

gptel-agent `.md` definitions. Loaded via `gptel-agent-update` after
`assistant/agents/` is added to `gptel-agent-dirs`.

| File | Role |
|------|------|
| `gptel-agent.md` | Action agent (full toolset) |
| `gptel-plan.md` | Planning agent (read-only tools) |
| `executor.md` | Delegated executor subagent |
| `researcher.md` | Web/codebase research subagent |
| `introspector.md` | Emacs introspection subagent |
| `explorer_agent.md` | Deep codebase exploration via `RunAgent` |

Nucleus patches `executor`, `researcher`, and `introspector` after load to
inject compact `<tool_usage_policy>` blocks (see `nucleus--override-gptel-agent-presets`).

## Skills (`assistant/skills/`)

Self-contained skill packages. Each subdirectory contains a `SKILL.md` that
is loaded on demand via the `Skill` tool or `load_skill`.

```
skills/<name>/
└── SKILL.md    # Instructions + any bundled resources
```

See `SKILL_TEMPLATE.md` for the canonical structure.

## Presets and Tool Lists

Two presets, toggled with `nucleus-agent-toggle` (`M-x nucleus-agent-toggle` or the `[Plan]`/`[Agent]` header-line button):

| Preset | Tools | System prompt |
|--------|-------|---------------|
| `gptel-plan` | Read-only subset: Glob, Grep, Read, LSP (Hover, Definition, Refs, Diags, Workspace), WebSearch, WebFetch, YouTube, Agent, Skill, Eval, find_buffers, **Code_Map, Code_Inspect, Code_Usages, Code_Check** | `plan_agent.md` |
| `gptel-agent` | Full toolset (29 tools): Core tools + LSP mutators (Rename) + Preview/Skill helpers, **Code_Map, Code_Inspect, Code_Replace, Code_Usages, Code_Check** | `code_agent.md` |

Tool lists are strictly defined in `lisp/modules/nucleus-tools.el`:
- `(:readonly . (...))`
- `(:nucleus . (...))`
- `(:core . (...))`

## Models & Routing

Nucleus implements task-specific model routing to optimize cost and capability (configured via `nucleus-presets.el` and `gptel-tools-agent.el`):

| Role | Default Model | Reasoning |
|------|---------------|-----------|
| **Global Fallback** | `qwen3.5-plus` | Solid generalist via `dashscope` |
| **Plan Agent** | `qwen3.5-plus` | Fast, logic-heavy planning and reasoning |
| **Action Agent** | `glm-5` | High capability for complex coding and refactoring |
| **Subagents** | `kimi-k2.5` | Fast, deep-context model via `moonshot` for heavy codebase reading |

*Note: Subagents spawned via `RunAgent` or `Agent` are entirely stateless and use exponential backoff (`my/gptel-auto-retry`) for stability.*

## Key Customizations in `gptel-config.el`

### Tool execution
- **Async tool overrides** — Bash, Grep, Glob, Edit are replaced with async
  implementations that respect abort signals and enforce per-tool timeouts
  (all under `my/gptel-interrupt` customization group).
- **Write safety** — `Write` refuses to overwrite existing files; use `Edit`
  or `Insert` instead.
- **Duplicate tool guard** — Deduplicates `gptel-tools` before serialization
  to prevent 400 errors from the API.

### FSM hardening
- **Nil-tool guard** — Strips nil/null-named tool calls from both the `:tool-use`
  call-spec list and the stored assistant message, preventing 400 errors and
  FSM hangs when the model emits phantom tool calls.
- **Doom-loop detection** — Mirrors OpenCode's `DOOM_LOOP_THRESHOLD=3`: aborts
  the turn when the same tool is called with identical arguments 3 consecutive
  times (`my/gptel-doom-loop-threshold`, customizable).
- **Empty tool-use guard** — When all tool calls are pruned as malformed, forces
  the FSM to `DONE` instead of hanging in `TOOL` state forever.
- **Reasoning content** — Moonshot/Kimi `reasoning_content` is preserved across
  tool-call turns so the API never receives messages without the required field.

### Preview & patch
- **`preview_file_change`** — Async step-through preview using `magit-diff-paths`
  (falls back to `diff-mode`). Multiple files queue up and are shown one at a
  time; `n` advances, `q` aborts remaining. The FSM waits for each `n`/`q`
  before the agent can proceed.
- **`preview_patch`** — Async inspect-only patch preview (`n` = reviewed,
  not applied; `q` = abort).
- **`ApplyPatch`** — Shows `*gptel-patch-preview*` in `diff-mode` and waits for
  `n` (apply) or `q` (abort) before running `git apply`. Gated by
  `my/gptel-applypatch-auto-preview` (default `t`); set to `nil` for headless use.

### Infrastructure
- **Auto-compaction** — Buffers are summarized via `compact.md` when they
  approach the model's context window.
- **Prompt marker** — `### ` is inserted after each response for easy cursor
  placement.
- **C-g abort** — Remapped to `my/gptel-keyboard-quit`, which kills all
  gptel-managed processes before quitting.
- **Context window cache** — OpenRouter model context windows are fetched
  asynchronously and cached to disk; refreshed in the background at most once
  per `my/gptel-context-window-auto-refresh-interval-days` days.

## OpenCode Source Reference

When in doubt about how a feature works, consult the OpenCode source as the
authoritative reference (also documented in `AGENTS.md`):

```bash
# List files
gh api 'repos/anomalyco/opencode/git/trees/dev?recursive=1' --jq '.tree[] | .path'
# Read a file
gh api 'repos/anomalyco/opencode/contents/PATH?ref=dev' --jq '.content' | base64 -d
```

## Adding a New Agent Prompt

1. Add a `.md` file under `assistant/prompts/`.
2. Register it in `nucleus-prompt-files` in `nucleus-config.el`.
3. If it should appear in the interactive picker, ensure it is **not** in the
   `seq-remove` exclusion list inside `nucleus-gptel-directives`.

## Adding a New Skill

```
mkdir assistant/skills/<name>
# Write assistant/skills/<name>/SKILL.md
```

The skill is immediately available via the `Skill` tool without restarting Emacs.

## Adding a New Code_* Tool

1. Implement the tool function in `lisp/modules/gptel-tools-code.el`
2. Register with `gptel-make-tool` in `gptel-tools-code-register()`
3. Add to `nucleus-toolsets` in `lisp/modules/nucleus-tools.el`
4. Create prompt doc in `assistant/prompts/tools/code_*.md`
5. Update this README and `docs/CODE_TOOLS.md`

## Tool Conflicts & Resolutions

### Diagnostics vs Code_Check

Both tools collect diagnostics, but with different scopes:

| Tool | Source | Scope | Fallback | Recommendation |
|------|--------|-------|----------|----------------|
| **Code_Check** | `gptel-tools-code.el` | **Entire project** | LSP → CLI linters | ✅ **USE THIS** |
| `Diagnostics` | `gptel-agent-tools.el` (upstream) | Open buffers only | None (flymake only) | ⚠️ Only for quick open-file checks |

**Why Code_Check is better:**
1. Scans entire project, not just open buffers
2. Has CLI linter fallback when LSP unavailable
3. Provides clearer messaging about LSP status
4. Auto-detects project type (Python/JS/Rust)

The `Diagnostics` tool is still available from upstream but is **not registered** in our nucleus toolsets. The LLM will primarily see and use `Code_Check`.
