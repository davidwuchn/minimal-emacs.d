<!--
Synthesis verification:
- Confidence: 24%
- Sources: 4 memories
- Warnings: No code examples or concrete references, Content does not mention topic 'audit-fix-2026'
- Auto-approved: yes (flagged)
--->

The user wants me to synthesize memories into a knowledge page. The prompt doesn't contain "EXPECTED BEHAVIORS" so I should check if this is a grading task... but actually, looking at the prompt more carefully, this is a generation/synthesis task, not a grading task. The user is asking me to CREATE a knowledge page from memories.

The system prompt says to evaluate outputs against defined criteria, but this prompt is asking me to generate content, not evaluate it. The "REQUIREMENTS" section here are instructions for what to generate, not evaluation criteria in the EXPECTED BEHAVIORS format.

Wait, let me re-read the system prompt: "Code Mode (DEFAULT) — When prompt contains 'EXPECTED BEHAVIORS'". This prompt does not contain "EXPECTED BEHAVIORS". It contains "REQUIREMENTS" which is different.

But the system prompt says "ALWAYS check for 'EXPECTED BEHAVIORS' in the prompt first. If present, use Code Mode. NEVER look for eval_metadata.json when 'EXPECTED BEHAVIORS' is in the prompt."

Since there's no "EXPECTED BEHAVIORS" in the prompt, this is not Code Mode. And there's no eval_metadata.json mentioned. So... this doesn't match either mode.

Looking at the user's actual request, they're asking me to synthesize memories and write a knowledge page. This is a generation task, not an evaluation task. The system prompt is about evaluation, but the user is asking for generation.

I think the right approach is to recognize that the user wants me to GENERATE content. The "REQUIREMENTS" in the prompt are generation requirements (minimum 50 lines, concrete examples, etc.), not evaluation criteria.

I should just do what the user asks - synthesize the memories into a knowledge page. The system prompt's evaluation framework doesn't apply here because the user isn't asking me to evaluate something, they're asking me to create something.

Let me synthesize these memories. I have 4 self-audit reports:
- 2026-06-08T10:14:33 - 37 issues
- 2026-06-08T11:03:34 - 37 issues
- 2026-06-08T18:00:12 - 38 issues
- 2026-06-08T19:00:09 - 38 issues

All report the same issues:
- 8/8 backends cold (never used in 7 days)
- 29/29 strategies unevaluated
- Staging-merge auto-resolver deployed (commit 95396bc1)
- Action items: cold backend retry, 40% exploration rate, source code merge review

I need to create a knowledge page with:
1. Frontmatter (title, status, category, tags)
2. Minimum 50 lines of content
3. Concrete examples (code, tables, commands)
4. Actionable patterns
5. Cross-references to related topics
6. Full markdown page inline

Let me write this comprehensive knowledge page.