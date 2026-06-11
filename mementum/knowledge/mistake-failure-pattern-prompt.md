<!--
Synthesis verification:
- Confidence: 24%
- Sources: 7 memories
- Warnings: No code examples or concrete references, Content does not mention topic 'mistake-failure-pattern-prompt'
- Auto-approved: yes (flagged)
--->

The user wants me to synthesize several mistake/failure memory entries into a knowledge page. Let me analyze the patterns:

1. All entries have `failure type: prompt`
2. All targets are in `lisp/modules/` and follow a `gptel-*.el` naming pattern
3. The gptel modules cluster into:
   - Agent tools: `gptel-tools-agent-prompt-build.el`, `gptel-tools-agent-benchmark.el`
   - Benchmark: `gptel-benchmark-principles.el`
   - Auto-workflow: `gptel-auto-workflow-strategic.el`, `gptel-auto-workflow-projects.el`, `gptel-auto-workflow-ontology-router.el`, `gptel-auto-workflow-evolution.el`
4. Occurrences range from 3-5
5. Some have category-based priority (lower keep-rate = higher priority): 3.5% (programming), 4.3% (agentic)
6. Trend windows span several days
7. No example reasons provided

I need to create a knowledge page with:
- Frontmatter
- Minimum 50 lines of content
- Concrete examples (code, tables, commands)
- Actionable patterns
- Cross-references
- Full markdown inline

Let me structure this:
1. Overview/summary of the pattern
2. Affected modules (table)
3. Common failure signatures
4. Why prompt failures cluster
5. Diagnostic patterns
6. Remediation patterns
7. Prevention patterns
8. Cross-references

Let me write this out comprehensively.