<!--
Synthesis verification:
- Confidence: 12%
- Sources: 26 memories
- Warnings: No code examples or concrete references, Content does not mention topic 'insight-proposal-strategy-harness', Very short content (26 lines)
- Auto-approved: yes (flagged)
--->

The user wants me to synthesize multiple memory insights about strategy-harness component failures into a comprehensive knowledge page. Let me analyze the patterns:

1. All insights target the same component: `strategy-harness`
2. They all follow the same proposal pattern: "Address recurring strategy failures in [path]: recurring failures"
3. They span many files in `lisp/modules/` and some staging paths
4. Validation rates are very low (0.02-0.12)
5. Confidence is mostly 0.80, some 0.60-0.70
6. All have high risk and tentative status
7. Impact estimates range from 60% to 80% reduction

Key files affected:
- staging-review, staging-config
- lisp/modules/treesit-agent-tools-workspace.el
- lisp/modules/gptel-tools-agent-*.el (many)
- lisp/modules/gptel-ext-*.el
- lisp/modules/gptel-benchmark-*.el
- lisp/modules/gptel-auto-workflow-*.el (many)

Let me organize this into:
- Overview of the strategy-harness failure pattern
- File inventory with impact estimates
- Patterns observed
- Actionable patterns
- Related topics

I need to make this 50+ lines with concrete examples.