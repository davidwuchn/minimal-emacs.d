# PMF Mayor — Run Value Stream

## Purpose
Execute experiments to improve code quality and keep-rate.

## Invocation
```bash
# Run experiments (PMF Mayor)
emacsclient -s /tmp/emacs$(id -u)/pmf-value-stream \
  -e '(gptel-auto-workflow-run-async)'

# Check status
emacsclient -s /tmp/emacs$(id -u)/pmf-value-stream \
  -e '(gptel-auto-workflow-status)'

# Force evolution cycle
emacsclient -s /tmp/emacs$(id -u)/pmf-value-stream \
  -e '(gptel-auto-workflow--maybe-run-evolution)'
```

## What It Does
1. Reads GTM strategy from `mementum/gtm/strategy-roadmap.md`
2. Checks innovation queue for pending ideas
3. Selects targets (static + LLM + frontier)
4. Runs experiments on each target
5. Grades results (kept/discarded)
6. Files beads to `mementum/beads/pmf-to-gtm/`
7. Updates PMF dashboard

## Human Gate
If `gptel-auto-workflow-human-decision-gate` is non-nil:
- Checks `mementum/decisions/` for pending decisions
- Blocks until human marks decision as "approved"

## Safety
- Worktree boundary validation (cannot edit worktree files)
- Pre-commit hook blocks commits of worktree files
- `--daemon` mode (not `--fg-daemon`)

## Logs
- `var/log/emacs-*.log` — daemon stdout
- `var/tmp/cron/evolution-backtrace.log` — errors
- `var/tmp/experiments/YYYY-MM-DD/results.tsv` — experiment results
