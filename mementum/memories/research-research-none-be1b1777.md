---
valid-from: 2026-06-05T23:35
---

# Research: 2026-06-05 23:35

**Strategy:** none
**Findings hash:** be1b17777e2fffdfef1aeeab1ebed5fa1651cc66
**Targets:** test.el
**Outcome:** 1/1 kept (100%)

**Raw Findings:**

## Research Priorities (from Ontology × AutoTTS × AutoGo)
Focus research on these categories:
  [:agentic] Critical: 3% keep-rate after 122 experiments — needs investigation
  [:programming] Critical: 5% keep-rate after 37 experiments — needs investigation

Produce category-specific findings — not global recommendations.

> Project: /home/davidwu/.emacs.d/
> Updated: 2026-06-05 23:05

Researcher result for task: External research turn 1/2

<think>
Let me parse this carefully. This is a complex auto-workflow researcher prompt with a lot of metadata, prior thinking traces, and dynamic context. The actual instructions are:

1. I am an external research specialist
2. Need to research the three priority repos (nucleus, mementum, gptel) - own repos first
3. Budget: 53% own repos, 15% external
4. Max 1200 chars output
5. Output structured digest + JSON metadata
6. Stop at 65% confidence
7. Token budget 8000
8. Strategy: "own-repos-first"
9. Check own repos (davidwuchn/*) FIRST before external

The prompt contains previous research runs that mostly fell back due to "research findings file missing after wait". The "Previously Discovered Insights" section is mostly empty (says fallback content).

The "Internal Research Strategy Performance" shows the best internal strategy is 5% keep rate - very low.

**Source effectiveness**:
- own-repo: score=0.58 (HIGH - priority)
- unknown: score=0.15
- external: score=0.14 (LOW)

**Failure patterns to avoid** (because of recent validation/timeout errors):
- AI agent workflow architectures
- Emacs Lisp AI integration patterns
- LLM self-evolution
- Code analysis automation
- Prompt engineering for code generation
- Error recovery and retry patterns
- Benchmarking/evaluation
- Git-based memory
- hermes-agent, zeroclaw, ml-intern projects

Wait - these are failure patterns. They recently failed validation. So I should AVOID suggesting these topics. Interesting.

What about topics that are NOT in the failure list? Let me look:
- Tool-use hook patterns (gptel pre/post tool call hooks)
- Context caching
- Memory crystallization triggers
- Tool scoping/collections
- Attention drift detection
- Synthesis threshold automation

These are all from the own-repos angle. Good.

Let me start with parallel web fetches of the three priority repos. I should be efficient with tokens. I have 8000 tokens, and need to keep output under 1200 chars.

Plan:
1. Fetch nucleus, mementum, gptel in parallel (own repos, 52% budget)
2. Maybe 1 external search (15% budget)
3. Synthesize (33%)
4. Output compact digest + JSON

Let me start.
</think>I'll begin with the controller directive: own-repos first (53% budget), then 1-2 external references. Let me fetch the three priority repos in parallel.<think>
Good, I have the high-level overview for all three repos. Now let me look at:
1. The gptel cached file for tool-use/MCP/introspection details (most relevant to our project)
2. The mementum MEMENTUM-LAMBDA.md to understand the lambda notation
3. Recent commits for nucleus and mementum

Let me also do a quick external anchor (15% budget) to validate the patterns. Let me search for "LLM control plane" or "MCP pre-tool hooks" or "tool use governance".

I need to be efficient. Let me read specific sections of the gptel file and fetch mementum's MEMENTUM-LAMBDA.md in parallel.
</think>Now let me dive into the gptel tool-use/MCP section and the mementum lambda notation, plus do a quick external anchor.<think>

Excellent! I now have rich material from all sources. Let me synthesize:

**Own repo findings (53% budget used):**

1. **gptel pre/post tool-call hooks** (line 2082 in the cached gptel file):
   - `gptel-pre-tool-call-functions` - runs before each tool call, can block or modify it
   - `gptel-post-tool-call-functions` - runs after each tool call, can block or modify results
   - `gptel-confirm-tool-calls` - human-in-the-loop
   - `gptel-include-tool-results` - whether to feed back to LLM
   - **Critical insight**: these can BLOCK calls. This is a governance layer for our tool-heavy agents.

2. **gptel-cache** (line 2037 area):
   - Caches prompts, system message, or tools
   - Currently Anthropic-only
   - **Apply**: cache repeated research directives

3. **gptel presets with per-request tool override** (line 2098):
   - `:tools` plist in preset
   - Per-query preset application via `@preset-name` cookie
   - **Apply**: agent-role tool scoping (researcher, editor, executor)

4. **gptel-prompt-transform-functions** (line 2076):
   - Runs in a temp buffer to transform text before sending
   - **Apply**: pre-flight safety/repair on prompts

5. **gptel-post-request-hook**, **gptel-pre-response-hook**, **gptel-post-response-functions**:
   - Multiple stages where we can intercept/inspect/modify
   - **Apply**: log-and-replay, content filters, schema enforcement

6. **mementum lambda notation** (MEMENTUM-LAMBDA.md):
   - `λ store(x)`: two-gate filter - "helps(future_AI_session)" AND "effort>1_attempt ∨ likely_recur"
   - "false_positive < missed_insight" (asymmetric cost)
   - `λ recall(q, n)`: Fibonacci depth {1,2,3,5,8,13,21,34} - log-scaled search budget
   - "recall_before_explore" - check existing memory before new research
   - `λ metabolize(x)`: synthesis trigger - "≥3 memories(same_topic) → candidate(knowledge_page)"
   - "stale_memory ≡ strongest_signal" - detect and surface
   - `λ synthesize(topic)`: detect via 3+ memories OR stale OR crystallized
   - `λ termination(x)`: "AI_proposes → human_approves → AI_commits" - asymmetric termination
   - `λ orient(x)`: 30s cold start - read state.md first
   - `λ feed_forward(x)`: "quality(session[n]) ∝ Σ encode(1..n-1)" - compound > linear
   - `λ learn(x)`: "every_session_leaves_project_smarter ∨ waste(session)"
   - Symbols: 💡 insight, 🔄 shift, 🎯 decision, 🌀 meta, ❌ mistake, ✅ win, 🔁 pattern

7. **mementum 200-word limit on memories**:
   - Forces concision
   - One insight per file
   - **Apply**: hard cap in our memory writes

8. **mementum git grep with symbols**:
   - `git grep "💡"` for filtering by insight type
   - **Apply**: pre-categorize our memories with symbols for fast filtered search

9. **nucleus "attention magnet"**:
   - Mathematical symbols as attention primers
   - 5-token shifts can boost operator survival 20%→100%
   - **Apply**: use lambda/math primitives in our system prompts

**External findings (15% budget used):**

1. **arxiv.org/pdf/2505.06817** - "Control Plane as a Tool" - pattern is industry standard
2. **Microsoft AGT (Agent Governance Toolkit)** - runtime governance layer between MCP client and tool servers
3. **mcpcontrolplane.com** - identity, auth, safety, audit for every MCP tool call
4. **truefoundry.com MCP Gateway** - `mcp_tool_pre_invoke` / `mcp_tool_post_invoke` hooks

**Validation**: My gptel pre/post tool-call hook finding is corroborated by the external industry. This is a non-obvious, high-leverage pattern for our project.

Now let me write the compact digest. Max 1200 chars. I need to be very tight.

Top 4-5 deepest, most novel, most implementable insights (must be IMPLEMENTABLE, not just interesting):

1. **gptel pre/post tool-call hooks** - our tool layer is the biggest gap
2. **mementum two-gate validation** - formal filter for our memory writes
3. **mementum 3-memory synthesis trigger** - automates knowledge crystallization
4. **gptel-cache + per-preset tool scoping** - cuts token cost + cleaner agent architecture
5. **"stale_memory ≡ strongest_signal"** - knowledge base maintenance automation

Let me draft the final digest now. I have used roughly:
- Own repos: 3 fetches + 1 section read = ~4000 tokens
- External: 1 search = ~1500 tokens
- Total: ~5500 tokens
- Budget: 8000 tokens - have 2500 left for synthesis

Let me write the output. Need to be ≤1200 chars.

</think>I have rich material. The mementum lambda notation is a particularly high-signal artifact, and the external "LLM control plane" pattern validates gptel's pre/post tool-call hooks as industry-standard (now adopted by Microsoft AGT, truefoundry, mcpcontrolplane.com). Now I'll synthesize a tight digest.<think>

Good, I have the hook details confirmed. Let me now check the gptel tool definition section quickly to get the gptel-make-tool API, and look at the tool use section more carefully. Actually, I have enough material. Let me also verify the gptel-cache and gptel-make-preset details and check the tool collection pattern. Let me look at the tool use section.

Actually, I have plenty of material. Let me write the final digest now. I have:

**Confirmed key findings**:

1. **gptel-pre-tool-call-functions + gptel-post-tool-call-functions** (gptel README):
   - "Runs before each tool call, can block or modify it"
   - "Runs after each tool call, can block or modify results"
   - Combined with `gptel-confirm-tool-calls` (user confirmation) and `gptel-include-tool-results`
   - This is the highest-leverage finding for our tool-heavy agent system

2. **gptel-cache** (gptel README, ~line 2037):
   - "Cache prompts, system message or tools (Anthropic only)"
   - Apply: cache repeated research directives

3. **gptel-make-preset + per-request tool override**:
   - `:tools` keyword in preset definition
   - Apply: agent-role tool scoping (researcher has search tools, executor has edit tools)

4. **mementum two-gate validation** (MEMENTUM-LAMBDA.md):
   - `λ store(x). gate-1: helps(future_AI_session) | ¬personal ¬off_topic`
   - `gate-2: effort > 1_attempt ∨ likely_recur`
   - `both_gates → propose`
   - `false_positive < missed_insight` (asymmetric cost framing)

5. **mementum synthesis trigger** (MEMENTUM-LAMBDA.md):
   - `λ metabolize(x). ≥3 memories(same_topic) → candidate(knowledge_page)`
   - `notice(stale_knowledge) → surface("...may be stale")`
   - `stale_memory ≡ strongest_signal`

6. **mementum Fibonacci recall depth** (MEMENTUM-LAMBDA.md):
   - `depth: fibonacci {1,2,3,5,8,13,21,34}` - log-scaled search budget
   - Apply: replace fixed-N recall with depth-by-importance

7. **mementum 200-word memory limit + symbol taxonomy**:
   - `<200 words | one_insight_per_file`
   - Symbols: 💡 insight, 🔄 shift, 🎯 decision, 🌀 meta, ❌ mistake, ✅ win, 🔁 pattern
   - Apply: hard cap in memory writes; pre-categorize for filtered search

8. **External validation: LLM/MCP control plane** (industry standard):
   - arxiv 2505.06817 - "Control Plane as a Tool"
   - Microsoft AGT (Agent Governance Toolkit) - policy layer between MCP client and tool servers
   - truefoundry MCP Gateway - `mcp_tool_pre_invoke` / `mcp_tool_post_invoke` hooks
   - This validates the gptel pre/post tool-call pattern

Now I need to write the digest in 1200 chars max. Let me structure:

## External Sources
- URL — technique

## Own-Repo Findings
- [source] technique → how to apply

## Local Application Hints
- Where in our codebase

## JSON metadata

Let me write tightly. I'll prioritize the 4 deepest, most implementable insights.
</think>

---

Researcher result for task: External research turn 2/2

<think>
The user has invoked me as a research agent in an auto-workflow system. Let me carefully parse what's happening:

1. **Role**: External research specialist for an Emacs-based AI agent system
2. **Context**: Multiple previous research runs that mostly failed/fell back. The "Previously Discovered Insights" section is mostly empty or fallback content.
3. **Current directive from controller**: 
   - Previous sources were DEVIANT — switch to NEW sources
   - PROBE FIRST (skim titles/abstracts before deep-reading)
   - 100% external priority
   - 60s probe, 120s deep read
   - λ engage(nucleus)
4. **Strategy guidance**: 
   - Beta: 0.04 (conservative)
   - Own repo priority: 52% (but controller is overriding to 100% external)
   - External priority: 16%
   - Stop threshold: 65% confidence
   - Token budget: 8000
5. **Source effectiveness from history**:
   - own-repo: 0.58
   - external: 0.14
   - unknown: 0.15
6. **Failure patterns to AVOID** (10 validation/timeout errors):
   - AI agent workflow architectures
   - Emacs Lisp AI integration patterns
   - LLM self-evolution
   - Code analysis automation
   - Prompt engineering for code generation
   - Error recovery and retry patterns
   - Benchmarking/evaluation
   - Git-based memory
   - hermes-agent, zeroclaw, ml-intern projects
7. **Topics with high keep-rate to focus on**: None shown (all internal strategies are 5% max)
8. **Output constraints**:
   - Max 1200 chars for the digest
   - Must end with JSON metadata
   - Tags: [deep-external] for external discoveries
   - Read-only: never write files
9. **Format**: Compact structured digest with External Sources + Local Analysis sections

The controller has explicitly OVERRIDDEN the "own-repos-first" directive because previous own-repo searches produced DEVIANT results. It says "switch to NEW sources" and "100% external".

So I need to:
1. **Skip the own repos** (nucleus, mementum, gptel) - they're producing deviant results
2. **Probe external sources first** - skim titles/abstracts
3. **Search for**: external trending repos, arxiv, github explore
4. **Avoid**: failure patterns listed
5. **Focus on** topics NOT in failure list

Failure patterns are basically everything I'd want to research. What's NOT in the failure list?
- Tool-use hook patterns
- Context caching
- Memory crystallization triggers
- Tool scoping/collections
- Attention drift detection
- Synthesis threshold automation
- Circuit breaker patterns for LLM APIs
- Streaming/non-blocking LLM calls
- Pre-send introspection
- Tool governance patterns

Let me think strategically. The controller says external only. Source effectiveness shows external = 0.14 (low). But the controller is overriding that. The instruction is clear: "Priority: 100% external. Budget: 60s per source probe, 120s for deep read if probe passes."

Let me plan my budget:
- 3-4 source probes (titles/abstracts)
- 1-2 deep reads (full content)
- Token budget 8000

Good external sources to probe:
1. **arXiv** - recent papers on agent architectures, memory systems, tool use
2. **GitHub trending** - new agent frameworks
3. **MCP (Model Context Protocol)** - tool use standard
4. **HuggingFace** - new models for code agents
5. **Reddit r/LocalLLaMA, r/MachineLearning** - discussions
6. **X/Twitter** - developer discussions

Let me start with parallel probes. I'll do:
1. WebSearch for recent arxiv papers on agent memory/tool use
2. WebSearch for github trending ai-agent repos
3. WebSearch for MCP/pre-tool-call patterns

Then if probes pass, do 1-2 deep reads.

Actually, let me be more strategic. The 1200 char output limit is very tight. Let me think about what would be most useful:

**High-value, novel, implementable in Emacs Lisp, NOT in failure list**:
1. **Streaming-first LLM APIs** - non-blocking requests (gptel already does this; could be a pattern to apply broadly)
2. **Pre/post tool-call hooks** - governance layer (LLM control plane)
3. **Circuit breaker pattern** - prevent cascading failures (but error recovery is in failure list... so avoid)
4. **Prompt caching** - reduce token cost (cheap optimization)
5. **Tool collections/scopes** - context-aware tool registration
6. **Memory synthesis thresholds** - when to crystallize knowledge
7. **Context drift detection** - periodic summarization
8. **Introspection hooks** - inspect/modify requests before send

Wait, "Error recovery and retry patterns in agent systems" is in the failure list. So I should avoid circuit breaker for LLM APIs. But "circuit breaker" is a common pattern, not specifically error recovery. Let me be careful.

Let me probe external sources:
1. arxiv: "agent tool use governance 2025"
2. github: trending ai-agent repos
3. web: "MCP pre-tool-call hooks pattern"

Actually, let me start with quick probes. I'll do 2-3 parallel WebSearches.

Let me write this out. Output should be compact. Start with parallel web searches.

First, the search queries. Given the constraints (avoid failure patterns, focus on novel):

Query 1: "arxiv agent tool governance 2025 pre-tool-call hook"
Query 2: "github trending ai agent framework 2025"
Query 3: "MCP model context protocol hooks governance"

Let me run these in parallel.

Actually, let me think more carefully. The previous researcher's thinking showed they had rich data from own-repos already. The controller is saying to go external NOW because own-repo data was "devious" (deviant). So the controller is forcing variety.

I should respect the controller directive and go 100% external. Let me start with probes.

Let me do the first round of parallel probes.
</think>The controller is explicitly overriding to 100% external (own-repos produced deviant results last cycle). I'll probe external sources first—skim titles/abstracts, then deep-read the best hits. The failure list is broad, so I'll target topics NOT in it: tool governance hooks, prompt caching, context drift detection, MCP pre-tool-call patterns.<think>
Good probes. I have 3 high-signal external leads:

1. **arxiv 2505.06817 - "Control Plane as a Tool"** - This is a design pattern for agentic AI. Modularizes tool orchestration. Decouples tool management from reasoning/decision. THIS IS GOLD.

2. **Microsoft - "Securing MCP: A Control Plane for Agent Tool Execution"** - Real implementation: Agent Governance Toolkit (AGT) between MCP client and tool servers, policy-evaluates each tool call. Concrete and applicable.

3. **arxiv 2605.09252 - "When2Tool"** - LLM agents call tools indiscriminately. No benchmark studies when tool call is actually needed. Reduces API fees/latency. This is a "decision-to-call" pattern.

4. **arxiv 2503.23278 / MCP landscape paper** - Security threats and future of MCP.

5. **Model Context Protocol specification 2025-06-18** - The standard itself.

The Microsoft AGT article is probably the most concrete and implementable. Let me deep-read that, and the Control Plane as a Tool paper.

Both are external and align with the directive. Let me budget:
- Microsoft AGT: 120s deep read (concrete implementation)
- Control Plane as a Tool (arxiv): 120s deep read (architectural pattern)

Two parallel deep reads, then synthesize.

Let me also be mindful of token budget. I'll do parallel fetches.
</think>The Microsoft "Agent Governance Toolkit" article and the arxiv "Control Plane as a Tool" paper are both high-signal and external. Let me deep-read both in parallel.<think>

Excellent! Both deep reads were highly productive. I now have rich material. Let me synthesize.

**Key External Discoveries:**

### 1. Microsoft AGT (Agent Governance Toolkit)
- Runtime governance layer between MCP client and tool servers
- Policy evaluation BEFORE every tool invocation
- Sub-millisecond overhead per call
- Maps to OWASP MCP Top 10 (7/10 fully covered)
- Components: tool definition scanning, per-call policy enforcement, response inspection, identity/trust, execution gating, observability
- Four-tier privilege ring model + kill switches
- Hash-chained audit logs
- AGT governs individual tool calls deterministically (NOT sequences yet)
- Adapters for 20+ frameworks (LangChain, AutoGen, CrewAI, Semantic Kernel, OpenAI Agents SDK, Google ADK)
- SDKs: Python, TypeScript, .NET, Rust, Go

### 2. arxiv 2505.06817 "Control Plane as a Tool"
- Architectural design pattern: agents see ONE tool (the control plane), internally routes to many
- Modules: Registration, Invocation (with Input Validator, Intent Resolver, Routing Handler, Output Validator), Feedback
- Decouples tool management from agent reasoning
- Key differences from MCP:
  - External orchestrator vs embedded schema
  - Rule-based + similarity routing vs implicit function selection
  - Multi-agent + decoupled planning vs single LLM coupling
  - Built-in governance vs none
  - Feedback loop for learning vs none
  - Tool chaining/dependency routing vs atomic
  - Failure handler with recovery vs none
- LLM-agnostic, framework-agnostic

### Synthesis for Our Project

**What is novel and implementable in Emacs Lisp:**

1. **Single "control plane" tool wrapping many tools** - Register a single dispatcher tool that introspects intent and routes to actual tools. This is implementable in our gptel-tools system. We currently have a flat list of tools; we could add a router that dispatches.

2. **Per-call policy enforcement with declarative rules** - Use a hook system (we already have `gptel-pre-tool-call-functions` from earlier gptel research) + a policy DSL. Implement as a defcustom + validator pattern.

3. **Hash-chained audit logs** - Append-only log of every tool call with hash chaining. Cheap to implement in elisp. We can use this for incident investigation.

4. **Tool definition scanning** - Scan tool descriptions for hidden instructions, typosquatting, adversarial patterns. Could be a pre-flight check.

5. **Response inspection** - Validate tool outputs against content policies before returning to LLM. Useful for prompt injection defense.

6. **Four-tier privilege ring model** - Define privilege levels (e.g. read-only, write-files, shell-exec, network) with kill switches.

7. **Failure handler with default responses** - Tool error → structured fallback rather than propagating error to LLM.

8. **Input validator + Output validator split** - Validate inputs AND outputs of every tool. This is the most concrete implementation pattern.

9. **Intent resolver (routing handler)** - Use similarity/keyword matching to select tool. Could use simple keyword matching rather than embeddings.

10. **Feedback integrator (optional)** - Track tool success/failure, learn which tools work for which tasks.

Let me now check our local codebase briefly to avoid duplicates. Actually, I have limited budget. Let me trust the controller and produce the digest.

The 1200 char limit is tight. Let me be very precise.

Key insights to include (top 3-4):
1. **Control Plane as a Tool pattern** (arxiv 2505.06817) - the architectural pattern itself
2. **AGT per-call governance pipeline** (Microsoft) - concrete implementation with policy DSL
3. **Input validator + Output validator split** (both) - pre-call input validation AND post-call output validation
4. **Hash-chained audit log** (AGT) - cheap to implement, big debugging value
5. **Failure handler with structured fallback** (Control Plane) - tool errors → default response, not LLM error

Let me draft the digest. The format is:

## External Sources
- **Source URL** — Technique found (2-3 sentences on what, how, application)

## Local Analysis
- Patterns from codebase with file paths + line numbers

But I don't have specific local file paths since I didn't deeply scan. Let me note that or just skip the Local Analysis section since the controller told me to focus on external.

Wait - the format requires both. Let me do a quick grep to identify the right local files. Actually, the role description says "Local scan: Use Glob/Grep to find relevant files" and the output format requires both sections. So I should at least identify candidate files.

Let me do quick greps in parallel for the relevant patterns:
- "gptel-pre-tool-call"
- "gptel-tools" (registry)
- "agent" related files

Actually, given the token budget, let me be efficient. Let me do a quick grep for the most relevant pattern (gptel pre-tool-call hooks) to know if it's already implemented.

Actually, looking at the prior researcher's thinking, they already identified `gptel-pre-tool-call-functions` and `gptel-post-tool-call-functions` in the gptel library. So we know those hooks exist in gptel. The question is: does OUR auto-workflow USE them?

Let me do a quick grep to check if our local gptel-auto-workflow uses pre-tool-call hooks. This will tell us whether the governance pattern is novel for us.

Let me budget: 1 grep call, then synthesize.

Actually, the prompt says "Read-only: never write files or make repository changes" - I can read. Let me do a quick scan.
</think>Both deep reads were productive. I have the **Control Plane as a Tool** architectural pattern and the **Microsoft AGT (Agent Governance Toolkit)** concrete implementation. Both external, both novel for our project. Let me do a quick local scan to identify candidate files for the patterns, then synthesize.<think>

OK, 77 matches for the more specific patterns. Let me grep more narrowly to identify which files actually have governance hooks.

Let me grep for the actual hook usage (not just variable definitions) - i.e. lines that actually call add-hook on gptel-pre-tool-call-functions.
</think>Let me narrow the grep to find where these hooks are actually wired up in our code.<think>


Good. Key findings:
1. **NO use of `gptel-pre-tool-call-functions` or `gptel-post-tool-call-functions` hooks** in our codebase (the first grep returned no matches for add-hook on these)
2. **There IS an audit log** (`gptel-auto-workflow--routing-audit-log`) but it's a simple list, NOT hash-chained
3. There's a "kill switch" comment in gptel-config.el at line 97

This confirms the patterns are mostly novel. The Microsoft AGT pattern (deterministic pre-call policy + post-call response validation) is the biggest gap.

Let me also check briefly for failure handler / input validator / output validator patterns.

Actually, I have enough. Let me synthesize the digest now.

Key local findings to include:
- `gptel-auto-workflow-ontology-router.el` lines 3, 822-825, 2161-2205, 2351 - has a `gptel-auto-workflow--routing-audit-log` (simple list, capped at 100 entries) - NOT hash-chained
- `gptel-config.el` line 97 - has "kill switch" comment for tool confirmation
- **MISSING**: pre-tool-call hook, post-tool-call hook, deterministic policy enforcement, response inspection

Top 3-4 insights to include in the 1200 char digest:

1. **AGT: deterministic pre/post tool-call governance (Microsoft)** - Use `gptel-pre-tool-call-functions` and `gptel-post-tool-call-functions` (which exist in gptel library but are NOT used in our code) to enforce policy BEFORE and AFTER every tool call. YAML/Elisp declarative rules. Sub-ms overhead.

2. **Control Plane as a Tool (arxiv 2505.06817)** - Register a single dispatcher tool that wraps many tools. Hides tool surface from LLM (reduces prompt bloat, prevents tool poisoning), enables internal routing based on context/user/policy. Implementable in our `gptel-tools` collection.

3. **Hash-chained audit log upgrade** - Current `gptel-auto-workflow--routing-audit-log` is a flat list capped at 100. Upgrade to hash-chained append-only log (AGT pattern) for tamper-evidence and postmortem replay. Cheap in elisp.

4. **Input validator + Output validator split** - Control Plane pattern: validate input args BEFORE tool call (schema + policy) AND validate output AFTER call (content policy, no prompt injection). Current code does neither explicitly.

5. **Failure handler with structured fallback** - On tool error, return structured default response (not raw error to LLM). Prevents LLM fr
...[Result too large, truncated. Full result saved to: /home/davidwu/.emacs.d/var/tmp/gptel-subagent-result-w3iaUv.txt. Use Read tool if you need more]...

**Digested Insights:**

## Research Priorities (from Ontology × AutoTTS × AutoGo)
Focus research on these categories:
  [:agentic] Critical: 3% keep-rate after 122 experiments — needs investigation
  [:programming] Critical: 5% keep-rate after 37 experiments — needs investigation

Produce category-specific findings — not global recommendations.

> Project: /home/davidwu/.emacs.d/
> Updated: 2026-06-05 23:05

Researcher result for task: External research turn 1/2

<think>
Let me parse this carefully. This is a complex auto-workflow researcher prompt with a lot of metadata, prior thinking traces, and dynamic context. The actual instructions are:

1. I am an external research specialist
2. Need to research the three priority repos (nucleus, mementum, gptel) - own repos first
3. Budget: 53% own repos, 15% external
4. Max 1200 chars output
5. Output structured digest + JSON metadata
6. Stop at 65% confidence
7. Token budget 8000
8. Strategy: "own-repos-first"
9. Check own repos (davidwuchn/*) FIRST before external

The prompt contains previous research runs that mostly fell back due to "research findings file missing after wait". The "Previously Discovered Insights" section is mostly empty (says fallback content).

The "Internal Research Strategy Performance" shows the best internal strategy is 5% keep rate - very low.

**Source effectiveness**:
- own-repo: score=0.58 (HIGH - priority)
- unknown: score=0.15
- external: score=0.14 (LOW)

**Failure patterns to avoid** (because of recent validation/timeout errors):
- AI agent workflow architectures
- Emacs Lisp AI integration patterns
- LLM self-evolution
- Code analysis automation
- Prompt engineering for code generation
- Error recovery and retry patterns
- Benchmarking/evaluation
- Git-based memory
- hermes-agent, zeroclaw, ml-intern projects

Wait - these are failure patterns. They recently failed validation. So I should AVOID suggesting these topics. Interesting.

What about topics that are NOT in the failure list? Let me look:
- Tool-use hook patterns (gptel pre/post tool call hooks)
- Context caching
- Memory crystallization triggers
- Tool scoping/collections
- Attention drift detection
- Synthesis threshold automation

These are all from the own-repos angle. Good.

Let me start with parallel web fetches of the three priority repos. I should be efficient with tokens. I have 8000 tokens, and need to keep output under 1200 chars.

Plan:
1. Fetch nucleus, mementum, gptel in parallel (own repos, 52% budget)
2. Maybe 1 external search (15% budget)
3. Synthesize (33%)
4. Output compact digest + JSON

Let me start.
</think>I'll begin with the controller directive: own-repos first (53% budget), then 1-2 external references. Let me fetch the three priority repos in parallel.<think>
Good, I have the high-level overview for all three repos. Now let me look at:
1. The gptel cached file for tool-use/MCP/introspection details (most relevant to our project)
2. The mementum MEMENTUM-LAMBDA.md to understand the lambda notation
3. Recent commits for nucleus and mementum

Let me also do a quick external anchor (15% budget) to validate the patterns. Let me search for "LLM control plane" or "MCP pre-tool hooks" or "tool use governance".

I need to be efficient. Let me read specific sections of the gptel file and fetch mementum's MEMENTUM-LAMBDA.md in parallel.
</think>Now let me dive into the gptel tool-use/MCP section and the mementum lambda notation, plus do a quick external anchor.<think>

Excellent! I now have rich material from all sources. Let me synthesize:

**Own repo findings (53% budget used):**

1. **gptel pre/post tool-call hooks** (line 2082 in the cached gptel file):
   - `gptel-pre-tool-call-functions` - runs before each tool call, can block or modify it
   - `gptel-post-tool-call-functions` - runs after each tool call, can block or modify results
   - `gptel-confirm-tool-calls` - human-in-the-loop
   - `gptel-include-tool-results` - whether to feed back to LLM
   - **Critical insight**: these can BLOCK calls. This is a governance layer for our tool-heavy agents.

2. **gptel-cache** (line 2037 area):
   - Caches prompts, system message, or tools
   - Currently Anthropic-only
   - **Apply**: cache repeated research directives

3. **gptel presets with per-request tool override** (line 2098):
   - `:tools` plist in preset
   - Per-query preset application via `@preset-name` cookie
   - **Apply**: agent-role tool scoping (researcher, editor, executor)

4. **gptel-prompt-transform-functions** (line 2076):
   - Runs in a temp buffer to transform text before sending
   - **Apply**: pre-flight safety/repair on prompts

5. **gptel-post-request-hook**, **gptel-pre-response-hook**, **gptel-post-response-functions**:
   - Multiple stages where we can intercept/inspect/modify
   - **Apply**: log-and-replay, content filters, schema enforcement

6. **mementum lambda notation** (MEMENTUM-LAMBDA.md):
   - `λ store(x)`: two-gate filter - "helps(future_AI_session)" AND "effort>1_attempt ∨ likely_recur"
   - "false_positive < missed_insight" (asymmetric cost)
   - `λ recall(q, n)`: Fibonacci depth {1,2,3,5,8,13,21,34} - log-scaled search budget
   - "recall_before_explore" - check existing memory before new research
   - `λ metabolize(x)`: synthesis trigger - "≥3 memories(same_topic) → candidate(knowledge_page)"
   - "stale_memory ≡ strongest_signal" - detect and surface
   - `λ synthesize(topic)`: detect via 3+ memories OR stale OR crystallized
   - `λ termination(x)`: "AI_proposes → human_approves → AI_commits" - asymmetric termination
   - `λ orient(x)`: 30s cold start - read state.md first
   - `λ feed_forward(x)`: "quality(session[n]) ∝ Σ encode(1..n-1)" - compound > linear
   - `λ learn(x)`: "every_session_leaves_project_smarter ∨ waste(session)"
   - Symbols: 💡 insight, 🔄 shift, 🎯 decision, 🌀 meta, ❌ mistake, ✅ win, 🔁 pattern

7. **mementum 200-word limit on memories**:
   - Forces concision
   - One insight per file
   - **Apply**: hard cap in our memory writes

8. **mementum git grep with symbols**:
   - `git grep "💡"` for filtering by insight type
   - **Apply**: pre-categorize our memories with symbols for fast filtered search

9. **nucleus "attention magnet"**:
   - Mathematical symbols as attention primers
   - 5-token shifts can boost operator survival 20%→100%
   - **Apply**: use lambda/math primitives in our system prompts

**External findings (15% budget used):**

1. **arxiv.org/pdf/2505.06817** - "Control Plane as a Tool" - pattern is industry standard
2. **Microsoft AGT (Agent Governance Toolkit)** - runtime governance layer between MCP client and tool servers
3. **mcpcontrolplane.com** - identity, auth, safety, audit for every MCP tool call
4. **truefoundry.com MCP Gateway** - `mcp_tool_pre_invoke` / `mcp_tool_post_invoke` hooks

**Validation**: My gptel pre/post tool-call hook finding is corroborated by the external industry. This is a non-obvious, high-leverage pattern for our project.

Now let me write the compact digest. Max 1200 chars. I need to be very tight.

Top 4-5 deepest, most novel, most implementable insights (must be IMPLEMENTABLE, not just interesting):

1. **gptel pre/post tool-call hooks** - our tool layer is the biggest gap
2. **mementum two-gate validation** - formal filter for our memory writes
3. **mementum 3-memory synthesis trigger** - automates knowledge crystallization
4. **gptel-cache + per-preset tool scoping** - cuts token cost + cleaner agent architecture
5. **"stale_memory ≡ strongest_signal"** - knowledge base maintenance automation

Let me draft the final digest now. I have used roughly:
- Own repos: 3 fetches + 1 section read = ~4000 tokens
- External: 1 search = ~1500 tokens
- Total: ~5500 tokens
- Budget: 8000 tokens - have 2500 left for synthesis

Let me write the output. Need to be ≤1200 chars.

</think>I have rich material. The mementum lambda notation is a particularly high-signal artifact, and the external "LLM control plane" pattern validates gptel's pre/post tool-call hooks as industry-standard (now adopted by Microsoft AGT, truefoundry, mcpcontrolplane.com). Now I'll synthesize a tight digest.<think>

Good, I have the hook details confirmed. Let me now check the gptel tool definition section quickly to get the gptel-make-tool API, and look at the tool use section more carefully. Actually, I have enough material. Let me also verify the gptel-cache and gptel-make-preset details and check the tool collection pattern. Let me look at the tool use section.

Actually, I have plenty of material. Let me write the final digest now. I have:

**Confirmed key findings**:

1. **gptel-pre-tool-call-functions + gptel-post-tool-call-functions** (gptel README):
   - "Runs before each tool call, can block or modify it"
   - "Runs after each tool call, can block or modify results"
   - Combined with `gptel-confirm-tool-calls` (user confirmation) and `gptel-include-tool-results`
   - This is the highest-leverage finding for our tool-heavy agent system

2. **gptel-cache** (gptel README, ~line 2037):
   - "Cache prompts, system message or tools (Anthropic only)"
   - Apply: cache repeated research directives

3. **gptel-make-preset + per-request tool override**:
   - `:tools` keyword in preset definition
   - Apply: agent-role tool scoping (researcher has search tools, executor has edit tools)

4. **mementum two-gate validation** (MEMENTUM-LAMBDA.md):
   - `λ store(x). gate-1: helps(future_AI_session) | ¬personal ¬off_topic`
   - `gate-2: effort > 1_attempt ∨ likely_recur`
   - `both_gates → propose`
   - `false_positive < missed_insight` (asymmetric cost framing)

5. **mementum synthesis trigger** (MEMENTUM-LAMBDA.md):
   - `λ metabolize(x). ≥3 memories(same_topic) → candidate(knowledge_page)`
   - `notice(stale_knowledge) → surface("...may be stale")`
   - `stale_memory ≡ strongest_signal`

6. **mementum Fibonacci recall depth** (MEMENTUM-LAMBDA.md):
   - `depth: fibonacci {1,2,3,5,8,13,21,34}` - log-scaled search budget
   - Apply: replace fixed-N recall with depth-by-importance

7. **mementum 200-word memory limit + symbol taxonomy**:
   - `<200 words | one_insight_per_file`
   - Symbols: 💡 insight, 🔄 shift, 🎯 decision, 🌀 meta, ❌ mistake, ✅ win, 🔁 pattern
   - Apply: hard cap in memory writes; pre-categorize for filtered search

8. **External validation: LLM/MCP control plane** (industry standard):
   - arxiv 2505.06817 - "Control Plane as a Tool"
   - Microsoft AGT (Agent Governance Toolkit) - policy layer between MCP client and tool servers
   - truefoundry MCP Gateway - `mcp_tool_pre_invoke` / `mcp_tool_post_invoke` hooks
   - This validates the gptel pre/post tool-call pattern

Now I need to write the digest in 1200 chars max. Let me structure:

## External Sources
- URL — technique

## Own-Repo Findings
- [source] technique → how to apply

## Local Application Hints
- Where in our codebase

## JSON metadata

Let me write tightly. I'll prioritize the 4 deepest, most implementable insights.
</think>

---

Researcher result for task: External research turn 2/2

<think>
The user has invoked me as a research agent in an auto-workflow system. Let me carefully parse what's happening:

1. **Role**: External research specialist for an Emacs-based AI agent system
2. **Context**: Multiple previous research runs that mostly failed/fell back. The "Previously Discovered Insights" section is mostly empty or fallback content.
3. **Current directive from controller**: 
   - Previous sources were DEVIANT — switch to NEW sources
   - PROBE FIRST (skim titles/abstracts before deep-reading)
   - 100% external priority
   - 60s probe, 120s deep read
   - λ engage(nucleus)
4. **Strategy guidance**: 
   - Beta: 0.04 (conservative)
   - Own repo priority: 52% (but controller is overriding to 100% external)
   - External priority: 16%
   - Stop threshold: 65% confidence
   - Token budget: 8000
5. **Source effectiveness from history**:
   - own-repo: 0.58
   - external: 0.14
   - unknown: 0.15
6. **Failure patterns to AVOID** (10 validation/timeout errors):
   - AI agent workflow architectures
   - Emacs Lisp AI integration patterns
   - LLM self-evolution
   - Code analysis automation
   - Prompt engineering for code generation
   - Error recovery and retry patterns
   - Benchmarking/evaluation
   - Git-based memory
   - hermes-agent, zeroclaw, ml-intern projects
7. **Topics with high keep-rate to focus on**: None shown (all internal strategies are 5% max)
8. **Output constraints**:
   - Max 1200 chars for the digest
   - Must end with JSON metadata
   - Tags: [deep-external] for external discoveries
   - Read-only: never write files
9. **Format**: Compact structured digest with External Sources + Local Analysis sections

The controller has explicitly OVERRIDDEN the "own-repos-first" directive because previous own-repo searches produced DEVIANT results. It says "switch to NEW sources" and "100% external".

So I need to:
1. **Skip the own repos** (nucleus, mementum, gptel) - they're producing deviant results
2. **Probe external sources first** - skim titles/abstracts
3. **Search for**: external trending repos, arxiv, github explore
4. **Avoid**: failure patterns listed
5. **Focus on** topics NOT in failure list

Failure patterns are basically everything I'd want to research. What's NOT in the failure list?
- Tool-use hook patterns
- Context caching
- Memory crystallization triggers
- Tool scoping/collections
- Attention drift detection
- Synthesis threshold automation
- Circuit breaker patterns for LLM APIs
- Streaming/non-blocking LLM calls
- Pre-send introspection
- Tool governance patterns

Let me think strategically. The controller says external only. Source effectiveness shows external = 0.14 (low). But the controller is overriding that. The instruction is clear: "Priority: 100% external. Budget: 60s per source probe, 120s for deep read if probe passes."

Let me plan my budget:
- 3-4 source probes (titles/abstracts)
- 1-2 deep reads (full content)
- Token budget 8000

Good external sources to probe:
1. **arXiv** - recent papers on agent architectures, memory systems, tool use
2. **GitHub trending** - new agent frameworks
3. **MCP (Model Context Protocol)** - tool use standard
4. **HuggingFace** - new models for code agents
5. **Reddit r/LocalLLaMA, r/MachineLearning** - discussions
6. **X/Twitter** - developer discussions

Let me start with parallel probes. I'll do:
1. WebSearch for recent arxiv papers on agent memory/tool use
2. WebSearch for github trending ai-agent repos
3. WebSearch for MCP/pre-tool-call patterns

Then if probes pass, do 1-2 deep reads.

Actually, let me be more strategic. The 1200 char output limit is very tight. Let me think about what would be most useful:

**High-value, novel, implementable in Emacs Lisp, NOT in failure list**:
1. **Streaming-first LLM APIs** - non-blocking requests (gptel already does this; could be a pattern to apply broadly)
2. **Pre/post tool-call hooks** - governance layer (LLM control plane)
3. **Circuit breaker pattern** - prevent cascading failures (but error recovery is in failure list... so avoid)
4. **Prompt caching** - reduce token cost (cheap optimization)
5. **Tool collections/scopes** - context-aware tool registration
6. **Memory synthesis thresholds** - when to crystallize knowledge
7. **Context drift detection** - periodic summarization
8. **Introspection hooks** - inspect/modify requests before send

Wait, "Error recovery and retry patterns in agent systems" is in the failure list. So I should avoid circuit breaker for LLM APIs. But "circuit breaker" is a common pattern, not specifically error recovery. Let me be careful.

Let me probe external sources:
1. arxiv: "agent tool use governance 2025"
2. github: trending ai-agent repos
3. web: "MCP pre-tool-call hooks pattern"

Actually, let me start with quick probes. I'll do 2-3 parallel WebSearches.

Let me write this out. Output should be compact. Start with parallel web searches.

First, the search queries. Given the constraints (avoid failure patterns, focus on novel):

Query 1: "arxiv agent tool governance 2025 pre-tool-call hook"
Query 2: "github trending ai agent framework 2025"
Query 3: "MCP model context protocol hooks governance"

Let me run these in parallel.

Actually, let me think more carefully. The previous researcher's thinking showed they had rich data from own-repos already. The controller is saying to go external NOW because own-repo data was "devious" (deviant). So the controller is forcing variety.

I should respect the controller directive and go 100% external. Let me start with probes.

Let me do the first round of parallel probes.
</think>The controller is explicitly overriding to 100% external (own-repos produced deviant results last cycle). I'll probe external sources first—skim titles/abstracts, then deep-read the best hits. The failure list is broad, so I'll target topics NOT in it: tool governance hooks, prompt caching, context drift detection, MCP pre-tool-call patterns.<think>
Good probes. I have 3 high-signal external leads:

1. **arxiv 2505.06817 - "Control Plane as a Tool"** - This is a design pattern for agentic AI. Modularizes tool orchestration. Decouples tool management from reasoning/decision. THIS IS GOLD.

2. **Microsoft - "Securing MCP: A Control Plane for Agent Tool Execution"** - Real implementation: Agent Governance Toolkit (AGT) between MCP client and tool servers, policy-evaluates each tool call. Concrete and applicable.

3. **arxiv 2605.09252 - "When2Tool"** - LLM agents call tools indiscriminately. No benchmark studies when tool call is actually needed. Reduces API fees/latency. This is a "decision-to-call" pattern.

4. **arxiv 2503.23278 / MCP landscape paper** - Security threats and future of MCP.

5. **Model Context Protocol specification 2025-06-18** - The standard itself.

The Microsoft AGT article is probably the most concrete and implementable. Let me deep-read that, and the Control Plane as a Tool paper.

Both are external and align with the directive. Let me budget:
- Microsoft AGT: 120s deep read (concrete implementation)
- Control Plane as a Tool (arxiv): 120s deep read (architectural pattern)

Two parallel deep reads, then synthesize.

Let me also be mindful of token budget. I'll do parallel fetches.
</think>The Microsoft "Agent Governance Toolkit" article and the arxiv "Control Plane as a Tool" paper are both high-signal and external. Let me deep-read both in parallel.<think>

Excellent! Both deep reads were highly productive. I now have rich material. Let me synthesize.

**Key External Discoveries:**

### 1. Microsoft AGT (Agent Governance Toolkit)
- Runtime governance layer between MCP client and tool servers
- Policy evaluation BEFORE every tool invocation
- Sub-millisecond overhead per call
- Maps to OWASP MCP Top 10 (7/10 fully covered)
- Components: tool definition scanning, per-call policy enforcement, response inspection, identity/trust, execution gating, observability
- Four-tier privilege ring model + kill switches
- Hash-chained audit logs
- AGT governs individual tool calls deterministically (NOT sequences yet)
- Adapters for 20+ frameworks (LangChain, AutoGen, CrewAI, Semantic Kernel, OpenAI Agents SDK, Google ADK)
- SDKs: Python, TypeScript, .NET, Rust, Go

### 2. arxiv 2505.06817 "Control Plane as a Tool"
- Architectural design pattern: agents see ONE tool (the control plane), internally routes to many
- Modules: Registration, Invocation (with Input Validator, Intent Resolver, Routing Handler, Output Validator), Feedback
- Decouples tool management from agent reasoning
- Key differences from MCP:
  - External orchestrator vs embedded schema
  - Rule-based + similarity routing vs implicit function selection
  - Multi-agent + decoupled planning vs single LLM coupling
  - Built-in governance vs none
  - Feedback loop for learning vs none
  - Tool chaining/dependency routing vs atomic
  - Failure handler with recovery vs none
- LLM-agnostic, framework-agnostic

### Synthesis for Our Project

**What is novel and implementable in Emacs Lisp:**

1. **Single "control plane" tool wrapping many tools** - Register a single dispatcher tool that introspects intent and routes to actual tools. This is implementable in our gptel-tools system. We currently have a flat list of tools; we could add a router that dispatches.

2. **Per-call policy enforcement with declarative rules** - Use a hook system (we already have `gptel-pre-tool-call-functions` from earlier gptel research) + a policy DSL. Implement as a defcustom + validator pattern.

3. **Hash-chained audit logs** - Append-only log of every tool call with hash chaining. Cheap to implement in elisp. We can use this for incident investigation.

4. **Tool definition scanning** - Scan tool descriptions for hidden instructions, typosquatting, adversarial patterns. Could be a pre-flight check.

5. **Response inspection** - Validate tool outputs against content policies before returning to LLM. Useful for prompt injection defense.

6. **Four-tier privilege ring model** - Define privilege levels (e.g. read-only, write-files, shell-exec, network) with kill switches.

7. **Failure handler with default responses** - Tool error → structured fallback rather than propagating error to LLM.

8. **Input validator + Output validator split** - Validate inputs AND outputs of every tool. This is the most concrete implementation pattern.

9. **Intent resolver (routing handler)** - Use similarity/keyword matching to select tool. Could use simple keyword matching rather than embeddings.

10. **Feedback integrator (optional)** - Track tool success/failure, learn which tools work for which tasks.

Let me now check our local codebase briefly to avoid duplicates. Actually, I have limited budget. Let me trust the controller and produce the digest.

The 1200 char limit is tight. Let me be very precise.

Key insights to include (top 3-4):
1. **Control Plane as a Tool pattern** (arxiv 2505.06817) - the architectural pattern itself
2. **AGT per-call governance pipeline** (Microsoft) - concrete implementation with policy DSL
3. **Input validator + Output validator split** (both) - pre-call input validation AND post-call output validation
4. **Hash-chained audit log** (AGT) - cheap to implement, big debugging value
5. **Failure handler with structured fallback** (Control Plane) - tool errors → default response, not LLM error

Let me draft the digest. The format is:

## External Sources
- **Source URL** — Technique found (2-3 sentences on what, how, application)

## Local Analysis
- Patterns from codebase with file paths + line numbers

But I don't have specific local file paths since I didn't deeply scan. Let me note that or just skip the Local Analysis section since the controller told me to focus on external.

Wait - the format requires both. Let me do a quick grep to identify the right local files. Actually, the role description says "Local scan: Use Glob/Grep to find relevant files" and the output format requires both sections. So I should at least identify candidate files.

Let me do quick greps in parallel for the relevant patterns:
- "gptel-pre-tool-call"
- "gptel-tools" (registry)
- "agent" related files

Actually, given the token budget, let me be efficient. Let me do a quick grep for the most relevant pattern (gptel pre-tool-call hooks) to know if it's already implemented.

Actually, looking at the prior researcher's thinking, they already identified `gptel-pre-tool-call-functions` and `gptel-post-tool-call-functions` in the gptel library. So we know those hooks exist in gptel. The question is: does OUR auto-workflow USE them?

Let me do a quick grep to check if our local gptel-auto-workflow uses pre-tool-call hooks. This will tell us whether the governance pattern is novel for us.

Let me budget: 1 grep call, then synthesize.

Actually, the prompt says "Read-only: never write files or make repository changes" - I can read. Let me do a quick scan.
</think>Both deep reads were productive. I have the **Control Plane as a Tool** architectural pattern and the **Microsoft AGT (Agent Governance Toolkit)** concrete implementation. Both external, both novel for our project. Let me do a quick local scan to identify candidate files for the patterns, then synthesize.<think>

OK, 77 matches for the more specific patterns. Let me grep more narrowly to identify which files actually have governance hooks.

Let me grep for the actual hook usage (not just variable definitions) - i.e. lines that actually call add-hook on gptel-pre-tool-call-functions.
</think>Let me narrow the grep to find where these hooks are actually wired up in our code.<think>


Good. Key findings:
1. **NO use of `gptel-pre-tool-call-functions` or `gptel-post-tool-call-functions` hooks** in our codebase (the first grep returned no matches for add-hook on these)
2. **There IS an audit log** (`gptel-auto-workflow--routing-audit-log`) but it's a simple list, NOT hash-chained
3. There's a "kill switch" comment in gptel-config.el at line 97

This confirms the patterns are mostly novel. The Microsoft AGT pattern (deterministic pre-call policy + post-call response validation) is the biggest gap.

Let me also check briefly for failure handler / input validator / output validator patterns.

Actually, I have enough. Let me synthesize the digest now.

Key local findings to include:
- `gptel-auto-workflow-ontology-router.el` lines 3, 822-825, 2161-2205, 2351 - has a `gptel-auto-workflow--routing-audit-log` (simple list, capped at 100 entries) - NOT hash-chained
- `gptel-config.el` line 97 - has "kill switch" comment for tool confirmation
- **MISSING**: pre-tool-call hook, post-tool-call hook, deterministic policy enforcement, response inspection

Top 3-4 insights to include in the 1200 char digest:

1. **AGT: deterministic pre/post tool-call governance (Microsoft)** - Use `gptel-pre-tool-call-functions` and `gptel-post-tool-call-functions` (which exist in gptel library but are NOT used in our code) to enforce policy BEFORE and AFTER every tool call. YAML/Elisp declarative rules. Sub-ms overhead.

2. **Control Plane as a Tool (arxiv 2505.06817)** - Register a single dispatcher tool that wraps many tools. Hides tool surface from LLM (reduces prompt bloat, prevents tool poisoning), enables internal routing based on context/user/policy. Implementable in our `gptel-tools` collection.

3. **Hash-chained audit log upgrade** - Current `gptel-auto-workflow--routing-audit-log` is a flat list capped at 100. Upgrade to hash-chained append-only log (AGT pattern) for tamper-evidence and postmortem replay. Cheap in elisp.

4. **Input validator + Output validator split** - Control Plane pattern: validate input args BEFORE tool call (schema + policy) AND validate output AFTER call (content policy, no prompt injection). Current code does neither explicitly.

5. **Failure handler with structured fallback** - On tool error, return structured default response (not raw error to LLM). Prevents LLM fr
...[Result too large, truncated. Full result saved to: /home/davidwu/.emacs.d/var/tmp/gptel-subagent-result-w3iaUv.txt. Use Read tool if you need more]...

**Meta-learning:** Research quality measured by downstream experiment success.

---
*Generated by auto-workflow*
