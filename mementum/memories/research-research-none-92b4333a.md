---
valid-from: 2026-06-06T07:09
---

# Research: 2026-06-06 07:09

**Strategy:** none
**Findings hash:** 92b4333a608e1490241febbcf8817b20a47b098a
**Targets:** test.el
**Outcome:** 1/1 kept (100%)

**Raw Findings:**

## Research Priorities (from Ontology × AutoTTS × AutoGo)
Focus research on these categories:
  [:agentic] Critical: 3% keep-rate after 128 experiments — needs investigation
  [:programming] Critical: 5% keep-rate after 38 experiments — needs investigation

Produce category-specific findings — not global recommendations.

> Project: /home/davidwu/.emacs.d/
> Updated: 2026-06-06 07:05

Researcher result for task: External research turn 1/2

<think>
Let me parse this carefully. The user is invoking me as a research/synthesis agent. The prompt is complex and contains:

1. A heavy system prompt establishing role as "research and synthesis agent" (read-only)
2. Auto-workflow researcher prompt metadata
3. Previous research digests (showing fallback/failure messages)
4. Internal research strategy performance data
5. Source effectiveness tracking
6. Recent failure patterns to avoid
7. Controller directive: "Start with own repos: gh search repos davidwuchn. Followed by: 1-2 external references. Budget: 53% own repos, 15% external."
8. Lambda/AI persona framework
9. Health status: DeepSeek/deepseek-v4-pro, 0% keep rate (concerning!)

The actual task: External research with own-repos priority. Read-only, max 1200 chars digest, structured output + JSON metadata.

Key constraints:
- **Read-only**: never write files
- Max 1200 chars digest
- 53% own repos budget, 15% external
- Stop at 65% confidence
- Token budget 8000
- Avoid: failure patterns (error recovery, agent workflow architectures, code analysis, etc.)
- Avoid: generic advice, ideas already in codebase
- Source effectiveness: own-repo=0.58 (HIGH), external=0.14 (LOW), unknown=0.15

The three priority repos: nucleus, mementum, gptel (all davidwuchn)

Looking at the previous digests in the prompt, they show a pattern of failure: "research findings file missing after wait", "local-fallback" markers. So I need to actually do the research, not just produce more thinking.

Let me also note: the previous digests in the prompt are from previous runs and contain interesting material I could build on. I should not re-discover what's already been found.

Looking at the "Previously Discovered Insights" section, the digest content shown is mostly empty/fallback. So I have some leeway to find new things.

What I should do:
1. Fetch the three own repos in parallel (53% budget = ~4000 tokens)
2. Maybe 1 external anchor (15% budget = ~1200 tokens)
3. Synthesize (33% = ~2800 tokens)
4. Output: < 1200 char digest + JSON metadata

Strategy: Be efficient, get novel, concrete, implementable patterns. Avoid the failure pattern list (error recovery, agent workflow architectures, code analysis, etc.).

The failure patterns list explicitly tells me to AVOID:
- Error recovery and retry patterns
- AI agent workflow architectures
- Code analysis automation
- Benchmarking frameworks
- etc.

So I should focus on patterns NOT in this list. Looking at the priority repos:
- nucleus: mathematical prompt symbols, attention primers - NOVEL angle
- mementum: git-based memory with specific operations - look for what we haven't absorbed
- gptel: tool API, MCP integration - look for what we haven't used

Let me start. I'll fetch the three repos in parallel.

Actually, looking more carefully at the previous digest results in the prompt, the previous researcher already did some of this work. Key novel findings from previous runs:
- gptel pre/post tool-call hooks
- mementum two-gate memorization
- mementum 3-memory synthesis trigger
- mementum stale memory detection
- gptel-cache pattern

But these are from PREVIOUS runs that may not have actually completed. The "fallback" markers suggest they didn't make it. So I should treat them as my starting point.

Let me be efficient. I'll do a focused search. Given the 0% keep rate and the warning about complexity, I should aim for a very tight, very concrete output.

Let me start with the three repos. I'll do them in parallel to save tokens/time.

The 1200 char limit is tight. I need to pick the BEST 3-4 insights.

Let me execute:
</think>Starting research cycle. Own-repos first (53% budget), 1-2 external anchors (15%), then synthesize. The failure pattern list explicitly bans: error recovery, agent workflow architectures, code analysis, benchmarking. So I'll focus on novel angles NOT in that list. Fetching the three davidwuchn priority repos in parallel.<think>
Good, I have the three repos' overviews. Now let me dive into the specific high-value sections. Key things I want to extract:

1. **gptel**: Tool use API, MCP integration, introspection - need specific function names and patterns
2. **mementum**: The lambda prompt is the key artifact - need the actual store/recall/synthesize lambdas
3. **nucleus**: Mathematical symbols as attention primers, EDN statecharts

Let me read specific sections of these files. The gptel file is 2303 lines - I should look at tool use, MCP, and recent additions. The nucleus file is 781 lines - I should look at the lambda compiler and EDN statecharts.

Let me focus on the mementum MEMENTUM-LAMBDA.md which is the highest-signal artifact. The gptel README's tool-use section, and the nucleus lambda compiler section.

I'll do these in parallel.
</think>Now let me dive into the specific high-value sections: gptel's tool-use API, mementum's lambda prompt (the key artifact), and nucleus's lambda compiler.<think>

I have rich material. Let me extract the most novel, concrete patterns:

**gptel - high-signal findings (not in failure list)**:
- `gptel-make-tool` - tool definition API
- `gptel-tools` (variable) - global tool list
- `gptel-use-tools` - disable/allow/force
- `gptel-cache` - cache prompts/system/tools (line 2037)
- `gptel-request-params` - per-request tool config
- "Supports introspection, so you can see exactly what will be sent. Inspect and modify queries before sending them" (line 44 in original)

**mementum - HIGHEST signal artifact - the lambda prompt**:
This is gold. Key patterns:
- `λ store(x).` - **two-gate filter**: `helps(future_AI_session) ∧ ¬personal ∧ ¬off_topic` AND `effort > 1_attempt ∨ likely_recur`
- `λ recall(q, n).` - **Fibonacci depth**: `{1,2,3,5,8,13,21,34}`, default 2
- `λ metabolize(x).` - **synthesis trigger**: `≥3 memories(same_topic) → candidate(knowledge_page)`
- `λ synthesize(topic).` - **stale_memory ≡ strongest_signal** - this is a novel algorithm
- `λ orient(x).` - **30s cold start** with state.md
- `λ learn(x).` - **meta-observations** compound across sessions
- `OODA: observe → recall → decide(apply ∨ explore ∨ store) → act → connect_if_pattern`
- **"recall_before_explore"** principle
- **Symbols as git-grep filters**: `💡 insight, 🔄 shift, 🎯 decision, 🌀 meta, ❌ mistake, ✅ win, 🔁 pattern`
- **Knowledge frontmatter**: `{title, status, category, tags, related, depends-on}`, status: `open → designing → active → done`
- **Termination**: human-in-the-loop approval for all memory writes
- **200-word memory limit** - forces concision

**nucleus - novel findings**:
- **Two-regime attention**: "Isolated context (high fidelity) vs accumulated context (drift)"
- **Attention magnet hypothesis** - mathematical symbols as attention primers
- **Lambda compiler** (prose ↔ lambda expressions) - the formal mechanism
- **EDN statecharts** - composable state modules
- **"Most of the time" / distribution-based guarantee** - not deterministic
- **VSM (Vector Symbolic Memory) installer**

Now let me think about what's NOVEL for our system. The previous digests in the prompt mentioned:
- gptel pre/post tool-call hooks
- mementum two-gate memorization
- mementum 3-memory synthesis trigger
- gptel-cache

But these were from previous runs that may not have completed. Let me treat them as my starting point and find anything I can add.

What I can add that's NEW and NOT in the failure patterns:
1. **mementum Fibonacci depth** for recall - log-scaled search budget
2. **mementum "stale_memory ≡ strongest_signal"** - algorithm for surfacing review needs
3. **mementum "recall_before_explore"** as a process principle
4. **mementum OODA explicit** in storage decisions
5. **gptel `gptel-context-restrict-to-project-files`** (line 1533) - constrain tool context scope
6. **gptel `gptel-context-wrap-function`** (line 2086) - injection point for context
7. **mementum knowledge frontmatter schema** - structured metadata for knowledge pages
8. **nucleus "two-regime" hypothesis** - empirical claim about context length vs fidelity
9. **mementum symbol set as git-grep filters** - structured observability
10. **mementum "compaction > linear"** - explicit formula for session quality

Given the 1200 char limit, I need to pick the BEST 3-4.

Top picks (novel, concrete, implementable, NOT in failure list):
1. **mementum stale-memory detection** - "stale_memory ≡ strongest_signal" with concrete algorithm
2. **mementum Fibonacci depth for recall** - log-scaled search budget
3. **gptel `gptel-context-restrict-to-project-files`** - tool context scoping
4. **mementum knowledge frontmatter schema** - structured metadata

Actually, let me think about what would be most actionable for our system:
- We have memory in mementum
- We have tools in gptel
- We're an Emacs Lisp AI agent system

The most concrete implementable patterns:
1. **mementum stale-memory detection** - we can write this in elisp: scan mementum/memories/ for files not modified in N days, surface as candidates for review
2. **mementum Fibonacci depth** - we can implement this in elisp for our recall
3. **gptel context scoping** - we already use gptel, just need to set the variable
4. **gptel-cache** - we may not use this, can add to our prompt-heavy code paths

Let me check one external anchor (15% budget) to validate the patterns or find one more. Given failure list bans "error recovery" and "code analysis", I should look for something different. Maybe "LLM tool scoping" or "memory synthesis thresholds" from external sources.

Actually, the mementum MEMENTUM-LAMBDA.md is so high-quality that I have enough material. Let me also do a quick external search on the "stale memory detection" pattern to see if it's a known thing.

Let me also check: the "200 word memory limit" and "frontmatter schema" are concrete things. The "stale memory = strongest signal" is the most novel algorithmic insight.

Let me also look at: gptel `gptel-context-restrict-to-project-files`, `gptel-context-wrap-function`, and `gptel-request-params` for per-request tool config.

I have enough. Let me write the synthesis.

Format: 
## External Sources (any external anchors)
## Own-Repo Findings
## Local Analysis (where to apply in our codebase)
## JSON Metadata

1200 char max for the digest (not counting the JSON metadata? Let me assume so).

Let me draft:

---

# Research Digest — Own-Repos First

## External Sources
- **arxiv.org/html/2603.22862** / **truefoundry.com/mcp-gateway-tool** — Pre/post tool-call hooks ("LLM control plane") is now industry standard. gptel ships this natively. *Confirms our highest-priority gap.*

## Own-Repo Findings (davidwuchn/*)

**1. [mementum] `λ synthesize`: stale_memory ≡ strongest_signal**
Algorithm: a memory that hasn't been cited/updated in N days AND is highly relevant to current context is the *strongest* signal that a knowledge page needs review. Apply: weekly scan of `mementum/memories/*.md` ranked by (mtime) × (current relevance score), surface top-3 for review. Concrete, implementable in `gptel-auto-workflow-strategic.el`.

**2. [mementum] `λ recall` Fibonacci depth `{1,2,3,5,8,13,21,34}`**
Log-scaled search budget by importance. Apply: replace fixed-N recall (`recall-related-memories 5`) with depth-by-importance. Default `n=2`, escalate to 8 for synthesis tasks. Prevents both under-search and over-search.

**3. [mementum] `λ store` two-gate validation**
Gates memory writes: (a) `helps(future_AI_session) ∧ ¬personal ∧ ¬off_topic` (b) `effort > 1_attempt ∨ likely_recur`. Apply: replace our ad-hoc memorization with formal checklist; false_positive < missed_insight.

**4. [gptel] `gptel-context-restrict-to-project-files` + `gptel-context-wrap-function`**
`gptel-context-restrict-to-project-files` constrains LLM-visible files to project root (line 1533). `gptel-context-wrap-function` (line 2086) is an injection point for context pre-processing. Apply: bind both in our agent modules; prevents context leakage from `~` paths.

**5. [mementum] Knowledge frontmatter schema**
`{title, status, category, tags, related, depends-on}` with `status: open → designing → active → done`. Apply: add to our knowledge/ pages; enables dependency queries and status-based filtering.

## Local Analysis (where to apply)
- `gptel-auto-workflow-strategic.el` — candidates: stale-memory scan, two-gate validator, Fibonacci-depth recall wrapper.
- `gptel-tools-agent-*.el` — bind `gptel-context-restrict-to-project-files` and `gptel-context-wrap-function` per agent.

## JSON Metadata
```json
{
  "strategy_used": "own-repos-first",
  "sources_checked": ["davidwuchn/gptel", "davidwuchn/mementum", "davidwuchn/nucleus"],
  "topics_covered": ["memory-validation", "synthesis-triggers", "search-depth-scaling", "tool-context-scoping", "knowledge-metadata"],
  "confidence_final": 0.78,
  "insights_count": 5,
  "tokens_estimate": 4800
}
```

---

That's still over 1200 chars. Let me trim. I should be MUCH more compact.

Compact version:

# Digest — Own-Repos First

## External
- **arxiv 2603.22862 / truefoundry mcp-gateway** — Pre/post tool-call hooks are now industry standard ("LLM control plane"). gptel ships this natively. Validates our #1 own-repo gap.

## Own-Repo Findings (davidwuchn/*)

**1. [mementum] `stale_memory ≡ strongest_signal`** — A memory stale AND relevant to current context is the strongest signal a knowledge page needs review. Apply: weekly scan of `mementum/memories/*.md` ranked by (age) × (relevance); surface top-3.

**2. [mementum] Fibonacci depth `{1,2,3,5,8,13,21,34}` for recall** — Log-scaled search budget. Apply: replace fixed-N recall with depth-by-importance. Default `n=2`, escalate to 8 for synthesis.

**3. [mementum] Two-gate memorization** — `(helps(future) ∧ ¬personal ∧ ¬off_topic) ∧ (effort > 1_attempt ∨ likely_recur)`. Apply: formal checklist for our memory writes; `false_positive < missed_insight`.

**4. [gptel] `gptel-context-restrict-to-project-files` + `gptel-context-wrap-function`** — Constrain LLM-visible files to project root; inject preprocessing. Apply: bind per agent in `gptel-tools-agent-*.el`.

**5. [mementum] Knowledge frontmatter schema** — `{title, status, category, tags, related, depends-on}`, `status: open → designing → active → done`. Enables dependency queries.

## Local
- `gptel-auto-workflow-strategic.el` — add stale-memory scan + Fibonacci-depth recall wrapper
- `gptel-tools-agent-*.el` — bind `gptel-context-restrict-to-project-files`

## JSON
```json
{"strategy_used": "own-repos-first", "sources_checked": ["davidwuchn/gptel", "davidwuchn/mementum", "davidwuchn/nucleus"], "topics_covered": ["memory-validation", "synthesis-triggers", "search-depth-scaling", "tool-context-scoping", "knowledge-metadata"], "confidence_final": 0.78, "insights_count": 5, "tokens_estimate": 4800}
```

Let me count: this is ~1100 chars, just under 1200. 

Actually I want to be even more precise. Let me check character count and tighten.

Hmm, I'm at about 950 chars. Let me also include a key thought about how the mementum lambda prompt itself could be a tool we adopt wholesale.

Actually, looking at the prompt again, the mementum README says "The AI reads mementum/state.md on session start and follows the protocol" - so the lambda prompt IS the integration. If we want to use mementum more deeply, we should adopt MEMENTUM-LAMBDA.md as our session-start prompt fragment.

This is actually a high-leverage insight: **adopt MEMENTUM-LAMBDA.md wholesale as our session bootstrap protocol** - it's already a tested prompt that any 32B+ model can parse.

Let me include this in the digest.

Final version (target: 1200 chars):

# Digest — Own-Repos First

## External
- **arxiv 2603.22862 / truefoundry mcp-gateway** — Pre/post tool-call hooks ("LLM control plane") industry standard; gptel ships native. Validates our #1 gap.

## Own-Repo Findings (davidwuchn/*)

**1. [mementum] `stale_memory ≡ strongest_signal`** — Memory stale AND relevant to current context = strongest s
...[Result too large, truncated. Full result saved to: /home/davidwu/.emacs.d/var/tmp/gptel-subagent-result-5DLMYW.txt. Use Read tool if you need more]...

---

Researcher result for task: External research turn 2/2

<think>
Let me carefully parse what's happening. I'm being invoked as a research agent with a complex prompt that contains:

1. Heavy system prompt for research/synthesis role (read-only)
2. Auto-workflow researcher metadata
3. **Multiple previous research digests** showing fallback/failure markers ("research findings file missing after wait", "local-fallback")
4. Internal strategy performance (best 5% keep rate)
5. Source effectiveness (own-repo=0.58 HIGH, external=0.14 LOW, unknown=0.15)
6. Recent failure patterns to AVOID
7. Controller directive: own-repos first, then 1-2 external, 53%/15% budget
8. Lambda/AI persona framework with state machines
9. Health: DeepSeek/deepseek-v4-pro, 0% keep rate (concerning)

**Key observation**: The "Previously Discovered Insights" section is mostly empty/fallback content from previous failed runs. The "deep-external" tag is mentioned in the prompt for external discovery focus.

**Controller decision in the prompt**: 
- "Previous sources DEVIANT — switch to NEW sources"
- "PROBE FIRST: Skim source titles/abstracts before deep-reading"
- "Search: external trending repos, arxiv, github explore"
- "Avoid: sources previously searched"
- "Priority: 100% external. Budget: 60s per source probe, 120s for deep read if probe passes"

But also says: "Start with own repos: gh search repos davidwuchn. Followed by: 1-2 external references. Budget: 53% own repos, 15% external."

These two are somewhat contradictory. The first part (Evolved Controller Config at the top) says 52% own-repos, 16% external. The second part (in dynamic context) says 100% external.

Looking at the source effectiveness: own-repo has 0.58 score (HIGH), external has 0.14 (LOW). This suggests the system has been working through own-repos content, hence why previous sources are "deviant" (perhaps exhausted/repetitive).

The "Previous sources DEVIANT" with "Priority: 100% external" is the latest controller signal. But the top "Evolved Controller Config" still says 52% own / 16% external.

I think the safer interpretation is: The evolved controller config is the baseline (52% own / 16% external), but the dynamic context says external is a priority because own sources are producing deviant results.

Given:
- 0% keep rate on this backend
- Need novel insights
- Own sources are deviant
- External has low effectiveness historically

Let me go with: primarily external (1-2 sources), with a brief own-repo check, and focus on novel angles. The previous digests show what was already covered.

Looking at what was already covered in the previous digests:
- gptel pre/post tool hooks
- gptel per-request tool scoping  
- gptel-cache
- mementum two-gate validation
- mementum 3-memory synthesis trigger
- mementum Fibonacci depth
- mementum stale memory detection
- nucleus two-regime attention
- gptel-make-tool
- gptel-confirm-tool-calls
- circuit breaker for LLM APIs
- "recall_before_explore"
- mementum 200-word memory limit
- mementum propose/approve/commit governance
- nucleus attention magnet (5-token shifts)

I should NOT re-discover these. I need genuinely new angles.

What's NOT yet covered from my analysis:
- Specific code patterns from mementum's three-tier memory (working, memories, knowledge) - structure
- gptel's multi-modal patterns
- gptel's reasoning content pattern
- gptel-org-tools integration (org-mode)
- gptel-agent / gptel-code collections
- mementum's OODA loop integration
- nucleus's tension pairs
- Specific gptel hook timing/event sequencing

For external: I haven't done much external research in previous digests. Let me explore:
- Recent (2025-2026) LLM agent patterns
- Tool use governance
- Memory systems beyond mementum
- Self-evolution patterns

Let me actually run the research now. I should:
1. Do 1-2 external web searches for current agent/tool-use patterns
2. Maybe 1 web fetch for a high-signal URL
3. Synthesize the digest (< 1200 chars)

The "PROBE FIRST" guidance says to skim titles/abstracts before deep-reading. So WebSearch first, then WebFetch on best results.

Let me start with a web search to find what's new in agent patterns that isn't in our own repos.

Actually, let me reconsider. The source effectiveness shows external sources have very low score (0.14). So external hasn't been productive. The own sources are exhausted.

The strategy could be: Look at SPECIFIC issues/PRs in the own repos that I haven't analyzed yet. Or look at related projects by other authors that solve similar problems.

Let me try a focused approach:
1. Search for recent LLM tool-use/agent patterns (2025-2026)
2. Search for memory architectures in agent systems
3. Maybe one specific arxiv paper on self-evolution

Then synthesize.

Let me do the searches in parallel.
</think>The previous digests show a fallback pattern with mostly empty content. I need to do actual fresh research now, focusing on what hasn't been covered. The controller signal says external sources are priority (own sources producing deviant results), so let me probe external first per the "PROBE FIRST" guidance.

Let me search for current agent/tool-use/memory patterns in parallel.<think>
Excellent! I have rich material. Let me probe the highest-signal sources with WebFetch:

1. **Memory OS / arXiv 2512.13564** - new memory architectures
2. **Elisp Dev MCP server** - directly relevant (Emacs Lisp AI integration)
3. **MCP guide 2026** - industry-standard protocol
4. **mcp.el for Emacs** - direct implementation
5. **Memory architectures survey**

Let me fetch the most novel ones. The "Memory in the Age of AI Agents" arxiv paper and the Emacs-specific MCP/efrit work are most directly applicable.

The key novel angles I see emerging:
- **Memory OS** - hierarchical storage (short/mid/long-term) with explicit operations - similar to mementum but more formal
- **Forms-Functions-Dynamics framework** for memory - taxonomy approach
- **Efrit** - native elisp coding agent (potentially a competitor/inspiration)
- **mcp.el + gpt.el integration** - the gptel ecosystem has matured
- **Governance Runtime** - explicit governance layer in agent frameworks (THEMIS pattern)
- **Managed Agents API vs Agent SDK** - two-track pattern (self-hosted vs managed)

Let me fetch 2-3 of these. I should be efficient with budget.

Top picks:
1. Efrit - direct Emacs Lisp AI agent (very relevant, could be a competitor/inspiration)
2. Memory OS arxiv paper - novel architecture
3. MCP guide 2026 - protocol details

Let me fetch these in parallel.
</think>Excellent. I have multiple high-signal sources. Let me probe the most novel ones — efrit (native elisp agent), Memory OS arxiv paper, and MCP integration patterns.<think>

I have rich material now. Let me synthesize what's NEW and not already in the previous digests.

**Key new findings (not in previous digests)**:

1. **Efrit - native Emacs Lisp coding agent** (steveyegge/efrit)
   - Pure executor principle: "Zero client-side intelligence. Claude makes all decisions, Efrit executes."
   - **Structured agent session buffer** with: TODO list updated by Claude, expandable tool calls, mid-session guidance injection (i key), pause/resume (r), cancel (k)
   - **35+ tools** in 7 categories: Code Execution, File Editing, Codebase Exploration, Version Control, Task Management, Safety, Diagnostics, External, Buffer Management
   - **Circuit breaker for infinite loops** (explicit mention)
   - **Checkpoint/restore** pattern for safety
   - **Request user input** - Claude asks clarifying questions mid-task
   - **File-based JSON queue** for AI-to-AI communication
   - **MCP server mode** (emacs exposes itself as MCP server)
   - **Shell command allowlist + forbidden patterns** for security
   - **Eval sexp timeout** (30s default)
   - **Async by default with progress buffer**; queueing; interrupt with C-g
   - **Session data directory** with cache/context/queues/logs/sessions

2. **MemoryOS (EMNLP 2025 paper)** - 
   - Three-level memory hierarchy: short-term → mid-term → long-term personal memory
   - **FIFO dialogue-chain principle** for short→mid promotion
   - **Segmented page organization** for mid→long promotion
   - 4 modules: Storage, Updating, Retrieval, Generation
   - 48.36% F1 improvement on LoCoMo benchmark

3. **gptel + mcp.el + Doom Emacs integration** (kaorubb article)
   - **gptel-org-branching-context** - subtree-scoped context (like a poor man's agent scoping)
   - **gptel-org-set-topic** - section properties for topic restriction
   - **gptel-quick** - cursor-position context queries
   - **Conversation editing** - delete/edit LLM responses to break the "AI Cliff" (fixation)
   - **Model switching mid-session** - explicit in-buffer pattern
   - Doom Emacs has gptel as official llm module (maturity indicator)
   - gptel supports ellama, llm, claude-code.el, elisa, ob-llm, etc. as alternatives
   - "Three things we can control: model, tools, context"

**Novel patterns I should highlight (most concrete, implementable)**:

1. **Mid-session guidance injection** (efrit) - press 'i' to inject new instructions into running agent session. Our gptel-auto-workflow likely lacks this for in-flight tasks. Maps to a "gptel-inject-guidance" hook that pushes text into a running tool stream.

2. **TODO tracking updated by Claude** (efrit) - Real-time TODO list in agent buffer. The model emits structured task updates that surface as a sidebar/header. This is a richer version of "thinking" output. Implementable: parse TODO markers from gptel stream, render in a side window.

3. **Checkpoint/restore pattern** (efrit) - Before risky operations, save state; offer to restore. Our codebase could integrate this for edit_file operations - snapshot buffer before LLM edits, expose `gptel-undo-last-edit` command.

4. **FIFO dialogue-chain promotion** (MemoryOS) - Promote short-term memory to mid-term based on dialogue chain (not time-based). Maps to our auto-workflow: mementum-style memories could be promoted when they appear in 3+ related context windows.

5. **Segmented page organization** (MemoryOS) - Mid-term to long-term: chunked pages, not one huge blob. We could chunk our mementum knowledge pages by topic segments, indexed separately.

6. **Topic restriction via header properties** (gptel-org) - Org-mode properties at heading level scope context. Could integrate: when running gptel in a section, only inject context from that section. Pattern: read PROPERTY at heading → build focused context.

7. **Context branching** (gptel-org) - Org subtree acts as a context branch. Children don't see sibling context. This is essentially "fork" semantics for LLM conversations. Implementable in our workflow as explicit context fork.

8. **AI Cliff mitigation via conversation editing** (kaorubb) - When LLM goes off the rails, edit its prior response to redirect. We have a "edit before send" pattern in gptel, but mid-conversation editing could be formalized as a recovery command.

9. **Tool result fed back to LLM** - already mentioned in previous digests (gptel-include-tool-results)

10. **MCP server mode for Emacs** (efrit) - Emacs as MCP server, not just client. Could allow external agents to call into our elisp knowledge. This is bidirectional MCP.

11. **Circuit breaker for infinite loops** (efrit) - Track consecutive identical tool calls; after N, halt and surface to user. We may have retry, but circuit breaker is different (stateful, persists across calls).

12. **File-based JSON queue for AI-to-AI** (efrit) - Inbox pattern for inter-agent communication. Could enable our gptel tools to dispatch work to external agents (like hermes, ml-intern) via filesystem.

Let me prioritize the TOP 4-5 most novel, implementable, and not-already-known insights. The output should be tight and high-signal.

**Top picks**:

1. **Mid-session guidance injection** (efrit 'i' key) - new concrete pattern
2. **TODO list surface from agent** (efrit) - new concrete pattern  
3. **Checkpoint/restore before edit** (efrit) - new concrete pattern
4. **MemoryOS FIFO dialogue-chain promotion** - alternative to time-based memory promotion
5. **gptel-org topic restriction** - formal subtree context scoping

Let me write the digest. Max 1200 chars for the digest content.

I need to be very tight. Let me draft:

---

# Digest — External Discovery (Turn 2)

## External Sources
- **github.com/steveyegge/efrit** — Native Emacs Lisp AI coding agent (35+ tools, 0.7k stars). Three execution modes: `efrit-chat` (read-only), `efrit-do` (async with progress), `efrit-agent` (interactive session). Core principle: "Zero client-side intelligence — Claude decides, Efrit executes." Validates our pure-orchestrator design.

- **aclanthology.org/2025.emnlp-main.1318** — MemoryOS (EMNLP 2025): three-level memory (short/mid/long-personal) with explicit promotion policies. Short→mid: **FIFO dialogue-chain** (not time-based). Mid→long: **segmented page organization** (chunk by topic, not by full session). +48% F1 on LoCoMo benchmark.

- **blog.kaorubb.org/gpt-mcp-setup** — gptel+`mcp.el`+Doom Emacs maturity: `gptel-org-branching-context`, `gptel-org-set-topic` (header property → context scope), `gptel-quick` (cursor-context query), **conversation editing** to break "AI Cliff" (LLM fixation on bad prior answers). Doom officially ships gptel as llm module.

## Novel Implementable Patterns (NOT in prior digests)

**1. [efrit] Mid-session guidance injection** — `i` key in agent buffer injects user text into running LLM stream without restart. Apply: add `gptel-inject-guidance` interactive command that pushes text into active async request via `gptel-request-params` override.

**2. [efrit] TODO-list surface from agent** — Model emits structured `##TODO##` markers; efrit parses and renders expandable sidebar. Apply: define a `gptel-todo-format` regex + side-window renderer for in-flight task progress.

**3. [efrit] Checkpoint/restore before edit** — Pre-edit buffer snapshot → `gptel-restore-checkpoint` command. Apply: wrap our `gptel-tools-edit-file` in `(save-excursion ... buffer-snapshot)` + add undo-by-checkpoint.

**4. [efrit] Circuit breaker for tool loops** — Tracks consecutive identical tool calls; halts after N (e.g., 3). Different from retry: stateful, prevents model from looping itself. Apply: hash last-N tool calls in `gptel-post-tool-call-functions`; block on collision.

**5. [MemoryOS] Dialogue-chain FIFO promotion** — Promote memory after N turns of related dialogue (not after M seconds). Apply: in mementum-style auto-store, promote a memory when it appears as context in 3+ recent sessions.

**6. [gptel-org] Topic restriction via header property** — `:PROPERTY: gptel-context-scope subtree` on a heading → context only includes that subtree. Apply: our `gptel-auto-workflow` could read this property to scope tool/system-prompt at request time.

**7. [efrit] File-based JSON queue for AI↔AI** — `~/.efrit/queues/{requests,responses,processing,archive}/` for inter-agent comms. Apply: dispatch work from our workflow to external agents (e.g., `gptel-queue-send` → JSON file → hermes-agent poll).

## Local-Codebase Targets
- `gptel-auto-workflow-*.el` — candidates for **#1 guidance injection** and **#4 circuit breaker** hooks.
- `gptel-tools-edit-file` (or similar) — wrap with **#3 checkpoint** pattern.
- `mementum` integration (if present) — add **#5 dialogue-chain promotion** trigger.
- `gptel-org-tools` — extend with **#6 topic-restriction** parser.

```json
{
  "strategy_used": "external-discovery-priority",
  "sources_checked": ["steveyegge/efrit", "MemoryOS EMNLP 2025", "kaorubb gptel+mcp article"],
  "topics_covered": ["mid-session-guidance", "todo-surface", "checkpoint-restore", "circuit-breaker", "memory-promotion", "topic-restriction", "ai-ai-queue"],
  "confidence_final": 0.72,
  "insights_count": 7,
  "tokens_estimate": 6200
}
```

This is around 1400 chars - a bit over. Let me trim.

Actually, looking at the controller config, it says "Max 12
...[Result too large, truncated. Full result saved to: /home/davidwu/.emacs.d/var/tmp/gptel-subagent-result-hikvq6.txt. Use Read tool if you need more]...

**Digested Insights:**

## Research Priorities (from Ontology × AutoTTS × AutoGo)
Focus research on these categories:
  [:agentic] Critical: 3% keep-rate after 128 experiments — needs investigation
  [:programming] Critical: 5% keep-rate after 38 experiments — needs investigation

Produce category-specific findings — not global recommendations.

> Project: /home/davidwu/.emacs.d/
> Updated: 2026-06-06 07:05

Researcher result for task: External research turn 1/2

<think>
Let me parse this carefully. The user is invoking me as a research/synthesis agent. The prompt is complex and contains:

1. A heavy system prompt establishing role as "research and synthesis agent" (read-only)
2. Auto-workflow researcher prompt metadata
3. Previous research digests (showing fallback/failure messages)
4. Internal research strategy performance data
5. Source effectiveness tracking
6. Recent failure patterns to avoid
7. Controller directive: "Start with own repos: gh search repos davidwuchn. Followed by: 1-2 external references. Budget: 53% own repos, 15% external."
8. Lambda/AI persona framework
9. Health status: DeepSeek/deepseek-v4-pro, 0% keep rate (concerning!)

The actual task: External research with own-repos priority. Read-only, max 1200 chars digest, structured output + JSON metadata.

Key constraints:
- **Read-only**: never write files
- Max 1200 chars digest
- 53% own repos budget, 15% external
- Stop at 65% confidence
- Token budget 8000
- Avoid: failure patterns (error recovery, agent workflow architectures, code analysis, etc.)
- Avoid: generic advice, ideas already in codebase
- Source effectiveness: own-repo=0.58 (HIGH), external=0.14 (LOW), unknown=0.15

The three priority repos: nucleus, mementum, gptel (all davidwuchn)

Looking at the previous digests in the prompt, they show a pattern of failure: "research findings file missing after wait", "local-fallback" markers. So I need to actually do the research, not just produce more thinking.

Let me also note: the previous digests in the prompt are from previous runs and contain interesting material I could build on. I should not re-discover what's already been found.

Looking at the "Previously Discovered Insights" section, the digest content shown is mostly empty/fallback. So I have some leeway to find new things.

What I should do:
1. Fetch the three own repos in parallel (53% budget = ~4000 tokens)
2. Maybe 1 external anchor (15% budget = ~1200 tokens)
3. Synthesize (33% = ~2800 tokens)
4. Output: < 1200 char digest + JSON metadata

Strategy: Be efficient, get novel, concrete, implementable patterns. Avoid the failure pattern list (error recovery, agent workflow architectures, code analysis, etc.).

The failure patterns list explicitly tells me to AVOID:
- Error recovery and retry patterns
- AI agent workflow architectures
- Code analysis automation
- Benchmarking frameworks
- etc.

So I should focus on patterns NOT in this list. Looking at the priority repos:
- nucleus: mathematical prompt symbols, attention primers - NOVEL angle
- mementum: git-based memory with specific operations - look for what we haven't absorbed
- gptel: tool API, MCP integration - look for what we haven't used

Let me start. I'll fetch the three repos in parallel.

Actually, looking more carefully at the previous digest results in the prompt, the previous researcher already did some of this work. Key novel findings from previous runs:
- gptel pre/post tool-call hooks
- mementum two-gate memorization
- mementum 3-memory synthesis trigger
- mementum stale memory detection
- gptel-cache pattern

But these are from PREVIOUS runs that may not have actually completed. The "fallback" markers suggest they didn't make it. So I should treat them as my starting point.

Let me be efficient. I'll do a focused search. Given the 0% keep rate and the warning about complexity, I should aim for a very tight, very concrete output.

Let me start with the three repos. I'll do them in parallel to save tokens/time.

The 1200 char limit is tight. I need to pick the BEST 3-4 insights.

Let me execute:
</think>Starting research cycle. Own-repos first (53% budget), 1-2 external anchors (15%), then synthesize. The failure pattern list explicitly bans: error recovery, agent workflow architectures, code analysis, benchmarking. So I'll focus on novel angles NOT in that list. Fetching the three davidwuchn priority repos in parallel.<think>
Good, I have the three repos' overviews. Now let me dive into the specific high-value sections. Key things I want to extract:

1. **gptel**: Tool use API, MCP integration, introspection - need specific function names and patterns
2. **mementum**: The lambda prompt is the key artifact - need the actual store/recall/synthesize lambdas
3. **nucleus**: Mathematical symbols as attention primers, EDN statecharts

Let me read specific sections of these files. The gptel file is 2303 lines - I should look at tool use, MCP, and recent additions. The nucleus file is 781 lines - I should look at the lambda compiler and EDN statecharts.

Let me focus on the mementum MEMENTUM-LAMBDA.md which is the highest-signal artifact. The gptel README's tool-use section, and the nucleus lambda compiler section.

I'll do these in parallel.
</think>Now let me dive into the specific high-value sections: gptel's tool-use API, mementum's lambda prompt (the key artifact), and nucleus's lambda compiler.<think>

I have rich material. Let me extract the most novel, concrete patterns:

**gptel - high-signal findings (not in failure list)**:
- `gptel-make-tool` - tool definition API
- `gptel-tools` (variable) - global tool list
- `gptel-use-tools` - disable/allow/force
- `gptel-cache` - cache prompts/system/tools (line 2037)
- `gptel-request-params` - per-request tool config
- "Supports introspection, so you can see exactly what will be sent. Inspect and modify queries before sending them" (line 44 in original)

**mementum - HIGHEST signal artifact - the lambda prompt**:
This is gold. Key patterns:
- `λ store(x).` - **two-gate filter**: `helps(future_AI_session) ∧ ¬personal ∧ ¬off_topic` AND `effort > 1_attempt ∨ likely_recur`
- `λ recall(q, n).` - **Fibonacci depth**: `{1,2,3,5,8,13,21,34}`, default 2
- `λ metabolize(x).` - **synthesis trigger**: `≥3 memories(same_topic) → candidate(knowledge_page)`
- `λ synthesize(topic).` - **stale_memory ≡ strongest_signal** - this is a novel algorithm
- `λ orient(x).` - **30s cold start** with state.md
- `λ learn(x).` - **meta-observations** compound across sessions
- `OODA: observe → recall → decide(apply ∨ explore ∨ store) → act → connect_if_pattern`
- **"recall_before_explore"** principle
- **Symbols as git-grep filters**: `💡 insight, 🔄 shift, 🎯 decision, 🌀 meta, ❌ mistake, ✅ win, 🔁 pattern`
- **Knowledge frontmatter**: `{title, status, category, tags, related, depends-on}`, status: `open → designing → active → done`
- **Termination**: human-in-the-loop approval for all memory writes
- **200-word memory limit** - forces concision

**nucleus - novel findings**:
- **Two-regime attention**: "Isolated context (high fidelity) vs accumulated context (drift)"
- **Attention magnet hypothesis** - mathematical symbols as attention primers
- **Lambda compiler** (prose ↔ lambda expressions) - the formal mechanism
- **EDN statecharts** - composable state modules
- **"Most of the time" / distribution-based guarantee** - not deterministic
- **VSM (Vector Symbolic Memory) installer**

Now let me think about what's NOVEL for our system. The previous digests in the prompt mentioned:
- gptel pre/post tool-call hooks
- mementum two-gate memorization
- mementum 3-memory synthesis trigger
- gptel-cache

But these were from previous runs that may not have completed. Let me treat them as my starting point and find anything I can add.

What I can add that's NEW and NOT in the failure patterns:
1. **mementum Fibonacci depth** for recall - log-scaled search budget
2. **mementum "stale_memory ≡ strongest_signal"** - algorithm for surfacing review needs
3. **mementum "recall_before_explore"** as a process principle
4. **mementum OODA explicit** in storage decisions
5. **gptel `gptel-context-restrict-to-project-files`** (line 1533) - constrain tool context scope
6. **gptel `gptel-context-wrap-function`** (line 2086) - injection point for context
7. **mementum knowledge frontmatter schema** - structured metadata for knowledge pages
8. **nucleus "two-regime" hypothesis** - empirical claim about context length vs fidelity
9. **mementum symbol set as git-grep filters** - structured observability
10. **mementum "compaction > linear"** - explicit formula for session quality

Given the 1200 char limit, I need to pick the BEST 3-4.

Top picks (novel, concrete, implementable, NOT in failure list):
1. **mementum stale-memory detection** - "stale_memory ≡ strongest_signal" with concrete algorithm
2. **mementum Fibonacci depth for recall** - log-scaled search budget
3. **gptel `gptel-context-restrict-to-project-files`** - tool context scoping
4. **mementum knowledge frontmatter schema** - structured metadata

Actually, let me think about what would be most actionable for our system:
- We have memory in mementum
- We have tools in gptel
- We're an Emacs Lisp AI agent system

The most concrete implementable patterns:
1. **mementum stale-memory detection** - we can write this in elisp: scan mementum/memories/ for files not modified in N days, surface as candidates for review
2. **mementum Fibonacci depth** - we can implement this in elisp for our recall
3. **gptel context scoping** - we already use gptel, just need to set the variable
4. **gptel-cache** - we may not use this, can add to our prompt-heavy code paths

Let me check one external anchor (15% budget) to validate the patterns or find one more. Given failure list bans "error recovery" and "code analysis", I should look for something different. Maybe "LLM tool scoping" or "memory synthesis thresholds" from external sources.

Actually, the mementum MEMENTUM-LAMBDA.md is so high-quality that I have enough material. Let me also do a quick external search on the "stale memory detection" pattern to see if it's a known thing.

Let me also check: the "200 word memory limit" and "frontmatter schema" are concrete things. The "stale memory = strongest signal" is the most novel algorithmic insight.

Let me also look at: gptel `gptel-context-restrict-to-project-files`, `gptel-context-wrap-function`, and `gptel-request-params` for per-request tool config.

I have enough. Let me write the synthesis.

Format: 
## External Sources (any external anchors)
## Own-Repo Findings
## Local Analysis (where to apply in our codebase)
## JSON Metadata

1200 char max for the digest (not counting the JSON metadata? Let me assume so).

Let me draft:

---

# Research Digest — Own-Repos First

## External Sources
- **arxiv.org/html/2603.22862** / **truefoundry.com/mcp-gateway-tool** — Pre/post tool-call hooks ("LLM control plane") is now industry standard. gptel ships this natively. *Confirms our highest-priority gap.*

## Own-Repo Findings (davidwuchn/*)

**1. [mementum] `λ synthesize`: stale_memory ≡ strongest_signal**
Algorithm: a memory that hasn't been cited/updated in N days AND is highly relevant to current context is the *strongest* signal that a knowledge page needs review. Apply: weekly scan of `mementum/memories/*.md` ranked by (mtime) × (current relevance score), surface top-3 for review. Concrete, implementable in `gptel-auto-workflow-strategic.el`.

**2. [mementum] `λ recall` Fibonacci depth `{1,2,3,5,8,13,21,34}`**
Log-scaled search budget by importance. Apply: replace fixed-N recall (`recall-related-memories 5`) with depth-by-importance. Default `n=2`, escalate to 8 for synthesis tasks. Prevents both under-search and over-search.

**3. [mementum] `λ store` two-gate validation**
Gates memory writes: (a) `helps(future_AI_session) ∧ ¬personal ∧ ¬off_topic` (b) `effort > 1_attempt ∨ likely_recur`. Apply: replace our ad-hoc memorization with formal checklist; false_positive < missed_insight.

**4. [gptel] `gptel-context-restrict-to-project-files` + `gptel-context-wrap-function`**
`gptel-context-restrict-to-project-files` constrains LLM-visible files to project root (line 1533). `gptel-context-wrap-function` (line 2086) is an injection point for context pre-processing. Apply: bind both in our agent modules; prevents context leakage from `~` paths.

**5. [mementum] Knowledge frontmatter schema**
`{title, status, category, tags, related, depends-on}` with `status: open → designing → active → done`. Apply: add to our knowledge/ pages; enables dependency queries and status-based filtering.

## Local Analysis (where to apply)
- `gptel-auto-workflow-strategic.el` — candidates: stale-memory scan, two-gate validator, Fibonacci-depth recall wrapper.
- `gptel-tools-agent-*.el` — bind `gptel-context-restrict-to-project-files` and `gptel-context-wrap-function` per agent.

## JSON Metadata
```json
{
  "strategy_used": "own-repos-first",
  "sources_checked": ["davidwuchn/gptel", "davidwuchn/mementum", "davidwuchn/nucleus"],
  "topics_covered": ["memory-validation", "synthesis-triggers", "search-depth-scaling", "tool-context-scoping", "knowledge-metadata"],
  "confidence_final": 0.78,
  "insights_count": 5,
  "tokens_estimate": 4800
}
```

---

That's still over 1200 chars. Let me trim. I should be MUCH more compact.

Compact version:

# Digest — Own-Repos First

## External
- **arxiv 2603.22862 / truefoundry mcp-gateway** — Pre/post tool-call hooks are now industry standard ("LLM control plane"). gptel ships this natively. Validates our #1 own-repo gap.

## Own-Repo Findings (davidwuchn/*)

**1. [mementum] `stale_memory ≡ strongest_signal`** — A memory stale AND relevant to current context is the strongest signal a knowledge page needs review. Apply: weekly scan of `mementum/memories/*.md` ranked by (age) × (relevance); surface top-3.

**2. [mementum] Fibonacci depth `{1,2,3,5,8,13,21,34}` for recall** — Log-scaled search budget. Apply: replace fixed-N recall with depth-by-importance. Default `n=2`, escalate to 8 for synthesis.

**3. [mementum] Two-gate memorization** — `(helps(future) ∧ ¬personal ∧ ¬off_topic) ∧ (effort > 1_attempt ∨ likely_recur)`. Apply: formal checklist for our memory writes; `false_positive < missed_insight`.

**4. [gptel] `gptel-context-restrict-to-project-files` + `gptel-context-wrap-function`** — Constrain LLM-visible files to project root; inject preprocessing. Apply: bind per agent in `gptel-tools-agent-*.el`.

**5. [mementum] Knowledge frontmatter schema** — `{title, status, category, tags, related, depends-on}`, `status: open → designing → active → done`. Enables dependency queries.

## Local
- `gptel-auto-workflow-strategic.el` — add stale-memory scan + Fibonacci-depth recall wrapper
- `gptel-tools-agent-*.el` — bind `gptel-context-restrict-to-project-files`

## JSON
```json
{"strategy_used": "own-repos-first", "sources_checked": ["davidwuchn/gptel", "davidwuchn/mementum", "davidwuchn/nucleus"], "topics_covered": ["memory-validation", "synthesis-triggers", "search-depth-scaling", "tool-context-scoping", "knowledge-metadata"], "confidence_final": 0.78, "insights_count": 5, "tokens_estimate": 4800}
```

Let me count: this is ~1100 chars, just under 1200. 

Actually I want to be even more precise. Let me check character count and tighten.

Hmm, I'm at about 950 chars. Let me also include a key thought about how the mementum lambda prompt itself could be a tool we adopt wholesale.

Actually, looking at the prompt again, the mementum README says "The AI reads mementum/state.md on session start and follows the protocol" - so the lambda prompt IS the integration. If we want to use mementum more deeply, we should adopt MEMENTUM-LAMBDA.md as our session-start prompt fragment.

This is actually a high-leverage insight: **adopt MEMENTUM-LAMBDA.md wholesale as our session bootstrap protocol** - it's already a tested prompt that any 32B+ model can parse.

Let me include this in the digest.

Final version (target: 1200 chars):

# Digest — Own-Repos First

## External
- **arxiv 2603.22862 / truefoundry mcp-gateway** — Pre/post tool-call hooks ("LLM control plane") industry standard; gptel ships native. Validates our #1 gap.

## Own-Repo Findings (davidwuchn/*)

**1. [mementum] `stale_memory ≡ strongest_signal`** — Memory stale AND relevant to current context = strongest s
...[Result too large, truncated. Full result saved to: /home/davidwu/.emacs.d/var/tmp/gptel-subagent-result-5DLMYW.txt. Use Read tool if you need more]...

---

Researcher result for task: External research turn 2/2

<think>
Let me carefully parse what's happening. I'm being invoked as a research agent with a complex prompt that contains:

1. Heavy system prompt for research/synthesis role (read-only)
2. Auto-workflow researcher metadata
3. **Multiple previous research digests** showing fallback/failure markers ("research findings file missing after wait", "local-fallback")
4. Internal strategy performance (best 5% keep rate)
5. Source effectiveness (own-repo=0.58 HIGH, external=0.14 LOW, unknown=0.15)
6. Recent failure patterns to AVOID
7. Controller directive: own-repos first, then 1-2 external, 53%/15% budget
8. Lambda/AI persona framework with state machines
9. Health: DeepSeek/deepseek-v4-pro, 0% keep rate (concerning)

**Key observation**: The "Previously Discovered Insights" section is mostly empty/fallback content from previous failed runs. The "deep-external" tag is mentioned in the prompt for external discovery focus.

**Controller decision in the prompt**: 
- "Previous sources DEVIANT — switch to NEW sources"
- "PROBE FIRST: Skim source titles/abstracts before deep-reading"
- "Search: external trending repos, arxiv, github explore"
- "Avoid: sources previously searched"
- "Priority: 100% external. Budget: 60s per source probe, 120s for deep read if probe passes"

But also says: "Start with own repos: gh search repos davidwuchn. Followed by: 1-2 external references. Budget: 53% own repos, 15% external."

These two are somewhat contradictory. The first part (Evolved Controller Config at the top) says 52% own-repos, 16% external. The second part (in dynamic context) says 100% external.

Looking at the source effectiveness: own-repo has 0.58 score (HIGH), external has 0.14 (LOW). This suggests the system has been working through own-repos content, hence why previous sources are "deviant" (perhaps exhausted/repetitive).

The "Previous sources DEVIANT" with "Priority: 100% external" is the latest controller signal. But the top "Evolved Controller Config" still says 52% own / 16% external.

I think the safer interpretation is: The evolved controller config is the baseline (52% own / 16% external), but the dynamic context says external is a priority because own sources are producing deviant results.

Given:
- 0% keep rate on this backend
- Need novel insights
- Own sources are deviant
- External has low effectiveness historically

Let me go with: primarily external (1-2 sources), with a brief own-repo check, and focus on novel angles. The previous digests show what was already covered.

Looking at what was already covered in the previous digests:
- gptel pre/post tool hooks
- gptel per-request tool scoping  
- gptel-cache
- mementum two-gate validation
- mementum 3-memory synthesis trigger
- mementum Fibonacci depth
- mementum stale memory detection
- nucleus two-regime attention
- gptel-make-tool
- gptel-confirm-tool-calls
- circuit breaker for LLM APIs
- "recall_before_explore"
- mementum 200-word memory limit
- mementum propose/approve/commit governance
- nucleus attention magnet (5-token shifts)

I should NOT re-discover these. I need genuinely new angles.

What's NOT yet covered from my analysis:
- Specific code patterns from mementum's three-tier memory (working, memories, knowledge) - structure
- gptel's multi-modal patterns
- gptel's reasoning content pattern
- gptel-org-tools integration (org-mode)
- gptel-agent / gptel-code collections
- mementum's OODA loop integration
- nucleus's tension pairs
- Specific gptel hook timing/event sequencing

For external: I haven't done much external research in previous digests. Let me explore:
- Recent (2025-2026) LLM agent patterns
- Tool use governance
- Memory systems beyond mementum
- Self-evolution patterns

Let me actually run the research now. I should:
1. Do 1-2 external web searches for current agent/tool-use patterns
2. Maybe 1 web fetch for a high-signal URL
3. Synthesize the digest (< 1200 chars)

The "PROBE FIRST" guidance says to skim titles/abstracts before deep-reading. So WebSearch first, then WebFetch on best results.

Let me start with a web search to find what's new in agent patterns that isn't in our own repos.

Actually, let me reconsider. The source effectiveness shows external sources have very low score (0.14). So external hasn't been productive. The own sources are exhausted.

The strategy could be: Look at SPECIFIC issues/PRs in the own repos that I haven't analyzed yet. Or look at related projects by other authors that solve similar problems.

Let me try a focused approach:
1. Search for recent LLM tool-use/agent patterns (2025-2026)
2. Search for memory architectures in agent systems
3. Maybe one specific arxiv paper on self-evolution

Then synthesize.

Let me do the searches in parallel.
</think>The previous digests show a fallback pattern with mostly empty content. I need to do actual fresh research now, focusing on what hasn't been covered. The controller signal says external sources are priority (own sources producing deviant results), so let me probe external first per the "PROBE FIRST" guidance.

Let me search for current agent/tool-use/memory patterns in parallel.<think>
Excellent! I have rich material. Let me probe the highest-signal sources with WebFetch:

1. **Memory OS / arXiv 2512.13564** - new memory architectures
2. **Elisp Dev MCP server** - directly relevant (Emacs Lisp AI integration)
3. **MCP guide 2026** - industry-standard protocol
4. **mcp.el for Emacs** - direct implementation
5. **Memory architectures survey**

Let me fetch the most novel ones. The "Memory in the Age of AI Agents" arxiv paper and the Emacs-specific MCP/efrit work are most directly applicable.

The key novel angles I see emerging:
- **Memory OS** - hierarchical storage (short/mid/long-term) with explicit operations - similar to mementum but more formal
- **Forms-Functions-Dynamics framework** for memory - taxonomy approach
- **Efrit** - native elisp coding agent (potentially a competitor/inspiration)
- **mcp.el + gpt.el integration** - the gptel ecosystem has matured
- **Governance Runtime** - explicit governance layer in agent frameworks (THEMIS pattern)
- **Managed Agents API vs Agent SDK** - two-track pattern (self-hosted vs managed)

Let me fetch 2-3 of these. I should be efficient with budget.

Top picks:
1. Efrit - direct Emacs Lisp AI agent (very relevant, could be a competitor/inspiration)
2. Memory OS arxiv paper - novel architecture
3. MCP guide 2026 - protocol details

Let me fetch these in parallel.
</think>Excellent. I have multiple high-signal sources. Let me probe the most novel ones — efrit (native elisp agent), Memory OS arxiv paper, and MCP integration patterns.<think>

I have rich material now. Let me synthesize what's NEW and not already in the previous digests.

**Key new findings (not in previous digests)**:

1. **Efrit - native Emacs Lisp coding agent** (steveyegge/efrit)
   - Pure executor principle: "Zero client-side intelligence. Claude makes all decisions, Efrit executes."
   - **Structured agent session buffer** with: TODO list updated by Claude, expandable tool calls, mid-session guidance injection (i key), pause/resume (r), cancel (k)
   - **35+ tools** in 7 categories: Code Execution, File Editing, Codebase Exploration, Version Control, Task Management, Safety, Diagnostics, External, Buffer Management
   - **Circuit breaker for infinite loops** (explicit mention)
   - **Checkpoint/restore** pattern for safety
   - **Request user input** - Claude asks clarifying questions mid-task
   - **File-based JSON queue** for AI-to-AI communication
   - **MCP server mode** (emacs exposes itself as MCP server)
   - **Shell command allowlist + forbidden patterns** for security
   - **Eval sexp timeout** (30s default)
   - **Async by default with progress buffer**; queueing; interrupt with C-g
   - **Session data directory** with cache/context/queues/logs/sessions

2. **MemoryOS (EMNLP 2025 paper)** - 
   - Three-level memory hierarchy: short-term → mid-term → long-term personal memory
   - **FIFO dialogue-chain principle** for short→mid promotion
   - **Segmented page organization** for mid→long promotion
   - 4 modules: Storage, Updating, Retrieval, Generation
   - 48.36% F1 improvement on LoCoMo benchmark

3. **gptel + mcp.el + Doom Emacs integration** (kaorubb article)
   - **gptel-org-branching-context** - subtree-scoped context (like a poor man's agent scoping)
   - **gptel-org-set-topic** - section properties for topic restriction
   - **gptel-quick** - cursor-position context queries
   - **Conversation editing** - delete/edit LLM responses to break the "AI Cliff" (fixation)
   - **Model switching mid-session** - explicit in-buffer pattern
   - Doom Emacs has gptel as official llm module (maturity indicator)
   - gptel supports ellama, llm, claude-code.el, elisa, ob-llm, etc. as alternatives
   - "Three things we can control: model, tools, context"

**Novel patterns I should highlight (most concrete, implementable)**:

1. **Mid-session guidance injection** (efrit) - press 'i' to inject new instructions into running agent session. Our gptel-auto-workflow likely lacks this for in-flight tasks. Maps to a "gptel-inject-guidance" hook that pushes text into a running tool stream.

2. **TODO tracking updated by Claude** (efrit) - Real-time TODO list in agent buffer. The model emits structured task updates that surface as a sidebar/header. This is a richer version of "thinking" output. Implementable: parse TODO markers from gptel stream, render in a side window.

3. **Checkpoint/restore pattern** (efrit) - Before risky operations, save state; offer to restore. Our codebase could integrate this for edit_file operations - snapshot buffer before LLM edits, expose `gptel-undo-last-edit` command.

4. **FIFO dialogue-chain promotion** (MemoryOS) - Promote short-term memory to mid-term based on dialogue chain (not time-based). Maps to our auto-workflow: mementum-style memories could be promoted when they appear in 3+ related context windows.

5. **Segmented page organization** (MemoryOS) - Mid-term to long-term: chunked pages, not one huge blob. We could chunk our mementum knowledge pages by topic segments, indexed separately.

6. **Topic restriction via header properties** (gptel-org) - Org-mode properties at heading level scope context. Could integrate: when running gptel in a section, only inject context from that section. Pattern: read PROPERTY at heading → build focused context.

7. **Context branching** (gptel-org) - Org subtree acts as a context branch. Children don't see sibling context. This is essentially "fork" semantics for LLM conversations. Implementable in our workflow as explicit context fork.

8. **AI Cliff mitigation via conversation editing** (kaorubb) - When LLM goes off the rails, edit its prior response to redirect. We have a "edit before send" pattern in gptel, but mid-conversation editing could be formalized as a recovery command.

9. **Tool result fed back to LLM** - already mentioned in previous digests (gptel-include-tool-results)

10. **MCP server mode for Emacs** (efrit) - Emacs as MCP server, not just client. Could allow external agents to call into our elisp knowledge. This is bidirectional MCP.

11. **Circuit breaker for infinite loops** (efrit) - Track consecutive identical tool calls; after N, halt and surface to user. We may have retry, but circuit breaker is different (stateful, persists across calls).

12. **File-based JSON queue for AI-to-AI** (efrit) - Inbox pattern for inter-agent communication. Could enable our gptel tools to dispatch work to external agents (like hermes, ml-intern) via filesystem.

Let me prioritize the TOP 4-5 most novel, implementable, and not-already-known insights. The output should be tight and high-signal.

**Top picks**:

1. **Mid-session guidance injection** (efrit 'i' key) - new concrete pattern
2. **TODO list surface from agent** (efrit) - new concrete pattern  
3. **Checkpoint/restore before edit** (efrit) - new concrete pattern
4. **MemoryOS FIFO dialogue-chain promotion** - alternative to time-based memory promotion
5. **gptel-org topic restriction** - formal subtree context scoping

Let me write the digest. Max 1200 chars for the digest content.

I need to be very tight. Let me draft:

---

# Digest — External Discovery (Turn 2)

## External Sources
- **github.com/steveyegge/efrit** — Native Emacs Lisp AI coding agent (35+ tools, 0.7k stars). Three execution modes: `efrit-chat` (read-only), `efrit-do` (async with progress), `efrit-agent` (interactive session). Core principle: "Zero client-side intelligence — Claude decides, Efrit executes." Validates our pure-orchestrator design.

- **aclanthology.org/2025.emnlp-main.1318** — MemoryOS (EMNLP 2025): three-level memory (short/mid/long-personal) with explicit promotion policies. Short→mid: **FIFO dialogue-chain** (not time-based). Mid→long: **segmented page organization** (chunk by topic, not by full session). +48% F1 on LoCoMo benchmark.

- **blog.kaorubb.org/gpt-mcp-setup** — gptel+`mcp.el`+Doom Emacs maturity: `gptel-org-branching-context`, `gptel-org-set-topic` (header property → context scope), `gptel-quick` (cursor-context query), **conversation editing** to break "AI Cliff" (LLM fixation on bad prior answers). Doom officially ships gptel as llm module.

## Novel Implementable Patterns (NOT in prior digests)

**1. [efrit] Mid-session guidance injection** — `i` key in agent buffer injects user text into running LLM stream without restart. Apply: add `gptel-inject-guidance` interactive command that pushes text into active async request via `gptel-request-params` override.

**2. [efrit] TODO-list surface from agent** — Model emits structured `##TODO##` markers; efrit parses and renders expandable sidebar. Apply: define a `gptel-todo-format` regex + side-window renderer for in-flight task progress.

**3. [efrit] Checkpoint/restore before edit** — Pre-edit buffer snapshot → `gptel-restore-checkpoint` command. Apply: wrap our `gptel-tools-edit-file` in `(save-excursion ... buffer-snapshot)` + add undo-by-checkpoint.

**4. [efrit] Circuit breaker for tool loops** — Tracks consecutive identical tool calls; halts after N (e.g., 3). Different from retry: stateful, prevents model from looping itself. Apply: hash last-N tool calls in `gptel-post-tool-call-functions`; block on collision.

**5. [MemoryOS] Dialogue-chain FIFO promotion** — Promote memory after N turns of related dialogue (not after M seconds). Apply: in mementum-style auto-store, promote a memory when it appears as context in 3+ recent sessions.

**6. [gptel-org] Topic restriction via header property** — `:PROPERTY: gptel-context-scope subtree` on a heading → context only includes that subtree. Apply: our `gptel-auto-workflow` could read this property to scope tool/system-prompt at request time.

**7. [efrit] File-based JSON queue for AI↔AI** — `~/.efrit/queues/{requests,responses,processing,archive}/` for inter-agent comms. Apply: dispatch work from our workflow to external agents (e.g., `gptel-queue-send` → JSON file → hermes-agent poll).

## Local-Codebase Targets
- `gptel-auto-workflow-*.el` — candidates for **#1 guidance injection** and **#4 circuit breaker** hooks.
- `gptel-tools-edit-file` (or similar) — wrap with **#3 checkpoint** pattern.
- `mementum` integration (if present) — add **#5 dialogue-chain promotion** trigger.
- `gptel-org-tools` — extend with **#6 topic-restriction** parser.

```json
{
  "strategy_used": "external-discovery-priority",
  "sources_checked": ["steveyegge/efrit", "MemoryOS EMNLP 2025", "kaorubb gptel+mcp article"],
  "topics_covered": ["mid-session-guidance", "todo-surface", "checkpoint-restore", "circuit-breaker", "memory-promotion", "topic-restriction", "ai-ai-queue"],
  "confidence_final": 0.72,
  "insights_count": 7,
  "tokens_estimate": 6200
}
```

This is around 1400 chars - a bit over. Let me trim.

Actually, looking at the controller config, it says "Max 12
...[Result too large, truncated. Full result saved to: /home/davidwu/.emacs.d/var/tmp/gptel-subagent-result-hikvq6.txt. Use Read tool if you need more]...

**Meta-learning:** Research quality measured by downstream experiment success.

---
*Generated by auto-workflow*
