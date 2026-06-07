# Mementum State

> **Bootstrapped**: 2026-06-06
> **Session**: 2026-06-07 — OV5 pipeline overhaul: strategy diversity, business value, run-level health
> **Status**: All 6 phases pushed, 53 tests pass, pipeline reformed

---

## Current Priorities

| Priority | Item | Status |
|---|---|---|
| **DONE** | Phase 1: Break nil-guard death spiral (strategy + templates) | ✅ |
| **DONE** | Phase 2: Wire business_value_score to local signals | ✅ |
| **DONE** | Phase 3: Fix git pull --ff-only divergence | ✅ |
| **DONE** | Phase 5: Run-level 0% keep-rate detector | ✅ |
| **P1** | Monitor next 3 pipeline runs for keep-rate improvement | 🔄 |
| **P2** | Production metrics as real sensor (wire error logs, load times) | 📋 |

## What Changed Today

### Root Cause: The Nil-Guard Death Spiral
The pipeline had 1.4% keep-rate across 140+ runs because:
1. All experiments were "add ONE safety guard" (template-default dominated)
2. Strategy selection had a 1-try-and-out trap (new strategies discarded after 1 failure)
3. Strategy rotation always fell back to template-default
4. Business value scores were all 0.00 (production metrics module never loaded)
5. Git pull --ff-only always failed on Pi5 (stale code running)

### Fixes Applied (2 commits pushed to origin/main)

**Commit `8f446711` — Break the nil-guard death spiral:**
- `strategy-harness.el`: min 5 trials before comparing to template-default, 70% exploration rate
- `experiment-core.el`: rotate to random alternative (not always template-default)
- All 4 prompt templates (agentic, programming, tool-calls, natural-language): v1→v2
  - "ADD ONE SAFETY GUARD" → "MAKE ONE HIGH-VALUE IMPROVEMENT"
  - Prioritized: fix bugs > improve errors > add tests > fix docs > nil guards
  - Added "already-safe code" as forbidden
- `run-pipeline.sh`: `git pull --ff-only` → `git pull --rebase` (fixes Pi5 divergence)

**Commit `5999723e` — Business value + run-level health:**
- `production-metrics.el`: local business value from error logs, byte-compile warnings, test coverage
- `prompt-build.el`: auto-inject business metrics into TSV when missing
- `evolution.el`: run-level consecutive 0% keep-rate detector (3 runs → strategy review, 5 runs → target reset)
- Wired into `maybe-self-heal` (called after every experiment run)

### Files Changed This Session

| File | Change |
|------|--------|
| `scripts/run-pipeline.sh` | git pull --rebase (was --ff-only) |
| `lisp/modules/gptel-tools-agent-strategy-harness.el` | Min 5 trials, 70% exploration |
| `lisp/modules/gptel-tools-agent-experiment-core.el` | Rotate to random alternative |
| `lisp/modules/gptel-auto-workflow-production-metrics.el` | Local business value computation |
| `lisp/modules/gptel-auto-workflow-evolution.el` | Run-level streak detector |
| `lisp/modules/gptel-tools-agent-prompt-build.el` | Auto-inject business metrics |
| `assistant/skills/auto-workflow/prompt-template-*.md` | v2 templates (all 4) |

## Active Patterns

- **Strategy death spiral**: New strategies need min 5 trials before comparison — don't let 1 failure kill them
- **Business value from local signals**: Error logs, byte-compile warnings, test coverage — no Sentry needed
- **Template diversity**: Prompt templates must offer HIGH/MEDIUM/LOW value change types, not just nil guards
- **Git rebase > ff-only**: Pi5 frequently diverges; rebase handles this gracefully
- **Run-level health**: Check across entire runs (not just experiments within a run)

## Expected Impact

Next Pi5 pipeline run (scheduled every 4h) should:
1. Successfully pull latest code via rebase (was failing before)
2. Use new v2 templates with diverse change types
3. Score business value from local signals (no longer all 0.00)
4. Give new strategies 5+ trials before judging them
5. Auto-detect if 3+ consecutive runs have 0% keep-rate

## Context for Next Session

- Opencode default model: `bailian-token-plan/deepseek-v4-pro`
- 53 ERT tests pass
- Pipeline running on Pi5 every 4h (23,3,7,11,15,19)
- GTM daemon socket: `/run/user/1000/emacs/gtm-product-org`
- Keep-rate was 1.4% (2/140 experiments) — should improve significantly

---
*Active Mementum v1.0 — pipeline overhaul, strategy diversity, business value*
