<!--
Synthesis verification:
- Confidence: 80%
- Sources: 7 memories
- Warnings: No code examples or concrete references
- Auto-approved: yes (passed)
--->

The user wants me to synthesize memories about a specific topic: "mistake-failure-pattern-prompt" into a knowledge page. Let me analyze the memories:

1. All entries share the same failure type: "prompt"
2. All targets are files in `lisp/modules/` related to gptel (likely a Claude/LLM integration in Emacs)
3. Various files affected:
   - gptel-tools-agent-prompt-build.el (4 occurrences)
   - gptel-tools-agent-benchmark.el (5 occurrences, keep-rate 3.5%)
   - gptel-benchmark-principles.el (3 occurrences)
   - gptel-auto-workflow-strategic.el (3 occurrences, keep-rate 4.3%)
   - gptel-auto-workflow-projects.el (3 occurrences, keep-rate 4.3%)
   - gptel-auto-workflow-ontology-router.el (3 occurrences)
   - gptel-auto-workflow-evolution.el (3 occurrences)

4. Time range: 2026-05-30 to 2026-06-08
5. Common pattern: prompt-related failures in gptel modules
6. Categories mentioned: :programming, :agentic
7. Keep-rates are very low (3.5%, 4.3%) - meaning very few generated outputs are kept
8. Multiple occurrences (3-5) per file

Key insights:
- This is a systemic pattern, not isolated incidents
- Affects gptel modules (Emacs LLM integration)
- Cross-cutting: affects prompt building, benchmarking, auto-workflow
- Two categories: programming and agentic
- The keep-rates are concerning (3.5-4.3% is very low)
- Files are split across multiple subsystems

I need to create a knowledge page with:
- Frontmatter
- Minimum 50 lines of content
- Concrete examples
- Actionable patterns
- Cross-references
- Tables/commands

Let me structure this:
1. Overview/Pattern Summary
2. Affected Modules (table)
3. Common Failure Modes
4. Root Cause Analysis
5. Detection Patterns
6. Actionable Remediation
7. Prevention
8. Related topics