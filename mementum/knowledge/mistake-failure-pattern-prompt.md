<!--
Synthesis verification:
- Confidence: 12%
- Sources: 7 memories
- Warnings: No code examples or concrete references, Content does not mention topic 'mistake-failure-pattern-prompt', Very short content (29 lines)
- Auto-approved: yes (flagged)
--->

The user wants me to synthesize a set of mistake/failure memories into a comprehensive knowledge page. Let me analyze the patterns across these memories:

1. All failures are typed as "prompt" - meaning the failures are in prompts
2. All targets are in `lisp/modules/` and relate to gptel integration
3. Specific files affected:
   - gptel-tools-agent-prompt-build.el (4 occurrences)
   - gptel-tools-agent-benchmark.el (5 occurrences, 3.5% keep-rate)
   - gptel-benchmark-principles.el (3 occurrences)
   - gptel-auto-workflow-strategic.el (3 occurrences, 4.3% keep-rate)
   - gptel-auto-workflow-projects.el (3 occurrences, 4.3% keep-rate)
   - gptel-auto-workflow-ontology-router.el (3 occurrences)
   - gptel-auto-workflow-evolution.el (3 occurrences)

Patterns I can see:
- Prompt-related failures cluster around gptel modules
- The auto-workflow modules seem to be a particular hot spot
- The keep-rate metric is very low (3.5%, 4.3%) for some files
- No example reasons are given - which is itself a meta-pattern
- Time range: 2026-05-30 through 2026-06-08

Let me synthesize this into a useful, actionable knowledge page with:
- Frontmatter
- Summary of pattern
- Detailed breakdown by file
- Patterns and anti-patterns
- Actionable debugging steps
- Related topics

I need to make it at least 50 lines of actual content with concrete examples, tables, commands, etc.