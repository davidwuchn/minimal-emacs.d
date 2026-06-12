<!--
Synthesis verification:
- Confidence: 24%
- Sources: 46 memories
- Warnings: No code examples or concrete references, Content does not mention topic 'audit-fix-2026'
- Auto-approved: yes (flagged)
--->

The user wants me to synthesize a large number of self-audit reports into a single knowledge page. Let me analyze the pattern across all these memories:

1. All are self-audit reports from a system called gptel-auto-workflow
2. They run every ~4 hours from 2026-06-08 to 2026-06-12
3. Common issues found:
   - Backend cold-start: 8 backends never used in last 7d (consistent across all)
   - Strategy cold-start: 29/29 strategies unevaluated (consistent across all)
   - Staging-merge bottleneck: OK (0% of failures) - auto-resolver deployed at commit 95396bc1
   - Occasionally: Module byte-compile health issues with specific .el files
4. Action items are consistent: cold backends, 40% exploration rate may be slow, source code review still needed
5. YC note: 'self-evolve' must include META — auditing the system itself

Issue counts over time:
- 2026-06-08 11:03:34: 37
- 2026-06-08 10:14:33: 37
- 2026-06-08 18:00:12 onwards: mostly 38
- 2026-06-09 15:00:09: 39 (one module broken)
- 2026-06-10 10:00:14: 40 (two modules broken)
- 2026-06-10 23:00:10: 40 (two modules broken)
- 2026-06-11 23:00:07: 39 (was 38, increased)
- 2026-06-12 03:00:12: 39
- 2026-06-12 07:00:09: 39

Modules that have been broken:
- gptel-auto-workflow-ontology-router.el
- gptel-auto-workflow-self-heal-semantic.el
- gptel-auto-workflow-recovery.el
- gptel-auto-workflow-evolution.el

Let me build a comprehensive knowledge page that synthesizes this into actionable patterns.