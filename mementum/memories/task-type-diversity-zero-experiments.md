## Task-Type Diversity: Zero Experiments Analysis

**Problem**: The DIVERSITY check shows 0 experiments for all task types on `gptel-auto-workflow-strategic.el`.

**Root Cause**: 
- `gptel-auto-experiment--get-task-type-stats` reads from `var/tmp/experiments/{run-id}/results.tsv`
- No results recorded for this specific target yet
- `gptel-benchmark--detect-task-type` classifies hypotheses using keyword matching

**Key Files**:
- `gptel-tools-agent-prompt-build.el:2702` - `format-task-type-diversity` function
- `gptel-benchmark-principles.el:271` - `detect-task-type` with keyword patterns
- `gptel-auto-workflow-strategic.el` - main target (146KB)

**Classification Patterns**:
- refactoring: "extract", "simplify", "duplicate", "DRY"
- bug-fix: "fix", "error", "crash", "handle"
- performance: "optimize", "cache", "speed", "memory"
- validation: "guard", "nil-check", "safety"
- feature: "add", "new", "feature", "implement"

**Research Insight**: The system tracks experiments by target path. For a large file like strategic.el, experiments may have been run on other targets but not this specific file. Suggest running first experiment on strategic.el to seed the diversity data.