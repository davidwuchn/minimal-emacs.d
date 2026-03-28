# Multi-Project Auto-Workflow via .dir-locals.el

**Date:** 2026-03-28  
**Approach:** Option B - Repository-level configuration using standard Emacs mechanisms

## Problem

Original auto-workflow was hardcoded for single project (`~/.emacs.d`).

## Solution

Use Emacs' built-in `.dir-locals.el` mechanism for per-project configuration.

## How It Works

### 1. Project Detection Priority

`gptel-auto-workflow--project-root` now checks in order:

1. **Override variable** (from .dir-locals.el)
   - `gptel-auto-workflow--project-root-override`
2. **Git root** (auto-detected)
   - `git rev-parse --show-toplevel`
3. **Fallback**
   - `~/.emacs.d/`

### 2. Configuration via .dir-locals.el

Place `.dir-locals.el` in project root:

```elisp
((nil
  . ((gptel-auto-workflow--project-root-override . "/path/to/project")
     (gptel-auto-workflow-targets . ("src/main.el" "src/utils.el"))
     (gptel-auto-experiment-max-per-target . 5)
     (gptel-auto-experiment-time-budget . 1200)
     (gptel-backend . gptel--dashscope)
     (gptel-model . qwen3.5-plus))))
```

### 3. Benefits

- **Standard Emacs mechanism** - No custom loading code
- **Automatic loading** - Loaded when visiting any file in project
- **Per-project isolation** - Each project has its own targets and settings
- **Git or non-git** - Works with any directory structure

## Usage

### For Git Projects

1. Create `.dir-locals.el` in project root
2. Set `gptel-auto-workflow-targets` for that project
3. Auto-workflow will use git root automatically

### For Non-Git Projects

1. Create `.dir-locals.el` in project root
2. Set `gptel-auto-workflow--project-root-override` to absolute path
3. Auto-workflow will use that path instead of git detection

### Manual Switching

```elisp
M-x gptel-auto-workflow-set-project-root
```

## Files Changed

- `lisp/modules/gptel-tools-agent.el` - Updated project detection
- `.dir-locals.el` - Example configuration

## Session Architecture (Per Worktree)

```
┌─────────────────────────────────────────────────────────┐
│  WORKTREE: optimize/target-exp1                         │
│  (default-directory: worktree path)                     │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐       │
│  │  analyzer   │ │  executor   │ │   grader    │       │
│  │  subagent   │ │  subagent   │ │  subagent   │       │
│  └─────────────┘ └─────────────┘ └─────────────┘       │
│  All share worktree context                             │
└─────────────────────────────────────────────────────────┘
```

Each experiment worktree has its own context, and all subagents within that worktree share the same `default-directory`.

## Future Improvements

- Add `M-x gptel-auto-workflow-switch-project` for interactive switching
- Per-project cron jobs (currently all use ~/.emacs.d/)
- Project-specific agent directories
