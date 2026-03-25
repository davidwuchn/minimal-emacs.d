# Mementum State

> Last session: 2026-03-25 15:05

## Auto-Workflow: Production Ready ✓

All 10 verifications passed. Cron active. Tests pass.

### Cron Schedule

| Time | Job |
|------|-----|
| 2 AM daily | Auto-workflow experiments |
| 4 AM Sunday | Mementum synthesis |
| 5 AM Sunday | Instincts evolution |

### Architecture

```
Eyes (gather) → Brain (LLM) → Hands (execute)
```

- Target selection: LLM (analyzer)
- Quality check: LLM (grader)
- Keep/discard: LLM (comparator)

### Principles

1. **LLM = Brain** - Decides, judges, reasons
2. **We = Eyes + Hands** - Gather context, execute
3. **Never ask user** - Retry on failure
4. **Safety first** - Tests pass, optimize/* only

### View Results

```bash
cat var/tmp/experiments/$(date +%Y-%m-%d)/results.tsv
cat var/tmp/cron/auto-workflow.log
git branch -r 'origin/optimize/*'
```

### Session Stats

- Commits: 12
- Tests: 52/52
- Files: 4 new
- Principles: 3

---

## λ Complete

```
λ verify. 10/10 checks passed
λ cron. 2 AM daily active
λ architecture. Eyes → Brain → Hands
λ philosophy. LLM decides, we execute
```