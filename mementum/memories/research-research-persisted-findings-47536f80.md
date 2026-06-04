# Research: 2026-06-04 16:00

**Strategy:** persisted-findings
**Findings hash:** 47536f808526658d138e5b8bb49edd29ff4b94e0
**Targets:** lisp/modules/gptel-auto-workflow-ontology-router.el, staging-review
**Outcome:** 0/10 kept (0%)

**Raw Findings:**

> Project: /home/davidwu/.emacs.d/
> Updated: 2026-06-04 15:07

## Local Codebase Analysis (fallback — external research unavailable)

> Auto-generated from local git history, experiment results, and codebase scan.

## Git Activity (last 30 commits to lisp/modules/)

- **12** bug fixes
- **0** feature/evolution commits
- Focus: stabilization

## Module Complexity (top 5 by lines)

```
73053 total
   6812 lisp/modules/gptel-auto-workflow-evolution.el
   3875 lisp/modules/gptel-auto-workflow-ontology-router.el
   3780 lisp/modules/gptel-tools-agent-prompt-build.el
   2888 lisp/modules/gptel-auto-workflow-strategic.el
```

**Self-Evolution Directive:** Focus on the highest-failure modules above. Apply nil-safety patterns and validation guards to reduce failure rates.

---

Researcher result for task: External research turn 2/2

<think>
The user has provided a very complex, multi-layered prompt. Let me parse what's actually being asked:

1. **System/Role**: I'm a research and synthesis agent. Read-only. Gather info from local codebases AND external sources.

2. **The main task**: External research specialist for an Emacs-based AI agent system. Hunt internet for novel ideas.

3. **Current state context**:
   - 870 total experiments
   - Research effectiveness: 15.9%
   - Best strategy: 6.0% keep rate
   - Own repo priority: 53%, external: 15%
   - Beta: 0.06 (conservative)
   - Token budget: 4503
   - Stop threshold: 66% confidence
   - EMA confidence currently 0.34 (below threshold)

4. **Priority repos to monitor**:
   - davidwuchn/nucleus — VSM, lambda, Wu Xing
   - davidwuchn/mementum — Git-based AI memory
   - davidwuchn/gptel — LLM backend integration

5. **Sources to check**:
   - YouTube, X/Twitter, GitHub trending, arXiv, HuggingFace, Reddit

6. **Anti-patterns**: Generic advice, ideas already in codebase, theoretical without implementation path, heavy external dependencies

7. **Output format**:
   - Max 1200 chars
   - JSON metadata at end
   - ## headers
   - Bullet points for techniques
   - Inline code for examples

8. **Special instruction**: "Minimal Pair Probes" — For each bug/pattern, produce TWO competing hypotheses that differ in exactly ONE aspect. Label them HA and HB. Prefix each with `[pair-probe]`.

9. **Dynamic context**: Previously discovered insights (Reflexion, DSPy, Aider's repo map, etc.)

10. **The truncated prior turn** shows a massive research dump about Hermes Agent, subagent delegation, Skills System.

11. **The current controller directive** says:
    - Previous sources DEVIANT — switch to NEW sources
    - PROBE FIRST: Skim titles/abstracts before deep-reading
    - Search external trending repos, arxiv, github explore
    - Avoid previously searched sources
    - Priority: 100% external
    - Budget: 60s per source probe, 120s for deep read
    - λ engage(nucleus)

12. **Current state at end**:
    - HEALTHY (level 0, 14 experiments, 0% keep-rate)
    - Local fallback was used previously
    - Multiple previous turns were "local-fallback: research findings file missing after wait"
    - EMA confidence: 0.03 (delta: 0.00)
    - "Previous findings show promise but need more depth"

So the question is: what should I actually DO?

Looking at the system message structure, this is asking me to do a real research turn. The controller has:
- Told me to switch to NEW external sources (previous ones deviant)
- Probe first (skim titles)
- Avoid previously searched sources
- 100% external priority

I should:
1. Pick a few specific external sources that haven't been searched before
2. WebSearch to find new candidates
3. WebFetch promising ones (max 3 fetches per the instructions)
4. Return a 1200-char digest with JSON metadata
5. Apply [pair-probe] labeling

What HAS been searched already (from the prior turn truncated output):
- davidwuchn/* repos (via commit page attempt, but got auth wall; nucleus Atom feed worked)
- hermes-agent.nousresearch.com (deep-read)
- gptel, claude-code.el, aider, anthropic, magent, dspy, arxiv.org, memgpt, mem0, a-mem, mast, gptel-context-branching, mevedel

So I need NEW sources. Some ideas for fresh angles:
- **zeroclaw project** (mentioned in failure patterns) — I haven't researched this
- **ml-intern project** (mentioned in failure patterns) — I haven't researched this
- **Aider's recent work** (repomap was found, but new features)
- **Claude Code / Anthropic SDK patterns** 
- **DSPy optimization** newer work
- **GitHub Copilot Workspace** patterns
- **OpenHands/Cursor recent developments**
- **Cline/Roo-Cline patterns**
- **AutoCodeRover, SWE-Agent** (software engineering agents)
- **arXiv papers on tool use, agent loops**

Let me focus on:
1. **zeroclaw** - failure pattern mentions this
2. **SWE-Agent / AutoCodeRover** - software engineering agents
3. **arXiv recent agent papers**

Also, the directives mention "minimal pair probes" — for each finding, give HA and HB hypotheses. Let me apply this to the Hermes Skills System finding from the prior turn (which is the most novel insight so far).

Wait, let me re-read the system prompt header. The system says:
- "Read-only: never write files or make repository changes."
- "Synthesis over dumps."
- "If the prompt already includes the source material, synthesize directly."
- "Max 1200 chars. Prioritize depth over breadth."

And the previous turn's output is being shown to me as if I generated it (truncated). The "Result too large, truncated" line at the bottom suggests the prior research output exceeded the buffer.

So I think the right thing to do is:
1. **Don't repeat the prior turn's massive dump** (which already covered Hermes Agent Skills, subagent delegation, etc.)
2. **Probe NEW external sources** as the controller directed
3. **Apply [pair-probe] labeling** to the new findings
4. **Stay within 1200 char budget**
5. **Include JSON metadata**

Let me do this:

1. WebSearch for "zeroclaw agent framework" (new source per failure pattern)
2. WebSearch for "SWE-Agent arxiv 2025" or similar
3. WebSearch for "ml-intern ML coding assistant"

In parallel, then deep-read 1-2 of the most promising.

Then synthesize into a tight 1200 char digest with [pair-probe] labels and JSON metadata.

Let me start.
</think>I'll honor the controller's directive: **probe new external sources** (the prior turn was deviant), apply **[pair-probe]** labeling, stay within the 1200-char budget. Failure patterns point to *zeroclaw*, *ml-intern*, and software-engineering-agent literature. Let me run targeted probes in parallel.<think>
I have three solid probe targets. Let me identify the most novel/least-captured:

1. **ZeroClaw** (Rust-based, <5MB RAM, trait-driven, $10 hardware) — completely new, addresses lightweight local agent design
2. **SWE-agent / AutoCodeRover** (NeurIPS 2024) — has the ACI (agent-computer interface) concept, the prior turn found "ACI" via Anthropic's article, but this is the primary source
3. **ml-intern** (HuggingFace) — ML engineer agent that "researches, writes, ships" — relevant to the ML-intern failure pattern

The most novel/unsearched: **ZeroClaw** (architecture: trait-driven, <5MB RAM) and **ml-intern** (workflow: research→write→ship). SWE-agent has the ACI concept that overlaps with prior Anthropic finding, but the NeurIPS paper version may have NEW specifics (custom file viewer, scroll-based navigation).

Per directive: "PROBE FIRST: Skim source titles/abstracts before deep-reading. Search: external trending repos, arxiv, github explore. Avoid: sources previously searched (they produced deviant results). Priority: 100% external. Budget: 60s per source probe, 120s for deep read if probe passes."

Let me do one parallel batch of deeper reads on the TWO most novel: zeroclaw (GitHub) and ml-intern (PyPI/GitHub). The SWE-agent ACI is a slight overlap with prior, so I'll skip deep-read on it.

Actually, I have budget. Let me probe all three. But I should focus on the unique insights. Let me deep-read zeroclaw (the GitHub README, which should have architecture) and ml-intern (the GitHub README). SWE-agent ACI is the prior-turn overlap, so I'll skip.

Wait, the system prompt says "max 3 fetches" total. I've already done 3 web searches. The "max 3 fetches" likely refers to WebFetch calls. Let me budget: 2 fetches (zeroclaw + ml-intern).

Let me run these in parallel.

</think>Good probe results. The most novel and least-captured sources: **ZeroClaw** (Rust, <5MB RAM, trait-driven — addresses our lightweight local-agent design gap) and **ml-intern** (HF's ML engineer with research→write→ship workflow). SWE-agent ACI overlaps with prior turn's Anthropic finding — skipping its deep-read.<think>

Excellent. Two rich fetches. Let me extract the most novel, high-leverage patterns that we haven't captured:

## From ZeroClaw (Rust, 2026)
1. **Trait-driven architecture** — `Peripheral` trait, provider trait, channel trait, tool trait — extensible via Rust trait system
2. **SOP engine** — event-triggered Standard Operating Procedures (MQTT/webhook/cron/peripheral) with approval gates and resumable runs
3. **Cryptographic tool receipts on every action** — auditable action log
4. **Workspace boundaries + OS-level sandboxes** (Landlock/Bubblewrap/Seatbelt/Docker) — defense in depth
5. **Fallback chains for providers** — graceful degradation across LLM providers
6. **ACP — Agent Client Protocol** — JSON-RPC 2.0 over stdio for IDE integration (this is a standard, like LSP for agents)
7. **Single TOML config** with type.alias paths (e.g., `providers.models.openai.coding`)
8. **Runtime on $10 hardware, <5MB RAM** — the trait-driven minimal-kernel approach

## From ml-intern (HuggingFace, 2026)
1. **Doom Loop Detector** — detects repeated tool patterns and injects corrective prompts (HUGE — directly addresses our timeout/retry failure pattern!)
2. **Auto-compaction at 170k tokens** — context window management
3. **Approval gate before sensitive ops** — jobs, sandbox, destructive ops
4. **Event queue architecture** — separation of submission_loop and event_queue, 16+ event types
5. **Sandbox tool runtime** — opt-in via `--sandbox-tools` to use HF Space sandboxes (GPU) vs local
6. **Trace upload** — auto-upload to private HF dataset, Claude Code JSONL format
7. **ToolRouter** with 6 categories (HF docs/repos/datasets/jobs/papers, GitHub, Sandbox, Planning, MCP)
8. **Submission queue + Event queue** — clean async architecture (vs fire-and-forget)

The MOST novel + directly applicable to our system:

**1. Doom Loop Detector** (ml-intern) — directly maps to our failure pattern "10 validation/timeout errors in last 10 commits." A detector that recognizes repeated tool-call patterns and injects corrective prompts. This is exactly the missing piece in our recovery system.

**2. SOP engine + approval gates** (ZeroClaw) — event-triggered standard operating procedures with approval gates and resumable runs. Maps to our auto-workflow state machines, but with the resume/cancel semantics we don't have.

**3. ACP — Agent Client Protocol** (ZeroClaw) — JSON-RPC 2.0 over stdio for editor integration. This is a STANDARD for agent-editor communication, similar to LSP. We could expose our gptel agents via ACP.

**4. Fallback chains for providers** (ZeroClaw) — graceful degradation across LLM providers. We have multiple providers but no automatic fallback chain.

**5. Auto-compaction at threshold** (ml-intern) — context window management. Our auto-workflow has long histories.

**6. Cryptographic tool receipts** (ZeroClaw) — auditable action log per experiment.

Now I need to apply the **[pair-probe]** format — TWO competing hypotheses that differ in exactly ONE aspect.

For each finding, I'll generate HA and HB. The ONE aspect that varies should be the implementation choice: position of guard, error handler style, default value, etc.

## [pair-probe] Doom Loop Detection — GUARD POSITION

**HA**: Add doom-loop detection **inline in the LLM response parser** in `gptel-auto-workflow-strategic.el` — check the last 5 tool calls for repeated patterns and inject corrective prompt before next LLM call.
**HB**: Add doom-loop detection **in a separate `gptel-auto-workflow-recovery.el` middleware** that wraps the LLM call and post-processes the response, logging the recovery event to mementum.

**Differs in**: where the guard sits (inline parser vs. middleware wrapper). HA is faster/simpler; HB is decoupled/loggable.

## [pair-probe] SOP Engine — RESUMABLE RUNS

**HA**: Make our auto-workflow state machines **resumable by persisting the state chart position + last event** to mementum after each transition; on crash, restart from last persisted position.
**HB**: Make our auto-workflow state machines **resumable via a sidecar journal file** (JSONL append-only) that records every transition; on crash, replay the journal.

**Differs in**: persistence substrate (mementum/git vs. local JSONL). HA reuses our memory infra; HB is faster/simpler/no network.

## [pair-probe] Provider Fallback — RETRY POLICY

**HA**: Add provider fallback as a **synchronous retry chain** in `gptel-request.el` — if provider A fails, immediately try provider B with the same request; only escalate after both fail.
**HB**: Add provider fallback as a **deferred retry with circuit breaker** — track per-provider failure rate; if A fails 3/5 times, mark A as "open" for 5 minutes, route all traffic to B until A recovers.

**Differs in**: retry timing (immediate vs. circuit-broken). HA is simpler; HB prevents cascading failures.

OK, I have 3 pair-probes. The 1200 char budget is tight. Let me count my structure.

Format:
- ## External Sources (with each source URL + technique)
- ## [pair-probe] findings (3 of them)
- JSON metadata

Let me also add a tiny bit of local-codebase analysis if possible. The system prompt says "Read-only: never write files or make repository changes" and "Lead with the answer." Given the controller is also enforcing "100% external", I should NOT spend tokens on local scanning.

Let me draft tight 1200 chars.

Hmm, 1200 chars is REALLY tight. Let me count what I need:

```
## External Sources
- **[ZeroClaw](url)** — 1-line
- **[ml-intern](url)** — 1-line

## Pair-Probe Findings
### [pair-probe] Doom Loop Detection
- **HA**: 1-line
- **HB**: 1-line

### [pair-probe] SOP Resumable Runs
- **HA**: 1-line
- **HB**: 1-line

### [pair-probe] Provider Fallback
- **HA**: 1-line
- **HB**: 1-line

## JSON
{...}
```

Each line ~80 chars. 11 lines = ~880 chars. Plus headers and inline code... I should be OK. Let me be tight.

Actually wait — the prior turn was 1200 char max and I have a lot of content. Let me be very surgical. I'll use 2 pair-probes (the most novel ones: doom loop + SOP) and skip the fallback chain (we likely already have some provider config).

Actually, the user prompt's prior turn was a "Result too large, truncated" — so I should be especially tight. Let me target ~1100 chars to be safe.

Let me write it.

One more thing: the system prompt says I should NOT repeat previously discovered insights. The "## External Sources" section should NOT re-list Hermes Skills (already captured). I should focus on what IS new: ZeroClaw + ml-intern.

The pair-probes should build on the prior turn's findings, not duplicate them. Doom loop detection is genuinely new (ml-intern's distinct pattern, not Hermes Skills). SOP is also new (ZeroClaw distinct, not Hermes).

OK, drafting now.
</parameter>

Drafting the 1200-char digest. I have 2 rich fetches with concrete, novel patterns. Let me apply [pair-probe] to the two highest-leverage findings (Doom Loop + SOP Resumability) and skip prior-turn overlap (Hermes Skills).

```markdown
## External Sources

- **[ZeroClaw](https://github.com/zeroclaw-labs/zeroclaw)** — Rust runtime, <5MB RAM, trait-driven kernel. Key: **SOP engine** (event-triggered standard-operating-procedures via MQTT/webhook/cron/peripheral with approval gates + **resumable runs**). Also: cryptographic tool receipts per action, ACP (JSON-RPC stdio for editor integration), provider **fallback chains**, OS-level sandbox (Landlock/Bubblewrap/Seatbelt/Docker).

- **[ml-intern](https://github.com/huggingface/ml-intern)** — HF's ML engineer agent. Key: **Doom Loop Detector** that watches repeated tool-call patterns and injects corrective prompts mid-loop. Also: **auto-compaction at 170k tokens**, approval gates (jobs/sandbox/destructive), event-queue + submission-queue separation, sandbox-vs-local tool runtime opt-in (`--sandbox-tools`).

## [pair-probe] Doom-Loop Detection (failure pattern: 10 validation/timeout errors)

- **HA**: Inline guard in `gptel-auto-workflow-strategic.el` LLM-response parser — hash last 5 `(tool . args)` pairs; if 3-of-5 repeat, inject "your last N attempts failed with X; try a different approach" b
...[Result too large, truncated. Full result saved to: /home/davidwu/.emacs.d/var/tmp/gptel-subagent-result-9SRiFa.txt. Use Read tool if you need more]...

**Digested Insights:**

> Project: /home/davidwu/.emacs.d/
> Updated: 2026-06-04 15:07

## Local Codebase Analysis (fallback — external research unavailable)

> Auto-generated from local git history, experiment results, and codebase scan.

## Git Activity (last 30 commits to lisp/modules/)

- **12** bug fixes
- **0** feature/evolution commits
- Focus: stabilization

## Module Complexity (top 5 by lines)

```
73053 total
   6812 lisp/modules/gptel-auto-workflow-evolution.el
   3875 lisp/modules/gptel-auto-workflow-ontology-router.el
   3780 lisp/modules/gptel-tools-agent-prompt-build.el
   2888 lisp/modules/gptel-auto-workflow-strategic.el
```

**Self-Evolution Directive:** Focus on the highest-failure modules above. Apply nil-safety patterns and validation guards to reduce failure rates.

---

Researcher result for task: External research turn 2/2

<think>
The user has provided a very complex, multi-layered prompt. Let me parse what's actually being asked:

1. **System/Role**: I'm a research and synthesis agent. Read-only. Gather info from local codebases AND external sources.

2. **The main task**: External research specialist for an Emacs-based AI agent system. Hunt internet for novel ideas.

3. **Current state context**:
   - 870 total experiments
   - Research effectiveness: 15.9%
   - Best strategy: 6.0% keep rate
   - Own repo priority: 53%, external: 15%
   - Beta: 0.06 (conservative)
   - Token budget: 4503
   - Stop threshold: 66% confidence
   - EMA confidence currently 0.34 (below threshold)

4. **Priority repos to monitor**:
   - davidwuchn/nucleus — VSM, lambda, Wu Xing
   - davidwuchn/mementum — Git-based AI memory
   - davidwuchn/gptel — LLM backend integration

5. **Sources to check**:
   - YouTube, X/Twitter, GitHub trending, arXiv, HuggingFace, Reddit

6. **Anti-patterns**: Generic advice, ideas already in codebase, theoretical without implementation path, heavy external dependencies

7. **Output format**:
   - Max 1200 chars
   - JSON metadata at end
   - ## headers
   - Bullet points for techniques
   - Inline code for examples

8. **Special instruction**: "Minimal Pair Probes" — For each bug/pattern, produce TWO competing hypotheses that differ in exactly ONE aspect. Label them HA and HB. Prefix each with `[pair-probe]`.

9. **Dynamic context**: Previously discovered insights (Reflexion, DSPy, Aider's repo map, etc.)

10. **The truncated prior turn** shows a massive research dump about Hermes Agent, subagent delegation, Skills System.

11. **The current controller directive** says:
    - Previous sources DEVIANT — switch to NEW sources
    - PROBE FIRST: Skim titles/abstracts before deep-reading
    - Search external trending repos, arxiv, github explore
    - Avoid previously searched sources
    - Priority: 100% external
    - Budget: 60s per source probe, 120s for deep read
    - λ engage(nucleus)

12. **Current state at end**:
    - HEALTHY (level 0, 14 experiments, 0% keep-rate)
    - Local fallback was used previously
    - Multiple previous turns were "local-fallback: research findings file missing after wait"
    - EMA confidence: 0.03 (delta: 0.00)
    - "Previous findings show promise but need more depth"

So the question is: what should I actually DO?

Looking at the system message structure, this is asking me to do a real research turn. The controller has:
- Told me to switch to NEW external sources (previous ones deviant)
- Probe first (skim titles)
- Avoid previously searched sources
- 100% external priority

I should:
1. Pick a few specific external sources that haven't been searched before
2. WebSearch to find new candidates
3. WebFetch promising ones (max 3 fetches per the instructions)
4. Return a 1200-char digest with JSON metadata
5. Apply [pair-probe] labeling

What HAS been searched already (from the prior turn truncated output):
- davidwuchn/* repos (via commit page attempt, but got auth wall; nucleus Atom feed worked)
- hermes-agent.nousresearch.com (deep-read)
- gptel, claude-code.el, aider, anthropic, magent, dspy, arxiv.org, memgpt, mem0, a-mem, mast, gptel-context-branching, mevedel

So I need NEW sources. Some ideas for fresh angles:
- **zeroclaw project** (mentioned in failure patterns) — I haven't researched this
- **ml-intern project** (mentioned in failure patterns) — I haven't researched this
- **Aider's recent work** (repomap was found, but new features)
- **Claude Code / Anthropic SDK patterns** 
- **DSPy optimization** newer work
- **GitHub Copilot Workspace** patterns
- **OpenHands/Cursor recent developments**
- **Cline/Roo-Cline patterns**
- **AutoCodeRover, SWE-Agent** (software engineering agents)
- **arXiv papers on tool use, agent loops**

Let me focus on:
1. **zeroclaw** - failure pattern mentions this
2. **SWE-Agent / AutoCodeRover** - software engineering agents
3. **arXiv recent agent papers**

Also, the directives mention "minimal pair probes" — for each finding, give HA and HB hypotheses. Let me apply this to the Hermes Skills System finding from the prior turn (which is the most novel insight so far).

Wait, let me re-read the system prompt header. The system says:
- "Read-only: never write files or make repository changes."
- "Synthesis over dumps."
- "If the prompt already includes the source material, synthesize directly."
- "Max 1200 chars. Prioritize depth over breadth."

And the previous turn's output is being shown to me as if I generated it (truncated). The "Result too large, truncated" line at the bottom suggests the prior research output exceeded the buffer.

So I think the right thing to do is:
1. **Don't repeat the prior turn's massive dump** (which already covered Hermes Agent Skills, subagent delegation, etc.)
2. **Probe NEW external sources** as the controller directed
3. **Apply [pair-probe] labeling** to the new findings
4. **Stay within 1200 char budget**
5. **Include JSON metadata**

Let me do this:

1. WebSearch for "zeroclaw agent framework" (new source per failure pattern)
2. WebSearch for "SWE-Agent arxiv 2025" or similar
3. WebSearch for "ml-intern ML coding assistant"

In parallel, then deep-read 1-2 of the most promising.

Then synthesize into a tight 1200 char digest with [pair-probe] labels and JSON metadata.

Let me start.
</think>I'll honor the controller's directive: **probe new external sources** (the prior turn was deviant), apply **[pair-probe]** labeling, stay within the 1200-char budget. Failure patterns point to *zeroclaw*, *ml-intern*, and software-engineering-agent literature. Let me run targeted probes in parallel.<think>
I have three solid probe targets. Let me identify the most novel/least-captured:

1. **ZeroClaw** (Rust-based, <5MB RAM, trait-driven, $10 hardware) — completely new, addresses lightweight local agent design
2. **SWE-agent / AutoCodeRover** (NeurIPS 2024) — has the ACI (agent-computer interface) concept, the prior turn found "ACI" via Anthropic's article, but this is the primary source
3. **ml-intern** (HuggingFace) — ML engineer agent that "researches, writes, ships" — relevant to the ML-intern failure pattern

The most novel/unsearched: **ZeroClaw** (architecture: trait-driven, <5MB RAM) and **ml-intern** (workflow: research→write→ship). SWE-agent has the ACI concept that overlaps with prior Anthropic finding, but the NeurIPS paper version may have NEW specifics (custom file viewer, scroll-based navigation).

Per directive: "PROBE FIRST: Skim source titles/abstracts before deep-reading. Search: external trending repos, arxiv, github explore. Avoid: sources previously searched (they produced deviant results). Priority: 100% external. Budget: 60s per source probe, 120s for deep read if probe passes."

Let me do one parallel batch of deeper reads on the TWO most novel: zeroclaw (GitHub) and ml-intern (PyPI/GitHub). The SWE-agent ACI is a slight overlap with prior, so I'll skip deep-read on it.

Actually, I have budget. Let me probe all three. But I should focus on the unique insights. Let me deep-read zeroclaw (the GitHub README, which should have architecture) and ml-intern (the GitHub README). SWE-agent ACI is the prior-turn overlap, so I'll skip.

Wait, the system prompt says "max 3 fetches" total. I've already done 3 web searches. The "max 3 fetches" likely refers to WebFetch calls. Let me budget: 2 fetches (zeroclaw + ml-intern).

Let me run these in parallel.

</think>Good probe results. The most novel and least-captured sources: **ZeroClaw** (Rust, <5MB RAM, trait-driven — addresses our lightweight local-agent design gap) and **ml-intern** (HF's ML engineer with research→write→ship workflow). SWE-agent ACI overlaps with prior turn's Anthropic finding — skipping its deep-read.<think>

Excellent. Two rich fetches. Let me extract the most novel, high-leverage patterns that we haven't captured:

## From ZeroClaw (Rust, 2026)
1. **Trait-driven architecture** — `Peripheral` trait, provider trait, channel trait, tool trait — extensible via Rust trait system
2. **SOP engine** — event-triggered Standard Operating Procedures (MQTT/webhook/cron/peripheral) with approval gates and resumable runs
3. **Cryptographic tool receipts on every action** — auditable action log
4. **Workspace boundaries + OS-level sandboxes** (Landlock/Bubblewrap/Seatbelt/Docker) — defense in depth
5. **Fallback chains for providers** — graceful degradation across LLM providers
6. **ACP — Agent Client Protocol** — JSON-RPC 2.0 over stdio for IDE integration (this is a standard, like LSP for agents)
7. **Single TOML config** with type.alias paths (e.g., `providers.models.openai.coding`)
8. **Runtime on $10 hardware, <5MB RAM** — the trait-driven minimal-kernel approach

## From ml-intern (HuggingFace, 2026)
1. **Doom Loop Detector** — detects repeated tool patterns and injects corrective prompts (HUGE — directly addresses our timeout/retry failure pattern!)
2. **Auto-compaction at 170k tokens** — context window management
3. **Approval gate before sensitive ops** — jobs, sandbox, destructive ops
4. **Event queue architecture** — separation of submission_loop and event_queue, 16+ event types
5. **Sandbox tool runtime** — opt-in via `--sandbox-tools` to use HF Space sandboxes (GPU) vs local
6. **Trace upload** — auto-upload to private HF dataset, Claude Code JSONL format
7. **ToolRouter** with 6 categories (HF docs/repos/datasets/jobs/papers, GitHub, Sandbox, Planning, MCP)
8. **Submission queue + Event queue** — clean async architecture (vs fire-and-forget)

The MOST novel + directly applicable to our system:

**1. Doom Loop Detector** (ml-intern) — directly maps to our failure pattern "10 validation/timeout errors in last 10 commits." A detector that recognizes repeated tool-call patterns and injects corrective prompts. This is exactly the missing piece in our recovery system.

**2. SOP engine + approval gates** (ZeroClaw) — event-triggered standard operating procedures with approval gates and resumable runs. Maps to our auto-workflow state machines, but with the resume/cancel semantics we don't have.

**3. ACP — Agent Client Protocol** (ZeroClaw) — JSON-RPC 2.0 over stdio for editor integration. This is a STANDARD for agent-editor communication, similar to LSP. We could expose our gptel agents via ACP.

**4. Fallback chains for providers** (ZeroClaw) — graceful degradation across LLM providers. We have multiple providers but no automatic fallback chain.

**5. Auto-compaction at threshold** (ml-intern) — context window management. Our auto-workflow has long histories.

**6. Cryptographic tool receipts** (ZeroClaw) — auditable action log per experiment.

Now I need to apply the **[pair-probe]** format — TWO competing hypotheses that differ in exactly ONE aspect.

For each finding, I'll generate HA and HB. The ONE aspect that varies should be the implementation choice: position of guard, error handler style, default value, etc.

## [pair-probe] Doom Loop Detection — GUARD POSITION

**HA**: Add doom-loop detection **inline in the LLM response parser** in `gptel-auto-workflow-strategic.el` — check the last 5 tool calls for repeated patterns and inject corrective prompt before next LLM call.
**HB**: Add doom-loop detection **in a separate `gptel-auto-workflow-recovery.el` middleware** that wraps the LLM call and post-processes the response, logging the recovery event to mementum.

**Differs in**: where the guard sits (inline parser vs. middleware wrapper). HA is faster/simpler; HB is decoupled/loggable.

## [pair-probe] SOP Engine — RESUMABLE RUNS

**HA**: Make our auto-workflow state machines **resumable by persisting the state chart position + last event** to mementum after each transition; on crash, restart from last persisted position.
**HB**: Make our auto-workflow state machines **resumable via a sidecar journal file** (JSONL append-only) that records every transition; on crash, replay the journal.

**Differs in**: persistence substrate (mementum/git vs. local JSONL). HA reuses our memory infra; HB is faster/simpler/no network.

## [pair-probe] Provider Fallback — RETRY POLICY

**HA**: Add provider fallback as a **synchronous retry chain** in `gptel-request.el` — if provider A fails, immediately try provider B with the same request; only escalate after both fail.
**HB**: Add provider fallback as a **deferred retry with circuit breaker** — track per-provider failure rate; if A fails 3/5 times, mark A as "open" for 5 minutes, route all traffic to B until A recovers.

**Differs in**: retry timing (immediate vs. circuit-broken). HA is simpler; HB prevents cascading failures.

OK, I have 3 pair-probes. The 1200 char budget is tight. Let me count my structure.

Format:
- ## External Sources (with each source URL + technique)
- ## [pair-probe] findings (3 of them)
- JSON metadata

Let me also add a tiny bit of local-codebase analysis if possible. The system prompt says "Read-only: never write files or make repository changes" and "Lead with the answer." Given the controller is also enforcing "100% external", I should NOT spend tokens on local scanning.

Let me draft tight 1200 chars.

Hmm, 1200 chars is REALLY tight. Let me count what I need:

```
## External Sources
- **[ZeroClaw](url)** — 1-line
- **[ml-intern](url)** — 1-line

## Pair-Probe Findings
### [pair-probe] Doom Loop Detection
- **HA**: 1-line
- **HB**: 1-line

### [pair-probe] SOP Resumable Runs
- **HA**: 1-line
- **HB**: 1-line

### [pair-probe] Provider Fallback
- **HA**: 1-line
- **HB**: 1-line

## JSON
{...}
```

Each line ~80 chars. 11 lines = ~880 chars. Plus headers and inline code... I should be OK. Let me be tight.

Actually wait — the prior turn was 1200 char max and I have a lot of content. Let me be very surgical. I'll use 2 pair-probes (the most novel ones: doom loop + SOP) and skip the fallback chain (we likely already have some provider config).

Actually, the user prompt's prior turn was a "Result too large, truncated" — so I should be especially tight. Let me target ~1100 chars to be safe.

Let me write it.

One more thing: the system prompt says I should NOT repeat previously discovered insights. The "## External Sources" section should NOT re-list Hermes Skills (already captured). I should focus on what IS new: ZeroClaw + ml-intern.

The pair-probes should build on the prior turn's findings, not duplicate them. Doom loop detection is genuinely new (ml-intern's distinct pattern, not Hermes Skills). SOP is also new (ZeroClaw distinct, not Hermes).

OK, drafting now.
</parameter>

Drafting the 1200-char digest. I have 2 rich fetches with concrete, novel patterns. Let me apply [pair-probe] to the two highest-leverage findings (Doom Loop + SOP Resumability) and skip prior-turn overlap (Hermes Skills).

```markdown
## External Sources

- **[ZeroClaw](https://github.com/zeroclaw-labs/zeroclaw)** — Rust runtime, <5MB RAM, trait-driven kernel. Key: **SOP engine** (event-triggered standard-operating-procedures via MQTT/webhook/cron/peripheral with approval gates + **resumable runs**). Also: cryptographic tool receipts per action, ACP (JSON-RPC stdio for editor integration), provider **fallback chains**, OS-level sandbox (Landlock/Bubblewrap/Seatbelt/Docker).

- **[ml-intern](https://github.com/huggingface/ml-intern)** — HF's ML engineer agent. Key: **Doom Loop Detector** that watches repeated tool-call patterns and injects corrective prompts mid-loop. Also: **auto-compaction at 170k tokens**, approval gates (jobs/sandbox/destructive), event-queue + submission-queue separation, sandbox-vs-local tool runtime opt-in (`--sandbox-tools`).

## [pair-probe] Doom-Loop Detection (failure pattern: 10 validation/timeout errors)

- **HA**: Inline guard in `gptel-auto-workflow-strategic.el` LLM-response parser — hash last 5 `(tool . args)` pairs; if 3-of-5 repeat, inject "your last N attempts failed with X; try a different approach" b
...[Result too large, truncated. Full result saved to: /home/davidwu/.emacs.d/var/tmp/gptel-subagent-result-9SRiFa.txt. Use Read tool if you need more]...

**Meta-learning:** Research quality measured by downstream experiment success.

---
*Generated by auto-workflow*
