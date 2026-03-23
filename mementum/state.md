# Mementum State

> Last session: 2026-03-23

## Active

- **Autonomous Research Agent** — ~48 experiments/night, skill auto-evolution
- **Auto-workflow** — program.md + optimization-skills + mementum integration

## Recent (7 days)

| Date | What | Status |
|------|------|--------|
| 2026-03-23 | Autonomous Research Agent complete | ✓ |
| 2026-03-23 | Skill auto-evolution + 10min budget | ✓ |

## Pointers

| Path | Purpose |
|------|---------|
| `mementum/memories/` | Session insights (24 files) |
| `mementum/knowledge/` | Synthesized pages (12 files) |
| `mementum/knowledge/optimization-skills/` | Target skills |
| `mementum/knowledge/mutations/` | Mutation patterns |
| `docs/auto-workflow-program.md` | Human-editable objectives |

## Entry Points

```elisp
M-x gptel-auto-workflow-run-autonomous
```

## Cron

```bash
0 2 * * * emacsclient -e '(gptel-auto-workflow-run-autonomous)'   # Daily 2 AM
0 3 * * 0 emacsclient -e '(gptel-benchmark-instincts-weekly-job)' # Sunday 3 AM
```

## History

See git log: `git log --oneline --since="2026-03-20"` or `git log --grep="◈"`