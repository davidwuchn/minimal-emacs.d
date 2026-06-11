<!--
Synthesis verification:
- Confidence: 24%
- Sources: 10 memories
- Warnings: No code examples or concrete references, Content does not mention topic 'mistake-failure-pattern-empty'
- Auto-approved: yes (flagged)
--->

The user wants me to synthesize multiple memory entries about a pattern called "empty-hypothesis" into a comprehensive knowledge page. Let me analyze the patterns:

1. All entries share the failure type: `empty-hypothesis`
2. Targets fall into two categories:
   - Staging operations: `staging-verification`, `staging-scope`, `staging-review`
   - Specific lisp modules in `lisp/modules/` directory
3. Categories: `:programming` and `:agentic`
4. Keep-rates are very low (0.0% to 3.2%) - meaning outputs are rarely kept
5. Occurrences range from 3 to 12
6. "Example reasons" are all "none" - this is a key observation - the system can't articulate why failures occur
7. All detected by monitoring agent as systemic failures
8. Time range: early June 2026

Key insights to capture:
- "empty-hypothesis" means failures where no clear root cause was identified
- These are systemic, not one-off
- They cluster in specific areas (staging + gptel/auto-workflow modules)
- 0% keep-rate in many cases means outputs are entirely discarded
- The lack of example reasons is itself a meta-pattern

Let me build a comprehensive knowledge page with:
- Frontmatter
- Overview
- Pattern definition
- Affected targets (table)
- Category breakdown
- Trend analysis
- Actionable diagnostic patterns
- Prevention strategies
- Cross-references

I need to make sure to hit 50+ lines of actual content with concrete examples, tables, and code.