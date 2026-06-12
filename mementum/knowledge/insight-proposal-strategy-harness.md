<!--
Synthesis verification:
- Confidence: 24%
- Sources: 24 memories
- Warnings: No code examples or concrete references, Content does not mention topic 'insight-proposal-strategy-harness'
- Auto-approved: yes (flagged)
--->

The user wants me to synthesize multiple memory insights about strategy-harness failures into a knowledge page. Let me analyze the data:

1. All insights are from the auto-workflow monitoring agent
2. They all target "strategy-harness" component
3. They cover many files in lisp/modules/ (both gptel-* and treesit-agent-tools-workspace.el)
4. The proposals all follow the same pattern: "Address recurring strategy failures"
5. Risk is high across the board
6. Validation rates are very low (0.02-0.08)
7. Expected impacts vary from 60-80% reduction
8. Confidence varies from 0.60-0.80
9. Status is tentative across all

Let me organize this into a useful knowledge page with:
- Categorization of affected files
- Patterns in failures
- Triage/prioritization framework
- Actionable next steps
- Tables of affected modules
- Cross-references

I'll need to make this minimum 50 lines of content, with concrete examples, actionable patterns, and cross-references.

Let me categorize the files:

**Core agent (gptel-tools-agent-*)**: 
- gptel-tools-agent.el
- gptel-tools-agent-runtime.el
- gptel-tools-agent-prompt-build.el
- gptel-tools-agent-strategy-harness.el
- gptel-tools-agent-experiment-core.el
- gptel-tools-agent-error.el
- gptel-tools-agent-benchmark.el

**Auto-workflow (gptel-auto-workflow-*)**:
- gptel-auto-workflow-strategic.el
- gptel-auto-workflow-research-cache.el
- gptel-auto-workflow-projects.el
- gptel-auto-workflow-production-metrics.el
- gptel-auto-workflow-production.el
- gptel-auto-workflow-ontology-strategy.el
- gptel-auto-workflow-ontology-router.el
- gptel-auto-workflow-mementum.el
- gptel-auto-workflow-evolution.el
- gptel-auto-workflow-bare-path-diagnostic.el
- gptel-auto-workflow-approval-queue.el

**Extensions (gptel-ext-*)**:
- gptel-ext-tool-confirm.el
- gptel-ext-backend-registry.el

**Benchmark (gptel-benchmark-*)**:
- gptel-benchmark-subagent.el
- gptel-benchmark-principles.el
- gptel-benchmark-core.el

**Tree-sit**:
- treesit-agent-tools-workspace.el

That's 25 files total. Let me build a table and analysis.

The pattern is striking: all share the same "recurring failures" label, all are high risk, all have very low validation rates (0.02-0.08), and all are tentative. This suggests a systemic issue with the strategy-harness component, not a per-file issue.

Key observations:
- Validation rate max 0.08 means only 8% of proposals get validated at most
- Confidence averages around 0.70
- Most files show 0.80 confidence/impact, but validation rate is 0.04-0.08
- This is a strong signal that proposals are not translating to actual fixes

Let me write this up properly.