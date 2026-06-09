<!--
Synthesis verification:
- Confidence: 80%
- Sources: 38 memories
- Warnings: No code examples or concrete references
- Auto-approved: yes (passed)
--->

The user wants me to synthesize the provided memories into a knowledge page. The topic is "research-research-persisted". The requirements are:
1. Minimum 50 lines of actual content
2. Concrete examples (code, tables, commands)
3. Actionable patterns (not just descriptions)
4. Cross-references to related topics
5. Return the full markdown page directly in the final response
6. Start with frontmatter and include the full document body

I need to extract patterns from the research memories about the persisted research system. The memories show a research daemon/agent that performs external research, synthesizes findings, and produces structured digests. Key patterns I see across the memories:

1. **Own-repos-first research strategy** - Prioritizing davidwuchn/* repos before external sources, with budget allocation (e.g., 68% own repos, 21% external)
2. **Compact structured digest format** - Max 1200 chars, [deep-external] prefix, JSON metadata at end
3. **Research controller with EMA confidence** - Stop threshold (e.g., 65%, 75%), beta parameter for exploration, EMA tracking
4. **Source deviation detection** - Flagging when sources become "DEVIANT" and switching to NEW sources
5. **Three-tier memory/knowledge hierarchy** - state.md (working), memories (raw <200 words), knowledge (synthesized) from mementum
6. **Anti-pattern filtering** - Skipping already-covered topics (e.g., "agent-survey taxonomies (zeroclaw covers)")
7. **Local research fallback** - When daemon fails, produce local fallback context
8. **Probe-then-deep-read workflow** - 60s probe, 120s deep read
9. **Actionable application mapping** - Every finding includes "Apply to us" / "Implementation sketch" section
10. **GPTel FSM/state machine pattern** - Pause/resume multi-stage requests with serializable INFO plist
11. **Mementum protocol operations** - 7 operations: create, create-knowledge, update, delete, search, read, synthesize
12. **Research quality feedback loop** - Research hash linking outcomes back to research trace, results.tsv metadata

I need to write a comprehensive markdown page with frontmatter, sections with code examples, tables, and actionable patterns. Minimum 50 lines.

Let me structure the page:

Frontmatter:
- title: research-research-persisted
- status: active
- category: knowledge
- tags: [research, auto-workflow, gptel, mementum, synthesis]

Sections:
1. Overview / Research Pipeline Architecture
2. Source Strategy & Budgeting (with table of budget allocation)
3. Digest Format Specification (with code block showing exact format)
4. Controller Logic & Stop Conditions (with condition-case style logic or table)
5. Knowledge Storage Hierarchy (mementum 3-tier)
6. Actionable Patterns (with code examples)
   - Pattern 1: Probe-then-Deep-Read
   - Pattern 2: Deviation Detection & Source Switching
   - Pattern 3: Research-to-Experiment Traceability
   - Pattern 4: Local Fallback on Daemon Failure
   - Pattern 5: Compact Digest with JSON Metadata
7. Cross-References

I need to make sure there are concrete examples: code blocks, tables, commands.

Let me draft the content carefully to be over 50 lines and rich with specifics.

Counting lines:
- Frontmatter: ~5 lines
- Title: 1
- Overview: ~10 lines
- Source Strategy: ~15 lines with table
- Digest Format: ~20 lines with code block
- Controller Logic: ~15 lines with table
- Storage Hierarchy: ~10 lines
- Actionable Patterns: ~30 lines with code
- Related: ~5 lines

Total should be well over 50 lines.

Let me write it now.