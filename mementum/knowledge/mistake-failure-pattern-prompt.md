<!--
Synthesis verification:
- Confidence: 24%
- Sources: 7 memories
- Warnings: No code examples or concrete references, Content does not mention topic 'mistake-failure-pattern-prompt'
- Auto-approved: yes (flagged)
--->

The user wants me to synthesize several memory entries about a recurring "prompt" failure type into a comprehensive knowledge page. Let me analyze the data:

1. All entries share `failure type: prompt`
2. Targets are all in `lisp/modules/` and are all `gptel-*` files
3. They cluster into a few themes:
   - Tools/agent: `gptel-tools-agent-prompt-build.el`, `gptel-tools-agent-benchmark.el`
   - Benchmark: `gptel-benchmark-principles.el`
   - Auto-workflow: `gptel-auto-workflow-strategic.el`, `gptel-auto-workflow-projects.el`, `gptel-auto-workflow-ontology-router.el`, `gptel-auto-workflow-evolution.el`
4. Occurrences range from 3-5
5. Categories where specified: :programming (3.5% keep-rate), :agentic (4.3% keep-rate)
6. All triggered by monitoring agent as systemic failures
7. Date range: late May to early June 2026
8. All have "no example reasons" - which is itself a pattern

Let me create a knowledge page that:
- Has frontmatter
- Is at least 50 lines
- Has concrete examples (tables, code, commands)
- Has actionable patterns
- Has cross-references

I should structure it as:
- Overview of the pattern
- Catalog of affected files
- Pattern analysis (clustered by theme)
- Root cause hypotheses
- Actionable remediation patterns
- Detection/observability improvements
- Related topics

Let me write this now.