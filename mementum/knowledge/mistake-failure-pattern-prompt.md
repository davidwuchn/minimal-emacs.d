<!--
Synthesis verification:
- Confidence: 24%
- Sources: 7 memories
- Warnings: No code examples or concrete references, Content does not mention topic 'mistake-failure-pattern-prompt'
- Auto-approved: yes (flagged)
--->

The user wants me to synthesize multiple memory entries about a "prompt" failure type into a knowledge page. Let me analyze the data:

1. All entries share "Failure type: prompt"
2. Various targets in lisp/modules/ directory - all related to gptel system
3. Categories mentioned: :programming (keep-rate: 3.5%), :agentic (keep-rate: 4.3%)
4. Occurrences range from 3-5 per file
5. These are auto-workflow generated systemic failure detections

Key insights:
- Pattern targets gptel-related modules (gptel-tools-agent, gptel-benchmark, gptel-auto-workflow)
- All are "prompt" type failures - suggesting prompt engineering issues
- Low keep-rates (3.5%, 4.3%) suggest these generated content has low retention value
- Multiple files affected across the system

Let me create a comprehensive knowledge page that:
1. Has frontmatter
2. Documents the pattern
3. Shows concrete examples from the data
4. Provides actionable patterns
5. Cross-references related topics
6. Minimum 50 lines of content

I'll structure it as:
- Frontmatter
- Overview
- Pattern Analysis (with table of affected files)
- Failure characteristics
- Common indicators
- Diagnostic commands
- Actionable remediation patterns
- Related topics