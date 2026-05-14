**Target:** AutoTTS + researcher + self-evolution pipeline
**Decision:** Multiple fixes applied across 8 commits
**Score:** 9/10

## Key Fixes Applied

1. **Template variable mismatch**: SKILL.md used `{x}` but `substitute-researcher-variables` searched for `{{x}}`. Fixed in both evolve_researcher.py and SKILL.md.

2. **Dead duplicate functions**: strategic.el had 314 lines of duplicate `run-research-turn`, `controller-decide-research-flow`, `load-autotts-controller`, `build-adaptive-followup-prompt`, `finalize-research` — all overridden by strategic-daemon-functions.el at load time.

3. **JSON key-type bug**: `json-key-type 'keyword` converted keys to `:topics` but code accessed with `gethash "topics"` → always nil → merge functions silently failed.

4. **Daemon single-turn vs multi-turn**: `slr-run-research` bypassed EMA controller entirely. Fixed by delegating to `research-patterns` when available with single-turn fallback.

5. **Auto-generated files in git**: token-efficiency.md, FINDINGS.md, RESEARCHER.md were auto-regenerated every evolution cycle and always conflicted on merge. Relocated to `var/tmp/evolution/` (already gitignored).

6. **Missing feedback loop**: Added bootstrap for `strategy-guidance.json`, outcome-triggered controller evolution (10 threshold), periodic research timer auto-start.

## Lesson

When integrating multiple feedback loops, trace the FULL data flow end-to-end: generator → file → reader → consumer. Silent failures (nil from type mismatch, path resolution, load order) are the hardest bugs to find.
