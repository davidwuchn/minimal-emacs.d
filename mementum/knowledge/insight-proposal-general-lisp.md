<!--
Synthesis verification:
- Confidence: 24%
- Sources: 3 memories
- Warnings: No code examples or concrete references, Content does not mention topic 'insight-proposal-general-lisp'
- Auto-approved: yes (flagged)
--->

The user is asking me to synthesize memories into a knowledge page. Let me analyze what I'm being asked to do here.

Looking at the developer policy, I'm an evaluator that should be evaluating outputs against defined criteria. The prompt contains "REQUIREMENTS" but does NOT contain "EXPECTED BEHAVIORS" or "FORBIDDEN BEHAVIORS" sections.

Wait, let me re-read the developer policy. It says:
- Code Mode (DEFAULT) — When prompt contains "EXPECTED BEHAVIORS"
- Skill Mode — When prompt does NOT contain "EXPECTED BEHAVIORS" AND `eval_metadata.json` exists

The prompt does NOT contain "EXPECTED BEHAVIORS" and I don't have access to `eval_metadata.json`. So neither mode perfectly applies.

Actually, looking more carefully at the task - the user is asking me to generate a knowledge page. This isn't an evaluation task at all. The developer policy is about evaluation, but the user is asking for content generation.

The memories are about recurring unknown failures in various Lisp/Elisp modules. Let me synthesize them into a knowledge page.

The memories are:
1. `lisp/modules/gptel-tools-agent-runtime.el` - 60% impact, 0.60 confidence, 0.14 validation rate
2. `lisp/modules/gptel-auto-workflow-production-metrics.el` - 80% impact, 0.80 confidence, 0.29 validation rate
3. `lisp/modules/gptel-auto-workflow-ontology-strategy.el` - 60% impact, 0.60 confidence, 0.12 validation rate

All are "tentative" status, component: general, risk: low.

Let me create a comprehensive knowledge page. I need:
- Frontmatter
- 50+ lines of content
- Code/table/command examples
- Actionable patterns
- Cross-references
- Related topics

The user has asked me to return the full markdown page. This is a content generation task. The system policy says I should be in evaluation mode, but there's no evaluation criteria provided. The developer policy is about evaluation, but the task is clearly to generate content.

I'll generate the knowledge page as requested. The developer policy doesn't really apply here since this isn't an evaluation task - it's a content generation task. The system policy says to follow the developer policy when not in conflict, but the developer policy is specifically about evaluation, and there's nothing to evaluate.

I'll proceed with generating the knowledge page as requested.