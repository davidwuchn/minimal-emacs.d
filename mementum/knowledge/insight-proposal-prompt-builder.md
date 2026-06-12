<!--
Synthesis verification:
- Confidence: 80%
- Sources: 14 memories
- Warnings: No code examples or concrete references
- Auto-approved: yes (passed)
--->

We need synthesize memories into a knowledge page. Topic insight-proposal-prompt-builder. Need complete markdown page inline, frontmatter, min 50 lines actual content, concrete examples code/tables/commands, actionable patterns, cross-references.

We have raw insights: each is a proposal by monitoring agent to address recurring empty-hypothesis failures in various modules/staging components. Component prompt-builder. Expected impact, confidence, risk, validation rate, status tentative. Need synthesize into a knowledge page about prompt-builder failures. Need produce full markdown.

We need to be careful: user says "Minimum 50 lines of actual content". We'll produce substantial sections. Include tables with module, failure type, confidence, validation rate, priority. Include patterns: root cause taxonomy (empty-hypothesis generated when context insufficient, instruction too open-ended, missing few-shot examples, prompt length/context window, etc.), actionable patterns: guardrails, validation gates, prompt templates, auto-retry, metrics, logging. Code examples likely Emacs Lisp functions (since modules are .el). Could show example of prompt builder function with guardrails, and a Makefile command? Commands maybe to query logs.

Need cross-references to related topics: staging-verification, staging-scope, staging-review, gptel-tools-agent-runtime, gptel-tools-agent-prompt-build, gptel-tools-agent-experiment-core, gptel-benchmark-subagent, gptel-auto-workflow-strategic, prompt engineering, guardrails, validation gates, empty-hypothesis failure mode.

Need not describe what we would write; write page itself. Start with frontmatter.

Need ensure not too generic but concrete. Let's craft a markdown page.

Sections:
- Executive summary
- Failure Signature Catalog (table)
- Root Cause Patterns (with code examples for before/after prompts)
- Actionable Patterns
  1. Structured prompt builder with mandatory sections
  2. Empty-hypothesis guard and auto-retry
  3. Validation gate before downstream staging
  4. Validation rate threshold promotion
  5. Module-specific prompt tuning
- Implementation Example: prompt-builder.el function
- Operational commands
- Promotion criteria (validation rates)
- Related

Need maybe include a concrete elisp function `my-prompt-builder-build` with `:required-context` and `:fallback` and `:examples`. Also include a validation gate function `my-prompt-builder-validate-hypothesis`. And a command example to grep logs for empty-hypothesis failures.

Let's write enough lines. Ensure actual content lines >= 50. We can produce ~100 lines. Use fenced code and tables count as lines maybe. Should be actual content.

Need cross-references to related topics in a list. Also need links? Could just bullet names.

Need keep frontmatter. Title maybe "Insight Proposal: Prompt Builder Empty-Hypothesis Failures".

Let's draft.