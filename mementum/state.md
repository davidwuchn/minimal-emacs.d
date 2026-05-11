# Mementum State

> Last session: 2026-05-11 13:30

## Current Session: 2026-05-11 Pipeline E2E + Self-Evolution Fixes

**Status:** Pipeline e2e reviewed and fixed locally. Main/staging were synced at `e5a1526f` before edits; worktree now has uncommitted pipeline/evolution fixes.

**Done (This Session):**
- ✅ **Real e2e pipeline run** — research produced fresh findings, integration passed, self-evolution ran, auto-workflow queued
- ✅ **Checked `*Messages*`** — self-evolution completed; pipeline waiter was falsely waiting on unrelated workflow status
- ✅ **Fixed pipeline orchestration** — env-overridable waits, shared status-based idle check, explicit self-evolution step, smoke mode
- ✅ **Fixed duplicate logs** — `log()` avoids double-appending when stdout already points at pipeline log
- ✅ **Fixed self-evolution stat regression** — preserve aggregate skill stats when local experiment corpus is smaller
- ✅ **Fixed token-efficiency ownership** — legacy Elisp synthesis writes `auto-workflow/token-efficiency.md`, not canonical `SKILL.md`
- ✅ **Verified smoke e2e** — research → verify → self-evolution completes cleanly without queuing batch when `PIPELINE_SMOKE_ONLY=yes`

**Key Improvements Merged:**

| Component | Change | Impact |
|-----------|--------|--------|
| `scripts/run-pipeline.sh` | Explicit self-evolution stage + smoke mode + status polling | Smooth e2e orchestration |
| `gptel-auto-workflow-evolution.el` | Write token-efficiency sidecar instead of overwriting `SKILL.md` | Prevents canonical skill stat regression |
| `analyze_results.py` | Preserve highest existing aggregate experiment count | Avoids shrinking stats on hosts with partial local corpus |
| `evolve_skills.py` | Skip skill generators when existing aggregate > local records | Prevents local self-evolution from overwriting broader remote stats |

**Tests Verified:**
- Real pipeline e2e: research → verify → self-evolution → auto-workflow queue observed ✓
- Smoke pipeline e2e: `PIPELINE_SMOKE_ONLY=yes` completes cleanly ✓
- `scripts/run-auto-workflow-cron.sh messages`: self-evolution complete, aggregate guard active ✓
- `bash -n scripts/run-pipeline.sh` ✓
- `python3 -m py_compile` for touched evolution scripts ✓
- `emacs --batch -Q -L lisp/modules -f batch-byte-compile lisp/modules/gptel-auto-workflow-evolution.el` ✓

**Branch Status:**
| Branch | HEAD | Remote |
|--------|------|--------|
| main | `e5a1526f` + local edits | origin/main |
| staging | `e5a1526f` | origin/staging |

**Provider Status:**
- MiniMax: WORKING (quota reset)
- CF-Gateway: WORKING (fallback)
- moonshot: WORKING (subagent fallback)

**Daemon Status:**
- Workflow daemon idle: `(:running nil :phase "idle")`
- Last smoke run: `13:22:56` → `13:23:52`, research findings 1251 bytes, self-evolution complete

**Next Steps:**
- Review local diff, then commit/push if desired
- If running production pipeline, omit `PIPELINE_SMOKE_ONLY=yes`
- Consider cleaning or committing generated `assistant/skills/auto-workflow/token-efficiency.md`

---
