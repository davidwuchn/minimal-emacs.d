<!--
Synthesis verification:
- Confidence: 12%
- Sources: 3 memories
- Warnings: No code examples or concrete references, Content does not mention topic 'toctou-buffer-guard', Very short content (28 lines)
- Auto-approved: yes (flagged)
--->

<think>
The user wants me to create a knowledge page about TOCTOU (Time-Of-Check-Time-Of-Use) buffer guards in Emacs. Let me synthesize the memories provided into a comprehensive knowledge page.

Key points from the memories:
1. TOCTOU race conditions when iterating over buffers in async Emacs workflows
2. Buffers can be killed between iterator's `buffer-live-p` check and lambda's `with-current-buffer` call
3. Solution: Add secondary `buffer-live-p` guard at the use site
4. Pattern includes: nil check + liveness check + error wrapping
5. Applied in gptel-auto-workflow-projects.el
6. Defense-in-depth approach

I need to create a comprehensive page with:
- Minimum 50 lines
- Concrete examples (code, tables, commands)
- Actionable patterns
- Cross-references to related topics
- Full markdown format with frontmatter

Let me structure this properly:

1. Frontmatter
2. Overview/Introduction
3. The Problem (TOCTOU explanation)
4. The Pattern (with code examples)
5. Implementation Examples
6. Best Practices
7. Related Topics
</think>