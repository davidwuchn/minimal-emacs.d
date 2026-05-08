# Closed-Loop Skill Evolution Test Plan

## Current State

- **Status**: Paused (API quota exhausted)
- **Quota reset**: 2026-05-11T00:00:00+08:00
- **Daemon**: Running (PID 3008726), will auto-resume
- **Last run**: 2026-05-08T122426Z-53f9 (17 experiments)
- **Total experiments**: 870 across 36 targets

## What Changed (This Session)

1. **Extracted 8 domain knowledge skills** from hardcoded elisp
2. **Created 5 evolve scripts** that analyze experiments and update skills
3. **Closed the loop**: Evolved recommendations now inject into executor prompts
4. **Key finding**: Earth/Control improvements have 16% success rate (highest)

## Test Plan

### Phase 1: Baseline Measurement (Before)

Run `analyze_results.py` on existing experiments to establish baseline:

```bash
python3 assistant/skills/auto-workflow/scripts/analyze_results.py \
  --root /home/davidwu/.emacs.d \
  --output /tmp/baseline-analysis.json
```

**Metrics to track:**
- Overall keep rate: 14% (current)
- Success rate by element:
  - Earth (Control): 16%
  - Wood (Operations): 14%
  - Water (Identity): 14%
  - Metal (Coordination): 12%
  - Fire (Intelligence): 0%

### Phase 2: Trigger New Batch (With Evolved Knowledge)

After quota reset, trigger new experiment batch:

```bash
# Via emacsclient (if daemon is running)
emacsclient -s copilot-auto-workflow -e \
  '(gptel-auto-workflow-run "lisp/modules/gptel-sandbox.el" 5)'
```

Or wait for the scheduled cron job to trigger automatically.

### Phase 3: Compare Results (After)

After ~50-100 new experiments:

```bash
python3 assistant/skills/auto-workflow/scripts/analyze_results.py \
  --root /home/davidwu/.emacs.d \
  --output /tmp/post-evolution-analysis.json
```

**Expected improvements:**
- Higher keep rate for Earth/Control hypotheses (executor now prioritizes these)
- Lower attempts on Fire/Intelligence (executor skips these)
- More "prevent errors" and "add validation" patterns in kept experiments

### Phase 4: Iterate

1. Run `evolve_skills.py` to update skills with new data
2. Check if evolved recommendations changed
3. Compare before/after effectiveness

## Success Criteria

- **Minimum**: Keep rate for Earth/Control improves from 16% to 18%+
- **Target**: Overall keep rate improves from 14% to 16%+
- **Stretch**: Fire/Intelligence attempts decrease by 50%

## Monitoring

Watch for:
- Executor prompt includes "Data-Driven Improvement Priorities" section
- Hypotheses mention "prevent errors", "add validation", "fix bugs"
- Reduced attempts on planning/analysis improvements

## Rollback

If results worsen:
1. Revert `benchmark-improver/SKILL.md` to pre-evolution state
2. Disable `gptel-auto-workflow--load-evolved-recommendations()`
3. Fall back to hardcoded defaults

## Timeline

- **2026-05-11**: Quota resets, experiments resume
- **2026-05-12**: Collect 50-100 new experiments
- **2026-05-13**: Run analysis and compare
- **2026-05-14**: Iterate based on results

## λ Principle

```
λ test(x).   baseline → intervention → measure → compare → iterate
             | closed_loop(x) ≡ measure(after) > measure(before)
             | open_loop(x) ≡ no_measurement ∨ no_comparison
```
