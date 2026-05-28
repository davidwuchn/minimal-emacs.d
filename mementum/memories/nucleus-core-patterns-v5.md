# Nucleus (Ouroboros V5) Core Patterns

## Meta-Architecture: Self-Evolving AI R&D Engine
- Closed-loop: research → prototype → test → decide → merge
- 1,159 experiments across 257 runs, 20.4% keep rate
- 2,013 tests pass before any merge, 24/7 autonomous

## 10 Core Patterns

### 1. Ouroboros Self-Evolution Loop
Pipeline runs every 4h (Linux) or 3x/day (macOS). Each run: select targets, research, experiment, grade, merge what improves. Strategy evolution feeds outcomes back into next cycle.

### 2. Eight Keys + Wu Xing Grading
φ vitality, fractal clarity, ε purpose, τ wisdom, π synthesis, μ directness, ∃ truth, ∀ vigilance. Wu Xing phases: Water→Wood→Fire→Earth→Metal→Water. Every experiment scored on all 8 axes.

### 3. Deterministic-First Architecture
`λ select(x). deterministic(x) > AI(x) | data(x) → compute > model`
Compute from frontier TSV data before calling AI. Hand-tuned chains beat aggregate ranking. AI analyzer only as emergency fallback.

### 4. Lambda Prompt Compression
4-5x token reduction using formal λ notation. All 4 major prompts compressed. `forge-lambda-fixed-point` decompiler as fallback. EDN prompt pipeline: deterministic plist→λ resolution.

### 5. Multi-Provider Routing (6 backends)
Keep-rate based: DeepSeek (25%) > MiniMax (16%) > moonshot > DashScope (0%) > CF-Gateway. Bayesian Thompson sampling. Auto-failover on transient errors. Provider blacklist rules.

### 6. Mementum Memory System
Three tiers: `state.md` (session continuity), `memories/` (atomic <200-word insights), `knowledge/` (synthesized pages: patterns, protocols, project facts). Confidence-tagged.

### 7. Marker-Based Tool System
Tools tagged with capabilities. Marker profiles for execution modes (headless, interactive, sandbox). Tool contract validation at startup. `nucleus-tools-with-marker` for capability-based tool selection.

### 8. Research Variants + Champion League
Multiple research prompt variants compete. Champion league with PCR (Probabilistic Champion Research): 20% explore, 80% exploit champion. Digest variants for finding synthesis.

### 9. Staged Worktree Pipeline
Isolated git worktrees per experiment. Staging→merge→verification pipeline. Auto-cleanup of old worktrees. No direct commits to main.

### 10. Skill Extraction from Experiments
Skills gate evolution on measurable improvement. Domain skills (tool-based: clojure-expert, reddit, seo-geo) vs Protocol skills (knowledge-based: elisp-expert, eight-keys-grader). `skill-eval` meta-skill validates via A/B experiments.

## Key Files
- `lisp/modules/nucleus-prompts.el` — Prompt loading, init composition
- `lisp/modules/gptel-auto-workflow-strategic.el` — Research, strategy evolution
- `lisp/modules/gptel-tools-agent-main.el` — Experiment loop orchestration
- `lisp/modules/gptel-benchmark-core.el` — Eight Keys scoring, trend analysis
- `lisp/modules/nucleus-tools.el` — Marker-based tool profiles
- `assistant/agents/` — 10 subagent definitions
- `assistant/skills/` — ~30 skills
- `assistant/strategies/` — Research variants, digest variants, prompt builders
