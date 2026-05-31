<!--
Synthesis verification:
- Confidence: 12%
- Sources: 3 memories
- Warnings: No code examples or concrete references, Content does not mention topic 'toctou-buffer-guard', Very short content (23 lines)
- Auto-approved: yes (flagged)
--->

<think>
The user wants me to synthesize memories about TOCTOU (Time-of-Check-Time-of-Use) buffer guards in Emacs into a comprehensive knowledge page. Let me create a detailed, actionable knowledge page with:

1. Frontmatter with proper metadata
2. At least 50 lines of actual content
3. Concrete code examples
4. Actionable patterns
5. Cross-references to related topics
6. Full markdown format

The topic is about handling race conditions when iterating over buffers in async Emacs workflows, specifically the TOCTOU problem where buffers can be killed between a liveness check and actual use.

Let me structure this comprehensively:

1. Introduction to TOCTOU in Emacs
2. The Problem Explained
3. Code Examples showing the race condition
4. The Solution Pattern (defense in depth)
5. Implementation Guidelines
6. Specific application in gptel-auto-workflow
7. Related Topics
8. Best Practices Checklist
</think>