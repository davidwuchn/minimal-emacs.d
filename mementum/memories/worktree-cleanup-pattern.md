# Experiment Worktree Cleanup Pattern

**Pattern:** Merged experiment worktrees should be cleaned up to prevent accumulation.

**Symptoms:**
- Many stale worktrees in `var/tmp/experiments/`
- Experiment branches that were merged to staging but not deleted
- Worktree count grows without bound

**Detection:**
```bash
git worktree list | grep optimize | awk '{print $3}' | sed 's/\[//' | sed 's/\]//' | while read branch; do
  if git log staging --oneline | grep -q "Merge $branch"; then
    echo "MERGED: $branch"
  fi
done
```

**Cleanup:**
```bash
git worktree remove <path> --force
git branch -D <branch>
```

**Prevention:**
- Auto-workflow should clean up merged experiments
- Periodic cleanup of merged worktrees
- Consider auto-deletion after merge to staging

**Example:** Cleaned 7 merged worktrees (agent-exp1, agent-exp2, core-exp2, strategic-exp1, strategic-exp2, tools-exp1, tools-exp2)

**Location:** `var/tmp/experiments/optimize/`