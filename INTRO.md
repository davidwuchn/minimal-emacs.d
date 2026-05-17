# minimal-emacs.d + gptel-nucleus

> **An AI-powered Emacs that researches, codes, reviews, and self-evolves — autonomously.**

A fork of [jamescherti/minimal-emacs.d](https://github.com/jamescherti/minimal-emacs.d) extended into a full autonomous AI agent system built on [gptel](https://github.com/karthink/gptel).

---

## What It Does

This setup turns Emacs into an **autonomous optimization pipeline** — it researches external projects for novel techniques, writes and tests code improvements, reviews its own work, and learns from results to get better over time. All inside Emacs, all automated.

| Capability | How |
|-----------|-----|
| **Researches** | Scans GitHub, arXiv, and 18+ davidwuchn repos for novel AI patterns |
| **Codes** | Writes Emacs Lisp fixes: nil-safety guards, DRY refactors, error handling |
| **Reviews** | AI reviewer checks every change before merge |
| **Verifies** | Runs 89+ test files in isolated staging worktrees |
| **Self-Evolves** | Learns from 870+ experiments — 40+ auto-evolved strategies |
| **Runs on Schedule** | Cron-driven: 3-6 pipeline runs/day, fully autonomous |

---

## Quick Start

```bash
./scripts/setup-packages.sh     # Install required Git-tracked packages
./scripts/setup-eca-links.sh    # Setup ECA config symlinks
./scripts/install-cron.sh       # (Optional) Install cron jobs
```

Then it runs. No manual intervention needed.

---

## The Pipeline

```
┌──────────┐    ┌──────────┐    ┌─────────────┐    ┌──────────────┐
│ Research │───→│ Evolution│───→│ Auto-Workflow│───→│ Post-Evolve  │
│ (3min)   │    │ (2min)   │    │ (1-4h)       │    │ (2min)        │
└──────────┘    └──────────┘    └─────────────┘    └──────────────┘
     ↓                               ↓
  External findings             worktree → analyzer
  + 18-repo prefetch            → executor → grader
                                → benchmark → decide
                                → reviewer → staging
```

**Each auto-workflow experiment:** selects a target file, generates a hypothesis, implements a fix, runs tests, grades itself, gets reviewed, and either merges to staging or learns from failure.

---

## Proven Results

| Metric | Value |
|--------|-------|
| **Commits** | 1700+ fixes, 1100+ verified experiment merges |
| **Kept experiments** | 195+ (code improvements that passed all gates) |
| **Evolved strategies** | 40+ prompt-building strategies |
| **Test coverage** | 89 module files, 57 regression test files |
| **Backend fallback** | 5-provider chain (MiniMax → moonshot → DashScope → DeepSeek → CF-Gateway) |

---

## Key Features

### Autonomous Pipeline
- **Research**: Multi-turn AutoTTS controller searches 18+ repos + arXiv + GitHub for relevant techniques
- **Code**: Executor subagent reads files, writes fixes, verifies syntax — all in isolated git worktrees
- **Review**: AI reviewer checks for blockers, regressions, and code quality
- **Decide**: Comparator weighs before/after scores (70% grader, 30% code quality)
- **Learn**: Non-kept experiments feed back into strategy evolution

### Self-Evolution
- **40+ strategies** auto-discovered from prompt-builder code
- **Pareto frontier** tracks non-dominated strategies for exploration/exploitation balance
- **AutoTTS controller** learns from 21+ research traces, adjusting priorities over time
- **Convergence detection** stops evolution when plateau detected (prevents overfitting)

### Safety & Reliability
- **Git worktree isolation** — never touches `main` directly
- **Staging verification** — 1800s timeout, 89-test suite, rollback on failure
- **Conflict marker guard** — rejects commits with `<<<<<<<` markers
- **Provider failover** — 5 backends with automatic chain advancement
- **Watchdog** — force-stops stuck workflows after 90 minutes
- **Quota-aware** — skips runs when API quota exhausted

### Architecture
- **31-tool nucleus stack** — Read, Write, Edit, Bash, Grep, Glob, Code_Map, Programmatic, RunAgent...
- **6 subagent types** — executor, grader, reviewer, analyzer, comparator, researcher
- **Security ACLs** — hard capability filtering by preset (plan mode physically cannot mutate)
- **Payload resilience** — pre-send compaction, auto-retry, reasoning repair for thinking models

---

## Backend Fallback Chain

Auto-workflow runs on MiniMax by default, automatically failing over when rate-limited:

| # | Backend | Model | Use |
|---|---------|-------|-----|
| 1 | MiniMax | minimax-m2.7-highspeed | Primary workhorse |
| 2 | moonshot | kimi-k2.6 | Best for code changes |
| 3 | DashScope | qwen3.6-plus | Fast, reliable |
| 4 | DeepSeek | deepseek-v4-pro | Strong reasoning |
| 5 | CF-Gateway | @cf/moonshotai/kimi-k2.6 | 262k context, function calling |

---

## Requirements

- Emacs 29.1+
- API keys in auth-source: `api.minimaxi.com`, `api.kimi.com`, `coding.dashscope.aliyuncs.com`, `api.deepseek.com`, `gateway.ai.cloudflare.com`
- Git, `gh` CLI (for repo prefetch), `timeout` (for staging verification)
- macOS or Linux

---

## Installation

```bash
# 1. Clone with submodules
git clone --recurse-submodules https://github.com/davidwuchn/minimal-emacs.d ~/.emacs.d

# 2. Install packages
cd ~/.emacs.d && ./scripts/setup-packages.sh

# 3. Setup ECA symlinks
./scripts/setup-eca-links.sh

# 4. Start Emacs normally
emacs
```

---

## Key Commands

```elisp
;; Manual workflow triggers
(gptel-auto-workflow-run-async)        ; Start workflow
(gptel-auto-workflow-status)           ; Check status
(gptel-auto-workflow-run-research)     ; Run researcher now
```

```bash
# Full pipeline (research → evolve → work → evolve)
./scripts/run-pipeline.sh

# Direct auto-workflow (skip research)
./scripts/run-auto-workflow-cron.sh auto-workflow

# Status snapshots
./scripts/run-auto-workflow-cron.sh status
./scripts/run-auto-workflow-cron.sh messages
```

---

## Directory Structure

```
~/.emacs.d/
├── lisp/modules/         80+ Elisp modules (AI agents, tools, evolution)
├── packages/              Git-tracked dependencies (gptel, gptel-agent, nucleus, mementum)
├── assistant/             Agent prompts, skills, strategies (40+ evolved)
├── tests/                 57 regression test files
├── scripts/               Pipeline orchestration, cron, prefetch, setup
├── mementum/              AI memory system (insights, patterns, knowledge)
├── var/tmp/               Runtime data (experiments, traces, findings, staging)
├── var/elpa/              Package state (auto-seeded in worktrees)
└── eca/                   ECA provider configuration + secure wrappers
```

---

## Upstream

This fork builds on [minimal-emacs.d](https://github.com/jamescherti/minimal-emacs.d) by James Cherti. See `README.md` for the base Emacs configuration.

Key divergences:
- `pre-early-init.el` — max-lisp-eval-depth 20000, daemon workflow support
- `post-init.el` — AI module loading, runtime seeding, research overrides
- `lisp/init-ai.el` — gptel + nucleus + ECA + benchmark integration
- Git-tracked `packages/` instead of ELPA for gptel/gptel-agent (ELPA lags behind required APIs)
