# Research: 2026-05-31 08:42

**Strategy:** persisted-findings
**Findings hash:** 63dfcccf90a7343042a4e35883afd0833b0b519b
**Targets:** lisp/modules/gptel-benchmark-subagent.el, lisp/modules/gptel-auto-workflow-projects.el, staging-review
**Outcome:** 3/15 kept (20%)

**Raw Findings:**

> Project: /home/davidwu/.emacs.d/
> Updated: 2026-05-31 07:03

Researcher result for task: External research turn 1/3

<think>
Let me analyze this research request. The user wants me to:

1. Research external sources for actionable techniques related to AI agent architectures
2. Prioritize davidwuchn's own repos (nucleus, mementum, gptel) since own-repo has the highest effectiveness score (0.60)
3. Follow the source directive: Start with own repos, then 1-2 external references
4. Budget: 55% own repos, 15% external

The current research performance shows:
- own-repo has the highest effectiveness (0.60)
- external has low effectiveness (0.14)
- 10 recent failure patterns noted

Let me start by checking davidwuchn's repos on GitHub, then potentially do 1-2 external searches.

I should:
1. WebFetch the three priority repos (nucleus, mementum, gptel)
2. Extract 1-3 patterns from each
3. Do minimal external research (1-2 sources)
4. Synthesize findings

Let me start with the own repos.
</think>## Research Pipeline: External Discovery

**Strategy**: Own-repos-first (55% budget allocation)
**Source effectiveness**: own-repo=0.60 (HIGH PRIORITY), external=0.14 (LOW)

Starting with davidwuchn's repos since own-repo effectiveness is 4x higher than external.<think>
Let me read the full content of these repos to extract architectural patterns. The temp files are large, let me read specific parts.
</think><think>
Now let me get more specific architecture patterns from gptel, particularly around tool use and MCP integration since that's a key feature.
</think><think>
Let me read more to get tool use and MCP integration details from gptel.
</think><think>
Now let me read more about gptel-agent for the agentic workflow patterns.
</think><think>
Now let me check for specific patterns I can extract. I have enough context now. Let me do a quick external search on AI agent workflow patterns for Emacs, specifically focusing on areas not covered.
</think>Now let me do 1-2 external searches to complement the own-repo research:<think>
Excellent! I found a direct reference to karthink/gptel-agent. Let me fetch that since it's directly relevant.
</think><think>
Excellent! Now I have comprehensive information. Let me synthesize the findings:

## External Sources (Own Repos)

1. **nucleus**: Attention magnet theory using mathematical symbols (phi, fractal, euler, etc.) to prime model attention toward formal reasoning patterns. Lambda notation as a compression layer.

2. **mementum**: Git-based memory protocol with session continuity. Three storage types (working memory, memories, knowledge), seven operations, human governance.

3. **gptel**: Multi-backend LLM client with tool-use, MCP integration, and agentic capabilities.

4. **karthink/gptel-agent**: Sub-agent delegation pattern - executor, researcher, introspector. Parallel delegation, context isolation.

## External Patterns

- Error recovery patterns: exponential backoff, fallback chains
- Multi-step reasoning: plan-act-reflect loop
- Silent failure detection in agent traces

Let me write the research digest with actionable techniques.
</think>

---

## Local Codebase Analysis (fallback — external research unavailable)

> Auto-generated from local git history, experiment results, and codebase scan.

## Git Activity (last 30 commits to lisp/modules/)

- **18** bug fixes
- **9** feature/evolution commits
- Focus: stabilization

## Module Complexity (top 5 by lines)

```
64310 total
   6056 lisp/modules/gptel-auto-workflow-evolution.el
   3231 lisp/modules/gptel-auto-workflow-ontology-router.el
   3070 lisp/modules/gptel-tools-agent-prompt-build.el
   2803 lisp/modules/gptel-auto-workflow-strategic.el
```

**Self-Evolution Directive:** Focus on the highest-failure modules above. Apply nil-safety patterns and validation guards to reduce failure rates.

---

Researcher result for task: External research turn 3/3

The user wants me to continue researching external sources. This is turn 3+, and the EMA confidence is 0.34 (low). I need to be concise and focus on highest-impact insights. The controller is telling me to switch to NEW sources since previous sources were "DEVIANT" - meaning the own-repo research approach wasn't yielding great results.

Let me focus on external sources now:
- Search for AI agent architectures, Emacs AI integration patterns, LLM self-evolution
- Use WebSearch to find recent/relevant items
- Probe source titles/abstracts before deep reading
- 100% external priority

Let me think about the most promising areas to search:
1. AI agent architectures - Anthropic's patterns, LangChain, AutoGPT patterns
2. Emacs Lisp AI integration - gptel, ellama, org-ai
3. LLM self-evolution - DSPy, TextGrad, automatic prompt optimization
4. Code generation prompts - Aider, Cline, Cursor patterns
5. Error recovery patterns - structured retry, fallback chains

Let me search for recent developments in these areas.## Turn 3: Fresh External Probe

**EMA confidence**: 0.34 — switching to NEW external sources. Probing for high-signal before deep-reading.Let me analyze the search results:

1. **Emacs gptel MCP** - Found good results. The karthink/gptel repo is the main gptel repo (not the davidwuchn fork). There's also gptel.org, some blog posts about setup. The Martin Sukany blog and kaorubb.org blogs look interesting with tool ecosystem patterns.

2. **AI agent retry error recovery** - Multiple good results. The fast.io article looks comprehensive, the aiagentsblog.com has 5 patterns, and the gocodeo.com article covers validation checkpoints and fallback prompts. The callsphere.ai article distinguishes retry vs self-healing. The mindra.co article covers fault-tolerant patterns.

3. **LLM self-evolution DSPy TextGrad** - The arxiv paper on DSPy-based optimization (2604.04869) is a primary source. The dipankar.cc survey of automated prompt optimization from AutoPrompt to TextGrad is comprehensive. The morphllm.com comparison guide is recent (2026).

Now I need to probe these sources - skim titles/abstracts to determine which ones to deep-read. Let me fetch the most promising ones:

For retry/error patterns:
- fast.io - comprehensive patterns
- callsphere.ai - self-healing vs retry distinction

For Emacs gptel MCP:
- sukany.cz blog - tool ecosystem layers
- kaorubb.org - MCP setup

For self-evolution:
- arxiv.org/abs/2604.04869 - DSPy paper
- dipankar.cc - survey
- morphllm.com - SPO cost-effective approach

Let me probe the most promising ones. I'll pick:
1. The SPO paper/approach from morphllm.com - cost-effective prompt optimization
2. The callsphere.ai self-healing vs retry distinction
3. The sukany.cz emacs gptel tool ecosystem layers

Let me fetch these.Good signal across all three topic areas. Let me probe the most promising sources:Excellent! The callsphere.ai article is very rich with patterns. Let me also fetch the SPO paper abstract and the dipankar.cc survey for the self-evolution topic.

Let me now synthesize findings. I have:

1. **callsphere.ai** - Very detailed error recovery patterns:
   - Circuit breaker pattern with CLOSED/OPEN/HALF_OPEN states
   - Per-model circuit breakers for isolation
   - Exponential backoff with jitter
   - Fallback agent routing with priority-ordered providers
   - Error classification (retryable vs fatal)
   - Self-correction loops with validators
   - Graceful degradation with capability flags
   - Resilience metrics tracking

2. **sukany.cz** - Emacs gptel setup patterns:
   - Multi-backend centralized config
   - Model preference list with fallthrough
   - Dynamic model discovery from API
   - Model name normalization (dots vs dashes)
   - gptel-rewrite dispatch mode (Accept/Reject/Diff/Merge)
   - Three-layer tool ecosystem
   - Copilot auth flow with session token caching
   - curl over url.el for corporate proxy

3. **morphllm.com** - The page I fetched was just testimonials, not the actual content. Let me try the arxiv paper instead.

Let me now also check the DSPy arxiv paper and the dipankar.cc survey.The callsphere article is extremely rich. Let me also probe the DSPy survey and the arxiv paper for the self-evolution angle:Now I have substantial research material. Let me synthesize the findings into a compact digest.

Key findings to report:

**From callsphere.ai (error recovery)**:
1. Circuit breaker pattern with CLOSED/OPEN/HALF_OPEN states - applicable to our LLM backend failover (provider-error-analyzer skill)
2. Per-model circuit breakers for isolation - prevent one provider from taking down all
3. Exponential backoff with jitter
4. Fallback agent routing with priority-ordered providers
5. Error classification (retryable vs fatal) - mirrors our provider-error-analyzer
6. Self-correction loops with output validators
7. Graceful degradation with capability flags

**From sukany.cz (Emacs gptel setup)**:
1. Multi-backend centralized config with model preference list fallthrough
2. Dynamic model discovery from APIs
3. Model name normalization (dots vs dashes)
4. gptel-rewrite dispatch mode
5. Three-layer tool ecosystem (llm-tool-collection, ragmacs, gptel-got)
6. MCP integration via mcp-hub
7. curl over url.el for corporate proxy reliability

**From dipankar.cc (prompt optimization survey)**:
1. APO: "natural language gradient descent" - LLM examines failures, generates critique, edits prompt
2. OPRO: LLM as optimizer with meta-prompt showing prior solutions and scores
3. DSPy: declarative pipeline compilation
4. EvoPrompt: evolutionary algorithms for prompt search
5. Prompt optimization works on closed APIs since 2022

**From arxiv (DSPy paper)**:
1. 30-45% improvement in factual accuracy
2. 25% reduction in hallucination rates
3. Unified architecture: symbolic planning + gradient-free optimization + automated module rewriting

Now let me think about what's *actionable* for our Emacs Lisp AI agent system:

For auto-workflow / self-evolution:
- APO pattern: our auto-workflow already does hypothesis-driven experimentation. We could add the "natural language gradient" pattern: after each experiment, have the LLM analyze why it failed, generate a critique, and use that to guide the next hypothesis. This is essentially what our grader agent does, but we could make it more explicit.
- OPRO pattern: maintain a table of past strategies with scores, feed them to the LLM when generating new strategies. Our results.tsv already tracks this.

For error recovery:
- Circuit breaker: per-backend circuit breaker with state tracking. Our provider-error-analyzer could be extended to track failure counts and implement the HALF_OPEN recovery pattern.
- Error classification: we already have this in provider-error-analyzer but the retryable vs fatal distinction could be sharpened.
- Self-correction loops: our auto-workflow already has grader → fixer cycles, but we could add structured output validators.

For multi-backend:
- Model preference list with fallthrough: applicable to our LLM backend selection
- Dynamic model discovery: our backends already fetch models, but we could add a preference-based auto-selection

Let me now write a compact digest. I'll focus on the highest-impact, most actionable insights.

**Digested Insights:**

> Project: /home/davidwu/.emacs.d/
> Updated: 2026-05-31 07:03

Researcher result for task: External research turn 1/3

<think>
Let me analyze this research request. The user wants me to:

1. Research external sources for actionable techniques related to AI agent architectures
2. Prioritize davidwuchn's own repos (nucleus, mementum, gptel) since own-repo has the highest effectiveness score (0.60)
3. Follow the source directive: Start with own repos, then 1-2 external references
4. Budget: 55% own repos, 15% external

The current research performance shows:
- own-repo has the highest effectiveness (0.60)
- external has low effectiveness (0.14)
- 10 recent failure patterns noted

Let me start by checking davidwuchn's repos on GitHub, then potentially do 1-2 external searches.

I should:
1. WebFetch the three priority repos (nucleus, mementum, gptel)
2. Extract 1-3 patterns from each
3. Do minimal external research (1-2 sources)
4. Synthesize findings

Let me start with the own repos.
</think>## Research Pipeline: External Discovery

**Strategy**: Own-repos-first (55% budget allocation)
**Source effectiveness**: own-repo=0.60 (HIGH PRIORITY), external=0.14 (LOW)

Starting with davidwuchn's repos since own-repo effectiveness is 4x higher than external.<think>
Let me read the full content of these repos to extract architectural patterns. The temp files are large, let me read specific parts.
</think><think>
Now let me get more specific architecture patterns from gptel, particularly around tool use and MCP integration since that's a key feature.
</think><think>
Let me read more to get tool use and MCP integration details from gptel.
</think><think>
Now let me read more about gptel-agent for the agentic workflow patterns.
</think><think>
Now let me check for specific patterns I can extract. I have enough context now. Let me do a quick external search on AI agent workflow patterns for Emacs, specifically focusing on areas not covered.
</think>Now let me do 1-2 external searches to complement the own-repo research:<think>
Excellent! I found a direct reference to karthink/gptel-agent. Let me fetch that since it's directly relevant.
</think><think>
Excellent! Now I have comprehensive information. Let me synthesize the findings:

## External Sources (Own Repos)

1. **nucleus**: Attention magnet theory using mathematical symbols (phi, fractal, euler, etc.) to prime model attention toward formal reasoning patterns. Lambda notation as a compression layer.

2. **mementum**: Git-based memory protocol with session continuity. Three storage types (working memory, memories, knowledge), seven operations, human governance.

3. **gptel**: Multi-backend LLM client with tool-use, MCP integration, and agentic capabilities.

4. **karthink/gptel-agent**: Sub-agent delegation pattern - executor, researcher, introspector. Parallel delegation, context isolation.

## External Patterns

- Error recovery patterns: exponential backoff, fallback chains
- Multi-step reasoning: plan-act-reflect loop
- Silent failure detection in agent traces

Let me write the research digest with actionable techniques.
</think>

---

## Local Codebase Analysis (fallback — external research unavailable)

> Auto-generated from local git history, experiment results, and codebase scan.

## Git Activity (last 30 commits to lisp/modules/)

- **18** bug fixes
- **9** feature/evolution commits
- Focus: stabilization

## Module Complexity (top 5 by lines)

```
64310 total
   6056 lisp/modules/gptel-auto-workflow-evolution.el
   3231 lisp/modules/gptel-auto-workflow-ontology-router.el
   3070 lisp/modules/gptel-tools-agent-prompt-build.el
   2803 lisp/modules/gptel-auto-workflow-strategic.el
```

**Self-Evolution Directive:** Focus on the highest-failure modules above. Apply nil-safety patterns and validation guards to reduce failure rates.

---

Researcher result for task: External research turn 3/3

The user wants me to continue researching external sources. This is turn 3+, and the EMA confidence is 0.34 (low). I need to be concise and focus on highest-impact insights. The controller is telling me to switch to NEW sources since previous sources were "DEVIANT" - meaning the own-repo research approach wasn't yielding great results.

Let me focus on external sources now:
- Search for AI agent architectures, Emacs AI integration patterns, LLM self-evolution
- Use WebSearch to find recent/relevant items
- Probe source titles/abstracts before deep reading
- 100% external priority

Let me think about the most promising areas to search:
1. AI agent architectures - Anthropic's patterns, LangChain, AutoGPT patterns
2. Emacs Lisp AI integration - gptel, ellama, org-ai
3. LLM self-evolution - DSPy, TextGrad, automatic prompt optimization
4. Code generation prompts - Aider, Cline, Cursor patterns
5. Error recovery patterns - structured retry, fallback chains

Let me search for recent developments in these areas.## Turn 3: Fresh External Probe

**EMA confidence**: 0.34 — switching to NEW external sources. Probing for high-signal before deep-reading.Let me analyze the search results:

1. **Emacs gptel MCP** - Found good results. The karthink/gptel repo is the main gptel repo (not the davidwuchn fork). There's also gptel.org, some blog posts about setup. The Martin Sukany blog and kaorubb.org blogs look interesting with tool ecosystem patterns.

2. **AI agent retry error recovery** - Multiple good results. The fast.io article looks comprehensive, the aiagentsblog.com has 5 patterns, and the gocodeo.com article covers validation checkpoints and fallback prompts. The callsphere.ai article distinguishes retry vs self-healing. The mindra.co article covers fault-tolerant patterns.

3. **LLM self-evolution DSPy TextGrad** - The arxiv paper on DSPy-based optimization (2604.04869) is a primary source. The dipankar.cc survey of automated prompt optimization from AutoPrompt to TextGrad is comprehensive. The morphllm.com comparison guide is recent (2026).

Now I need to probe these sources - skim titles/abstracts to determine which ones to deep-read. Let me fetch the most promising ones:

For retry/error patterns:
- fast.io - comprehensive patterns
- callsphere.ai - self-healing vs retry distinction

For Emacs gptel MCP:
- sukany.cz blog - tool ecosystem layers
- kaorubb.org - MCP setup

For self-evolution:
- arxiv.org/abs/2604.04869 - DSPy paper
- dipankar.cc - survey
- morphllm.com - SPO cost-effective approach

Let me probe the most promising ones. I'll pick:
1. The SPO paper/approach from morphllm.com - cost-effective prompt optimization
2. The callsphere.ai self-healing vs retry distinction
3. The sukany.cz emacs gptel tool ecosystem layers

Let me fetch these.Good signal across all three topic areas. Let me probe the most promising sources:Excellent! The callsphere.ai article is very rich with patterns. Let me also fetch the SPO paper abstract and the dipankar.cc survey for the self-evolution topic.

Let me now synthesize findings. I have:

1. **callsphere.ai** - Very detailed error recovery patterns:
   - Circuit breaker pattern with CLOSED/OPEN/HALF_OPEN states
   - Per-model circuit breakers for isolation
   - Exponential backoff with jitter
   - Fallback agent routing with priority-ordered providers
   - Error classification (retryable vs fatal)
   - Self-correction loops with validators
   - Graceful degradation with capability flags
   - Resilience metrics tracking

2. **sukany.cz** - Emacs gptel setup patterns:
   - Multi-backend centralized config
   - Model preference list with fallthrough
   - Dynamic model discovery from API
   - Model name normalization (dots vs dashes)
   - gptel-rewrite dispatch mode (Accept/Reject/Diff/Merge)
   - Three-layer tool ecosystem
   - Copilot auth flow with session token caching
   - curl over url.el for corporate proxy

3. **morphllm.com** - The page I fetched was just testimonials, not the actual content. Let me try the arxiv paper instead.

Let me now also check the DSPy arxiv paper and the dipankar.cc survey.The callsphere article is extremely rich. Let me also probe the DSPy survey and the arxiv paper for the self-evolution angle:Now I have substantial research material. Let me synthesize the findings into a compact digest.

Key findings to report:

**From callsphere.ai (error recovery)**:
1. Circuit breaker pattern with CLOSED/OPEN/HALF_OPEN states - applicable to our LLM backend failover (provider-error-analyzer skill)
2. Per-model circuit breakers for isolation - prevent one provider from taking down all
3. Exponential backoff with jitter
4. Fallback agent routing with priority-ordered providers
5. Error classification (retryable vs fatal) - mirrors our provider-error-analyzer
6. Self-correction loops with output validators
7. Graceful degradation with capability flags

**From sukany.cz (Emacs gptel setup)**:
1. Multi-backend centralized config with model preference list fallthrough
2. Dynamic model discovery from APIs
3. Model name normalization (dots vs dashes)
4. gptel-rewrite dispatch mode
5. Three-layer tool ecosystem (llm-tool-collection, ragmacs, gptel-got)
6. MCP integration via mcp-hub
7. curl over url.el for corporate proxy reliability

**From dipankar.cc (prompt optimization survey)**:
1. APO: "natural language gradient descent" - LLM examines failures, generates critique, edits prompt
2. OPRO: LLM as optimizer with meta-prompt showing prior solutions and scores
3. DSPy: declarative pipeline compilation
4. EvoPrompt: evolutionary algorithms for prompt search
5. Prompt optimization works on closed APIs since 2022

**From arxiv (DSPy paper)**:
1. 30-45% improvement in factual accuracy
2. 25% reduction in hallucination rates
3. Unified architecture: symbolic planning + gradient-free optimization + automated module rewriting

Now let me think about what's *actionable* for our Emacs Lisp AI agent system:

For auto-workflow / self-evolution:
- APO pattern: our auto-workflow already does hypothesis-driven experimentation. We could add the "natural language gradient" pattern: after each experiment, have the LLM analyze why it failed, generate a critique, and use that to guide the next hypothesis. This is essentially what our grader agent does, but we could make it more explicit.
- OPRO pattern: maintain a table of past strategies with scores, feed them to the LLM when generating new strategies. Our results.tsv already tracks this.

For error recovery:
- Circuit breaker: per-backend circuit breaker with state tracking. Our provider-error-analyzer could be extended to track failure counts and implement the HALF_OPEN recovery pattern.
- Error classification: we already have this in provider-error-analyzer but the retryable vs fatal distinction could be sharpened.
- Self-correction loops: our auto-workflow already has grader → fixer cycles, but we could add structured output validators.

For multi-backend:
- Model preference list with fallthrough: applicable to our LLM backend selection
- Dynamic model discovery: our backends already fetch models, but we could add a preference-based auto-selection

Let me now write a compact digest. I'll focus on the highest-impact, most actionable insights.

**Meta-learning:** Research quality measured by downstream experiment success.

---
*Generated by auto-workflow*
