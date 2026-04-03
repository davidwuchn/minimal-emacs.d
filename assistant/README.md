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
| **Diagnostics** | Project diagnostics | LSP → CLI linter fallback |

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
│ Verify changes                │ Diagnostics                  │
│ Read arbitrary text file      │ Read                        │
│ Search text pattern           │ Grep                        │
│ Find files by name            │ Glob                        │
│ Create new file               │ Write                       │
│ Edit non-function text        │ Edit                        │
└─────────────────────────────────────────────────────────────┘
```

## Programmatic Tool

`Programmatic` is a restricted orchestration tool for collapsing several small,
tightly-coupled tool calls into one turn. Instead of asking the model to emit a
`Grep` call, wait, emit a `Read` call, wait, and so on, the model can write a
small restricted Emacs Lisp program that runs those steps inside one tool use.

### What It Is For

- Reducing tool round trips for search -> read -> summarize workflows
- Returning one final structured result instead of several intermediate tool results
- Reusing existing ACL, timeout, confirmation, and preview behavior

### What It Is Not For

- Arbitrary Elisp evaluation
- Nested `Bash` or raw process/network access
- Replacing `RunAgent` for broad exploratory work
- Bypassing confirmation for mutating tools

### Current Safe Subset

Supported forms in the restricted sandbox include:

- `setq`, `result`, top-level `tool-call`
- `if`, `when`, `unless`, `not`, `and`, `or`, `progn`, `let`, `let*`
- collection helpers `mapcar` and `filter`
- small data helpers such as `plist-get`, `alist-get`, `assoc`, `cons`

The current sandbox is still expression-oriented: it supports simple collection
transforms, but not open-ended loops like `while`.

That keeps common transform/filter cases ergonomic without opening the door to
general looping semantics in v1.

Results can be returned as strings or structured values; structured values are
pretty-printed before returning to the model.

### Tool Access and Limits

- Exposed in both the `:nucleus` toolset and the readonly plan toolset
- `gptel-plan` gets a readonly capability profile; `gptel-agent` gets the full agent profile
- Default timeout: 15 seconds
- Default max nested tool calls: 25
- Final result size is truncated when it exceeds the configured limit
- Nested tool recursion back into `Programmatic` is rejected

### Nested Mutating Tools

`Programmatic` is read-mostly by default, but preview-backed patch tools are
allowed for controlled mutating flows in agent mode:

- `Edit`
- `ApplyPatch`
- `Code_Replace`

These still go through the normal confirmation UI. Nested Programmatic confirms
reuse the regular minibuffer / overlay tool approval flow, and the underlying
mutating tool keeps its own preview/apply path.

When a Programmatic run includes multiple mutating steps, the agent now gets an
aggregate preview/approval step first, summarizing the whole mutating plan
before individual tool confirmations run.

In `gptel-plan`, `Programmatic` is readonly-only and may call only readonly
nested tools such as `Read`, `Grep`, `Glob`, `Code_Map`, `Code_Inspect`,
`Code_Usages`, `Diagnostics`, and introspection helpers.

### When to Prefer Programmatic

Use `Programmatic` when all of the following are true:

- the task needs 3+ tightly-coupled tool calls
- the intermediate tool results do not need separate model turns
- the work is orchestration rather than open-ended delegation

Prefer direct tools for one-off actions, and prefer `RunAgent` when the task is
wide-scope exploration or research.

In plan mode, prefer readonly `Programmatic` when the planning task needs 3+
small readonly tool calls but should still remain in a single read-only turn.

### Example

```elisp
(setq hits (tool-call "Grep" :regex "Programmatic" :path "lisp/modules"))
(setq snippet (tool-call "Read" :file_path "lisp/modules/gptel-sandbox.el" :start_line 1 :end_line 40))
(result (list :hits hits :snippet snippet))
```

### Benchmarking

A small local benchmark harness compares ordinary multi-tool chaining against
single `Programmatic` orchestration runs for two representative workflows:

- read-only `Grep -> Read -> Read -> summarize`
- mutating preview-backed `Read -> Edit(diff)`

Run it with:

```bash
scripts/benchmark-programmatic.sh
scripts/benchmark-programmatic.sh 500
```

The benchmark reports:

- local execution time
- simulated end-to-end time with per-turn model latency
- tool round-trip count
- transcript byte reduction
- separate read-only and mutating preview-backed workflow results

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
message from `init_AGENTS.md` + the project's `AGENTS.md`.

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
| `diagnostics.md` | Diagnostics | LSP diagnostics + linter fallback |

#### Deprecated Tool Prompts
| File | Tool | Description | Status |
|------|------|-------------|--------|
| ~~`lsp_hover.md`~~ | ~~lsp_hover~~ | ~~Type info at cursor~~ | ❌ Removed from nucleus-tool-prompt-files |
| ~~`lsp_rename.md`~~ | ~~lsp_rename~~ | ~~Cross-file symbol rename~~ | ❌ Removed from nucleus-tool-prompt-files |
| ~~`lsp_diagnostics.md`~~ | ~~lsp_diagnostics~~ | ~~LSP errors~~ | ❌ Replaced by Diagnostics |
| ~~`lsp_references.md`~~ | ~~lsp_references~~ | ~~Find references~~ | ❌ Replaced by Code_Usages |
| ~~`lsp_definition.md`~~ | ~~lsp_definition~~ | ~~Go to definition~~ | ❌ Replaced by Code_Inspect |
| ~~`lsp_workspace_symbol.md`~~ | ~~lsp_workspace_symbol~~ | ~~Workspace search~~ | ❌ Replaced by Code_Inspect |

**Note:** LSP tools have been removed from `nucleus-tool-prompt-files`. Use Code_* tools instead.

#### Standard Tool Prompts
| File | Tool | Description |
|------|------|-------------|
| `agent.md` | Agent | Delegate to subagent |
| `apply_patch.md` | ApplyPatch | Apply unified diff patch |
| `bash_command.md` | Bash | Execute shell commands (sandboxed in Plan mode) |
| `edit_file.md` | Edit | Edit file with exact string match |
| `glob.md` | Glob | Find files by pattern |
| `grep.md` | Grep | Search file contents |
| `read_file.md` | Read | Read file contents |
| `write_file.md` | Write | Create new file |
| `diagnostics.md` | Diagnostics | Project-wide diagnostics (renamed from Code_Check) |
| `run_agent.md` | RunAgent | Run subagent by name |
| `skill.md` | Skill | Load skill package |
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
| `gptel-plan` | Read-only: Glob, Grep, Read, WebSearch, WebFetch, YouTube, Agent, Skill, Eval, find_buffers, describe_symbol, get_symbol_source, **Code_Map, Code_Inspect, Code_Usages, Diagnostics** | `plan_agent.md` |
| `gptel-agent` | Full toolset (25+ tools): Core tools + Preview/Skill helpers + Mutators, **Programmatic, Code_Map, Code_Inspect, Code_Replace, Code_Usages, Diagnostics, Bash, RunAgent** | `code_agent.md` |

Tool lists are strictly defined in `lisp/modules/nucleus-tools.el`:
- `(:readonly . (...))`
- `(:nucleus . (...))`
- `(:core . (...))`

## Models & Routing

Model is configured in YAML frontmatter (single source of truth). Edit `assistant/agents/*.md` to change models:

| Role | Model | YAML File |
|------|-------|-----------|
| **Plan Agent** | `minimax-m2.5` | `plan_agent.md` |
| **Action Agent** | `minimax-m2.5` | `code_agent.md` |
| **Subagents** | per-agent | `executor.md`, `researcher.md`, etc. |

*Note: Subagents spawned via `RunAgent` or `Agent` are entirely stateless. Network requests still benefit from `my/gptel-auto-retry`, and the RunAgent loop itself retries transient subagent failures with a fixed short delay.*

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
- **`Preview`** — Unified async preview tool. Two modes: (1) file change
  (`path` + `replacement`) generates and shows unified diff; (2) patch mode
  (`patch` param) shows raw unified diff. Both display in `diff-mode` with
  minibuffer confirmation: `y` apply, `n` abort, `!` apply all, `q` quit.
- **`ApplyPatch`** — Shows `*gptel-patch-preview*` in `diff-mode` and prompts
  in minibuffer before running `git apply`. Gated by
  `gptel-tools-preview-enabled` (default `t`); set to `nil` to auto-apply.
- **Confirmation options**:
  - `y` — Yes, apply this change
  - `n` — No, abort this change
  - `!` — Apply all (auto-apply rest of session)
  - `q` — Quit (same as n)
  - `M-x gptel-tools-preview-reset-confirmation` — Re-enable confirmations

### Infrastructure
- **Auto-compaction** — Buffers are summarized via `compact.md` when they
  approach the model's context window.
- **Prompt marker** — `### ` is inserted after each response for easy cursor
  placement.
- **C-g abort** — Remapped to `my/gptel-keyboard-quit`, which kills all
  gptel-managed processes before quitting.
- **C-c C-k** — Abort active request (same as C-g).
- **C-c C-p** — Add project files to context.
- **C-c C-.** — Permit and run tool (remember for session).
- **C-c C-x** — Toggle tool profile (readonly/nucleus).
- **M-x my/gptel-emergency-stop** — Emergency stop: abort all requests, clear
  permits, switch to confirm-all mode.
- **M-x my/gptel-health-check** — Show tool system status: mode, permits,
  preset, registered tools, active processes.
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

### Our Diagnostics vs Upstream Diagnostics

Both tools collect diagnostics, but with different scopes:

| Tool | Source | Scope | Fallback | Recommendation |
|------|--------|-------|----------|----------------|
| **Diagnostics** | `gptel-tools-code.el` | **Entire project** | LSP → CLI linters | ✅ **USE THIS** |
| `Diagnostics` | `gptel-agent-tools.el` (upstream) | Open buffers only | None (flymake only) | ⚠️ Only for quick open-file checks |

**Why Diagnostics is better:**
1. Scans entire project, not just open buffers
2. Has CLI linter fallback when LSP unavailable
3. Provides clearer messaging about LSP status
4. Auto-detects project type (Python/JS/Rust)

The upstream `Diagnostics` tool from gptel-agent-tools.el (open-buffers-only) is **not registered** in our nucleus toolsets. The LLM will primarily see and use our `Diagnostics` tool (project-wide + CLI fallback).
