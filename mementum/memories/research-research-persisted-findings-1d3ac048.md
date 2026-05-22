# Research: 2026-05-22 04:11

**Strategy:** persisted-findings
**Findings hash:** 1d3ac048f3b65e66d1b03bbba845d2612b8f9628
**Targets:** lisp/modules/gptel-tools-preview.el, staging-verification, lisp/modules/gptel-auto-workflow-mementum.el, lisp/modules/gptel-tools-agent-error.el, lisp/modules/gptel-tools-agent-runtime.el, staging-merge, lisp/modules/gptel-ext-fsm-utils.el
**Outcome:** 2/56 kept (4%)

**Raw Findings:**

> Project: /home/davidwu/.emacs.d/
> Updated: 2026-05-21 23:07

Researcher result for task: External research turn 1/6

I'll systematically research the priority repos, starting with own repos as directed by the evolved controller config (80% own repo priority).Now let me systematically research the priority repos. Starting with Tier 1 (directly applicable):Now let me research Tier 2 repos for agent architecture patterns:Now let me check Tier 3 repos and search for external patterns:Now let me check the existing auto-workflow codebase to understand what's already implemented:Now I have comprehensive data. Let me synthesize the findings:

---

## Research Digest: External Research Insights

### Technique 1: Three-Tier Watchdog Architecture
- **Source type**: GitHub (gastown)
- **Impact**: HIGH
- **Difficulty**: MEDIUM
- **Description**: Systematized lifecycle management via three tiers: Witness (session lifecycle), Deacon (continuous background patrol), Dogs (dispatched workers). Convoy system bundles work items with autonomous stall detection.
- **Application**: Implement in `gptel-auto-workflow-daemon.el` — separate watchdog from execution logic
- **Implementation sketch**: Define `workflow--witness` for session health, `workflow--deacon` for periodic health checks, `workflow--dogs` for dispatched cleanup/error recovery tasks

### Technique 2: Think-in-Code Context Reduction
- **Source type**: GitHub (context-mode)
- **Impact**: HIGH  
- **Difficulty**: HARD
- **Description**: Instead of dumping 700KB via 47× Read() calls, agent writes a script that computes and returns only the answer. Achieves 98% context reduction. Session continuity via SQLite/FTS5 indexed events.
- **Application**: Refactor `gptel-auto-workflow-projects.el` analysis passes to accept executable analysis scripts instead of data dumps
- **Implementation sketch**: Create `workflow--compute` function that accepts elisp analysis scripts, runs them in isolated context, returns only structured results

### Technique 3: DEGRADED State Circuit Breaker
- **Source type**: External (Hannecke Medium article)
- **Impact**: MEDIUM
- **Difficulty**: MEDIUM
- **Description**: Five failure categories (Hard, Structural, Semantic, Behavioral, Resource) need different handling. DEGRADED state between CLOSED/OPEN allows graceful degradation instead of hard fail. Graduated re-enablement: L1 (5% traffic), L2 (20%), L3 (50%).
- **Application**: Enhance `gptel-auto-workflow-daemon.el` circuit breaker with graduated capability reduction
- **Implementation sketch**: After 3 consecutive failures → disable risky tools, add human review flag, switch to conservative mode before hard stop

### Technique 4: Hybrid Search Fusion (Vector + BM25)
- **Source type**: GitHub (gbrain)
- **Impact**: MEDIUM
- **Difficulty**: HARD
- **Description**: P@5 49.1% via hybrid search combining vector embeddings + BM25 keyword + reciprocal-rank fusion. ZeroEntropy embeddings 2.2× faster than OpenAI, wins 11/20 head-to-head queries.
- **Application**: Improve `gptel-auto-workflow-projects.el` target selection with hybrid retrieval over git history
- **Implementation sketch**: Use `ollama` embeddings + `ripgrep` BM25 for project history search

### Technique 5: Self-Wiring Knowledge Graph
- **Source type**: GitHub (gbrain)
- **Impact**: MEDIUM
- **Difficulty**: HARD
- **Description**: Every page write extracts entity references and creates typed links (attended, works_at, invested_in) with zero LLM calls. Graph produces +31.4 P@5 lift over vector-only RAG.
- **Application**: Add entity linking to `mementum--memory` system for cross-experiment knowledge graph
- **Implementation sketch**: Parse [[wiki/people/bob]] style references in memories, create typed edges in knowledge base

### Technique 6: Three-Loop Meta-Learning Architecture
- **Source type**: arXiv (HyperAgents)
- **Impact**: HIGH
- **Difficulty**: MEDIUM
- **Description**: Task Execution (ReAct-style) → Evaluation (test-based feedback) → Self-Improvement (metacognitive self-modification). Unified agent + meta a
...[Result too large, truncated. Full result saved to: /home/davidwu/.emacs.d/tmp/gptel-subagent-result-zgnSS9.txt. Use Read tool if you need more]...

---

Researcher result for task: External research turn 1/6

I'll systematically research the priority repos, starting with own repos as directed by the evolved controller config (80% own repo priority).Now let me systematically research the priority repos. Starting with Tier 1 (directly applicable):Now let me research Tier 2 repos for agent architecture patterns:Now let me check Tier 3 repos and search for external patterns:Now let me check the existing auto-workflow codebase to understand what's already implemented:Now I have comprehensive data. Let me synthesize the findings:

---

## Research Digest: External Research Insights

### Technique 1: Three-Tier Watchdog Architecture
- **Source type**: GitHub (gastown)
- **Impact**: HIGH
- **Difficulty**: MEDIUM
- **Description**: Systematized lifecycle management via three tiers: Witness (session lifecycle), Deacon (continuous background patrol), Dogs (dispatched workers). Convoy system bundles work items with autonomous stall detection.
- **Application**: Implement in `gptel-auto-workflow-daemon.el` — separate watchdog from execution logic
- **Implementation sketch**: Define `workflow--witness` for session health, `workflow--deacon` for periodic health checks, `workflow--dogs` for dispatched cleanup/error recovery tasks

### Technique 2: Think-in-Code Context Reduction
- **Source type**: GitHub (context-mode)
- **Impact**: HIGH  
- **Difficulty**: HARD
- **Description**: Instead of dumping 700KB via 47× Read() calls, agent writes a script that computes and returns only the answer. Achieves 98% context reduction. Session continuity via SQLite/FTS5 indexed events.
- **Application**: Refactor `gptel-auto-workflow-projects.el` analysis passes to accept executable analysis scripts instead of data dumps
- **Implementation sketch**: Create `workflow--compute` function that accepts elisp analysis scripts, runs them in isolated context, returns only structured results

### Technique 3: DEGRADED State Circuit Breaker
- **Source type**: External (Hannecke Medium article)
- **Impact**: MEDIUM
- **Difficulty**: MEDIUM
- **Description**: Five failure categories (Hard, Structural, Semantic, Behavioral, Resource) need different handling. DEGRADED state between CLOSED/OPEN allows graceful degradation instead of hard fail. Graduated re-enablement: L1 (5% traffic), L2 (20%), L3 (50%).
- **Application**: Enhance `gptel-auto-workflow-daemon.el` circuit breaker with graduated capability reduction
- **Implementation sketch**: After 3 consecutive failures → disable risky tools, add human review flag, switch to conservative mode before hard stop

### Technique 4: Hybrid Search Fusion (Vector + BM25)
- **Source type**: GitHub (gbrain)
- **Impact**: MEDIUM
- **Difficulty**: HARD
- **Description**: P@5 49.1% via hybrid search combining vector embeddings + BM25 keyword + reciprocal-rank fusion. ZeroEntropy embeddings 2.2× faster than OpenAI, wins 11/20 head-to-head queries.
- **Application**: Improve `gptel-auto-workflow-projects.el` target selection with hybrid retrieval over git history
- **Implementation sketch**: Use `ollama` embeddings + `ripgrep` BM25 for project history search

### Technique 5: Self-Wiring Knowledge Graph
- **Source type**: GitHub (gbrain)
- **Impact**: MEDIUM
- **Difficulty**: HARD
- **Description**: Every page write extracts entity references and creates typed links (attended, works_at, invested_in) with zero LLM calls. Graph produces +31.4 P@5 lift over vector-only RAG.
- **Application**: Add entity linking to `mementum--memory` system for cross-experiment knowledge graph
- **Implementation sketch**: Parse [[wiki/people/bob]] style references in memories, create typed edges in knowledge base

### Technique 6: Three-Loop Meta-Learning Architecture
- **Source type**: arXiv (HyperAgents)
- **Impact**: HIGH
- **Difficulty**: MEDIUM
- **Description**: Task Execution (ReAct-style) → Evaluation (test-based feedback) → Self-Improvement (metacognitive self-modification). Unified agent + meta a
...[Result too large, truncated. Full result saved to: /home/davidwu/.emacs.d/tmp/gptel-subagent-result-zgnSS9.txt. Use Read tool if you need more]...

**Digested Insights:**

> Project: /home/davidwu/.emacs.d/
> Updated: 2026-05-21 23:07

Researcher result for task: External research turn 1/6

I'll systematically research the priority repos, starting with own repos as directed by the evolved controller config (80% own repo priority).Now let me systematically research the priority repos. Starting with Tier 1 (directly applicable):Now let me research Tier 2 repos for agent architecture patterns:Now let me check Tier 3 repos and search for external patterns:Now let me check the existing auto-workflow codebase to understand what's already implemented:Now I have comprehensive data. Let me synthesize the findings:

---

## Research Digest: External Research Insights

### Technique 1: Three-Tier Watchdog Architecture
- **Source type**: GitHub (gastown)
- **Impact**: HIGH
- **Difficulty**: MEDIUM
- **Description**: Systematized lifecycle management via three tiers: Witness (session lifecycle), Deacon (continuous background patrol), Dogs (dispatched workers). Convoy system bundles work items with autonomous stall detection.
- **Application**: Implement in `gptel-auto-workflow-daemon.el` — separate watchdog from execution logic
- **Implementation sketch**: Define `workflow--witness` for session health, `workflow--deacon` for periodic health checks, `workflow--dogs` for dispatched cleanup/error recovery tasks

### Technique 2: Think-in-Code Context Reduction
- **Source type**: GitHub (context-mode)
- **Impact**: HIGH  
- **Difficulty**: HARD
- **Description**: Instead of dumping 700KB via 47× Read() calls, agent writes a script that computes and returns only the answer. Achieves 98% context reduction. Session continuity via SQLite/FTS5 indexed events.
- **Application**: Refactor `gptel-auto-workflow-projects.el` analysis passes to accept executable analysis scripts instead of data dumps
- **Implementation sketch**: Create `workflow--compute` function that accepts elisp analysis scripts, runs them in isolated context, returns only structured results

### Technique 3: DEGRADED State Circuit Breaker
- **Source type**: External (Hannecke Medium article)
- **Impact**: MEDIUM
- **Difficulty**: MEDIUM
- **Description**: Five failure categories (Hard, Structural, Semantic, Behavioral, Resource) need different handling. DEGRADED state between CLOSED/OPEN allows graceful degradation instead of hard fail. Graduated re-enablement: L1 (5% traffic), L2 (20%), L3 (50%).
- **Application**: Enhance `gptel-auto-workflow-daemon.el` circuit breaker with graduated capability reduction
- **Implementation sketch**: After 3 consecutive failures → disable risky tools, add human review flag, switch to conservative mode before hard stop

### Technique 4: Hybrid Search Fusion (Vector + BM25)
- **Source type**: GitHub (gbrain)
- **Impact**: MEDIUM
- **Difficulty**: HARD
- **Description**: P@5 49.1% via hybrid search combining vector embeddings + BM25 keyword + reciprocal-rank fusion. ZeroEntropy embeddings 2.2× faster than OpenAI, wins 11/20 head-to-head queries.
- **Application**: Improve `gptel-auto-workflow-projects.el` target selection with hybrid retrieval over git history
- **Implementation sketch**: Use `ollama` embeddings + `ripgrep` BM25 for project history search

### Technique 5: Self-Wiring Knowledge Graph
- **Source type**: GitHub (gbrain)
- **Impact**: MEDIUM
- **Difficulty**: HARD
- **Description**: Every page write extracts entity references and creates typed links (attended, works_at, invested_in) with zero LLM calls. Graph produces +31.4 P@5 lift over vector-only RAG.
- **Application**: Add entity linking to `mementum--memory` system for cross-experiment knowledge graph
- **Implementation sketch**: Parse [[wiki/people/bob]] style references in memories, create typed edges in knowledge base

### Technique 6: Three-Loop Meta-Learning Architecture
- **Source type**: arXiv (HyperAgents)
- **Impact**: HIGH
- **Difficulty**: MEDIUM
- **Description**: Task Execution (ReAct-style) → Evaluation (test-based feedback) → Self-Improvement (metacognitive self-modification). Unified agent + meta a
...[Result too large, truncated. Full result saved to: /home/davidwu/.emacs.d/tmp/gptel-subagent-result-zgnSS9.txt. Use Read tool if you need more]...

---

Researcher result for task: External research turn 1/6

I'll systematically research the priority repos, starting with own repos as directed by the evolved controller config (80% own repo priority).Now let me systematically research the priority repos. Starting with Tier 1 (directly applicable):Now let me research Tier 2 repos for agent architecture patterns:Now let me check Tier 3 repos and search for external patterns:Now let me check the existing auto-workflow codebase to understand what's already implemented:Now I have comprehensive data. Let me synthesize the findings:

---

## Research Digest: External Research Insights

### Technique 1: Three-Tier Watchdog Architecture
- **Source type**: GitHub (gastown)
- **Impact**: HIGH
- **Difficulty**: MEDIUM
- **Description**: Systematized lifecycle management via three tiers: Witness (session lifecycle), Deacon (continuous background patrol), Dogs (dispatched workers). Convoy system bundles work items with autonomous stall detection.
- **Application**: Implement in `gptel-auto-workflow-daemon.el` — separate watchdog from execution logic
- **Implementation sketch**: Define `workflow--witness` for session health, `workflow--deacon` for periodic health checks, `workflow--dogs` for dispatched cleanup/error recovery tasks

### Technique 2: Think-in-Code Context Reduction
- **Source type**: GitHub (context-mode)
- **Impact**: HIGH  
- **Difficulty**: HARD
- **Description**: Instead of dumping 700KB via 47× Read() calls, agent writes a script that computes and returns only the answer. Achieves 98% context reduction. Session continuity via SQLite/FTS5 indexed events.
- **Application**: Refactor `gptel-auto-workflow-projects.el` analysis passes to accept executable analysis scripts instead of data dumps
- **Implementation sketch**: Create `workflow--compute` function that accepts elisp analysis scripts, runs them in isolated context, returns only structured results

### Technique 3: DEGRADED State Circuit Breaker
- **Source type**: External (Hannecke Medium article)
- **Impact**: MEDIUM
- **Difficulty**: MEDIUM
- **Description**: Five failure categories (Hard, Structural, Semantic, Behavioral, Resource) need different handling. DEGRADED state between CLOSED/OPEN allows graceful degradation instead of hard fail. Graduated re-enablement: L1 (5% traffic), L2 (20%), L3 (50%).
- **Application**: Enhance `gptel-auto-workflow-daemon.el` circuit breaker with graduated capability reduction
- **Implementation sketch**: After 3 consecutive failures → disable risky tools, add human review flag, switch to conservative mode before hard stop

### Technique 4: Hybrid Search Fusion (Vector + BM25)
- **Source type**: GitHub (gbrain)
- **Impact**: MEDIUM
- **Difficulty**: HARD
- **Description**: P@5 49.1% via hybrid search combining vector embeddings + BM25 keyword + reciprocal-rank fusion. ZeroEntropy embeddings 2.2× faster than OpenAI, wins 11/20 head-to-head queries.
- **Application**: Improve `gptel-auto-workflow-projects.el` target selection with hybrid retrieval over git history
- **Implementation sketch**: Use `ollama` embeddings + `ripgrep` BM25 for project history search

### Technique 5: Self-Wiring Knowledge Graph
- **Source type**: GitHub (gbrain)
- **Impact**: MEDIUM
- **Difficulty**: HARD
- **Description**: Every page write extracts entity references and creates typed links (attended, works_at, invested_in) with zero LLM calls. Graph produces +31.4 P@5 lift over vector-only RAG.
- **Application**: Add entity linking to `mementum--memory` system for cross-experiment knowledge graph
- **Implementation sketch**: Parse [[wiki/people/bob]] style references in memories, create typed edges in knowledge base

### Technique 6: Three-Loop Meta-Learning Architecture
- **Source type**: arXiv (HyperAgents)
- **Impact**: HIGH
- **Difficulty**: MEDIUM
- **Description**: Task Execution (ReAct-style) → Evaluation (test-based feedback) → Self-Improvement (metacognitive self-modification). Unified agent + meta a
...[Result too large, truncated. Full result saved to: /home/davidwu/.emacs.d/tmp/gptel-subagent-result-zgnSS9.txt. Use Read tool if you need more]...

**Meta-learning:** Research quality measured by downstream experiment success.

---
*Generated by auto-workflow*
