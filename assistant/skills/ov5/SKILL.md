---
name: ov5
description: Inspect and operate OV5 (Ouroboros V5) through the live Emacs daemon. Use when checking auto-workflow status, starting guarded runs, reviewing experiment results, or querying researcher and evolution state.
---

# OV5

## Overview

OV5 is the live Ouroboros V5 self-improving system behind the `pmf-value-stream` Emacs daemon.

Subsystems:
1. **Pipeline (`auto-workflow`)**: select -> categorize -> route -> hypothesis -> tests -> grade -> review -> merge/learn
2. **Researcher**: scans repos via `gh` API and refreshes research cache
3. **Analyzer**: selects targets from TSV history and frontier/Pareto ranking
4. **Grader**: scores 0.0-1.0 on structure, correctness, and Eight Keys
5. **Comparator**: keep vs discard from score deltas
6. **Evolution (`self-evolve`)**: generates new strategies from failure patterns
7. **Monitoring**: 10 phases (0-9), Sentry wired, production sensing
8. **Approval queue**: file-based, 7-day expiry for high-risk proposals

Current architecture facts from `OUROBOROS-V5.md`: 120 modules (76 byte-compiled, 44 no-byte-compile), 3,485 ERT tests, 7 gates, 8 backend definitions (4-5 actively routed), ~20% keep-rate, ~59% prompt compression, and ~$0.50-2.00/run.

## Socket discovery

Use the main OV5 daemon: `pmf-value-stream`.

Preferred socket path:

```text
/tmp/emacs$(id -u)/pmf-value-stream
```

Resolution order:
1. `$XDG_RUNTIME_DIR/emacs/pmf-value-stream`
2. `${TMPDIR}/emacs$(id -u)/pmf-value-stream`
3. `/tmp/emacs$(id -u)/pmf-value-stream`

Quick check:

```bash
ls "/tmp/emacs$(id -u)/"
```

## Mandatory `emacsclient` pattern

Always use heredoc plus `-a false` for OV5 calls. See also the `daemon-repl` skill for shared emacsclient guidance.

```bash
emacsclient -s /tmp/emacs$(id -u)/pmf-value-stream -a false --eval "$(cat <<'EOF'
(gptel-auto-workflow-status)
EOF
)"
```

Rules:
- Always use `-a false` so `emacsclient` never auto-spawns a daemon.
- Always use heredoc for Elisp quoting.
- Wrap multi-form code in `progn`.

## Public API

| Form | Returns / use | Notes |
|---|---|---|
| `(gptel-auto-workflow-status)` | `(:running :kept :total :phase :run-id :results)` | Main status entrypoint. |
| `(gptel-auto-workflow-run-async)` | Starts a run | Raw async start; returns `'started`. |
| `(gptel-auto-workflow-run-async--guarded)` | Starts a guarded run | Preferred for automation. |
| `(gptel-auto-workflow-log)` | Last 20 sanitized log lines | Filters `[auto-]` and `[nucleus]` messages. |
| `(gptel-auto-workflow-read-persisted-status)` | Status from disk | Survives daemon restarts. |
| `(gptel-auto-workflow-research-status)` | Researcher status plist | Cache freshness and timer state. |
| `(gptel-auto-workflow-run-research)` | Refreshes research cache | Public researcher entrypoint. |
| `(gptel-auto-workflow-evolution-status)` | Evolution subsystem status | Buffer-oriented / interactive. |

### State vars (not functions)

Use these with `bound-and-true-p`:

- `(bound-and-true-p gptel-auto-workflow--running)`
- `(bound-and-true-p gptel-auto-workflow--current-target)`

## Key workflows

### Check status

```bash
emacsclient -s /tmp/emacs$(id -u)/pmf-value-stream -a false --eval "$(cat <<'EOF'
(gptel-auto-workflow-status)
EOF
)"
```

### Start a run (guarded)

```bash
emacsclient -s /tmp/emacs$(id -u)/pmf-value-stream -a false --eval "$(cat <<'EOF'
(gptel-auto-workflow-run-async--guarded)
EOF
)"
```

If it returns `nil`, check for pending decisions in `mementum/decisions/` or an already-running workflow.

### Review last run

```bash
emacsclient -s /tmp/emacs$(id -u)/pmf-value-stream -a false --eval "$(cat <<'EOF'
(gptel-auto-workflow-log)
EOF
)"
```

Then inspect:
- `var/tmp/cron/auto-workflow-status.sexp`
- `var/tmp/experiments/*/results.tsv`
- `git log --oneline -10`

### Targets

Auto-discovered from `lisp/modules/` (skips `-test.el`, `-disabled.el`, `/test/`). Override in `.dir-locals.el`:

```elisp
((emacs-lisp-mode . ((gptel-auto-workflow-targets . ("lisp/modules/foo.el")))))
```

### Researcher

```bash
emacsclient -s /tmp/emacs$(id -u)/pmf-value-stream -a false --eval "$(cat <<'EOF'
(gptel-auto-workflow-run-research)
EOF
)"
```

## Avoid stale forms

- No `gptel-auto-workflow--rate-limited-backends` function exists.
- No `gptel-auto-workflow--read-analysis` function exists.
- No `gptel-auto-workflow-strategic-research` function exists.

## Filesystem reference

| Path | Purpose |
|---|---|
| `var/tmp/cron/auto-workflow-status.sexp` | Persisted workflow status |
| `var/tmp/cron/auto-workflow-messages-tail.txt` | Persisted message tail |
| `var/tmp/experiments/*/results.tsv` | Per-run experiment results |
| `var/tmp/experiments/*/optimize/` | Per-experiment worktree output |
| `var/tmp/research-findings.md` | Researcher cache |
| `var/tmp/cross-subsystem-state.json` | Cross-subsystem persisted state |
| `var/approval-queue/pending/` | Pending high-risk proposals |
| `var/approval-queue/decisions/` | Approved/rejected/expired proposals |
| `mementum/decisions/` | Human decision gate |

## Cron schedule

```cron
0 10,14,18 * * *  pipeline (3x daily)
0 2 * * *         mementum
0 3 * * *         instincts
```

## Safety

- Always use heredoc plus `-a false`.
- Prefer `gptel-auto-workflow-run-async--guarded` for agent-driven starts.
- OV5 never touches `main` directly — isolated git worktrees only.
- 7 gates before merge: routing, tests, grading, complexity, review, pi synthesis, champion.
- High-risk proposals → approval queue (7-day expiry).

## Related skills

- `daemon-repl` — shared emacsclient/heredoc patterns, Elisp evaluation
- `brepl` — Clojure nREPL client (separate tool)
- `ov5-status` — focused system health check
- `ov5-handover` — session handover for OV5
