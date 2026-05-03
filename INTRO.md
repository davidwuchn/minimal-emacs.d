# minimal-emacs.d + gptel-nucleus

A fork of [jamescherti/minimal-emacs.d](https://github.com/jamescherti/minimal-emacs.d)
extended with a full AI agent system built on
[gptel](https://github.com/karthink/gptel).

## Project Status

| Metric | Value |
|--------|-------|
| **Code fixes** | 242+ real fixes merged |
| **New features** | Auto-workflow, benchmark, retry loop, researcher, sandbox, strategic planner |
| **Agents** | 10+ (MiniMax workhorse, DashScope/moonshot/DeepSeek/CF-Gateway fallbacks) |
| **Cron jobs** | 6 scheduled jobs (auto-workflow, research, mementum, instincts) |

### Latest Features (2026-05-03)

| Feature | Purpose |
|---------|---------|
| **Auto-Workflow** | Headless experiments with grading, review, and staging merge |
| **Strategy Evolution** | Meta-Harness style harness search: agent-driven proposer, Pareto frontier, held-out test sets, stateful lifecycle |
| **Backend Fallback** | MiniMax → DashScope → moonshot → DeepSeek → CF-Gateway |
| **Benchmark System** | Score tracking, quality metrics, evolution patterns |
| **Shell Timeout Sentinel** | Wait for process exit before capturing results |
| **FSM Registry Validation** | Bidirectional consistency checks |
| **Review Retry Loop** | Executor fixes issues, reviewer validates, max 2 retries |
| **Periodic Researcher** | Every 4h, finds anti-patterns for target selection |
| **Sandbox Execution** | Safe code evaluation with nil guards and error handling |
| **Strategic Planner** | Long-term improvement planning with hypothesis tracking |

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

This fork tracks its core AI packages from Git submodules under `packages/`
instead of relying only on ELPA snapshots:

```bash
./scripts/setup-packages.sh           # Install if missing
./scripts/setup-packages.sh --update  # Sync submodules to tracked remote heads
./scripts/setup-packages.sh --force   # Reinstall
./scripts/check-submodule-sync.sh     # Verify gitlinks match tracked remote heads
```

Git hooks and CI now fail if a committed submodule gitlink is either missing on
its configured remote or behind the branch head declared in `.gitmodules`.

Key paths:
- `packages/` - Git-tracked package checkouts managed by `setup-packages.sh`
- `var/elpa/` - `package.el` state, archives, and bootstrap cache

Important Git-tracked packages:
- `gptel` - Chat engine and FSM-based tool execution
- `gptel-agent` - Subagent delegation and tool orchestration
- `ai-code`, `ai-behaviors`, `mementum`, `nucleus`

**Why Git-tracked packages?** ELPA's `gptel-0.9.9.4` is missing functions
required by `gptel-agent` (e.g., `gptel--handle-pre-tool`). The tracked Git
heads include these fixes.

## Model Configuration

Model is configured in YAML frontmatter (single source of truth):

| Use Case | Model | YAML File |
|----------|-------|-----------|
| **Plan preset** | `minimax-m2.7-highspeed` | `assistant/agents/plan_agent.md` |
| **Agent preset** | `minimax-m2.7-highspeed` | `assistant/agents/code_agent.md` |
| **Subagents** | per-agent YAML | `assistant/agents/*.md` |

### Backend Fallback Chain

Auto-workflow uses MiniMax as the primary workhorse with automatic provider failover:

1. **MiniMax** — `minimax-m2.7-highspeed` (primary)
2. **DashScope** — `qwen3.6-plus`
3. **moonshot** — `kimi-k2.6`
4. **DeepSeek** — `deepseek-v4-pro`
5. **CF-Gateway** — `@cf/moonshotai/kimi-k2.6`

Requires `api.minimaxi.com` API key in auth-source. All alternate backends require their respective API keys configured in auth-source.

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

### AI Code Behaviors

This fork includes [ai-code](https://github.com/davidwuchn/ai-code-interface.el)
with [ai-behaviors](https://github.com/xificurC/ai-behaviors) integration:

- **ai-code** - Unified interface for AI coding assistants (Claude Code, Gemini, Copilot, etc.)
- **ai-behaviors** - Structured prompting framework with 40+ predefined behaviors

Behaviors are loaded from the `packages/ai-behaviors` submodule. Use them in prompts:

```
#=code Fix the auth bug          # Production code mode
#=debug Why is this failing      # Systematic debugging
#=review This function           # Code review mode
#=deep Thorough analysis         # Deep thinking mode
```

Setup automatically handled by `./scripts/setup-packages.sh`.

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
- **Auto-workflow** - phased autonomous agent for optimization experiments
  with auto-evolution via 相生/相克. See [docs/auto-workflow.md](docs/auto-workflow.md).

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

Configured for MiniMax (default), Moonshot/Kimi, DashScope/Qwen, DeepSeek,
Gemini, OpenRouter, GitHub Copilot, and Cloudflare Workers AI. Backend/model
selection is centralized so presets and subagents inherit the active default
instead of hardcoding provider-specific values.

## Auto-Workflow

Phased autonomous agent for optimization experiments with auto-evolution.

### Pipeline

```
worktree → analyzer → executor → grader → benchmark → code-quality → decide
```

Decision logic: **70% grader + 30% code quality**

### Features

| Feature | Purpose |
|---------|---------|
| **Code Quality** | Docstring coverage scoring (0.0-1.0) |
| **LLM Degradation** | Detect off-topic, apologies, AI self-reference |
| **Dynamic Stop** | Stop after N consecutive no-improvements |
| **TSV Logging** | Explainable results with code_quality column |
| **Pre-Merge Review** | Reviewer checks for blockers before staging merge |
| **Periodic Researcher** | Every 4h, finds anti-patterns for target selection |
| **Review Retry Loop** | Executor fixes issues, max 2 retries |
| **Strategy Evolution** | Meta-Harness harness search: agent-driven proposal, Pareto frontier, anti-overfitting |

### Strategy Evolution (Meta-Harness)

The auto-workflow system searches over **prompt-building strategies** (how prompts are constructed), not just prompt content. Based on the Stanford IRIS Lab [Meta-Harness](https://github.com/stanford-iris-lab/meta-harness) framework:

```
Proposer (gptel) → 3 candidates → Validate → Prototype → Evolve → Frontier
     ↑                                                              ↓
     └───────────── Warm-start from failure analysis ───────────────┘
```

| Component | Purpose |
|-----------|---------|
| **Agent-driven proposer** | Generates 3 novel strategy candidates per evolution iteration |
| **Pareto frontier** | Tracks non-dominated strategies by success rate and avg score |
| **Held-out test set** | 20% of targets held out during evolution to prevent overfitting |
| **Anti-overfitting rules** | Explicit: no target-specific hints, no file names in strategy code |
| **Anti-parameter-tuning** | Self-critique rejects constant-only changes |
| **Stateful interface** | `analyze-results`, `get-state`, `set-state` for learning strategies |
| **Run isolation** | `--run-name`, `--fresh`, per-run evolution summaries |
| **Evolution summary** | `evolution_summary.jsonl` tracking per-iteration results |
| **Strategy discovery** | Auto-discovers strategies from `assistant/strategies/prompt-builders/*.el` |
| **Signal handling** | Graceful `quit` handling preserves state on interrupt |

Exploitation axes: A=Template architecture, B=Context retrieval, C=Section ordering, D=Variable computation, E=Skill loading, F=Adaptive compression.

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    AUTO-WORKFLOW SYSTEM                      │
├─────────────────────────────────────────────────────────────┤
│  Researcher (moonshot) ──→ Analyzer (MiniMax) ──→ Executor │
│        ↓                        ↓                    ↓      │
│  Findings Cache          Target Selection        Code Fixes │
│                                                      ↓      │
│                                               Reviewer       │
│                                              (moonshot)      │
│                                                   ↓          │
│                                              Staging         │
│                                                ↓             │
│                                              Main            │
└─────────────────────────────────────────────────────────────┘
```

### Agent Distribution

| Agent | Backend | Purpose |
|-------|---------|---------|
| analyzer | MiniMax | Target selection |
| comparator | MiniMax | Before/after comparison |
| executor | MiniMax | Code changes |
| explorer | MiniMax | Code exploration |
| grader | MiniMax | Quality scoring |
| introspector | MiniMax | Self-analysis |
| nucleus-gptel-agent | MiniMax | Main agent |
| nucleus-gptel-plan | MiniMax | Planning |
| researcher | moonshot | Code research, anti-pattern detection |
| reviewer | moonshot | Pre-merge code review |

### Cron Schedule

| Job | Schedule | Machine |
|-----|----------|---------|
| Auto-workflow | 10AM, 2PM, 6PM | macOS |
| Researcher | Every 4 hours | macOS + Pi5 |
| Weekly mementum | Sunday 4AM | macOS + Pi5 |
| Weekly instincts | Sunday 5AM | macOS + Pi5 |

Install: `./scripts/install-cron.sh`

Cron runs through `./scripts/run-auto-workflow-cron.sh`, which uses a dedicated `copilot-auto-workflow` Emacs daemon and writes a fast status snapshot to `var/tmp/cron/auto-workflow-status.sexp`.

### Usage

```
#=frame #file var/tmp/experiments/{run-id}/{target}/frame.md
#=research #ground #file
#=design #subtract #file
#=code #checklist
#=review #file
#=review #meta #file
```

### Parallel Overnight (via RunAgent)

```
RunAgent("code", "optimize gptel-ext-retry.el following docs/auto-workflow.md")
RunAgent("code", "optimize gptel-ext-context.el following docs/auto-workflow.md")
```

### Key Commands

```elisp
;; Workflow
(gptel-auto-workflow-run-async)        ; Start workflow
(gptel-auto-workflow-status)           ; Check status
(gptel-auto-workflow-log)              ; Get clean log

;; Researcher
(gptel-auto-workflow-run-research)     ; Run researcher now
(gptel-auto-workflow-research-status)  ; Researcher status
```

```bash
# Cron-style manual run
./scripts/run-auto-workflow-cron.sh auto-workflow

# Fast snapshot-based status + recent output
./scripts/run-auto-workflow-cron.sh status
./scripts/run-auto-workflow-cron.sh messages
```

### Config Options

```elisp
gptel-auto-workflow-require-review        ; default t
gptel-auto-workflow-research-targets      ; default nil
gptel-auto-workflow-research-before-fix   ; default nil
gptel-auto-workflow--review-max-retries   ; default 2
gptel-auto-workflow-research-interval     ; default 14400 (4h)
gptel-auto-workflow-max-targets-per-run   ; default 5
```

### Phases

| Phase | Trigger | Purpose |
|-------|---------|---------|
| **Frame** | `#=frame #file` | Define target, goal, constraints |
| **Research** | `#=research #ground #file` | Understand, benchmark baseline |
| **Design** | `#=design #subtract #file` | Propose minimal approach |
| **Execute** | `#=code #checklist` | Implement in worktree, validate |
| **Review** | `#=review #file` | Summary, recommendation |
| **Learn** | `#=review #meta #file` | Auto-evolve via 相生/相克 |

### Safety

- Git worktree isolation per experiment
- Test gate: `./scripts/verify-nucleus.sh` must pass
- Benchmark validation required
- Token/time budget enforcement
- **Main NEVER touched** - all changes wait in staging
- Pre-merge review catches blockers/critical issues

See [docs/auto-workflow.md](docs/auto-workflow.md) for full specification.

## ECA + ai-code Integration

[ECA](https://github.com/editor-code-assistant/eca-emacs) is configured as a backend for [ai-code](https://github.com/tninja/ai-code).

### Setup

```bash
# Create symlinks
./scripts/setup-eca-links.sh

# Or manually:
mkdir -p ~/.config ~/bin
ln -sfn ~/.emacs.d/eca ~/.config/eca
ln -sfn ~/.emacs.d/eca/eca-secure ~/bin/eca
```

### Configuration

| File | Purpose |
|------|---------|
| `eca/config.json` | Provider configuration |
| `eca/eca-secure` | Secure wrapper script |
| `eca/prompts/` | Custom prompts |
| `eca/.behaviors/` | Behavior configurations |

### Usage

```elisp
M-x ai-code-menu          ; Main menu (C-c a)
M-x ai-code-set-backend   ; Switch to 'eca
```

See `eca/README.md` and `eca/AGENTS.md` for details.

---

This fork builds on
[minimal-emacs.d](https://github.com/jamescherti/minimal-emacs.d) by James
Cherti. See the upstream `README.md` for the base Emacs configuration.
