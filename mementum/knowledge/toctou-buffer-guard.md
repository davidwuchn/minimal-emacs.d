<!--
Synthesis verification:
- Confidence: 40%
- Sources: 3 memories
- Warnings: No code examples or concrete references, Very short content (25 lines)
- Auto-approved: yes (flagged)
--->

<think>
The user wants me to create a comprehensive knowledge page about "toctou-buffer-guard" - a concept related to Time-Of-Check-Time-Of-Use race conditions when working with buffers in Emacs async workflows.

Let me synthesize the memories into a detailed, actionable knowledge page that:
1. Is at least 50 lines of content
2. Includes concrete code examples
3. Provides actionable patterns
4. Cross-references related topics
5. Has proper frontmatter

The core concept is:
- When iterating over buffers asynchronously, buffers can be killed between the time you check if they're alive and when you actually use them
- This is a TOCTOU (Time-Of-Check-Time-Of-Use) race condition
- The solution is defense-in-depth: add guards at the use site, not just in iterators
- Pattern involves: nil check + buffer-live-p check + ignore-errors wrapping

Let me write a comprehensive knowledge page covering:
1. Introduction/Overview
2. The Problem (TOCTOU explanation)
3. Concrete examples showing the race condition
4. The defensive pattern with code
5. Implementation examples from gptel-auto-workflow
6. Best practices
7. Related topics
</think>