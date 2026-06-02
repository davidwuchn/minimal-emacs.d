# Skill Level Frontmatter

## What
Added `level:` frontmatter to 25 skills using the three-layer taxonomy from skill graph architecture.

## Classification

### Atoms (13 skills) — Single focused capabilities (~99% reliability)
- `hashline-edit` — Content-addressed line editing
- `elisp-expert` — Emacs Lisp code generation
- `clojure-expert` — Clojure code generation
- `elisp-debug` — Interactive debugging
- `elisp-validator` — Code validation
- `elisp-replace` — Structural replacement
- `provider-error-analyzer` — Error analysis
- `agent-prompts` — Prompt templates
- `tool-prompts` — Tool prompts
- `reddit` — Reddit API
- `requesthunt` — Request scraping
- `seo-geo` — SEO optimization
- `benchmark-llm-prompts` — Benchmark prompts

### Molecules (11 skills) — Hardcoded atom sequences (~90% reliability)
- `elisp-refactor` — Analyze → extract → verify
- `elisp-discover` — Discover → understand
- `benchmark-improver` — Detect → improve
- `eight-keys-grader` — Read → analyze → score
- `evolution-patterns` — Learn → apply
- `meta-harness-proposer` — Propose → design
- `research-digest` — Digest → extract
- `researcher-prompt` — Research → synthesize
- `sandbox-profiles` — Define → enforce
- `skill-eval` — Validate → measure
- `strategy-proposer` — Generate → evaluate

### Compounds (2 skills) — Human-driven workflows (~70% reliability)
- `auto-workflow` — Full pipeline orchestration
- `ov5` — System-wide architecture

## Verification
```bash
for f in assistant/skills/*/SKILL.md; do grep "^level:" "$f"; done
```
All 25 skills have `level:` field.

## Next Steps
1. Parse `level:` in skill loading code (`gptel-tools-agent-prompt-build.el` or skill router)
2. Use level for token budget allocation (atoms get more budget per-step, compounds get less)
3. Track per-level success rates in AutoTTS traces
4. Use level for skill graph construction (atoms = nodes, molecules = edges, compounds = workflows)

## Related
- `mementum/memories/skill-graph-three-layer-taxonomy.md`
- `mementum/memories/ov5-skill-graph-self-evolution.md`
