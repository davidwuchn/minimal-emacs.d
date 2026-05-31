<!--
Synthesis verification:
- Confidence: 24%
- Sources: 3 memories
- Warnings: No code examples or concrete references, Content does not mention topic 'toctou-buffer-guard'
- Auto-approved: yes (flagged)
--->

<think>
The user wants me to create a knowledge page about TOCTOU (Time-of-Check-Time-of-Use) buffer guards in Emacs, specifically for async workflows. Let me synthesize the memories into a comprehensive knowledge page.

Key points from the memories:
1. TOCTOU race conditions when iterating over buffers in async Emacs workflows
2. Buffers can be killed between iterator's check and lambda execution
3. Defense-in-depth pattern: nil guard + buffer-live-p check + error wrapping
4. Applied in gptel-auto-workflow-projects.el
5. Specific functions: `gptel-auto-workflow-list-project-buffers`, `gptel-auto-workflow-clear-executor-overlays`

I need to:
1. Write minimum 50 lines of actual content
2. Include concrete examples (code, tables, commands)
3. Include actionable patterns
4. Cross-reference to related topics
5. Return full markdown page

Let me structure this knowledge page:

1. Frontmatter
2. Introduction - what is TOCTOU in Emacs
3. The Problem - async buffer iteration issues
4. The Solution Pattern - defense-in-depth
5. Code Examples - showing the pattern
6. Real-world applications (gptel-auto-workflow)
7. Checklist for implementation
8. Related topics

Let me write comprehensive content for each section.
</think>