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
in `nucleus-config.el`). These are supplemental — the schema-faithful
`<tool_usage_policy>` block in the main agent prompt is the primary contract.

Only the tools listed in `nucleus--gptel-agent-snippet-tools` are injected
into the agent system prompt (currently: `Bash`, `Edit`, `ApplyPatch`,
`preview_file_change`).

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
| `gptel-plan` | Glob, Grep, Read, WebSearch, WebFetch, YouTube, Agent, Skill, Eval | `plan_agent.md` |
| `gptel-agent` | All 17 core tools + preview/skill helpers | `code_agent.md` |

Tool lists are defined in `nucleus-config.el`:
- `nucleus--gptel-plan-readonly-tools`
- `nucleus--gptel-agent-nucleus-tools`

Tool list construction is deferred to `with-eval-after-load 'gptel-agent-tools`
so all upstream tool structs are registered before the lists are snapshotted.

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
