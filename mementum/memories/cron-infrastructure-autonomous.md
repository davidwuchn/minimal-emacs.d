💡 cron-infrastructure-autonomous

## Problem
Gap analysis showed autonomous operation infrastructure missing:
- No cron scheduling for overnight experiments
- Weekly synthesis not wired to cron
- var/tmp/experiments/ directory missing

## Solution
1. Created `scripts/install-cron.sh` for easy cron installation
2. Updated `cron.d/auto-workflow` with weekly synthesis job
3. Created required directories: var/tmp/cron/, var/tmp/experiments/

## Scheduled Jobs
| Daily 2:00 AM | auto-workflow-run | Overnight experiments |
| Weekly Sun 4:00 AM | mementum-weekly-job | Synthesis + decay |
| Weekly Sun 5:00 AM | instincts-weekly-job | Evolution |

## Install
```bash
./scripts/install-cron.sh --dry-run   # Preview
./scripts/install-cron.sh             # Install
```

## Logs
`tail -f var/tmp/cron/*.log`