<!--
Synthesis verification:
- Confidence: 12%
- Sources: 3 memories
- Warnings: No code examples or concrete references, Content does not mention topic 'toctou-buffer-guard', Very short content (17 lines)
- Auto-approved: yes (flagged)
--->

<think>
The user wants me to synthesize the provided memories about TOCTOU buffer guards into a comprehensive knowledge page. Let me analyze the memories:

1. Core concept: TOCTOU (Time-Of-Check-Time-Of-Use) race conditions in Emacs when iterating over buffers
2. The problem: Buffers can be killed between the iterator's `buffer-live-p` check and the lambda's execution
3. The solution: Defense-in-depth pattern with multiple guards
4. Applications: Applied in gptel-auto-workflow-projects.el in multiple functions

I need to create a comprehensive, detailed knowledge page with:
- Minimum 50 lines
- Concrete code examples
- Tables and patterns
- Cross-references
- Full markdown with frontmatter

Let me write this out comprehensively.
</think>