# Multi-Project Auto-Workflow Setup

## Overview

Auto-workflow now supports multiple projects using:
- **Simple variable** (`gptel-auto-workflow-projects`) - lists all projects  
- **Per-project config** (`.dir-locals.el` in each project) - project-specific settings

## How It Works

1. **Cron wrapper** calls `./scripts/run-auto-workflow-cron.sh auto-workflow`
2. **For each project**:
   - Changes to project directory (loads `.dir-locals.el` automatically)
   - Clears previous project state
   - Runs auto-workflow with project-specific settings

## Setup New Project

### Step 1: Add .dir-locals.el to Your Project

Create `.dir-locals.el` in your project root:

```elisp
((nil
  . ((gptel-auto-workflow-targets . ("src/main.py" "src/utils.py"))
     (gptel-auto-experiment-max-per-target . 5)
     (gptel-auto-experiment-time-budget . 900)
     ;; Optional: override backend
     ;; (gptel-backend . gptel--dashscope)
     )))
```

### Step 2: Register Project

From Emacs:
```elisp
M-x gptel-auto-workflow-add-project
;; Select your project directory
```

Or customize the variable:
```elisp
M-x customize-variable RET gptel-auto-workflow-projects
;; Add your project paths
```

Or set in your init.el:
```elisp
(setq gptel-auto-workflow-projects
      '("~/.emacs.d"
        "~/projects/my-web-app"
        "~/work/company-project"))
```

### Step 3: Verify

```elisp
M-x gptel-auto-workflow-list-projects
;; Shows all configured projects
```

## Management Commands

- **Add project**: `M-x gptel-auto-workflow-add-project`
- **Remove project**: `M-x gptel-auto-workflow-remove-project`
- **List projects**: `M-x gptel-auto-workflow-list-projects`
- **Run all projects**: `M-x gptel-auto-workflow-run-all-projects`

## Cron Schedule

The same cron job runs all projects:
- 10:00 AM, 2:00 PM, 6:00 PM daily
- Uses the dedicated `copilot-auto-workflow` Emacs daemon
- Processes all projects in sequence
- Logs to `~/.emacs.d/var/tmp/cron/auto-workflow.log`
- Persists status to `~/.emacs.d/var/tmp/cron/auto-workflow-status.sexp`

## Project Isolation

Each project is completely isolated:
- Separate worktrees: `var/tmp/experiments/project1/` and `var/tmp/experiments/project2/`
- Separate results: Each project logs to its own context
- Separate state: Hash tables cleared between projects
- Separate sessions: Each worktree = one gptel-agent session

## Example: Three Projects

```elisp
;; In your init.el or via customize:
(setq gptel-auto-workflow-projects
      '("~/.emacs.d"
        "~/projects/web-app"
        "~/projects/cli-tool"))
```

Each with its own `.dir-locals.el`:

```elisp
;; ~/.emacs.d/.dir-locals.el
((nil . ((gptel-auto-workflow-targets . 
          ("lisp/modules/gptel-tools-agent.el"
           "lisp/modules/gptel-auto-workflow-strategic.el")))))

;; ~/projects/web-app/.dir-locals.el  
((nil . ((gptel-auto-workflow-targets . 
          ("app.py" "models.py" "api/routes.py"))
         (gptel-backend . gptel--openai))))

;; ~/projects/cli-tool/.dir-locals.el
((nil . ((gptel-auto-workflow-targets . 
          ("cmd/root.go" "pkg/utils.go"))
         (gptel-auto-experiment-max-per-target . 3)))
```

## Simple Approach (Alternative)

If you only have one project, just set the variable:

```elisp
(setq gptel-auto-workflow-projects '("~/my-project"))
```

Or use the default (current emacs.d):
- No configuration needed
- Auto-workflow runs on `~/.emacs.d` by default
