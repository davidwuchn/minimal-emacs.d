<!--
Synthesis verification:
- Confidence: 80%
- Sources: 3 memories
- Warnings: No code examples or concrete references
- Auto-approved: yes (passed)
--->

<think>
The user wants me to synthesize the provided memories into a comprehensive knowledge page about "toctou-buffer-guard" (Time-of-Check to Time-of-Use buffer guards in Emacs).

Let me analyze what I have:

1. **Core concept**: TOCTOU (Time-of-Check to Time-of-Use) race conditions when iterating over buffers in async Emacs workflows
2. **The problem**: Buffers can be killed between the iterator's `buffer-live-p` check and the lambda's `with-current-buffer` call
3. **The solution**: Defense-in-depth with multiple guards at the use site
4. **Applied patterns**: Various places in gptel-auto-workflow-projects.el

I need to create a comprehensive knowledge page with:
- Frontmatter
- Multiple sections
- Concrete code examples
- Tables
- Actionable patterns
- Cross-references

Let me structure this:

1. **Overview** - What is TOCTOU in Emacs buffer contexts
2. **The Problem** - Detailed explanation with code showing the race
3. **The Solution** - Defense-in-depth pattern
4. **Code Patterns** - Complete examples
5. **Anti-patterns** - What NOT to do
6. **Applied Examples** - Real-world applications
7. **Related Topics** - Cross-references

This should be comprehensive and at least 50 lines of actual content.
</think>