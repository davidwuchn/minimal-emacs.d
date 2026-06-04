# Research: 2026-06-04 17:26

**Strategy:** persisted-findings
**Findings hash:** 269d8aa520fe1c257a49ccb68233f3dd456d08cf
**Targets:** lisp/modules/gptel-benchmark-subagent.el, lisp/modules/gptel-auto-workflow-ontology-strategy.el
**Outcome:** 0/10 kept (0%)

**Raw Findings:**

> Project: /home/davidwu/.emacs.d/
> Updated: 2026-06-04 15:06

Researcher result for task: External research turn 1/4

<think>
The user has provided a complex prompt that appears to be a meta-prompt for an AI research agent. Let me parse what's actually being asked:

1. The core request is a research task: "Deep External Discovery" - go beyond surface browsing
2. Priority: own repos first (davidwuchn/*), then 1-2 external references
3. Budget: 68% own repos, 21% external
4. Max 1200 chars for output
5. Output format: JSON metadata + structured findings
6. Topics: AI agent architectures, Emacs Lisp AI integration, LLM self-evolution, prompt engineering, error recovery, benchmarking

The metadata indicates:
- Total experiments: 870
- Lambda compiler: unverified
- Health: HEALTHY
- Backend: DeepSeek/deepseek-v4-pro

Let me execute the research plan:

1. **Own repos first** (68% of budget) - Check davidwuchn/* repos:
   - nucleus (mentioned in prompt)
   - mementum (mentioned in prompt)
   - gptel (mentioned in prompt)
   - Plus other relevant ones from past: zeroclaw, context-mode, eca, ai-code-interface.el, nullclaw, Ori-Mnemos, hermes-agent, ml-intern

2. **External references** (21% of budget) - 1-2 sources

3. **Skip previously researched topics**:
   - AI agent workflow architectures
   - Emacs Lisp AI integration patterns
   - LLM self-evolution and meta-learning
   - Code analysis automation
   - Prompt engineering for code generation
   - Error recovery and retry patterns
   - Benchmarking and evaluation frameworks
   - Git-based memory and knowledge systems
   - hermes-agent, zeroclaw, ml-intern

Let me start by fetching the own repos. I'll focus on the three named in the prompt (nucleus, mementum, gptel) and also check for novel patterns in their recent activity.

Let me do parallel WebFetch calls to start.
</think>I'll execute the research plan: own repos first (68%), then 1-2 external references, max 1200 chars output. Starting parallel fetches on davidwuchn repos.<think>
Good initial data. Let me dig into the gptel content to find specific recent patterns, and also look for one or two external references. Let me also check the local codebase for what's already implemented (to avoid re-reporting).

Let me read the cached gptel content and check git log of local repo.

</think><think>

Now I have a strong picture of all three own repos. Let me get one external reference to round out the 68/21 budget split. I'll look for something novel — perhaps a recent paper on agent self-evolution, or a tool that implements a pattern we don't have.

Let me also check the recent gptel commits for novel patterns. The gptel response mentioned a lot of standard things, but I should look at recent commits. The cached gptel file is huge (2303 lines) - I should look at recent commits specifically.

Let me also search for one external reference: a paper or tool on agent error recovery / retry patterns, or a new technique.

Given recent commit pattern shows: 
- MiniMax-M3 backend integration
- Z-AI backend
- DeepSeek executor priority
- Watchdog threshold lowering
- Protected files filter

These suggest the system is doing multi-backend routing with health tracking. That's the existing state.

For novel patterns to extract from own repos:

1. **Nucleus**: 
   - "Semantically equivalent, not identical" framing for prompt outputs
   - Attention magnet theory with empirical evidence
   - Lambda notation for prompt compression
   - Works like programming language when isolated, like guidance when accumulated

2. **Mementum**:
   - Git as memory substrate (already in our system)
   - Three storage types: working memory, memories, knowledge
   - Human governance: AI proposes, human approves
   - Discovery via DNS-based lookup
   - Protocol interoperability for cross-project memory

3. **gptel**:
   - Tool use + MCP integration
   - Multi-modal input
   - "Reasoning" content handling
   - Pause/resume multi-stage requests
   - Introspection (inspect/modify queries before sending)
   - Backend-agnostic, transient menu

For non-obvious novel patterns I haven't seen in past research:
1. **Mementum's "discovery infrastructure" pattern** - DNS-based lookup of conforming repos across GitHub to enable protocol interoperability (network of memory nodes)
2. **Nucleus's "attention magnet" theory with logprob measurement** as a way to validate prompt effects
3. **gptel's "pause multi-stage requests at intermediate stage and resume later"** - stageable request orchestration
4. **Nucleus's failure mode acknowledgment** - drift in accumulated context, training priors winning over notation

Let me search for one external source on a related topic. The past research covered:
- AI agent workflow architectures
- Emacs Lisp AI integration patterns
- LLM self-evolution
- Code analysis automation
- Prompt engineering
- Error recovery and retry patterns
- Benchmarking
- Git-based memory
- hermes-agent, zeroclaw, ml-intern

What's NOT covered? Let me look for:
- Logprob-based prompt validation
- Multi-stage pause/resume patterns
- DNS-based discovery for AI memory
- Backend health watchdog patterns

Let me search for one external paper or tool on a novel angle.
</think>Strong material on own repos. Let me check git log to avoid re-reporting existing patterns, and search for one novel external angle (logprob-based prompt validation is a nucleus-specific idea I haven't seen in past research).<think>


Excellent! I have rich material now. Let me synthesize the digest with the budget allocation:
- 68% own repos: nucleus, mementum, gptel
- 21% external: SE-Agent/SCOPE papers (self-evolution trajectories) + checkpointing pattern

I need to verify these are NOT in our codebase already. Let me check git log for "checkpoint\|trajectory\|SCOPE\|SE-Agent" and look at what's in our state.md.

Looking at the git log:
- "Self-healing pipeline" was added
- "Watchdog" exists
- "Grader-bypass" pattern
- "Auto-evolved mementum"
- "MemGraphRAG" was studied (9 ontology gaps)

The novel angles that ARE NOT in our codebase yet (based on git log):
1. **Logprob measurement for prompt validation** (nucleus theory) - novel, not in git
2. **DNS-based discovery infrastructure** (mementum) - protocol network of memory nodes - novel
3. **Trajectory-level intervention for agent self-evolution** (SE-Agent) - novel
4. **KV cache management for agentic workloads with pauses** (Continuum paper) - novel
5. **Event-history replay / durable execution** (zylos) - novel

Let me check if any of these are present. The git log shows "Self-healing" but not specifically "trajectory" or "durable execution" or "KV cache". 

Let me look at one quick check for "checkpoint" and "trajectory" in the codebase.
</think><think>


Good — so `trajectory` and `checkpoint` already exist in our codebase. `durable-execution`, `event-history`, `logprob`, `KV-cache`, `DNS-based` do NOT. So my novel insights are:

1. **Logprob-based prompt validation** (nucleus theory) — novel
2. **DNS-based memory node discovery** (mementum) — novel  
3. **Trajectory-level intervention for agent self-evolution** (SE-Agent) — partially novel (we have trajectory but not the systematic intervention pattern)
4. **KV cache management for agentic workloads** (Continuum) — novel

Let me also check the experiment TSV data and the state.md to see what's been done recently.

Actually I have enough. Let me synthesize the final digest now. Budget: 1200 chars. Need to be compact.

Let me check the state.md quickly for any context.

</think><think>

Excellent context. The state.md confirms:
- "researcher daemon dead since Jun 3, only PMF running → stale research"
- The system has pipeline hardening, hashline collision reduction, subagent type registration

This validates the urgency of fresh research. Now I have everything I need. Let me write the final digest.

Budget: 1200 chars. I need to be very tight. The output format is:
- Compact structured digest
- Insights with: source URL, key technique, how it applies
- End with JSON metadata

Let me draft:

```
## Researcher Digest — 2026-06-04

### Own Repos (davidwuchn/*) — 68%

**[deep-external] nucleus: Logprob-based prompt validation**
Source: github.com/davidwuchn/nucleus (AGENTS.md "Attention Magnets" section)
Technique: Nucleus theory predicts symbol effectiveness correlates with training-weight salience, not semantic coherence. They propose measuring logprobs of probe tokens to confirm attention shifts empirically.
Apply: Add `gptel-research--measure-attention-shift()` — sample token logprobs before/after preamble injection, return Δ as a scalar in experiment TSV. Use as objective signal in addition to keep-rate.

**[deep-external] mementum: DNS-based memory node discovery**
Source: github.com/davidwuchn/mementum (USAGE.md "discovery infrastructure")
Technique: Mementum repos become network-addressable memory nodes via DNS-based lookup — any conforming repo can be discovered and read by any AI with bash+git. Protocol interoperability today, auto-discovery later.
Apply: Add `mementum-discover.el` — resolve `_mementum._tcp.davidwuchn.com` SRV records, surface remote `knowledge/` pages as recall candidates in our recall protocol.

**[deep-external] gptel: Stageable request pause/resume**
Source: github.com/davidwuchn/gptel (README §Usage → "Pause multi-stage requests")
Technique: gptel natively supports pausing a multi-stage request at intermediate stage and resuming later, with full state preserved.
Apply: We have checkpointing but not for in-flight requests. Add `gptel-agent--stageable-pause(point)` and `gptel-agent--stageable-resume(handle)` to elisp long-running executor tasks that risk timeout (watchdog threshold drops keep eating experiments).

### External — 21%

**[deep-external] SE-Agent: Trajectory-level intervention** (NeurIPS 2025)
Source: arxiv.org/abs/2508.02085
Technique: Intervene at the trajectory level — selectively mutate sub-trajectories, not just sample parameters — to drive self-evolution. We already track trajectories (strategy-convergence-adaptive-ordering.el) but don't mutate them.
Apply: Add trajectory-edit step: keep top-k trajectories, mutate their step boundaries, re-execute, measure keep-rate. Beta=0.02 makes this safe (only 2% exploratory budget).

**[deep-external] Continuum: KV cache for agentic pauses** (arxiv 2511.02230)
Source: arxiv.org/abs/2511.02230
Technique: Inference engines evict finished-request KV cache when new requests wait; breaks for agentic workloads that interleave LLM calls with tool pauses. Preserve cache across pause boundaries.
Apply: When gptel request stages pause, snapshot gptel request KV state to disk keyed by `(backend . request-hash)`. Resume reuses snapshot → no re-tokenization. Cuts latency on resumed multi-stage experiments.

### Skip
- Workflow architectures, prompt engineering basics, Git memory (already covered last cycle).

```json
{
  "strategy_used": "own-repos-first",
  "sources_checked": ["davidwuchn/nucleus","davidwuchn/mementum","davidwuchn/gptel","arxiv/2508.02085","arxiv/2511.02230"],
  "topics_covered": ["logprob-validation","memory-discovery","stageable-pause","trajectory-mutation","kv-cache-pause"],
  "confidence_final": 0.78,
  "insights_count": 5,
  "tokens_estimate": 1180
}
```

Let me count chars. The narrative is around 1500-1700 chars. I need to tighten to ≤1200. Let me compress.

</think>

---

Researcher result for task: External research turn 1/4

<think>
The user has provided a complex prompt that appears to be a meta-prompt for an AI research agent. Let me parse what's actually being asked:

1. The core request is a research task: "Deep External Discovery" - go beyond surface browsing
2. Priority: own repos first (davidwuchn/*), then 1-2 external references
3. Budget: 68% own repos, 21% external
4. Max 1200 chars for output
5. Output format: JSON metadata + structured findings
6. Topics: AI agent architectures, Emacs Lisp AI integration, LLM self-evolution, prompt engineering, error recovery, benchmarking

The metadata indicates:
- Total experiments: 870
- Lambda compiler: unverified
- Health: HEALTHY
- Backend: DeepSeek/deepseek-v4-pro

Let me execute the research plan:

1. **Own repos first** (68% of budget) - Check davidwuchn/* repos:
   - nucleus (mentioned in prompt)
   - mementum (mentioned in prompt)
   - gptel (mentioned in prompt)
   - Plus other relevant ones from past: zeroclaw, context-mode, eca, ai-code-interface.el, nullclaw, Ori-Mnemos, hermes-agent, ml-intern

2. **External references** (21% of budget) - 1-2 sources

3. **Skip previously researched topics**:
   - AI agent workflow architectures
   - Emacs Lisp AI integration patterns
   - LLM self-evolution and meta-learning
   - Code analysis automation
   - Prompt engineering for code generation
   - Error recovery and retry patterns
   - Benchmarking and evaluation frameworks
   - Git-based memory and knowledge systems
   - hermes-agent, zeroclaw, ml-intern

Let me start by fetching the own repos. I'll focus on the three named in the prompt (nucleus, mementum, gptel) and also check for novel patterns in their recent activity.

Let me do parallel WebFetch calls to start.
</think>I'll execute the research plan: own repos first (68%), then 1-2 external references, max 1200 chars output. Starting parallel fetches on davidwuchn repos.<think>
Good initial data. Let me dig into the gptel content to find specific recent patterns, and also look for one or two external references. Let me also check the local codebase for what's already implemented (to avoid re-reporting).

Let me read the cached gptel content and check git log of local repo.

</think><think>

Now I have a strong picture of all three own repos. Let me get one external reference to round out the 68/21 budget split. I'll look for something novel — perhaps a recent paper on agent self-evolution, or a tool that implements a pattern we don't have.

Let me also check the recent gptel commits for novel patterns. The gptel response mentioned a lot of standard things, but I should look at recent commits. The cached gptel file is huge (2303 lines) - I should look at recent commits specifically.

Let me also search for one external reference: a paper or tool on agent error recovery / retry patterns, or a new technique.

Given recent commit pattern shows: 
- MiniMax-M3 backend integration
- Z-AI backend
- DeepSeek executor priority
- Watchdog threshold lowering
- Protected files filter

These suggest the system is doing multi-backend routing with health tracking. That's the existing state.

For novel patterns to extract from own repos:

1. **Nucleus**: 
   - "Semantically equivalent, not identical" framing for prompt outputs
   - Attention magnet theory with empirical evidence
   - Lambda notation for prompt compression
   - Works like programming language when isolated, like guidance when accumulated

2. **Mementum**:
   - Git as memory substrate (already in our system)
   - Three storage types: working memory, memories, knowledge
   - Human governance: AI proposes, human approves
   - Discovery via DNS-based lookup
   - Protocol interoperability for cross-project memory

3. **gptel**:
   - Tool use + MCP integration
   - Multi-modal input
   - "Reasoning" content handling
   - Pause/resume multi-stage requests
   - Introspection (inspect/modify queries before sending)
   - Backend-agnostic, transient menu

For non-obvious novel patterns I haven't seen in past research:
1. **Mementum's "discovery infrastructure" pattern** - DNS-based lookup of conforming repos across GitHub to enable protocol interoperability (network of memory nodes)
2. **Nucleus's "attention magnet" theory with logprob measurement** as a way to validate prompt effects
3. **gptel's "pause multi-stage requests at intermediate stage and resume later"** - stageable request orchestration
4. **Nucleus's failure mode acknowledgment** - drift in accumulated context, training priors winning over notation

Let me search for one external source on a related topic. The past research covered:
- AI agent workflow architectures
- Emacs Lisp AI integration patterns
- LLM self-evolution
- Code analysis automation
- Prompt engineering
- Error recovery and retry patterns
- Benchmarking
- Git-based memory
- hermes-agent, zeroclaw, ml-intern

What's NOT covered? Let me look for:
- Logprob-based prompt validation
- Multi-stage pause/resume patterns
- DNS-based discovery for AI memory
- Backend health watchdog patterns

Let me search for one external paper or tool on a novel angle.
</think>Strong material on own repos. Let me check git log to avoid re-reporting existing patterns, and search for one novel external angle (logprob-based prompt validation is a nucleus-specific idea I haven't seen in past research).<think>


Excellent! I have rich material now. Let me synthesize the digest with the budget allocation:
- 68% own repos: nucleus, mementum, gptel
- 21% external: SE-Agent/SCOPE papers (self-evolution trajectories) + checkpointing pattern

I need to verify these are NOT in our codebase already. Let me check git log for "checkpoint\|trajectory\|SCOPE\|SE-Agent" and look at what's in our state.md.

Looking at the git log:
- "Self-healing pipeline" was added
- "Watchdog" exists
- "Grader-bypass" pattern
- "Auto-evolved mementum"
- "MemGraphRAG" was studied (9 ontology gaps)

The novel angles that ARE NOT in our codebase yet (based on git log):
1. **Logprob measurement for prompt validation** (nucleus theory) - novel, not in git
2. **DNS-based discovery infrastructure** (mementum) - protocol network of memory nodes - novel
3. **Trajectory-level intervention for agent self-evolution** (SE-Agent) - novel
4. **KV cache management for agentic workloads with pauses** (Continuum paper) - novel
5. **Event-history replay / durable execution** (zylos) - novel

Let me check if any of these are present. The git log shows "Self-healing" but not specifically "trajectory" or "durable execution" or "KV cache". 

Let me look at one quick check for "checkpoint" and "trajectory" in the codebase.
</think><think>


Good — so `trajectory` and `checkpoint` already exist in our codebase. `durable-execution`, `event-history`, `logprob`, `KV-cache`, `DNS-based` do NOT. So my novel insights are:

1. **Logprob-based prompt validation** (nucleus theory) — novel
2. **DNS-based memory node discovery** (mementum) — novel  
3. **Trajectory-level intervention for agent self-evolution** (SE-Agent) — partially novel (we have trajectory but not the systematic intervention pattern)
4. **KV cache management for agentic workloads** (Continuum) — novel

Let me also check the experiment TSV data and the state.md to see what's been done recently.

Actually I have enough. Let me synthesize the final digest now. Budget: 1200 chars. Need to be compact.

Let me check the state.md quickly for any context.

</think><think>

Excellent context. The state.md confirms:
- "researcher daemon dead since Jun 3, only PMF running → stale research"
- The system has pipeline hardening, hashline collision reduction, subagent type registration

This validates the urgency of fresh research. Now I have everything I need. Let me write the final digest.

Budget: 1200 chars. I need to be very tight. The output format is:
- Compact structured digest
- Insights with: source URL, key technique, how it applies
- End with JSON metadata

Let me draft:

```
## Researcher Digest — 2026-06-04

### Own Repos (davidwuchn/*) — 68%

**[deep-external] nucleus: Logprob-based prompt validation**
Source: github.com/davidwuchn/nucleus (AGENTS.md "Attention Magnets" section)
Technique: Nucleus theory predicts symbol effectiveness correlates with training-weight salience, not semantic coherence. They propose measuring logprobs of probe tokens to confirm attention shifts empirically.
Apply: Add `gptel-research--measure-attention-shift()` — sample token logprobs before/after preamble injection, return Δ as a scalar in experiment TSV. Use as objective signal in addition to keep-rate.

**[deep-external] mementum: DNS-based memory node discovery**
Source: github.com/davidwuchn/mementum (USAGE.md "discovery infrastructure")
Technique: Mementum repos become network-addressable memory nodes via DNS-based lookup — any conforming repo can be discovered and read by any AI with bash+git. Protocol interoperability today, auto-discovery later.
Apply: Add `mementum-discover.el` — resolve `_mementum._tcp.davidwuchn.com` SRV records, surface remote `knowledge/` pages as recall candidates in our recall protocol.

**[deep-external] gptel: Stageable request pause/resume**
Source: github.com/davidwuchn/gptel (README §Usage → "Pause multi-stage requests")
Technique: gptel natively supports pausing a multi-stage request at intermediate stage and resuming later, with full state preserved.
Apply: We have checkpointing but not for in-flight requests. Add `gptel-agent--stageable-pause(point)` and `gptel-agent--stageable-resume(handle)` to elisp long-running executor tasks that risk timeout (watchdog threshold drops keep eating experiments).

### External — 21%

**[deep-external] SE-Agent: Trajectory-level intervention** (NeurIPS 2025)
Source: arxiv.org/abs/2508.02085
Technique: Intervene at the trajectory level — selectively mutate sub-trajectories, not just sample parameters — to drive self-evolution. We already track trajectories (strategy-convergence-adaptive-ordering.el) but don't mutate them.
Apply: Add trajectory-edit step: keep top-k trajectories, mutate their step boundaries, re-execute, measure keep-rate. Beta=0.02 makes this safe (only 2% exploratory budget).

**[deep-external] Continuum: KV cache for agentic pauses** (arxiv 2511.02230)
Source: arxiv.org/abs/2511.02230
Technique: Inference engines evict finished-request KV cache when new requests wait; breaks for agentic workloads that interleave LLM calls with tool pauses. Preserve cache across pause boundaries.
Apply: When gptel request stages pause, snapshot gptel request KV state to disk keyed by `(backend . request-hash)`. Resume reuses snapshot → no re-tokenization. Cuts latency on resumed multi-stage experiments.

### Skip
- Workflow architectures, prompt engineering basics, Git memory (already covered last cycle).

```json
{
  "strategy_used": "own-repos-first",
  "sources_checked": ["davidwuchn/nucleus","davidwuchn/mementum","davidwuchn/gptel","arxiv/2508.02085","arxiv/2511.02230"],
  "topics_covered": ["logprob-validation","memory-discovery","stageable-pause","trajectory-mutation","kv-cache-pause"],
  "confidence_final": 0.78,
  "insights_count": 5,
  "tokens_estimate": 1180
}
```

Let me count chars. The narrative is around 1500-1700 chars. I need to tighten to ≤1200. Let me compress.

</think>

**Digested Insights:**

> Project: /home/davidwu/.emacs.d/
> Updated: 2026-06-04 15:06

Researcher result for task: External research turn 1/4

<think>
The user has provided a complex prompt that appears to be a meta-prompt for an AI research agent. Let me parse what's actually being asked:

1. The core request is a research task: "Deep External Discovery" - go beyond surface browsing
2. Priority: own repos first (davidwuchn/*), then 1-2 external references
3. Budget: 68% own repos, 21% external
4. Max 1200 chars for output
5. Output format: JSON metadata + structured findings
6. Topics: AI agent architectures, Emacs Lisp AI integration, LLM self-evolution, prompt engineering, error recovery, benchmarking

The metadata indicates:
- Total experiments: 870
- Lambda compiler: unverified
- Health: HEALTHY
- Backend: DeepSeek/deepseek-v4-pro

Let me execute the research plan:

1. **Own repos first** (68% of budget) - Check davidwuchn/* repos:
   - nucleus (mentioned in prompt)
   - mementum (mentioned in prompt)
   - gptel (mentioned in prompt)
   - Plus other relevant ones from past: zeroclaw, context-mode, eca, ai-code-interface.el, nullclaw, Ori-Mnemos, hermes-agent, ml-intern

2. **External references** (21% of budget) - 1-2 sources

3. **Skip previously researched topics**:
   - AI agent workflow architectures
   - Emacs Lisp AI integration patterns
   - LLM self-evolution and meta-learning
   - Code analysis automation
   - Prompt engineering for code generation
   - Error recovery and retry patterns
   - Benchmarking and evaluation frameworks
   - Git-based memory and knowledge systems
   - hermes-agent, zeroclaw, ml-intern

Let me start by fetching the own repos. I'll focus on the three named in the prompt (nucleus, mementum, gptel) and also check for novel patterns in their recent activity.

Let me do parallel WebFetch calls to start.
</think>I'll execute the research plan: own repos first (68%), then 1-2 external references, max 1200 chars output. Starting parallel fetches on davidwuchn repos.<think>
Good initial data. Let me dig into the gptel content to find specific recent patterns, and also look for one or two external references. Let me also check the local codebase for what's already implemented (to avoid re-reporting).

Let me read the cached gptel content and check git log of local repo.

</think><think>

Now I have a strong picture of all three own repos. Let me get one external reference to round out the 68/21 budget split. I'll look for something novel — perhaps a recent paper on agent self-evolution, or a tool that implements a pattern we don't have.

Let me also check the recent gptel commits for novel patterns. The gptel response mentioned a lot of standard things, but I should look at recent commits. The cached gptel file is huge (2303 lines) - I should look at recent commits specifically.

Let me also search for one external reference: a paper or tool on agent error recovery / retry patterns, or a new technique.

Given recent commit pattern shows: 
- MiniMax-M3 backend integration
- Z-AI backend
- DeepSeek executor priority
- Watchdog threshold lowering
- Protected files filter

These suggest the system is doing multi-backend routing with health tracking. That's the existing state.

For novel patterns to extract from own repos:

1. **Nucleus**: 
   - "Semantically equivalent, not identical" framing for prompt outputs
   - Attention magnet theory with empirical evidence
   - Lambda notation for prompt compression
   - Works like programming language when isolated, like guidance when accumulated

2. **Mementum**:
   - Git as memory substrate (already in our system)
   - Three storage types: working memory, memories, knowledge
   - Human governance: AI proposes, human approves
   - Discovery via DNS-based lookup
   - Protocol interoperability for cross-project memory

3. **gptel**:
   - Tool use + MCP integration
   - Multi-modal input
   - "Reasoning" content handling
   - Pause/resume multi-stage requests
   - Introspection (inspect/modify queries before sending)
   - Backend-agnostic, transient menu

For non-obvious novel patterns I haven't seen in past research:
1. **Mementum's "discovery infrastructure" pattern** - DNS-based lookup of conforming repos across GitHub to enable protocol interoperability (network of memory nodes)
2. **Nucleus's "attention magnet" theory with logprob measurement** as a way to validate prompt effects
3. **gptel's "pause multi-stage requests at intermediate stage and resume later"** - stageable request orchestration
4. **Nucleus's failure mode acknowledgment** - drift in accumulated context, training priors winning over notation

Let me search for one external source on a related topic. The past research covered:
- AI agent workflow architectures
- Emacs Lisp AI integration patterns
- LLM self-evolution
- Code analysis automation
- Prompt engineering
- Error recovery and retry patterns
- Benchmarking
- Git-based memory
- hermes-agent, zeroclaw, ml-intern

What's NOT covered? Let me look for:
- Logprob-based prompt validation
- Multi-stage pause/resume patterns
- DNS-based discovery for AI memory
- Backend health watchdog patterns

Let me search for one external paper or tool on a novel angle.
</think>Strong material on own repos. Let me check git log to avoid re-reporting existing patterns, and search for one novel external angle (logprob-based prompt validation is a nucleus-specific idea I haven't seen in past research).<think>


Excellent! I have rich material now. Let me synthesize the digest with the budget allocation:
- 68% own repos: nucleus, mementum, gptel
- 21% external: SE-Agent/SCOPE papers (self-evolution trajectories) + checkpointing pattern

I need to verify these are NOT in our codebase already. Let me check git log for "checkpoint\|trajectory\|SCOPE\|SE-Agent" and look at what's in our state.md.

Looking at the git log:
- "Self-healing pipeline" was added
- "Watchdog" exists
- "Grader-bypass" pattern
- "Auto-evolved mementum"
- "MemGraphRAG" was studied (9 ontology gaps)

The novel angles that ARE NOT in our codebase yet (based on git log):
1. **Logprob measurement for prompt validation** (nucleus theory) - novel, not in git
2. **DNS-based discovery infrastructure** (mementum) - protocol network of memory nodes - novel
3. **Trajectory-level intervention for agent self-evolution** (SE-Agent) - novel
4. **KV cache management for agentic workloads with pauses** (Continuum paper) - novel
5. **Event-history replay / durable execution** (zylos) - novel

Let me check if any of these are present. The git log shows "Self-healing" but not specifically "trajectory" or "durable execution" or "KV cache". 

Let me look at one quick check for "checkpoint" and "trajectory" in the codebase.
</think><think>


Good — so `trajectory` and `checkpoint` already exist in our codebase. `durable-execution`, `event-history`, `logprob`, `KV-cache`, `DNS-based` do NOT. So my novel insights are:

1. **Logprob-based prompt validation** (nucleus theory) — novel
2. **DNS-based memory node discovery** (mementum) — novel  
3. **Trajectory-level intervention for agent self-evolution** (SE-Agent) — partially novel (we have trajectory but not the systematic intervention pattern)
4. **KV cache management for agentic workloads** (Continuum) — novel

Let me also check the experiment TSV data and the state.md to see what's been done recently.

Actually I have enough. Let me synthesize the final digest now. Budget: 1200 chars. Need to be compact.

Let me check the state.md quickly for any context.

</think><think>

Excellent context. The state.md confirms:
- "researcher daemon dead since Jun 3, only PMF running → stale research"
- The system has pipeline hardening, hashline collision reduction, subagent type registration

This validates the urgency of fresh research. Now I have everything I need. Let me write the final digest.

Budget: 1200 chars. I need to be very tight. The output format is:
- Compact structured digest
- Insights with: source URL, key technique, how it applies
- End with JSON metadata

Let me draft:

```
## Researcher Digest — 2026-06-04

### Own Repos (davidwuchn/*) — 68%

**[deep-external] nucleus: Logprob-based prompt validation**
Source: github.com/davidwuchn/nucleus (AGENTS.md "Attention Magnets" section)
Technique: Nucleus theory predicts symbol effectiveness correlates with training-weight salience, not semantic coherence. They propose measuring logprobs of probe tokens to confirm attention shifts empirically.
Apply: Add `gptel-research--measure-attention-shift()` — sample token logprobs before/after preamble injection, return Δ as a scalar in experiment TSV. Use as objective signal in addition to keep-rate.

**[deep-external] mementum: DNS-based memory node discovery**
Source: github.com/davidwuchn/mementum (USAGE.md "discovery infrastructure")
Technique: Mementum repos become network-addressable memory nodes via DNS-based lookup — any conforming repo can be discovered and read by any AI with bash+git. Protocol interoperability today, auto-discovery later.
Apply: Add `mementum-discover.el` — resolve `_mementum._tcp.davidwuchn.com` SRV records, surface remote `knowledge/` pages as recall candidates in our recall protocol.

**[deep-external] gptel: Stageable request pause/resume**
Source: github.com/davidwuchn/gptel (README §Usage → "Pause multi-stage requests")
Technique: gptel natively supports pausing a multi-stage request at intermediate stage and resuming later, with full state preserved.
Apply: We have checkpointing but not for in-flight requests. Add `gptel-agent--stageable-pause(point)` and `gptel-agent--stageable-resume(handle)` to elisp long-running executor tasks that risk timeout (watchdog threshold drops keep eating experiments).

### External — 21%

**[deep-external] SE-Agent: Trajectory-level intervention** (NeurIPS 2025)
Source: arxiv.org/abs/2508.02085
Technique: Intervene at the trajectory level — selectively mutate sub-trajectories, not just sample parameters — to drive self-evolution. We already track trajectories (strategy-convergence-adaptive-ordering.el) but don't mutate them.
Apply: Add trajectory-edit step: keep top-k trajectories, mutate their step boundaries, re-execute, measure keep-rate. Beta=0.02 makes this safe (only 2% exploratory budget).

**[deep-external] Continuum: KV cache for agentic pauses** (arxiv 2511.02230)
Source: arxiv.org/abs/2511.02230
Technique: Inference engines evict finished-request KV cache when new requests wait; breaks for agentic workloads that interleave LLM calls with tool pauses. Preserve cache across pause boundaries.
Apply: When gptel request stages pause, snapshot gptel request KV state to disk keyed by `(backend . request-hash)`. Resume reuses snapshot → no re-tokenization. Cuts latency on resumed multi-stage experiments.

### Skip
- Workflow architectures, prompt engineering basics, Git memory (already covered last cycle).

```json
{
  "strategy_used": "own-repos-first",
  "sources_checked": ["davidwuchn/nucleus","davidwuchn/mementum","davidwuchn/gptel","arxiv/2508.02085","arxiv/2511.02230"],
  "topics_covered": ["logprob-validation","memory-discovery","stageable-pause","trajectory-mutation","kv-cache-pause"],
  "confidence_final": 0.78,
  "insights_count": 5,
  "tokens_estimate": 1180
}
```

Let me count chars. The narrative is around 1500-1700 chars. I need to tighten to ≤1200. Let me compress.

</think>

---

Researcher result for task: External research turn 1/4

<think>
The user has provided a complex prompt that appears to be a meta-prompt for an AI research agent. Let me parse what's actually being asked:

1. The core request is a research task: "Deep External Discovery" - go beyond surface browsing
2. Priority: own repos first (davidwuchn/*), then 1-2 external references
3. Budget: 68% own repos, 21% external
4. Max 1200 chars for output
5. Output format: JSON metadata + structured findings
6. Topics: AI agent architectures, Emacs Lisp AI integration, LLM self-evolution, prompt engineering, error recovery, benchmarking

The metadata indicates:
- Total experiments: 870
- Lambda compiler: unverified
- Health: HEALTHY
- Backend: DeepSeek/deepseek-v4-pro

Let me execute the research plan:

1. **Own repos first** (68% of budget) - Check davidwuchn/* repos:
   - nucleus (mentioned in prompt)
   - mementum (mentioned in prompt)
   - gptel (mentioned in prompt)
   - Plus other relevant ones from past: zeroclaw, context-mode, eca, ai-code-interface.el, nullclaw, Ori-Mnemos, hermes-agent, ml-intern

2. **External references** (21% of budget) - 1-2 sources

3. **Skip previously researched topics**:
   - AI agent workflow architectures
   - Emacs Lisp AI integration patterns
   - LLM self-evolution and meta-learning
   - Code analysis automation
   - Prompt engineering for code generation
   - Error recovery and retry patterns
   - Benchmarking and evaluation frameworks
   - Git-based memory and knowledge systems
   - hermes-agent, zeroclaw, ml-intern

Let me start by fetching the own repos. I'll focus on the three named in the prompt (nucleus, mementum, gptel) and also check for novel patterns in their recent activity.

Let me do parallel WebFetch calls to start.
</think>I'll execute the research plan: own repos first (68%), then 1-2 external references, max 1200 chars output. Starting parallel fetches on davidwuchn repos.<think>
Good initial data. Let me dig into the gptel content to find specific recent patterns, and also look for one or two external references. Let me also check the local codebase for what's already implemented (to avoid re-reporting).

Let me read the cached gptel content and check git log of local repo.

</think><think>

Now I have a strong picture of all three own repos. Let me get one external reference to round out the 68/21 budget split. I'll look for something novel — perhaps a recent paper on agent self-evolution, or a tool that implements a pattern we don't have.

Let me also check the recent gptel commits for novel patterns. The gptel response mentioned a lot of standard things, but I should look at recent commits. The cached gptel file is huge (2303 lines) - I should look at recent commits specifically.

Let me also search for one external reference: a paper or tool on agent error recovery / retry patterns, or a new technique.

Given recent commit pattern shows: 
- MiniMax-M3 backend integration
- Z-AI backend
- DeepSeek executor priority
- Watchdog threshold lowering
- Protected files filter

These suggest the system is doing multi-backend routing with health tracking. That's the existing state.

For novel patterns to extract from own repos:

1. **Nucleus**: 
   - "Semantically equivalent, not identical" framing for prompt outputs
   - Attention magnet theory with empirical evidence
   - Lambda notation for prompt compression
   - Works like programming language when isolated, like guidance when accumulated

2. **Mementum**:
   - Git as memory substrate (already in our system)
   - Three storage types: working memory, memories, knowledge
   - Human governance: AI proposes, human approves
   - Discovery via DNS-based lookup
   - Protocol interoperability for cross-project memory

3. **gptel**:
   - Tool use + MCP integration
   - Multi-modal input
   - "Reasoning" content handling
   - Pause/resume multi-stage requests
   - Introspection (inspect/modify queries before sending)
   - Backend-agnostic, transient menu

For non-obvious novel patterns I haven't seen in past research:
1. **Mementum's "discovery infrastructure" pattern** - DNS-based lookup of conforming repos across GitHub to enable protocol interoperability (network of memory nodes)
2. **Nucleus's "attention magnet" theory with logprob measurement** as a way to validate prompt effects
3. **gptel's "pause multi-stage requests at intermediate stage and resume later"** - stageable request orchestration
4. **Nucleus's failure mode acknowledgment** - drift in accumulated context, training priors winning over notation

Let me search for one external source on a related topic. The past research covered:
- AI agent workflow architectures
- Emacs Lisp AI integration patterns
- LLM self-evolution
- Code analysis automation
- Prompt engineering
- Error recovery and retry patterns
- Benchmarking
- Git-based memory
- hermes-agent, zeroclaw, ml-intern

What's NOT covered? Let me look for:
- Logprob-based prompt validation
- Multi-stage pause/resume patterns
- DNS-based discovery for AI memory
- Backend health watchdog patterns

Let me search for one external paper or tool on a novel angle.
</think>Strong material on own repos. Let me check git log to avoid re-reporting existing patterns, and search for one novel external angle (logprob-based prompt validation is a nucleus-specific idea I haven't seen in past research).<think>


Excellent! I have rich material now. Let me synthesize the digest with the budget allocation:
- 68% own repos: nucleus, mementum, gptel
- 21% external: SE-Agent/SCOPE papers (self-evolution trajectories) + checkpointing pattern

I need to verify these are NOT in our codebase already. Let me check git log for "checkpoint\|trajectory\|SCOPE\|SE-Agent" and look at what's in our state.md.

Looking at the git log:
- "Self-healing pipeline" was added
- "Watchdog" exists
- "Grader-bypass" pattern
- "Auto-evolved mementum"
- "MemGraphRAG" was studied (9 ontology gaps)

The novel angles that ARE NOT in our codebase yet (based on git log):
1. **Logprob measurement for prompt validation** (nucleus theory) - novel, not in git
2. **DNS-based discovery infrastructure** (mementum) - protocol network of memory nodes - novel
3. **Trajectory-level intervention for agent self-evolution** (SE-Agent) - novel
4. **KV cache management for agentic workloads with pauses** (Continuum paper) - novel
5. **Event-history replay / durable execution** (zylos) - novel

Let me check if any of these are present. The git log shows "Self-healing" but not specifically "trajectory" or "durable execution" or "KV cache". 

Let me look at one quick check for "checkpoint" and "trajectory" in the codebase.
</think><think>


Good — so `trajectory` and `checkpoint` already exist in our codebase. `durable-execution`, `event-history`, `logprob`, `KV-cache`, `DNS-based` do NOT. So my novel insights are:

1. **Logprob-based prompt validation** (nucleus theory) — novel
2. **DNS-based memory node discovery** (mementum) — novel  
3. **Trajectory-level intervention for agent self-evolution** (SE-Agent) — partially novel (we have trajectory but not the systematic intervention pattern)
4. **KV cache management for agentic workloads** (Continuum) — novel

Let me also check the experiment TSV data and the state.md to see what's been done recently.

Actually I have enough. Let me synthesize the final digest now. Budget: 1200 chars. Need to be compact.

Let me check the state.md quickly for any context.

</think><think>

Excellent context. The state.md confirms:
- "researcher daemon dead since Jun 3, only PMF running → stale research"
- The system has pipeline hardening, hashline collision reduction, subagent type registration

This validates the urgency of fresh research. Now I have everything I need. Let me write the final digest.

Budget: 1200 chars. I need to be very tight. The output format is:
- Compact structured digest
- Insights with: source URL, key technique, how it applies
- End with JSON metadata

Let me draft:

```
## Researcher Digest — 2026-06-04

### Own Repos (davidwuchn/*) — 68%

**[deep-external] nucleus: Logprob-based prompt validation**
Source: github.com/davidwuchn/nucleus (AGENTS.md "Attention Magnets" section)
Technique: Nucleus theory predicts symbol effectiveness correlates with training-weight salience, not semantic coherence. They propose measuring logprobs of probe tokens to confirm attention shifts empirically.
Apply: Add `gptel-research--measure-attention-shift()` — sample token logprobs before/after preamble injection, return Δ as a scalar in experiment TSV. Use as objective signal in addition to keep-rate.

**[deep-external] mementum: DNS-based memory node discovery**
Source: github.com/davidwuchn/mementum (USAGE.md "discovery infrastructure")
Technique: Mementum repos become network-addressable memory nodes via DNS-based lookup — any conforming repo can be discovered and read by any AI with bash+git. Protocol interoperability today, auto-discovery later.
Apply: Add `mementum-discover.el` — resolve `_mementum._tcp.davidwuchn.com` SRV records, surface remote `knowledge/` pages as recall candidates in our recall protocol.

**[deep-external] gptel: Stageable request pause/resume**
Source: github.com/davidwuchn/gptel (README §Usage → "Pause multi-stage requests")
Technique: gptel natively supports pausing a multi-stage request at intermediate stage and resuming later, with full state preserved.
Apply: We have checkpointing but not for in-flight requests. Add `gptel-agent--stageable-pause(point)` and `gptel-agent--stageable-resume(handle)` to elisp long-running executor tasks that risk timeout (watchdog threshold drops keep eating experiments).

### External — 21%

**[deep-external] SE-Agent: Trajectory-level intervention** (NeurIPS 2025)
Source: arxiv.org/abs/2508.02085
Technique: Intervene at the trajectory level — selectively mutate sub-trajectories, not just sample parameters — to drive self-evolution. We already track trajectories (strategy-convergence-adaptive-ordering.el) but don't mutate them.
Apply: Add trajectory-edit step: keep top-k trajectories, mutate their step boundaries, re-execute, measure keep-rate. Beta=0.02 makes this safe (only 2% exploratory budget).

**[deep-external] Continuum: KV cache for agentic pauses** (arxiv 2511.02230)
Source: arxiv.org/abs/2511.02230
Technique: Inference engines evict finished-request KV cache when new requests wait; breaks for agentic workloads that interleave LLM calls with tool pauses. Preserve cache across pause boundaries.
Apply: When gptel request stages pause, snapshot gptel request KV state to disk keyed by `(backend . request-hash)`. Resume reuses snapshot → no re-tokenization. Cuts latency on resumed multi-stage experiments.

### Skip
- Workflow architectures, prompt engineering basics, Git memory (already covered last cycle).

```json
{
  "strategy_used": "own-repos-first",
  "sources_checked": ["davidwuchn/nucleus","davidwuchn/mementum","davidwuchn/gptel","arxiv/2508.02085","arxiv/2511.02230"],
  "topics_covered": ["logprob-validation","memory-discovery","stageable-pause","trajectory-mutation","kv-cache-pause"],
  "confidence_final": 0.78,
  "insights_count": 5,
  "tokens_estimate": 1180
}
```

Let me count chars. The narrative is around 1500-1700 chars. I need to tighten to ≤1200. Let me compress.

</think>

**Meta-learning:** Research quality measured by downstream experiment success.

---
*Generated by auto-workflow*
