<!--
Synthesis verification:
- Confidence: 24%
- Sources: 7 memories
- Warnings: No code examples or concrete references, Content does not mention topic 'mistake-failure-pattern-prompt'
- Auto-approved: yes (flagged)
--->

The user wants me to synthesize multiple memory entries about a specific mistake/failure pattern into a comprehensive knowledge page. Let me analyze the memories:

All memories share a common pattern:
- **Failure type:** prompt
- **Target:** Various `lisp/modules/gptel-*.el` files
- These are all related to gptel (an Emacs LLM client) modules
- Multiple occurrences across different files
- Some have categories (`:programming` with 3.5% keep-rate, `:agentic` with 4.3% keep-rate)
- Trend data shows recurring failures over time

Let me organize the targets:
1. `gptel-tools-agent-prompt-build.el` - 4 occurrences
2. `gptel-tools-agent-benchmark.el` - 5 occurrences, :programming (3.5%)
3. `gptel-benchmark-principles.el` - 3 occurrences
4. `gptel-auto-workflow-strategic.el` - 3 occurrences, :agentic (4.3%)
5. `gptel-auto-workflow-projects.el` - 3 occurrences, :agentic (4.3%)
6. `gptel-auto-workflow-ontology-router.el` - 3 occurrences
7. `gptel-auto-workflow-evolution.el` - 3 occurrences

Common themes:
- All are prompt-related failures
- All involve gptel modules
- Group into: gptel-tools-agent-*, gptel-benchmark-*, gptel-auto-workflow-*
- Keep-rates are low (3.5%, 4.3%) indicating high failure rates
- No example reasons captured (gap to address)
- Trends span late May through early June 2026

I need to write a comprehensive knowledge page that:
1. Has frontmatter
2. Is at least 50 lines
3. Has concrete examples
4. Has actionable patterns
5. Has cross-references
6. Returns full markdown

Let me build this out properly.