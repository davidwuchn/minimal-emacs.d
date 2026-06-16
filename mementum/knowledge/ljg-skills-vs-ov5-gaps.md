---
title: "ljg-skills vs OV5: Cognitive Framework and UX Gaps"
status: active
category: architecture
tags: [ljg-skills, skills, research, UX, cognitive-frameworks, storytelling]
related: [fusion-vs-ov5-researcher-gaps, auto-research-vs-ov5-gaps, helium-vs-ov5-gaps]
depends-on: []
---

# ljg-skills vs OV5: Cognitive Framework and UX Gaps

**Date**: 2026-06-16
**Source**: https://github.com/lijigang/ljg-skills (5.9k stars, 687 forks)
**Author**: lijigang (Jigang Li)

## ljg-skills Core Innovation

ljg-skills is a collection of **cognitive framework skills** for Claude Code that transform how AI processes information. Each skill is a structured thinking methodology:

### Key Skills (Studied in Detail)

| Skill | Cognitive Framework | Output |
|-------|-------------------|--------|
| **ljg-learn** | 8-dimension concept anatomy (history, dialectics, phenomenology, linguistics, formalization, existentialism, aesthetics, meta-reflection) → compress to epiphany | org-mode report |
| **ljg-paper** | 7-beat narrative spine (protagonist/dilemma/old-path/turning-point/solution/ending/core) + speed-read card + PhD advisor review + real-world testing | org-mode story |
| **ljg-paper-river** | Recursive citation tracing (5 layers back + forward to latest) → problem evolution story | org-mode lineage |
| **ljg-think** | Vertical deep-drill to irreducible essence (layer by layer: mechanism → principle → axiom) | org-mode descent |
| **ljg-roundtable** | Multi-persona structured debate with truth-seeking moderator + ASCII framework diagrams per round | org-mode dialogue |

### Other Skills (From README)

| Skill | Purpose |
|-------|---------|
| **ljg-card** | Content → PNG visual cards (infographic, comic, visual notes, whiteboard, big-text) |
| **ljg-book** | Book dissection along problem axis + ASCII reference frame diagram |
| **ljg-library** | Book's unique "framing lens" explained + PNG library card |
| **ljg-qa** | Q-A chain extraction (Q cuts to core, A has 4 parts: conclusion/formalization/steps/boundaries) |
| **ljg-plain** | Rewrite for smart 12-year-old |
| **ljg-rank** | Find irreducible generators of a domain |
| **ljg-word** | Deep English word dissection (core semantics + epiphany moment) |
| **ljg-writes** | Writing engine — surgical dissection of a viewpoint (1000-1500 words) |
| **ljg-invest** | Investment analysis — is it an "order-creating machine"? |
| **ljg-read** | Companion reading — 3-layer translation (literal/faithful/elegant) + structure annotation |
| **ljg-relationship** | 5-layer structural diagnosis + psychoanalysis |
| **ljg-travel** | Deep cultural research for cities (org-mode + PNG card) |
| **ljg-skill-map** | Visual skill overview (scans all installed skills) |
| **ljg-present** | Presentation caster (Takahashi method, slogan style) |

### Workflows (Skill Chains)

| Workflow | Chain | Purpose |
|----------|-------|---------|
| **ljg-paper-flow** | paper → comic cards | Read paper + make comic cards in one command |
| **ljg-word-flow** | word → infographic | Deep word analysis + infographic in one command |

### Key Design Patterns

1. **Trigger words** — Natural language invocation: "解剖概念", "读论文", "追本", "圆桌讨论"
2. **Visual output** — PNG cards, ASCII diagrams, org-mode reports
3. **Storytelling** — Papers told as narratives, not reports
4. **Depth tools** — Vertical drilling, recursive tracing, multi-dimensional analysis
5. **Workflow composition** — Skills chain into workflows via `*-flow` suffix
6. **Denote integration** — All outputs saved as org-mode files with timestamps and tags

## OV5 Skills System (Current)

### Architecture

- **4 skill registries**: `assistant/skills/` (25), `packages/nucleus/skills/` (8), `.opencode/skills/` (7), `.agents/skills/` (4)
- **3-level hierarchy**: atoms → molecules → compounds
- **Ontology-driven routing**: Multi-dimensional scoring (task-overlap, category-fit, keyword-depth, exclusive-match, keep-rate, trend, confidence, holographic)
- **Skill graph**: Edge weights updated by experiment outcomes
- **Champion league**: Per-axis champions crowned by keep-rate
- **A/B testing**: LLM-generated variants tested via assertion checking
- **Governance**: Health scans, security audits, canary observation

### Key Skills

| Skill | Purpose |
|-------|---------|
| **auto-workflow** | Orchestrates entire pipeline (compound) |
| **researcher-prompt** | External research specialist (auto-evolves) |
| **elisp-expert** | Safe Elisp code generation |
| **elisp-validator** | Validates AI-generated Elisp |
| **hashline-edit** | Content-addressed line editing |
| **skill-eval** | Meta-skill: validates other skills |
| **eight-keys-grader** | Grading rubric (phi, fractal, epsilon, tau, pi, mu, exist, forall) |

### Strengths

1. **Automated evolution** — Skills evolve through experiment outcomes
2. **Ontology-driven routing** — Multi-dimensional scoring for automatic selection
3. **Skill graph** — Hierarchy with edge weights reinforced by success
4. **Governance** — Health scans, security audits, canary observation
5. **Mementum integration** — Skills feed into persistent memory system

### Weaknesses

1. **No cognitive frameworks** — Skills are technical (code generation, validation), not thinking methodologies
2. **No visual output** — Text only, no diagrams/cards/visualizations
3. **No storytelling** — Research findings extracted, not narrated
4. **No depth tools** — Breadth-first scanning, no vertical drilling
5. **No multi-perspective** — Single-model research, no structured debate
6. **No interactive UX** — No skill browser, no invocation feedback, no workflow composer

## Architecture Comparison

| Dimension | ljg-skills | OV5 Skills |
|-----------|------------|------------|
| **Skill type** | Cognitive frameworks (thinking methodologies) | Technical capabilities (code generation, validation) |
| **Invocation** | Natural language triggers ("解剖概念", "读论文") | Ontology routing (keyword matching + scoring) |
| **Output** | Visual (PNG cards, ASCII diagrams, org-mode) | Text only |
| **Composition** | Workflow chains (paper → cards) | Skill graph (atoms → molecules → compounds) |
| **Evolution** | Manual (human-edited SKILL.md) | Automated (A/B testing, champion league) |
| **Depth** | Vertical drilling, recursive tracing | Breadth-first scanning |
| **Perspective** | Multi-persona debate, 8-dimension analysis | Single-model research |
| **UX** | Trigger words, visual output, Denote integration | No interactive UI, no invocation feedback |
| **Storage** | org-mode files with timestamps/tags | mementum memories, skill graph EDN |

## Highest-Leverage Gaps for OV5

### Gap 1: Cognitive Framework Skills for Research
**Problem**: OV5 researcher does surface-level scanning (URL extraction, keyword matching). No deep analysis methodologies.
**ljg solution**: 8-dimension concept anatomy, 7-beat narrative spine, vertical deep-drill, recursive citation tracing.
**OV5 implementation**: Create research skills that wrap ljg frameworks:
- `concept-anatomy` — When researcher encounters new concept, run 8-dimension analysis (ljg-learn)
- `paper-storytelling` — When researcher reads paper, extract 7-beat narrative spine (ljg-paper)
- `citation-tracing` — When researcher finds key paper, trace 5 layers back + forward (ljg-paper-river)
- `deep-drill` — When researcher hits surface finding, drill to irreducible essence (ljg-think)
- `multi-perspective` — When researcher evaluates competing approaches, run structured debate (ljg-roundtable)

### Gap 2: Visual Output for Research
**Problem**: OV5 produces text-only research findings. No visualizations, diagrams, or cards.
**ljg solution**: PNG cards (infographic, comic, visual notes), ASCII diagrams (framework maps, knowledge networks), org-mode reports.
**OV5 implementation**: Add visual output to research pipeline:
- `research-card` — Generate PNG infographic card from research findings (ljg-card)
- `research-map` — Generate ASCII knowledge map showing concept relationships
- `research-report` — Generate org-mode report with structure annotation (ljg-read style)

### Gap 3: Interactive Skill Browser
**Problem**: Humans can't browse, search, or visualize the skill graph. Must use `M-x` commands or read files.
**ljg solution**: `ljg-skill-map` scans all installed skills and renders visual overview.
**OV5 implementation**: Create interactive skill browser:
- `skill-browser` — Emacs UI to browse/search/visualize skill graph
- `skill-invoke-feedback` — Show which skill was selected and why (routing scores)
- `skill-composer` — Interactive tool to compose skill chains (molecule builder)

### Gap 4: Natural Language Skill Invocation
**Problem**: Humans must know skill names or rely on automatic routing. No trigger-word discovery.
**ljg solution**: Natural language triggers: "解剖概念", "读论文", "追本", "圆桌讨论".
**OV5 implementation**: Add trigger-word system:
- `skill-triggers` — Map natural language phrases to skills
- `skill-discovery` — When user says "explain this concept", suggest `concept-anatomy` skill
- `skill-override` — Allow humans to explicitly invoke skills: "/skill concept-anatomy entropy"

### Gap 5: Workflow Composition
**Problem**: No interactive tool for humans to compose skill workflows. Skill graph is design-time only.
**ljg solution**: Workflow chains (paper → cards, word → infographic) via `*-flow` suffix.
**OV5 implementation**: Add workflow composition:
- `workflow-builder` — Interactive tool to chain skills into workflows
- `workflow-library` — Pre-built workflows (research-flow, paper-flow, concept-flow)
- `workflow-executor` — Execute workflow chains with intermediate outputs

### Gap 6: Multi-Persona Research
**Problem**: OV5 uses single-model research. No structured debate or multi-perspective analysis.
**ljg solution**: `ljg-roundtable` — 3-5 real historical figures debate with truth-seeking moderator, ASCII framework diagrams per round.
**OV5 implementation**: Add multi-persona research:
- `research-roundtable` — When evaluating competing approaches, run structured debate
- `research-panels` — Multiple models research same topic, fuse results (Fusion-inspired)
- `research-devil-advocate` — Explicitly generate counter-arguments to research findings

## Implementation Priority

1. **Cognitive framework skills** (Gap 1) — Highest impact for auto-research quality
   - Start with `paper-storytelling` (ljg-paper) — transforms research from extraction to narration
   - Then `citation-tracing` (ljg-paper-river) — adds depth to research
   - Then `concept-anatomy` (ljg-learn) — adds multi-dimensional analysis

2. **Natural language invocation** (Gap 4) — Improves human UX immediately
   - Add trigger-word mapping to skill frontmatter
   - Add skill discovery to gptel prompt processing
   - Allow explicit skill override via "/skill" command

3. **Visual output** (Gap 2) — Makes research more accessible
   - Add ASCII knowledge maps to research output
   - Add org-mode report generation
   - (Future) Add PNG card generation via ljg-card

4. **Interactive skill browser** (Gap 3) — Improves skill discoverability
   - Build Emacs UI for skill graph visualization
   - Add skill invocation feedback (show routing scores)
   - Add skill composer for molecule building

5. **Workflow composition** (Gap 5) — Enables complex research pipelines
   - Build workflow builder UI
   - Create pre-built workflows (research-flow, paper-flow)
   - Add workflow executor with intermediate outputs

6. **Multi-persona research** (Gap 6) — Adds depth to evaluation
   - Implement research-roundtable (ljg-roundtable adapted)
   - Integrate with Fusion multi-model dispatch
   - Add devil's advocate mode

## Strategic Insight

ljg-skills and OV5 skills solve **different problems**:
- **ljg-skills** optimizes **human cognition** — structured thinking methodologies for deep understanding
- **OV5 skills** optimizes **automated evolution** — skills that improve through experiment outcomes

**Integration opportunity**: Adopt ljg's cognitive frameworks as OV5 research skills. This gives OV5 both **depth** (8-dimension analysis, vertical drilling, recursive tracing) and **evolution** (automated skill improvement through experiments).

**Key insight**: The most valuable ljg skills for OV5 are not the visual output (PNG cards) but the **cognitive frameworks** (8-dimension anatomy, 7-beat narrative, vertical drilling). These transform research from surface-level extraction to deep understanding.

**UX insight**: ljg's trigger-word system ("解剖概念", "读论文") is more intuitive than OV5's ontology routing. Humans think in natural language, not keyword scores. Adding trigger-word discovery to OV5 would dramatically improve human-skill interaction.

## References

- ljg-skills repo: https://github.com/lijigang/ljg-skills
- ljg-learn SKILL.md: https://raw.githubusercontent.com/lijigang/ljg-skills/master/skills/ljg-learn/SKILL.md
- ljg-paper SKILL.md: https://raw.githubusercontent.com/lijigang/ljg-skills/master/skills/ljg-paper/SKILL.md
- ljg-paper-river SKILL.md: https://raw.githubusercontent.com/lijigang/ljg-skills/master/skills/ljg-paper-river/SKILL.md
- ljg-think SKILL.md: https://raw.githubusercontent.com/lijigang/ljg-skills/master/skills/ljg-think/SKILL.md
- ljg-roundtable SKILL.md: https://raw.githubusercontent.com/lijigang/ljg-skills/master/skills/ljg-roundtable/SKILL.md
- OV5 skills: `assistant/skills/`, `packages/nucleus/skills/`
- OV5 skill graph: `lisp/modules/gptel-auto-workflow-skill-graph.el`
- OV5 skill routing: `lisp/modules/skill-routing-onto.el`
