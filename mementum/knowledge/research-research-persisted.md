<!--
Synthesis verification:
- Confidence: 24%
- Sources: 8 memories
- Warnings: No code examples or concrete references, Content does not mention topic 'research-research-persisted'
- Auto-approved: yes (flagged)
--->

---
title: Research Persistence & Pattern Synthesis
status: active
category: knowledge
tags: [research, self-evolution, patterns, daemon, workflow]
---

# Research Persistence & Pattern Synthesis

## Overview

This knowledge page synthesizes research findings from multiple research sessions using the `persisted-findings` strategy. The research targets Emacs AI agent system development, focusing on self-evolution, resilience patterns, and agent architecture.

**Key Metrics from Research Sessions:**

| Date | Targets | Outcome | Quality |
|------|---------|---------|---------|
| 2026-05-22 10:29 | 6 modules | 9/39 (23%) | Best |
| 2026-05-20 23:27 | 5 modules | 4/24 (17%) | High |
| 2026-05-22 04:11 | 7 modules | 2/56 (4%) | Medium |
| 2026-05-22 12:10 | 2 modules | 3/9 (33%) | Best ratio |
| 2026-05-25 09:26 | 4 targets | 1/24 (4%) | Low |
| 2026-05-25 08:55 | 5 modules | 0/15 (0%) | Fallback |
| 2026-05-27 06:17 | 3 targets | 0/7 (0%) | Fallback |

**Meta-learning:** Research quality is measured by downstream experiment success, not raw findings count.

---

## Module Complexity Analysis

Understanding which modules drive the most complexity helps prioritize research targets:

```
58031 total lines in lisp/modules/
├── 5822 gptel-auto-workflow-evolution.el     (largest - self-evolution core)
├── 2698 gptel-auto-workflow-strategic.el      (orchestration logic)
├── 2431 gptel-tools-agent-prompt-build.el     (prompt engineering)
├── 1742 gptel-auto-workflow-research-benchmark.el
└── [other modules...]
```

**Self-Evolution Directive:** Focus on the highest-failure modules above. Apply nil-safety patterns and validation guards to reduce failure rates.

---

## Tier 1: Directly Applicable Patterns (Emacs Lisp + AI Agents)

### 1. Circuit Breaker + Checkpoint/Restore Pattern

**Source:** [efrit](https://github.com/davidwuchn/efrit)

**Technique:** Circuit breaker monitors failure rates per provider, transitions through CLOSED→OPEN→HALF-OPEN states to prevent cascading failures. Checkpoint/restore stores state snapshots before risky operations.

**Implementation:**

```elisp
(defcustom gptel-circuit-breaker-config
  '(("openai" 5 3 300)
    ("anthropic" 5 3 300)
    ("ollama" 3 2 60))
  "Alist of (provider failure-threshold success-threshold reset-seconds)."
  :type '(alist :key-type string :value-type (list integer integer integer)))

(defvar gptel-circuit-breaker-state (make-hash-table :test 'equal))

(defun gptel-circuit-breaker--get-state (provider)
  "Get or initialize circuit breaker state for PROVIDER."
  (or (gethash provider gptel-circuit-breaker-state)
      (puthash provider
               (list 0 0 nil)  ; (failure-count success-count last-failure)
               gptel-circuit-breaker-state)))

(defun gptel-circuit-breaker--record (provider success)
  "Record SUCCESS for PROVIDER in circuit breaker state."
  (pcase-let ((`(,failures ,successes ,last-fail)
               (gptel-circuit-breaker--get-state provider)))
    (puthash provider
             (if success
                 (list 0 (1+ successes) last-fail)
               (list (1+ failures) 0 (current-time)))
             gptel-circuit-breaker-state)))

(defun gptel-circuit-breaker--open-p (provider)
  "Check if circuit is open for PROVIDER."
  (pcase-let ((`(,failures ,successes ,last-fail)
               (gptel-circuit-breaker--get-state provider))
              (`(,_threshold ,success-threshold ,reset-secs)
               (alist-get provider gptel-circuit-breaker-config)))
    (cond
     ((>= failures 5) t)  ; Hard open after 5 consecutive failures
     ((and last-fail
           (> (float-time (time-since last-fail)) reset-secs)
           (>= successes success-threshold))
      (setq gptel-circuit-breaker-state
            (puthash provider '(0 0 nil) gptel-circuit-breaker-state))
      nil)  ; Reset after cooldown
     (t nil))))
```

**Checkpoint/Restore Pattern:**

```elisp
(defvar gptel-checkpoint-dir
  (expand-file-name ".gptel/checkpoints/" user-emacs-directory))

(defun gptel-checkpoint-save (name data)
  "Save DATA to checkpoint NAME for crash recovery."
  (let ((file (expand-file-name name gptel-checkpoint-dir)))
    (make-directory gptel-checkpoint-dir t)
    (with-temp-file file
      (let ((print-length nil) (print-level nil))
        (prin1 data (current-buffer)))))
  name)

(defun gptel-checkpoint-restore (name &optional default)
  "Restore checkpoint NAME or return DEFAULT if missing."
  (let ((file (expand-file-name name gptel-checkpoint-dir)))
    (if (file-exists-p file)
        (with-temp-buffer
          (insert-file-contents file)
          (goto-char (point-min))
          (read (current-buffer)))
      default)))
```

---

### 2. Tool Receipts for Audit Trail

**Source:** [efrit](https://github.com/davidwuchn/efrit) (35+ tools with security controls)

**Technique:** Every tool execution generates structured metadata: `(input-hash output-hash timestamp duration tool-name)`. Shell commands have allowed/forbidden pattern matching.

**Implementation:**

```elisp
(defcustom gptel-tool-log-db
  (expand-file-name ".gptel/tool-log.db" user-emacs-directory)
  "SQLite database for tool execution audit trail.")

(defun gptel-tool-log--init ()
  "Initialize tool log SQLite database."
  (require 'sqlite)
  (sqlite-execute gptel-tool-log-db
    "CREATE TABLE IF NOT EXISTS tool_executions (
       id INTEGER PRIMARY KEY AUTOINCREMENT,
       tool_name TEXT NOT NULL,
       input_hash TEXT,
       output_hash TEXT,
       timestamp REAL NOT NULL,
       duration_ms INTEGER,
       success INTEGER,
       error TEXT
     )")
  (sqlite-execute gptel-tool-log-db
    "CREATE INDEX IF NOT EXISTS idx_tool_name ON tool_executions(tool_name)")
  (sqlite-execute gptel-tool-log-db
    "CREATE INDEX IF NOT EXISTS idx_timestamp ON tool_executions(timestamp)"))

(defun gptel-tool-log-record (tool-name input output duration-ms success &optional error)
  "Record tool execution with structured metadata."
  (let ((input-hash (secure-hash 'sha256 (prin1-to-string input)))
        (output-hash (and output (secure-hash 'sha256 (prin1-to-string output))))
        (timestamp (float-time)))
    (sqlite-execute gptel-tool-log-db
      (format "INSERT INTO tool_executions 
               (tool_name, input_hash, output_hash, timestamp, duration_ms, success, error)
               VALUES ('%s', '%s', '%s', %f, %d, %d, %s)"
        tool-name input-hash (or output-hash "NULL") timestamp duration-ms
        (if success 1 0) (or (and error (format "'%s'" error)) "NULL")))))

(defun gptel-tool-log-query (tool-name &optional limit)
  "Query recent executions for TOOL-NAME."
  (sqlite-select gptel-tool-log-db
    (format "SELECT * FROM tool_executions 
             WHERE tool_name = '%s' ORDER BY timestamp DESC LIMIT %d"
      tool-name (or limit 10))))
```

---

### 3. Think-in-Code Context Reduction

**Source:** [context-mode](https://github.com/davidwuchn/context-mode)

**Technique:** Instead of dumping raw file reads (700KB), execute analysis script that returns only result (3.6KB). Achieves 98% context reduction via sandbox tools. Session continuity via SQLite/FTS5 indexed events.

**Implementation:**

```elisp
(defcustom gptel-sandbox-max-size 4096
  "Maximum bytes to include from tool output in context."
  :type 'integer)

(defvar gptel-sandbox-cache (make-hash-table :test 'equal))

(defun gptel-sandbox-execute (analysis-script)
  "Execute ANALYSIS-SCRIPT in isolated subprocess, return structured result.
This prevents the LLM from becoming a data processor by executing
analysis code instead of dumping raw data."
  (let* ((script-hash (secure-hash 'sha256 analysis-script))
         (cached (gethash script-hash gptel-sandbox-cache)))
    (if (and cached
             (< (- (float-time) (cdr cached)) 300))
        (car cached)  ; Return cached result within 5 minutes
      (let ((result (condition-case err
                        (eval (read analysis-script))
                      (error (list 'error (error-message-string err))))))
        (puthash script-hash (cons result (float-time)) gptel-sandbox-cache)
        result))))

(defun gptel-context-summarize (raw-output)
  "Summarize RAW-OUTPUT to fit within context limit."
  (if (< (string-bytes raw-output) gptel-sandbox-max-size)
      raw-output
    (format "[Output truncated: %d bytes → summary needed]
First 1000 chars: %s
...
Total lines: %d
(Tool output stored in SQLite, retrieve via gptel-tool-log-query)"
      (string-bytes raw-output)
      (substring raw-output 0 (min 1000 (length raw-output)))
      (string-count ?\n raw-output))))
```

---

### 4. Session Continuity via FTS5

**Source:** [context-mode](https://github.com/davidwuchn/context-mode)

**Technique:** Every edit, git op, task, error tracked in SQLite with FTS5. When context compacts, retrieves only relevant events via BM25 search—not dumps raw data.

**Implementation:**

```elisp
(defvar gptel-session-db
  (expand-file-name ".gptel/session.db" user-emacs-directory))

(defun gptel-session-db--init ()
  "Initialize session continuity database."
  (sqlite-execute gptel-session-db
    "CREATE TABLE IF NOT EXISTS session_events (
       id INTEGER PRIMARY KEY AUTOINCREMENT,
       session_id TEXT NOT NULL,
       timestamp REAL NOT NULL,
       event_type TEXT NOT NULL,
       data TEXT
     )")
  (sqlite-execute gptel-session-db
    "CREATE VIRTUAL TABLE IF NOT EXISTS session_fts 
     USING fts5(event_type, data, content='session_events', content_rowid='id')")
  (sqlite-execute gptel-session-db
    "CREATE TRIGGER IF NOT EXISTS session_ai AFTER INSERT ON session_events BEGIN
       INSERT INTO session_fts(rowid, event_type, data) VALUES (new.id, new.event_type, new.data);
     END"))

(defun gptel-session-track (session-id event-type data)
  "Track SESSION-ID EVENT-TYPE with DATA for continuity."
  (sqlite-execute gptel-session-db
    (format "INSERT INTO session_events (session_id, timestamp, event_type, data)
             VALUES ('%s', %f, '%s', '%s')"
      session-id (float-time) event-type data)))

(defun gptel-session-retrieve (session-id query &optional limit)
  "Retrieve relevant events from SESSION-ID matching QUERY via BM25."
  (sqlite-select gptel-session-db
    (format "SELECT session_events.*, bm25(session_fts) as rank
             FROM session_events
             JOIN session_fts ON session_events.id = session_fts.rowid
             WHERE session_events.session_id = '%s'
               AND session_fts MATCH '%s'
             ORDER BY rank
             LIMIT %d"
      session-id query (or limit 20))))
```

---

### 5. Feed-Forward Memory Protocol

**Source:** [mementum](https://github.com/davidwuchn/mementum)

**Technique:** Three storage types (working memory/state.md, memories <200 words, synthesized knowledge). Human governance: AI proposes, human approves, AI commits.

**Implementation:**

```elisp
(defcustom gptel-memory-synthesize-file
  (expand-file-name "mementum/state.md" user-emacs-directory)
  "Path to mementum state file for session start.")

(defun gptel-memory-synthesize ()
  "Read mementum state.md on session start for feed-forward."
  (when (file-exists-p gptel-memory-synthesize-file)
    (with-temp-buffer
      (insert-file-contents gptel-memory-synthesize-file)
      (buffer-string))))

(defcustom gptel-knowledge-approval-required t
  "If non-nil, require human approval before committing to knowledge.")

(defun gptel-knowledge-propose (page-title content)
  "Propose PAGE-TITLE with CONTENT for knowledge synthesis.
Returns pending proposal ID for human review."
  (let ((proposal-id (format "proposal-%d" (float-time))))
    (puthash proposal-id
             (list :title page-title :content content :status 'pending)
             gptel-knowledge-pending)
    proposal-id))

(defun gptel-knowledge-approve (proposal-id)
  "Approve and commit PROPOSAL-ID to knowledge base."
  (pcase-let ((`(,_id ,proposal) (gethash proposal-id gptel-knowledge-pending)))
    (setf (nth 2 proposal) 'approved)
    (remhash proposal-id gptel-knowledge-pending)
    proposal))  ; Caller should write to knowledge file
```

---

## Tier 2: Agent Architecture Patterns

### 6. Three-Tier Watchdog Architecture

**Source:** [gastown](https://github.com/davidwuchn/gastown)

**Technique:** Systematized lifecycle management via three tiers: Witness (session lifecycle), Deacon (continuous background patrol), Dogs (dispatched workers). Convoy system bundles work items with autonomous stall detection.

**Implementation:**

```elisp
(defvar gptel-workflow--witness nil "Session lifecycle watchdog.")
(defvar gptel-workflow--deacon nil "Background patrol timer.")
(defvar gptel-workflow--dogs (make-hash-table) "Dispatched cleanup/error recovery tasks.")

(defun gptel-workflow-witness-start ()
  "Start session lifecycle watchdog."
  (setq gptel-workflow--witness
        (run-with-timer 0 60  ; Check every 60 seconds
          (lambda ()
            (when (and gptel-workflow--session-active
                       (time-less-p (seconds-to-time 300)
                                    (time-since gptel-workflow--last-activity)))
              (gptel-workflow--stall-warning))))))

(defun gptel-workflow-deacon-start ()
  "Start continuous background patrol."
  (setq gptel-workflow--deacon
        (run-with-idle-timer 30 t
          (lambda ()
            (dolist (task (hash-table-values gptel-workflow--dogs))
              (when (gptel-workflow--dog-stale-p task)
                (gptel-workflow--dog-recover task)))))))

(defun gptel-workflow-dog-dispatch (task-id cleanup-fn)
  "Dispatch CLEANUP-FN as a 'dog' for TASK-ID with stall detection."
  (puthash task-id
           (list :cleanup-fn cleanup-fn
                 :dispatched-at (float-time)
                 :last-check (float-time))
           gptel-workflow--dogs)
  (run-with-timer 60 30
    (lambda ()
      (let ((task (gethash task-id gptel-workflow--dogs)))
        (when task
          (funcall (plist-get task :cleanup-fn))
          (remhash task-id gptel-workflow--dogs))))))
```

---

### 7. Lambda Notation + Mathematical Attention Magnets

**Source:** [nucleus](https://github.com/davidwuchn/nucleus)

**Technique:** Greek letters and math symbols as compressed prompt preamble: `λ engage(nucleus). [phi fractal euler tao pi mu ∃ ∀] | [Δ λ Ω ∞/0 | ε/φ Σ/μ c/h] | OODA`. Primes formal reasoning patterns.

**Implementation:**

```elisp
(defconst gptel-nucleus-preamble-library
  '((reasoning . "λ engage. [φ ψ Δ λ ε] | [∀ ∃ ∈ ⊂] | OODA loop")
    (formal . "ℕ ℤ ℚ ℝ ℂ | ∀x∈S: P(x) | ∴ ∵ ∷ | ≔ ≝")
    (entropy . "ΔS ≥ 0 | H(X) | Σp·log(p) | noise→signal")
    (control . "feedback loop | OODA | thermostat | servo")
    (creative . "∅→∃ | 0→1 | diverge→converge | expand→contract"))
  "Mapping from semantic tags to mathematical preambles.")

(defun gptel-nucleus-build-preamble (&rest tags)
  "Build nucleus-style preamble from TAGS."
  (string-join
   (delq nil (mapcar (lambda (tag)
                       (alist-get tag gptel-nucleus-preamble-library))
                     tags))
   " "))

;; Example usage in system prompt:
;; "λ engage(auto-workflow). [φ systematic] [Δ change ε small] | [∀ experiment ∈ corpus] | OODA"
```

---

### 8. DEGRADED State Circuit Breaker

**Source:** External (Hannecke patterns)

**Technique:** Five failure categories (Hard, Structural, Semantic, Behavioral, Resource) need different handling. DEGRADED state between CLOSED/OPEN allows graceful degradation instead of hard fail. Graduated re-enablement: L1 (5% traffic), L2 (20%), L3 (50%).

**Implementation:**

```elisp
(defvar gptel-degraded-level nil "Current degradation level 0-3.")
(defvar gptel-degraded-capabilities nil "Capabilities disabled in degraded mode.")

(defconst gptel-degraded-levels
  '(("L0" :risky-tools nil :human-review nil :retry-limit 3)
    ("L1" :risky-tools nil :human-review nil :retry-limit 2)
    ("L2" :risky-tools '(edit delete shell) :human-review t :retry-limit 1)
    ("L3" :risky-tools '(edit delete shell compile) :human-review t :retry-limit 0))
  "Degradation levels with graduated capability reduction.")

(defun gptel-degraded-enter (level)
  "Enter degraded mode at LEVEL (0-3)."
  (setq gptel-degraded-level level
        gptel-degraded-capabilities
        (plist-get (alist-get (format "L%d" level) gptel-degraded-levels)
                   :risky-tools))
  (message "Entered DEGRADED mode L%d: %s"
           level gptel-degraded-capabilities))

(defun gptel-degraded-recover (&optional level)
  "Attempt recovery, optionally to specific LEVEL."
  (let ((target (or level (1+ (or gptel-degraded-level 0)))))
    (if (< target 3)
        (progn
          (gptel-degraded-enter target)
          (message "Recovery attempt: L%d (5%% traffic)" target))
      (setq gptel-degraded-level nil
            gptel-degraded-capabilities nil
            gptel-workflow--consecutive-failures 0)
      (message "Full recovery achieved"))))
```

---

### 9. Self-Verification Engine

**Source:** [genesis-agent](https://github.com/davidwuchn/genesis-agent)

**Technique:** 66 deterministic checks where "the LLM proposes — the machine verifies." AST parsing, exit codes, import resolution, file validation, module signatures.

**Implementation:**

```elisp
(defvar gptel-verify-functions (make-hash-table))

(defun gptel-verify-register (check-type fn)
  "Register verification function FN for CHECK-TYPE."
  (puthash check-type fn gptel-verify-functions))

(defun gptel-verify (check-type data)
  "Run CHECK-TYPE verification on DATA."
  (let ((fn (gethash check-type gptel-verify-functions)))
    (if fn
        (condition-case err
            (funcall fn data)
          (error (list 'verification-error check-type (error-message-string err))))
      (list 'unknown-check-type check-type))))

;; Register standard verification checks:
(gptel-verify-register 'elisp-syntax
  (lambda (code)
    (with-temp-buffer
      (insert code)
      (let ((syntax-errors nil))
        (condition-case ()
            (progn
              (goto-char (point-min))
              (while (forward-sexp))
              t)
          (invalid-syntax (setq syntax-errors t)))
        (not syntax-errors)))))

(gptel-verify-register 'file-exists
  (lambda (path)
    (if (listp path)
        (mapcar #'file-exists-p path)
      (file-exists-p path))))

(gptel-verify-register 'shell-exit
  (lambda (exit-code)
    (zerop exit-code)))
```

---

## Tier 3: External Academic Patterns

### 10. Agent Design Pattern Catalogue

**Source:** arXiv:2405.10467

**Technique:** Systematic pattern catalogue for foundation model-based agents addressing goal-seeking and plan generation. Decision model for selecting appropriate orchestration patterns based on task requirements.

**Orchestration Spectrum:**

| Level | Pattern | Use When | Implementation |
|-------|---------|----------|----------------|
| 1 | Direct model call | Single-step tasks, prompt engineering suffices | Simple `gptel-request` |
| 2 | Single agent + tools | Varied queries, dynamic tool use | `gptel-agent` with tool registry |
| 3 | Sequential | Linear dependencies, progressive refinement | Workflow pipeline |
| 4 | Concurrent | Independent perspectives, fan-out/fan-in | `threading--` macros |
| 5 | Hierarchical | Master-slave coordination, complex delegation | Daemon + subagents |

**Implementation:**

```elisp
(defcustom gptel-orchestration-level 2
  "Current orchestration complexity level (1-5)."
  :type '(radio :tag "Orchestration Level"
                (const :doc "Direct model call" 1)
                (const :doc "Single agent + tools" 2)
                (const :doc "Sequential workflow" 3)
                (const :doc "Concurrent fan-out" 4)
                (const :doc "Hierarchical delegation" 5)))

(defun gptel-orchestrate (task &optional context)
  "Orchestrate TASK at current gptel-orchestration-level with CONTEXT."
  (pcase gptel-orchestration-level
    (1 (gptel-request task))
    (2 (gptel-agent task context))
    (3 (gptel-workflow-sequence task))
    (4 (gptel-workflow-concurrent task))
    (5 (gptel-workflow-hierarchical task))))
```

---

### 11. MetaAgent Self-Evolving Paradigm

**Source:** arXiv:2508.00271

**Technique:** Self-improving agent via tool meta-learning without parameter changes. Starts minimal, generates help requests on knowledge gaps, routes to tools via dedicated router.

**Implementation:**

```elisp
(defvar gptel-p-success-history (make-hash-table :test 'equal))

(defun gptel-p-success (task-pattern)
  "Calculate P(success) for TASK-PATTERN based on outcome history."
  (let ((history (gethash task-pattern gptel-p-success-history)))
    (if (< (length history) 3)
        0.5  ; Unknown: default to 50%
      (let ((successes (cl-count-if #'identity history)))
        (/ (float successes) (length history))))))

(defun gptel-p-success-record (task-pattern success)
  "Record SUCCESS for TASK-PATTERN in outcome history."
  (let* ((history (gethash task-pattern gptel-p-success-history '()))
         (new-history (cons success (cl-subseq history 0 19))))  ; Keep last 20
    (puthash task-pattern new-history gptel-p-success-history)))

(defun gptel-help-request-p (task)
  "Generate help request if TASK pattern is unrecognized."
  (when (< (gptel-p-success (gptel-task-pattern task)) 0.3)
    (format "Help needed: task type '%s' has low success history.
Consider additional context or alternative approach."
      (gptel-task-pattern task))))
```

---

### 12. Trajectory-Aware Metrics

**Source:** [NVIDIA AI Agent Evaluation Guide](https://developer.nvidia.com/blog/mastering-agentic-techniques-ai-agent-evaluation/)

**Technique:** Evaluate trajectories, not just final answers. Log complete trajectories (plans, tool calls, outcomes).

**Metrics:**

| Metric | Formula | Target |
|--------|---------|--------|
| Task Success Rate (TSR) | successes / total | >80% |
| Tool Call Accuracy | correct_calls / total_calls | >90% |
| Trajectory Efficiency | steps_per_success (lower=better) | <10 |
| Reasoning Soundness | valid_traces / total_traces | >85% |

**Implementation:**

```elisp
(defvar gptel-trajectory-log (make-hash-table :test 'equal))

(defun gptel-trajectory-log-step (experiment-id step-type data)
  "Log STEP-TYPE with DATA for EXPERIMENT-ID trajectory."
  (let ((log (gethash experiment-id gptel-trajectory-log '())))
    (push (list :step (length log)
                :type step-type
                :timestamp (float-time)
                :data data)
          (puthash experiment-id (puthash experiment-id log gptel-trajectory-log)))))

(defun gptel-metrics-calculate (experiment-id)
  "Calculate trajectory metrics for EXPERIMENT-ID."
  (let ((trajectory (gethash experiment-id gptel-trajectory-log)))
    (list :tsr (gptel-metrics--tsr trajectory)
          :tool-accuracy (gptel-metrics--tool-accuracy trajectory)
          :trajectory-efficiency (gptel-metrics--efficiency trajectory)
          :reasoning-soundness (gptel-metrics--soundness trajectory))))
```

---

### 13. Error Recovery Patterns

**Source:** [AI Agent Error Recovery Patterns](https://aiagentsblog.com/blog/agent-error-recovery-patterns/)

**Key Patterns:**

1. **Exponential Backoff with Jitter** — Retry delays increase exponentially with random jitter
2. **Circuit Breakers** — Open circuit after N failures
3. **Checkpoint-and-Resume** — Save state at each step
4. **Fallback Chains** — Provider A → Provider B → Provider C
5. **Escalation Queues** — Failed tasks to human review

**Implementation:**

```elisp
(defun gptel-exponential-backoff (attempt base max)
  "Calculate exponential backoff with jitter for ATTEMPT.
BASE defaults to 1 second, MAX to 60 seconds."
  (let* ((delay (min (* base (expt 2 attempt)) max))
         (jitter (* delay (random 0.3))))  ; 0-30% jitter
    (+ delay jitter)))

(defun gptel-fallback-chain (&rest providers)
  "Try PROVIDERS in sequence until one succeeds."
  (catch 'success
    (dolist (provider providers)
      (condition-case err
          (if (gptel-provider-available-p provider)
              (let ((result (funcall provider)))
                (throw 'success result))
            (message "Provider %s unavailable, trying next..." provider))
        (error
         (message "Provider %s failed: %s" provider err)
         (gptel-circuit-breaker--record provider nil))))
    (gptel-escalation-queue '("All providers failed"))))

(defvar gptel-escalation-queue '())

(defun gptel-escalation-queue (items)
  "Add ITEMS to human review queue."
  (dolist (item items)
    (push (list :timestamp (float-time) :item item)
          gptel-escalation-queue)))
```

---

## Research Pipeline Guidelines

### Structured Research Output Format

Every research run should produce machine-parseable output:

```yaml
source: github.com/davidwuchn/efrit
technique: circuit-breaker
apply-to-us: |
  Implement in gptel-auto-workflow-daemon.el
  - Track failure/success counts per provider
  - Auto-open circuit after 5 consecutive failures
verification: |
  Test by triggering 5 consecutive failures,
  verify circuit opens and requests fail fast
```

### Preserving Feedback Loop

```elisp
(defcustom gptel-research-hash-required t
  "If non-nil, every experiment row must include a non-none research hash.")

(defun gptel-research-validate (experiment-row)
  "Validate EXPERIMENT-ROW includes research hash."
  (when (and gptel-research-hash-required
             (null (alist-get 'research-hash experiment-row)))
    (error "Experiment row missing research hash: %s" experiment-row)))
```

### Research Quality Metrics

| Metric | Formula | Minimum |
|--------|---------|---------|
| Retention Rate | kept / total findings | >15% |
| Downstream Impact | experiments using findings / total | >10% |
| Pattern Novelty | new patterns / total patterns | >20% |

---

## Common Patterns Summary

| Pattern | Source | Difficulty | Impact | Action |
|---------|--------|------------|--------|--------|
| Circuit Breaker | efrit | MEDIUM | HIGH | Implement per-provider failure tracking |
| Tool Audit Trail | efrit | MEDIUM | MEDIUM | SQLite logging with hash verification |
| Think-in-Code | context-mode | HARD | HIGH | Sandboxed analysis scripts |
| FTS5 Session DB | context-mode | HARD | MEDIUM | SQLite with full-text search |
| Feed-Forward Memory | mementum | MEDIUM | HIGH | Read state.md on session start |
| Three-Tier Watchdog | gastown | MEDIUM | HIGH | Witness/Deacon/Dogs separation |
| Mathematical Preamble | nucleus | MEDIUM | MEDIUM | Lambda notation attention anchors |
| Degraded Mode | External | MEDIUM | MEDIUM | Graduated capability reduction |
| Self-Verification | genesis | MEDIUM | HIGH | Deterministic AST/exit code checks |
| Trajectory Metrics | NVIDIA | MEDIUM | HIGH | Log plans, calls, outcomes |
| Exponential Backoff | External | LOW | MEDIUM | Retry with jitter |
| Fallback Chains | External | LOW | HIGH | Multi-provider resilience |

---

## Implementation Priority

1. **Circuit Breaker + Checkpoint** — Prevents cascade failures
2. **Self-Verification** — Reduces bad code commits
3. **Exponential Backoff** — Handles transient failures
4. **Trajectory Logging** — Enables metrics and debugging
5. **Tool Audit Trail** — Compliance and replay
6. **Fallback Chains** — Multi-provider resilience
7. **Three-Tier Watchdog** — Separates lifecycle concerns
8. **Think-in-Code** — Context efficiency at scale
9. **FTS5 Session Continuity** — Memory persistence
10. **Degraded Mode** — Graceful failure handling

---

## Related

- [[research-pipeline]] — Research workflow orchestration
- [[self-evolution]] — Self-modifying agent patterns
- [[daemon-resilience]] — Daemon watchdog and recovery
- [[tool-audit]] — Tool execution logging
- [[context-efficiency]] — Context window management
- [[mementum-protocol]] — Feed-forward memory system

---

*Synthesized from research sessions 2026-05-20 through 2026-05-27*
*Generated by auto-workflow research synthesis*
```