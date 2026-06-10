<!--
Synthesis verification:
- Confidence: 80%
- Sources: 14 memories
- Warnings: No code examples or concrete references
- Auto-approved: yes (passed)
--->

The user wants me to synthesize a set of memory insights into a knowledge page about "insight-proposal-prompt-builder". Let me analyze the memories:

All memories share common patterns:
- They're all auto-generated insights from a monitoring agent
- All target the `prompt-builder` component
- Most address "recurring empty-hypothesis failures" (with one exception: "recurring prompt failures")
- All have medium risk
- All are tentative status
- They span various modules and staging targets
- Validation rates vary from 0.01 to 0.24
- Confidence levels are 0.60, 0.70, or 0.80
- Expected impact reductions range from ~60% to ~80%

Key modules mentioned:
- staging-verification
- staging-scope
- staging-review
- lisp/modules/gptel-tools-agent-runtime.el
- lisp/modules/gptel-tools-agent-prompt-build.el
- lisp/modules/gptel-tools-agent-experiment-core.el
- lisp/modules/gptel-tools-agent-benchmark.el
- lisp/modules/gptel-benchmark-principles.el
- lisp/modules/gptel-auto-workflow-projects.el
- lisp/modules/gptel-auto-workflow-production-metrics.el
- lisp/modules/gptel-auto-workflow-production.el
- lisp/modules/gptel-auto-workflow-ontology-strategy.el
- lisp/modules/gptel-auto-workflow-ontology-router.el
- lisp/modules/gptel-auto-workflow-mementum.el

Common failure pattern: "recurring empty-hypothesis failures"
Secondary pattern: "recurring prompt failures" (in 2 cases)

I need to:
1. Create a knowledge page with frontmatter
2. Minimum 50 lines of content
3. Include concrete examples (tables, code, commands)
4. Actionable patterns
5. Cross-references
6. Return full markdown inline

Let me structure this as a proper knowledge page that consolidates these patterns and provides actionable guidance.