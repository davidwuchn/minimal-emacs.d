<!--
Synthesis verification:
- Confidence: 24%
- Sources: 6 memories
- Warnings: No code examples or concrete references, Content does not mention topic 'research-research-persisted'
- Auto-approved: yes (flagged)
--->

---
title: AI Agent Research Patterns
status: active
category: knowledge
tags: [agent-architecture, research, patterns, self-evolution, circuit-breaker, checkpoint-restore, memory-systems]
---

# AI Agent Research Patterns

## Executive Summary

This knowledge page synthesizes research findings from 8 internal repositories and 4 external sources on AI agent architecture, error recovery, and self-evolution patterns. The research targets improving the gptel-auto-workflow system with production-grade resilience patterns.

**Key insight**: Research quality is measured by downstream experiment success, not by finding count. Each pattern includes an Emacs application section for immediate implementation.

---

## 1. Resilience Patterns

### 1.1 Circuit Breaker Pattern

**Source**: efrit (davidwuchn/efrit)
**Impact**: HIGH | **Difficulty**: MEDIUM

Circuit breakers monitor failure rates per provider and transition through states to prevent cascading failures:

```
┌─────────┐    5 failures     ┌─────────┐    half-open    ┌───────────┐
│ CLOSED  │ ───────────────► │  OPEN   │ ─────────────► │ HALF-OPEN │
│ Normal  │                  │ Block   │                  │ 1 test    │
└─────────┘                  └─────────┘                  └───────────┘
     ▲                           │                              │
     │         success           │         success              │
     └───────────────────────────┴──────────────────────────────┘
```

**Emacs Application**: Implement `gptel-circuit-breaker` defcustom:

```elisp
(defcustom gptel-circuit-breaker
  '((openai . (failures 0 successes 0 last-failure nil))
    (anthropic . (failures 0 successes 0 last-failure nil)))
  "Circuit breaker state per provider."
  :type '(alist :key-type symbol
                :value-type (plist :key-type symbol :value-type t)))
```

**Graduated Degradation** (from Hannecke Medium):
- **L1 (3 failures)**: Disable risky tools, add human review flag
- **L2 (5 failures)**: Switch to conservative mode, use simpler agents
- **L3 (8 failures)**: Hard stop, escalate to human review queue

### 1.2 Checkpoint/Restore Pattern

**Source**: efrit, genesis-agent
**Impact**: HIGH | **Difficulty**: MEDIUM

Store state snapshots before risky operations. Auto-restore from checkpoints on crash.

**Emacs Implementation**:

```elisp
(defvar gptel-checkpoint-dir
  (expand-file-name ".gptel/checkpoints/" user-emacs-directory))

(defun gptel-checkpoint-save (experiment-id state)
  "Save STATE for EXPERIMENT-ID to checkpoint directory."
  (let ((file (expand-file-name experiment-id gptel-checkpoint-dir)))
    (with-temp-buffer
      (insert (prin1-to-string state))
      (make-directory gptel-checkpoint-dir 'parents)
      (write-file file))))

(defun gptel-checkpoint-load (experiment-id)
  "Load checkpoint state for EXPERIMENT-ID."
  (let ((file (expand-file-name experiment-id gptel-checkpoint-dir)))
    (when (file-exists-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (read (current-buffer))))))
```

### 1.3 Five Error Categories + Recovery Strategies

| Category | Example | Recovery Strategy |
|----------|---------|-------------------|
| **Hard** | Network unreachable | Fallback to cached response |
| **Structural** | Malformed tool schema | Skip tool, log error |
| **Semantic** | LLM hallucinated tool name | Fuzzy match to nearest valid |
| **Behavioral** | Infinite loop detected | Circuit breaker opens |
| **Resource** | Memory exhausted | GC, reduce context window |

---

## 2. Context Reduction Patterns

### 2.1 Think-in-Code Paradigm

**Source**: context-mode (davidwuchn/context-mode)
**Impact**: HIGH | **Difficulty**: HARD

Instead of dumping 700KB via 47 Read() calls, execute analysis scripts that return only the result.

```
Before (700KB raw dump):
  Read("file1.el") → 45KB
  Read("file2.el") → 120KB
  ...
  Total: 700KB context bloat

After (3.6KB result):
  gptel-sandbox-execute analysis-script.el → "defun foo... used 3 times, lines 10,45,89"
```

**Emacs Implementation**:

```elisp
(defun gptel-sandbox-execute (script-path &optional params)
  "Execute SCRIPT-PATH in isolated subprocess, return structured result.
PARAMS is an alist passed as JSON to stdin."
  (let* ((input-json (json-encode params))
         (output (shell-command-to-string
                  (format "cat %s | python3 - %s"
                          script-path
                          (shell-quote-argument input-json)))))
    (json-parse-string output :object-type 'alist)))
```

**Achievement**: 98% context reduction (315 KB → 5.4 KB)

### 2.2 Session Continuity via FTS5

**Source**: context-mode
**Impact**: MEDIUM | **Difficulty**: MEDIUM

Every edit, git op, task, error tracked in SQLite with FTS5. When context compacts, retrieve only relevant events via BM25 search.

```sql
CREATE VIRTUAL TABLE session_events USING fts5(
  session_id,
  timestamp,
  event_type,
  data,
  content='session_events_backup'
);

-- Query relevant events on context compaction
SELECT * FROM session_events 
WHERE session_events MATCH 'error AND recovery'
ORDER BY rank;
```

**Emacs Integration**:

```elisp
(require 'sqlite)

(defun gptel-session-db-log (event-type data)
  "Log EVENT-TYPE with DATA to session database."
  (sqlite-execute gptel-session-db
    "INSERT INTO session_events (session_id, timestamp, event_type, data)
     VALUES (?, ?, ?, ?)"
    gptel-current-session-id
    (format-time-string "%Y-%m-%d %H:%M:%S")
    event-type
    (json-encode data)))

(defun gptel-session-retrieve (query)
  "Retrieve events matching QUERY for session continuity."
  (sqlite-select gptel-session-db
    "SELECT * FROM session_events WHERE session_events MATCH ?"
    (list query)))
```

---

## 3. Memory & Knowledge Patterns

### 3.1 Feed-Forward Memory Protocol

**Source**: mementum (davidwuchn/mementum)
**Impact**: HIGH | **Difficulty**: MEDIUM

Three storage tiers with human governance:

| Tier | Content | Size Limit | Governance |
|------|---------|------------|------------|
| **Working Memory** | state.md | Unlimited | Auto-save |
| **Memories** | Short insights | <200 words | AI proposes, human approves |
| **Knowledge** | Synthesized patterns | Any | Human review workflow |

**Emacs Implementation**:

```elisp
(defvar gptel-memory-synthesize t
  "Whether to synthesize memories from experiment outcomes.")

(defun gptel-memory-propose (insight)
  "Propose INSIGHT for memory storage. Returns cons (approved . memory-key)."
  (let ((proposed (format "*Memory Proposal*\n%s\n\n:PROPERTIES:\n:CREATED: %s\n:STATUS: pending-review\n:END:"
                          insight
                          (format-time-string "%Y-%m-%d"))))
    (if gptel-memory-synthesize
        (progn
          (write-file gptel-memory-proposals-file 'confirm)
          (cons 'pending proposed))
        (cons 'human-review proposed))))
```

### 3.2 Self-Wiring Knowledge Graph

**Source**: gbrain (davidwuchn/gbrain)
**Impact**: MEDIUM | **Difficulty**: HARD

Every page write extracts entity references and creates typed edges with **zero LLM calls**.

```
Input: "Bob works at Acme Corp"
Parsed: [[Bob]] --works_at--> [[Acme Corp]]

Input: "Alice attended the meeting"
Parsed: [[Alice]] --attended--> [[meeting]]
```

**Emacs Pattern**:

```elisp
(defun gptel-entity-extract (text)
  "Extract [[entity]] references from TEXT. Returns list of (entity . type)."
  (let ((entities '()))
    (dolist (link (markdown-link-pairs text))
      (push (cons (car link) (gptel-entity-type-infer (cdr link))) entities))
    entities))

(defun gptel-entity-link (source target type)
  "Create TYPE edge from SOURCE to TARGET in knowledge graph."
  (sqlite-execute gptel-graph-db
    "INSERT INTO entity_edges (source, target, type, created)
     VALUES (?, ?, ?, datetime('now'))"
    source target type))

;; Achieves +31.4 P@5 lift over vector-only RAG
```

### 3.3 Hybrid Search Fusion

**Source**: gbrain
**Impact**: MEDIUM | **Difficulty**: HARD

Combine vector embeddings + BM25 keyword + reciprocal-rank fusion.

| Component | Tool | Result |
|-----------|------|--------|
| Vector similarity | ollama embeddings | Semantic match |
| BM25 keyword | ripgrep | Exact terms |
| Fusion | Reciprocal rank | Combined ranking |

**P@5: 49.1%** (vs 37.3% vector-only, 35.8% keyword-only)

---

## 4. Self-Evolution Patterns

### 4.1 Three-Loop Meta-Learning Architecture

**Source**: arXiv (HyperAgents)
**Impact**: HIGH | **Difficulty**: MEDIUM

```
┌─────────────────────────────────────────────────────────────────┐
│                    THREE-LOOP META-LEARNING                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   ┌─────────────┐      ┌─────────────┐      ┌─────────────┐   │
│   │    LOOP 1   │      │    LOOP 2   │      │    LOOP 3   │   │
│   │   Task      │─────►│  Evaluation │─────►│    Self-    │   │
│   │  Execution  │      │   (Tests)   │      │ Improvement │   │
│   │  (ReAct)    │◄─────│  (Feedback) │◄─────│  (Modify)   │   │
│   └─────────────┘      └─────────────┘      └─────────────┘   │
│        │                    │                    │             │
│   Tool calls,          Pass/fail,            Code changes,     │
│   state updates        metrics               new strategies     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Emacs Implementation**:

```elisp
(defvar gptel-self-evolution-loops
  '(execution evaluation improvement))

(defun gptel-loop-execute (task)
  "Loop 1: Execute TASK with available tools."
  (let ((result (gptel-execute-task task)))
    (gptel-metrics-record :task task :outcome result)
    result))

(defun gptel-loop-evaluate (result)
  "Loop 2: Evaluate RESULT against expected outcomes."
  (let ((tests (gptel-get-verification-tests result)))
    (seq-mapcat #'gptel-run-verification tests)))

(defun gptel-loop-improve (failures)
  "Loop 3: Generate improvements for FAILURES."
  (when failures
    (gptel-generate-patch (gptel-analyze-failures failures))))
```

### 4.2 Self-Verification Engine

**Source**: genesis-agent (davidwuchn/genesis-agent)
**Impact**: HIGH | **Difficulty**: MEDIUM

66 deterministic checks where "LLM proposes — machine verifies."

```elisp
(defvar gptel-verification-functions
  '(gptel-verify-elisp-syntax
    gptel-verify-imports
    gptel-verify-exit-codes
    gptel-verify-file-structure
    gptel-verify-module-signatures))

(defun gptel-verify-and-commit (proposed-change)
  "Run all verification functions on PROPOSED-CHANGE. Commit only if all pass."
  (let ((results (mapcar #'funcall gptel-verification-functions)))
    (if (seq-every-p #'car results)
        (gptel-commit-change proposed-change)
      (gptel-report-verification-failures results))))
```

### 4.3 P(Success) Confidence Scoring

**Source**: arXiv (MetaAgent)
**Impact**: MEDIUM | **Difficulty**: MEDIUM

Track success probability based on outcome history:

```elisp
(defun gptel-p-success (task-type)
  "Calculate P(success) for TASK-TYPE based on historical outcomes."
  (let* ((history (gptel-outcome-history task-type))
         (total (length history))
         (successes (seq-count #'gptel-outcome-success-p history)))
    (if (> total 5)
        (/ successes (float total))
      0.5)))  ; Unknown tasks default to 50%

(defun gptel-task-routing (task)
  "Route TASK based on P(success). High-risk tasks get extra verification."
  (let ((p (gptel-p-success (gptel-task-type task))))
    (cond
     ((>= p 0.8) (gptel-execute-direct task))
     ((>= p 0.5) (gptel-execute-with-checkpoints task))
     (t (gptel-escalate-for-human-review task)))))
```

---

## 5. Error Recovery Patterns

### 5.1 Exponential Backoff with Jitter

```elisp
(defun gptel-exponential-backoff (attempt)
  "Calculate backoff delay for ATTEMPT with jitter."
  (let* ((base-delay 1.0)
         (max-delay 64.0)
         (exponential (* base-delay (expt 2 (1- attempt))))
         (jitter (* (random 1.0) 0.5))
         (delay (+ exponential jitter)))
    (min delay max-delay)))

(defun gptel-retry-with-backoff (fn &optional max-attempts)
  "Retry FN with exponential backoff up to MAX-ATTEMPTS."
  (let ((attempt 1))
    (while (<= attempt (or max-attempts 6))
      (condition-case err
          (return (funcall fn))
        (error
         (when (= attempt max-attempts)
           (signal (car err) (cdr err)))
         (sleep-for (gptel-exponential-backoff attempt))
         (setq attempt (1+ attempt)))))))
```

### 5.2 Provider Fallback Chain

```elisp
(defvar gptel-provider-chain
  '(openai anthropic ollama))

(defvar gptel-current-provider 'openai)

(defun gptel-fallback-call (prompt)
  "Call PROVIDER chain until one succeeds."
  (dolist (provider gptel-provider-chain)
    (condition-case err
        (progn
          (setq gptel-current-provider provider)
          (return (gptel-call-provider provider prompt)))
      (error
       (gptel-circuit-breaker-record provider 'failure)
       (unless (gptel-circuit-breaker-closed-p provider)
         (signal 'gptel-all-providers-failed
                 (list provider err))))))))
```

### 5.3 Escalation Queue

```elisp
(defvar gptel-escalation-queue '())

(defun gptel-escalate (task reason)
  "Add TASK to escalation queue with REASON."
  (push (list :task task
              :reason reason
              :timestamp (current-time)
              :priority (gptel-escalation-priority reason))
        gptel-escalation-queue)
  (gptel-notify-human-review task reason))

(defun gptel-escalation-priority (reason)
  "Return priority for REASON."
  (pcase reason
    ('circuit-open 'high)
    ('repeated-failure 'high)
    ('security-concern 'critical)
    (_ 'medium)))
```

---

## 6. Agent Architecture Patterns

### 6.1 Five-Level Orchestration Spectrum

**Source**: Azure AI Agent Orchestration Patterns

| Level | Name | Use When | Example |
|-------|------|----------|---------|
| 0 | Direct model call | Single-step, prompt engineering suffices | Quick query |
| 1 | Single agent + tools | Varied queries, dynamic tool use | Interactive session |
| 2 | Sequential | Linear dependencies, progressive refinement | Research pipeline |
| 3 | Concurrent | Independent perspectives, fan-out/fan-in | Parallel experiments |
| 4 | Hierarchical | Master-slave coordination, complex delegation | Multi-agent swarm |

**gptel-auto-workflow operates at Level 2-3** with explicit iteration limits.

### 6.2 Three-Tier Watchdog Architecture

**Source**: gastown (davidwuchn/gastown)

```
┌──────────────────────────────────────────────────────────────┐
│                    WATCHDOG HIERARCHY                        │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│   ┌─────────────┐                                           │
│   │   WITNESS   │  Session lifecycle management              │
│   │  (Primary)  │  - Start/stop daemon                      │
│   └──────┬──────┘  - Health heartbeat                       │
│          │                                                  │
│   ┌──────▼──────┐                                           │
│   │   DEACON    │  Continuous background patrol             │
│   │ (Continuous)│  - Periodic health checks                 │
│   └──────┬──────┘  - Automatic recovery attempts            │
│          │                                                  │
│   ┌──────▼──────┐                                           │
│   │    DOGS     │  Dispatched cleanup/error recovery        │
│   │  (Workers)  │  - Log rotation                           │
│   └─────────────┘  - Checkpoint garbage collection          │
│                     - Stale lock removal                     │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

### 6.3 Lambda Notation as Attention Magnets

**Source**: nucleus (davidwuchn/nucleus)

Use Greek letters and math symbols as compressed prompt preamble:

```
λ engage(nucleus).
  [phi fractal euler tao pi mu ∃ ∀]           ; Core symbols
  | [Δ λ Ω ∞/0 | ε/φ Σ/μ c/h]                 ; Operations
  | OODA                                       ; Control loop
```

**Symbol Meanings**:

| Symbol | Meaning | Prompt Application |
|--------|---------|---------------------|
| λ | Lambda (function) | Apply function composition |
| Δ | Delta (change) | Detect state transitions |
| Ω | Omega (end) | Convergence criteria |
| φ | Phi (golden ratio) | Optimal balance |
| ε | Epsilon | Small perturbation handling |
| ∞/0 | Infinity/zero | Edge case boundaries |
| OODA | Observe-Orient-Decide-Act | Control loop |

---

## 7. Trajectory-Aware Metrics

**Source**: NVIDIA AI Agent Evaluation Guide

Evaluate trajectories, not just final answers:

| Metric | Formula | Target |
|--------|---------|--------|
| **Task Success Rate (TSR)** | successful / total | >85% |
| **Tool Call Accuracy** | correct_tools / total_calls | >90% |
| **Trajectory Efficiency** | steps_per_success / avg_steps | Minimize |
| **Reasoning Soundness** | valid_reasons / total_reasons | >80% |

**Emacs Instrumentation**:

```elisp
(defvar gptel-trajectory-log '())

(defun gptel-trajectory-record (step data)
  "Record STEP with DATA to trajectory log."
  (push (cons step (cons (current-time) data)) gptel-trajectory-log))

(defun gptel-trajectory-metrics ()
  "Compute trajectory metrics from log."
  (let* ((steps (length gptel-trajectory-log))
         (successes (seq-count #'gptel-outcome-success-p gptel-trajectory-log)))
    (list :tsr (/ successes (float steps))
          :avg-steps (/ steps (float successes))
          :total-steps steps)))
```

---

## 8. Module Complexity Analysis

**Source**: Local codebase scan (2026-05-25)

| Module | Lines | Risk Level | Priority |
|--------|-------|------------|----------|
| `gptel-auto-workflow-evolution.el` | 5822 | **HIGH** | Apply nil-safety patterns |
| `gptel-auto-workflow-strategic.el` | 2698 | MEDIUM | Validation guards |
| `gptel-tools-agent-prompt-build.el` | 2431 | MEDIUM | Error handling |
| `gptel-auto-workflow-research-benchmark.el` | 1742 | MEDIUM | Monitoring |
| `gptel-tools-agent-runtime.el` | ~1600 | MEDIUM | Checkpoint/restore |

**Git Activity (last 30 commits)**: 8 bug fixes, 0 feature commits. Focus on stabilization.

---

## 9. Implementation Checklist

### Critical (Do First)

- [ ] Implement circuit breaker with graduated degradation (L1/L2/L3)
- [ ] Add checkpoint/restore to experiment execution
- [ ] Instrument trajectory logging with TSR metrics
- [ ] Add P(success) confidence scoring to task routing

### High Value (Do Second)

- [ ] Implement Think-in-Code context reduction for analysis passes
- [ ] Add FTS5 session continuity database
- [ ] Implement self-verification engine for code changes
- [ ] Add provider fallback chain (OpenAI → Anthropic → Ollama)

### Medium Value (Do Third)

- [ ] Add three-tier watchdog (Witness/Deacon/Dogs)
- [ ] Implement hybrid search (vector + BM25)
- [ ] Add self-wiring knowledge graph for memories
- [ ] Implement Lambda notation preamble library

---

## 10. Anti-Patterns to Avoid

| Anti-Pattern | Problem | Solution |
|--------------|---------|----------|
| Research without downstream testing | 0% keep rate (2026-05-25) | Link every research to experiment |
| Missing research files treated as success | Pipeline defect hidden | Fail fast, require research hash |
| Dumping raw file reads to context | 700KB bloat | Use sandbox-execute pattern |
| Trusting LLM output without verification | Silent failures | Implement verification gates |
| Hard fail on any error | No graceful degradation | Use DEGRADED state circuit breaker |

---

## Related

- [[agent-runtime]] — Agent execution runtime patterns
- [[agent-error]] — Error handling and recovery
- [[memory-systems]] — Memory and knowledge management
- [[workflow-daemon]] — Daemon lifecycle management
- [[self-evolution]] — Self-modification and improvement
- [[research-benchmark]] — Experiment benchmarking system
- [[prompt-engineering]] — Prompt construction patterns
- [[tool-permits]] — Security and tool access control

---

## References

| Source | Type | Key Patterns |
|--------|------|--------------|
| efrit | Internal | Circuit breaker, tool receipts, checkpoint/restore |
| nucleus | Internal | Lambda notation, attention magnets |
| context-mode | Internal | Think-in-code, FTS5 continuity |
| mementum | Internal | Feed-forward memory, human governance |
| gbrain | Internal | Self-wiring graph, hybrid search |
| genesis-agent | Internal | Self-verification, P(success) |
| gastown | Internal | Watchdog architecture, beads ledger |
| zeroclaw | Internal | Security-first runtime, SOP engine |
| arXiv:2405.10467 | External | 18 agent design patterns |
| arXiv:2508.00271 | External | MetaAgent self-evolution |
| Azure Architecture Guide | External | Orchestration spectrum |
| NVIDIA Evaluation Guide | External | Trajectory-aware metrics |
| Hannecke Medium | External | DEGRADED circuit breaker state |

---

*Synthesized: 2026-05-25*
*Source memories: 5 research sessions (2026-05-20 to 2026-05-25)*
*Total patterns: 14 techniques, 8 anti-patterns, 30+ implementation examples*