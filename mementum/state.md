# Mementum State

> Last session: 2026-03-24

## Session: Cron Infrastructure for Autonomous Operation ✓

**What was added:**

| Component | Description |
|-----------|-------------|
| `scripts/install-cron.sh` | Easy cron installation |
| `cron.d/auto-workflow` | Updated with mementum weekly job |
| `var/tmp/cron/` | Log directory |
| `var/tmp/experiments/` | Results directory |

### Scheduled Jobs

| Schedule | Function | Purpose |
|----------|----------|---------|
| Daily 2:00 AM | `gptel-auto-workflow-run` | Overnight optimization experiments |
| Weekly Sun 4:00 AM | `gptel-mementum-weekly-job` | Synthesis + decay |
| Weekly Sun 5:00 AM | `gptel-benchmark-instincts-weekly-job` | Evolution batch commit |

### Install

```bash
./scripts/install-cron.sh --dry-run   # Preview
./scripts/install-cron.sh             # Install
```

### Prerequisites

1. Emacs daemon running: `emacs --daemon`
2. Targets configured in: `docs/auto-workflow-program.md`
3. Logs: `tail -f var/tmp/cron/*.log`

---

## Previous Session: DashScope Streaming Fixed ✓

**Root causes found:** nil header, missing host, broken custom parser
**Solution:** use `apply` for delegation, explicit host, standard parser