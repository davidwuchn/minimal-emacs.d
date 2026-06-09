<!--
Synthesis verification:
- Confidence: 80%
- Sources: 26 memories
- Warnings: No code examples or concrete references
- Auto-approved: yes (passed)
--->

The user wants me to synthesize a set of memory insights into a knowledge page about "insight-proposal-strategy-harness". Let me analyze the memories:

1. All insights are about "recurring strategy failures" in various files/components
2. They all target the "strategy-harness" component
3. They come from auto-workflow / monitoring agent
4. Validation rates are very low (0.02-0.12)
5. Confidence is mostly 0.80, sometimes 0.60 or 0.70
6. Risk is always "high"
7. Status is always "tentative"
8. Expected impact is ~80%, ~70%, or ~60%

The files affected include:
- staging-review
- staging-config
- lisp/modules/treesit-agent-tools-workspace.el
- lisp/modules/gptel-tools-agent-strategy-harness.el
- lisp/modules/gptel-tools-agent-runtime.el
- lisp/modules/gptel-tools-agent-prompt-build.el
- lisp/modules/gptel-tools-agent-experiment-core.el
- lisp/modules/gptel-tools-agent-error.el
- lisp/modules/gptel-tools-agent.el
- lisp/modules/gptel-tools-agent-benchmark.el
- lisp/modules/gptel-ext-tool-confirm.el
- lisp/modules/gptel-ext-backend-registry.el
- lisp/modules/gptel-benchmark-subagent.el
- lisp/modules/gptel-benchmark-principles.el
- lisp/modules/gptel-benchmark-core.el
- lisp/modules/gptel-auto-workflow-strategic.el
- lisp/modules/gptel-auto-workflow-research-cache.el
- lisp/modules/gptel-auto-workflow-projects.el
- lisp/modules/gptel-auto-workflow-production-metrics.el
- lisp/modules/gptel-auto-workflow-production.el
- lisp/modules/gptel-auto-workflow-ontology-strategy.el
- lisp/modules/gptel-auto-workflow-ontology-router.el
- lisp/modules/gptel-auto-workflow-mementum.el
- lisp/modules/gptel-auto-workflow-evolution.el
- lisp/modules/gptel-auto-workflow-bare-path-diagnostic.el
- lisp/modules/gptel-auto-workflow-approval-queue.el

Patterns I see:
- Massive duplication of the same proposal template
- Very low validation rates indicate these are speculative
- High risk
- Cross-cutting concern across many modules
- The strategy-harness component is itself one of the affected modules

Let me build a knowledge page with:
1. Frontmatter
2. Overview section
3. Pattern analysis - the proposals follow identical structure
4. Tables of affected components grouped by category
5. Code/Elisp examples for a strategy-harness
6. Actionable patterns for addressing recurring strategy failures
7. Validation rate analysis
8. Cross-references

Let me write this with at least 50 lines of content. I'll aim for thorough content with tables, code examples, and patterns.