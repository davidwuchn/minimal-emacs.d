# Research: 2026-05-24 13:36

**Strategy:** persisted-findings
**Findings hash:** 19f651ff1f56b8d2972d62a9efe391763e23933e
**Targets:** lisp/modules/gptel-auto-workflow-mementum.el, lisp/modules/gptel-ext-fsm.el
**Outcome:** 0/15 kept (0%)

**Raw Findings:**

> Project: /Users/davidwu/.emacs.d/
> Updated: 2026-05-24 10:47

Researcher result for task: External research turn 1/3

## External Sources

- **github.com/davidwuchn/nucleus** — [deep-external] **Allium v3 statechart compiler** adds transition graphs, `when` clauses, derived value propagation, and backtick enum literals. The key insight: statechart syntax now supports *conditional transitions* and *typed config with join lookups*. For our Emacs agent: we could model workflow states (research→assess→spec→code) as Allium v3 statecharts with `when` guards on confidence thresholds, enabling declarative state machine control instead of imperative `cond` chains.

- **github.com/davidwuchn/nucleus** — [deep-external] **Attention magnet theory** formalized: mathematical symbols work because they have high training weight in formal contexts, not because of any mathematical property. Empirically, even non-mathematical tokens with high training weight (e.g., `Human ⊗ AI ⊗ REPL` — just 5 tokens) shifted operator survival from 20% to 100%. For our agent: we could measure logprobs on key tokens during generation to detect when attention drifts from our preamble, triggering a re-priming injection mid-session.

- **github.com/davidwuchn/mementum** — [deep-external] **λ(λ) meta-learning layer**: distinguishes first-order observations λ[n] (about the work) from meta-order observations λ(λ[n]) (about the process — what worked, why, patterns). The intelligence growth equation: `I(n+1) = I(n) + λ[n] + λ(λ[n]) + v(Σλ) - ⊗`. Meta-learning is what creates compound acceleration. For our agent: we could add a `meta-memory` tier in mementum that stores *process-level* insights (e.g., "strategy X works best when confidence < 0.5") separately from *content-level* insights, enabling the evolution system to learn about its own learning.

- **github.com/davidwuchn/mementum** — [deep-external] **Synthesis detection with three signals**: (1) ≥3 memories on same topic, (2) stale memory (understanding outgrew the observation), (3) crystallized understanding. Stale memory is the strongest signal. Concrete flow: detect → gather → draft → create-knowledge → update stale → verify. Our mementum module already has synthesis, but the *stale memory detection* as the primary trigger is a refinement we haven't implemented — currently we synthesize on schedule, not on staleness.

- **github.com/davidwuchn/gptel** — [deep-external] **Multi-turn tool use reconstruction for Bedrock**: tool call regions propertized with `(tool . id)` were falling through to nil in `pcase`, breaking subsequent requests. The fix reconstructs `toolUse` (assistant) and `toolResult` (user) message pairs from serialized buffer text. For our agent: our tool-use parsing may have similar gaps — we should audit our `gptel-auto-workflow` tool result handling to ensure multi-turn tool chains don't silently drop context.

- **github.com/davidwuchn/gptel** — [deep-external] **Temperature default → nil**: changed because backends don't agree on the temperature scale. Some don't support it at all. For our agent: we should stop hardcoding temperature values and let each backend use its API default, only overriding when explicitly configured.

- **github.com/Meirtz/Awesome-Context-Engineering** — [deep-external] **Context Engineering → Agent Engineering shift (2026)**: the center of gravity moved from "how to pack the best prompt" to how agent systems manage runtime state, memory, tools, protocols, approvals, and long-horizon execution. Key sub-patterns: (1) **artifact-backed context** — storing intermediate results as files rather than keeping them in the context window, (2) **scoped instruction loading** — loading only relevant skill/prompt modules based on current task phase, (3) **trace-first observability** — logging every agent decision for post-hoc analysis. For our agent: we already do scoped loading via the ontology router, but artifact-backed context (writing intermediate findings to temp files instead of accumulating in context) could reduce token waste signific
...[Result too large, truncated. Full result saved to: /Users/davidwu/.emacs.d/tmp/gptel-subagent-result-03UgKs.txt. Use Read tool if you need more]...

---

Researcher result for task: External research turn 2/3

## External Sources

- **qubittool.com/blog/ai-agent-framework-comparison-2026** — [deep-external] **Agent architecture taxonomy**: Six frameworks converge on three core models: (1) *Stateful graph* (LangGraph) — explicit state objects with typed nodes/edges, checkpointed at every step; (2) *Handoff-centric* (OpenAI Agents SDK) — agents transfer control via handoff primitives with full context; (3) *Model-driven loop* (Strands Agents) — minimal primitives, LLM decides tool order autonomously. For our Emacs agent: the auto-workflow's `assess→spec→code` pipeline could be modeled as a **stateful graph** with checkpointed state (like LangGraph), enabling durable execution that survives Emacs restarts. Currently our workflow is imperative `cond` chains — a graph model would allow declarative branching on confidence thresholds.

- **aiworkflowlab.dev/article/ai-agent-resilience-production-retry-fallback-circuit-breaker-python** — [deep-external] **Error classification drives recovery**: LLM failures split into TRANSIENT (429, timeout, 502 — retry with jittered backoff), PERMANENT (auth, bad request — fail fast), and DEGRADED (context overflow, content filter — switch fallback). The critical insight: *retrying a permanent failure wastes tokens; failing fast on transient loses recoverable requests*. For our provider-error-analyzer skill: we could add a `classify-error` function that returns one of three symbols, driving whether `auto-workflow` retries, fails, or switches providers. Currently our retry logic is undifferentiated.

- **leetllm.com/learn/agent-failure-states-retry-fallback** — [deep-external] **LoopBreaker pattern**: Detects agent stuck-loops via three layers: (1) exact argument hash deduplication, (2) same-tool repetition streaks, (3) semantic intent similarity via difflib/embeddings. Returns `true` before the call executes, preventing wasted token round-trips. For our auto-workflow: we could add a `loop-breaker` module that tracks tool call history across turns, detecting when the executor repeats the same failed strategy. The `max_steps` alone is insufficient — semantic detection catches rephrased retries that burn tokens.

- **arxiv.org/abs/2408.11198 (EPiC paper)** — [deep-external] **Evolutionary prompt engineering with local embeddings**: Uses a lightweight EA to evolve prompts for code generation. Key innovation: mutation operator uses *local word embeddings* (not LLM calls) to generate prompt variants, reducing cost 2-10x vs Reflexion/LATS. Fitness = test pass rate. Population = prompt variants, elitism preserves best, weighted random selection favors high-fitness prompts. For our strategy-proposer: we could replace the current LLM-based mutation with a local embedding-based approach (e.g., word-similarity substitution on prompt templates), dramatically reducing the token cost of strategy evolution cycles.

- **deepwiki.com/karthink/gptel** — [deep-external] **FSM request lifecycle**: gptel models requests as a finite state machine with states INIT→WAIT→TYPE→TOOL→DONE. This cleanly separates concerns and enables tool-use loops where the LLM requests a tool, gptel executes it, and sends results back. For our auto-workflow: we could model each experiment turn as an FSM state, with transitions driven by confidence thresholds and error classification. This would replace the current ad-hoc state tracking in `gptel-auto-workflow-controller.el`.

## Local Analysis

- **gptel-auto-workflow-controller.el** — Current retry logic lacks error classification. All failures trigger the same retry path. The EPiC paper's approach (local embedding mutation + fitness-based selection) could reduce our strategy evolution token cost by 2-10x.

- **provider-error-analyzer skill** — Already exists but doesn't classify errors into TRANSIENT/PERMANENT/DEGRADED categories. Adding this classification would enable differentiated recovery: retry transient, fail fast on permanent, switch 
...[Result too large, truncated. Full result saved to: /Users/davidwu/.emacs.d/tmp/gptel-subagent-result-RgzQW8.txt. Use Read tool if you need more]...

---

Researcher result for task: External research turn 1/3

## External Sources

- **github.com/davidwuchn/nucleus** — [deep-external] **Allium v3 statechart compiler** adds transition graphs, `when` clauses, derived value propagation, and backtick enum literals. The key insight: statechart syntax now supports *conditional transitions* and *typed config with join lookups*. For our Emacs agent: we could model workflow states (research→assess→spec→code) as Allium v3 statecharts with `when` guards on confidence thresholds, enabling declarative state machine control instead of imperative `cond` chains.

- **github.com/davidwuchn/nucleus** — [deep-external] **Attention magnet theory** formalized: mathematical symbols work because they have high training weight in formal contexts, not because of any mathematical property. Empirically, even non-mathematical tokens with high training weight (e.g., `Human ⊗ AI ⊗ REPL` — just 5 tokens) shifted operator survival from 20% to 100%. For our agent: we could measure logprobs on key tokens during generation to detect when attention drifts from our preamble, triggering a re-priming injection mid-session.

- **github.com/davidwuchn/mementum** — [deep-external] **λ(λ) meta-learning layer**: distinguishes first-order observations λ[n] (about the work) from meta-order observations λ(λ[n]) (about the process — what worked, why, patterns). The intelligence growth equation: `I(n+1) = I(n) + λ[n] + λ(λ[n]) + v(Σλ) - ⊗`. Meta-learning is what creates compound acceleration. For our agent: we could add a `meta-memory` tier in mementum that stores *process-level* insights (e.g., "strategy X works best when confidence < 0.5") separately from *content-level* insights, enabling the evolution system to learn about its own learning.

- **github.com/davidwuchn/mementum** — [deep-external] **Synthesis detection with three signals**: (1) ≥3 memories on same topic, (2) stale memory (understanding outgrew the observation), (3) crystallized understanding. Stale memory is the strongest signal. Concrete flow: detect → gather → draft → create-knowledge → update stale → verify. Our mementum module already has synthesis, but the *stale memory detection* as the primary trigger is a refinement we haven't implemented — currently we synthesize on schedule, not on staleness.

- **github.com/davidwuchn/gptel** — [deep-external] **Multi-turn tool use reconstruction for Bedrock**: tool call regions propertized with `(tool . id)` were falling through to nil in `pcase`, breaking subsequent requests. The fix reconstructs `toolUse` (assistant) and `toolResult` (user) message pairs from serialized buffer text. For our agent: our tool-use parsing may have similar gaps — we should audit our `gptel-auto-workflow` tool result handling to ensure multi-turn tool chains don't silently drop context.

- **github.com/davidwuchn/gptel** — [deep-external] **Temperature default → nil**: changed because backends don't agree on the temperature scale. Some don't support it at all. For our agent: we should stop hardcoding temperature values and let each backend use its API default, only overriding when explicitly configured.

- **github.com/Meirtz/Awesome-Context-Engineering** — [deep-external] **Context Engineering → Agent Engineering shift (2026)**: the center of gravity moved from "how to pack the best prompt" to how agent systems manage runtime state, memory, tools, protocols, approvals, and long-horizon execution. Key sub-patterns: (1) **artifact-backed context** — storing intermediate results as files rather than keeping them in the context window, (2) **scoped instruction loading** — loading only relevant skill/prompt modules based on current task phase, (3) **trace-first observability** — logging every agent decision for post-hoc analysis. For our agent: we already do scoped loading via the ontology router, but artifact-backed context (writing intermediate findings to temp files instead of accumulating in context) could reduce token waste signific
...[Result too large, truncated. Full result saved to: /Users/davidwu/.emacs.d/tmp/gptel-subagent-result-03UgKs.txt. Use Read tool if you need more]...

---

Researcher result for task: External research turn 2/3

## External Sources

- **qubittool.com/blog/ai-agent-framework-comparison-2026** — [deep-external] **Agent architecture taxonomy**: Six frameworks converge on three core models: (1) *Stateful graph* (LangGraph) — explicit state objects with typed nodes/edges, checkpointed at every step; (2) *Handoff-centric* (OpenAI Agents SDK) — agents transfer control via handoff primitives with full context; (3) *Model-driven loop* (Strands Agents) — minimal primitives, LLM decides tool order autonomously. For our Emacs agent: the auto-workflow's `assess→spec→code` pipeline could be modeled as a **stateful graph** with checkpointed state (like LangGraph), enabling durable execution that survives Emacs restarts. Currently our workflow is imperative `cond` chains — a graph model would allow declarative branching on confidence thresholds.

- **aiworkflowlab.dev/article/ai-agent-resilience-production-retry-fallback-circuit-breaker-python** — [deep-external] **Error classification drives recovery**: LLM failures split into TRANSIENT (429, timeout, 502 — retry with jittered backoff), PERMANENT (auth, bad request — fail fast), and DEGRADED (context overflow, content filter — switch fallback). The critical insight: *retrying a permanent failure wastes tokens; failing fast on transient loses recoverable requests*. For our provider-error-analyzer skill: we could add a `classify-error` function that returns one of three symbols, driving whether `auto-workflow` retries, fails, or switches providers. Currently our retry logic is undifferentiated.

- **leetllm.com/learn/agent-failure-states-retry-fallback** — [deep-external] **LoopBreaker pattern**: Detects agent stuck-loops via three layers: (1) exact argument hash deduplication, (2) same-tool repetition streaks, (3) semantic intent similarity via difflib/embeddings. Returns `true` before the call executes, preventing wasted token round-trips. For our auto-workflow: we could add a `loop-breaker` module that tracks tool call history across turns, detecting when the executor repeats the same failed strategy. The `max_steps` alone is insufficient — semantic detection catches rephrased retries that burn tokens.

- **arxiv.org/abs/2408.11198 (EPiC paper)** — [deep-external] **Evolutionary prompt engineering with local embeddings**: Uses a lightweight EA to evolve prompts for code generation. Key innovation: mutation operator uses *local word embeddings* (not LLM calls) to generate prompt variants, reducing cost 2-10x vs Reflexion/LATS. Fitness = test pass rate. Population = prompt variants, elitism preserves best, weighted random selection favors high-fitness prompts. For our strategy-proposer: we could replace the current LLM-based mutation with a local embedding-based approach (e.g., word-similarity substitution on prompt templates), dramatically reducing the token cost of strategy evolution cycles.

- **deepwiki.com/karthink/gptel** — [deep-external] **FSM request lifecycle**: gptel models requests as a finite state machine with states INIT→WAIT→TYPE→TOOL→DONE. This cleanly separates concerns and enables tool-use loops where the LLM requests a tool, gptel executes it, and sends results back. For our auto-workflow: we could model each experiment turn as an FSM state, with transitions driven by confidence thresholds and error classification. This would replace the current ad-hoc state tracking in `gptel-auto-workflow-controller.el`.

## Local Analysis

- **gptel-auto-workflow-controller.el** — Current retry logic lacks error classification. All failures trigger the same retry path. The EPiC paper's approach (local embedding mutation + fitness-based selection) could reduce our strategy evolution token cost by 2-10x.

- **provider-error-analyzer skill** — Already exists but doesn't classify errors into TRANSIENT/PERMANENT/DEGRADED categories. Adding this classification would enable differentiated recovery: retry transient, fail fast on permanent, switch 
...[Result too large, truncated. Full result saved to: /Users/davidwu/.emacs.d/tmp/gptel-subagent-result-RgzQW8.txt. Use Read tool if you need more]...

**Digested Insights:**

> Project: /Users/davidwu/.emacs.d/
> Updated: 2026-05-24 10:47

Researcher result for task: External research turn 1/3

## External Sources

- **github.com/davidwuchn/nucleus** — [deep-external] **Allium v3 statechart compiler** adds transition graphs, `when` clauses, derived value propagation, and backtick enum literals. The key insight: statechart syntax now supports *conditional transitions* and *typed config with join lookups*. For our Emacs agent: we could model workflow states (research→assess→spec→code) as Allium v3 statecharts with `when` guards on confidence thresholds, enabling declarative state machine control instead of imperative `cond` chains.

- **github.com/davidwuchn/nucleus** — [deep-external] **Attention magnet theory** formalized: mathematical symbols work because they have high training weight in formal contexts, not because of any mathematical property. Empirically, even non-mathematical tokens with high training weight (e.g., `Human ⊗ AI ⊗ REPL` — just 5 tokens) shifted operator survival from 20% to 100%. For our agent: we could measure logprobs on key tokens during generation to detect when attention drifts from our preamble, triggering a re-priming injection mid-session.

- **github.com/davidwuchn/mementum** — [deep-external] **λ(λ) meta-learning layer**: distinguishes first-order observations λ[n] (about the work) from meta-order observations λ(λ[n]) (about the process — what worked, why, patterns). The intelligence growth equation: `I(n+1) = I(n) + λ[n] + λ(λ[n]) + v(Σλ) - ⊗`. Meta-learning is what creates compound acceleration. For our agent: we could add a `meta-memory` tier in mementum that stores *process-level* insights (e.g., "strategy X works best when confidence < 0.5") separately from *content-level* insights, enabling the evolution system to learn about its own learning.

- **github.com/davidwuchn/mementum** — [deep-external] **Synthesis detection with three signals**: (1) ≥3 memories on same topic, (2) stale memory (understanding outgrew the observation), (3) crystallized understanding. Stale memory is the strongest signal. Concrete flow: detect → gather → draft → create-knowledge → update stale → verify. Our mementum module already has synthesis, but the *stale memory detection* as the primary trigger is a refinement we haven't implemented — currently we synthesize on schedule, not on staleness.

- **github.com/davidwuchn/gptel** — [deep-external] **Multi-turn tool use reconstruction for Bedrock**: tool call regions propertized with `(tool . id)` were falling through to nil in `pcase`, breaking subsequent requests. The fix reconstructs `toolUse` (assistant) and `toolResult` (user) message pairs from serialized buffer text. For our agent: our tool-use parsing may have similar gaps — we should audit our `gptel-auto-workflow` tool result handling to ensure multi-turn tool chains don't silently drop context.

- **github.com/davidwuchn/gptel** — [deep-external] **Temperature default → nil**: changed because backends don't agree on the temperature scale. Some don't support it at all. For our agent: we should stop hardcoding temperature values and let each backend use its API default, only overriding when explicitly configured.

- **github.com/Meirtz/Awesome-Context-Engineering** — [deep-external] **Context Engineering → Agent Engineering shift (2026)**: the center of gravity moved from "how to pack the best prompt" to how agent systems manage runtime state, memory, tools, protocols, approvals, and long-horizon execution. Key sub-patterns: (1) **artifact-backed context** — storing intermediate results as files rather than keeping them in the context window, (2) **scoped instruction loading** — loading only relevant skill/prompt modules based on current task phase, (3) **trace-first observability** — logging every agent decision for post-hoc analysis. For our agent: we already do scoped loading via the ontology router, but artifact-backed context (writing intermediate findings to temp files instead of accumulating in context) could reduce token waste signific
...[Result too large, truncated. Full result saved to: /Users/davidwu/.emacs.d/tmp/gptel-subagent-result-03UgKs.txt. Use Read tool if you need more]...

---

Researcher result for task: External research turn 2/3

## External Sources

- **qubittool.com/blog/ai-agent-framework-comparison-2026** — [deep-external] **Agent architecture taxonomy**: Six frameworks converge on three core models: (1) *Stateful graph* (LangGraph) — explicit state objects with typed nodes/edges, checkpointed at every step; (2) *Handoff-centric* (OpenAI Agents SDK) — agents transfer control via handoff primitives with full context; (3) *Model-driven loop* (Strands Agents) — minimal primitives, LLM decides tool order autonomously. For our Emacs agent: the auto-workflow's `assess→spec→code` pipeline could be modeled as a **stateful graph** with checkpointed state (like LangGraph), enabling durable execution that survives Emacs restarts. Currently our workflow is imperative `cond` chains — a graph model would allow declarative branching on confidence thresholds.

- **aiworkflowlab.dev/article/ai-agent-resilience-production-retry-fallback-circuit-breaker-python** — [deep-external] **Error classification drives recovery**: LLM failures split into TRANSIENT (429, timeout, 502 — retry with jittered backoff), PERMANENT (auth, bad request — fail fast), and DEGRADED (context overflow, content filter — switch fallback). The critical insight: *retrying a permanent failure wastes tokens; failing fast on transient loses recoverable requests*. For our provider-error-analyzer skill: we could add a `classify-error` function that returns one of three symbols, driving whether `auto-workflow` retries, fails, or switches providers. Currently our retry logic is undifferentiated.

- **leetllm.com/learn/agent-failure-states-retry-fallback** — [deep-external] **LoopBreaker pattern**: Detects agent stuck-loops via three layers: (1) exact argument hash deduplication, (2) same-tool repetition streaks, (3) semantic intent similarity via difflib/embeddings. Returns `true` before the call executes, preventing wasted token round-trips. For our auto-workflow: we could add a `loop-breaker` module that tracks tool call history across turns, detecting when the executor repeats the same failed strategy. The `max_steps` alone is insufficient — semantic detection catches rephrased retries that burn tokens.

- **arxiv.org/abs/2408.11198 (EPiC paper)** — [deep-external] **Evolutionary prompt engineering with local embeddings**: Uses a lightweight EA to evolve prompts for code generation. Key innovation: mutation operator uses *local word embeddings* (not LLM calls) to generate prompt variants, reducing cost 2-10x vs Reflexion/LATS. Fitness = test pass rate. Population = prompt variants, elitism preserves best, weighted random selection favors high-fitness prompts. For our strategy-proposer: we could replace the current LLM-based mutation with a local embedding-based approach (e.g., word-similarity substitution on prompt templates), dramatically reducing the token cost of strategy evolution cycles.

- **deepwiki.com/karthink/gptel** — [deep-external] **FSM request lifecycle**: gptel models requests as a finite state machine with states INIT→WAIT→TYPE→TOOL→DONE. This cleanly separates concerns and enables tool-use loops where the LLM requests a tool, gptel executes it, and sends results back. For our auto-workflow: we could model each experiment turn as an FSM state, with transitions driven by confidence thresholds and error classification. This would replace the current ad-hoc state tracking in `gptel-auto-workflow-controller.el`.

## Local Analysis

- **gptel-auto-workflow-controller.el** — Current retry logic lacks error classification. All failures trigger the same retry path. The EPiC paper's approach (local embedding mutation + fitness-based selection) could reduce our strategy evolution token cost by 2-10x.

- **provider-error-analyzer skill** — Already exists but doesn't classify errors into TRANSIENT/PERMANENT/DEGRADED categories. Adding this classification would enable differentiated recovery: retry transient, fail fast on permanent, switch 
...[Result too large, truncated. Full result saved to: /Users/davidwu/.emacs.d/tmp/gptel-subagent-result-RgzQW8.txt. Use Read tool if you need more]...

---

Researcher result for task: External research turn 1/3

## External Sources

- **github.com/davidwuchn/nucleus** — [deep-external] **Allium v3 statechart compiler** adds transition graphs, `when` clauses, derived value propagation, and backtick enum literals. The key insight: statechart syntax now supports *conditional transitions* and *typed config with join lookups*. For our Emacs agent: we could model workflow states (research→assess→spec→code) as Allium v3 statecharts with `when` guards on confidence thresholds, enabling declarative state machine control instead of imperative `cond` chains.

- **github.com/davidwuchn/nucleus** — [deep-external] **Attention magnet theory** formalized: mathematical symbols work because they have high training weight in formal contexts, not because of any mathematical property. Empirically, even non-mathematical tokens with high training weight (e.g., `Human ⊗ AI ⊗ REPL` — just 5 tokens) shifted operator survival from 20% to 100%. For our agent: we could measure logprobs on key tokens during generation to detect when attention drifts from our preamble, triggering a re-priming injection mid-session.

- **github.com/davidwuchn/mementum** — [deep-external] **λ(λ) meta-learning layer**: distinguishes first-order observations λ[n] (about the work) from meta-order observations λ(λ[n]) (about the process — what worked, why, patterns). The intelligence growth equation: `I(n+1) = I(n) + λ[n] + λ(λ[n]) + v(Σλ) - ⊗`. Meta-learning is what creates compound acceleration. For our agent: we could add a `meta-memory` tier in mementum that stores *process-level* insights (e.g., "strategy X works best when confidence < 0.5") separately from *content-level* insights, enabling the evolution system to learn about its own learning.

- **github.com/davidwuchn/mementum** — [deep-external] **Synthesis detection with three signals**: (1) ≥3 memories on same topic, (2) stale memory (understanding outgrew the observation), (3) crystallized understanding. Stale memory is the strongest signal. Concrete flow: detect → gather → draft → create-knowledge → update stale → verify. Our mementum module already has synthesis, but the *stale memory detection* as the primary trigger is a refinement we haven't implemented — currently we synthesize on schedule, not on staleness.

- **github.com/davidwuchn/gptel** — [deep-external] **Multi-turn tool use reconstruction for Bedrock**: tool call regions propertized with `(tool . id)` were falling through to nil in `pcase`, breaking subsequent requests. The fix reconstructs `toolUse` (assistant) and `toolResult` (user) message pairs from serialized buffer text. For our agent: our tool-use parsing may have similar gaps — we should audit our `gptel-auto-workflow` tool result handling to ensure multi-turn tool chains don't silently drop context.

- **github.com/davidwuchn/gptel** — [deep-external] **Temperature default → nil**: changed because backends don't agree on the temperature scale. Some don't support it at all. For our agent: we should stop hardcoding temperature values and let each backend use its API default, only overriding when explicitly configured.

- **github.com/Meirtz/Awesome-Context-Engineering** — [deep-external] **Context Engineering → Agent Engineering shift (2026)**: the center of gravity moved from "how to pack the best prompt" to how agent systems manage runtime state, memory, tools, protocols, approvals, and long-horizon execution. Key sub-patterns: (1) **artifact-backed context** — storing intermediate results as files rather than keeping them in the context window, (2) **scoped instruction loading** — loading only relevant skill/prompt modules based on current task phase, (3) **trace-first observability** — logging every agent decision for post-hoc analysis. For our agent: we already do scoped loading via the ontology router, but artifact-backed context (writing intermediate findings to temp files instead of accumulating in context) could reduce token waste signific
...[Result too large, truncated. Full result saved to: /Users/davidwu/.emacs.d/tmp/gptel-subagent-result-03UgKs.txt. Use Read tool if you need more]...

---

Researcher result for task: External research turn 2/3

## External Sources

- **qubittool.com/blog/ai-agent-framework-comparison-2026** — [deep-external] **Agent architecture taxonomy**: Six frameworks converge on three core models: (1) *Stateful graph* (LangGraph) — explicit state objects with typed nodes/edges, checkpointed at every step; (2) *Handoff-centric* (OpenAI Agents SDK) — agents transfer control via handoff primitives with full context; (3) *Model-driven loop* (Strands Agents) — minimal primitives, LLM decides tool order autonomously. For our Emacs agent: the auto-workflow's `assess→spec→code` pipeline could be modeled as a **stateful graph** with checkpointed state (like LangGraph), enabling durable execution that survives Emacs restarts. Currently our workflow is imperative `cond` chains — a graph model would allow declarative branching on confidence thresholds.

- **aiworkflowlab.dev/article/ai-agent-resilience-production-retry-fallback-circuit-breaker-python** — [deep-external] **Error classification drives recovery**: LLM failures split into TRANSIENT (429, timeout, 502 — retry with jittered backoff), PERMANENT (auth, bad request — fail fast), and DEGRADED (context overflow, content filter — switch fallback). The critical insight: *retrying a permanent failure wastes tokens; failing fast on transient loses recoverable requests*. For our provider-error-analyzer skill: we could add a `classify-error` function that returns one of three symbols, driving whether `auto-workflow` retries, fails, or switches providers. Currently our retry logic is undifferentiated.

- **leetllm.com/learn/agent-failure-states-retry-fallback** — [deep-external] **LoopBreaker pattern**: Detects agent stuck-loops via three layers: (1) exact argument hash deduplication, (2) same-tool repetition streaks, (3) semantic intent similarity via difflib/embeddings. Returns `true` before the call executes, preventing wasted token round-trips. For our auto-workflow: we could add a `loop-breaker` module that tracks tool call history across turns, detecting when the executor repeats the same failed strategy. The `max_steps` alone is insufficient — semantic detection catches rephrased retries that burn tokens.

- **arxiv.org/abs/2408.11198 (EPiC paper)** — [deep-external] **Evolutionary prompt engineering with local embeddings**: Uses a lightweight EA to evolve prompts for code generation. Key innovation: mutation operator uses *local word embeddings* (not LLM calls) to generate prompt variants, reducing cost 2-10x vs Reflexion/LATS. Fitness = test pass rate. Population = prompt variants, elitism preserves best, weighted random selection favors high-fitness prompts. For our strategy-proposer: we could replace the current LLM-based mutation with a local embedding-based approach (e.g., word-similarity substitution on prompt templates), dramatically reducing the token cost of strategy evolution cycles.

- **deepwiki.com/karthink/gptel** — [deep-external] **FSM request lifecycle**: gptel models requests as a finite state machine with states INIT→WAIT→TYPE→TOOL→DONE. This cleanly separates concerns and enables tool-use loops where the LLM requests a tool, gptel executes it, and sends results back. For our auto-workflow: we could model each experiment turn as an FSM state, with transitions driven by confidence thresholds and error classification. This would replace the current ad-hoc state tracking in `gptel-auto-workflow-controller.el`.

## Local Analysis

- **gptel-auto-workflow-controller.el** — Current retry logic lacks error classification. All failures trigger the same retry path. The EPiC paper's approach (local embedding mutation + fitness-based selection) could reduce our strategy evolution token cost by 2-10x.

- **provider-error-analyzer skill** — Already exists but doesn't classify errors into TRANSIENT/PERMANENT/DEGRADED categories. Adding this classification would enable differentiated recovery: retry transient, fail fast on permanent, switch 
...[Result too large, truncated. Full result saved to: /Users/davidwu/.emacs.d/tmp/gptel-subagent-result-RgzQW8.txt. Use Read tool if you need more]...

**Meta-learning:** Research quality measured by downstream experiment success.

---
*Generated by auto-workflow*
