# INSTALL.md — OV5 Installation Guide

> **Clone → Configure → Run → Review. Improvements appear overnight.**

---

## Prerequisites

| Requirement | Minimum | Check | Install |
|---|---|---|---|
| **Git** | 2.x | `git --version` | System package manager |
| **Emacs** | 27+ | `emacs --version` | [emacs.org](https://emacs.org) or Homebrew |
| **Bash** | 4+ | `bash --version` | System default |
| **jq** | any | `jq --version` | `brew install jq` (macOS) or `apt install jq` (Linux) |
| **GNU sed** | any | macOS only | `brew install gnu-sed` (script has BSD compat fallback) |
| **OpenCode CLI** | latest | `opencode --version` | [opencode.dev](https://opencode.dev) |

**macOS note:** The install scripts handle BSD sed compatibility automatically. GNU sed is recommended but not required.

**Critical:** `~/.emacs` and `~/.emacs.el` must NOT exist. Emacs ignores `~/.emacs.d/init.el` if either is present. Remove them before proceeding:

```bash
rm -f ~/.emacs ~/.emacs.el
```

---

## Step 1: Clone

```bash
git clone --recurse-submodules https://github.com/davidwuchn/minimal-emacs.d ~/.emacs.d
```

If you forgot `--recurse-submodules`, fix it:

```bash
cd ~/.emacs.d
git submodule update --init --recursive
```

**Verify:** You should see `packages/gptel/`, `packages/gptel-agent/`, `packages/ai-code/` directories with content.

---

## Step 2: Package Setup

```bash
cd ~/.emacs.d
./scripts/setup-packages.sh
```

This does:
1. Syncs and initializes git submodules
2. Generates autoload files for each package
3. Installs git hooks

**Flags:**
- `--update` — pull latest from tracked remote branches
- `--force` — discard local submodule changes
- `--clean` — full teardown and re-init (destructive)

**Verify:** `ls packages/gptel/gptel.el` should exist. Autoload files should be in each `packages/*/` dir.

---

## Step 3: Create `pre-early-init.el`

This file redirects Emacs data to `var/` and is **critical** — without it, ELPA packages and daemon sockets go to wrong locations.

Create `~/.emacs.d/pre-early-init.el`:

```elisp
;; pre-early-init.el — Redirect Emacs data to var/ directory
;; This prevents ELPA packages from polluting ~/.emacs.d/elpa/
;; and ensures daemon sockets use /tmp/emacs$UID/

(setq user-emacs-directory (expand-file-name "var/" minimal-emacs-user-directory))
(setq package-user-dir (expand-file-name "elpa" user-emacs-directory))
```

**Verify:** Start Emacs and check `user-emacs-directory` evaluates to `~/.emacs.d/var/`.

---

## Step 4: API Keys

OV5 needs API keys for LLM providers. These go in `~/.authinfo` (or `~/.authinfo.gpg` for encrypted storage):

```text
machine api.openai.com login api password sk-...
machine api.deepseek.com login api password sk-...
machine api.minimax.chat login api password sk-...
machine api.moonshot.cn login api password sk-...
machine api.github.com login oauth ghp_...
```

**Minimum required:** At least one LLM provider key. The system auto-routes across available providers with failover.

**Recommended:** 3+ providers for resilience. OV5 uses 8 backend definitions with automatic failover.

**GitHub token:** Needed for the research pipeline (GTM Mayor scans repos via `gh api`).

**Verify:** `M-x gptel` should show available backends with your keys.

---

## Step 5: ECA Links

```bash
cd ~/.emacs.d
./scripts/setup-eca-links.sh
```

This creates:
- `~/.config/eca` → symlink to `~/.emacs.d/eca/`
- `~/bin/eca` → symlink to `~/.emacs.d/eca/eca-secure`
- Directory `~/.emacs.d/var/eca/`

**Verify:** `ls -la ~/.config/eca` should show a symlink. `eca --version` should work if `~/bin` is in your PATH.

---

## Step 6: OpenCode Skills (Optional but Recommended)

```bash
cd ~/.emacs.d
./scripts/install-ops-global.sh
```

This installs:
- OV5 cowork skill in `~/.config/opencode/skills/ov5/`
- Agent configurations with correct model assignments
- DeepSeek thinking mode (requires `jq`)

**Model assignments:**

| Agent | Model | Role |
|---|---|---|
| @maintainer | kimi-k2.6 | Orchestrator |
| @delegate | deepseek-v4-pro | Exploration |
| @delegate-strong | gpt-5.4 | Deep analysis |
| @delegate-fast | deepseek-v4-flash | Quick checks |
| @implementer | glm-5.1 | Code execution |

**Verify:** `ls ~/.config/opencode/skills/ov5/SKILL.md` should exist. Agent files in `~/.config/opencode/agents/` should have correct model lines.

---

## Step 7: Start the Daemon

```bash
cd ~/.emacs.d
./scripts/watchdog-daemon.sh start
```

This starts the Emacs daemon (`pmf-value-stream`) with:
- Socket at `/tmp/emacs$(id -u)/pmf-value-stream`
- Environment sanitized (no DISPLAY/WAYLAND vars)
- Native compilation disabled for stability
- Stack size increased to 65532KB

**Alternative:** Let cron handle it (see Step 8).

**Verify:** `emacsclient -s pmf-value-stream --eval 't'` should return `t`.

---

## Step 8: Schedule the Pipeline

For 24/7 autonomous operation, install the cron job:

```bash
cd ~/.emacs.d
./scripts/install-cron.sh
```

The default schedule runs every 4 hours (6 runs/day). On Pi5 (primary server), the schedule is `0 23,3,7,11,15,19`.

**Local dev machines** should run the pipeline manually:

```bash
./scripts/run-pipeline.sh
```

**Verify:** Check cron is installed: `crontab -l | grep run-pipeline`.

---

## Step 9: First Pipeline Run

```bash
cd ~/.emacs.d
./scripts/run-pipeline.sh
```

This executes the full cycle: Research → Self-Evolution → Auto-Workflow.

**What happens:**
1. Bootstrap: fetches `origin/main`, rebases, updates auto-evolved files
2. Research phase: scans repos for techniques and patterns
3. Evolution phase: selects targets, generates hypotheses
4. Workflow phase: runs experiments in isolated git worktrees
5. Results: kept experiments merged, discarded ones recorded

**Expected output:**
```
[auto-workflow] Starting 2026-06-07T120000Z-abc1 with 5 targets
[subagent] executor using DashScope/qwen3.6-plus
[auto-experiment] ✓ Tests passed
[auto-experiment] ✓ Experiment kept — merged to staging
===RESULT=== {"metric":"evolution-cycle","value":0.107}
```

**Verify:** `git log --oneline -10` should show new commits with "kept" or "discarded" markers.

---

## Step 10: Daily Review

After the first run (and every morning after):

```bash
# Check what happened overnight
git log --oneline -10

# Review kept experiments
git log --grep="kept" --oneline -5

# Check experiment results
head -3 var/tmp/experiments/*/results.tsv

# Skim logs for errors
tail -50 var/log/emacs-*.log
```

**What's normal:**
- Phase cycles idle → running → idle
- Timeouts and rate-limits in logs (auto-recover)
- Keep-rate fluctuates 10-30% early on

**What's not normal:**
- Stuck in "selecting" for >30min
- 0 kept for 3+ consecutive runs with different targets
- Same error across all backends (code issue, not provider)

---

## Troubleshooting

### Clone Issues

| Problem | Fix |
|---|---|
| `~/.emacs` or `~/.emacs.el` exists | `rm -f ~/.emacs ~/.emacs.el` |
| Submodules empty after clone | `git submodule update --init --recursive` |
| `~/.emacs.d` already exists | `mv ~/.emacs.d ~/.emacs.d.bak` then re-clone |

### Package Issues

| Problem | Fix |
|---|---|
| Package autoloads missing | `./scripts/setup-packages.sh` (regenerates) |
| ELPA packages in wrong dir | Check `pre-early-init.el` — `user-emacs-directory` must point to `var/` |
| Package download hangs | ELPA cache in `pre-early-init.el` handles this (24h TTL) |

### API Key Issues

| Problem | Fix |
|---|---|
| "all backends exhausted" | Check keys in `~/.authinfo`; verify billing |
| Rate-limit errors | Normal — system auto-recovers with exponential backoff |
| Single backend works, others fail | Check specific provider key format in `~/.authinfo` |

### Daemon Issues

| Problem | Fix |
|---|---|
| Daemon won't start | Check stale socket: `rm /tmp/emacs$(id -u)/pmf-value-stream` |
| `emacsclient` can't connect | Verify socket path matches: `ls /tmp/emacs$(id -u)/` |
| Memory >2.5GB | Watchdog auto-restarts; check `var/tmp/cron/watchdog.log` |
| Daemon unresponsive | ERT test run may be blocking (2min max); wait or `./scripts/watchdog-daemon.sh restart` |

### Pipeline Issues

| Problem | Fix |
|---|---|
| 0 targets selected | All backends rate-limited; check keys |
| All experiments discarded | Run `./scripts/run-tests.sh` — baseline tests must pass |
| "prompt is empty" errors | Usually transient; persistent → check `var/tmp/evolution/` |
| Keep-rate stuck at 0% after 50+ experiments | Review target categories in `.dir-locals.el` |
| Worktree merge conflicts | System auto-rebases; persistent → `git worktree prune` |

### macOS-Specific Issues

| Problem | Fix |
|---|---|
| `sed -i` fails | Scripts have BSD compat wrapper; or `brew install gnu-sed` |
| Socket in wrong location | Scripts use `/tmp/emacs$(id -u)/` (not XDG_RUNTIME_DIR) |
| `lsof` can't find Unix sockets | Known limitation; watchdog uses `ps` fallback |

---

## Verification Checklist

After completing all steps, verify your installation:

```bash
# 1. Submodules populated
ls ~/.emacs.d/packages/gptel/gptel.el

# 2. Var directory exists
ls ~/.emacs.d/var/

# 3. Daemon running
emacsclient -s pmf-value-stream --eval 't'

# 4. API keys configured
emacsclient -s pmf-value-stream --eval '(gptel-get-backend)'

# 5. Pipeline ran successfully
git log --oneline -5

# 6. Tests pass
./scripts/run-tests.sh
```

All 6 checks should pass. If any fail, see the Troubleshooting section above.

---

## Architecture Overview

OV5 has three configuration layers:

| Layer | File | What it configures |
|---|---|---|
| **Emacs** | `~/.emacs.d/pre-early-init.el` | Package dirs, var/ redirection |
| **OV5** | `~/.emacs.d/.dir-locals.el` | Targets, backends, evolution settings |
| **OpenCode** | `~/.config/opencode/` | Agent models, skills, thinking mode |

**Key directories:**

| Path | Purpose |
|---|---|
| `~/.emacs.d/var/` | Emacs data (ELPA, cache, sockets) |
| `~/.emacs.d/var/elpa/` | Installed packages |
| `~/.emacs.d/var/tmp/experiments/` | Experiment results (TSV) |
| `~/.emacs.d/var/tmp/cron/` | Pipeline logs and status |
| `~/.emacs.d/var/log/` | Emacs daemon logs |
| `~/.emacs.d/var/context/` | Context database sidecars |
| `~/.emacs.d/var/approval-queue/` | Approval queue for high-risk proposals |
| `~/.emacs.d/mementum/` | AI memory system |
| `~/.emacs.d/lisp/modules/` | OV5 modules (39 files) |
| `~/.emacs.d/packages/` | Git submodule packages |

---

## For Pi5 (Primary Server)

On the primary evolution server, use the scheduled pipeline:

```bash
# Cron runs at: 0 23,3,7,11,15,19 (6 runs/day)
./scripts/install-cron.sh

# Watchdog monitors daemon health every 30 min
# Auto-restarts on: crashes, memory >2.5GB, socket issues
```

**Pi5-specific rules:**
- Only Pi5 runs the scheduled pipeline
- Only Pi5 pushes evolved skill changes
- Both machines can push mementum memories
- Local machines MUST `git pull --rebase` before running experiments

See [AGENTS.md](AGENTS.md) for the full cross-machine co-evolution protocol.

---

## Quick Reference

```bash
# Setup (one-time)
git clone --recurse-submodules https://github.com/davidwuchn/minimal-emacs.d ~/.emacs.d
cd ~/.emacs.d
./scripts/setup-packages.sh
./scripts/setup-eca-links.sh
./scripts/install-ops-global.sh  # optional

# Daily operation
./scripts/run-pipeline.sh        # run experiments
git log --oneline -10             # review results
./scripts/watchdog-daemon.sh start # start/restart daemon

# Diagnostics
./scripts/run-tests.sh           # verify tests pass
./scripts/check-evolution-status.sh  # pipeline health
./scripts/byte-compile-check.sh  # compilation status
```

---

**See Also:** [OUROBOROS-V5.md](OUROBOROS-V5.md) (architecture) · [BUSINESS_CONTEXT.md](BUSINESS_CONTEXT.md) (YC vision, GTM) · [AGENTS.md](AGENTS.md) (VSM, cross-machine protocol)