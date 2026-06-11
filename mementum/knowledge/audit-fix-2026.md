<!--
Synthesis verification:
- Confidence: 12%
- Sources: 39 memories
- Warnings: No code examples or concrete references, Content does not mention topic 'audit-fix-2026', Very short content (27 lines)
- Auto-approved: yes (flagged)
--->

The user wants me to synthesize many similar self-audit reports into a single knowledge page. Let me analyze the patterns:

1. All reports have ~38 issues (some 37, 39, 40)
2. Common issues:
   - Backend cold-start: 8 backends never used in 7d
   - Strategy cold-start: 29 strategies unevaluated
   - Staging-merge bottleneck: OK (0% of failures), auto-resolver deployed (commit 95396bc1)
   - Action items repeated
3. Some reports (occasional) have additional module byte-compile issues:
   - 2026-06-10T23:00:10: 2 broken modules (ontology-router, self-heal-semantic)
   - 2026-06-10T23:00:09: 1 broken (ontology-router)
   - 2026-06-10T15:00:07: 1 broken (recovery)
   - 2026-06-10T10:00:14: 2 broken (recovery, self-heal-semantic)
   - 2026-06-09T15:00:09: 1 broken (evolution)

The reports span 2026-06-08 to 2026-06-11.

Let me create a comprehensive knowledge page with:
- Frontmatter
- Overview/summary
- Pattern analysis
- Tables showing the data
- Concrete examples
- Actionable patterns
- Cross-references

Let me write this now.