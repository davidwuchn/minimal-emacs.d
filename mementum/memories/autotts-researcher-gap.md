# AutoTTS vs Researcher: Critical Architecture Gap

## Discovery
Our "AutoTTS-inspired" researcher was just text in a markdown prompt. AutoTTS is a **code-generating feedback loop with cached evaluation**.

## Key Gaps
1. **No Replay Store**: AutoTTS caches reasoning traces offline. We do fresh web searches every run.
2. **No Strategy as Code**: AutoTTS agent writes Python controller code. We output text summaries.
3. **No Offline Evaluator**: AutoTTS tests against replay store without LLM calls. We have no cached data to test against.
4. **No Token Cost Tracking**: AutoTTS measures cost per strategy. We don't track tokens per insight.
5. **No Rewrite Loop**: AutoTTS iterates controller code based on metrics. We run once and stop.

## Fixes Applied
- `research-error-p`: Only flag errors for short responses (<1000 chars)
- `digest-research-findings`: Pass through structured research >2000 chars
- `prompt-build.el`: Pass research findings to executor prompts (they were invisible before!)
- `researcher-prompt/SKILL.md`: Mandatory own-repo check first
- `evolution.el`: Clean raw researcher garbage before writing FINDINGS.md
- Created `assistant/skills/researcher-prompt/scripts/evolve-researcher.py` for replay store

## Next Steps
- Build actual replay store from TSV data
- Make researcher output structured strategy metadata
- Run evolution script after each pipeline
- Measure: tokens/insight, keep rate per strategy
