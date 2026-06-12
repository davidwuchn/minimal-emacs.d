<!--
Synthesis verification:
- Confidence: 24%
- Sources: 7 memories
- Warnings: No code examples or concrete references, Content does not mention topic 'mistake-failure-pattern-prompt'
- Auto-approved: yes (flagged)
--->

The user wants me to synthesize several mistake/failure memories into a knowledge page about prompt failure patterns. Let me analyze the data:

All entries share:
- Failure type: prompt
- Target: lisp/modules/gptel-*.el (Emacs Lisp files in gptel modules)
- All have "Example reasons: none" (a notable pattern)
- Various occurrence counts: 3, 4, 5
- Different categories: :programming (3.5% keep-rate), :agentic (4.3% keep-rate)

Files affected:
1. gptel-tools-agent-prompt-build.el (4 occurrences)
2. gptel-tools-agent-benchmark.el (5 occurrences, :programming 3.5%)
3. gptel-benchmark-principles.el (3 occurrences)
4. gptel-auto-workflow-strategic.el (3 occurrences, :agentic 4.3%)
5. gptel-auto-workflow-projects.el (3 occurrences, :agentic 4.3%)
6. gptel-auto-workflow-ontology-router.el (3 occurrences)
7. gptel-auto-workflow-evolution.el (3 occurrences)

Key observations:
- The "prompt" failure type is systemic
- All targets are in lisp/modules/ - this is a directory
- Multiple gptel-* modules
- Two clusters: gptel-auto-workflow-* and gptel-tools-agent-* + gptel-benchmark-*
- "Example reasons: none" suggests a tooling issue - reasons aren't being captured
- The keep-rates are very low (3.5%, 4.3%) - this is significant
- Trends show dates from late May through early June 2026

Let me build a comprehensive knowledge page. I need:
- Frontmatter
- 50+ lines
- Concrete examples (code, tables, commands)
- Actionable patterns
- Cross-references

Let me structure it:

1. Overview
2. Failure data table
3. Pattern analysis
4. Root cause hypotheses
5. Detection signals
6. Actionable patterns / fixes
7. Related topics

Let me write this out fully.