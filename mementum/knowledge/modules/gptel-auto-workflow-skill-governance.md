# auto workflow skill governance

## Purpose

Integrates the yknothing/skills-refiner toolkit into the self-evolution pipeline.
Provides four layers of skill governance: (1) health scanning via skill-scan.sh
with JSON reporting, (2) static security audit via Semia CLI with offline
baseline, (3) canary-based activation tracing and dashboard observation of which
skills agents actually use, and (4) skill-eval A/B testing that measures skill
effectiveness via controlled experiments on target files. Also injects invisible
canaries into SKILL.md files for activation tracing.

## File Stats

- **Lines**: 420
- **Path**: `lisp/modules/gptel-auto-workflow-skill-governance.el`

## Key Functions

| Function | Line | Purpose |
|----------|------|---------|
| `gptel-auto-workflow--semia-scan-skill` | 37 | Run Semia security audit on a single skill directory |
| `gptel-auto-workflow--semia-scan-all-skills` | 65 | Scan all skill directories with Semia |
| `gptel-auto-workflow--skill-governance-scan` | 123 | Run skill-scan.sh and return health plist |
| `gptel-auto-workflow--skill-governance-doctor` | 147 | Run full doctor check (probe, dashboard, hygiene) |
| `gptel-auto-workflow--skill-governance-dashboard` | 169 | Read canary observation dashboard for last N days |
| `gptel-auto-workflow--skill-governance-inject-canaries` | 189 | Inject observation canaries into SKILL.md files |
| `gptel-auto-workflow--skill-governance-run-scan-report` | 213 | Save scan health report to var/tmp/skill-governance/ |
| `gptel-auto-workflow--skill-eval-run-ab` | 244 | Run controlled A/B experiment for a skill |
| `gptel-auto-workflow--skill-governance-run-cycle` | 314 | Run complete governance cycle (scan, audit, dashboard, A/B, report) |

## Dependencies

- `json`
- `gptel-tools-agent-base` (worktree root)
- `gptel-auto-workflow-ontology-router` (JSON encoding)

## Integration Points

- **Evolution cycle**: `gptel-auto-workflow--skill-governance-run-cycle` is called during evolution
- **Semia audit**: Static analysis for shell commands, network access, secrets in skills
- **Canary injection**: Scheduled via `run-with-timer` (hourly check, daily refresh)
- **A/B testing**: Integrates with benchmark infrastructure (`byte-compile-file`, behavioral tests)
- **Report persistence**: Saves scan reports and A/B results to `var/tmp/skill-governance/`

## See Also

- [auto workflow evolution](gptel-auto-workflow-evolution.md)
- [tools agent benchmark](gptel-tools-agent-benchmark.md)
- [tools agent prompt build](gptel-tools-agent-prompt-build.md)