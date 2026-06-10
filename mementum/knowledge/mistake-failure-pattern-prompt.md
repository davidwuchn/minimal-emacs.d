<!--
Synthesis verification:
- Confidence: 80%
- Sources: 7 memories
- Warnings: No code examples or concrete references
- Auto-approved: yes (passed)
--->

The user wants me to synthesize multiple memory records about a specific failure pattern (`mistake-failure-pattern-prompt`) into a comprehensive knowledge page. Let me analyze the memories:

1. All entries are classified as `failure-type: prompt`
2. They all target files in `lisp/modules/gptel-*.el` - specifically auto-workflow and agent-related modules
3. The targets include:
   - gptel-tools-agent-prompt-build.el (4 occurrences)
   - gptel-tools-agent-benchmark.el (5 occurrences, :programming category, 3.5% keep-rate)
   - gptel-benchmark-principles.el (3 occurrences)
   - gptel-auto-workflow-strategic.el (3 occurrences, :agentic, 4.3% keep-rate)
   - gptel-auto-workflow-projects.el (3 occurrences, :agentic, 4.3% keep-rate)
   - gptel-auto-workflow-ontology-router.el (3 occurrences)
   - gptel-auto-workflow-evolution.el (3 occurrences)

The pattern shows that "prompt" failures are concentrated in gptel-related modules, particularly auto-workflow and agent files. The keep-rates are very low (3.5-4.3%) indicating these are low-value outputs that are being filtered.

I need to create a comprehensive knowledge page with:
- Frontmatter
- 50+ lines of content
- Concrete examples (code, tables, commands)
- Actionable patterns
- Cross-references to related topics
- Full markdown page

Let me build this thoughtfully. The topic is about a prompt failure pattern, so I should focus on:
- What the pattern is
- Which files are affected
- The metrics (keep-rates, occurrences)
- Root cause analysis
- Actionable patterns to address
- Related patterns

Let me draft this now.