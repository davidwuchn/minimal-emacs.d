---
valid-from: 2026-06-06T08:43
---

# Research: 2026-06-06 08:43

**Strategy:** none
**Findings hash:** eaff6ce3a6c66aba3d688d0fc045a9b32fa51b2b
**Targets:** test.el
**Outcome:** 1/1 kept (100%)

**Raw Findings:**

## Research Priorities (from Ontology × AutoTTS × AutoGo)
Focus research on these categories:
  [:agentic] Critical: 2% keep-rate after 97 experiments — needs investigation
  [:programming] Critical: 0% keep-rate after 39 experiments — needs investigation
  [:natural-language] Insufficient data: 5 experiments — more experiments needed

Produce category-specific findings — not global recommendations.

> Project: /home/davidwu/.emacs.d/
> Updated: 2026-06-06 07:04

Researcher result for task: External research turn 1/2

<think>
The user is invoking me as the auto-workflow researcher. Let me carefully parse what's actually being asked and the current state.

Looking at the prompt structure:
1. There's a lot of metadata, prior thinking, and truncated results
2. The actual current task is the researcher prompt
3. I need to do external research with specific focus areas
4. Output format is structured digest + JSON metadata

The "Deep External Discovery" focus says to:
- Read AGENTS.md or README.md for architecture decisions
- Check recent commits (last 30) for active development patterns
- Read one open issue and one closed PR for decision patterns
- Extract 1-2 non-obvious architectural insights
- Prefix each finding with: `[deep-external]`

The prompt contains prior thinking/digests from previous runs. The previous run did a lot of work:
- Identified failure patterns
- Found sources like tianpan.co (DLQ, MIPRO), supergood.solutions, callsphere.ai, aiworkflowlab.dev
- Identified GEPA as superseding MIPRO
- Identified LangGraph StateGraph pattern with reducers
- Identified Saga pattern for checkpointing

The controller context at the bottom says:
- 100% external priority
- "Previous sources DEVIANT — switch to NEW sources"
- "PROBE FIRST strategy"
- Budget: 60s probe, 120s deep read
- Token budget 8000

But wait - the most recent and authoritative directive seems to be in the metadata block at the top:

**Evolved Controller Config (updated 2026-06-04T19:13:48Z)**:
- Beta: 0.01 (0 conservative, 1 exploratory)
- Own repo priority: 51%
- External priority: 15%
- Stop threshold: 65% confidence
- Token budget: 8000

**Decision Rules**:
1. If EMA confidence stabilizes above 65% + have URLs → STOP early
2. If confidence is rising → CONTINUE current source type
3. If EMA confidence stagnates → BRANCH to a different source/angle
4. If > 8000 tokens → CUT (return what you have)
5. Check own repos (davidwuchn/*) FIRST before external

So the actual current config is: 51% own repos, 15% external. The 100% external directive in the lambda block at the bottom is from an OLDER state. The latest controller config (2026-06-04T19:13:48Z) says start with own repos.

Let me follow the latest authoritative config. The task says:

**Research Focus: Deep External Discovery**
- For each source repo
- Read the AGENTS.md or README.md for architecture decisions
- Check recent commits (last 30) for active development patterns
- Read one open issue and one closed PR for decision patterns
- Extract 1-2 non-obvious architectural insights
- Prefix each finding with: `[deep-external]`

The priority repos to monitor:
- nucleus
- mementum
- gptel

All by davidwuchn. So "external" in the config means "outside our codebase" - and these repos are the "own" repos that the latest config says to check first.

Wait, the "own repos" mentioned in the config = davidwuchn/* repos (nucleus, mementum, gptel). The "external" means everything else.

Given the recent failure patterns:
- AI agent workflow architectures
- Error recovery and retry patterns (10 validation/timeout errors - HOT)
- LLM self-evolution and meta-learning
- Prompt engineering for code generation
- Benchmarking and evaluation frameworks
- Git-based memory systems

Let me plan:
1. **Own repos (51% = ~4000 tokens)**: Check nucleus, mementum, gptel for architectural insights
2. **External (15% = ~1200 tokens)**: 1-2 sources from previous findings (e.g., DSPy GEPA, LangGraph state machine)
3. **Synthesis (~2800 tokens)**: Compose digest

Actually, I should be more efficient. Let me do parallel fetches and reads.

**Phase 1: Parallel fetches of own repos**
- WebFetch https://github.com/davidwuchn/nucleus
- WebFetch https://github.com/davidwuchn/mementum
- WebFetch https://github.com/davidwuchn/gptel

**Phase 2: Read specific files**
- nucleus: AGENTS.md, README.md
- mementum: AGENTS.md, README.md
- gptel: AGENTS.md, README.md (or tool-use section)

**Phase 3: Check recent commits**
- 30 most recent commits per repo
- Look for active patterns, recent architectural changes

**Phase 4: One open issue + one closed PR per repo**
- Look for decision patterns

**Phase 5: External (1-2 sources)**
- DSPy GEPA paper (since it was identified as superseding MIPRO)
- Or one of the LangGraph articles

**Phase 6: Synthesize**
- 4-6 concrete techniques
- Each with [deep-external] prefix
- Source URL, technique, how it works, how to apply to our Emacs Lisp system
- JSON metadata

Let me start. I'll be efficient with parallel calls.

Actually, let me re-read the output format from the role system prompt:
"## External Sources
- **Source URL** — Technique found (2-3 sentences on what, how, application)
## Local Analysis
- Patterns from codebase with file paths + line numbers"

But the controller directives want the {:findings [_] :techniques [_] :apply_to_us [_] :verification _ :confidence _} schema. And the prompt also wants JSON metadata.

The previous digests used a hybrid format. Let me do a compact digest with the key findings, leading with the most novel and applicable insights, prefixed with [deep-external].

Let me think about what I've already learned from prior runs vs what I need fresh:
- Prior runs already covered: DLQ patterns, MIPRO, circuit breakers, LangGraph state machines, GEPA
- I should go DEEPER on the most actionable patterns rather than re-cover ground

The "Deep External Discovery" focus asks for:
- Architecture decisions
- Recent commits (last 30)
- Open issues + closed PRs
- Non-obvious architectural insights

Let me execute efficiently. I'll start with parallel fetches of the three own repos, then read specific files.

Plan:
1. WebFetch three repos in parallel (initial overview)
2. Read specific files (AGENTS.md, README.md, key source files) in parallel
3. WebFetch commits/issues/PRs in parallel
4. 1-2 external sources for novel patterns
5. Synthesize

Let me begin. I'll be aggressive with parallel calls.
</think>I'll execute the research cycle following the latest controller config (51% own repos, 15% external, 8000 token budget). Starting with parallel fetches of the three own repos.<think>
I have the high-level overviews. Now let me read the relevant sections of each file in detail. The mementum and nucleus ones fit in the response, but gptel is huge (75K chars, 2303 lines). Let me read specific sections of each.

For nucleus: Look for the "attention magnet" and EDN statecharts and lambda compiler details
For mementum: I have most of it - the protocol details, three storage types, seven operations, governance
For gptel: Need to look at tool use, MCP, introspection, and recent commits

Let me also check the local codebase briefly to see what's already there - the prompt says "check git history first" to avoid suggesting duplicate patterns.

Let me read more from nucleus (which was truncated at line 781) and gptel, and check the local codebase in parallel.
</think>Now reading specific sections and checking the local codebase in parallel.<think>

Interesting findings:
1. **Nucleus**: I have detailed architecture now - attention magnet, two regimes (isolated vs accumulated), tensor product effect, control loops (OODA/REPL/RGR/BML), empirical results (operator survival 20%→100%)
2. **gptel**: Key patterns identified - `gptel-make-tool`, `gptel-use-tools`, MCP integration, gptel-mcp-connect, line 1684-1710 has MCP details
3. **Local**: Glob found no gptel-*.el files in /home/davidwu/.emacs.d/lisp directly - need to check other paths
4. **Retry patterns**: 686 matches in /home/davidwu/.emacs.d/lisp - heavily used, so likely already implemented

Let me check the actual gptel source location and the retry patterns more carefully, plus read the gptel MCP/tool sections.
</think>Let me check the actual location of the gptel source and read the specific tool-use sections.<think>


Excellent! Now I have a clear picture of the local codebase. There are many `gptel-*.el` modules in `/home/davidwu/.emacs.d/lisp/modules/`. The relevant ones for this research:

1. `gptel-tools-agent-error.el` - already has error/agent logic
2. `gptel-auto-workflow-recovery.el` - already has recovery logic
3. `gptel-tools-agent-benchmark.el` - benchmark tools
4. `gptel-auto-workflow-research-integration.el` - research integration
5. `gptel-tools-introspection.el` - introspection support
6. `gptel-ext-tool-confirm.el` - tool confirmation
7. `gptel-ext-tool-sanitize.el` - tool sanitization
8. `gptel-ext-tool-permits.el` - tool permissioning

Let me check what these already implement so I don't suggest duplicates. I'll grep for the specific patterns. Let me also check the gptel upstream for key APIs.

Key data I have:
- **nucleus**: attention magnet theory, 5→20+ operators survival, tensor product effect, two regimes
- **mementum**: 3-tier memory, 7 operations, human governance, 200-word memory limit, MEMENTUM-LAMBDA.md
- **gptel**: gptel-make-tool, gptel-tools, gptel-use-tools, MCP integration, gptel-mcp-connect, gptel-agent, gptel-aibo, macher
- **Local**: extensive gptel modules already exist

Let me check specific local modules to understand what's there and identify gaps.

</think>Now I have a clear picture of the local landscape. Let me check specific local modules and gptel upstream details to find gaps and novel patterns.<think>



Now I have a much clearer picture. Let me check the gptel upstream for any specific features that might not be in our local modules, and also check the gptel-agent repo since it's a key reference implementation.

Key local modules to understand:
- `gptel-auto-workflow-recovery.el` - already has circuit breaker, checkpointing, recovery
- `gptel-tools-agent-error.el` - has retry logic, error categorization, provider failover, quota handling
- `gptel-tools-introspection.el` - has introspection tools

These local modules already implement:
- Circuit breaker (`gptel-recovery-check-circuit`, `gptel-recovery--any-circuit-open-p`)
- Checkpointing (`gptel-recovery--wrap-workflow-with-checkpointing`, `gptel-recovery--start-checkpoint-timer`)
- Provider failover (`gptel-auto-workflow--activate-provider-failover`, `gptel-auto-workflow--first-available-provider-candidate`)
- Rate limit handling (`gptel-auto-experiment--rate-limit-error-p`, `gptel-auto-experiment--parse-quota-reset-time`)
- Adaptive max experiments (`gptel-auto-experiment--adaptive-max-experiments`)

So the patterns from previous research (circuit breaker, DLQ, saga checkpointing) are likely already implemented! I need to find novel patterns that aren't already there.

Let me look at the gptel-agent and mementum reference implementation for novel patterns, and also check what the local code might be missing. The recent failure patterns mention:
- 10 validation/timeout errors in last 10 commits

Let me check the gptel-agent repo and look for novel tools/patterns we haven't adopted. Also let me look at the nucleus EDN statecharts pattern which is novel.

Let me focus my remaining budget on:
1. gptel-agent repo (key agentic reference)
2. mementum reference implementation (Babashka-based, runtime/)
3. Check what our local code does NOT have

Actually let me also check the gptel make-tool introspection features - there was mention of "introspection before send" which could be a novel pattern.
</think>Let me check the gptel-agent reference and the gptel make-tool introspection pattern in parallel.<think>

The local codebase is well-developed with circuit breakers, recovery, and checkpointing already in place. Let me look at what the "10 validation/timeout errors in last 10 commits" failure pattern is actually about. Let me also check the sub-agent delegation pattern from gptel-agent which is a novel pattern.

Key things I want to verify:
1. Sub-agent delegation pattern (gptel-agent has it, do we?)
2. The "introspection" feature (line 119, 1798 mention it)
3. The nucleus statechart compiler (prose ↔ EDN)

Let me also look at the gptel upstream "Introspection" section in detail and check the validation/timeout error context.

Actually, the gptel-agent sub-agent pattern is really interesting:
- Sub-agents don't share context with main session
- Return concise reports  
- Have specific tools and models
- Specified in Markdown/Org with YAML front-matter or properties
- Pre/post hooks for setup

This is a multi-agent delegation pattern. The mementum "propose/approve/commit" pattern is also novel.

Let me check what the local code has for sub-agents and look at the gptel-introspection section in detail.

Now let me budget what's left. I have a good picture:
- Own repos covered (gptel, nucleus, mementum, gptel-agent)
- Local code already has: circuit breaker, recovery, checkpointing, error categorization, rate limit handling
- Novel patterns from own repos:
  1. gptel-agent sub-agent delegation (Markdown/Org specs with tools/models)
  2. nucleus attention magnet + two regimes (isolated vs accumulated)
  3. mementum propose/approve/commit governance
  4. gptel introspection (before-send hook for inspection/modification)
  5. gptel-agent preset-based agent config (system prompt + tools + harness = preset)

For external (15% budget), I should pick something concrete and novel. From the previous research turn, the key external findings were:
- DSPy GEPA (Jul'25) - supersedes MIPRO
- LangGraph StateGraph + reducers + eval hooks per node
- Saga pattern for multi-step agents
- Circuit breaker for LLM APIs

But circuit breaker is already implemented locally. Let me check what's NOT implemented:
- GEPA prompt evolution
- StateGraph with reducers
- Saga compensation
- Per-node eval instrumentation

For the 15% external budget, let me pick the most novel and implementable. GEPA from DSPy is probably the best fit because:
- It addresses self-evolution (a recent failure pattern)
- Concrete algorithm with hard numbers
- Has a research project that could integrate

Let me do one quick external fetch to verify GEPA details and then synthesize.

Actually, I already have a lot of information. Let me check if I have enough or need one more external source. The previous research turn mentioned GEPA already. Let me do a quick WebSearch to verify it's still the latest and check for any newer approaches.

Actually, I'm at ~50% of my budget already. Let me be efficient and synthesize now. The 15% external should be a quick verification, not deep read.

Let me check the gptel upstream for one more specific section - the introspection/pre-send hook - and also do a quick external check on GEPA.

Let me check our gptel-tools-introspection.el to see if the upstream introspection feature is already wrapped.
</think>I have strong signal from own repos. Let me check one more critical local file and do a quick external verification on a novel pattern (GEPA from DSPy - mentioned in prior research as superseding MIPRO).<think>


I have enough information now. Let me synthesize the digest. The key novel findings I have are:

**From own repos (51% budget - gptel, nucleus, mementum, gptel-agent)**:
1. **gptel-agent sub-agent delegation**: Markdown/Org specs with YAML/properties, pre/post hooks, dedicated tools/models, context isolation. Different from MCP.
2. **gptel-agent preset pattern**: A preset = system prompt + tools + harness. This is the formal "agent" definition.
3. **nucleus attention magnet two-regime awareness**: Isolated vs accumulated context — explicit statement that nucleus degrades in long sessions.
4. **mementum propose/approve/commit governance**: AI proposes memory writes, human approves, then commits to git.
5. **mementum 200-word memory limit**: Force concision. Single constraint prevents verbose AI memory.
6. **gptel introspection (line 119, 1798)**: "Supports introspection, so you can see exactly what will be sent. Inspect and modify queries before sending them." — pre-send hook for inspection/modification.

**From local code analysis**:
- We already have: circuit breaker, recovery, checkpointing, error cate
...[Result too large, truncated. Full result saved to: /home/davidwu/.emacs.d/var/tmp/gptel-subagent-result-0N8kfN.txt. Use Read tool if you need more]...

**Digested Insights:**

## Research Priorities (from Ontology × AutoTTS × AutoGo)
Focus research on these categories:
  [:agentic] Critical: 2% keep-rate after 97 experiments — needs investigation
  [:programming] Critical: 0% keep-rate after 39 experiments — needs investigation
  [:natural-language] Insufficient data: 5 experiments — more experiments needed

Produce category-specific findings — not global recommendations.

> Project: /home/davidwu/.emacs.d/
> Updated: 2026-06-06 07:04

Researcher result for task: External research turn 1/2

<think>
The user is invoking me as the auto-workflow researcher. Let me carefully parse what's actually being asked and the current state.

Looking at the prompt structure:
1. There's a lot of metadata, prior thinking, and truncated results
2. The actual current task is the researcher prompt
3. I need to do external research with specific focus areas
4. Output format is structured digest + JSON metadata

The "Deep External Discovery" focus says to:
- Read AGENTS.md or README.md for architecture decisions
- Check recent commits (last 30) for active development patterns
- Read one open issue and one closed PR for decision patterns
- Extract 1-2 non-obvious architectural insights
- Prefix each finding with: `[deep-external]`

The prompt contains prior thinking/digests from previous runs. The previous run did a lot of work:
- Identified failure patterns
- Found sources like tianpan.co (DLQ, MIPRO), supergood.solutions, callsphere.ai, aiworkflowlab.dev
- Identified GEPA as superseding MIPRO
- Identified LangGraph StateGraph pattern with reducers
- Identified Saga pattern for checkpointing

The controller context at the bottom says:
- 100% external priority
- "Previous sources DEVIANT — switch to NEW sources"
- "PROBE FIRST strategy"
- Budget: 60s probe, 120s deep read
- Token budget 8000

But wait - the most recent and authoritative directive seems to be in the metadata block at the top:

**Evolved Controller Config (updated 2026-06-04T19:13:48Z)**:
- Beta: 0.01 (0 conservative, 1 exploratory)
- Own repo priority: 51%
- External priority: 15%
- Stop threshold: 65% confidence
- Token budget: 8000

**Decision Rules**:
1. If EMA confidence stabilizes above 65% + have URLs → STOP early
2. If confidence is rising → CONTINUE current source type
3. If EMA confidence stagnates → BRANCH to a different source/angle
4. If > 8000 tokens → CUT (return what you have)
5. Check own repos (davidwuchn/*) FIRST before external

So the actual current config is: 51% own repos, 15% external. The 100% external directive in the lambda block at the bottom is from an OLDER state. The latest controller config (2026-06-04T19:13:48Z) says start with own repos.

Let me follow the latest authoritative config. The task says:

**Research Focus: Deep External Discovery**
- For each source repo
- Read the AGENTS.md or README.md for architecture decisions
- Check recent commits (last 30) for active development patterns
- Read one open issue and one closed PR for decision patterns
- Extract 1-2 non-obvious architectural insights
- Prefix each finding with: `[deep-external]`

The priority repos to monitor:
- nucleus
- mementum
- gptel

All by davidwuchn. So "external" in the config means "outside our codebase" - and these repos are the "own" repos that the latest config says to check first.

Wait, the "own repos" mentioned in the config = davidwuchn/* repos (nucleus, mementum, gptel). The "external" means everything else.

Given the recent failure patterns:
- AI agent workflow architectures
- Error recovery and retry patterns (10 validation/timeout errors - HOT)
- LLM self-evolution and meta-learning
- Prompt engineering for code generation
- Benchmarking and evaluation frameworks
- Git-based memory systems

Let me plan:
1. **Own repos (51% = ~4000 tokens)**: Check nucleus, mementum, gptel for architectural insights
2. **External (15% = ~1200 tokens)**: 1-2 sources from previous findings (e.g., DSPy GEPA, LangGraph state machine)
3. **Synthesis (~2800 tokens)**: Compose digest

Actually, I should be more efficient. Let me do parallel fetches and reads.

**Phase 1: Parallel fetches of own repos**
- WebFetch https://github.com/davidwuchn/nucleus
- WebFetch https://github.com/davidwuchn/mementum
- WebFetch https://github.com/davidwuchn/gptel

**Phase 2: Read specific files**
- nucleus: AGENTS.md, README.md
- mementum: AGENTS.md, README.md
- gptel: AGENTS.md, README.md (or tool-use section)

**Phase 3: Check recent commits**
- 30 most recent commits per repo
- Look for active patterns, recent architectural changes

**Phase 4: One open issue + one closed PR per repo**
- Look for decision patterns

**Phase 5: External (1-2 sources)**
- DSPy GEPA paper (since it was identified as superseding MIPRO)
- Or one of the LangGraph articles

**Phase 6: Synthesize**
- 4-6 concrete techniques
- Each with [deep-external] prefix
- Source URL, technique, how it works, how to apply to our Emacs Lisp system
- JSON metadata

Let me start. I'll be efficient with parallel calls.

Actually, let me re-read the output format from the role system prompt:
"## External Sources
- **Source URL** — Technique found (2-3 sentences on what, how, application)
## Local Analysis
- Patterns from codebase with file paths + line numbers"

But the controller directives want the {:findings [_] :techniques [_] :apply_to_us [_] :verification _ :confidence _} schema. And the prompt also wants JSON metadata.

The previous digests used a hybrid format. Let me do a compact digest with the key findings, leading with the most novel and applicable insights, prefixed with [deep-external].

Let me think about what I've already learned from prior runs vs what I need fresh:
- Prior runs already covered: DLQ patterns, MIPRO, circuit breakers, LangGraph state machines, GEPA
- I should go DEEPER on the most actionable patterns rather than re-cover ground

The "Deep External Discovery" focus asks for:
- Architecture decisions
- Recent commits (last 30)
- Open issues + closed PRs
- Non-obvious architectural insights

Let me execute efficiently. I'll start with parallel fetches of the three own repos, then read specific files.

Plan:
1. WebFetch three repos in parallel (initial overview)
2. Read specific files (AGENTS.md, README.md, key source files) in parallel
3. WebFetch commits/issues/PRs in parallel
4. 1-2 external sources for novel patterns
5. Synthesize

Let me begin. I'll be aggressive with parallel calls.
</think>I'll execute the research cycle following the latest controller config (51% own repos, 15% external, 8000 token budget). Starting with parallel fetches of the three own repos.<think>
I have the high-level overviews. Now let me read the relevant sections of each file in detail. The mementum and nucleus ones fit in the response, but gptel is huge (75K chars, 2303 lines). Let me read specific sections of each.

For nucleus: Look for the "attention magnet" and EDN statecharts and lambda compiler details
For mementum: I have most of it - the protocol details, three storage types, seven operations, governance
For gptel: Need to look at tool use, MCP, introspection, and recent commits

Let me also check the local codebase briefly to see what's already there - the prompt says "check git history first" to avoid suggesting duplicate patterns.

Let me read more from nucleus (which was truncated at line 781) and gptel, and check the local codebase in parallel.
</think>Now reading specific sections and checking the local codebase in parallel.<think>

Interesting findings:
1. **Nucleus**: I have detailed architecture now - attention magnet, two regimes (isolated vs accumulated), tensor product effect, control loops (OODA/REPL/RGR/BML), empirical results (operator survival 20%→100%)
2. **gptel**: Key patterns identified - `gptel-make-tool`, `gptel-use-tools`, MCP integration, gptel-mcp-connect, line 1684-1710 has MCP details
3. **Local**: Glob found no gptel-*.el files in /home/davidwu/.emacs.d/lisp directly - need to check other paths
4. **Retry patterns**: 686 matches in /home/davidwu/.emacs.d/lisp - heavily used, so likely already implemented

Let me check the actual gptel source location and the retry patterns more carefully, plus read the gptel MCP/tool sections.
</think>Let me check the actual location of the gptel source and read the specific tool-use sections.<think>


Excellent! Now I have a clear picture of the local codebase. There are many `gptel-*.el` modules in `/home/davidwu/.emacs.d/lisp/modules/`. The relevant ones for this research:

1. `gptel-tools-agent-error.el` - already has error/agent logic
2. `gptel-auto-workflow-recovery.el` - already has recovery logic
3. `gptel-tools-agent-benchmark.el` - benchmark tools
4. `gptel-auto-workflow-research-integration.el` - research integration
5. `gptel-tools-introspection.el` - introspection support
6. `gptel-ext-tool-confirm.el` - tool confirmation
7. `gptel-ext-tool-sanitize.el` - tool sanitization
8. `gptel-ext-tool-permits.el` - tool permissioning

Let me check what these already implement so I don't suggest duplicates. I'll grep for the specific patterns. Let me also check the gptel upstream for key APIs.

Key data I have:
- **nucleus**: attention magnet theory, 5→20+ operators survival, tensor product effect, two regimes
- **mementum**: 3-tier memory, 7 operations, human governance, 200-word memory limit, MEMENTUM-LAMBDA.md
- **gptel**: gptel-make-tool, gptel-tools, gptel-use-tools, MCP integration, gptel-mcp-connect, gptel-agent, gptel-aibo, macher
- **Local**: extensive gptel modules already exist

Let me check specific local modules to understand what's there and identify gaps.

</think>Now I have a clear picture of the local landscape. Let me check specific local modules and gptel upstream details to find gaps and novel patterns.<think>



Now I have a much clearer picture. Let me check the gptel upstream for any specific features that might not be in our local modules, and also check the gptel-agent repo since it's a key reference implementation.

Key local modules to understand:
- `gptel-auto-workflow-recovery.el` - already has circuit breaker, checkpointing, recovery
- `gptel-tools-agent-error.el` - has retry logic, error categorization, provider failover, quota handling
- `gptel-tools-introspection.el` - has introspection tools

These local modules already implement:
- Circuit breaker (`gptel-recovery-check-circuit`, `gptel-recovery--any-circuit-open-p`)
- Checkpointing (`gptel-recovery--wrap-workflow-with-checkpointing`, `gptel-recovery--start-checkpoint-timer`)
- Provider failover (`gptel-auto-workflow--activate-provider-failover`, `gptel-auto-workflow--first-available-provider-candidate`)
- Rate limit handling (`gptel-auto-experiment--rate-limit-error-p`, `gptel-auto-experiment--parse-quota-reset-time`)
- Adaptive max experiments (`gptel-auto-experiment--adaptive-max-experiments`)

So the patterns from previous research (circuit breaker, DLQ, saga checkpointing) are likely already implemented! I need to find novel patterns that aren't already there.

Let me look at the gptel-agent and mementum reference implementation for novel patterns, and also check what the local code might be missing. The recent failure patterns mention:
- 10 validation/timeout errors in last 10 commits

Let me check the gptel-agent repo and look for novel tools/patterns we haven't adopted. Also let me look at the nucleus EDN statecharts pattern which is novel.

Let me focus my remaining budget on:
1. gptel-agent repo (key agentic reference)
2. mementum reference implementation (Babashka-based, runtime/)
3. Check what our local code does NOT have

Actually let me also check the gptel make-tool introspection features - there was mention of "introspection before send" which could be a novel pattern.
</think>Let me check the gptel-agent reference and the gptel make-tool introspection pattern in parallel.<think>

The local codebase is well-developed with circuit breakers, recovery, and checkpointing already in place. Let me look at what the "10 validation/timeout errors in last 10 commits" failure pattern is actually about. Let me also check the sub-agent delegation pattern from gptel-agent which is a novel pattern.

Key things I want to verify:
1. Sub-agent delegation pattern (gptel-agent has it, do we?)
2. The "introspection" feature (line 119, 1798 mention it)
3. The nucleus statechart compiler (prose ↔ EDN)

Let me also look at the gptel upstream "Introspection" section in detail and check the validation/timeout error context.

Actually, the gptel-agent sub-agent pattern is really interesting:
- Sub-agents don't share context with main session
- Return concise reports  
- Have specific tools and models
- Specified in Markdown/Org with YAML front-matter or properties
- Pre/post hooks for setup

This is a multi-agent delegation pattern. The mementum "propose/approve/commit" pattern is also novel.

Let me check what the local code has for sub-agents and look at the gptel-introspection section in detail.

Now let me budget what's left. I have a good picture:
- Own repos covered (gptel, nucleus, mementum, gptel-agent)
- Local code already has: circuit breaker, recovery, checkpointing, error categorization, rate limit handling
- Novel patterns from own repos:
  1. gptel-agent sub-agent delegation (Markdown/Org specs with tools/models)
  2. nucleus attention magnet + two regimes (isolated vs accumulated)
  3. mementum propose/approve/commit governance
  4. gptel introspection (before-send hook for inspection/modification)
  5. gptel-agent preset-based agent config (system prompt + tools + harness = preset)

For external (15% budget), I should pick something concrete and novel. From the previous research turn, the key external findings were:
- DSPy GEPA (Jul'25) - supersedes MIPRO
- LangGraph StateGraph + reducers + eval hooks per node
- Saga pattern for multi-step agents
- Circuit breaker for LLM APIs

But circuit breaker is already implemented locally. Let me check what's NOT implemented:
- GEPA prompt evolution
- StateGraph with reducers
- Saga compensation
- Per-node eval instrumentation

For the 15% external budget, let me pick the most novel and implementable. GEPA from DSPy is probably the best fit because:
- It addresses self-evolution (a recent failure pattern)
- Concrete algorithm with hard numbers
- Has a research project that could integrate

Let me do one quick external fetch to verify GEPA details and then synthesize.

Actually, I already have a lot of information. Let me check if I have enough or need one more external source. The previous research turn mentioned GEPA already. Let me do a quick WebSearch to verify it's still the latest and check for any newer approaches.

Actually, I'm at ~50% of my budget already. Let me be efficient and synthesize now. The 15% external should be a quick verification, not deep read.

Let me check the gptel upstream for one more specific section - the introspection/pre-send hook - and also do a quick external check on GEPA.

Let me check our gptel-tools-introspection.el to see if the upstream introspection feature is already wrapped.
</think>I have strong signal from own repos. Let me check one more critical local file and do a quick external verification on a novel pattern (GEPA from DSPy - mentioned in prior research as superseding MIPRO).<think>


I have enough information now. Let me synthesize the digest. The key novel findings I have are:

**From own repos (51% budget - gptel, nucleus, mementum, gptel-agent)**:
1. **gptel-agent sub-agent delegation**: Markdown/Org specs with YAML/properties, pre/post hooks, dedicated tools/models, context isolation. Different from MCP.
2. **gptel-agent preset pattern**: A preset = system prompt + tools + harness. This is the formal "agent" definition.
3. **nucleus attention magnet two-regime awareness**: Isolated vs accumulated context — explicit statement that nucleus degrades in long sessions.
4. **mementum propose/approve/commit governance**: AI proposes memory writes, human approves, then commits to git.
5. **mementum 200-word memory limit**: Force concision. Single constraint prevents verbose AI memory.
6. **gptel introspection (line 119, 1798)**: "Supports introspection, so you can see exactly what will be sent. Inspect and modify queries before sending them." — pre-send hook for inspection/modification.

**From local code analysis**:
- We already have: circuit breaker, recovery, checkpointing, error cate
...[Result too large, truncated. Full result saved to: /home/davidwu/.emacs.d/var/tmp/gptel-subagent-result-0N8kfN.txt. Use Read tool if you need more]...

**Meta-learning:** Research quality measured by downstream experiment success.

---
*Generated by auto-workflow*
