<!--
Synthesis verification:
- Confidence: 80%
- Sources: 7 memories
- Warnings: No code examples or concrete references
- Auto-approved: yes (passed)
--->

We need synthesize provided memories into a markdown knowledge page. Must be min 50 lines actual content, concrete examples (code, tables, commands), actionable patterns, cross-references. Return full markdown inline, not summary. Start with frontmatter. We need write a page about mistake-failure-pattern-prompt. We have memories: several prompt failures targeting gptel modules. Need infer patterns and create actionable content.

We must ensure >=50 lines content. Provide concrete examples: code snippets (Emacs Lisp gptel prompts), tables, commands. Include patterns, diagnostics, fixes. Cross-references to related topics.

We need produce final markdown page with frontmatter and full body. Let's craft thoroughly. Let's think about content structure.

Topic: mistake-failure-pattern-prompt. The memories indicate systemic prompt failures in gptel modules: gptel-tools-agent-prompt-build, gptel-tools-agent-benchmark, gptel-benchmark-principles, gptel-auto-workflow-strategic, gptel-auto-workflow-projects, gptel-auto-workflow-ontology-router, gptel-auto-workflow-evolution. Failure type prompt, occurrences 3-5, example reasons none, trend IDs. Category programming keep-rate 3.5%, agentic 4.3%, meaning low keep rate. Need patterns for why prompts fail, e.g. context length, ambiguous instructions, missing schema/examples, no validation, over/under specification, prompt drift. Actionable patterns: root-cause capture, prompt versioning, structured templates, runtime validation, fallback policies, telemetry. Since this is Emacs/gptel, code examples can be prompt template functions, checklist commands, Elisp for tracking.

Need make page useful. Title: "Prompt Failure Pattern in gptel Agent Workflows". status active, category knowledge, tags. Sections: Summary, Detected Signature, Root Cause Patterns, Diagnostic Checklist, Actionable Patterns, Implementation Templates, Operational Commands, Metrics & Dashboard, Related.

Concrete examples: table of failures. Elisp code for `gptel--prompt-failure-tracker`, `gptel-prompt-validate`. Also shell? Emacs commands? Use M-x gptel-prompt-audit etc. Tables for modules and occurrences, keep-rate.

Need ensure 50 lines actual content (not counting frontmatter? actual content). Let's aim 100+ lines.

Cross-references to related topics: "memory-management-context-window", "agentic-validation", "benchmark-keep-rate", "template-versioning", "auto-workflow-monitoring". Provide links.

Need not summarize. Write page. Must include full document body.

Let's draft. Need be concise but comprehensive.

Potential patterns: 
1. Missing concrete negative examples/reasons => failure reasons not captured. Use structured rejection taxonomy.
2. Prompts that generate prompts recursively (prompt-build) amplify small errors.
3. Benchmark prompts used as both test and spec, causing drift.
4. Strategic/project prompts span long context and degrade; keep-rate 4.3%. Need chunking.
5. Agentic prompts lack explicit validation step.

Actionable patterns:
- Record rejection reasons with `gptel-prompt-reason-capture`.
- Validate before execution with JSON schema guardrails.
- Use `must/must-not` lists.
- Keep prompt templates in versioned files; diff between trend IDs.
- Run `gptel-prompt-simulator` to replay prompt with frozen context.

Implementation templates: Elisp functions. Example prompt template with delimiters. Table mapping failure type to fix.

Operational commands: `M-x gptel-audit-prompt-failures`, `M-x gptel-compare-prompt-versions`, `M-x gptel-run-prompt-validation-suite`.

Metrics & Dashboard: keep-rate threshold, occurrences, trend id.

Let's write.

Need ensure content lines count. Let's count later. Write enough.

Be careful not to claim external info beyond memories; but we can synthesize and infer. That's okay.

Now produce final.