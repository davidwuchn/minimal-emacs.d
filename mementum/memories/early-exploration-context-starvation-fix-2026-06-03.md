## Early-Exploration Context Starvation Fix (2026-06-03)

### Problem
`compress-aggressive` in `strategy-experiment-velocity-context.el` stripped all sections except Task, Code, Failure patterns, Guidance. This caused executor context starvation - 0/5 experiments kept because executor lacked:
- Previous failure context
- Concrete improvement directives
- Past learning recall

### Fix
Expanded `keep-sections` to include:
- "previous experiment" - what was tried before
- "Weakest Keys" - priority focus areas
- "Suggested Hypothesis" - skill-derived guidance
- "RELEVANT PAST" - mementum recall
- "Moderator Intervention" - drift detection

Also fixed `compress-moderate` broken regex (`\\|` at start matched empty string) and `summarize-pattern-history` (was returning static string).

### Evidence
- Byte-compile clean (only width warning)
- Added ASSUMPTION/BEHAVIOR/EDGE CASE/TEST structured comments
- Fallback to original prompt if compression removes everything