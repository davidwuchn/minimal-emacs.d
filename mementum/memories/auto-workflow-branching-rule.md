# Auto-Workflow Branching Rule

**Date**: 2026-03-25
**Symbol**: 🔁 pattern

## Rule

```
λ auto-workflow-branching(x).
    change(x) → branch(optimize/{target}-{hostname}-exp{N})
    | push(optimize/...) → origin/optimize/...
    | ¬push(main)
    | human_review → merge(main)
```

## Branch Format

`optimize/{target-name}-{hostname}-exp{N}`

**Example**: `optimize/retry-imacpro.taila8bdd.ts.net-exp1`

## Flow

1. Create worktree with optimize branch
2. Executor makes changes in worktree (isolated from main)
3. If improvement → commit to optimize branch
4. Push to `origin optimize/...` (NOT main!)
5. Human reviews and merges to main via PR

## Why This Matters

- Prevents unreviewed AI changes on main
- Multiple machines can optimize same target without conflicts
- Human gate for quality control

## Code Location

`gptel-tools-agent.el:1134`:
```elisp
(when gptel-auto-experiment-auto-push
  (magit-git-success "push" "origin" gptel-auto-workflow--current-branch))
```

## Lesson Learned

On 2026-03-25, I mistakenly pushed auto-workflow changes directly to main.
This violated the branching rule. Always check branch before pushing.