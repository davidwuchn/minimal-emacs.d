<!--
Synthesis verification:
- Confidence: 40%
- Sources: 4 memories
- Warnings: No code examples or concrete references, Very short content (25 lines)
- Auto-approved: yes (flagged)
--->

The user wants me to synthesize the provided memories about a pattern of failures into a knowledge page. Let me analyze the data:

1. All 4 memories share a common topic: "mistake-failure-pattern-unknown" - meaning unknown failure types
2. They all involve files in `lisp/modules/` related to gptel auto-workflow
3. The failure type is "unknown" in all cases
4. The categories vary: :programming (0.0% keep-rate) and :agentic (2.2%, 4.3%, 4.3%)
5. Total occurrences: 5+6+4+3 = 18
6. The keep-rates are all very low (0.0% to 4.3%), indicating systemic issues

The files affected:
- gptel-tools-agent-benchmark.el
- gptel-auto-workflow-production-metrics.el
- gptel-auto-workflow-ontology-strategy.el
- gptel-auto-workflow-ontology-router.el

All seem to be related to the gptel auto-workflow system, particularly the ontology, routing, and metrics components.

I need to create a knowledge page that:
- Is at least 50 lines of content
- Has concrete examples (code, tables, commands)
- Has actionable patterns
- Cross-references related topics
- Is in markdown format with frontmatter

Let me build this out properly.