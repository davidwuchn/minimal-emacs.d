<!--
Synthesis verification:
- Confidence: 24%
- Sources: 14 memories
- Warnings: No code examples or concrete references, Content does not mention topic 'insight-proposal-prompt-builder'
- Auto-approved: yes (flagged)
--->

The user wants me to synthesize memories about a "prompt-builder" component that has recurring empty-hypothesis and prompt failure issues across multiple files. Let me create a comprehensive knowledge page that:

1. Has frontmatter
2. Is at least 50 lines of content
3. Includes concrete examples (code, tables, commands)
4. Has actionable patterns
5. Cross-references related topics
6. Is the full markdown page

Let me analyze the patterns:
- All insights target the `prompt-builder` component
- Most are "empty-hypothesis failures" (13 entries)
- A few are generic "prompt failures" (2 entries: gptel-tools-agent-prompt-build.el, gptel-benchmark-principles.el)
- Confidence ranges: 0.60-0.80
- Risk: all medium
- Validation rates: very low (0.01-0.24)
- Status: all tentative
- Expected impact: 60-80% reduction

The files affected span:
- staging-* (verification, scope, review) - workflow staging
- lisp/modules/gptel-tools-agent-*.el (runtime, prompt-build, experiment-core, benchmark)
- lisp/modules/gptel-benchmark-principles.el
- lisp/modules/gptel-auto-workflow-*.el (projects, production-metrics, production, ontology-strategy, ontology-router, mementum)

Key insight: The prompt-builder is a cross-cutting component with widespread "empty-hypothesis" failures. The low validation rates (max 0.24) suggest these proposals haven't been validated, which is itself a meta-issue.

Let me build a knowledge page that captures:
1. Overview of the prompt-builder failure pattern
2. The two failure modes (empty-hypothesis vs prompt failures)
3. Affected files inventory
4. Statistical patterns
5. Root cause hypotheses
6. Actionable patterns for fixing
7. Code examples
8. Cross-references

Let me write this out fully.