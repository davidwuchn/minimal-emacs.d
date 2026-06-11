<!--
Synthesis verification:
- Confidence: 24%
- Sources: 7 memories
- Warnings: No code examples or concrete references, Content does not mention topic 'mistake-failure-pattern-prompt'
- Auto-approved: yes (flagged)
--->

The user wants me to synthesize a series of mistake/failure pattern memories into a comprehensive knowledge page. Let me analyze the data:

All entries share:
- Failure type: `prompt`
- Target: various files in `lisp/modules/` related to `gptel-*` and `gptel-tools-agent-*` and `gptel-auto-workflow-*`
- No example reasons provided
- Detected by monitoring agent
- Various occurrence counts (3-5)
- Some have category/keep-rate data

Let me identify the affected files:
1. `lisp/modules/gptel-tools-agent-prompt-build.el` - 4 occurrences
2. `lisp/modules/gptel-tools-agent-benchmark.el` - 5 occurrences, :programming, 3.5% keep-rate
3. `lisp/modules/gptel-benchmark-principles.el` - 3 occurrences
4. `lisp/modules/gptel-auto-workflow-strategic.el` - 3 occurrences, :agentic, 4.3% keep-rate
5. `lisp/modules/gptel-auto-workflow-projects.el` - 3 occurrences, :agentic, 4.3% keep-rate
6. `lisp/modules/gptel-auto-workflow-ontology-router.el` - 3 occurrences
7. `lisp/modules/gptel-auto-workflow-evolution.el` - 3 occurrences

Common patterns:
- All `failure-type: prompt`
- All target gptel-related modules
- Two clusters: tools-agent-* and auto-workflow-*
- Keep-rates are very low (3.5%, 4.3%) indicating systemic issues
- No "example reasons" — means the failure signals are not being attributed specific causes

Let me build a comprehensive page with:
- Frontmatter
- Overview/Summary
- Affected files table
- Pattern analysis
- Actionable patterns
- Diagnostic commands
- Cross-references

I need at least 50 lines of content with concrete examples, code, tables, commands, and cross-references.