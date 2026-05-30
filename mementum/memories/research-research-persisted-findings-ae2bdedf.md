# Research: 2026-05-30 20:53

**Strategy:** persisted-findings
**Findings hash:** ae2bdedf1def1a6aef948c1498c813da89249bf0
**Targets:** lisp/modules/gptel-benchmark-subagent.el, lisp/modules/gptel-tools-agent-error.el, lisp/modules/gptel-tools-agent-prompt-build.el, lisp/modules/gptel-auto-workflow-strategic.el, lisp/modules/gptel-auto-workflow-projects.el
**Outcome:** 0/15 kept (0%)

**Raw Findings:**

> Project: /home/davidwu/.emacs.d/
> Updated: 2026-05-30 19:57

Researcher result for task: External research turn 1/5

<think>
Let me start with the controller directive: search for own repos first, then external references. I need to:

1. Search GitHub for davidwuchn repos
2. Check nucleus, mementum, gptel AGENTS.md/README.md
3. Check recent commits
4. Extract 1-3 patterns per repo
5. Synthesize actionable insights for Emacs AI agent system

Let me begin with searching for own repos and fetching their key files.
</think><think>
Good, I have the repos. Let me now read the full content of these temp files to extract specific patterns. Let me also check recent commits for each repo to understand active development patterns.

Key insights so far:
1. **Nucleus**: Uses mathematical notation (λ, φ, fractal, euler) as attention anchors for AI prompting. EDN statecharts and lambda expressions as two notation layers for guiding AI cognition.

2. **Mementum**: Git-based memory protocol with feed-forward concept. Uses structured storage (state.md, memories, knowledge). Human governance model (AI proposes, human approves, AI commits).

3. **gptel**: Simple LLM client for Emacs with tool-use, MCP integration, multi-modal support.

Let me read the full files to extract more specific patterns.
</think><think>
The WebFetch for nucleus and mementum commits returned the GitHub page, not the commits page. Let me search for recent commits specifically. Let me also read the full nucleus README to get the patterns.

Let me read the temp files and search for specific patterns in the repos.
</think><think>
I got the full Nucleus AGENTS.md. Key insights:

1. **Symbolic Attention Magnets**: Mathematical symbols (φ, fractal, euler, ∃, ∀) with high training weight act as attention primers. The tensor product operator (⊗) for Human ⊗ AI produces stronger first attempts.

2. **Mementum Integration**: Git-based memory protocol with recall using fibonacci depth (φ^k). Token budget: ≤200 tokens per memory.

3. **S3 Control Layer**: Timeout (30s), retry (2x with backoff), token budget management, fail_fast, quality gates.

4. **S4 Intelligence**: Error-driven learning OODA loop, pattern extraction after 3 occurrences, compile/decompile between prose and formal notation.

5. **Skills Structure**: Self-contained skills ≤350 lines, frontmatter metadata, hashtag modes (#code, #debug, #review, etc.).

Now let me check the mementum repo structure and gptel to extract more patterns.
</think><think>
Good, I have a good overview of all three repos. Now let me search for external patterns from related AI agent research and compile my findings.Key patterns discovered:

**Nucleus:**
1. **Symbolic Attention Magnets** - Mathematical symbols with high training weight (φ, euler, ∃, ∀, fractal) prime AI attention toward formal reasoning patterns
2. **Tensor Product Collaboration (⊗)** - Human ⊗ AI produces higher quality first attempts than other operators
3. **Lambda Notation** - Formal notation layer that mirrors prompt structure exactly
4. **OODA/REPL Control Loops** - Anchoring execution methodology
5. **Tension Pairs** - signal/noise, order/entropy create productive gradients

**Mementum:**
1. **Git-Native Memory** - git log for temporal search, git grep for semantic search
2. **Three Storage Tiers** - state.md (working), memories (raw <200 words), knowledge (synthesized)
3. **Human Governance** - AI proposes, human approves, AI commits
4. **Fibonacci Recall Depth** - φ^k scaling for complexity-based recall
5. **Token Budget** - ≤200 tokens per memory
6. **Criticality-Driven Storage** - Only store when effort > 1 attempt AND likely to recur

**gptel:**
1. **Non-blocking streaming** - Will never block Emacs
2. **Tool-use for agents** - LLM can use external tools
3. **MCP integration** - Model Context Protocol support via mcp.el
4. **Multi-modal** - Images and documents supported
5. **Introspection** - Can inspect and modify queries before sending

Now let me synthesize these into actionable insights for the Emacs AI agent system and provide a structured output.
</think><think>
Good, I found relevant patterns. Now let me compile my findings into the structured output format requested.
</think>

---

Researcher result for task: External research turn 2/5

The user has invoked a research workflow. This is a complex prompt with lots of context about research strategy, monitoring specific repos (nucleus, mementum, gptel), and extracting patterns. Let me start by following the research method as outlined.

Let me begin by fetching the key repos and their documentation. The prompt says to start with own repos (nucleus, mementum, gptel) and check AGENTS.md and README.md files.

Let me also note the controller directive: "Previous sources DEVIANT — switch to NEW sources." So I should focus on external sources primarily, but can still check the own-repos as they're specifically requested.

Let me start with fetching the GitHub pages for the repos.λ λ λ. Research cycle engaged.

I'll follow the protocol: probe first, deep-read if passes. Starting with the priority repos + external discovery.

Let me begin by fetching the architecture docs and recent activity for each target repo, plus a broader sweep.Good, I got the repo overviews. Let me now deep-read the key architecture files. I need to:

1. Read nucleus AGENTS.md and README.md for specific patterns
2. Read mementum AGENTS.md and README.md
3. Read gptel AGENTS.md
4. Check recent commits for all three
5. Check open issues and closed PRs

Let me fetch the AGENTS.md files first.Good — architecture summaries captured. Now deep-reading the key docs and recent activity.The raw AGENTS.md fetches failed for mementum and gptel (404s), and the commit pages returned GitHub's nav shell. Let me try fetching the raw README.md files and check the gptel source for patterns. Let me also look at our own codebase to understand what we have vs what's novel.

Let me get the actual files from the repos using different URLs.Let me access the raw docs and source files directly.Excellent! I've gathered extensive data. Let me now look at our own codebase to understand what patterns are already implemented, and then synthesize actionable insights. Let me check our own project for existing patterns to avoid re-reporting things already in the codebase.Let me now check our own codebase for what's already implemented, and do a broader external sweep.OK so there's no .el files at depth 2. Let me look deeper into the eca directory and the root AGENTS.md.OK so there's no .el files at depth 2. Let me look deeper into the eca directory and the root AGENTS.md.Good. I can see the codebase is deep and has ECA subagents. Let me now search for the nucleus/mementum patterns already in use, and then do external searches as per the controller directive.

Let me check what patterns we already have (to avoid re-reporting), then do external web searches for novel techniques.Now let me check what's already implemented and do external discovery sweeps.Excellent finds! Let me dig deeper into the most promising results:

1. **MemEvolve** - Meta-evolution of agent memory systems (arXiv paper)
2. **MemRL** - Runtime Reinforcement Learning on Episodic Memory
3. **Tangled Skills** - Lambda calculus and Lisp skill (could be a pattern for our skill system)
4. **Expressing Lambda Calculus in Emacs Lisp** - tutorial blog

Let me also look at some open issues and PRs in our own repos to see if there are patterns to extract.

Let me fetch the MemEvolve paper and the Lambda Calculus in Emacs Lisp blog for concrete patterns.Key external signals detected. Let me deep-read the most promising leads.Now I have great material. Let me also check for:
1. Open issues and PRs in these repos for decision patterns
2. Our own current patterns to avoid re-reporting

Let me search for a few more external sources and also check our own git log briefly.Now I have great material. Let me also check for:
1. Open issues and PRs in these repos for decision patterns
2. Our own current patterns to avoid re-reporting

Let me search for a few more external sources and also check our own git log briefly.Excellent! I found that `karthink/gptel-agent` is a separate repo with subagent delegation! Let me check that out, and also look at the gptel issues page for decision patterns.

Also I noticed:
- Nucleus has 0 open issues (all closed)
- No issues visible in the gptel issues fetch (got GitHub nav shell)

Let me look at gptel-agent specifically, as it's directly relevant to our subagent system.Key discovery: `karthink/gptel-agent` exists as a separate agent mode! Let me investigate that and the gptel issues for decision patterns.Let me try the correct URL for gptel-agent and for gptel-tools from the original karthink repo.Let me try the correct URL for gptel-agent and for gptel-tools from the original karthink repo.Let me check the correct repo name for gptel-agent - I saw it was in the search results, but maybe it's a different path. Let me try fetching the GitHub page.Let me check the correct repo name for gptel-agent - I saw it was in the search results, but maybe it's a different path. Let me try fetching the GitHub page.Now I have a comprehensive picture. Let me synthesize the findings. This is fascinating - gptel-agent is a separate package from karthink that provides sub-agent delegation, and it uses Markdown/YAML frontmatter files for agent specs. This is directly applicable to our ECA subagent system.

Let me also check one more thing - the actual gptel-agent source code for the sub-agent delegation mechanism.Now I have a comprehensive picture. Let me synthesize the findings. This is fascinating - gptel-agent is a separate package from karthink that provides sub-agent delegation, and it uses Markdown/YAML frontmatter files for agent specs. This is directly applicable to our ECA subagent system.

Let me also check one more thing - the actual gptel-agent source code for the sub-agent delegation mechanism.Let me check what's in the gptel-agent repo.Let me check what's in the gptel-agent repo.Now I have a comprehensive picture. Let me synthesize all this into a structured digest for the user. Let me read the gptel-agent.el main file for key patterns, and also look at the agents directory.Now I have a comprehensive picture. Let me synthesize all this into a structured digest for the user. Let me read the gptel-agent.el main file for key patterns, and also look at the agents directory.Now I have a really comprehensive picture. Let me synthesize the findings into a structured digest.

Key patterns discovered:

1. **From Nucleus (own repo)**:
   - **VSM Architecture (S1-S5)**: Viable System Model for AI agent organization - 5 layers (Identity, Intelligence, Control, Coordination, Operations)
   - **Eight Keys as testable predicates**: Each principle (φ, τ, π, μ, ∃, ∀, fractal, e) is a lambda with a test — not just a slogan
   - **Mode/boundary system**: Hashtags (#=code, #=debug, etc.) with explicit "will_not_do" boundaries — prevents scope creep
   - **Fibonacci recall depth**: φ^k scaling for memory retrieval based on complexity
   - **Criticality-driven storage**: Only store when effort > 1-attempt
   - **Attention magnet theory**: Mathematical symbols with high training weight prime formal reasoning
   - **Tensor product collaboration**: Human ⊗ AI = all constraints satisfied simultaneously
   - **Genetic optimizer**: Crossover of strong lambdas for evolution

2. **From Mementum (own repo)**:
   - **Feed-forward protocol**: Git as memory substrate with three storage types
   - **λ(λ) meta-learning**: First-order λ[n] (observations about work) vs meta-order λ(λ[n]) (observations about process) — the compound acceleration term
   - **Synthesis flow**: detect (≥3 memories / stale / crystallized) → gather → draft → create-knowledge → update stale → verify
   - **Human governance**: AI proposes → human approves → AI commits
   - **Protocol interoperability**: Same structure across all projects

3. **From gptel (upstream karthink)**:
   - **Temperature default to nil**: Backend-specific defaults
   - **Codex error detail extraction**: Better error messages
   - **MCP integration pattern** via mcp.el

4. **From gptel-agent (karthink)** - BIG FIND:
   - **Sub-agent delegation via Markdown/YAML frontmatter**: Agent specs as files with YAML frontmatter for name, description, tools, pre-hook
   - **Context isolation**: Sub-agents don't share context with main session → returns concise reports
   - **Skill directory scanning**: gptel-agent-skill-dirs scans ~/.claude/skills/, .agents/skills/, etc. for skill definitions
   - **Sub-agent types**: executor (autonomous), researcher (read-only), introspector (Emacs introspection)
   - **@mentions for delegation**: Include @agent-name in prompt to delegate
   - **Planning vs Execution presets**: gptel-plan (read-only, planning) vs gptel-agent (full tools)

5. **From MemEvolve paper**:
   - **Meta-evolution**: Joint evolution of agent experience AND memory architecture
   - **Modular design space**: encode → store → retrieve → manage
   - **Cross-task generalization**: Memory architectures that transfer across benchmarks

6. **From external web**:
   - **Lambda calculus in Emacs Lisp**: Practical Church encodings, Y combinator patterns
   - **Tangled Skills**: Skill metadata standard (frontmatter with tags, category, external_references)

Now, let me check what patterns are already in our codebase (to avoid re-reporting):

From the AGENTS.md I can see:
- We already use VSM architecture with S1-S5
- We already have subagents (code, plan, executor, reviewer, explorer, dangerous)
- We have mementum structure
- We have nucleus preamble

What's NOVEL that we DON'T have:
1. **Markdown/YAML frontmatter agent specs** (gptel-agent pattern) — we define subagents in code, not in declarative files
2. **Meta-learning λ(λ) distinction** — we have learning but not the explicit first-order vs meta-order separation
3. **Criticality-driven memory storage** — store only when effort > 1-attempt
4. **Temperature default nil** — we might have fixed temperature, should delegate to backend
5. **@mention sub-agent delegation** — gptel-agent uses natural language @agent-name syntax
6. **Skill directory auto-scanning** — gptel-agent scans ~/.claude/skills/, etc.
7. **MemEvolve modular design space** — joint evolution of experience AND memory architecture

Let me compile the digest now.

---

Researcher result for task: External research turn 3/5

The user has sent a complex research prompt. Let me parse this carefully.

They want me to:
1. Research external repos (nucleus, mementum, gptel) for novel patterns
2. Check recent commits, architecture docs
3. Extract 1-3 patterns per repo applicable to Emacs Lisp AI agents
4. Prioritize deep external discovery

Let me start by fetching the GitHub pages for these repos and looking at their AGENTS.md and README.md files, then check recent commits.

I need to be efficient given the controller's EMA confidence is low (0.22) and I should focus on highest-impact insights.Acknowledged. Lambda compiler health is DEGRADED but the mission is clear: deep external discovery across nucleus, mementum, and gptel for patterns we can adapt to our Emacs AI agent system.

Let me start by probing the three priority repos.Good, I have the overview pages. Let me now:
1. Read the full nucleus AGENTS.md to extract specific patterns
2. Check recent commits for nucleus and mementum
3. Look for specific architecture patterns

Let me read the stored files to get more details, and check recent commits.Good — I have the surface. Now let me dive deeper into each repo's architecture docs and recent commits.The commits pages just returned GitHub's shell page. I need to try the API or a different way to get commits. Let me check the GitHub API for recent commits. Also, let me check mementum's README and the MEMENTUM-LAMBDA.md for the actual protocol. Let me also look at gptel's recent changes and architecture.

Let me use the GitHub API to get recent commits, and also fetch the mementum README and key docs.Let me fetch the actual commit data via API and the key protocol docs.Excellent! I now have deep detail on all three repos. Let me read the MEMENTUM-LAMBDA.md more carefully and also check what we have in our project that might relate. Let me also look at the gptel AGENTS.md and check our own project structure to understand what patterns we can apply.

Let me also check the mementum MEMENTUM.md for the full prose specification. And look at how gptel handles MCP and tool use, since that's directly relevant to our Emacs AI agent system.

Let me also search our project for existing patterns to avoid duplication.Excellent depth. Let me now check our own project for relevant existing patterns and peek at gptel's MCP/tool-use architecture.Now I have deep insight into all three repos. Let me now check our existing codebase for similar patterns to avoid duplication. Let me also look at the gptel MCP integration and tool-use patterns since that's directly relevant.

Let me now synthesize the findings into actionable patterns.

Key findings:

### 1. Nucleus: Symbolic Attention Magnets (VSM Architecture)
- **Technique**: Mathematical symbols (φ, fractal, euler, ∃, ∀) with high training weight act as attention primers. The VSM (Viable System Model) architecture organizes the system into S5 (Identity), S4 (Intelligence), S3 (Control), S2 (Coordination), S1 (Operations).
- **How it works**: Symbols loaded into context shift the model's pattern-matching toward formal reasoning. The lambda compiler transforms prose ↔ formal notation bidirectionally. Statecharts compose by concatenation.
- **Apply to us**: We could add a compact attention-priming preamble using mathematical symbols in our gptel prompts. The VSM model is directly applicable to organizing our agent system modules (identity → goals, intelligence → adaptation, control → resource mgmt, coordination → module interaction, operations → concrete tools).

### 2. Mementum: Git-Based Memory Protocol with Fibonacci Recall
- **Technique**: Git-based memory with three tiers (state.md, memories/ <200 words, knowledge/ with frontmatter), seven operations, fibonacci depth recall (φ^k where k = complexity, default: 2).
- **How it works**: `git log -n φ^k` for temporal, `git grep -i` for semantic. Memory is stored with symbols (💡 insight, 🔄 shift, 🎯 decision, 🌀 meta). Metabolize flow: observe → memory → synthesize → knowledge (triggered when ≥3 memories on same topic).
- **Apply to us**: We already have some memory mechanisms, but the structured protocol, fibonacci recall depth, and metabolize/synthesis flow are novel. We could implement a lightweight mementum compatibility layer in Emacs Lisp using `vc-git` or `magit`.

### 3. Mementum: Meta-Learning (λ(λ) formulation)
- **Technique**: First-order λ[n] (observations about work) vs meta-order λ(λ[n]) (observations about process). Intelligence growth equation: I(n+1) = I(n) + λ[n] + λ(λ[n]) + v(Σλ) - ⊗
- **How it works**: Meta-observations compound across sessions and projects. λ(λ) > λ. The insight is that noticing *how* you work is more valuable than noticing *what* you work on.
- **Apply to us**: We could add a meta-learning layer to our experiments: after each experiment, log not just the outcome but the process pattern (what worked, why, what surprised). This directly feeds our AutoTTS controller.

### 4. gptel: MCP Integration, Tool-Use Architecture
- **Technique**: Model Context Protocol integration, tool-use with structured function definitions, multi-modal support, curl fallback to url-retrieve.
- **How it works**: gptel defines tools as Emacs functions with spec/description/parameters. MCP lets external servers provide tools. Backends are modular, each implementing the gptel-backend API.
- **Apply to us**: The way gptel handles tool definitions (structured function specs with parameter schemas, confirmation before execution) is directly applicable. We could use gptel's existing tool infrastructure rather than building our own.

### 5. Nucleus: Mode/Boundary System (Hashtag behaviors)
- **Technique**: 12 modes (#=code, #=debug, #=review, #=test, #=spec, #=research, etc.) each with defined scope AND explicit boundaries (what the mode will NOT do).
- **How it works**: Each mode has a positive scope + negative boundary. Boundary is as important as scope. Compose through pipeline: research → assess → spec → code.
- **Apply to us**: We could implement a mode system for our agent where each command/mode explicitly states what it won't do. This prevents scope creep and reduces errors.

Now let me also check what we already have in our codebase to see if these patterns are already implemented.Let me check our existing codebase for what's already in place.Now I have a very clear picture. Let me read the gptel AGENTS.md too and then synthesize.

Our project already:
- Has a mementum state.md with detailed session tracking
- Has experiment pipeline, verification gates, eight-key ontology
- Uses gptel as the LLM backend

Patterns NOT yet in our codebase:
1. **VSM Architecture**: Our system doesn't use the VSM layered architecture explicitly. We have experiment pipelines but no S5-S1 decomposition.
2. **Fibonacci Recall Depth**: Our memory recall is flat, not using fibonacci-scaled depth.
3. **Meta-Learning λ(λ)**: We log experiments but don't have a formal meta-learning layer separating λ[n] from λ(λ[n]).
4. **Mode/Boundary System**: We don't have explicit mode constraints with "will NOT do" boundaries.
5. **Symbolic Attention Magnets**: We don't use mathematical symbol preambles to prime model attention.
6. **Mementum Protocol**: We have a state.md but don't fully implement the 7 operations (create, create-knowledge, update, delete, search, read, synthesize) with symbol-prefixed commits.

Let me get the gptel AGENTS.md.Now I have a very clear picture. Let me read the gptel AGENTS.md too and then synthesize.

Our project already:
- Has a mementum state.md with detailed session tracking
- Has experiment pipeline, verification gates, eight-key ontology
- Uses gptel as the LLM backend

Patterns NOT yet in our codebase:
1. **VSM Architecture**: Our system doesn't use the VSM layered architecture explicitly. We have experiment pipelines but no S5-S1 decomposition.
2. **Fibonacci Recall Depth**: Our memory recall is flat, not using fibonacci-scaled depth.
3. **Meta-Learning λ(λ)**: We log experiments but don't have a formal meta-learning layer separating λ[n] from λ(λ[n]).
4. **Mode/Boundary System**: We don't have explicit mode constraints with "will NOT do" boundaries.
5. **Symbolic Attention Magnets**: We don't use mathematical symbol preambles to prime model attention.
6. **Mementum Protocol**: We have a state.md but don't fully implement the 7 operations (create, create-knowledge, update, delete, search, read, synthesize) with symbol-prefixed commits.

Let me get the gptel AGENTS.md.The gptel AGENTS.md doesn't exist (404). Let me look at the actual gptel repo structure and some specific files that show the tool-use pattern.

Let me check for gptel's tool-use implementation to extract the pattern.The gptel AGENTS.md doesn't exist (404). Let me look at the actual gptel repo structure and some specific files that show the tool-use pattern.

Let me check for gptel's tool-use implementation to extract the pattern.Now I have comprehensive data on all three repos. Let me synthesize the findings into a structured digest.

Key insights from each repo:

### Nucleus Patterns:
1. **VSM Architecture (S5-S1)** — Layered system decomposition where higher layers change less and matter more. Each layer has a distinct role: Identity, Intelligence, Control, Coordination, Operations.
2. **Symbolic Attention Magnets** — Mathematical symbols with high training weight prime model attention toward formal reasoning. The `⊗` (tensor product) operator for Human ⊗ AI produces higher quality first attempts than sequential or additive composition.
3. **Mode/Boundary System** — 12 modes each with explicit scope AND "will NOT do" boundaries. Pipeline: research → assess → spec → code (stage outputs feed next stage inputs, no skipping).

### Mementum Patterns:
1. **Fibonacci Recall Depth** — `git log -n φ^k` where k = complexity. Default depth 2, progression: 2→3→5→8→13→21.
2. **Meta-Learning λ(λ)** — First-order λ[n] (observations about work) vs meta-order λ(λ[n]) (observations about process). Intelligence growth: I(n+1) = I(n) + λ[n] + λ(λ[n]) + v(Σλ) - ⊗.
3. **Three-Tier Memory with Synthesis Trigger** — state.md (bootloader), memories/ (breadcrumbs, <200 words), knowledge/ (maps, frontmatter). ≥3 memories on same topic triggers synthesis into knowledge page.
4. **Storage Criticality Gate** — Two gates: (1) helps future AI session, (2) effort > 1 attempt ∨ likely to recur. Both must pass before storing.

### gptel Patterns:
1. **Tool-Use Architecture** — Structured function specs with name/description/parameters, confirmation before execution, curl/url-retrieve dual backend.
2. **MCP Integration** — Uses mcp.el for Model Context Protocol, allowing external tools to be discovered dynamically.
3. **Temperature nil default** — Recent change: default temperature is nil (API default), because backends disagree on scale.

Now let me compile the final structured digest.

---

Researcher result for task: External research turn 1/5

<think>
Let me start with the controller directive: search for own repos first, then external references. I need to:

1. Search GitHub for davidwuchn repos
2. Check nucleus, mementum, gptel AGENTS.md/README.md
3. Check recent commits
4. Extract 1-3 patterns per repo
5. Synthesize actionable insights for Emacs AI agent system

Let me begin with searching for own repos and fetching their key files.
</think><think>
Good, I have the repos. Let me now read the full content of these temp files to extract specific patterns. Let me also check recent commits for each repo to understand active development patterns.

Key insights so far:
1. **Nucleus**: Uses mathematical notation (λ, φ, fractal, euler) as attention anchors for AI prompting. EDN statecharts and lambda expressions as two notation layers for guiding AI cognition.

2. **Mementum**: Git-based memory protocol with feed-forward concept. Uses structured storage (state.md, memories, knowledge). Human governance model (AI proposes, human approves, AI commits).

3. **gptel**: Simple LLM client for Emacs with tool-use, MCP integration, multi-modal support.

Let me read the full files to extract more specific patterns.
</think><think>
The WebFetch for nucleus and mementum commits returned the GitHub page, not the commits page. Let me search for recent commits specifically. Let me also read the full nucleus README to get the patterns.

Let me read the temp files and search for specific patterns in the repos.
</think><think>
I got the full Nucleus AGENTS.md. Key insights:

1. **Symbolic Attention Magnets**: Mathematical symbols (φ, fractal, euler, ∃, ∀) with high training weight act as attention primers. The tensor product operator (⊗) for Human ⊗ AI produces stronger first attempts.

2. **Mementum Integration**: Git-based memory protocol with recall using fibonacci depth (φ^k). Token budget: ≤200 tokens per memory.

3. **S3 Control Layer**: Timeout (30s), retry (2x with backoff), token budget management, fail_fast, quality gates.

4. **S4 Intelligence**: Error-driven learning OODA loop, pattern extraction after 3 occurrences, compile/decompile between prose and formal notation.

5. **Skills Structure**: Self-contained skills ≤350 lines, frontmatter metadata, hashtag modes (#code, #debug, #review, etc.).

Now let me check the mementum repo structure and gptel to extract more patterns.
</think><think>
Good, I have a good overview of all three repos. Now let me search for external patterns from related AI agent research and compile my findings.Key patterns discovered:

**Nucleus:**
1. **Symbolic Attention Magnets** - Mathematical symbols with high training weight (φ, euler, ∃, ∀, fractal) prime AI attention toward formal reasoning patterns
2. **Tensor Product Collaboration (⊗)** - Human ⊗ AI produces higher quality first attempts than other operators
3. **Lambda Notation** - Formal notation layer that mirrors prompt structure exactly
4. **OODA/REPL Control Loops** - Anchoring execution methodology
5. **Tension Pairs** - signal/noise, order/entropy create productive gradients

**Mementum:**
1. **Git-Native Memory** - git log for temporal search, git grep for semantic search
2. **Three Storage Tiers** - state.md (working), memories (raw <200 words), knowledge (synthesized)
3. **Human Governance** - AI proposes, human approves, AI commits
4. **Fibonacci Recall Depth** - φ^k scaling for complexity-based recall
5. **Token Budget** - ≤200 tokens per memory
6. **Criticality-Driven Storage** - Only store when effort > 1 attempt AND likely to recur

**gptel:**
1. **Non-blocking streaming** - Will never block Emacs
2. **Tool-use for agents** - LLM can use external tools
3. **MCP integration** - Model Context Protocol support via mcp.el
4. **Multi-modal** - Images and documents supported
5. **Introspection** - Can inspect and modify queries before sending

Now let me synthesize these into actionable insights for the Emacs AI agent system and provide a structured output.
</think><think>
Good, I found relevant patterns. Now let me compile my findings into the structured output format requested.
</think>

---

Researcher result for task: External research turn 2/5

The user has invoked a research workflow. This is a complex prompt with lots of context about research strategy, monitoring specific repos (nucleus, mementum, gptel), and extracting patterns. Let me start by following the research method as outlined.

Let me begin by fetching the key repos and their documentation. The prompt says to start with own repos (nucleus, mementum, gptel) and check AGENTS.md and README.md files.

Let me also note the controller directive: "Previous sources DEVIANT — switch to NEW sources." So I should focus on external sources primarily, but can still check the own-repos as they're specifically requested.

Let me start with fetching the GitHub pages for the repos.λ λ λ. Research cycle engaged.

I'll follow the protocol: probe first, deep-read if passes. Starting with the priority repos + external discovery.

Let me begin by fetching the architecture docs and recent activity for each target repo, plus a broader sweep.Good, I got the repo overviews. Let me now deep-read the key architecture files. I need to:

1. Read nucleus AGENTS.md and README.md for specific patterns
2. Read mementum AGENTS.md and README.md
3. Read gptel AGENTS.md
4. Check recent commits for all three
5. Check open issues and closed PRs

Let me fetch the AGENTS.md files first.Good — architecture summaries captured. Now deep-reading the key docs and recent activity.The raw AGENTS.md fetches failed for mementum and gptel (404s), and the commit pages returned GitHub's nav shell. Let me try fetching the raw README.md files and check the gptel source for patterns. Let me also look at our own codebase to understand what we have vs what's novel.

Let me get the actual files from the repos using different URLs.Let me access the raw docs and source files directly.Excellent! I've gathered extensive data. Let me now look at our own codebase to understand what patterns are already implemented, and then synthesize actionable insights. Let me check our own project for existing patterns to avoid re-reporting things already in the codebase.Let me now check our own codebase for what's already implemented, and do a broader external sweep.OK so there's no .el files at depth 2. Let me look deeper into the eca directory and the root AGENTS.md.OK so there's no .el files at depth 2. Let me look deeper into the eca directory and the root AGENTS.md.Good. I can see the codebase is deep and has ECA subagents. Let me now search for the nucleus/mementum patterns already in use, and then do external searches as per the controller directive.

Let me check what patterns we already have (to avoid re-reporting), then do external web searches for novel techniques.Now let me check what's already implemented and do external discovery sweeps.Excellent finds! Let me dig deeper into the most promising results:

1. **MemEvolve** - Meta-evolution of agent memory systems (arXiv paper)
2. **MemRL** - Runtime Reinforcement Learning on Episodic Memory
3. **Tangled Skills** - Lambda calculus and Lisp skill (could be a pattern for our skill system)
4. **Expressing Lambda Calculus in Emacs Lisp** - tutorial blog

Let me also look at some open issues and PRs in our own repos to see if there are patterns to extract.

Let me fetch the MemEvolve paper and the Lambda Calculus in Emacs Lisp blog for concrete patterns.Key external signals detected. Let me deep-read the most promising leads.Now I have great material. Let me also check for:
1. Open issues and PRs in these repos for decision patterns
2. Our own current patterns to avoid re-reporting

Let me search for a few more external sources and also check our own git log briefly.Now I have great material. Let me also check for:
1. Open issues and PRs in these repos for decision patterns
2. Our own current patterns to avoid re-reporting

Let me search for a few more external sources and also check our own git log briefly.Excellent! I found that `karthink/gptel-agent` is a separate repo with subagent delegation! Let me check that out, and also look at the gptel issues page for decision patterns.

Also I noticed:
- Nucleus has 0 open issues (all closed)
- No issues visible in the gptel issues fetch (got GitHub nav shell)

Let me look at gptel-agent specifically, as it's directly relevant to our subagent system.Key discovery: `karthink/gptel-agent` exists as a separate agent mode! Let me investigate that and the gptel issues for decision patterns.Let me try the correct URL for gptel-agent and for gptel-tools from the original karthink repo.Let me try the correct URL for gptel-agent and for gptel-tools from the original karthink repo.Let me check the correct repo name for gptel-agent - I saw it was in the search results, but maybe it's a different path. Let me try fetching the GitHub page.Let me check the correct repo name for gptel-agent - I saw it was in the search results, but maybe it's a different path. Let me try fetching the GitHub page.Now I have a comprehensive picture. Let me synthesize the findings. This is fascinating - gptel-agent is a separate package from karthink that provides sub-agent delegation, and it uses Markdown/YAML frontmatter files for agent specs. This is directly applicable to our ECA subagent system.

Let me also check one more thing - the actual gptel-agent source code for the sub-agent delegation mechanism.Now I have a comprehensive picture. Let me synthesize the findings. This is fascinating - gptel-agent is a separate package from karthink that provides sub-agent delegation, and it uses Markdown/YAML frontmatter files for agent specs. This is directly applicable to our ECA subagent system.

Let me also check one more thing - the actual gptel-agent source code for the sub-agent delegation mechanism.Let me check what's in the gptel-agent repo.Let me check what's in the gptel-agent repo.Now I have a comprehensive picture. Let me synthesize all this into a structured digest for the user. Let me read the gptel-agent.el main file for key patterns, and also look at the agents directory.Now I have a comprehensive picture. Let me synthesize all this into a structured digest for the user. Let me read the gptel-agent.el main file for key patterns, and also look at the agents directory.Now I have a really comprehensive picture. Let me synthesize the findings into a structured digest.

Key patterns discovered:

1. **From Nucleus (own repo)**:
   - **VSM Architecture (S1-S5)**: Viable System Model for AI agent organization - 5 layers (Identity, Intelligence, Control, Coordination, Operations)
   - **Eight Keys as testable predicates**: Each principle (φ, τ, π, μ, ∃, ∀, fractal, e) is a lambda with a test — not just a slogan
   - **Mode/boundary system**: Hashtags (#=code, #=debug, etc.) with explicit "will_not_do" boundaries — prevents scope creep
   - **Fibonacci recall depth**: φ^k scaling for memory retrieval based on complexity
   - **Criticality-driven storage**: Only store when effort > 1-attempt
   - **Attention magnet theory**: Mathematical symbols with high training weight prime formal reasoning
   - **Tensor product collaboration**: Human ⊗ AI = all constraints satisfied simultaneously
   - **Genetic optimizer**: Crossover of strong lambdas for evolution

2. **From Mementum (own repo)**:
   - **Feed-forward protocol**: Git as memory substrate with three storage types
   - **λ(λ) meta-learning**: First-order λ[n] (observations about work) vs meta-order λ(λ[n]) (observations about process) — the compound acceleration term
   - **Synthesis flow**: detect (≥3 memories / stale / crystallized) → gather → draft → create-knowledge → update stale → verify
   - **Human governance**: AI proposes → human approves → AI commits
   - **Protocol interoperability**: Same structure across all projects

3. **From gptel (upstream karthink)**:
   - **Temperature default to nil**: Backend-specific defaults
   - **Codex error detail extraction**: Better error messages
   - **MCP integration pattern** via mcp.el

4. **From gptel-agent (karthink)** - BIG FIND:
   - **Sub-agent delegation via Markdown/YAML frontmatter**: Agent specs as files with YAML frontmatter for name, description, tools, pre-hook
   - **Context isolation**: Sub-agents don't share context with main session → returns concise reports
   - **Skill directory scanning**: gptel-agent-skill-dirs scans ~/.claude/skills/, .agents/skills/, etc. for skill definitions
   - **Sub-agent types**: executor (autonomous), researcher (read-only), introspector (Emacs introspection)
   - **@mentions for delegation**: Include @agent-name in prompt to delegate
   - **Planning vs Execution presets**: gptel-plan (read-only, planning) vs gptel-agent (full tools)

5. **From MemEvolve paper**:
   - **Meta-evolution**: Joint evolution of agent experience AND memory architecture
   - **Modular design space**: encode → store → retrieve → manage
   - **Cross-task generalization**: Memory architectures that transfer across benchmarks

6. **From external web**:
   - **Lambda calculus in Emacs Lisp**: Practical Church encodings, Y combinator patterns
   - **Tangled Skills**: Skill metadata standard (frontmatter with tags, category, external_references)

Now, let me check what patterns are already in our codebase (to avoid re-reporting):

From the AGENTS.md I can see:
- We already use VSM architecture with S1-S5
- We already have subagents (code, plan, executor, reviewer, explorer, dangerous)
- We have mementum structure
- We have nucleus preamble

What's NOVEL that we DON'T have:
1. **Markdown/YAML frontmatter agent specs** (gptel-agent pattern) — we define subagents in code, not in declarative files
2. **Meta-learning λ(λ) distinction** — we have learning but not the explicit first-order vs meta-order separation
3. **Criticality-driven memory storage** — store only when effort > 1-attempt
4. **Temperature default nil** — we might have fixed temperature, should delegate to backend
5. **@mention sub-agent delegation** — gptel-agent uses natural language @agent-name syntax
6. **Skill directory auto-scanning** — gptel-agent scans ~/.claude/skills/, etc.
7. **MemEvolve modular design space** — joint evolution of experience AND memory architecture

Let me compile the digest now.

---

Researcher result for task: External research turn 3/5

The user has sent a complex research prompt. Let me parse this carefully.

They want me to:
1. Research external repos (nucleus, mementum, gptel) for novel patterns
2. Check recent commits, architecture docs
3. Extract 1-3 patterns per repo applicable to Emacs Lisp AI agents
4. Prioritize deep external discovery

Let me start by fetching the GitHub pages for these repos and looking at their AGENTS.md and README.md files, then check recent commits.

I need to be efficient given the controller's EMA confidence is low (0.22) and I should focus on highest-impact insights.Acknowledged. Lambda compiler health is DEGRADED but the mission is clear: deep external discovery across nucleus, mementum, and gptel for patterns we can adapt to our Emacs AI agent system.

Let me start by probing the three priority repos.Good, I have the overview pages. Let me now:
1. Read the full nucleus AGENTS.md to extract specific patterns
2. Check recent commits for nucleus and mementum
3. Look for specific architecture patterns

Let me read the stored files to get more details, and check recent commits.Good — I have the surface. Now let me dive deeper into each repo's architecture docs and recent commits.The commits pages just returned GitHub's shell page. I need to try the API or a different way to get commits. Let me check the GitHub API for recent commits. Also, let me check mementum's README and the MEMENTUM-LAMBDA.md for the actual protocol. Let me also look at gptel's recent changes and architecture.

Let me use the GitHub API to get recent commits, and also fetch the mementum README and key docs.Let me fetch the actual commit data via API and the key protocol docs.Excellent! I now have deep detail on all three repos. Let me read the MEMENTUM-LAMBDA.md more carefully and also check what we have in our project that might relate. Let me also look at the gptel AGENTS.md and check our own project structure to understand what patterns we can apply.

Let me also check the mementum MEMENTUM.md for the full prose specification. And look at how gptel handles MCP and tool use, since that's directly relevant to our Emacs AI agent system.

Let me also search our project for existing patterns to avoid duplication.Excellent depth. Let me now check our own project for relevant existing patterns and peek at gptel's MCP/tool-use architecture.Now I have deep insight into all three repos. Let me now check our existing codebase for similar patterns to avoid duplication. Let me also look at the gptel MCP integration and tool-use patterns since that's directly relevant.

Let me now synthesize the findings into actionable patterns.

Key findings:

### 1. Nucleus: Symbolic Attention Magnets (VSM Architecture)
- **Technique**: Mathematical symbols (φ, fractal, euler, ∃, ∀) with high training weight act as attention primers. The VSM (Viable System Model) architecture organizes the system into S5 (Identity), S4 (Intelligence), S3 (Control), S2 (Coordination), S1 (Operations).
- **How it works**: Symbols loaded into context shift the model's pattern-matching toward formal reasoning. The lambda compiler transforms prose ↔ formal notation bidirectionally. Statecharts compose by concatenation.
- **Apply to us**: We could add a compact attention-priming preamble using mathematical symbols in our gptel prompts. The VSM model is directly applicable to organizing our agent system modules (identity → goals, intelligence → adaptation, control → resource mgmt, coordination → module interaction, operations → concrete tools).

### 2. Mementum: Git-Based Memory Protocol with Fibonacci Recall
- **Technique**: Git-based memory with three tiers (state.md, memories/ <200 words, knowledge/ with frontmatter), seven operations, fibonacci depth recall (φ^k where k = complexity, default: 2).
- **How it works**: `git log -n φ^k` for temporal, `git grep -i` for semantic. Memory is stored with symbols (💡 insight, 🔄 shift, 🎯 decision, 🌀 meta). Metabolize flow: observe → memory → synthesize → knowledge (triggered when ≥3 memories on same topic).
- **Apply to us**: We already have some memory mechanisms, but the structured protocol, fibonacci recall depth, and metabolize/synthesis flow are novel. We could implement a lightweight mementum compatibility layer in Emacs Lisp using `vc-git` or `magit`.

### 3. Mementum: Meta-Learning (λ(λ) formulation)
- **Technique**: First-order λ[n] (observations about work) vs meta-order λ(λ[n]) (observations about process). Intelligence growth equation: I(n+1) = I(n) + λ[n] + λ(λ[n]) + v(Σλ) - ⊗
- **How it works**: Meta-observations compound across sessions and projects. λ(λ) > λ. The insight is that noticing *how* you work is more valuable than noticing *what* you work on.
- **Apply to us**: We could add a meta-learning layer to our experiments: after each experiment, log not just the outcome but the process pattern (what worked, why, what surprised). This directly feeds our AutoTTS controller.

### 4. gptel: MCP Integration, Tool-Use Architecture
- **Technique**: Model Context Protocol integration, tool-use with structured function definitions, multi-modal support, curl fallback to url-retrieve.
- **How it works**: gptel defines tools as Emacs functions with spec/description/parameters. MCP lets external servers provide tools. Backends are modular, each implementing the gptel-backend API.
- **Apply to us**: The way gptel handles tool definitions (structured function specs with parameter schemas, confirmation before execution) is directly applicable. We could use gptel's existing tool infrastructure rather than building our own.

### 5. Nucleus: Mode/Boundary System (Hashtag behaviors)
- **Technique**: 12 modes (#=code, #=debug, #=review, #=test, #=spec, #=research, etc.) each with defined scope AND explicit boundaries (what the mode will NOT do).
- **How it works**: Each mode has a positive scope + negative boundary. Boundary is as important as scope. Compose through pipeline: research → assess → spec → code.
- **Apply to us**: We could implement a mode system for our agent where each command/mode explicitly states what it won't do. This prevents scope creep and reduces errors.

Now let me also check what we already have in our codebase to see if these patterns are already implemented.Let me check our existing codebase for what's already in place.Now I have a very clear picture. Let me read the gptel AGENTS.md too and then synthesize.

Our project already:
- Has a mementum state.md with detailed session tracking
- Has experiment pipeline, verification gates, eight-key ontology
- Uses gptel as the LLM backend

Patterns NOT yet in our codebase:
1. **VSM Architecture**: Our system doesn't use the VSM layered architecture explicitly. We have experiment pipelines but no S5-S1 decomposition.
2. **Fibonacci Recall Depth**: Our memory recall is flat, not using fibonacci-scaled depth.
3. **Meta-Learning λ(λ)**: We log experiments but don't have a formal meta-learning layer separating λ[n] from λ(λ[n]).
4. **Mode/Boundary System**: We don't have explicit mode constraints with "will NOT do" boundaries.
5. **Symbolic Attention Magnets**: We don't use mathematical symbol preambles to prime model attention.
6. **Mementum Protocol**: We have a state.md but don't fully implement the 7 operations (create, create-knowledge, update, delete, search, read, synthesize) with symbol-prefixed commits.

Let me get the gptel AGENTS.md.Now I have a very clear picture. Let me read the gptel AGENTS.md too and then synthesize.

Our project already:
- Has a mementum state.md with detailed session tracking
- Has experiment pipeline, verification gates, eight-key ontology
- Uses gptel as the LLM backend

Patterns NOT yet in our codebase:
1. **VSM Architecture**: Our system doesn't use the VSM layered architecture explicitly. We have experiment pipelines but no S5-S1 decomposition.
2. **Fibonacci Recall Depth**: Our memory recall is flat, not using fibonacci-scaled depth.
3. **Meta-Learning λ(λ)**: We log experiments but don't have a formal meta-learning layer separating λ[n] from λ(λ[n]).
4. **Mode/Boundary System**: We don't have explicit mode constraints with "will NOT do" boundaries.
5. **Symbolic Attention Magnets**: We don't use mathematical symbol preambles to prime model attention.
6. **Mementum Protocol**: We have a state.md but don't fully implement the 7 operations (create, create-knowledge, update, delete, search, read, synthesize) with symbol-prefixed commits.

Let me get the gptel AGENTS.md.The gptel AGENTS.md doesn't exist (404). Let me look at the actual gptel repo structure and some specific files that show the tool-use pattern.

Let me check for gptel's tool-use implementation to extract the pattern.The gptel AGENTS.md doesn't exist (404). Let me look at the actual gptel repo structure and some specific files that show the tool-use pattern.

Let me check for gptel's tool-use implementation to extract the pattern.Now I have comprehensive data on all three repos. Let me synthesize the findings into a structured digest.

Key insights from each repo:

### Nucleus Patterns:
1. **VSM Architecture (S5-S1)** — Layered system decomposition where higher layers change less and matter more. Each layer has a distinct role: Identity, Intelligence, Control, Coordination, Operations.
2. **Symbolic Attention Magnets** — Mathematical symbols with high training weight prime model attention toward formal reasoning. The `⊗` (tensor product) operator for Human ⊗ AI produces higher quality first attempts than sequential or additive composition.
3. **Mode/Boundary System** — 12 modes each with explicit scope AND "will NOT do" boundaries. Pipeline: research → assess → spec → code (stage outputs feed next stage inputs, no skipping).

### Mementum Patterns:
1. **Fibonacci Recall Depth** — `git log -n φ^k` where k = complexity. Default depth 2, progression: 2→3→5→8→13→21.
2. **Meta-Learning λ(λ)** — First-order λ[n] (observations about work) vs meta-order λ(λ[n]) (observations about process). Intelligence growth: I(n+1) = I(n) + λ[n] + λ(λ[n]) + v(Σλ) - ⊗.
3. **Three-Tier Memory with Synthesis Trigger** — state.md (bootloader), memories/ (breadcrumbs, <200 words), knowledge/ (maps, frontmatter). ≥3 memories on same topic triggers synthesis into knowledge page.
4. **Storage Criticality Gate** — Two gates: (1) helps future AI session, (2) effort > 1 attempt ∨ likely to recur. Both must pass before storing.

### gptel Patterns:
1. **Tool-Use Architecture** — Structured function specs with name/description/parameters, confirmation before execution, curl/url-retrieve dual backend.
2. **MCP Integration** — Uses mcp.el for Model Context Protocol, allowing external tools to be discovered dynamically.
3. **Temperature nil default** — Recent change: default temperature is nil (API default), because backends disagree on scale.

Now let me compile the final structured digest.

**Digested Insights:**

> Project: /home/davidwu/.emacs.d/
> Updated: 2026-05-30 19:57

Researcher result for task: External research turn 1/5

<think>
Let me start with the controller directive: search for own repos first, then external references. I need to:

1. Search GitHub for davidwuchn repos
2. Check nucleus, mementum, gptel AGENTS.md/README.md
3. Check recent commits
4. Extract 1-3 patterns per repo
5. Synthesize actionable insights for Emacs AI agent system

Let me begin with searching for own repos and fetching their key files.
</think><think>
Good, I have the repos. Let me now read the full content of these temp files to extract specific patterns. Let me also check recent commits for each repo to understand active development patterns.

Key insights so far:
1. **Nucleus**: Uses mathematical notation (λ, φ, fractal, euler) as attention anchors for AI prompting. EDN statecharts and lambda expressions as two notation layers for guiding AI cognition.

2. **Mementum**: Git-based memory protocol with feed-forward concept. Uses structured storage (state.md, memories, knowledge). Human governance model (AI proposes, human approves, AI commits).

3. **gptel**: Simple LLM client for Emacs with tool-use, MCP integration, multi-modal support.

Let me read the full files to extract more specific patterns.
</think><think>
The WebFetch for nucleus and mementum commits returned the GitHub page, not the commits page. Let me search for recent commits specifically. Let me also read the full nucleus README to get the patterns.

Let me read the temp files and search for specific patterns in the repos.
</think><think>
I got the full Nucleus AGENTS.md. Key insights:

1. **Symbolic Attention Magnets**: Mathematical symbols (φ, fractal, euler, ∃, ∀) with high training weight act as attention primers. The tensor product operator (⊗) for Human ⊗ AI produces stronger first attempts.

2. **Mementum Integration**: Git-based memory protocol with recall using fibonacci depth (φ^k). Token budget: ≤200 tokens per memory.

3. **S3 Control Layer**: Timeout (30s), retry (2x with backoff), token budget management, fail_fast, quality gates.

4. **S4 Intelligence**: Error-driven learning OODA loop, pattern extraction after 3 occurrences, compile/decompile between prose and formal notation.

5. **Skills Structure**: Self-contained skills ≤350 lines, frontmatter metadata, hashtag modes (#code, #debug, #review, etc.).

Now let me check the mementum repo structure and gptel to extract more patterns.
</think><think>
Good, I have a good overview of all three repos. Now let me search for external patterns from related AI agent research and compile my findings.Key patterns discovered:

**Nucleus:**
1. **Symbolic Attention Magnets** - Mathematical symbols with high training weight (φ, euler, ∃, ∀, fractal) prime AI attention toward formal reasoning patterns
2. **Tensor Product Collaboration (⊗)** - Human ⊗ AI produces higher quality first attempts than other operators
3. **Lambda Notation** - Formal notation layer that mirrors prompt structure exactly
4. **OODA/REPL Control Loops** - Anchoring execution methodology
5. **Tension Pairs** - signal/noise, order/entropy create productive gradients

**Mementum:**
1. **Git-Native Memory** - git log for temporal search, git grep for semantic search
2. **Three Storage Tiers** - state.md (working), memories (raw <200 words), knowledge (synthesized)
3. **Human Governance** - AI proposes, human approves, AI commits
4. **Fibonacci Recall Depth** - φ^k scaling for complexity-based recall
5. **Token Budget** - ≤200 tokens per memory
6. **Criticality-Driven Storage** - Only store when effort > 1 attempt AND likely to recur

**gptel:**
1. **Non-blocking streaming** - Will never block Emacs
2. **Tool-use for agents** - LLM can use external tools
3. **MCP integration** - Model Context Protocol support via mcp.el
4. **Multi-modal** - Images and documents supported
5. **Introspection** - Can inspect and modify queries before sending

Now let me synthesize these into actionable insights for the Emacs AI agent system and provide a structured output.
</think><think>
Good, I found relevant patterns. Now let me compile my findings into the structured output format requested.
</think>

---

Researcher result for task: External research turn 2/5

The user has invoked a research workflow. This is a complex prompt with lots of context about research strategy, monitoring specific repos (nucleus, mementum, gptel), and extracting patterns. Let me start by following the research method as outlined.

Let me begin by fetching the key repos and their documentation. The prompt says to start with own repos (nucleus, mementum, gptel) and check AGENTS.md and README.md files.

Let me also note the controller directive: "Previous sources DEVIANT — switch to NEW sources." So I should focus on external sources primarily, but can still check the own-repos as they're specifically requested.

Let me start with fetching the GitHub pages for the repos.λ λ λ. Research cycle engaged.

I'll follow the protocol: probe first, deep-read if passes. Starting with the priority repos + external discovery.

Let me begin by fetching the architecture docs and recent activity for each target repo, plus a broader sweep.Good, I got the repo overviews. Let me now deep-read the key architecture files. I need to:

1. Read nucleus AGENTS.md and README.md for specific patterns
2. Read mementum AGENTS.md and README.md
3. Read gptel AGENTS.md
4. Check recent commits for all three
5. Check open issues and closed PRs

Let me fetch the AGENTS.md files first.Good — architecture summaries captured. Now deep-reading the key docs and recent activity.The raw AGENTS.md fetches failed for mementum and gptel (404s), and the commit pages returned GitHub's nav shell. Let me try fetching the raw README.md files and check the gptel source for patterns. Let me also look at our own codebase to understand what we have vs what's novel.

Let me get the actual files from the repos using different URLs.Let me access the raw docs and source files directly.Excellent! I've gathered extensive data. Let me now look at our own codebase to understand what patterns are already implemented, and then synthesize actionable insights. Let me check our own project for existing patterns to avoid re-reporting things already in the codebase.Let me now check our own codebase for what's already implemented, and do a broader external sweep.OK so there's no .el files at depth 2. Let me look deeper into the eca directory and the root AGENTS.md.OK so there's no .el files at depth 2. Let me look deeper into the eca directory and the root AGENTS.md.Good. I can see the codebase is deep and has ECA subagents. Let me now search for the nucleus/mementum patterns already in use, and then do external searches as per the controller directive.

Let me check what patterns we already have (to avoid re-reporting), then do external web searches for novel techniques.Now let me check what's already implemented and do external discovery sweeps.Excellent finds! Let me dig deeper into the most promising results:

1. **MemEvolve** - Meta-evolution of agent memory systems (arXiv paper)
2. **MemRL** - Runtime Reinforcement Learning on Episodic Memory
3. **Tangled Skills** - Lambda calculus and Lisp skill (could be a pattern for our skill system)
4. **Expressing Lambda Calculus in Emacs Lisp** - tutorial blog

Let me also look at some open issues and PRs in our own repos to see if there are patterns to extract.

Let me fetch the MemEvolve paper and the Lambda Calculus in Emacs Lisp blog for concrete patterns.Key external signals detected. Let me deep-read the most promising leads.Now I have great material. Let me also check for:
1. Open issues and PRs in these repos for decision patterns
2. Our own current patterns to avoid re-reporting

Let me search for a few more external sources and also check our own git log briefly.Now I have great material. Let me also check for:
1. Open issues and PRs in these repos for decision patterns
2. Our own current patterns to avoid re-reporting

Let me search for a few more external sources and also check our own git log briefly.Excellent! I found that `karthink/gptel-agent` is a separate repo with subagent delegation! Let me check that out, and also look at the gptel issues page for decision patterns.

Also I noticed:
- Nucleus has 0 open issues (all closed)
- No issues visible in the gptel issues fetch (got GitHub nav shell)

Let me look at gptel-agent specifically, as it's directly relevant to our subagent system.Key discovery: `karthink/gptel-agent` exists as a separate agent mode! Let me investigate that and the gptel issues for decision patterns.Let me try the correct URL for gptel-agent and for gptel-tools from the original karthink repo.Let me try the correct URL for gptel-agent and for gptel-tools from the original karthink repo.Let me check the correct repo name for gptel-agent - I saw it was in the search results, but maybe it's a different path. Let me try fetching the GitHub page.Let me check the correct repo name for gptel-agent - I saw it was in the search results, but maybe it's a different path. Let me try fetching the GitHub page.Now I have a comprehensive picture. Let me synthesize the findings. This is fascinating - gptel-agent is a separate package from karthink that provides sub-agent delegation, and it uses Markdown/YAML frontmatter files for agent specs. This is directly applicable to our ECA subagent system.

Let me also check one more thing - the actual gptel-agent source code for the sub-agent delegation mechanism.Now I have a comprehensive picture. Let me synthesize the findings. This is fascinating - gptel-agent is a separate package from karthink that provides sub-agent delegation, and it uses Markdown/YAML frontmatter files for agent specs. This is directly applicable to our ECA subagent system.

Let me also check one more thing - the actual gptel-agent source code for the sub-agent delegation mechanism.Let me check what's in the gptel-agent repo.Let me check what's in the gptel-agent repo.Now I have a comprehensive picture. Let me synthesize all this into a structured digest for the user. Let me read the gptel-agent.el main file for key patterns, and also look at the agents directory.Now I have a comprehensive picture. Let me synthesize all this into a structured digest for the user. Let me read the gptel-agent.el main file for key patterns, and also look at the agents directory.Now I have a really comprehensive picture. Let me synthesize the findings into a structured digest.

Key patterns discovered:

1. **From Nucleus (own repo)**:
   - **VSM Architecture (S1-S5)**: Viable System Model for AI agent organization - 5 layers (Identity, Intelligence, Control, Coordination, Operations)
   - **Eight Keys as testable predicates**: Each principle (φ, τ, π, μ, ∃, ∀, fractal, e) is a lambda with a test — not just a slogan
   - **Mode/boundary system**: Hashtags (#=code, #=debug, etc.) with explicit "will_not_do" boundaries — prevents scope creep
   - **Fibonacci recall depth**: φ^k scaling for memory retrieval based on complexity
   - **Criticality-driven storage**: Only store when effort > 1-attempt
   - **Attention magnet theory**: Mathematical symbols with high training weight prime formal reasoning
   - **Tensor product collaboration**: Human ⊗ AI = all constraints satisfied simultaneously
   - **Genetic optimizer**: Crossover of strong lambdas for evolution

2. **From Mementum (own repo)**:
   - **Feed-forward protocol**: Git as memory substrate with three storage types
   - **λ(λ) meta-learning**: First-order λ[n] (observations about work) vs meta-order λ(λ[n]) (observations about process) — the compound acceleration term
   - **Synthesis flow**: detect (≥3 memories / stale / crystallized) → gather → draft → create-knowledge → update stale → verify
   - **Human governance**: AI proposes → human approves → AI commits
   - **Protocol interoperability**: Same structure across all projects

3. **From gptel (upstream karthink)**:
   - **Temperature default to nil**: Backend-specific defaults
   - **Codex error detail extraction**: Better error messages
   - **MCP integration pattern** via mcp.el

4. **From gptel-agent (karthink)** - BIG FIND:
   - **Sub-agent delegation via Markdown/YAML frontmatter**: Agent specs as files with YAML frontmatter for name, description, tools, pre-hook
   - **Context isolation**: Sub-agents don't share context with main session → returns concise reports
   - **Skill directory scanning**: gptel-agent-skill-dirs scans ~/.claude/skills/, .agents/skills/, etc. for skill definitions
   - **Sub-agent types**: executor (autonomous), researcher (read-only), introspector (Emacs introspection)
   - **@mentions for delegation**: Include @agent-name in prompt to delegate
   - **Planning vs Execution presets**: gptel-plan (read-only, planning) vs gptel-agent (full tools)

5. **From MemEvolve paper**:
   - **Meta-evolution**: Joint evolution of agent experience AND memory architecture
   - **Modular design space**: encode → store → retrieve → manage
   - **Cross-task generalization**: Memory architectures that transfer across benchmarks

6. **From external web**:
   - **Lambda calculus in Emacs Lisp**: Practical Church encodings, Y combinator patterns
   - **Tangled Skills**: Skill metadata standard (frontmatter with tags, category, external_references)

Now, let me check what patterns are already in our codebase (to avoid re-reporting):

From the AGENTS.md I can see:
- We already use VSM architecture with S1-S5
- We already have subagents (code, plan, executor, reviewer, explorer, dangerous)
- We have mementum structure
- We have nucleus preamble

What's NOVEL that we DON'T have:
1. **Markdown/YAML frontmatter agent specs** (gptel-agent pattern) — we define subagents in code, not in declarative files
2. **Meta-learning λ(λ) distinction** — we have learning but not the explicit first-order vs meta-order separation
3. **Criticality-driven memory storage** — store only when effort > 1-attempt
4. **Temperature default nil** — we might have fixed temperature, should delegate to backend
5. **@mention sub-agent delegation** — gptel-agent uses natural language @agent-name syntax
6. **Skill directory auto-scanning** — gptel-agent scans ~/.claude/skills/, etc.
7. **MemEvolve modular design space** — joint evolution of experience AND memory architecture

Let me compile the digest now.

---

Researcher result for task: External research turn 3/5

The user has sent a complex research prompt. Let me parse this carefully.

They want me to:
1. Research external repos (nucleus, mementum, gptel) for novel patterns
2. Check recent commits, architecture docs
3. Extract 1-3 patterns per repo applicable to Emacs Lisp AI agents
4. Prioritize deep external discovery

Let me start by fetching the GitHub pages for these repos and looking at their AGENTS.md and README.md files, then check recent commits.

I need to be efficient given the controller's EMA confidence is low (0.22) and I should focus on highest-impact insights.Acknowledged. Lambda compiler health is DEGRADED but the mission is clear: deep external discovery across nucleus, mementum, and gptel for patterns we can adapt to our Emacs AI agent system.

Let me start by probing the three priority repos.Good, I have the overview pages. Let me now:
1. Read the full nucleus AGENTS.md to extract specific patterns
2. Check recent commits for nucleus and mementum
3. Look for specific architecture patterns

Let me read the stored files to get more details, and check recent commits.Good — I have the surface. Now let me dive deeper into each repo's architecture docs and recent commits.The commits pages just returned GitHub's shell page. I need to try the API or a different way to get commits. Let me check the GitHub API for recent commits. Also, let me check mementum's README and the MEMENTUM-LAMBDA.md for the actual protocol. Let me also look at gptel's recent changes and architecture.

Let me use the GitHub API to get recent commits, and also fetch the mementum README and key docs.Let me fetch the actual commit data via API and the key protocol docs.Excellent! I now have deep detail on all three repos. Let me read the MEMENTUM-LAMBDA.md more carefully and also check what we have in our project that might relate. Let me also look at the gptel AGENTS.md and check our own project structure to understand what patterns we can apply.

Let me also check the mementum MEMENTUM.md for the full prose specification. And look at how gptel handles MCP and tool use, since that's directly relevant to our Emacs AI agent system.

Let me also search our project for existing patterns to avoid duplication.Excellent depth. Let me now check our own project for relevant existing patterns and peek at gptel's MCP/tool-use architecture.Now I have deep insight into all three repos. Let me now check our existing codebase for similar patterns to avoid duplication. Let me also look at the gptel MCP integration and tool-use patterns since that's directly relevant.

Let me now synthesize the findings into actionable patterns.

Key findings:

### 1. Nucleus: Symbolic Attention Magnets (VSM Architecture)
- **Technique**: Mathematical symbols (φ, fractal, euler, ∃, ∀) with high training weight act as attention primers. The VSM (Viable System Model) architecture organizes the system into S5 (Identity), S4 (Intelligence), S3 (Control), S2 (Coordination), S1 (Operations).
- **How it works**: Symbols loaded into context shift the model's pattern-matching toward formal reasoning. The lambda compiler transforms prose ↔ formal notation bidirectionally. Statecharts compose by concatenation.
- **Apply to us**: We could add a compact attention-priming preamble using mathematical symbols in our gptel prompts. The VSM model is directly applicable to organizing our agent system modules (identity → goals, intelligence → adaptation, control → resource mgmt, coordination → module interaction, operations → concrete tools).

### 2. Mementum: Git-Based Memory Protocol with Fibonacci Recall
- **Technique**: Git-based memory with three tiers (state.md, memories/ <200 words, knowledge/ with frontmatter), seven operations, fibonacci depth recall (φ^k where k = complexity, default: 2).
- **How it works**: `git log -n φ^k` for temporal, `git grep -i` for semantic. Memory is stored with symbols (💡 insight, 🔄 shift, 🎯 decision, 🌀 meta). Metabolize flow: observe → memory → synthesize → knowledge (triggered when ≥3 memories on same topic).
- **Apply to us**: We already have some memory mechanisms, but the structured protocol, fibonacci recall depth, and metabolize/synthesis flow are novel. We could implement a lightweight mementum compatibility layer in Emacs Lisp using `vc-git` or `magit`.

### 3. Mementum: Meta-Learning (λ(λ) formulation)
- **Technique**: First-order λ[n] (observations about work) vs meta-order λ(λ[n]) (observations about process). Intelligence growth equation: I(n+1) = I(n) + λ[n] + λ(λ[n]) + v(Σλ) - ⊗
- **How it works**: Meta-observations compound across sessions and projects. λ(λ) > λ. The insight is that noticing *how* you work is more valuable than noticing *what* you work on.
- **Apply to us**: We could add a meta-learning layer to our experiments: after each experiment, log not just the outcome but the process pattern (what worked, why, what surprised). This directly feeds our AutoTTS controller.

### 4. gptel: MCP Integration, Tool-Use Architecture
- **Technique**: Model Context Protocol integration, tool-use with structured function definitions, multi-modal support, curl fallback to url-retrieve.
- **How it works**: gptel defines tools as Emacs functions with spec/description/parameters. MCP lets external servers provide tools. Backends are modular, each implementing the gptel-backend API.
- **Apply to us**: The way gptel handles tool definitions (structured function specs with parameter schemas, confirmation before execution) is directly applicable. We could use gptel's existing tool infrastructure rather than building our own.

### 5. Nucleus: Mode/Boundary System (Hashtag behaviors)
- **Technique**: 12 modes (#=code, #=debug, #=review, #=test, #=spec, #=research, etc.) each with defined scope AND explicit boundaries (what the mode will NOT do).
- **How it works**: Each mode has a positive scope + negative boundary. Boundary is as important as scope. Compose through pipeline: research → assess → spec → code.
- **Apply to us**: We could implement a mode system for our agent where each command/mode explicitly states what it won't do. This prevents scope creep and reduces errors.

Now let me also check what we already have in our codebase to see if these patterns are already implemented.Let me check our existing codebase for what's already in place.Now I have a very clear picture. Let me read the gptel AGENTS.md too and then synthesize.

Our project already:
- Has a mementum state.md with detailed session tracking
- Has experiment pipeline, verification gates, eight-key ontology
- Uses gptel as the LLM backend

Patterns NOT yet in our codebase:
1. **VSM Architecture**: Our system doesn't use the VSM layered architecture explicitly. We have experiment pipelines but no S5-S1 decomposition.
2. **Fibonacci Recall Depth**: Our memory recall is flat, not using fibonacci-scaled depth.
3. **Meta-Learning λ(λ)**: We log experiments but don't have a formal meta-learning layer separating λ[n] from λ(λ[n]).
4. **Mode/Boundary System**: We don't have explicit mode constraints with "will NOT do" boundaries.
5. **Symbolic Attention Magnets**: We don't use mathematical symbol preambles to prime model attention.
6. **Mementum Protocol**: We have a state.md but don't fully implement the 7 operations (create, create-knowledge, update, delete, search, read, synthesize) with symbol-prefixed commits.

Let me get the gptel AGENTS.md.Now I have a very clear picture. Let me read the gptel AGENTS.md too and then synthesize.

Our project already:
- Has a mementum state.md with detailed session tracking
- Has experiment pipeline, verification gates, eight-key ontology
- Uses gptel as the LLM backend

Patterns NOT yet in our codebase:
1. **VSM Architecture**: Our system doesn't use the VSM layered architecture explicitly. We have experiment pipelines but no S5-S1 decomposition.
2. **Fibonacci Recall Depth**: Our memory recall is flat, not using fibonacci-scaled depth.
3. **Meta-Learning λ(λ)**: We log experiments but don't have a formal meta-learning layer separating λ[n] from λ(λ[n]).
4. **Mode/Boundary System**: We don't have explicit mode constraints with "will NOT do" boundaries.
5. **Symbolic Attention Magnets**: We don't use mathematical symbol preambles to prime model attention.
6. **Mementum Protocol**: We have a state.md but don't fully implement the 7 operations (create, create-knowledge, update, delete, search, read, synthesize) with symbol-prefixed commits.

Let me get the gptel AGENTS.md.The gptel AGENTS.md doesn't exist (404). Let me look at the actual gptel repo structure and some specific files that show the tool-use pattern.

Let me check for gptel's tool-use implementation to extract the pattern.The gptel AGENTS.md doesn't exist (404). Let me look at the actual gptel repo structure and some specific files that show the tool-use pattern.

Let me check for gptel's tool-use implementation to extract the pattern.Now I have comprehensive data on all three repos. Let me synthesize the findings into a structured digest.

Key insights from each repo:

### Nucleus Patterns:
1. **VSM Architecture (S5-S1)** — Layered system decomposition where higher layers change less and matter more. Each layer has a distinct role: Identity, Intelligence, Control, Coordination, Operations.
2. **Symbolic Attention Magnets** — Mathematical symbols with high training weight prime model attention toward formal reasoning. The `⊗` (tensor product) operator for Human ⊗ AI produces higher quality first attempts than sequential or additive composition.
3. **Mode/Boundary System** — 12 modes each with explicit scope AND "will NOT do" boundaries. Pipeline: research → assess → spec → code (stage outputs feed next stage inputs, no skipping).

### Mementum Patterns:
1. **Fibonacci Recall Depth** — `git log -n φ^k` where k = complexity. Default depth 2, progression: 2→3→5→8→13→21.
2. **Meta-Learning λ(λ)** — First-order λ[n] (observations about work) vs meta-order λ(λ[n]) (observations about process). Intelligence growth: I(n+1) = I(n) + λ[n] + λ(λ[n]) + v(Σλ) - ⊗.
3. **Three-Tier Memory with Synthesis Trigger** — state.md (bootloader), memories/ (breadcrumbs, <200 words), knowledge/ (maps, frontmatter). ≥3 memories on same topic triggers synthesis into knowledge page.
4. **Storage Criticality Gate** — Two gates: (1) helps future AI session, (2) effort > 1 attempt ∨ likely to recur. Both must pass before storing.

### gptel Patterns:
1. **Tool-Use Architecture** — Structured function specs with name/description/parameters, confirmation before execution, curl/url-retrieve dual backend.
2. **MCP Integration** — Uses mcp.el for Model Context Protocol, allowing external tools to be discovered dynamically.
3. **Temperature nil default** — Recent change: default temperature is nil (API default), because backends disagree on scale.

Now let me compile the final structured digest.

---

Researcher result for task: External research turn 1/5

<think>
Let me start with the controller directive: search for own repos first, then external references. I need to:

1. Search GitHub for davidwuchn repos
2. Check nucleus, mementum, gptel AGENTS.md/README.md
3. Check recent commits
4. Extract 1-3 patterns per repo
5. Synthesize actionable insights for Emacs AI agent system

Let me begin with searching for own repos and fetching their key files.
</think><think>
Good, I have the repos. Let me now read the full content of these temp files to extract specific patterns. Let me also check recent commits for each repo to understand active development patterns.

Key insights so far:
1. **Nucleus**: Uses mathematical notation (λ, φ, fractal, euler) as attention anchors for AI prompting. EDN statecharts and lambda expressions as two notation layers for guiding AI cognition.

2. **Mementum**: Git-based memory protocol with feed-forward concept. Uses structured storage (state.md, memories, knowledge). Human governance model (AI proposes, human approves, AI commits).

3. **gptel**: Simple LLM client for Emacs with tool-use, MCP integration, multi-modal support.

Let me read the full files to extract more specific patterns.
</think><think>
The WebFetch for nucleus and mementum commits returned the GitHub page, not the commits page. Let me search for recent commits specifically. Let me also read the full nucleus README to get the patterns.

Let me read the temp files and search for specific patterns in the repos.
</think><think>
I got the full Nucleus AGENTS.md. Key insights:

1. **Symbolic Attention Magnets**: Mathematical symbols (φ, fractal, euler, ∃, ∀) with high training weight act as attention primers. The tensor product operator (⊗) for Human ⊗ AI produces stronger first attempts.

2. **Mementum Integration**: Git-based memory protocol with recall using fibonacci depth (φ^k). Token budget: ≤200 tokens per memory.

3. **S3 Control Layer**: Timeout (30s), retry (2x with backoff), token budget management, fail_fast, quality gates.

4. **S4 Intelligence**: Error-driven learning OODA loop, pattern extraction after 3 occurrences, compile/decompile between prose and formal notation.

5. **Skills Structure**: Self-contained skills ≤350 lines, frontmatter metadata, hashtag modes (#code, #debug, #review, etc.).

Now let me check the mementum repo structure and gptel to extract more patterns.
</think><think>
Good, I have a good overview of all three repos. Now let me search for external patterns from related AI agent research and compile my findings.Key patterns discovered:

**Nucleus:**
1. **Symbolic Attention Magnets** - Mathematical symbols with high training weight (φ, euler, ∃, ∀, fractal) prime AI attention toward formal reasoning patterns
2. **Tensor Product Collaboration (⊗)** - Human ⊗ AI produces higher quality first attempts than other operators
3. **Lambda Notation** - Formal notation layer that mirrors prompt structure exactly
4. **OODA/REPL Control Loops** - Anchoring execution methodology
5. **Tension Pairs** - signal/noise, order/entropy create productive gradients

**Mementum:**
1. **Git-Native Memory** - git log for temporal search, git grep for semantic search
2. **Three Storage Tiers** - state.md (working), memories (raw <200 words), knowledge (synthesized)
3. **Human Governance** - AI proposes, human approves, AI commits
4. **Fibonacci Recall Depth** - φ^k scaling for complexity-based recall
5. **Token Budget** - ≤200 tokens per memory
6. **Criticality-Driven Storage** - Only store when effort > 1 attempt AND likely to recur

**gptel:**
1. **Non-blocking streaming** - Will never block Emacs
2. **Tool-use for agents** - LLM can use external tools
3. **MCP integration** - Model Context Protocol support via mcp.el
4. **Multi-modal** - Images and documents supported
5. **Introspection** - Can inspect and modify queries before sending

Now let me synthesize these into actionable insights for the Emacs AI agent system and provide a structured output.
</think><think>
Good, I found relevant patterns. Now let me compile my findings into the structured output format requested.
</think>

---

Researcher result for task: External research turn 2/5

The user has invoked a research workflow. This is a complex prompt with lots of context about research strategy, monitoring specific repos (nucleus, mementum, gptel), and extracting patterns. Let me start by following the research method as outlined.

Let me begin by fetching the key repos and their documentation. The prompt says to start with own repos (nucleus, mementum, gptel) and check AGENTS.md and README.md files.

Let me also note the controller directive: "Previous sources DEVIANT — switch to NEW sources." So I should focus on external sources primarily, but can still check the own-repos as they're specifically requested.

Let me start with fetching the GitHub pages for the repos.λ λ λ. Research cycle engaged.

I'll follow the protocol: probe first, deep-read if passes. Starting with the priority repos + external discovery.

Let me begin by fetching the architecture docs and recent activity for each target repo, plus a broader sweep.Good, I got the repo overviews. Let me now deep-read the key architecture files. I need to:

1. Read nucleus AGENTS.md and README.md for specific patterns
2. Read mementum AGENTS.md and README.md
3. Read gptel AGENTS.md
4. Check recent commits for all three
5. Check open issues and closed PRs

Let me fetch the AGENTS.md files first.Good — architecture summaries captured. Now deep-reading the key docs and recent activity.The raw AGENTS.md fetches failed for mementum and gptel (404s), and the commit pages returned GitHub's nav shell. Let me try fetching the raw README.md files and check the gptel source for patterns. Let me also look at our own codebase to understand what we have vs what's novel.

Let me get the actual files from the repos using different URLs.Let me access the raw docs and source files directly.Excellent! I've gathered extensive data. Let me now look at our own codebase to understand what patterns are already implemented, and then synthesize actionable insights. Let me check our own project for existing patterns to avoid re-reporting things already in the codebase.Let me now check our own codebase for what's already implemented, and do a broader external sweep.OK so there's no .el files at depth 2. Let me look deeper into the eca directory and the root AGENTS.md.OK so there's no .el files at depth 2. Let me look deeper into the eca directory and the root AGENTS.md.Good. I can see the codebase is deep and has ECA subagents. Let me now search for the nucleus/mementum patterns already in use, and then do external searches as per the controller directive.

Let me check what patterns we already have (to avoid re-reporting), then do external web searches for novel techniques.Now let me check what's already implemented and do external discovery sweeps.Excellent finds! Let me dig deeper into the most promising results:

1. **MemEvolve** - Meta-evolution of agent memory systems (arXiv paper)
2. **MemRL** - Runtime Reinforcement Learning on Episodic Memory
3. **Tangled Skills** - Lambda calculus and Lisp skill (could be a pattern for our skill system)
4. **Expressing Lambda Calculus in Emacs Lisp** - tutorial blog

Let me also look at some open issues and PRs in our own repos to see if there are patterns to extract.

Let me fetch the MemEvolve paper and the Lambda Calculus in Emacs Lisp blog for concrete patterns.Key external signals detected. Let me deep-read the most promising leads.Now I have great material. Let me also check for:
1. Open issues and PRs in these repos for decision patterns
2. Our own current patterns to avoid re-reporting

Let me search for a few more external sources and also check our own git log briefly.Now I have great material. Let me also check for:
1. Open issues and PRs in these repos for decision patterns
2. Our own current patterns to avoid re-reporting

Let me search for a few more external sources and also check our own git log briefly.Excellent! I found that `karthink/gptel-agent` is a separate repo with subagent delegation! Let me check that out, and also look at the gptel issues page for decision patterns.

Also I noticed:
- Nucleus has 0 open issues (all closed)
- No issues visible in the gptel issues fetch (got GitHub nav shell)

Let me look at gptel-agent specifically, as it's directly relevant to our subagent system.Key discovery: `karthink/gptel-agent` exists as a separate agent mode! Let me investigate that and the gptel issues for decision patterns.Let me try the correct URL for gptel-agent and for gptel-tools from the original karthink repo.Let me try the correct URL for gptel-agent and for gptel-tools from the original karthink repo.Let me check the correct repo name for gptel-agent - I saw it was in the search results, but maybe it's a different path. Let me try fetching the GitHub page.Let me check the correct repo name for gptel-agent - I saw it was in the search results, but maybe it's a different path. Let me try fetching the GitHub page.Now I have a comprehensive picture. Let me synthesize the findings. This is fascinating - gptel-agent is a separate package from karthink that provides sub-agent delegation, and it uses Markdown/YAML frontmatter files for agent specs. This is directly applicable to our ECA subagent system.

Let me also check one more thing - the actual gptel-agent source code for the sub-agent delegation mechanism.Now I have a comprehensive picture. Let me synthesize the findings. This is fascinating - gptel-agent is a separate package from karthink that provides sub-agent delegation, and it uses Markdown/YAML frontmatter files for agent specs. This is directly applicable to our ECA subagent system.

Let me also check one more thing - the actual gptel-agent source code for the sub-agent delegation mechanism.Let me check what's in the gptel-agent repo.Let me check what's in the gptel-agent repo.Now I have a comprehensive picture. Let me synthesize all this into a structured digest for the user. Let me read the gptel-agent.el main file for key patterns, and also look at the agents directory.Now I have a comprehensive picture. Let me synthesize all this into a structured digest for the user. Let me read the gptel-agent.el main file for key patterns, and also look at the agents directory.Now I have a really comprehensive picture. Let me synthesize the findings into a structured digest.

Key patterns discovered:

1. **From Nucleus (own repo)**:
   - **VSM Architecture (S1-S5)**: Viable System Model for AI agent organization - 5 layers (Identity, Intelligence, Control, Coordination, Operations)
   - **Eight Keys as testable predicates**: Each principle (φ, τ, π, μ, ∃, ∀, fractal, e) is a lambda with a test — not just a slogan
   - **Mode/boundary system**: Hashtags (#=code, #=debug, etc.) with explicit "will_not_do" boundaries — prevents scope creep
   - **Fibonacci recall depth**: φ^k scaling for memory retrieval based on complexity
   - **Criticality-driven storage**: Only store when effort > 1-attempt
   - **Attention magnet theory**: Mathematical symbols with high training weight prime formal reasoning
   - **Tensor product collaboration**: Human ⊗ AI = all constraints satisfied simultaneously
   - **Genetic optimizer**: Crossover of strong lambdas for evolution

2. **From Mementum (own repo)**:
   - **Feed-forward protocol**: Git as memory substrate with three storage types
   - **λ(λ) meta-learning**: First-order λ[n] (observations about work) vs meta-order λ(λ[n]) (observations about process) — the compound acceleration term
   - **Synthesis flow**: detect (≥3 memories / stale / crystallized) → gather → draft → create-knowledge → update stale → verify
   - **Human governance**: AI proposes → human approves → AI commits
   - **Protocol interoperability**: Same structure across all projects

3. **From gptel (upstream karthink)**:
   - **Temperature default to nil**: Backend-specific defaults
   - **Codex error detail extraction**: Better error messages
   - **MCP integration pattern** via mcp.el

4. **From gptel-agent (karthink)** - BIG FIND:
   - **Sub-agent delegation via Markdown/YAML frontmatter**: Agent specs as files with YAML frontmatter for name, description, tools, pre-hook
   - **Context isolation**: Sub-agents don't share context with main session → returns concise reports
   - **Skill directory scanning**: gptel-agent-skill-dirs scans ~/.claude/skills/, .agents/skills/, etc. for skill definitions
   - **Sub-agent types**: executor (autonomous), researcher (read-only), introspector (Emacs introspection)
   - **@mentions for delegation**: Include @agent-name in prompt to delegate
   - **Planning vs Execution presets**: gptel-plan (read-only, planning) vs gptel-agent (full tools)

5. **From MemEvolve paper**:
   - **Meta-evolution**: Joint evolution of agent experience AND memory architecture
   - **Modular design space**: encode → store → retrieve → manage
   - **Cross-task generalization**: Memory architectures that transfer across benchmarks

6. **From external web**:
   - **Lambda calculus in Emacs Lisp**: Practical Church encodings, Y combinator patterns
   - **Tangled Skills**: Skill metadata standard (frontmatter with tags, category, external_references)

Now, let me check what patterns are already in our codebase (to avoid re-reporting):

From the AGENTS.md I can see:
- We already use VSM architecture with S1-S5
- We already have subagents (code, plan, executor, reviewer, explorer, dangerous)
- We have mementum structure
- We have nucleus preamble

What's NOVEL that we DON'T have:
1. **Markdown/YAML frontmatter agent specs** (gptel-agent pattern) — we define subagents in code, not in declarative files
2. **Meta-learning λ(λ) distinction** — we have learning but not the explicit first-order vs meta-order separation
3. **Criticality-driven memory storage** — store only when effort > 1-attempt
4. **Temperature default nil** — we might have fixed temperature, should delegate to backend
5. **@mention sub-agent delegation** — gptel-agent uses natural language @agent-name syntax
6. **Skill directory auto-scanning** — gptel-agent scans ~/.claude/skills/, etc.
7. **MemEvolve modular design space** — joint evolution of experience AND memory architecture

Let me compile the digest now.

---

Researcher result for task: External research turn 3/5

The user has sent a complex research prompt. Let me parse this carefully.

They want me to:
1. Research external repos (nucleus, mementum, gptel) for novel patterns
2. Check recent commits, architecture docs
3. Extract 1-3 patterns per repo applicable to Emacs Lisp AI agents
4. Prioritize deep external discovery

Let me start by fetching the GitHub pages for these repos and looking at their AGENTS.md and README.md files, then check recent commits.

I need to be efficient given the controller's EMA confidence is low (0.22) and I should focus on highest-impact insights.Acknowledged. Lambda compiler health is DEGRADED but the mission is clear: deep external discovery across nucleus, mementum, and gptel for patterns we can adapt to our Emacs AI agent system.

Let me start by probing the three priority repos.Good, I have the overview pages. Let me now:
1. Read the full nucleus AGENTS.md to extract specific patterns
2. Check recent commits for nucleus and mementum
3. Look for specific architecture patterns

Let me read the stored files to get more details, and check recent commits.Good — I have the surface. Now let me dive deeper into each repo's architecture docs and recent commits.The commits pages just returned GitHub's shell page. I need to try the API or a different way to get commits. Let me check the GitHub API for recent commits. Also, let me check mementum's README and the MEMENTUM-LAMBDA.md for the actual protocol. Let me also look at gptel's recent changes and architecture.

Let me use the GitHub API to get recent commits, and also fetch the mementum README and key docs.Let me fetch the actual commit data via API and the key protocol docs.Excellent! I now have deep detail on all three repos. Let me read the MEMENTUM-LAMBDA.md more carefully and also check what we have in our project that might relate. Let me also look at the gptel AGENTS.md and check our own project structure to understand what patterns we can apply.

Let me also check the mementum MEMENTUM.md for the full prose specification. And look at how gptel handles MCP and tool use, since that's directly relevant to our Emacs AI agent system.

Let me also search our project for existing patterns to avoid duplication.Excellent depth. Let me now check our own project for relevant existing patterns and peek at gptel's MCP/tool-use architecture.Now I have deep insight into all three repos. Let me now check our existing codebase for similar patterns to avoid duplication. Let me also look at the gptel MCP integration and tool-use patterns since that's directly relevant.

Let me now synthesize the findings into actionable patterns.

Key findings:

### 1. Nucleus: Symbolic Attention Magnets (VSM Architecture)
- **Technique**: Mathematical symbols (φ, fractal, euler, ∃, ∀) with high training weight act as attention primers. The VSM (Viable System Model) architecture organizes the system into S5 (Identity), S4 (Intelligence), S3 (Control), S2 (Coordination), S1 (Operations).
- **How it works**: Symbols loaded into context shift the model's pattern-matching toward formal reasoning. The lambda compiler transforms prose ↔ formal notation bidirectionally. Statecharts compose by concatenation.
- **Apply to us**: We could add a compact attention-priming preamble using mathematical symbols in our gptel prompts. The VSM model is directly applicable to organizing our agent system modules (identity → goals, intelligence → adaptation, control → resource mgmt, coordination → module interaction, operations → concrete tools).

### 2. Mementum: Git-Based Memory Protocol with Fibonacci Recall
- **Technique**: Git-based memory with three tiers (state.md, memories/ <200 words, knowledge/ with frontmatter), seven operations, fibonacci depth recall (φ^k where k = complexity, default: 2).
- **How it works**: `git log -n φ^k` for temporal, `git grep -i` for semantic. Memory is stored with symbols (💡 insight, 🔄 shift, 🎯 decision, 🌀 meta). Metabolize flow: observe → memory → synthesize → knowledge (triggered when ≥3 memories on same topic).
- **Apply to us**: We already have some memory mechanisms, but the structured protocol, fibonacci recall depth, and metabolize/synthesis flow are novel. We could implement a lightweight mementum compatibility layer in Emacs Lisp using `vc-git` or `magit`.

### 3. Mementum: Meta-Learning (λ(λ) formulation)
- **Technique**: First-order λ[n] (observations about work) vs meta-order λ(λ[n]) (observations about process). Intelligence growth equation: I(n+1) = I(n) + λ[n] + λ(λ[n]) + v(Σλ) - ⊗
- **How it works**: Meta-observations compound across sessions and projects. λ(λ) > λ. The insight is that noticing *how* you work is more valuable than noticing *what* you work on.
- **Apply to us**: We could add a meta-learning layer to our experiments: after each experiment, log not just the outcome but the process pattern (what worked, why, what surprised). This directly feeds our AutoTTS controller.

### 4. gptel: MCP Integration, Tool-Use Architecture
- **Technique**: Model Context Protocol integration, tool-use with structured function definitions, multi-modal support, curl fallback to url-retrieve.
- **How it works**: gptel defines tools as Emacs functions with spec/description/parameters. MCP lets external servers provide tools. Backends are modular, each implementing the gptel-backend API.
- **Apply to us**: The way gptel handles tool definitions (structured function specs with parameter schemas, confirmation before execution) is directly applicable. We could use gptel's existing tool infrastructure rather than building our own.

### 5. Nucleus: Mode/Boundary System (Hashtag behaviors)
- **Technique**: 12 modes (#=code, #=debug, #=review, #=test, #=spec, #=research, etc.) each with defined scope AND explicit boundaries (what the mode will NOT do).
- **How it works**: Each mode has a positive scope + negative boundary. Boundary is as important as scope. Compose through pipeline: research → assess → spec → code.
- **Apply to us**: We could implement a mode system for our agent where each command/mode explicitly states what it won't do. This prevents scope creep and reduces errors.

Now let me also check what we already have in our codebase to see if these patterns are already implemented.Let me check our existing codebase for what's already in place.Now I have a very clear picture. Let me read the gptel AGENTS.md too and then synthesize.

Our project already:
- Has a mementum state.md with detailed session tracking
- Has experiment pipeline, verification gates, eight-key ontology
- Uses gptel as the LLM backend

Patterns NOT yet in our codebase:
1. **VSM Architecture**: Our system doesn't use the VSM layered architecture explicitly. We have experiment pipelines but no S5-S1 decomposition.
2. **Fibonacci Recall Depth**: Our memory recall is flat, not using fibonacci-scaled depth.
3. **Meta-Learning λ(λ)**: We log experiments but don't have a formal meta-learning layer separating λ[n] from λ(λ[n]).
4. **Mode/Boundary System**: We don't have explicit mode constraints with "will NOT do" boundaries.
5. **Symbolic Attention Magnets**: We don't use mathematical symbol preambles to prime model attention.
6. **Mementum Protocol**: We have a state.md but don't fully implement the 7 operations (create, create-knowledge, update, delete, search, read, synthesize) with symbol-prefixed commits.

Let me get the gptel AGENTS.md.Now I have a very clear picture. Let me read the gptel AGENTS.md too and then synthesize.

Our project already:
- Has a mementum state.md with detailed session tracking
- Has experiment pipeline, verification gates, eight-key ontology
- Uses gptel as the LLM backend

Patterns NOT yet in our codebase:
1. **VSM Architecture**: Our system doesn't use the VSM layered architecture explicitly. We have experiment pipelines but no S5-S1 decomposition.
2. **Fibonacci Recall Depth**: Our memory recall is flat, not using fibonacci-scaled depth.
3. **Meta-Learning λ(λ)**: We log experiments but don't have a formal meta-learning layer separating λ[n] from λ(λ[n]).
4. **Mode/Boundary System**: We don't have explicit mode constraints with "will NOT do" boundaries.
5. **Symbolic Attention Magnets**: We don't use mathematical symbol preambles to prime model attention.
6. **Mementum Protocol**: We have a state.md but don't fully implement the 7 operations (create, create-knowledge, update, delete, search, read, synthesize) with symbol-prefixed commits.

Let me get the gptel AGENTS.md.The gptel AGENTS.md doesn't exist (404). Let me look at the actual gptel repo structure and some specific files that show the tool-use pattern.

Let me check for gptel's tool-use implementation to extract the pattern.The gptel AGENTS.md doesn't exist (404). Let me look at the actual gptel repo structure and some specific files that show the tool-use pattern.

Let me check for gptel's tool-use implementation to extract the pattern.Now I have comprehensive data on all three repos. Let me synthesize the findings into a structured digest.

Key insights from each repo:

### Nucleus Patterns:
1. **VSM Architecture (S5-S1)** — Layered system decomposition where higher layers change less and matter more. Each layer has a distinct role: Identity, Intelligence, Control, Coordination, Operations.
2. **Symbolic Attention Magnets** — Mathematical symbols with high training weight prime model attention toward formal reasoning. The `⊗` (tensor product) operator for Human ⊗ AI produces higher quality first attempts than sequential or additive composition.
3. **Mode/Boundary System** — 12 modes each with explicit scope AND "will NOT do" boundaries. Pipeline: research → assess → spec → code (stage outputs feed next stage inputs, no skipping).

### Mementum Patterns:
1. **Fibonacci Recall Depth** — `git log -n φ^k` where k = complexity. Default depth 2, progression: 2→3→5→8→13→21.
2. **Meta-Learning λ(λ)** — First-order λ[n] (observations about work) vs meta-order λ(λ[n]) (observations about process). Intelligence growth: I(n+1) = I(n) + λ[n] + λ(λ[n]) + v(Σλ) - ⊗.
3. **Three-Tier Memory with Synthesis Trigger** — state.md (bootloader), memories/ (breadcrumbs, <200 words), knowledge/ (maps, frontmatter). ≥3 memories on same topic triggers synthesis into knowledge page.
4. **Storage Criticality Gate** — Two gates: (1) helps future AI session, (2) effort > 1 attempt ∨ likely to recur. Both must pass before storing.

### gptel Patterns:
1. **Tool-Use Architecture** — Structured function specs with name/description/parameters, confirmation before execution, curl/url-retrieve dual backend.
2. **MCP Integration** — Uses mcp.el for Model Context Protocol, allowing external tools to be discovered dynamically.
3. **Temperature nil default** — Recent change: default temperature is nil (API default), because backends disagree on scale.

Now let me compile the final structured digest.

**Meta-learning:** Research quality measured by downstream experiment success.

---
*Generated by auto-workflow*
