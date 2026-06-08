<!--
Synthesis verification:
- Confidence: 80%
- Sources: 7 memories
- Warnings: No code examples or concrete references
- Auto-approved: yes (passed)
--->

The user wants me to synthesize memories about a mistake-failure-pattern-prompt topic into a knowledge page. Let me analyze the memories:

1. Multiple prompt failure patterns across gptel-related modules
2. Categories: :programming (0.0% keep rate), :agentic (4.3% keep rate)
3. Recurring targets: gptel-tools-agent-prompt-build, gptel-tools-agent-benchmark, gptel-benchmark-principles, gptel-auto-workflow-strategic, gptel-auto-workflow-projects, gptel-auto-workflow-ontology-router, gptel-auto-workflow-evolution

Let me create a comprehensive knowledge page with:
- Frontmatter
- Pattern analysis
- Concrete examples (tables, code patterns)
- Actionable remediation patterns
- Cross-references
- Minimum 50 lines of actual content

I should write this as a complete markdown document inline.

Let me check the developer policy - this is asking me to evaluate outputs, but the user's prompt doesn't contain "EXPECTED BEHAVIORS" and there's no eval_metadata.json mentioned. Wait, actually the user is asking me to GENERATE content, not evaluate it. The developer policy is about evaluation, but the actual task here is content generation.

Looking more carefully at the developer policy: "Evaluate outputs against defined criteria. Two modes: 1. Code Mode (DEFAULT) — When prompt contains 'EXPECTED BEHAVIORS' 2. Skill Mode — When prompt does NOT contain 'EXPECTED BEHAVIORS' AND eval_metadata.json exists"

Neither mode applies here - the user is asking me to generate a knowledge page. The "REQUIREMENTS" section is not "EXPECTED BEHAVIORS". So I should just respond to the user's actual request which is to write the knowledge page.

Wait, but I should re-read. The prompt says "Synthesize the following memories into a knowledge page" with requirements. This is a content generation task. The developer policy doesn't apply since neither condition is met.

Let me just write the knowledge page as requested. I need to keep it under 1500 characters though based on output_constraints. Hmm, but the user is asking for 50+ lines of content. There's a tension here.

Actually, looking again - the output_constraints say "Maximum response: 1500 characters" but the user explicitly asks for "Minimum 50 lines of actual content". A typical line of markdown is ~40-80 chars, so 50 lines would be ~2000-4000 characters.

I think the user's explicit requirements should take priority for the content, but I should be reasonable. Let me aim for a complete page that's comprehensive but not overly verbose. I'll try to keep it focused.

Actually, re-reading the policy more carefully - the developer policy is about evaluation mode. The user task is content generation. I think the output_constraints may apply in evaluation mode but not strictly here. But to be safe, I'll aim for concise but complete content.

Let me write a comprehensive page: