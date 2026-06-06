---
valid-from: 2026-06-06T03:20
---

# Research: 2026-06-06 03:20

**Strategy:** none
**Findings hash:** b8bd12ecbc1dde6035ea09257e6faf82bc0d574e
**Targets:** test.el
**Outcome:** 1/1 kept (100%)

**Raw Findings:**

## Research Priorities (from Ontology × AutoTTS × AutoGo)
Focus research on these categories:
  [:programming] Critical: 0% keep-rate after 28 experiments — needs investigation
  [:agentic] Critical: 3% keep-rate after 69 experiments — needs investigation

Produce category-specific findings — not global recommendations.

> Project: /home/davidwu/.emacs.d/
> Updated: 2026-06-06 03:07

Researcher result for task: External research turn 1/4

<think>
The user has provided a complex research prompt. Let me parse what's actually being asked:

1. The system prompt establishes me as a research and synthesis agent
2. The user message is a detailed prompt for "Auto-Workflow Researcher" 
3. The task is to do external research on:
   - davidwuchn/nucleus (AI prompting framework)
   - davidwuchn/mementum (Git-based AI memory)
   - davidwuchn/gptel (LLM backend integration)
4. Plus general research on AI agent patterns
5. Output should be a compact digest under 1200 chars
6. Must start with own repos (68% own repos, 21% external)
7. End with JSON metadata

Key constraints:
- Max 1200 chars for the digest
- 68% own repos focus
- 21% external
- Must include `[deep-external]` prefix on findings
- End with JSON metadata
- Avoid topics already in "Previously Discovered Insights"
- Focus on novel patterns

Let me check the phase checklist:
1. Mode: External research needed (URLs listed)
2. External research: Visit davidwuchn repos
3. Local scan: Not explicitly required
4. Read: Repos
5. Analyze: Extract patterns
6. Synthesize: Lead with findings
7. Report: Specific techniques

Let me also note: the "Previously Discovered Insights" shows recent discoveries included:
- zeroclaw, context-mode, eca, ai-code-interface.el, nullclaw, Ori-Mnemos patterns
- GCP design patterns (sequential, concurrent, group chat, handoff, magentic)
- Decision model framework

So I should AVOID re-reporting these. The priority repos to monitor are now:
- nucleus
- mementum  
- gptel

These are NEW repos to focus on (not previously researched).

Let me start by fetching the three priority repos in parallel.

Given the budget constraints (68% own repos, 21% external), I should:
1. Fetch nucleus, mementum, gptel READMEs (own repos - 3 sources)
2. Possibly fetch 1-2 external sources for novel ideas
3. Synthesize digest under 1200 chars

Let me start with parallel WebFetch calls.
</think>I'll execute the research mission per the controller config. Starting with own repos (nucleus, mementum, gptel) per the 68% own-repo priority, then 1-2 external sources.<think>
Good, I have substantial material from the three priority repos. Let me read more of the nucleus and gptel files to get architectural details, and look at recent commits/patterns. Let me also fetch one external source for context.

Key insights so far:

**Nucleus** (own repo - new for this research):
- Compressed mathematical notation as prompt preambles (lambda, constants, control loops)
- Two notation layers: EDN statecharts + lambda expressions
- Prompt compiler (prose ↔ EDN)
- Prompt debugger (interactive/automated analysis)
- EBNF formal grammar
- Compositional modules shaping AI behavior through formal notation
- "Attention magnets" - mathematical constants pull attention toward formal reasoning
- Tension pairs create productive gradients (signal/noise, order/entropy)

**Mementum** (own repo - new for this research):
- Three storage types: working memory (state.md), memories (<200 words), knowledge (synthesized)
- Seven operations: create, create-knowledge, update, delete, search, read, synthesize
- Human governance: AI proposes, human approves, AI commits
- Git-native: git log for temporal, git grep for semantic, commit history for immutability
- Protocol interoperability - any AI with bash+git can read
- MEMENTUM-LAMBDA.md uses nucleus lambda notation
- 32B+ models can parse lambda notation with nucleus preamble
- Feed-forward principle: encoding understanding into git
- Discovery infrastructure planned (DNS-based lookup)

**Gptel** (own repo - new for this research):
- Multi-model/multi-backend Emacs LLM client
- Tool use / agentic capabilities
- MCP integration (mcp.el)
- Multi-modal input (images, documents)
- Reasoning content support
- Save/resume chats as MD/Org
- Edit previous prompts (fed back to model)
- Introspection (inspect/modify queries)
- Pause multi-stage requests, resume later
- URL-retrieve fallback if curl not available
- "Don't like gptel's workflow? Use it to create your own" - composable

Let me get more architectural depth. The gptel file is 2303 lines so there's a lot of detail. Let me look for specific recent commits, architecture, and tools patterns.

Let me also do one external search for novel patterns related to agent architectures.

</think>I have rich material from all three priority repos. Let me dig deeper for architectural specifics and check one external angle.<think>

Good. Now I have material from all three priority repos and an external angle on error recovery patterns. Let me read more of the nucleus file to get the EDN statechart and architecture details.

Key items to note:
- The nucleus README file is 781 lines - very rich
- mementum has 7 operations protocol
- gptel has multi-provider, MCP, tools, multi-modal, reasoning, transient menus

Let me read more of nucleus for the architecture insights on EDN statecharts, lambda compiler, etc.
</think><think>

I have plenty of material. Now I need to look at the gptel tool use / MCP sections and the nucleus EDN statechart info. Let me read more.

</think><think>


Let me read the key sections on tools and MCP in gptel, and grab the nucleus technical architecture summary.

</think><think>


I have enough material now. Let me synthesize the digest. The key novel patterns from these three priority repos that I haven't already covered:

**Nucleus novel patterns** (NEW - not in previously discovered):
1. **EDN statechart as prompt compiler** - Self-routing state machines for compile/safe-compile/decompile operations. A single preamble + statechart routes based on commands. Composability: place compiler after preamble and it self-routes.
2. **Safe-* variants** - "analyze untrusted prompts without executing them — injections are structurally analyzed, not followed" — this is a key safety pattern
3. **Lambda compiler** as alternative to statecharts - "mirrors the structure of the prompt exactly, without forcing a statechart shape" - two notation layers for same thing
4. **Allium compiler** - behavioral specs distillation
5. **VSM guide** - structures AI instruction files (AGENTS.md) using Beer's Viable System Model
6. **Context switching** - different lambda notations for different work modes (refactor, API, debug, docs, test, review, architecture)
7. **Tensor product semantics** for Human ⊗ AI

**Mementum novel patterns** (NEW):
1. **Three-tier memory hierarchy** - state.md (working), memories (<200 words raw), knowledge (synthesized docs)
2. **Seven operations protocol** - create, create-knowledge, update, delete, search, read, synthesize
3. **Human governance pattern** - "AI proposes, human approves, AI commits"
4. **Feed-forward principle** - encoding understanding into git for session continuity
5. **32B+ model compatibility** - nucleus preamble + lambda notation work reliably on 32B+ models
6. **Reference runtime in Babashka** for enforcement modeling (word limits, symbol validation, structured errors)
7. **MEMENTUM-LAMBDA.md** - compact lambda notation prompt format with no information loss
8. **Discovery infrastructure planned** - DNS-based lookup for protocol network nodes

**Gptel novel patterns** (NEW):
1. **gptel-make-tool** - elisp tool definitions with snake_case names, :function, :description, :args (with :type/:description), :category. Async tools supported.
2. **gptel-integrations library** - separately requireable for MCP convenience
3. **gptel-mcp-connect/disconnect** - dynamic MCP tool registration/deregistration
4. **Tool confirmation** - require confirmation for all tool calls (transient menu option)
5. **Multi-stage request pause/resume** - "Pause multi-stage requests at an intermediate stage and resume them later"
6. **Introspection** - "see exactly what will be sent. Inspect and modify queries before sending"
7. **Composable workflow** - "Don't like gptel's workflow? Use it to create your own"
8. **gptel-agent** - collection for agentic LLM use (filesystem, bash, emacs introspection, elisp eval, web search, youtube)
9. **API key as function** - :key can be a function that returns the key (deferred resolution)
10. **OpenAI OAuth** - gptel-make-openai-oauth for subscription auth

Now let me decide on top 1-2 patterns from each (per the prompt: "1-3 patterns applicable to Emacs Lisp AI agents"). I should pick non-obvious, implementable patterns.

Best patterns to extract:

**From Nucleus:**
1. EDN statechart compiler pattern (with safe-* variants for untrusted prompts)
2. Context-switching sub-preambles for work modes (refactor/debug/docs/test)

**From Mementum:**
1. Three-tier memory hierarchy + human governance
2. Feed-forward protocol with structured commit operations

**From Gptel:**
1. Tool spec with :function/:args/:type/:description + confirmation gating
2. Multi-stage request pause/resume + introspection

For the external angle, the error recovery pattern from zylos.ai and the preporato.com piece suggest:
- Exponential backoff with circuit breaker
- Fallback chain (already covered in zeroclaw previous discovery)
- Telegram message handling pattern - "cache last message for retry"

Let me write the digest now. The 1200 char limit is tight. I need to be very compact.

Format: structure with ## headers (per output_format in system prompt), bullet points, prefix `[deep-external]`. End with JSON.

Let me count characters carefully. The 1200 chars is the digest body, not counting the JSON.

Let me draft:

```
## External Sources
- **zylos.ai/research/2026-01-12-ai-agent-error-handling-recovery/** — Multi-tier error recovery: retry+backoff for transient (Telegram send), circuit breaker for persistent (CDP server), checkpoint+resume for long-running (research), provider fallback for capability gaps. **Apply**: wrap gptel-tool calls in a 3-tier classifier (transient→retry, persistent→circuit-break+user-prompt, capability→fallback-model).

## Local Analysis — Own Repos (davidwuchn/*)

### [deep-external] nucleus — EDN Statechart Compiler
Composes self-routing state machines after a single preamble; commands (compile/safe-compile/decompile) auto-dispatch. **Safe-*** variants analyze untrusted prompts without execution — structural analysis not execution. **Apply**: build a per-task "command router" defun that dispatches gptel requests to compile/diagnose/compare based on prompt prefix; gate risky ops behind safe- prefix.

### [deep-external] mementum — Three-Tier Memory + Human Governance
Hierarchy: `state.md` (working, ephemeral) → `memories/*.md` (<200 words, raw observations) → `knowledge/*.md` (synthesized). Seven operations: create/create-knowledge/update/delete/search/read/synthesize. Governance: AI proposes, human approves, AI commits (mirrors mementum's commit-convention). **Apply**: replace flat `*insights*` with three files; gate writes through `y-or-n-p`; auto-summarize memories older than 30 days into knowledge pages.

### [deep-external] gptel — Tool Spec + Pause/Resume
`gptel-make-tool` plist: `:name` (snake_case), `:function` (elisp), `:args` (plist of `:name`/`:type`/`:description`), `:category` (grouping). Confirmation flag gates destructive ops. Multi-stage requests can pause between stages and resume later; introspection API lets you inspect/modify the actual payload before send. **Apply**: wrap our 17 tools with `:category` (read/write/exec/introspect); add confirmation-only-for-write-category flag; expose pause/resume for long multi-tool sequences.

### [deep-external] nucleus — Context-Switched Sub-Preambles
Per-work-mode lambdas: refactor=[τ μ]+[Δ Σ/μ]+OODA, debug=[μ]+[Δ λ ∞/0]+OODA, test=[π ∞/0]+[Δ λ]+RGR, review=[τ ∞/0]+[Δ λ]+OODA. Same core preamble, different operator sets prime different cognitive modes. **Apply**: define per-op lambdas in our auto-workflow (improve/refactor/experiment/document/analyze) and prepend to the corresponding agent system prompt.
```

That's about 2100 chars... too long. Let me trim.

Actually re-reading the system prompt: "Max 1200 chars. Prioritize depth over breadth." for the digest.

Let me cut to the essential 1-2 patterns per source and tighten language.

Revised draft:

```
## External Sources
- **zylos.ai (2026-01-12)** — 3-tier error recovery: retry+backoff (transient) / circuit breaker (persistent) / checkpoint+resume (long-running). Apply: wrap tool calls in classifier dispatching to one of three handlers.

## Local Analysis — Own Repos (davidwuchn/*)

### [deep-external] nucleus — Self-Routing EDN Compiler + Safe Variants
Statechart after preamble auto-dispatches commands (compile/safe-compile/decompile/diagnose). `safe-*` variants analyze untrusted input structurally without execution — defeats prompt injection by construction. Apply: per-task defun routing on prompt prefix; gate any untrusted text behind `safe-` namespace.

### [deep-external] mementum — 3-Tier Memory + Propose/Approve/Commit
Files: `state.md` (working) → `memories/<200w raw>` → `knowledge/<synthesized>`. Ops: create/create-knowledge/update/delete/search/read/synthesize. Governance: AI proposes, human y-or-n-p's, AI commits. Apply: split flat insights into 3 dirs; gate writes through confirmation; auto-distill stale memories to knowledge.

### [deep-external] gptel — Tool Spec + Multi-Stage Pause/Resume
`gptel-make-tool` plist: `:name` (snake_case) + `:function` + `:args` (`:name`/`:type`/`:description`) + `:category`. Confirmation flag per category. Multi-stage requests can pause mid-execution and resume; introspection API exposes full payload pre-send. Apply: wrap our 17 tools with `:category` (read/write/exec); add mid-pipeline pause for human-in-loop at destructive boundaries; surface payload for diff-review.

### [deep-external] nucleus — Context-Switched Sub-Lambdas
Per-op lambdas: refactor=[τ μ|Δ Σ/μ|OODA], debug=[μ|Δ λ ∞/0|OODA], test=[π ∞/0|Δ λ|RGR], review=[τ ∞/0|Δ λ|OODA]. Same preamble, different operator subsets prime different modes. Apply: prepend per-op lambda (improve/refactor/experiment/document/analyze) to agent system prompt.
```

Let me count: that's roughly 1900 chars. Still over. Need to cut more.

Let me try a tighter version. The prompt says max 1200 chars for the digest body.

Let me trim harder - aim for 1 pattern per source plus the external:

</think>I have rich material from all three priority repos. Now I have enough to synthesize. Let me check that I'm under 1200 chars for the digest body and the JSON is valid.<think>
Still 1831 chars - over 1200. Need to cut more. Let me trim aggressively. Cut to 1.5 patterns per source.
</think><think>
Still 1566. Need to cut more. Let me try removing the external section and merging it, or just trimming the per-source commentary.

</think><think>

1319. Need to cut 120 chars more to hit 1200. Let me trim a bit more.

</think><think>

Still 1269. Need to cut ~70 more chars. Let me drop "review" lambda (it's redundant with the example) and trim a few more words.

Actually I removed review already. Let me cut more.

Or wait - "Max 1200 chars" - this could be interpreted as 1200 chars soft cap. Let me check: "Max 1200 chars. Prioritize depth over breadth." - so 1200 is the hard cap.

Let me trim a few more chars.

</think><think>

Still 1205, just barely over. Let me cut a few more chars.

Actually wait - 1200 is the cap and I'm at 1205. Just need 5 more chars cut. Easy.

Let me remove the redundant "Operator subset primes mode" line ending since "Same preamble" already conveys it.

Actually let me just cut the last "Apply:" line a bit.
</think><think>


Now 1194 chars - under 1200. 

Now let me write the full response with the JSON metadata at the end.

Sources to list in JSON: nucleus, mementum, gptel, zylos.ai

Topics covered: error-recovery, memory-hierarchy, tool-spec, prompt-compiler, sub-lambdas

Confidence: I have 5 well-supported insights from 4 sources (3 own + 1 external), so 0.72-0.75 confidence.

Insights count: 5
Tokens estimate: ~1100-1200

Let me w
...[Result too large, truncated. Full result saved to: /home/davidwu/.emacs.d/var/tmp/gptel-subagent-result-CXT85Y.txt. Use Read tool if you need more]...

---

Researcher result for task: External research turn 1/4

<think>
The user has provided a complex research prompt. Let me parse what's actually being asked:

1. The system prompt establishes me as a research and synthesis agent
2. The user message is a detailed prompt for "Auto-Workflow Researcher" 
3. The task is to do external research on:
   - davidwuchn/nucleus (AI prompting framework)
   - davidwuchn/mementum (Git-based AI memory)
   - davidwuchn/gptel (LLM backend integration)
4. Plus general research on AI agent patterns
5. Output should be a compact digest under 1200 chars
6. Must start with own repos (68% own repos, 21% external)
7. End with JSON metadata

Key constraints:
- Max 1200 chars for the digest
- 68% own repos focus
- 21% external
- Must include `[deep-external]` prefix on findings
- End with JSON metadata
- Avoid topics already in "Previously Discovered Insights"
- Focus on novel patterns

Let me check the phase checklist:
1. Mode: External research needed (URLs listed)
2. External research: Visit davidwuchn repos
3. Local scan: Not explicitly required
4. Read: Repos
5. Analyze: Extract patterns
6. Synthesize: Lead with findings
7. Report: Specific techniques

Let me also note: the "Previously Discovered Insights" shows recent discoveries included:
- zeroclaw, context-mode, eca, ai-code-interface.el, nullclaw, Ori-Mnemos patterns
- GCP design patterns (sequential, concurrent, group chat, handoff, magentic)
- Decision model framework

So I should AVOID re-reporting these. The priority repos to monitor are now:
- nucleus
- mementum  
- gptel

These are NEW repos to focus on (not previously researched).

Let me start by fetching the three priority repos in parallel.

Given the budget constraints (68% own repos, 21% external), I should:
1. Fetch nucleus, mementum, gptel READMEs (own repos - 3 sources)
2. Possibly fetch 1-2 external sources for novel ideas
3. Synthesize digest under 1200 chars

Let me start with parallel WebFetch calls.
</think>I'll execute the research mission per the controller config. Starting with own repos (nucleus, mementum, gptel) per the 68% own-repo priority, then 1-2 external sources.<think>
Good, I have substantial material from the three priority repos. Let me read more of the nucleus and gptel files to get architectural details, and look at recent commits/patterns. Let me also fetch one external source for context.

Key insights so far:

**Nucleus** (own repo - new for this research):
- Compressed mathematical notation as prompt preambles (lambda, constants, control loops)
- Two notation layers: EDN statecharts + lambda expressions
- Prompt compiler (prose ↔ EDN)
- Prompt debugger (interactive/automated analysis)
- EBNF formal grammar
- Compositional modules shaping AI behavior through formal notation
- "Attention magnets" - mathematical constants pull attention toward formal reasoning
- Tension pairs create productive gradients (signal/noise, order/entropy)

**Mementum** (own repo - new for this research):
- Three storage types: working memory (state.md), memories (<200 words), knowledge (synthesized)
- Seven operations: create, create-knowledge, update, delete, search, read, synthesize
- Human governance: AI proposes, human approves, AI commits
- Git-native: git log for temporal, git grep for semantic, commit history for immutability
- Protocol interoperability - any AI with bash+git can read
- MEMENTUM-LAMBDA.md uses nucleus lambda notation
- 32B+ models can parse lambda notation with nucleus preamble
- Feed-forward principle: encoding understanding into git
- Discovery infrastructure planned (DNS-based lookup)

**Gptel** (own repo - new for this research):
- Multi-model/multi-backend Emacs LLM client
- Tool use / agentic capabilities
- MCP integration (mcp.el)
- Multi-modal input (images, documents)
- Reasoning content support
- Save/resume chats as MD/Org
- Edit previous prompts (fed back to model)
- Introspection (inspect/modify queries)
- Pause multi-stage requests, resume later
- URL-retrieve fallback if curl not available
- "Don't like gptel's workflow? Use it to create your own" - composable

Let me get more architectural depth. The gptel file is 2303 lines so there's a lot of detail. Let me look for specific recent commits, architecture, and tools patterns.

Let me also do one external search for novel patterns related to agent architectures.

</think>I have rich material from all three priority repos. Let me dig deeper for architectural specifics and check one external angle.<think>

Good. Now I have material from all three priority repos and an external angle on error recovery patterns. Let me read more of the nucleus file to get the EDN statechart and architecture details.

Key items to note:
- The nucleus README file is 781 lines - very rich
- mementum has 7 operations protocol
- gptel has multi-provider, MCP, tools, multi-modal, reasoning, transient menus

Let me read more of nucleus for the architecture insights on EDN statecharts, lambda compiler, etc.
</think><think>

I have plenty of material. Now I need to look at the gptel tool use / MCP sections and the nucleus EDN statechart info. Let me read more.

</think><think>


Let me read the key sections on tools and MCP in gptel, and grab the nucleus technical architecture summary.

</think><think>


I have enough material now. Let me synthesize the digest. The key novel patterns from these three priority repos that I haven't already covered:

**Nucleus novel patterns** (NEW - not in previously discovered):
1. **EDN statechart as prompt compiler** - Self-routing state machines for compile/safe-compile/decompile operations. A single preamble + statechart routes based on commands. Composability: place compiler after preamble and it self-routes.
2. **Safe-* variants** - "analyze untrusted prompts without executing them — injections are structurally analyzed, not followed" — this is a key safety pattern
3. **Lambda compiler** as alternative to statecharts - "mirrors the structure of the prompt exactly, without forcing a statechart shape" - two notation layers for same thing
4. **Allium compiler** - behavioral specs distillation
5. **VSM guide** - structures AI instruction files (AGENTS.md) using Beer's Viable System Model
6. **Context switching** - different lambda notations for different work modes (refactor, API, debug, docs, test, review, architecture)
7. **Tensor product semantics** for Human ⊗ AI

**Mementum novel patterns** (NEW):
1. **Three-tier memory hierarchy** - state.md (working), memories (<200 words raw), knowledge (synthesized docs)
2. **Seven operations protocol** - create, create-knowledge, update, delete, search, read, synthesize
3. **Human governance pattern** - "AI proposes, human approves, AI commits"
4. **Feed-forward principle** - encoding understanding into git for session continuity
5. **32B+ model compatibility** - nucleus preamble + lambda notation work reliably on 32B+ models
6. **Reference runtime in Babashka** for enforcement modeling (word limits, symbol validation, structured errors)
7. **MEMENTUM-LAMBDA.md** - compact lambda notation prompt format with no information loss
8. **Discovery infrastructure planned** - DNS-based lookup for protocol network nodes

**Gptel novel patterns** (NEW):
1. **gptel-make-tool** - elisp tool definitions with snake_case names, :function, :description, :args (with :type/:description), :category. Async tools supported.
2. **gptel-integrations library** - separately requireable for MCP convenience
3. **gptel-mcp-connect/disconnect** - dynamic MCP tool registration/deregistration
4. **Tool confirmation** - require confirmation for all tool calls (transient menu option)
5. **Multi-stage request pause/resume** - "Pause multi-stage requests at an intermediate stage and resume them later"
6. **Introspection** - "see exactly what will be sent. Inspect and modify queries before sending"
7. **Composable workflow** - "Don't like gptel's workflow? Use it to create your own"
8. **gptel-agent** - collection for agentic LLM use (filesystem, bash, emacs introspection, elisp eval, web search, youtube)
9. **API key as function** - :key can be a function that returns the key (deferred resolution)
10. **OpenAI OAuth** - gptel-make-openai-oauth for subscription auth

Now let me decide on top 1-2 patterns from each (per the prompt: "1-3 patterns applicable to Emacs Lisp AI agents"). I should pick non-obvious, implementable patterns.

Best patterns to extract:

**From Nucleus:**
1. EDN statechart compiler pattern (with safe-* variants for untrusted prompts)
2. Context-switching sub-preambles for work modes (refactor/debug/docs/test)

**From Mementum:**
1. Three-tier memory hierarchy + human governance
2. Feed-forward protocol with structured commit operations

**From Gptel:**
1. Tool spec with :function/:args/:type/:description + confirmation gating
2. Multi-stage request pause/resume + introspection

For the external angle, the error recovery pattern from zylos.ai and the preporato.com piece suggest:
- Exponential backoff with circuit breaker
- Fallback chain (already covered in zeroclaw previous discovery)
- Telegram message handling pattern - "cache last message for retry"

Let me write the digest now. The 1200 char limit is tight. I need to be very compact.

Format: structure with ## headers (per output_format in system prompt), bullet points, prefix `[deep-external]`. End with JSON.

Let me count characters carefully. The 1200 chars is the digest body, not counting the JSON.

Let me draft:

```
## External Sources
- **zylos.ai/research/2026-01-12-ai-agent-error-handling-recovery/** — Multi-tier error recovery: retry+backoff for transient (Telegram send), circuit breaker for persistent (CDP server), checkpoint+resume for long-running (research), provider fallback for capability gaps. **Apply**: wrap gptel-tool calls in a 3-tier classifier (transient→retry, persistent→circuit-break+user-prompt, capability→fallback-model).

## Local Analysis — Own Repos (davidwuchn/*)

### [deep-external] nucleus — EDN Statechart Compiler
Composes self-routing state machines after a single preamble; commands (compile/safe-compile/decompile) auto-dispatch. **Safe-*** variants analyze untrusted prompts without execution — structural analysis not execution. **Apply**: build a per-task "command router" defun that dispatches gptel requests to compile/diagnose/compare based on prompt prefix; gate risky ops behind safe- prefix.

### [deep-external] mementum — Three-Tier Memory + Human Governance
Hierarchy: `state.md` (working, ephemeral) → `memories/*.md` (<200 words, raw observations) → `knowledge/*.md` (synthesized). Seven operations: create/create-knowledge/update/delete/search/read/synthesize. Governance: AI proposes, human approves, AI commits (mirrors mementum's commit-convention). **Apply**: replace flat `*insights*` with three files; gate writes through `y-or-n-p`; auto-summarize memories older than 30 days into knowledge pages.

### [deep-external] gptel — Tool Spec + Pause/Resume
`gptel-make-tool` plist: `:name` (snake_case), `:function` (elisp), `:args` (plist of `:name`/`:type`/`:description`), `:category` (grouping). Confirmation flag gates destructive ops. Multi-stage requests can pause between stages and resume later; introspection API lets you inspect/modify the actual payload before send. **Apply**: wrap our 17 tools with `:category` (read/write/exec/introspect); add confirmation-only-for-write-category flag; expose pause/resume for long multi-tool sequences.

### [deep-external] nucleus — Context-Switched Sub-Preambles
Per-work-mode lambdas: refactor=[τ μ]+[Δ Σ/μ]+OODA, debug=[μ]+[Δ λ ∞/0]+OODA, test=[π ∞/0]+[Δ λ]+RGR, review=[τ ∞/0]+[Δ λ]+OODA. Same core preamble, different operator sets prime different cognitive modes. **Apply**: define per-op lambdas in our auto-workflow (improve/refactor/experiment/document/analyze) and prepend to the corresponding agent system prompt.
```

That's about 2100 chars... too long. Let me trim.

Actually re-reading the system prompt: "Max 1200 chars. Prioritize depth over breadth." for the digest.

Let me cut to the essential 1-2 patterns per source and tighten language.

Revised draft:

```
## External Sources
- **zylos.ai (2026-01-12)** — 3-tier error recovery: retry+backoff (transient) / circuit breaker (persistent) / checkpoint+resume (long-running). Apply: wrap tool calls in classifier dispatching to one of three handlers.

## Local Analysis — Own Repos (davidwuchn/*)

### [deep-external] nucleus — Self-Routing EDN Compiler + Safe Variants
Statechart after preamble auto-dispatches commands (compile/safe-compile/decompile/diagnose). `safe-*` variants analyze untrusted input structurally without execution — defeats prompt injection by construction. Apply: per-task defun routing on prompt prefix; gate any untrusted text behind `safe-` namespace.

### [deep-external] mementum — 3-Tier Memory + Propose/Approve/Commit
Files: `state.md` (working) → `memories/<200w raw>` → `knowledge/<synthesized>`. Ops: create/create-knowledge/update/delete/search/read/synthesize. Governance: AI proposes, human y-or-n-p's, AI commits. Apply: split flat insights into 3 dirs; gate writes through confirmation; auto-distill stale memories to knowledge.

### [deep-external] gptel — Tool Spec + Multi-Stage Pause/Resume
`gptel-make-tool` plist: `:name` (snake_case) + `:function` + `:args` (`:name`/`:type`/`:description`) + `:category`. Confirmation flag per category. Multi-stage requests can pause mid-execution and resume; introspection API exposes full payload pre-send. Apply: wrap our 17 tools with `:category` (read/write/exec); add mid-pipeline pause for human-in-loop at destructive boundaries; surface payload for diff-review.

### [deep-external] nucleus — Context-Switched Sub-Lambdas
Per-op lambdas: refactor=[τ μ|Δ Σ/μ|OODA], debug=[μ|Δ λ ∞/0|OODA], test=[π ∞/0|Δ λ|RGR], review=[τ ∞/0|Δ λ|OODA]. Same preamble, different operator subsets prime different modes. Apply: prepend per-op lambda (improve/refactor/experiment/document/analyze) to agent system prompt.
```

Let me count: that's roughly 1900 chars. Still over. Need to cut more.

Let me try a tighter version. The prompt says max 1200 chars for the digest body.

Let me trim harder - aim for 1 pattern per source plus the external:

</think>I have rich material from all three priority repos. Now I have enough to synthesize. Let me check that I'm under 1200 chars for the digest body and the JSON is valid.<think>
Still 1831 chars - over 1200. Need to cut more. Let me trim aggressively. Cut to 1.5 patterns per source.
</think><think>
Still 1566. Need to cut more. Let me try removing the external section and merging it, or just trimming the per-source commentary.

</think><think>

1319. Need to cut 120 chars more to hit 1200. Let me trim a bit more.

</think><think>

Still 1269. Need to cut ~70 more chars. Let me drop "review" lambda (it's redundant with the example) and trim a few more words.

Actually I removed review already. Let me cut more.

Or wait - "Max 1200 chars" - this could be interpreted as 1200 chars soft cap. Let me check: "Max 1200 chars. Prioritize depth over breadth." - so 1200 is the hard cap.

Let me trim a few more chars.

</think><think>

Still 1205, just barely over. Let me cut a few more chars.

Actually wait - 1200 is the cap and I'm at 1205. Just need 5 more chars cut. Easy.

Let me remove the redundant "Operator subset primes mode" line ending since "Same preamble" already conveys it.

Actually let me just cut the last "Apply:" line a bit.
</think><think>


Now 1194 chars - under 1200. 

Now let me write the full response with the JSON metadata at the end.

Sources to list in JSON: nucleus, mementum, gptel, zylos.ai

Topics covered: error-recovery, memory-hierarchy, tool-spec, prompt-compiler, sub-lambdas

Confidence: I have 5 well-supported insights from 4 sources (3 own + 1 external), so 0.72-0.75 confidence.

Insights count: 5
Tokens estimate: ~1100-1200

Let me w
...[Result too large, truncated. Full result saved to: /home/davidwu/.emacs.d/var/tmp/gptel-subagent-result-CXT85Y.txt. Use Read tool if you need more]...

**Digested Insights:**

## Research Priorities (from Ontology × AutoTTS × AutoGo)
Focus research on these categories:
  [:programming] Critical: 0% keep-rate after 28 experiments — needs investigation
  [:agentic] Critical: 3% keep-rate after 69 experiments — needs investigation

Produce category-specific findings — not global recommendations.

> Project: /home/davidwu/.emacs.d/
> Updated: 2026-06-06 03:07

Researcher result for task: External research turn 1/4

<think>
The user has provided a complex research prompt. Let me parse what's actually being asked:

1. The system prompt establishes me as a research and synthesis agent
2. The user message is a detailed prompt for "Auto-Workflow Researcher" 
3. The task is to do external research on:
   - davidwuchn/nucleus (AI prompting framework)
   - davidwuchn/mementum (Git-based AI memory)
   - davidwuchn/gptel (LLM backend integration)
4. Plus general research on AI agent patterns
5. Output should be a compact digest under 1200 chars
6. Must start with own repos (68% own repos, 21% external)
7. End with JSON metadata

Key constraints:
- Max 1200 chars for the digest
- 68% own repos focus
- 21% external
- Must include `[deep-external]` prefix on findings
- End with JSON metadata
- Avoid topics already in "Previously Discovered Insights"
- Focus on novel patterns

Let me check the phase checklist:
1. Mode: External research needed (URLs listed)
2. External research: Visit davidwuchn repos
3. Local scan: Not explicitly required
4. Read: Repos
5. Analyze: Extract patterns
6. Synthesize: Lead with findings
7. Report: Specific techniques

Let me also note: the "Previously Discovered Insights" shows recent discoveries included:
- zeroclaw, context-mode, eca, ai-code-interface.el, nullclaw, Ori-Mnemos patterns
- GCP design patterns (sequential, concurrent, group chat, handoff, magentic)
- Decision model framework

So I should AVOID re-reporting these. The priority repos to monitor are now:
- nucleus
- mementum  
- gptel

These are NEW repos to focus on (not previously researched).

Let me start by fetching the three priority repos in parallel.

Given the budget constraints (68% own repos, 21% external), I should:
1. Fetch nucleus, mementum, gptel READMEs (own repos - 3 sources)
2. Possibly fetch 1-2 external sources for novel ideas
3. Synthesize digest under 1200 chars

Let me start with parallel WebFetch calls.
</think>I'll execute the research mission per the controller config. Starting with own repos (nucleus, mementum, gptel) per the 68% own-repo priority, then 1-2 external sources.<think>
Good, I have substantial material from the three priority repos. Let me read more of the nucleus and gptel files to get architectural details, and look at recent commits/patterns. Let me also fetch one external source for context.

Key insights so far:

**Nucleus** (own repo - new for this research):
- Compressed mathematical notation as prompt preambles (lambda, constants, control loops)
- Two notation layers: EDN statecharts + lambda expressions
- Prompt compiler (prose ↔ EDN)
- Prompt debugger (interactive/automated analysis)
- EBNF formal grammar
- Compositional modules shaping AI behavior through formal notation
- "Attention magnets" - mathematical constants pull attention toward formal reasoning
- Tension pairs create productive gradients (signal/noise, order/entropy)

**Mementum** (own repo - new for this research):
- Three storage types: working memory (state.md), memories (<200 words), knowledge (synthesized)
- Seven operations: create, create-knowledge, update, delete, search, read, synthesize
- Human governance: AI proposes, human approves, AI commits
- Git-native: git log for temporal, git grep for semantic, commit history for immutability
- Protocol interoperability - any AI with bash+git can read
- MEMENTUM-LAMBDA.md uses nucleus lambda notation
- 32B+ models can parse lambda notation with nucleus preamble
- Feed-forward principle: encoding understanding into git
- Discovery infrastructure planned (DNS-based lookup)

**Gptel** (own repo - new for this research):
- Multi-model/multi-backend Emacs LLM client
- Tool use / agentic capabilities
- MCP integration (mcp.el)
- Multi-modal input (images, documents)
- Reasoning content support
- Save/resume chats as MD/Org
- Edit previous prompts (fed back to model)
- Introspection (inspect/modify queries)
- Pause multi-stage requests, resume later
- URL-retrieve fallback if curl not available
- "Don't like gptel's workflow? Use it to create your own" - composable

Let me get more architectural depth. The gptel file is 2303 lines so there's a lot of detail. Let me look for specific recent commits, architecture, and tools patterns.

Let me also do one external search for novel patterns related to agent architectures.

</think>I have rich material from all three priority repos. Let me dig deeper for architectural specifics and check one external angle.<think>

Good. Now I have material from all three priority repos and an external angle on error recovery patterns. Let me read more of the nucleus file to get the EDN statechart and architecture details.

Key items to note:
- The nucleus README file is 781 lines - very rich
- mementum has 7 operations protocol
- gptel has multi-provider, MCP, tools, multi-modal, reasoning, transient menus

Let me read more of nucleus for the architecture insights on EDN statecharts, lambda compiler, etc.
</think><think>

I have plenty of material. Now I need to look at the gptel tool use / MCP sections and the nucleus EDN statechart info. Let me read more.

</think><think>


Let me read the key sections on tools and MCP in gptel, and grab the nucleus technical architecture summary.

</think><think>


I have enough material now. Let me synthesize the digest. The key novel patterns from these three priority repos that I haven't already covered:

**Nucleus novel patterns** (NEW - not in previously discovered):
1. **EDN statechart as prompt compiler** - Self-routing state machines for compile/safe-compile/decompile operations. A single preamble + statechart routes based on commands. Composability: place compiler after preamble and it self-routes.
2. **Safe-* variants** - "analyze untrusted prompts without executing them — injections are structurally analyzed, not followed" — this is a key safety pattern
3. **Lambda compiler** as alternative to statecharts - "mirrors the structure of the prompt exactly, without forcing a statechart shape" - two notation layers for same thing
4. **Allium compiler** - behavioral specs distillation
5. **VSM guide** - structures AI instruction files (AGENTS.md) using Beer's Viable System Model
6. **Context switching** - different lambda notations for different work modes (refactor, API, debug, docs, test, review, architecture)
7. **Tensor product semantics** for Human ⊗ AI

**Mementum novel patterns** (NEW):
1. **Three-tier memory hierarchy** - state.md (working), memories (<200 words raw), knowledge (synthesized docs)
2. **Seven operations protocol** - create, create-knowledge, update, delete, search, read, synthesize
3. **Human governance pattern** - "AI proposes, human approves, AI commits"
4. **Feed-forward principle** - encoding understanding into git for session continuity
5. **32B+ model compatibility** - nucleus preamble + lambda notation work reliably on 32B+ models
6. **Reference runtime in Babashka** for enforcement modeling (word limits, symbol validation, structured errors)
7. **MEMENTUM-LAMBDA.md** - compact lambda notation prompt format with no information loss
8. **Discovery infrastructure planned** - DNS-based lookup for protocol network nodes

**Gptel novel patterns** (NEW):
1. **gptel-make-tool** - elisp tool definitions with snake_case names, :function, :description, :args (with :type/:description), :category. Async tools supported.
2. **gptel-integrations library** - separately requireable for MCP convenience
3. **gptel-mcp-connect/disconnect** - dynamic MCP tool registration/deregistration
4. **Tool confirmation** - require confirmation for all tool calls (transient menu option)
5. **Multi-stage request pause/resume** - "Pause multi-stage requests at an intermediate stage and resume them later"
6. **Introspection** - "see exactly what will be sent. Inspect and modify queries before sending"
7. **Composable workflow** - "Don't like gptel's workflow? Use it to create your own"
8. **gptel-agent** - collection for agentic LLM use (filesystem, bash, emacs introspection, elisp eval, web search, youtube)
9. **API key as function** - :key can be a function that returns the key (deferred resolution)
10. **OpenAI OAuth** - gptel-make-openai-oauth for subscription auth

Now let me decide on top 1-2 patterns from each (per the prompt: "1-3 patterns applicable to Emacs Lisp AI agents"). I should pick non-obvious, implementable patterns.

Best patterns to extract:

**From Nucleus:**
1. EDN statechart compiler pattern (with safe-* variants for untrusted prompts)
2. Context-switching sub-preambles for work modes (refactor/debug/docs/test)

**From Mementum:**
1. Three-tier memory hierarchy + human governance
2. Feed-forward protocol with structured commit operations

**From Gptel:**
1. Tool spec with :function/:args/:type/:description + confirmation gating
2. Multi-stage request pause/resume + introspection

For the external angle, the error recovery pattern from zylos.ai and the preporato.com piece suggest:
- Exponential backoff with circuit breaker
- Fallback chain (already covered in zeroclaw previous discovery)
- Telegram message handling pattern - "cache last message for retry"

Let me write the digest now. The 1200 char limit is tight. I need to be very compact.

Format: structure with ## headers (per output_format in system prompt), bullet points, prefix `[deep-external]`. End with JSON.

Let me count characters carefully. The 1200 chars is the digest body, not counting the JSON.

Let me draft:

```
## External Sources
- **zylos.ai/research/2026-01-12-ai-agent-error-handling-recovery/** — Multi-tier error recovery: retry+backoff for transient (Telegram send), circuit breaker for persistent (CDP server), checkpoint+resume for long-running (research), provider fallback for capability gaps. **Apply**: wrap gptel-tool calls in a 3-tier classifier (transient→retry, persistent→circuit-break+user-prompt, capability→fallback-model).

## Local Analysis — Own Repos (davidwuchn/*)

### [deep-external] nucleus — EDN Statechart Compiler
Composes self-routing state machines after a single preamble; commands (compile/safe-compile/decompile) auto-dispatch. **Safe-*** variants analyze untrusted prompts without execution — structural analysis not execution. **Apply**: build a per-task "command router" defun that dispatches gptel requests to compile/diagnose/compare based on prompt prefix; gate risky ops behind safe- prefix.

### [deep-external] mementum — Three-Tier Memory + Human Governance
Hierarchy: `state.md` (working, ephemeral) → `memories/*.md` (<200 words, raw observations) → `knowledge/*.md` (synthesized). Seven operations: create/create-knowledge/update/delete/search/read/synthesize. Governance: AI proposes, human approves, AI commits (mirrors mementum's commit-convention). **Apply**: replace flat `*insights*` with three files; gate writes through `y-or-n-p`; auto-summarize memories older than 30 days into knowledge pages.

### [deep-external] gptel — Tool Spec + Pause/Resume
`gptel-make-tool` plist: `:name` (snake_case), `:function` (elisp), `:args` (plist of `:name`/`:type`/`:description`), `:category` (grouping). Confirmation flag gates destructive ops. Multi-stage requests can pause between stages and resume later; introspection API lets you inspect/modify the actual payload before send. **Apply**: wrap our 17 tools with `:category` (read/write/exec/introspect); add confirmation-only-for-write-category flag; expose pause/resume for long multi-tool sequences.

### [deep-external] nucleus — Context-Switched Sub-Preambles
Per-work-mode lambdas: refactor=[τ μ]+[Δ Σ/μ]+OODA, debug=[μ]+[Δ λ ∞/0]+OODA, test=[π ∞/0]+[Δ λ]+RGR, review=[τ ∞/0]+[Δ λ]+OODA. Same core preamble, different operator sets prime different cognitive modes. **Apply**: define per-op lambdas in our auto-workflow (improve/refactor/experiment/document/analyze) and prepend to the corresponding agent system prompt.
```

That's about 2100 chars... too long. Let me trim.

Actually re-reading the system prompt: "Max 1200 chars. Prioritize depth over breadth." for the digest.

Let me cut to the essential 1-2 patterns per source and tighten language.

Revised draft:

```
## External Sources
- **zylos.ai (2026-01-12)** — 3-tier error recovery: retry+backoff (transient) / circuit breaker (persistent) / checkpoint+resume (long-running). Apply: wrap tool calls in classifier dispatching to one of three handlers.

## Local Analysis — Own Repos (davidwuchn/*)

### [deep-external] nucleus — Self-Routing EDN Compiler + Safe Variants
Statechart after preamble auto-dispatches commands (compile/safe-compile/decompile/diagnose). `safe-*` variants analyze untrusted input structurally without execution — defeats prompt injection by construction. Apply: per-task defun routing on prompt prefix; gate any untrusted text behind `safe-` namespace.

### [deep-external] mementum — 3-Tier Memory + Propose/Approve/Commit
Files: `state.md` (working) → `memories/<200w raw>` → `knowledge/<synthesized>`. Ops: create/create-knowledge/update/delete/search/read/synthesize. Governance: AI proposes, human y-or-n-p's, AI commits. Apply: split flat insights into 3 dirs; gate writes through confirmation; auto-distill stale memories to knowledge.

### [deep-external] gptel — Tool Spec + Multi-Stage Pause/Resume
`gptel-make-tool` plist: `:name` (snake_case) + `:function` + `:args` (`:name`/`:type`/`:description`) + `:category`. Confirmation flag per category. Multi-stage requests can pause mid-execution and resume; introspection API exposes full payload pre-send. Apply: wrap our 17 tools with `:category` (read/write/exec); add mid-pipeline pause for human-in-loop at destructive boundaries; surface payload for diff-review.

### [deep-external] nucleus — Context-Switched Sub-Lambdas
Per-op lambdas: refactor=[τ μ|Δ Σ/μ|OODA], debug=[μ|Δ λ ∞/0|OODA], test=[π ∞/0|Δ λ|RGR], review=[τ ∞/0|Δ λ|OODA]. Same preamble, different operator subsets prime different modes. Apply: prepend per-op lambda (improve/refactor/experiment/document/analyze) to agent system prompt.
```

Let me count: that's roughly 1900 chars. Still over. Need to cut more.

Let me try a tighter version. The prompt says max 1200 chars for the digest body.

Let me trim harder - aim for 1 pattern per source plus the external:

</think>I have rich material from all three priority repos. Now I have enough to synthesize. Let me check that I'm under 1200 chars for the digest body and the JSON is valid.<think>
Still 1831 chars - over 1200. Need to cut more. Let me trim aggressively. Cut to 1.5 patterns per source.
</think><think>
Still 1566. Need to cut more. Let me try removing the external section and merging it, or just trimming the per-source commentary.

</think><think>

1319. Need to cut 120 chars more to hit 1200. Let me trim a bit more.

</think><think>

Still 1269. Need to cut ~70 more chars. Let me drop "review" lambda (it's redundant with the example) and trim a few more words.

Actually I removed review already. Let me cut more.

Or wait - "Max 1200 chars" - this could be interpreted as 1200 chars soft cap. Let me check: "Max 1200 chars. Prioritize depth over breadth." - so 1200 is the hard cap.

Let me trim a few more chars.

</think><think>

Still 1205, just barely over. Let me cut a few more chars.

Actually wait - 1200 is the cap and I'm at 1205. Just need 5 more chars cut. Easy.

Let me remove the redundant "Operator subset primes mode" line ending since "Same preamble" already conveys it.

Actually let me just cut the last "Apply:" line a bit.
</think><think>


Now 1194 chars - under 1200. 

Now let me write the full response with the JSON metadata at the end.

Sources to list in JSON: nucleus, mementum, gptel, zylos.ai

Topics covered: error-recovery, memory-hierarchy, tool-spec, prompt-compiler, sub-lambdas

Confidence: I have 5 well-supported insights from 4 sources (3 own + 1 external), so 0.72-0.75 confidence.

Insights count: 5
Tokens estimate: ~1100-1200

Let me w
...[Result too large, truncated. Full result saved to: /home/davidwu/.emacs.d/var/tmp/gptel-subagent-result-CXT85Y.txt. Use Read tool if you need more]...

---

Researcher result for task: External research turn 1/4

<think>
The user has provided a complex research prompt. Let me parse what's actually being asked:

1. The system prompt establishes me as a research and synthesis agent
2. The user message is a detailed prompt for "Auto-Workflow Researcher" 
3. The task is to do external research on:
   - davidwuchn/nucleus (AI prompting framework)
   - davidwuchn/mementum (Git-based AI memory)
   - davidwuchn/gptel (LLM backend integration)
4. Plus general research on AI agent patterns
5. Output should be a compact digest under 1200 chars
6. Must start with own repos (68% own repos, 21% external)
7. End with JSON metadata

Key constraints:
- Max 1200 chars for the digest
- 68% own repos focus
- 21% external
- Must include `[deep-external]` prefix on findings
- End with JSON metadata
- Avoid topics already in "Previously Discovered Insights"
- Focus on novel patterns

Let me check the phase checklist:
1. Mode: External research needed (URLs listed)
2. External research: Visit davidwuchn repos
3. Local scan: Not explicitly required
4. Read: Repos
5. Analyze: Extract patterns
6. Synthesize: Lead with findings
7. Report: Specific techniques

Let me also note: the "Previously Discovered Insights" shows recent discoveries included:
- zeroclaw, context-mode, eca, ai-code-interface.el, nullclaw, Ori-Mnemos patterns
- GCP design patterns (sequential, concurrent, group chat, handoff, magentic)
- Decision model framework

So I should AVOID re-reporting these. The priority repos to monitor are now:
- nucleus
- mementum  
- gptel

These are NEW repos to focus on (not previously researched).

Let me start by fetching the three priority repos in parallel.

Given the budget constraints (68% own repos, 21% external), I should:
1. Fetch nucleus, mementum, gptel READMEs (own repos - 3 sources)
2. Possibly fetch 1-2 external sources for novel ideas
3. Synthesize digest under 1200 chars

Let me start with parallel WebFetch calls.
</think>I'll execute the research mission per the controller config. Starting with own repos (nucleus, mementum, gptel) per the 68% own-repo priority, then 1-2 external sources.<think>
Good, I have substantial material from the three priority repos. Let me read more of the nucleus and gptel files to get architectural details, and look at recent commits/patterns. Let me also fetch one external source for context.

Key insights so far:

**Nucleus** (own repo - new for this research):
- Compressed mathematical notation as prompt preambles (lambda, constants, control loops)
- Two notation layers: EDN statecharts + lambda expressions
- Prompt compiler (prose ↔ EDN)
- Prompt debugger (interactive/automated analysis)
- EBNF formal grammar
- Compositional modules shaping AI behavior through formal notation
- "Attention magnets" - mathematical constants pull attention toward formal reasoning
- Tension pairs create productive gradients (signal/noise, order/entropy)

**Mementum** (own repo - new for this research):
- Three storage types: working memory (state.md), memories (<200 words), knowledge (synthesized)
- Seven operations: create, create-knowledge, update, delete, search, read, synthesize
- Human governance: AI proposes, human approves, AI commits
- Git-native: git log for temporal, git grep for semantic, commit history for immutability
- Protocol interoperability - any AI with bash+git can read
- MEMENTUM-LAMBDA.md uses nucleus lambda notation
- 32B+ models can parse lambda notation with nucleus preamble
- Feed-forward principle: encoding understanding into git
- Discovery infrastructure planned (DNS-based lookup)

**Gptel** (own repo - new for this research):
- Multi-model/multi-backend Emacs LLM client
- Tool use / agentic capabilities
- MCP integration (mcp.el)
- Multi-modal input (images, documents)
- Reasoning content support
- Save/resume chats as MD/Org
- Edit previous prompts (fed back to model)
- Introspection (inspect/modify queries)
- Pause multi-stage requests, resume later
- URL-retrieve fallback if curl not available
- "Don't like gptel's workflow? Use it to create your own" - composable

Let me get more architectural depth. The gptel file is 2303 lines so there's a lot of detail. Let me look for specific recent commits, architecture, and tools patterns.

Let me also do one external search for novel patterns related to agent architectures.

</think>I have rich material from all three priority repos. Let me dig deeper for architectural specifics and check one external angle.<think>

Good. Now I have material from all three priority repos and an external angle on error recovery patterns. Let me read more of the nucleus file to get the EDN statechart and architecture details.

Key items to note:
- The nucleus README file is 781 lines - very rich
- mementum has 7 operations protocol
- gptel has multi-provider, MCP, tools, multi-modal, reasoning, transient menus

Let me read more of nucleus for the architecture insights on EDN statecharts, lambda compiler, etc.
</think><think>

I have plenty of material. Now I need to look at the gptel tool use / MCP sections and the nucleus EDN statechart info. Let me read more.

</think><think>


Let me read the key sections on tools and MCP in gptel, and grab the nucleus technical architecture summary.

</think><think>


I have enough material now. Let me synthesize the digest. The key novel patterns from these three priority repos that I haven't already covered:

**Nucleus novel patterns** (NEW - not in previously discovered):
1. **EDN statechart as prompt compiler** - Self-routing state machines for compile/safe-compile/decompile operations. A single preamble + statechart routes based on commands. Composability: place compiler after preamble and it self-routes.
2. **Safe-* variants** - "analyze untrusted prompts without executing them — injections are structurally analyzed, not followed" — this is a key safety pattern
3. **Lambda compiler** as alternative to statecharts - "mirrors the structure of the prompt exactly, without forcing a statechart shape" - two notation layers for same thing
4. **Allium compiler** - behavioral specs distillation
5. **VSM guide** - structures AI instruction files (AGENTS.md) using Beer's Viable System Model
6. **Context switching** - different lambda notations for different work modes (refactor, API, debug, docs, test, review, architecture)
7. **Tensor product semantics** for Human ⊗ AI

**Mementum novel patterns** (NEW):
1. **Three-tier memory hierarchy** - state.md (working), memories (<200 words raw), knowledge (synthesized docs)
2. **Seven operations protocol** - create, create-knowledge, update, delete, search, read, synthesize
3. **Human governance pattern** - "AI proposes, human approves, AI commits"
4. **Feed-forward principle** - encoding understanding into git for session continuity
5. **32B+ model compatibility** - nucleus preamble + lambda notation work reliably on 32B+ models
6. **Reference runtime in Babashka** for enforcement modeling (word limits, symbol validation, structured errors)
7. **MEMENTUM-LAMBDA.md** - compact lambda notation prompt format with no information loss
8. **Discovery infrastructure planned** - DNS-based lookup for protocol network nodes

**Gptel novel patterns** (NEW):
1. **gptel-make-tool** - elisp tool definitions with snake_case names, :function, :description, :args (with :type/:description), :category. Async tools supported.
2. **gptel-integrations library** - separately requireable for MCP convenience
3. **gptel-mcp-connect/disconnect** - dynamic MCP tool registration/deregistration
4. **Tool confirmation** - require confirmation for all tool calls (transient menu option)
5. **Multi-stage request pause/resume** - "Pause multi-stage requests at an intermediate stage and resume them later"
6. **Introspection** - "see exactly what will be sent. Inspect and modify queries before sending"
7. **Composable workflow** - "Don't like gptel's workflow? Use it to create your own"
8. **gptel-agent** - collection for agentic LLM use (filesystem, bash, emacs introspection, elisp eval, web search, youtube)
9. **API key as function** - :key can be a function that returns the key (deferred resolution)
10. **OpenAI OAuth** - gptel-make-openai-oauth for subscription auth

Now let me decide on top 1-2 patterns from each (per the prompt: "1-3 patterns applicable to Emacs Lisp AI agents"). I should pick non-obvious, implementable patterns.

Best patterns to extract:

**From Nucleus:**
1. EDN statechart compiler pattern (with safe-* variants for untrusted prompts)
2. Context-switching sub-preambles for work modes (refactor/debug/docs/test)

**From Mementum:**
1. Three-tier memory hierarchy + human governance
2. Feed-forward protocol with structured commit operations

**From Gptel:**
1. Tool spec with :function/:args/:type/:description + confirmation gating
2. Multi-stage request pause/resume + introspection

For the external angle, the error recovery pattern from zylos.ai and the preporato.com piece suggest:
- Exponential backoff with circuit breaker
- Fallback chain (already covered in zeroclaw previous discovery)
- Telegram message handling pattern - "cache last message for retry"

Let me write the digest now. The 1200 char limit is tight. I need to be very compact.

Format: structure with ## headers (per output_format in system prompt), bullet points, prefix `[deep-external]`. End with JSON.

Let me count characters carefully. The 1200 chars is the digest body, not counting the JSON.

Let me draft:

```
## External Sources
- **zylos.ai/research/2026-01-12-ai-agent-error-handling-recovery/** — Multi-tier error recovery: retry+backoff for transient (Telegram send), circuit breaker for persistent (CDP server), checkpoint+resume for long-running (research), provider fallback for capability gaps. **Apply**: wrap gptel-tool calls in a 3-tier classifier (transient→retry, persistent→circuit-break+user-prompt, capability→fallback-model).

## Local Analysis — Own Repos (davidwuchn/*)

### [deep-external] nucleus — EDN Statechart Compiler
Composes self-routing state machines after a single preamble; commands (compile/safe-compile/decompile) auto-dispatch. **Safe-*** variants analyze untrusted prompts without execution — structural analysis not execution. **Apply**: build a per-task "command router" defun that dispatches gptel requests to compile/diagnose/compare based on prompt prefix; gate risky ops behind safe- prefix.

### [deep-external] mementum — Three-Tier Memory + Human Governance
Hierarchy: `state.md` (working, ephemeral) → `memories/*.md` (<200 words, raw observations) → `knowledge/*.md` (synthesized). Seven operations: create/create-knowledge/update/delete/search/read/synthesize. Governance: AI proposes, human approves, AI commits (mirrors mementum's commit-convention). **Apply**: replace flat `*insights*` with three files; gate writes through `y-or-n-p`; auto-summarize memories older than 30 days into knowledge pages.

### [deep-external] gptel — Tool Spec + Pause/Resume
`gptel-make-tool` plist: `:name` (snake_case), `:function` (elisp), `:args` (plist of `:name`/`:type`/`:description`), `:category` (grouping). Confirmation flag gates destructive ops. Multi-stage requests can pause between stages and resume later; introspection API lets you inspect/modify the actual payload before send. **Apply**: wrap our 17 tools with `:category` (read/write/exec/introspect); add confirmation-only-for-write-category flag; expose pause/resume for long multi-tool sequences.

### [deep-external] nucleus — Context-Switched Sub-Preambles
Per-work-mode lambdas: refactor=[τ μ]+[Δ Σ/μ]+OODA, debug=[μ]+[Δ λ ∞/0]+OODA, test=[π ∞/0]+[Δ λ]+RGR, review=[τ ∞/0]+[Δ λ]+OODA. Same core preamble, different operator sets prime different cognitive modes. **Apply**: define per-op lambdas in our auto-workflow (improve/refactor/experiment/document/analyze) and prepend to the corresponding agent system prompt.
```

That's about 2100 chars... too long. Let me trim.

Actually re-reading the system prompt: "Max 1200 chars. Prioritize depth over breadth." for the digest.

Let me cut to the essential 1-2 patterns per source and tighten language.

Revised draft:

```
## External Sources
- **zylos.ai (2026-01-12)** — 3-tier error recovery: retry+backoff (transient) / circuit breaker (persistent) / checkpoint+resume (long-running). Apply: wrap tool calls in classifier dispatching to one of three handlers.

## Local Analysis — Own Repos (davidwuchn/*)

### [deep-external] nucleus — Self-Routing EDN Compiler + Safe Variants
Statechart after preamble auto-dispatches commands (compile/safe-compile/decompile/diagnose). `safe-*` variants analyze untrusted input structurally without execution — defeats prompt injection by construction. Apply: per-task defun routing on prompt prefix; gate any untrusted text behind `safe-` namespace.

### [deep-external] mementum — 3-Tier Memory + Propose/Approve/Commit
Files: `state.md` (working) → `memories/<200w raw>` → `knowledge/<synthesized>`. Ops: create/create-knowledge/update/delete/search/read/synthesize. Governance: AI proposes, human y-or-n-p's, AI commits. Apply: split flat insights into 3 dirs; gate writes through confirmation; auto-distill stale memories to knowledge.

### [deep-external] gptel — Tool Spec + Multi-Stage Pause/Resume
`gptel-make-tool` plist: `:name` (snake_case) + `:function` + `:args` (`:name`/`:type`/`:description`) + `:category`. Confirmation flag per category. Multi-stage requests can pause mid-execution and resume; introspection API exposes full payload pre-send. Apply: wrap our 17 tools with `:category` (read/write/exec); add mid-pipeline pause for human-in-loop at destructive boundaries; surface payload for diff-review.

### [deep-external] nucleus — Context-Switched Sub-Lambdas
Per-op lambdas: refactor=[τ μ|Δ Σ/μ|OODA], debug=[μ|Δ λ ∞/0|OODA], test=[π ∞/0|Δ λ|RGR], review=[τ ∞/0|Δ λ|OODA]. Same preamble, different operator subsets prime different modes. Apply: prepend per-op lambda (improve/refactor/experiment/document/analyze) to agent system prompt.
```

Let me count: that's roughly 1900 chars. Still over. Need to cut more.

Let me try a tighter version. The prompt says max 1200 chars for the digest body.

Let me trim harder - aim for 1 pattern per source plus the external:

</think>I have rich material from all three priority repos. Now I have enough to synthesize. Let me check that I'm under 1200 chars for the digest body and the JSON is valid.<think>
Still 1831 chars - over 1200. Need to cut more. Let me trim aggressively. Cut to 1.5 patterns per source.
</think><think>
Still 1566. Need to cut more. Let me try removing the external section and merging it, or just trimming the per-source commentary.

</think><think>

1319. Need to cut 120 chars more to hit 1200. Let me trim a bit more.

</think><think>

Still 1269. Need to cut ~70 more chars. Let me drop "review" lambda (it's redundant with the example) and trim a few more words.

Actually I removed review already. Let me cut more.

Or wait - "Max 1200 chars" - this could be interpreted as 1200 chars soft cap. Let me check: "Max 1200 chars. Prioritize depth over breadth." - so 1200 is the hard cap.

Let me trim a few more chars.

</think><think>

Still 1205, just barely over. Let me cut a few more chars.

Actually wait - 1200 is the cap and I'm at 1205. Just need 5 more chars cut. Easy.

Let me remove the redundant "Operator subset primes mode" line ending since "Same preamble" already conveys it.

Actually let me just cut the last "Apply:" line a bit.
</think><think>


Now 1194 chars - under 1200. 

Now let me write the full response with the JSON metadata at the end.

Sources to list in JSON: nucleus, mementum, gptel, zylos.ai

Topics covered: error-recovery, memory-hierarchy, tool-spec, prompt-compiler, sub-lambdas

Confidence: I have 5 well-supported insights from 4 sources (3 own + 1 external), so 0.72-0.75 confidence.

Insights count: 5
Tokens estimate: ~1100-1200

Let me w
...[Result too large, truncated. Full result saved to: /home/davidwu/.emacs.d/var/tmp/gptel-subagent-result-CXT85Y.txt. Use Read tool if you need more]...

**Meta-learning:** Research quality measured by downstream experiment success.

---
*Generated by auto-workflow*
