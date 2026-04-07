---
title: Auto-Workflow Knowledge Base
status: active
category: knowledge
tags: [auto-workflow, agent, gptel, autonomous, branching]
---

# Auto-Workflow Knowledge Base

## Overview

Auto-workflow is a fully autonomous agent system that optimizes code targets without human intervention. It runs at 2 AM, creates isolated experiment branches, and merges successful changes via PR review.

**Key Principle:** Never ask the user. Fail → Retry → Log → Continue.

---

## Branching Strategy

### Branch Naming Convention

```
optimize/{target-name}-{hostname}-exp{N}
```

| Component | Description | Example |
|-----------|-------------|---------|
| `optimize/` | Prefix indicating optimization experiment | `optimize/` |
| `{target-name}` | Name of file/target being optimized | `retry-imacpro.taila8bdd.ts.net` |
| `{hostname}` | Machine running the experiment | `imacpro` |
| `exp{N}` | Experiment iteration number | `exp1`, `exp2`, `exp3` |

**Full Example:**
```bash
optimize/retry-imacpro.taila8bdd.ts.net-exp1
```

### Branching Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    AUTO-WORKFLOW BRANCH FLOW                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   1. Create worktree with optimize branch                        │
│      ┌──────────────────────────────────────────┐               │
│      │ git worktree add ../worktrees/exp1       │               │
│      │   -b optimize/target-hostname-exp1       │               │
│      └──────────────────────────────────────────┘               │
│                         │                                        │
│                         ▼                                        │
│   2. Executor makes changes (isolated from main)                 │
│      ┌──────────────────────────────────────────┐               │
│      │ analyzer → executor → grader              │               │
│      │ (all within worktree context)            │               │
│      └──────────────────────────────────────────┘               │
│                         │                                        │
│                         ▼                                        │
│   3. If improvement → commit to optimize branch                   │
│      ┌──────────────────────────────────────────┐               │
│      │ git add -A && git commit -m "improvement" │               │
│      └──────────────────────────────────────────┘               │
│                         │                                        │
│                         ▼                                        │
│   4. Push to origin optimize/... (NOT main!)                     │
│      ┌──────────────────────────────────────────┐               │
│      │ git push origin optimize/...             │               │
│      └──────────────────────────────────────────┘               │
│                         │                                        │
│                         ▼                                        │
│   5. Human reviews and merges to main via PR                     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Critical Rule: NEVER Push to Main Directly

```elisp
;; ✅ CORRECT: Push to optimize branch
(when gptel-auto-experiment-auto-push
  (magit-git-success "push" "origin" gptel-auto-workflow--current-branch))

;; ❌ WRONG: Never push to main
;; (magit-git-success "push" "origin" "main")  ;; FORBIDDEN
```

**Violation Consequence:** Unreviewed AI changes land on main branch.

---

## Multi-Project Configuration

### Project Detection Priority

`gptel-auto-workflow--project-root` checks in order:

1. **Override variable** (from .dir-locals.el)
   - `gptel-auto-workflow--project-root-override`
2. **Git root** (auto-detected)
   
...[Result too large, truncated. Full result saved to: /Users/davidwu/.emacs.d/tmp/gptel-subagent-result-2hO59e.txt. Use Read tool if you need more]...