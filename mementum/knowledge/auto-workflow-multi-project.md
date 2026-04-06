# Auto-Workflow Multi-Project Setup

**Status**: active
**Category**: configuration
**Tags**: auto-workflow, multi-project, setup
**Related**: auto-workflow.md, nucleus-patterns.md

## Overview

Auto-workflow supports multiple projects with per-project configuration.

## Configuration

### Global Project List

```elisp
;; Set in early-init.el or init.el
(setq gptel-auto-workflow-projects
      '("~/workspace/project-a"
        "~/workspace/project-b"
        "~/.emacs.d"))
```

### Per-Project Settings

Create `.dir-locals.el` in each project:

```elisp
((nil . ((gptel-auto-workflow-max-experiments . 5)
         (gptel-auto-experiment-timeout . 600)
         (gptel-auto-workflow-targets . ("src/core.el" "src/utils.el")))))
```

## How It Works

1. Cron calls `./scripts/run-auto-workflow-cron.sh auto-workflow`
2. Script iterates over `gptel-auto-workflow-projects`
3. For each project:
   - Changes to project directory (loads `.dir-locals.el`)
   - Clears previous state
   - Runs auto-workflow with project settings
   - Stores results in `var/tmp/experiments/`

## Example Setup

### Project A (Emacs config)

```elisp
;; ~/.emacs.d/.dir-locals.el
((nil . ((gptel-auto-workflow-max-experiments . 3)
         (gptel-auto-experiment-timeout . 300)
         (gptel-auto-workflow-targets . ("lisp/modules/nucleus-tools.el")))))
```

### Project B (Web app)

```elisp
;; ~/workspace/webapp/.dir-locals.el
((nil . ((gptel-auto-workflow-max-experiments . 10)
         (gptel-auto-experiment-timeout . 900)
         (gptel-auto-workflow-targets . ("src/api.py" "src/models.py")))))
```

## Parallel Execution

Multiple machines can run auto-workflow simultaneously:

- **macOS** (daylight): 10AM, 2PM, 6PM
- **Pi5** (24/7): 11PM, 3AM, 7AM, 11AM, 3PM, 7PM

Each machine creates its own `optimize/*-machine-expN` branches.

## Results

Results stored in:
- `var/tmp/experiments/YYYY-MM-DD/results.tsv` - Daily results
- `var/tmp/experiments/YYYY-MM-DD/` - Experiment details

## Depends On

- `gptel-auto-workflow-projects` variable
- `.dir-locals.el` per project
- Cron configuration