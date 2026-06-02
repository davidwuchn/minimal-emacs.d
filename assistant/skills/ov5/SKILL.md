---
name: ov5
description: Cowork with OV5 (Ouroboros V5) — trigger experiments, review results, integrate feedback between coding agent and self-evolving pipeline
---
metadata:
  evolution-stats:
    total-experiments: 870

# OV5 Cowork

OV5 is a self-regulating Emacs daemon that runs automated code improvement experiments. You (the coding agent) cowork with it: you write code, OV5 tests improvements independently via isolated git worktrees.

## Socket

```
/run/user/1000/emacs/ov5-auto-workflow
```

All communication uses `emacsclient -s <socket> --eval '<expr>'`.

## OV5 Subsystems You Can Use

### Pipeline (auto-workflow)
Runs experiment cycles: select targets → categorize → route backend → generate hypothesis → run 2061 tests → AI grade → AI review → merge or learn.

| Command | What it does |
|---------|-------------|
| `(gptel-auto-workflow-status)` | Phase, targets, keep-rate, run-id |
| `(gptel-auto-workflow-run-async)` | Start a new cycle |
| `(gptel-auto-workflow--running)` | Is pipeline active? |
| `(gptel-auto-workflow--rate-limited-backends)` | Which backends are rate-limited |
| `(gptel-auto-workflow--current-target)` | File currently being experimented on |

### Researcher
Scans 17+ repos via gh API, fetches techniques that fill ontology knowledge gaps, produces Allium behavioral specs. Triggered by pipeline; not typically called directly.

### Analyzer
Selects experiment targets from TSV history, ranks by Pareto frontier size. Reads `gptel-auto-workflow--stats` for latest analysis.

### Grader
Scores experiment output 0.0-1.0 on structure, correctness, Eight Keys. Results logged in `===RESULT===` JSON blocks.

### Comparator
Decides keep vs discard from score/quality deltas. Results visible in `results.tsv`.

### Evolution (self-evolve)
Generates new strategies from failure patterns. Runs each cycle after experiments complete. Output in `===RESULT===`.

## Key Workflows

### Check pipeline health
```elisp
(gptel-auto-workflow-status)
;; → (:running nil :kept 0 :total 5 :phase "idle" :run-id "...")
```

### Start a new experiment cycle
```elisp
(gptel-auto-workflow-run-async)
;; → "started"
```

### Review last run results
```bash
cat var/tmp/experiments/*/results.tsv | column -t
cat var/log/emacs-*.log | grep "kept\|discard\|RESULT" | tail -10
git log --oneline -10
```

### Add a target file
Set `gptel-auto-workflow-targets` in `.dir-locals.el`:
```elisp
((emacs-lisp-mode . ((gptel-auto-workflow-targets . ("lisp/modules/foo.el")))))
```

### Trigger researcher for a specific technique
```elisp
(require 'gptel-auto-workflow-strategic nil t)
(gptel-auto-workflow-strategic-research "technique to research")
```

### Read experiment analysis
```elisp
(gptel-auto-workflow--plist-get
  (gptel-auto-experiment--merge-analysis
    (gptel-auto-workflow--read-analysis) previous-results)
  :patterns)
```

## Coworking Pattern

1. **You review code** → identify improvement opportunity
2. **You request experiment** → `(gptel-auto-workflow-run-async)` or add target
3. **OV5 runs experiment** → isolated worktree, 6 gates, ~30min
4. **You review results** → `git log --oneline -10` `results.tsv`
5. **You merge or refine** → if kept, review the diff; if discarded, adjust target config

The ontology learns from every kept/discarded pair — your review feedback trains future experiments.

## Filesystem Reference

| Path | Purpose |
|------|---------|
| `var/log/emacs-*.log` | Full daemon log |
| `var/tmp/experiments/*/results.tsv` | Experiment results TSV |
| `var/tmp/experiments/*/optimize/` | Per-experiment output |
| `var/tmp/cross-subsystem-state.json` | Persisted state across restarts |
| `assistant/strategies/provider-routing/backend-preference.el` | Auto-evolved backend preferences |
| `mementum/knowledge/backend-comparison.md` | Backend comparison |
| `mementum/knowledge/model-comparison.md` | Model comparison |

## Safety

OV5 never touches `main` directly. All experiments run in isolated git worktrees. A change only merges after passing 2061 tests + grader + reviewer + comparator + champion league. If you add a target, OV5 handles isolation automatically.
