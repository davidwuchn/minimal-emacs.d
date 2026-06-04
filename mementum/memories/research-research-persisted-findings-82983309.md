# Research: 2026-06-04 12:07

**Strategy:** persisted-findings
**Findings hash:** 829833092b0605b7bf04465880fe3ab6985e75e3
**Targets:** lisp/modules/gptel-tools-agent-runtime.el, staging-review
**Outcome:** 0/11 kept (0%)

**Raw Findings:**

> Project: /home/davidwu/.emacs.d/
> Updated: 2026-06-04 11:03

Researcher result for task: External research turn 1/2

<think>
Let me carefully parse this complex prompt. The system is feeding me a stateful, evolving research directive with multiple layers of context:

1. **Role**: External research specialist for Emacs AI agent system
2. **Current state**:
   - 870 total experiments
   - Research effectiveness: 15.9% (very low)
   - Best strategy: 6.0% keep rate
   - Source effectiveness: own-repo=0.54, external=0.14, unknown=0.15
   - Beta: 0.06 (very conservative)
   - Own repo priority: 53%, external: 15%
   - Stop threshold: 66% confidence
   - Token budget: 4503
   - Recent failure patterns include validation/timeout errors

3. **Controller directive**:
   - "Start with own repos: gh search repos davidwuchn"
   - "Followed by: 1-2 external references"
   - Budget: 53% own repos, 15% external
   - "λ engage(nucleus)"
   - Health: HEALTHY (level 0, 13 experiments, 0% keep-rate)

4. **Anti-patterns**: "Use AI better" is banned

5. **Output constraints**:
   - Max 1200 chars
   - JSON metadata at end
   - ## headers
   - Bullet points for techniques
   - Inline code for examples

6. **Banned patterns from previous research**: Generic advice, ideas already in codebase, theoretical without implementation path, heavy external dependencies

7. **Focus areas** (from failure patterns):
   - AI agent workflow architectures
   - Emacs Lisp AI integration patterns
   - LLM self-evolution and meta-learning
   - Code analysis automation
   - Prompt engineering for code generation
   - Error recovery and retry patterns
   - Benchmarking and evaluation
   - Git-based memory systems
   - hermes-agent, zeroclaw, ml-intern projects

Looking at the meta-context from previous research turn:
- Previous turn (now shown as truncated in the prompt) found:
  - **Reflexion** (verbal self-reflection) — gap confirmed: `gptel-recovery-record-experiment` records but doesn't reflect
  - **DSPy** (signatures, modules, optimizers)
  - **Aider's repo map** (graph-based codebase context)
  - **Anthropic Building Effective Agents** (5 workflow patterns + ACI)
  - **claude-code.el** (multi-instance buffer management)
  - gptel-context-branching
  - magent
  - MAST failure taxonomy
  - MemGPT/mem0/A-MEM

The current controller says "Start with own repos" - so I should check own repos for recent changes I haven't captured.

Wait - the prompt is showing me a continuation. The previous turn (shown truncated) found the **Reflexion** pattern as the highest-leverage gap. The controller has now given me a NEW directive: start with own repos, then 1-2 external.

The new directive is asking me to:
1. Check own repos (davidwuchn/*) for RECENT activity/changes
2. Then 1-2 external sources
3. Max 1200 chars output
4. JSON metadata at end
5. Be concrete and implementable in Emacs Lisp
6. Focus on gaps in our system

Given the system has ALREADY had the recovery/reflection insight, and the failure patterns highlight:
- Error recovery and retry patterns
- AI agent workflow architectures
- Code analysis automation
- hermes-agent, zeroclaw, ml-intern

I should:
1. Probe own repos for new commits since the last research cycle
2. Find one specific actionable insight that builds on Reflexion
3. Return tight 1200 char digest

Let me think about what specific things to look for:

1. **Check own repos** for changes since last research (nucleus, mementum, gptel)
2. **Look for SPECIFIC implementation patterns** - not generic advice
3. **Focus on the recovery gap** that the previous turn found

Let me do parallel web fetches to check recent activity on the own repos. The previous turn already did a thorough job on the major external sources, so I should:
1. Check own repos for recent changes
2. Find ONE specific new pattern (e.g., a newer arxiv paper, a specific Emacs package)
3. Make the connection to our specific modules

Let me start with parallel probes:

1. WebFetch davidwuchn/nucleus (recent activity)
2. WebFetch davidwuchn/mementum (recent activity)
3. WebFetch davidwuchn/gptel (recent activity)
4. WebSearch for the new failure patterns (hermes-agent, zeroclaw, ml-intern)

Actually, looking more carefully at the prompt - the "Previous turn" output is shown as if I did it, with truncated output. The current directive is asking me to do a NEW research turn.

Let me do this efficiently. The most important things:

1. The previous turn already identified the Reflexion gap. I should build on this.
2. The system has a recovery module that records failures but doesn't reflect.
3. I need to check own repos for new patterns, and find 1-2 external sources.

Let me check own repos for new activity in parallel with searching for the projects mentioned in failure patterns (hermes-agent, zeroclaw, ml-intern).

Actually, looking at the system prompt one more time, I see that the previous research turn was already done. The current state shows:

"## Sources Checked This Turn
- 1× gptel, claude-code.el, aider, anthropic, magent, dspy, arxiv.org, memgpt, mem0, a-mem, mast, gptel-context-branching, mevedel

## EMA confidence
- 0.34 (target: 0.65, delta: 0.00)"

So the EMA confidence is 0.34, below the 0.65 stop threshold. The controller is now asking me to CONTINUE with the new directive: 53% own repos, 15% external.

Wait, I see the prompt has been showing me the OUTPUT of previous research as if it were from a prior turn. Let me re-read the structure.

Looking at it again, the structure of this prompt is:
1. System prompt (role, phase checklist, output format)
2. Researcher prompt (with all the variables)
3. The big "..." section shows outputs from prior research turns (truncated)
4. Then the current turn's directives

The key question: is this the FIRST research turn, or am I being asked to do a CONTINUATION?

Given:
- The EMA confidence is 0.34 (below 0.65 threshold)
- The "Previous findings show promise but need more depth"
- "Start with own repos" directive
- Source directive shows: "Source type: own-repos-first"

This looks like the controller is now directing me to do an own-repos-first research turn, after the previous one failed (100% external was deviant).

So my task is:
1. Check davidwuchn/* repos first (53% budget)
2. Then 1-2 external (15% budget)
3. Max 1200 chars
4. JSON metadata
5. Be concrete for Emacs Lisp

Let me do this. I should:
1. Probe own repos in parallel
2. Check the local codebase for the actual state (since the previous research identified gaps)
3. Find concrete implementable patterns

Let me start with parallel web fetches and local greps.

Actually, looking at the system prompt and previous research output:
- The previous research (shown truncated) DID identify the Reflexion gap
- The controller's response was "Continue" with new directives
- This new turn is supposed to either:
  a) Build on the previous finding
  b) Find a new angle
  c) Verify the previous finding by checking the actual codebase

The directive says "Start with own repos" - so I should:
1. Check own repos (53% budget)
2. Then 1-2 external (15% budget)

Let me do this efficiently. I'll do parallel fetches:
- davidwuchn/gptel (main one for Emacs Lisp AI integration)
- davidwuchn/nucleus (for prompt patterns)
- davidwuchn/mementum (for memory patterns)

And one external probe for the new failure pattern topics.

Actually, I notice the failure pattern mentions "hermes-agent project: agent orchestration and delegation patterns" - this might be a specific repo to look at. Let me check what hermes-agent is.

Let me start.
</think>Switching to own-repos-first per the new directive. The previous turn (external-100pct) hit 0.34 EMA — below the 0.65 stop threshold. Now I need to find **concrete recent patterns from own repos** that we haven't captured. Failure patterns point to: error recovery/retry, agent workflow architectures, code analysis automation, plus the project names (hermes-agent, zeroclaw, ml-intern). Let me probe in parallel.<think>
GitHub's commit pages are returning the marketing site (likely an auth wall or the URL structure changed). But the WebSearch found something VERY interesting:

**Hermes Agent by Nous Research** — this is the project from the failure pattern list. Key insights from the search results:
- "The self-improving AI agent built by Nous Research. The only agent with a built-in learning loop — it creates skills from experience, improves them during use, nudges itself to persist knowledge, and builds a deepening model of who you are across sessions."
- "Hermes can spawn isolated child agents to work on tasks in parallel. Each subagent gets its own conversation, terminal session, and toolset. Only the final summary comes back — intermediate tool calls never enter your context window."

This is HUGE. Two key patterns:
1. **Self-improving learning loop** — creates skills from experience, improves them during use
2. **Subagent delegation with context isolation** — intermediate tool calls never enter parent's context

This is exactly the kind of thing the system needs! And it's from a project named in the failure patterns. Let me deep-read these.

Let me do a targeted fetch on the delegation-patterns page and the main Hermes Agent docs. This is high-value, novel (not searched in prior turn), and directly addresses two of the failure patterns:
- AI agent workflow architectures
- LLM self-evolution and meta-learning

Let me also try to fetch the own repos via a different URL pattern (e.g., the Atom feed for commits which doesn't require JS).
</think>The own repo commit pages are returning the marketing site (auth wall). But the WebSearch hit gold — **Hermes Agent by Nous Research**, which IS the project from the failure pattern list! Key hooks: "self-improving AI agent with a built-in learning loop — it creates skills from experience, improves them during use" and "isolated child agents... intermediate tool calls never enter your context window." Let me deep-read this AND try Atom feeds for own repos.<think>

I have rich material now. Let me synthesize:

**From own repo (nucleus Atom feed) — recent activity I HAVEN'T captured**:
- `c04e8001` 2026-05-10: Merge michaelwhitford/main into main
- `93c171ad` 2026-05-05: **❌ EBNF — add path primitive for directory arguments** (arg_list → `arg` accepts `expression | path`, new `path` and `path_segment` rules, fixes memories(mementum/memories/) parsing) — **HIGH RELEVANCE** to our mementum integration
- `147d33a2` 2026-03-29: `*-autoloads.el` gitignore
- `2668c598` 2026-03-27: **✅ allium compiler upgraded to v3** — Statechart syntax (transition graphs, when clauses, derived values, backtick enums, ordered collections, black box fn syntax) — directly relevant to our auto-workflow state machines
- `5efe2ba1` 2026-03-25: **✅ agents — backgammon game, VSM distill/drift cycle, fulcro VSM upgrade** — agents/distill-vsm, agents/distill-code-vsm, agents/drift-vsm, agents/drift-code-vsm — **PROCEDURAL MEMORY + VERIFICATION** patterns!
- `42718db8` 2026-03-24: **💡 document four new tension pairs** (signal/noise, order/entropy, truth/provability, self/other)
- `3eb97e32` 2026-03-24: **✅ agents/rps — first nucleus agent** — "AGENTS.md (executable prompt) + README.md (usage docs)" pattern
- And the VSM/Tiantai/Yin-Yang mapping work (probably already captured)

**From external (Hermes Agent by Nous Research) — novel & high-leverage**:

1. **Subagent delegation with context isolation** — Each subagent gets its own conversation, terminal session, toolset. Only the final summary comes back. Intermediate tool calls never enter the parent's context. This is a CONTEXT-ENGINEERING pattern we don't have.

2. **Skills System** — Procedural memory the agent creates and reuses. Autonomous skill creation, skill self-improvement during use, FTS5 cross-session recall. Compatible with agentskills.io. (Very similar to our mementum but with FTS5 + self-improvement.)

3. **Toolset selection** — Restricting toolsets keeps subagent focused. Default toolset types: web, terminal+file, full-stack, read-only. Prevents accidental side effects.

4. **The "Context Problem"** — Subagents know absolutely nothing about your conversation. They start completely fresh. If you delegate "fix the bug we were discussing," the subagent has no idea what bug you mean. **Always pass file paths, error messages, project structure, and constraints explicitly.**

5. **Nested delegation** — Leaf subagents cannot call delegate_task. Orchestrator subagents can. Configurable max_spawn_depth (1-3). The "isolation boundary" is a first-class config.

6. **Pattern: Gather Then Analyze** — Use execute_code (Python) for mechanical data gathering (10+ tool calls), then delegate the reasoning-heavy analysis to a subagent. This is exactly the "mechanical vs reasoning" decomposition we need.

7. **Constraints** — max_concurrent_children default 3, configurable ≥1. Not durable: if parent interrupted, children cancelled. For durable work, use cronjob or background terminal.

**The highest-leverage gap I see**:

The previous research turn identified the **Reflexion gap** (recovery records but doesn't reflect). Hermes's **Skills System** is the "production version" of this idea:

- Skills = procedural memory that grows from experience
- Created by the agent itself (autonomous)
- Self-improves during use
- Cross-session recall (FTS5)
- Compatible with agentskills.io (open standard)

This is more sophisticated than simple verbal reflection. It's a full PRODUCTION-READY pattern we can adopt.

**My concrete recommendation**:

Build a `gptel-auto-workflow-skills` module that mirrors Hermes's Skills System:
- Skills = small (name, description, prompt fragment, examples) entries stored in mementum
- After a successful experiment, the system extracts a generalized skill from the diff
- After a failed experiment, the system extracts an anti-skill
- On the next attempt for similar work, the system retrieves relevant skills and prepends them to the system prompt
- Use FTS5 (mementum already has this) for cross-session recall

This is novel, concrete, builds on the previous turn's Reflexion finding, and addresses the failure pattern of "LLM self-evolution and meta-learning."

Let me also note the Nucleus EBNF path primitive change — this is relevant because our mementum integration uses paths like `mementum/memories/`. The new path grammar in nucleus means we can now express `memories(mementum/memories/)` correctly.

And the Allium v3 statechart syntax is highly relevant to our auto-workflow state machines.

OK, let me draft the 1200 char digest. I have lots of material. The directive is to be specific and avoid generic advice. Let me focus on:

1. **Hermes Skills System** (highest leverage, novel, builds on Reflexion)
2. **Nucleus allium v3 statechart** (own repo, recent, directly applicable)
3. **Hermes subagent context isolation** (novel, addresses context flood issue)
4. **Nucleus EBNF path primitive** (own repo, fixes mementum path parsing)

For the 1200 char cap, I need to be TIGHT. Let me focus on 2-3 insights, not 4.

Let me also check if there's something in nucleus's new agents that we can directly use — the distill-vsm/drift-vsm pattern is essentially a "verify the system VSM against source" loop. This is structurally similar to auto-workflow's hypothesis-driven experiments!

Final digest plan:

## External Sources

**[deep-external] Hermes Agent Skills System** — https://hermes-agent.nousresearch.com/docs/
- **What**: Procedural memory the agent creates from experience. Each skill = (name, description, prompt fragment, examples). Stored in FTS5 DB. Self-improves during use. Cross-session recall. Compatible with agentskills.io (open standard).
- **Why novel**: Previous turn's Reflexion finding was "write a 1-paragraph reflection on failure." Hermes's Skills are the production version — generalized, reusable, indexed, with open standard for portability. They ARE the "skill library" a meta-learning system needs.
- **Apply**: Add `gptel-auto-workf
...[Result too large, truncated. Full result saved to: /home/davidwu/.emacs.d/var/tmp/gptel-subagent-result-IOlACd.txt. Use Read tool if you need more]...

**Digested Insights:**

> Project: /home/davidwu/.emacs.d/
> Updated: 2026-06-04 11:03

Researcher result for task: External research turn 1/2

<think>
Let me carefully parse this complex prompt. The system is feeding me a stateful, evolving research directive with multiple layers of context:

1. **Role**: External research specialist for Emacs AI agent system
2. **Current state**:
   - 870 total experiments
   - Research effectiveness: 15.9% (very low)
   - Best strategy: 6.0% keep rate
   - Source effectiveness: own-repo=0.54, external=0.14, unknown=0.15
   - Beta: 0.06 (very conservative)
   - Own repo priority: 53%, external: 15%
   - Stop threshold: 66% confidence
   - Token budget: 4503
   - Recent failure patterns include validation/timeout errors

3. **Controller directive**:
   - "Start with own repos: gh search repos davidwuchn"
   - "Followed by: 1-2 external references"
   - Budget: 53% own repos, 15% external
   - "λ engage(nucleus)"
   - Health: HEALTHY (level 0, 13 experiments, 0% keep-rate)

4. **Anti-patterns**: "Use AI better" is banned

5. **Output constraints**:
   - Max 1200 chars
   - JSON metadata at end
   - ## headers
   - Bullet points for techniques
   - Inline code for examples

6. **Banned patterns from previous research**: Generic advice, ideas already in codebase, theoretical without implementation path, heavy external dependencies

7. **Focus areas** (from failure patterns):
   - AI agent workflow architectures
   - Emacs Lisp AI integration patterns
   - LLM self-evolution and meta-learning
   - Code analysis automation
   - Prompt engineering for code generation
   - Error recovery and retry patterns
   - Benchmarking and evaluation
   - Git-based memory systems
   - hermes-agent, zeroclaw, ml-intern projects

Looking at the meta-context from previous research turn:
- Previous turn (now shown as truncated in the prompt) found:
  - **Reflexion** (verbal self-reflection) — gap confirmed: `gptel-recovery-record-experiment` records but doesn't reflect
  - **DSPy** (signatures, modules, optimizers)
  - **Aider's repo map** (graph-based codebase context)
  - **Anthropic Building Effective Agents** (5 workflow patterns + ACI)
  - **claude-code.el** (multi-instance buffer management)
  - gptel-context-branching
  - magent
  - MAST failure taxonomy
  - MemGPT/mem0/A-MEM

The current controller says "Start with own repos" - so I should check own repos for recent changes I haven't captured.

Wait - the prompt is showing me a continuation. The previous turn (shown truncated) found the **Reflexion** pattern as the highest-leverage gap. The controller has now given me a NEW directive: start with own repos, then 1-2 external.

The new directive is asking me to:
1. Check own repos (davidwuchn/*) for RECENT activity/changes
2. Then 1-2 external sources
3. Max 1200 chars output
4. JSON metadata at end
5. Be concrete and implementable in Emacs Lisp
6. Focus on gaps in our system

Given the system has ALREADY had the recovery/reflection insight, and the failure patterns highlight:
- Error recovery and retry patterns
- AI agent workflow architectures
- Code analysis automation
- hermes-agent, zeroclaw, ml-intern

I should:
1. Probe own repos for new commits since the last research cycle
2. Find one specific actionable insight that builds on Reflexion
3. Return tight 1200 char digest

Let me think about what specific things to look for:

1. **Check own repos** for changes since last research (nucleus, mementum, gptel)
2. **Look for SPECIFIC implementation patterns** - not generic advice
3. **Focus on the recovery gap** that the previous turn found

Let me do parallel web fetches to check recent activity on the own repos. The previous turn already did a thorough job on the major external sources, so I should:
1. Check own repos for recent changes
2. Find ONE specific new pattern (e.g., a newer arxiv paper, a specific Emacs package)
3. Make the connection to our specific modules

Let me start with parallel probes:

1. WebFetch davidwuchn/nucleus (recent activity)
2. WebFetch davidwuchn/mementum (recent activity)
3. WebFetch davidwuchn/gptel (recent activity)
4. WebSearch for the new failure patterns (hermes-agent, zeroclaw, ml-intern)

Actually, looking more carefully at the prompt - the "Previous turn" output is shown as if I did it, with truncated output. The current directive is asking me to do a NEW research turn.

Let me do this efficiently. The most important things:

1. The previous turn already identified the Reflexion gap. I should build on this.
2. The system has a recovery module that records failures but doesn't reflect.
3. I need to check own repos for new patterns, and find 1-2 external sources.

Let me check own repos for new activity in parallel with searching for the projects mentioned in failure patterns (hermes-agent, zeroclaw, ml-intern).

Actually, looking at the system prompt one more time, I see that the previous research turn was already done. The current state shows:

"## Sources Checked This Turn
- 1× gptel, claude-code.el, aider, anthropic, magent, dspy, arxiv.org, memgpt, mem0, a-mem, mast, gptel-context-branching, mevedel

## EMA confidence
- 0.34 (target: 0.65, delta: 0.00)"

So the EMA confidence is 0.34, below the 0.65 stop threshold. The controller is now asking me to CONTINUE with the new directive: 53% own repos, 15% external.

Wait, I see the prompt has been showing me the OUTPUT of previous research as if it were from a prior turn. Let me re-read the structure.

Looking at it again, the structure of this prompt is:
1. System prompt (role, phase checklist, output format)
2. Researcher prompt (with all the variables)
3. The big "..." section shows outputs from prior research turns (truncated)
4. Then the current turn's directives

The key question: is this the FIRST research turn, or am I being asked to do a CONTINUATION?

Given:
- The EMA confidence is 0.34 (below 0.65 threshold)
- The "Previous findings show promise but need more depth"
- "Start with own repos" directive
- Source directive shows: "Source type: own-repos-first"

This looks like the controller is now directing me to do an own-repos-first research turn, after the previous one failed (100% external was deviant).

So my task is:
1. Check davidwuchn/* repos first (53% budget)
2. Then 1-2 external (15% budget)
3. Max 1200 chars
4. JSON metadata
5. Be concrete for Emacs Lisp

Let me do this. I should:
1. Probe own repos in parallel
2. Check the local codebase for the actual state (since the previous research identified gaps)
3. Find concrete implementable patterns

Let me start with parallel web fetches and local greps.

Actually, looking at the system prompt and previous research output:
- The previous research (shown truncated) DID identify the Reflexion gap
- The controller's response was "Continue" with new directives
- This new turn is supposed to either:
  a) Build on the previous finding
  b) Find a new angle
  c) Verify the previous finding by checking the actual codebase

The directive says "Start with own repos" - so I should:
1. Check own repos (53% budget)
2. Then 1-2 external (15% budget)

Let me do this efficiently. I'll do parallel fetches:
- davidwuchn/gptel (main one for Emacs Lisp AI integration)
- davidwuchn/nucleus (for prompt patterns)
- davidwuchn/mementum (for memory patterns)

And one external probe for the new failure pattern topics.

Actually, I notice the failure pattern mentions "hermes-agent project: agent orchestration and delegation patterns" - this might be a specific repo to look at. Let me check what hermes-agent is.

Let me start.
</think>Switching to own-repos-first per the new directive. The previous turn (external-100pct) hit 0.34 EMA — below the 0.65 stop threshold. Now I need to find **concrete recent patterns from own repos** that we haven't captured. Failure patterns point to: error recovery/retry, agent workflow architectures, code analysis automation, plus the project names (hermes-agent, zeroclaw, ml-intern). Let me probe in parallel.<think>
GitHub's commit pages are returning the marketing site (likely an auth wall or the URL structure changed). But the WebSearch found something VERY interesting:

**Hermes Agent by Nous Research** — this is the project from the failure pattern list. Key insights from the search results:
- "The self-improving AI agent built by Nous Research. The only agent with a built-in learning loop — it creates skills from experience, improves them during use, nudges itself to persist knowledge, and builds a deepening model of who you are across sessions."
- "Hermes can spawn isolated child agents to work on tasks in parallel. Each subagent gets its own conversation, terminal session, and toolset. Only the final summary comes back — intermediate tool calls never enter your context window."

This is HUGE. Two key patterns:
1. **Self-improving learning loop** — creates skills from experience, improves them during use
2. **Subagent delegation with context isolation** — intermediate tool calls never enter parent's context

This is exactly the kind of thing the system needs! And it's from a project named in the failure patterns. Let me deep-read these.

Let me do a targeted fetch on the delegation-patterns page and the main Hermes Agent docs. This is high-value, novel (not searched in prior turn), and directly addresses two of the failure patterns:
- AI agent workflow architectures
- LLM self-evolution and meta-learning

Let me also try to fetch the own repos via a different URL pattern (e.g., the Atom feed for commits which doesn't require JS).
</think>The own repo commit pages are returning the marketing site (auth wall). But the WebSearch hit gold — **Hermes Agent by Nous Research**, which IS the project from the failure pattern list! Key hooks: "self-improving AI agent with a built-in learning loop — it creates skills from experience, improves them during use" and "isolated child agents... intermediate tool calls never enter your context window." Let me deep-read this AND try Atom feeds for own repos.<think>

I have rich material now. Let me synthesize:

**From own repo (nucleus Atom feed) — recent activity I HAVEN'T captured**:
- `c04e8001` 2026-05-10: Merge michaelwhitford/main into main
- `93c171ad` 2026-05-05: **❌ EBNF — add path primitive for directory arguments** (arg_list → `arg` accepts `expression | path`, new `path` and `path_segment` rules, fixes memories(mementum/memories/) parsing) — **HIGH RELEVANCE** to our mementum integration
- `147d33a2` 2026-03-29: `*-autoloads.el` gitignore
- `2668c598` 2026-03-27: **✅ allium compiler upgraded to v3** — Statechart syntax (transition graphs, when clauses, derived values, backtick enums, ordered collections, black box fn syntax) — directly relevant to our auto-workflow state machines
- `5efe2ba1` 2026-03-25: **✅ agents — backgammon game, VSM distill/drift cycle, fulcro VSM upgrade** — agents/distill-vsm, agents/distill-code-vsm, agents/drift-vsm, agents/drift-code-vsm — **PROCEDURAL MEMORY + VERIFICATION** patterns!
- `42718db8` 2026-03-24: **💡 document four new tension pairs** (signal/noise, order/entropy, truth/provability, self/other)
- `3eb97e32` 2026-03-24: **✅ agents/rps — first nucleus agent** — "AGENTS.md (executable prompt) + README.md (usage docs)" pattern
- And the VSM/Tiantai/Yin-Yang mapping work (probably already captured)

**From external (Hermes Agent by Nous Research) — novel & high-leverage**:

1. **Subagent delegation with context isolation** — Each subagent gets its own conversation, terminal session, toolset. Only the final summary comes back. Intermediate tool calls never enter the parent's context. This is a CONTEXT-ENGINEERING pattern we don't have.

2. **Skills System** — Procedural memory the agent creates and reuses. Autonomous skill creation, skill self-improvement during use, FTS5 cross-session recall. Compatible with agentskills.io. (Very similar to our mementum but with FTS5 + self-improvement.)

3. **Toolset selection** — Restricting toolsets keeps subagent focused. Default toolset types: web, terminal+file, full-stack, read-only. Prevents accidental side effects.

4. **The "Context Problem"** — Subagents know absolutely nothing about your conversation. They start completely fresh. If you delegate "fix the bug we were discussing," the subagent has no idea what bug you mean. **Always pass file paths, error messages, project structure, and constraints explicitly.**

5. **Nested delegation** — Leaf subagents cannot call delegate_task. Orchestrator subagents can. Configurable max_spawn_depth (1-3). The "isolation boundary" is a first-class config.

6. **Pattern: Gather Then Analyze** — Use execute_code (Python) for mechanical data gathering (10+ tool calls), then delegate the reasoning-heavy analysis to a subagent. This is exactly the "mechanical vs reasoning" decomposition we need.

7. **Constraints** — max_concurrent_children default 3, configurable ≥1. Not durable: if parent interrupted, children cancelled. For durable work, use cronjob or background terminal.

**The highest-leverage gap I see**:

The previous research turn identified the **Reflexion gap** (recovery records but doesn't reflect). Hermes's **Skills System** is the "production version" of this idea:

- Skills = procedural memory that grows from experience
- Created by the agent itself (autonomous)
- Self-improves during use
- Cross-session recall (FTS5)
- Compatible with agentskills.io (open standard)

This is more sophisticated than simple verbal reflection. It's a full PRODUCTION-READY pattern we can adopt.

**My concrete recommendation**:

Build a `gptel-auto-workflow-skills` module that mirrors Hermes's Skills System:
- Skills = small (name, description, prompt fragment, examples) entries stored in mementum
- After a successful experiment, the system extracts a generalized skill from the diff
- After a failed experiment, the system extracts an anti-skill
- On the next attempt for similar work, the system retrieves relevant skills and prepends them to the system prompt
- Use FTS5 (mementum already has this) for cross-session recall

This is novel, concrete, builds on the previous turn's Reflexion finding, and addresses the failure pattern of "LLM self-evolution and meta-learning."

Let me also note the Nucleus EBNF path primitive change — this is relevant because our mementum integration uses paths like `mementum/memories/`. The new path grammar in nucleus means we can now express `memories(mementum/memories/)` correctly.

And the Allium v3 statechart syntax is highly relevant to our auto-workflow state machines.

OK, let me draft the 1200 char digest. I have lots of material. The directive is to be specific and avoid generic advice. Let me focus on:

1. **Hermes Skills System** (highest leverage, novel, builds on Reflexion)
2. **Nucleus allium v3 statechart** (own repo, recent, directly applicable)
3. **Hermes subagent context isolation** (novel, addresses context flood issue)
4. **Nucleus EBNF path primitive** (own repo, fixes mementum path parsing)

For the 1200 char cap, I need to be TIGHT. Let me focus on 2-3 insights, not 4.

Let me also check if there's something in nucleus's new agents that we can directly use — the distill-vsm/drift-vsm pattern is essentially a "verify the system VSM against source" loop. This is structurally similar to auto-workflow's hypothesis-driven experiments!

Final digest plan:

## External Sources

**[deep-external] Hermes Agent Skills System** — https://hermes-agent.nousresearch.com/docs/
- **What**: Procedural memory the agent creates from experience. Each skill = (name, description, prompt fragment, examples). Stored in FTS5 DB. Self-improves during use. Cross-session recall. Compatible with agentskills.io (open standard).
- **Why novel**: Previous turn's Reflexion finding was "write a 1-paragraph reflection on failure." Hermes's Skills are the production version — generalized, reusable, indexed, with open standard for portability. They ARE the "skill library" a meta-learning system needs.
- **Apply**: Add `gptel-auto-workf
...[Result too large, truncated. Full result saved to: /home/davidwu/.emacs.d/var/tmp/gptel-subagent-result-IOlACd.txt. Use Read tool if you need more]...

**Meta-learning:** Research quality measured by downstream experiment success.

---
*Generated by auto-workflow*
