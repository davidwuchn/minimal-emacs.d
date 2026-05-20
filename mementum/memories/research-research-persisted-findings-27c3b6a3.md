# Research: 2026-05-17 19:23

**Strategy:** persisted-findings
**Findings hash:** 27c3b6a3c7bd7c27cc94948af5b66aa278fbc0d7
**Targets:** lisp/modules/gptel-benchmark-core.el, lisp/modules/gptel-auto-workflow-strategic.el, lisp/modules/gptel-tools-agent.el
**Outcome:** 3/14 kept (21%)

**Raw Findings:**

Researcher result for task: External research turn 1/6

## External Sources (Pre-Fetched Repo Analysis)

### Tier 1 — Directly Applicable

- **davidwuchn/nucleus** — λ notation compresses prompts to fraction of tokens with zero information loss. Uses mathematical symbols with high training weight (φ, λ, ∃, ∀) to shift pattern-matching toward formal reasoning. **Apply**: Replace verbose prose prompts with λ notation in `gptel-auto-workflow-*.el` — e.g., `λ adapt(x). unknown(x) → illuminate(x)` instead of paragraphs.

- **davidwuchn/mementum** — Git-native memory protocol with feed-forward: `store(x) → memories/YYYY-MM-DD-{slug}-{symbol}.md`. Temporal search via `git log`, semantic via `git grep`. **Apply**: Implement `gptel-memory-store` that writes to `memories/` with structured filenames, `gptel-memory-recall` that queries git history.

- **davidwuchn/context-mode** — "Think in Code" paradigm: LLM generates analysis scripts instead of processing data. One `ctx_execute()` replaces 10 tool calls, saves 100x context. Output compression: terse fragments, drop filler, ~65-75% reduction. **Apply**: Add `gptel-script-executor` tool that runs generated elisp analysis scripts, `gptel-output-compress` that strips hedging/filler from responses.

- **davidwuchn/efrit** — Zero Client-Side Intelligence: pure executor, all cognition delegated to Claude. Verification gates: `make compile` must pass before reporting completion. Beads (`bd`) for issue tracking. **Apply**: Add verification gate to `gptel-auto-workflow` — run `checkdoc` + byte-compile before marking experiment complete.

### Tier 2 — Agent Architecture

- **davidwuchn/genesis-agent** — Self-modification loop: read own AST → plan changes → test in sandbox → snapshot with git → apply only if tests pass. 66 deterministic checks (AST parse, import resolution, exit codes). Emotional steering: 5 dimensions influence prompt tone. **Apply**: Implement `gptel-self-modify` that reads own source, proposes changes, tests in `emacs --batch`, commits only on pass.

- **davidwuchn/gastown** — Multi-agent communication: `gt nudge` for immediate delivery, `gt mail` for persistent messages. Context recovery: `gt prime` reloads role context after compaction. **Apply**: Add `gptel-agent-nudge` for inter-agent messaging, `gptel-prime` for context reload after conversation compaction.

- **davidwuchn/symphony** — Worktree isolation: each autonomous run in isolated git worktree. Proof of work: CI status + PR review + complexity analysis. **Apply**: Create `gptel-worktree-run` that spawns experiments in isolated worktrees, preventing cross-contamination.

### Tier 3 — Infrastructure Patterns

- **davidwuchn/LLMLingua** — Prompt compression up to 20x using small LM (GPT2-small) to identify non-essential tokens. LLMLingua-2: 3x-6x faster, task-agnostic. **Apply**: Integrate LLMLingua as pre-processing step for long prompts in `gptel-send`, reduce token costs.

- **davidwuchn/ATLAS** — V3 Pipeline: PlanSearch (constraint-driven planning) → DivSampling (diverse candidates) → Budget Forcing (token allocation) → PR-CoT Repair (self-generated tests). Geometric Lens: energy-based scoring without external oracles. **Apply**: Implement multi-phase generation in `gptel-auto-workflow`: plan → generate diverse → score → repair loop.

- **davidwuchn/Ori-Mnemos** — Recursive Memory Harness: retrieval walks graph (PageRank at α=0.45), unresolved queries recurse into sub-questions. Q-Value reranking: notes earn scores from session outcomes. Three decay rates: identity (0.1x), knowledge (1.0x), operations (3.0x). **Apply**: Add `gptel-memory-qvalue` that tracks retrieval usefulness, `gptel-memory-decay` with ACT-R equations.

- **davidwuchn/GitNexus** — Impact analysis before editing: `gitnexus_impact({target: "symbolName", direction: "upstream"})`. Safe rename via graph edits. **Apply**: Add `gptel-impact-check` that runs `Code_Usages` before edits, warns on HIGH/CRITICAL blast radius.

### Tier 4 — Cross-Pollination


...[Result too large, truncated. Full result saved to: /home/davidwu/.emacs.d/tmp/gptel-subagent-result-rfB5Nm.txt. Use Read tool if you need more]...

---

Researcher result for task: External research turn 1/6

## External Sources (Pre-Fetched Repo Analysis)

### Tier 1 — Directly Applicable

- **davidwuchn/nucleus** — λ notation compresses prompts to fraction of tokens with zero information loss. Uses mathematical symbols with high training weight (φ, λ, ∃, ∀) to shift pattern-matching toward formal reasoning. **Apply**: Replace verbose prose prompts with λ notation in `gptel-auto-workflow-*.el` — e.g., `λ adapt(x). unknown(x) → illuminate(x)` instead of paragraphs.

- **davidwuchn/mementum** — Git-native memory protocol with feed-forward: `store(x) → memories/YYYY-MM-DD-{slug}-{symbol}.md`. Temporal search via `git log`, semantic via `git grep`. **Apply**: Implement `gptel-memory-store` that writes to `memories/` with structured filenames, `gptel-memory-recall` that queries git history.

- **davidwuchn/context-mode** — "Think in Code" paradigm: LLM generates analysis scripts instead of processing data. One `ctx_execute()` replaces 10 tool calls, saves 100x context. Output compression: terse fragments, drop filler, ~65-75% reduction. **Apply**: Add `gptel-script-executor` tool that runs generated elisp analysis scripts, `gptel-output-compress` that strips hedging/filler from responses.

- **davidwuchn/efrit** — Zero Client-Side Intelligence: pure executor, all cognition delegated to Claude. Verification gates: `make compile` must pass before reporting completion. Beads (`bd`) for issue tracking. **Apply**: Add verification gate to `gptel-auto-workflow` — run `checkdoc` + byte-compile before marking experiment complete.

### Tier 2 — Agent Architecture

- **davidwuchn/genesis-agent** — Self-modification loop: read own AST → plan changes → test in sandbox → snapshot with git → apply only if tests pass. 66 deterministic checks (AST parse, import resolution, exit codes). Emotional steering: 5 dimensions influence prompt tone. **Apply**: Implement `gptel-self-modify` that reads own source, proposes changes, tests in `emacs --batch`, commits only on pass.

- **davidwuchn/gastown** — Multi-agent communication: `gt nudge` for immediate delivery, `gt mail` for persistent messages. Context recovery: `gt prime` reloads role context after compaction. **Apply**: Add `gptel-agent-nudge` for inter-agent messaging, `gptel-prime` for context reload after conversation compaction.

- **davidwuchn/symphony** — Worktree isolation: each autonomous run in isolated git worktree. Proof of work: CI status + PR review + complexity analysis. **Apply**: Create `gptel-worktree-run` that spawns experiments in isolated worktrees, preventing cross-contamination.

### Tier 3 — Infrastructure Patterns

- **davidwuchn/LLMLingua** — Prompt compression up to 20x using small LM (GPT2-small) to identify non-essential tokens. LLMLingua-2: 3x-6x faster, task-agnostic. **Apply**: Integrate LLMLingua as pre-processing step for long prompts in `gptel-send`, reduce token costs.

- **davidwuchn/ATLAS** — V3 Pipeline: PlanSearch (constraint-driven planning) → DivSampling (diverse candidates) → Budget Forcing (token allocation) → PR-CoT Repair (self-generated tests). Geometric Lens: energy-based scoring without external oracles. **Apply**: Implement multi-phase generation in `gptel-auto-workflow`: plan → generate diverse → score → repair loop.

- **davidwuchn/Ori-Mnemos** — Recursive Memory Harness: retrieval walks graph (PageRank at α=0.45), unresolved queries recurse into sub-questions. Q-Value reranking: notes earn scores from session outcomes. Three decay rates: identity (0.1x), knowledge (1.0x), operations (3.0x). **Apply**: Add `gptel-memory-qvalue` that tracks retrieval usefulness, `gptel-memory-decay` with ACT-R equations.

- **davidwuchn/GitNexus** — Impact analysis before editing: `gitnexus_impact({target: "symbolName", direction: "upstream"})`. Safe rename via graph edits. **Apply**: Add `gptel-impact-check` that runs `Code_Usages` before edits, warns on HIGH/CRITICAL blast radius.

### Tier 4 — Cross-Pollination


...[Result too large, truncated. Full result saved to: /home/davidwu/.emacs.d/tmp/gptel-subagent-result-rfB5Nm.txt. Use Read tool if you need more]...

**Digested Insights:**

[No digestion performed]

**Meta-learning:** Research quality measured by downstream experiment success.

---
*Generated by auto-workflow*
