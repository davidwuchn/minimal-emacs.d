# tools agent worktree

## Purpose

Git worktree management and staging branch protection for the auto-workflow.
Creates isolated worktrees for each experiment so agents never touch the main
branch; enforces the critical invariant that auto-workflow NEVER writes to main.
Handles worktree creation/cleanup, staging branch syncing from remote, submodule
hydration and gitlink repair, stale worktree buffer discarding, and the shared
remote resolution for multi-host coordination.

## File Stats

- **Lines**: 1093
- **Path**: `lisp/modules/gptel-tools-agent-worktree.el`

## Key Functions

| Function | Line | Purpose |
|----------|------|---------|
| `gptel-auto-workflow--remote-optimize-branches` | 40 | List remote optimize branches with heads |
| `gptel-auto-workflow--discard-worktree-buffers` | 66 | Kill and unregister buffers rooted at a worktree |
| `gptel-auto-workflow-create-worktree` | 156 | Create isolated worktree for experiment (main entry point) |
| `gptel-auto-workflow-delete-worktree` | 231 | Delete worktree and associated branch |
| `gptel-auto-workflow--assert-main-untouched` | 284 | Assert current branch is NOT main (safety) |
| `gptel-auto-workflow--staging-main-ref` | 358 | Return safe main ref (local or remote) for staging sync |
| `gptel-auto-workflow--staging-sync-ref` | 436 | Return ref staging should sync from (prefers shared remote) |
| `gptel-auto-workflow--sync-staging-from-main` | 551 | Sync staging from upstream at workflow start |
| `gptel-auto-workflow--create-staging-worktree` | 611 | Create isolated staging verification worktree |
| `gptel-auto-workflow--delete-staging-worktree` | 666 | Delete staging worktree (branch preserved) |
| `gptel-auto-workflow--shared-remote` | 305 | Return canonical shared remote for multi-host coordination |
| `gptel-auto-workflow--finalize-refreshed-staging-submodules` | 901 | Repair submodule gitlinks from main ref |

## Critical Invariant

Auto-workflow NEVER touches the main branch. It only:
- **Reads** from main (to create worktrees, sync staging)
- **Writes** to `optimize/*` branches (experiment branches)
- **Writes** to staging branch (integration branch)
- Human reviews staging and merges to main manually.

## Dependencies

- `cl-lib`, `subr-x`
- `gptel-tools-agent-base` (worktree root, default dir, error handling)
- `gptel-tools-agent-benchmark` (project root)
- `gptel-tools-agent-experiment-loop` (git result, commit helpers)
- `gptel-tools-agent-git` (log sanitization)
- `gptel-tools-agent-staging-baseline` (submodule hydration)
- `gptel-tools-agent-staging-merge` (staging head)
- `gptel-tools-agent-subagent` (branch name, worktree paths)
- `magit-git` (branch operations)

## Integration Points

- **Experiment core**: `gptel-auto-workflow-create-worktree` called for each experiment
- **Workflow start**: `gptel-auto-workflow--sync-staging-from-main` syncs staging
- **Workflow end**: `gptel-auto-workflow--delete-staging-worktree` cleans up
- **Staging merge**: Pushes experiment branches to staging for integration
- **Submodule management**: Hydrates and repairs submodule gitlinks across worktrees

## See Also

- [tools agent experiment core](gptel-tools-agent-experiment-core.md)
- [tools agent staging merge](gptel-tools-agent-staging-merge.md)
- [tools agent staging baseline](gptel-tools-agent-staging-baseline.md)
- [tools agent subagent](gptel-tools-agent-subagent.md)