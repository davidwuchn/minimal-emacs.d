<!--
Synthesis verification:
- Confidence: 24%
- Sources: 8 memories
- Warnings: No code examples or concrete references, Content does not mention topic 'research-research-persisted'
- Auto-approved: yes (flagged)
--->

---
title: Research Persistence and Agent Resilience Patterns
status: active
category: knowledge
tags: [research, auto-workflow, agent, resilience, circuit-breaker, mementum, context-reduction, watchdog]
---

# Research Persistence and Agent Resilience Patterns

## Research Persistence Strategy

The `persisted-findings` strategy attempts to inject external research into the auto-workflow pipeline before experiment generation. Historical retention rates are poor (0–33%), indicating a structural mismatch between raw research volume and actionable experiment surface.

| Date | Findings Hash | Targets | Kept | Rate |
|------|---------------|---------|------|------|
| 2026-05-25 | e438c226... | benchmark, error, prompt-build, strategic, projects | 0/15 | 0% |
| 2026-05-27 | da0fbbb6... | fsm-utils, research-integration, staging-review | 0/7 | 0% |
| 2026-05-25 | befd494e... | benchmark-evolution, staging-review, research-integration, verification | 1/24 | 4% |
| 2026-05-22 | 1d3ac048... | preview, mementum, error, runtime, merge, fsm-utils | 2/56 | 4% |
| 2026-05-20 | 9af4a35c... | memory, benchmark-integrate, ext-core, tools, benchmark-memory | 4/24 | 17% |
| 2026-05-22 | 9bbb457e... | runtime, memory, merge, fsm, permits, abort | 9/39 | 23% |

**Pattern:** Low retention correlates with unfiltered raw dumps and missing machine-parseable structure. Every experiment row must include a non-nil research hash so `results.tsv` can link outcomes back to the research trace. Treat missing research files as a pipeline defect, not a successful empty run.

**Actionable guard:**
```elisp
(defun workflow--validate-research-signal (hash targets)
  "Fail fast if research signal is missing or malformed."
  (unless (and hash (not (string= hash "none")) targets)
    (error "Pipeline defect: missing research trace"))
  (list :research-hash hash
        :targets targets
        :timestamp (current-time)))
```

## Nil-Safety and Validation Guards

Local codebase analysis identifies the highest-failure modules by line count and bug-fix velocity. The current stabilization phase shows 8 bug fixes and 0 feature commits over the last 30 commits to `lisp/modules/`.

**High-failure modules (by complexity):**
- `gptel-auto-workflow-evolution.el` (5,822 LOC)
- `gptel-auto-workflow-strategic.el` (2,698 LOC)
- `gptel-tools-agent-prompt-build.el` (2,431 LOC)
- `gptel-auto-workflow-research-benchmark.el` (1,742 LOC)

**Actionable pattern:** Apply nil-safety and validation guards at module boundaries.
```elisp
(defun workflow--with-guard (fn &rest args)
  "Execute FN with nil-safety and validation."
  (condition-case err
      (let ((result (apply fn args)))
        (unless result
          (warn "Nil result from %s" fn))
        result)
    (error
     (message "Guard caught error in %s: %s" fn err)
     nil)))
```

## Daemon Orchestration and Fail-Fast Fallbacks

When the dedicated researcher daemon disappears after being observed, the pipeline must fall back immediately rather than waiting for the global timeout.

**Pipeline defect checklist:**
1. Missing findings file after daemon wait → fallback to local codebase scan
2. Every experiment row must carry `:research-hash` (non-none)
3. Prefer structured outputs with `source`, `technique`, `apply-to-us`, `verification` fields
4. Global timeout should not mask daemon death

**Actionable pattern:**
```elisp
(defun workflow--await-research (daemon-id timeout-sec)
  "Wait for DAEMON-ID output up to TIMEOUT-SEC seconds.
Fail fast if process disappears."
  (let ((start (float-time)))
    (while (and (< (- (float-time) start) timeout-sec)
                (process-live-p daemon-id)
                (not (file-exists-p workflow--research-output-file)))
      (sleep-for 0.5))
    (cond
     ((not (process-live-p daemon-id))
      (error "Daemon orchestration defect: researcher died"))
     ((not (file-exists-p workflow--research-output-file))
      (error "Research timeout: no findings produced"))
     (t (workflow--parse-findings workflow--research-output-file)))))
```

## Resilience Patterns: Circuit Breakers and Checkpoints

Research from `efrit` and external production patterns suggests a five-category failure taxonomy and a graduated circuit breaker.

**Failure categories:**
| Category | Example | Response |
|----------|---------|----------|
| Hard | Segfault, kill -9 | Immediate abort, checkpoint |
| Structural | JSON parse error, schema mismatch | Retry with corrected schema |
| Semantic | Wrong tool selected, hallucinated file | Degraded mode, human flag |
| Behavioral | Infinite loop, retry storm | Circuit breaker OPEN |
| Resource | OOM, rate limit | Exponential backoff, fallback provider |

**Circuit breaker state machine:**
```
CLOSED ──[3 consecutive failures]──► DEGRADED ──[2 more failures]──► OPEN
  ▲                                    │                              │
  │                                    │                              │
  └──[success]─────────────────────────┘    └──[timeout/recovery]────┘
```

In **DEGRADED** mode, disable risky tools, enable human review flags, and reduce traffic to 20%. In **OPEN** mode, reject requests for 60 seconds or switch to fallback provider chain: OpenAI → Anthropic → Ollama.

**Actionable implementation sketch:**
```elisp
(defcustom gptel-circuit-breaker-threshold 3
  "Consecutive failures before entering DEGRADED."
  :type 'integer)

(defvar gptel--circuit-state 'CLOSED)
(defvar gptel--failure-streak 0)

(defun gptel--record-failure ()
  (cl-incf gptel--failure-streak)
  (when (>= gptel--failure-streak gptel-circuit-breaker-threshold)
    (setq gptel--circuit-state 'DEGRADED)
    (run-with-timer 300 nil (lambda () (setq gptel--circuit-state 'CLOSED)))))
```

## Three-Tier Watchdog Architecture

From `gastown`, separate session lifecycle into three tiers:

| Tier | Responsibility | Emacs Mapping |
|------|---------------|---------------|
| Witness | Session lifecycle, startup/shutdown | `workflow--witness` |
| Deacon | Continuous background patrol | `workflow--deacon` timer |
| Dogs | Dispatched cleanup/error recovery | `workflow--dogs` async tasks |

**Convoy pattern:** Bundle work items with autonomous stall detection. If a subagent task hangs for >300s, dispatch a Dog to kill and checkpoint.

```elisp
(defun workflow--spawn-dog (task-id buffer)
  "Dispatch cleanup for TASK-ID if stall detected."
  (run-with-timer 300 nil
    (lambda ()
      (when (eq (process-status task-id) 'run)
        (interrupt-process task-id)
        (workflow--checkpoint buffer :reason 'stall)))))
```

## Context Reduction: Think-in-Code

From `context-mode`, avoid dumping 700 KB of raw file reads into the LLM context. Instead, execute an analysis script in an isolated subprocess and return only the structured result (3.6 KB), achieving 98% context reduction.

**Actionable pattern:**
```elisp
(defun gptel-sandbox-execute (script inputs)
  "Run SCRIPT against INPUTS in isolated Emacs child.
Return only structured result, never raw data."
  (let ((tmp (make-temp-file "sandbox-")))
    (with-temp-file tmp (insert (prin1-to-string inputs)))
    (with-output-to-string
      (call-process "emacs" nil standard-output nil
                    "-Q" "--batch" "--load" script "--eval"
                    (format "(sandbox-analyze %S)" tmp)))))
```

## Session Continuity and Memory Protocol

From `mementum`, use three storage types for feed-forward memory:
1. **Working memory** (`state.md`) — current session scratchpad
2. **Memories** (<200 words) — atomic observations
3. **Synthesized knowledge** — human-approved knowledge pages

From `context-mode`, persist events in SQLite with FTS5. When context compacts, retrieve only relevant events via BM25 search.

**Schema sketch:**
```sql
CREATE TABLE events (
  session_id TEXT,
  timestamp INTEGER,
  event_type TEXT,
  data TEXT
);
CREATE VIRTUAL TABLE events_fts USING fts5(data);
```

**Human governance loop:** AI proposes a knowledge page → human approves → AI commits to `knowledge/`. This prevents unbounded memory growth and ensures quality.

## Evaluation Metrics: Trajectory-Aware Quality

Research quality must be measured by downstream experiment success, not by output volume. Adopt trajectory-aware metrics from the NVIDIA evaluation guide:

| Metric | Definition | Target |
|--------|-----------|--------|
| Task Success Rate (TSR) | Intent resolved within constraints | >0.70 |
| Tool Call Accuracy | Schema compliance, correct function | >0.85 |
| Trajectory Efficiency | Steps per success | Minimize |
| Reasoning Soundness | Evidence usage in trace | Audit |

**Actionable pattern:** Log complete trajectories (plan, tool calls, outcomes) and compute TSR per experiment type. Use this to gate self-evolution: only promote patterns with TSR > 0.70 over 5 consecutive experiments.

```elisp
(defun workflow--compute-tsr (experiment-type rows)
  "Return success ratio for EXPERIMENT-TYPE from ROWS."
  (let ((subset (seq-filter (lambda (r) (equal (plist-get r :type) experiment-type)) rows))
        (successes (seq-filter (lambda (r) (plist-get r :success)) rows)))
    (/ (float (length successes)) (max 1 (length subset)))))
```

## Self-Wiring Knowledge Graph

From `gbrain`, extract `[[entity]]` references on every page write and create typed edges (`attended`, `works_at`, `founded`) with zero LLM calls. This yields +31.4 P@5 lift over vector-only RAG.

**Actionable pattern:**
```elisp
(defun mementum--extract-typed-links (content)
  "Return alist of (entity . type) from CONTENT."
  (let ((links nil))
    (while (string-match "\\[\\[\\([^]]+\\)/\\([^]]+\\)/\\([^]]+\\)\\]\\]" content (match-end 0))
      (push (cons (match-string 3 content) (match-string 1 content)) links))
    links))
```

## Related

- [[mementum]] — Feed-forward memory protocol and human governance loop
- [[gptel-auto-workflow]] — Daemon orchestration and experiment pipeline
- [[gptel-ext-fsm]] — Statechart-driven workflow states
- [[circuit-breaker]] — Graduated failure handling and provider fallback chains
- [[checkpoint-restore]] — Session snapshots before risky operations
- [[agent-evaluation]] — TSR and trajectory efficiency metrics
- [[think-in-code]] — Context reduction via sandboxed analysis scripts

---

Let me count lines to ensure minimum 50 lines of actual content. The content above looks well over 50 lines. It has concrete examples (elisp code, SQL schema, tables), actionable patterns, cross-references. Frontmatter is included. I should make sure it's comprehensive and directly written.

One thing: I should ensure the frontmatter format matches exactly what was requested.

Also, I need to make sure I include all the synthesized insights without truncating. The user said "Return the complete knowledge page inline, not a summary" and "Do not describe what you would write; write the page itself".

The draft above looks good. Let me refine it slightly to ensure smooth flow and add a bit more detail to meet the 50+ lines robustly (it already does, but more substance is better).

I should also integrate the meta-learning insight: "Research quality measured by downstream experiment success."

And the Azure AI Agent Orchestration Spectrum could be a good table to include.

Let me expand the orchestration spectrum section slightly and make sure everything ties together.

Actually, looking at the memories again, there's the "Three-Loop Meta-Learning Architecture" from HyperAgents: Task Execution → Evaluation → Self-Improvement. I should mention that briefly.

Let me also include the `[PLAN] + [EXPECT]` pattern from genesis-agent with P(success) confidence scoring.

Let me adjust the structure:

1. Research Persistence Strategy (retention rates, structured output requirement)
2. Daemon Orchestration and Fail-Fast Fallbacks (pipeline defects, fail-fast)
3. Nil-Safety and Validation Guards (high-failure modules, guards)
4. Resilience Patterns (circuit breaker, failure taxonomy, degraded mode)
5. Three-Tier Watchdog Architecture (witness/deacon/dogs)
6. Context Reduction and Session Continuity (think-in-code, sandbox, SQLite)
7. Memory and Knowledge Protocols (mementum 3-tier, gbrain auto-linking)
8. Evaluation and Meta-Learning (TSR, trajectory metrics, three-loop, P(success))
9. Related

This gives a solid 50+ lines easily.

Let me write the final output now.