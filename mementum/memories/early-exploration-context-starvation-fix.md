## Early-Exploration Context Starvation Fix (2026-06-02)

### Problem
`strategy-experiment-velocity-context.el` `compress-aggressive` stripped all sections except "Task", "Code under analysis", "Failure patterns", "Guidance". This starved executors of directional guidance needed for actionable improvements, causing 0/5 experiments kept.

### Root Cause
Aggressive compression removed critical sections:
- Weakest Keys (priority focus)
- Suggested Hypothesis / Hypothesis Templates
- Mandatory Focus Contract (prevents inspection thrash)
- Relevant Past Learnings
- Moderator Intervention (for stuck targets)
- Task-Type Diversity guidance

### Fix
Expanded `keep-sections` in `compress-aggressive` to include 15 directional guidance sections. Added fallback that returns full prompt with warning if no sections match.

### Evidence
- Before: 0/5 experiments kept, identical failures on `gptel-tools-agent-error.el`
- After: Prompt preserves concrete improvement targets and priority focus

### Pattern
Early-exploration compression must preserve directional guidance (WHAT to improve) not just structural sections. Executors need hypothesis templates, weakest keys, and focus contracts to produce actionable changes.