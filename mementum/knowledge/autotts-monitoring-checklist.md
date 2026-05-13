# AutoTTS Production Monitoring Checklist

## What to Watch For

### During Research Phase (15:00 pipeline)

**Expected Behavior:**
- `[auto-workflow] Hunting external ideas (multi-turn controller)...` — indicates multi-turn mode active
- `[autotts] Starting External research turn 1/3` — turn 1 begins
- `[autotts] Step 0: search ...` — step logged
- `[autotts] Turn 1 result: 1500 chars, confidence=0.55, decision=continue` — controller checkpoint
- `[autotts] Starting External research turn 2/3` — turn 2 begins
- `[autotts] Controller STOP after turn 2` — early stop (if confidence high)
- OR `[autotts] Max turns (3) reached` — all turns used
- `[autotts] Saved research trace: 2026...json (4 steps)` — trace saved with step count

**Red Flags:**
- Only 1 turn runs (controller stops immediately — may need tuning)
- 0 steps in trace (step extraction failed)
- No `[autotts]` messages at all (multi-turn not active)
- Error about `gptel-benchmark-call-subagent` (subagent unavailable)

**Check These Files After Run:**
```bash
# Latest trace
tail -1 /home/davidwu/.emacs.d/var/tmp/research-traces/*.json

# Should show: steps array with step-count > 0
# Should show: strategy name, controller-decision, confidence

# Controller config
cat /home/davidwu/.emacs.d/var/tmp/researcher-controller.json

# Evolution history
ls -la /home/davidwu/.emacs.d/var/tmp/controller-evolution-history.json
```

### During Evolution Phase (after pipeline)

**Expected Behavior:**
- `[autotts] Starting evolution cycle...`
- `[autotts] Loaded N traces, M past generations`
- `[autotts] Objective: own=X.XX ext=X.XX conf=X.XX eff=X.XX → X.XXX`
- `[autotts] Convergence: insufficient history (M < 3)` — until 3+ gens
- `[autotts] Saved evolved controller: ...`
- `[autotts] Saved evolution history: M generations`
- `[autotts] Updated SKILL.md with evolved controller (own=XX% ext=XX%)`

**Red Flags:**
- No evolution messages (hook not called)
- Convergence false positive (stops too early)
- SKILL.md not updated (joint optimization failed)

### Quick Verification Commands

```bash
# 1. Check latest trace has steps
cd /home/davidwu/.emacs.d
ls -t var/tmp/research-traces/*.json | head -1 | xargs cat | python3 -m json.tool | grep -E '"steps"|"step-count"'

# 2. Check controller was saved
cat var/tmp/researcher-controller.json | python3 -m json.tool

# 3. Check SKILL.md has evolved guidance
grep -A3 "Evolved Controller Config" assistant/skills/researcher-prompt/SKILL.md

# 4. Check evolution history
ls -la var/tmp/controller-evolution-history.json
```

## Manual Test (Interactive Emacs)

If you want to test the multi-turn controller manually:

```elisp
;; Run this in your Emacs
(require 'gptel-auto-workflow-strategic)
(gptel-auto-workflow--research-patterns
 (lambda (findings)
   (message "Research complete: %d chars" (length findings))
   (message "Steps logged: %d" (length gptel-auto-workflow--research-steps))))
```

**Expected:**
- Opens gptel chat with researcher
- Multiple turns (up to 3)
- Controller messages in *Messages*
- Trace saved to `var/tmp/research-traces/`

## Rollback Plan

If multi-turn causes issues:

```elisp
;; Disable multi-turn (revert to single 600s call)
(setq gptel-auto-workflow-max-research-turns 1)

;; Or disable entirely
(setq gptel-auto-workflow-research-targets nil)
```

## Success Criteria

After 15:00 run, verify:
- [ ] At least 1 new trace in `var/tmp/research-traces/`
- [ ] Trace has `:steps` array with count > 0
- [ ] Trace has `:step-count` field
- [ ] Controller config updated (check timestamp)
- [ ] SKILL.md has "Evolved Controller Config" section
- [ ] No errors in `var/tmp/cron/pipeline.log`

---

*Created for 15:00 pipeline monitoring*
*Last updated: 2026-05-13*
