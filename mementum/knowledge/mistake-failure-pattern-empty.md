<!--
Synthesis verification:
- Confidence: 24%
- Sources: 10 memories
- Warnings: No code examples or concrete references, Content does not mention topic 'mistake-failure-pattern-empty'
- Auto-approved: yes (flagged)
--->

The user wants me to synthesize multiple "empty-hypothesis" mistake memories into a comprehensive knowledge page. Let me analyze the patterns:

1. All failures are of type "empty-hypothesis"
2. They affect different targets:
   - Workflow staging areas: staging-verification, staging-scope, staging-review
   - Specific module files: gptel-tools-agent-experiment-core.el, gptel-tools-agent-benchmark.el, gptel-benchmark-subagent.el, gptel-auto-workflow-strategic.el, gptel-auto-workflow-projects.el, gptel-auto-workflow-ontology-strategy.el, gptel-auto-workflow-ontology-router.el
3. Categories are split between :programming and :agentic
4. Keep-rates are very low (0.0% to 3.2%), indicating these are high-priority
5. Occurrences range from 3-12
6. All have empty example reasons
7. Date range: 2026-06-02 to 2026-06-11

The pattern: "empty-hypothesis" means the system generated hypotheses that were empty - likely the agent's reasoning or diagnostic output was blank/missing. This is a systemic issue affecting both workflow staging and specific module files.

Let me build a knowledge page that:
- Documents the pattern
- Provides concrete examples
- Shows actionable patterns to fix/avoid
- Cross-references related topics
- Has 50+ lines of content

I'll structure it with:
- Frontmatter
- Overview
- Pattern characterization
- Affected targets table
- Category breakdown
- Root cause analysis
- Detection signals
- Actionable patterns (preventive, detective, corrective)
- Example code/commands
- Related topics