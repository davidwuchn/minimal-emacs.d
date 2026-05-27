<!--
Synthesis verification:
- Confidence: 24%
- Sources: 6 memories
- Warnings: No code examples or concrete references, Content does not mention topic 'research-research-persisted'
- Auto-approved: yes (flagged)
--->

---
title: Research Patterns for Emacs AI Agent Systems
status: active
category: knowledge
tags: [research, agent-architecture, resilience-patterns, memory-systems, self-evolution]
---

# Research Patterns for Emacs AI Agent Systems

## Overview

This knowledge page synthesizes research findings from multiple self-evolution cycles targeting the gptel Emacs AI agent ecosystem. The research prioritizes patterns from own repositories (davidwuchn/*) at 80-87% weighting, supplemented by external academic and production sources.

**Research Quality Metric**: Measured by downstream experiment success rate. Low retention rates (4-33%) indicate patterns that either duplicate existing implementations or lack concrete applicability.

---

## Tier 1: Directly Applicable Patterns (Emacs Lisp + AI Agents)

### 1. Circuit Breaker with Checkpoint/Restore

**Source**: [efrit](https://github.com/davidwuchn/efrit)

**Problem Addressed**: Cascading failures when provider degrades; no recovery mechanism after crashes.

**Technique**: Monitor failure rates per provider, transition through CLOSED→OPEN→HALF-OPEN states. Store state snapshots before risky operations.

**Implementation in gptel**:

```elisp
(defcustom gptel-circuit-breaker-state
  '((openai . (:failures 0 :successes 0 :state closed))
    (anthropic . (:failures 0 :successes 0 :state closed)))
  "Circuit breaker state per provider."
  :type '(alist :key-type symbol :value-type plist))

(defun gptel--check-circuit-breaker (provider)
  "Check if circuit is open for PROVIDER."
  (let ((state (alist-get provider gptel-circuit-breaker-state)))
    (pcase (plist-get state :state)
      ('open (if (> (- (float-time) (plist-get state :opened-at)) 60)
                 (progn (setf (plist-get state :state) 'half-open) 'half-open)
               'open))
      ('half-open 'half-open)
      (_ 'closed))))

(defun gptel--record-failure (provider)
  "Record failure for PROVIDER, open circuit if threshold exceeded."
  (let ((state (alist-get provider gptel-circuit-breaker-state)))
    (cl-incf (plist-get state :failures))
    (when (>= (plist-get state :failures) 5)
      (setf (plist-get state :state) 'open)
      (setf (plist-get state :opened-at) (float-time)))))

(defun gptel--record-success (provider)
  "Record success, reset failures for PROVIDER."
  (let ((state (alist-get provider gptel-circuit-breaker-state)))
    (setf (plist-get state :failures) 0)
    (setf (plist-get state :state) 'closed)))
```

**Checkpoint Directory**: `~/.emacs.d/.gptel/checkpoints/`

**Usage Pattern**:

```elisp
(defun gptel--checkpoint-save (experiment-id data)
  "Save EXPERIMENT-ID checkpoint to disk."
  (let ((dir (expand-file-name "checkpoints" gptel-data-dir)))
    (make-directory dir t)
    (with-temp-file (expand-file-name (format "%s.json" experiment-id) dir)
      (insert (json-serialize data)))))

(defun gptel--checkpoint-restore (experiment-id)
  "Restore checkpoint for EXPERIMENT-ID."
  (let ((file (expand-file-name (format "%s.json" experiment-id)
                                (expand-file-name "checkpoints" gptel-data-dir))))
    (when (file-exists-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (json-parse-buffer :object-type 'plist)))))
```

---

### 2. Tool Receipts for Audit Trail

**Source**: [efrit](https://github.com/davidwuchn/efrit) (35+ tools with security controls)

**Problem Addressed**: No record of tool executions for replay, debugging, or compliance.

**Technique**: Every tool execution generates structured metadata: `(input-hash output-hash timestamp duration tool-name)`. Shell commands have allowed/forbidden pattern matching.

**Implementation using sqlite.el**:

```elisp
(require 'sqlite)

(defvar gptel-tool-log-db nil
  "SQLite database for tool execution logs.")

(defun gptel-tool-log-init ()
  "Initialize tool log database."
  (setq gptel-tool-log-db
        (sqlite-open (expand-file-name "tool-log.db" gptel-data-dir)))
  (sqlite-execute gptel-tool-log-db
    "CREATE TABLE IF NOT EXISTS tool_receipts (
       id INTEGER PRIMARY KEY AUTOINCREMENT,
       session_id TEXT,
       timestamp REAL,
       tool_name TEXT,
       input_hash TEXT,
       output_hash TEXT,
       duration_ms INTEGER,
       success INTEGER,
       error TEXT
     )")
  (sqlite-execute gptel-tool-log-db
    "CREATE INDEX IF NOT EXISTS idx_session ON tool_receipts(session_id)")
  (sqlite-execute gptel-tool-log-db
    "CREATE INDEX IF NOT EXISTS idx_tool ON tool_receipts(tool_name)"))

(defun gptel-tool-log-record (session-id tool-name input output duration-ms success &optional error)
  "Record tool execution to audit trail."
  (sqlite-execute gptel-tool-log-db
    "INSERT INTO tool_receipts VALUES (NULL, ?, ?, ?, ?, ?, ?, ?, ?)"
    (list session-id
          (float-time)
          tool-name
          (secure-hash 'sha256 (prin1-to-string input))
          (secure-hash 'sha256 (prin1-to-string output))
          duration-ms
          (if success 1 0)
          error)))

(defun gptel-tool-log-query (session-id &optional limit)
  "Query tool executions for SESSION-ID."
  (sqlite-select gptel-tool-log-db
    (format "SELECT * FROM tool_receipts WHERE session_id = ? ORDER BY timestamp %s"
            (if limit (format "LIMIT %d" limit) ""))
    (list session-id)))
```

---

### 3. Lambda Notation + Mathematical Attention Magnets

**Source**: [nucleus](https://github.com/davidwuchn/nucleus)

**Problem Addressed**: Verbose prompts waste context; LLM attention scatters across irrelevant preamble.

**Technique**: Greek letters and math symbols as compressed prompt preamble: `λ engage(nucleus). [phi fractal euler tao pi mu ∃ ∀] | [Δ λ Ω ∞/0 | ε/φ Σ/μ c/h] | OODA`. Primes formal reasoning patterns.

**Implementation**:

```elisp
(defcustom gptel-nucleus-preamble-map
  '(("λ" . "lambda-execute")
    ("φ" . "phi-balance")    ; signal/noise balance
    ("ψ" . "psi-state")      ; state transition
    ("Δ" . "delta-change")   ; change detection
    ("ε" . "epsilon-precision") ; precision threshold
    ("Ω" . "omega-completion") ; goal completion
    ("∞" . "infinite-context")
    ("∃" . "exists-check")
    ("∀" . "forall-verify"))
  "Map mathematical symbols to semantic behaviors."
  :type '(alist :key-type string :value-type string))

(defun gptel-build-nucleus-preamble (&rest behaviors)
  "Build compressed preamble from BEHAVIORS list."
  (let ((symbols (mapcan (lambda (b)
                           (let ((pair (assoc b gptel-nucleus-preamble-map)))
                             (when pair (list (car pair)))))
                         behaviors)))
    (when symbols
      (format "λ engage(gptel). [%s]" (string-join symbols " ")))))

;; Usage in workflow prompts:
;; (gptel-build-nucleus-preamble "lambda-execute" "phi-balance" "delta-change")
;; => "λ engage(gptel). [λ φ Δ]"
```

**EDN Statechart Format**:

```elisp
(defun gptel-state-to-edn (state)
  "Convert workflow STATE to EDN format."
  (format "{:phase %s :actions [%s] :timestamp %s}"
          (plist-get state :phase)
          (string-join (plist-get state :actions) " ")
          (plist-get state :timestamp)))

;; Example EDN state:
;; {:phase :planning :actions [analyze execute verify] :timestamp 1716400000.0}
```

---

### 4. Think-in-Code Context Reduction

**Source**: [context-mode](https://github.com/davidwuchn/context-mode)

**Problem Addressed**: Raw file dumps (700KB) bloat context; LLM becomes data processor instead of thinking agent.

**Technique**: Instead of dumping file reads, execute analysis script that returns only result (3.6KB). Achieves 98% context reduction via sandbox tools.

**Implementation**:

```elisp
(defcustom gptel-sandbox-max-bytes 10240
  "Maximum bytes to return from sandbox execution."
  :type 'integer)

(defun gptel-sandbox-execute (analysis-script &optional params)
  "Execute ANALYSIS-SCRIPT in isolated subprocess, return structured result.
PARAMS are passed as environment variables."
  (let* ((script-file (make-temp-file "gptel-analysis-" nil ".el"))
         (output-file (make-temp-file "gptel-result-" nil ".json"))
         (env-vars (mapconcat (lambda (p)
                                (format "%s=%s" (car p) (cdr p)))
                              params " ")))
    (unwind-protect
        (progn
          (with-temp-file script-file
            (insert "(progn\n")
            (insert analysis-script)
            (insert (format "\n  (with-temp-file %S\n    (insert (json-serialize result)))\n)"
                           output-file)))
          (let ((exit-code (call-process "emacs" nil nil nil
                                         "--batch" "-l" script-file)))
            (when (= exit-code 0)
              (with-temp-buffer
                (insert-file-contents output-file)
                (let ((result (ignore-errors (json-parse-buffer))))
                  (when (> (buffer-size) gptel-sandbox-max-bytes)
                    (setq result `(:truncated t :size ,(buffer-size)
                                   :summary "Output exceeds maximum size")))
                  result)))))
      (delete-file script-file)
      (delete-file output-file))))

;; Example: Analysis script that would normally dump 50 files
;; Instead returns only the summary:
;; (gptel-sandbox-execute
;;  "(let ((result (list))) 
;;     (dolist (file (directory-files default-directory t \"\\.el$\"))
;;       (push (list :file file :lines (count-lines-file file)) result))
;;     (list :files (length result) :total-lines (apply '+ (mapcar 'cadr result))))")
```

---

### 5. Session Continuity via FTS5

**Source**: [context-mode](https://github.com/davidwuchn/context-mode)

**Problem Addressed**: Session state lost on context compaction; no mechanism to retrieve relevant history.

**Technique**: Every edit, git op, task, error tracked in SQLite with FTS5. When context compacts, retrieves only relevant events via BM25 search—not dumps raw data.

**Implementation**:

```elisp
(defvar gptel-session-db nil)

(defun gptel-session-init ()
  "Initialize session continuity database."
  (setq gptel-session-db
        (sqlite-open (expand-file-name "session.db" gptel-data-dir)))
  (sqlite-execute gptel-session-db
    "CREATE TABLE IF NOT EXISTS session_events (
       id INTEGER PRIMARY KEY AUTOINCREMENT,
       session_id TEXT,
       timestamp REAL,
       event_type TEXT,
       data TEXT
     )")
  (sqlite-execute gptel-session-db
    "CREATE VIRTUAL TABLE IF NOT EXISTS session_fts USING fts5(
       event_type, data, content=session_events, content_rowid=id)"))
  (sqlite-execute gptel-session-db
    "CREATE TRIGGER IF NOT EXISTS session_ai AFTER INSERT ON session_events BEGIN
       INSERT INTO session_fts(rowid, event_type, data) VALUES (new.id, new.event_type, new.data);
     END"))

(defun gptel-session-log (session-id event-type data)
  "Log EVENT-TYPE with DATA for SESSION-ID."
  (sqlite-execute gptel-session-db
    "INSERT INTO session_events VALUES (NULL, ?, ?, ?, ?)"
    (list session-id (float-time) event-type (json-serialize-string data))))

(defun gptel-session-retrieve (session-id query &optional limit)
  "Retrieve relevant events for SESSION-ID matching QUERY.
Uses FTS5 for semantic search."
  (sqlite-select gptel-session-db
    (format "SELECT se.* FROM session_events se
             JOIN session_fts fts ON se.id = fts.rowid
             WHERE se.session_id = ? AND session_fts MATCH ?
             ORDER BY se.timestamp DESC
             %s"
            (if limit (format "LIMIT %d" limit) ""))
    (list session-id query)))
```

---

### 6. Feed-Forward Memory Protocol

**Source**: [mementum](https://github.com/davidwuchn/mementum)

**Problem Addressed**: No persistent knowledge synthesis across sessions; patterns lost on restart.

**Technique**: Three storage types (working memory/state.md, memories <200 words, synthesized knowledge). Human governance: AI proposes, human approves, AI commits.

**Implementation**:

```elisp
(defvar gptel-memory-working-file nil
  "Path to current working memory state file.")

(defvar gptel-memory-memories-dir nil
  "Directory for memory fragments (<200 words each).")

(defvar gptel-memory-knowledge-dir nil
  "Directory for synthesized knowledge pages.")

(defun gptel-memory-synthesize ()
  "Read working memory on session start, synthesize patterns."
  (when (file-exists-p gptel-memory-working-file)
    (with-temp-buffer
      (insert-file-contents gptel-memory-working-file)
      (goto-char (point-min))
      (while (not (eobp))
        (let ((line (thing-at-point 'line t)))
          (when (string-match "^## \\(.+\\)$" line)
            (let ((topic (match-string 1 line)))
              (message "Synthesizing knowledge for: %s" topic))))
        (forward-line)))))

(defun gptel-memory-propose-knowledge (topic content)
  "Propose new knowledge TOPIC with CONTENT for human approval."
  (let ((proposal-file (expand-file-name
                        (format "proposals/%s.md" topic)
                        gptel-memory-knowledge-dir)))
    (make-directory (file-name-directory proposal-file) t)
    (with-temp-file proposal-file
      (insert (format "# Knowledge Proposal: %s\n\n" topic))
      (insert "Status: pending-approval\n\n")
      (insert content)
      (insert "\n\n---\n*Auto-generated by gptel*\n")))
  (message "Knowledge proposal written to %s" proposal-file))

(defun gptel-memory-commit-knowledge (topic)
  "Commit approved knowledge TOPIC."
  (let ((proposal-file (expand-file-name
                        (format "proposals/%s.md" topic)
                        gptel-memory-knowledge-dir))
        (commit-file (expand-file-name
                      (format "%s.md" topic)
                      gptel-memory-knowledge-dir)))
    (when (file-exists-p proposal-file)
      (with-temp-buffer
        (insert-file-contents proposal-file)
        (goto-char (point-min))
        (while (search-forward "pending-approval" nil t)
          (replace-match "approved"))
        (write-file commit-file))
      (delete-file proposal-file))))
```

---

## Tier 2: Agent Architecture Patterns

### 7. Three-Tier Watchdog Architecture

**Source**: [gastown](https://github.com/davidwuchn/gastown)

**Problem Addressed**: No systematic lifecycle management; failures cascade silently.

**Technique**: Three tiers: Witness (session lifecycle), Deacon (continuous background patrol), Dogs (dispatched workers). Convoy system bundles work items with autonomous stall detection.

**Implementation**:

```elisp
(defvar gptel-witness-timer nil)
(defvar gptel-deacon-timer nil)
(defvar gptel-dogs-processes nil)

(defun gptel-witness--check-session ()
  "Witness: Monitor session health and lifecycle."
  (let ((session-age (- (float-time) gptel-session-start-time)))
    (cond
     ((> session-age (* 60 60 4))  ; 4 hours
      (gptel-session-checkpoint)
      (gptel-session-refresh))
     ((gptel-session-stale-p)
      (gptel-session-recover)))))

(defun gptel-deacon--patrol ()
  "Deacon: Continuous background health checks."
  (dolist (work-item gptel-work-queue)
    (when (gptel-work-stalled-p work-item)
      (gptel-work-dispatch-dog work-item))))

(defun gptel-work-dispatch-dog (work-item)
  "Dispatch a dog to handle stalled WORK-ITEM."
  (let ((dog-process
         (make-process
          :name (format "gptel-dog-%s" (plist-get work-item :id))
          :command '("emacs" "--batch"
                     "-l" (expand-file-name "gptel-dog.el" gptel-module-dir)
                     "--eval" (format "(gptel-dog-recover %S)" work-item))
          :sentinel (lambda (proc event)
                      (gptel-dog--handle-completion proc event work-item)))))
    (push (cons work-item dog-process) gptel-dogs-processes)))

(defun gptel-dog--handle-completion (proc event work-item)
  "Handle dog completion for WORK-ITEM."
  (setq gptel-dogs-processes
        (cl-remove proc gptel-dogs-processes :test #'eq :key #'cdr))
  (cond
   ((string-match "finished" event)
    (gptel-work-complete work-item))
   ((string-match "failed" event)
    (gptel-work-escalate work-item 'high))))
```

---

### 8. Self-Wiring Knowledge Graph

**Source**: [gbrain](https://github.com/davidwuchn/gbrain)

**Problem Addressed**: Knowledge scattered across memories; no automatic linking between related concepts.

**Technique**: Every page write extracts entity references and creates typed edges with zero LLM calls. Achieves +31.4 P@5 lift over vector-only RAG.

**Implementation**:

```elisp
(defun gptel-entity-extract (text)
  "Extract entity references from TEXT using pattern matching.
Returns list of (entity type) tuples."
  (let ((entities nil))
    ;; Extract wiki-links [[category/name]]
    (when (string-match "\\[\\[\\([^/]+\\)/\\([^]]+\\)\\]\\]" text)
      (push (list (match-string 2 text) (match-string 1 text)) entities))
    ;; Extract typed references
    (dolist (pattern '(("works at" . :works_at)
                       ("founded" . :founded)
                       ("attended" . :attended)
                       ("invested in" . :invested_in)
                       ("uses" . :uses)
                       ("implements" . :implements)))
      (when (string-match (car pattern) text)
        (push (list (match-string 1 text) (cdr pattern)) entities)))
    entities))

(defun gptel-graph-link (source-entity target-entity edge-type)
  "Create typed edge between SOURCE-ENTITY and TARGET-ENTITY of EDGE-TYPE."
  (sqlite-execute gptel-session-db
    "INSERT OR IGNORE INTO knowledge_graph VALUES (?, ?, ?)"
    (list source-entity target-entity (symbol-name edge-type))))

(defun gptel-graph-query (entity &optional limit)
  "Query graph for ENTITY and related nodes."
  (sqlite-select gptel-session-db
    (format "SELECT * FROM knowledge_graph
             WHERE source = ? OR target = ?
             LIMIT %s" (or limit 20))
    (list entity entity)))
```

---

### 9. Self-Verification Engine

**Source**: [genesis-agent](https://github.com/davidwuchn/genesis-agent)

**Problem Addressed**: LLM outputs accepted blindly; syntax errors, failed tests not caught before commit.

**Technique**: 66 deterministic checks where "the LLM proposes — the machine verifies." AST parsing, exit codes, import resolution, file validation, module signatures.

**Implementation**:

```elisp
(defvar gptel-verification-checks
  '(syntax byte-compile file-integrity test-run signature-match))

(defun gptel-verify-changes (planned-changes)
  "Run verification checks on PLANNED-CHANGES before commit.
Returns (passes . failures) list."
  (let ((passes nil) (failures nil))
    (dolist (change planned-changes)
      (let ((result (gptel--run-verification change)))
        (if (plist-get result :passed)
            (push change passes)
          (push (cons change (plist-get result :error)) failures))))
    (cons passes failures)))

(defun gptel--run-verification (change)
  "Run all verification checks on CHANGE."
  (let ((errors nil))
    ;; Syntax check
    (unless (gptel-verify-syntax (plist-get change :file))
      (push "Syntax error" errors))
    ;; Byte compile
    (unless (gptel-verify-byte-compile (plist-get change :file))
      (push "Byte compilation failed" errors))
    ;; File integrity
    (unless (gptel-verify-file-exists (plist-get change :file))
      (push "File does not exist" errors))
    ;; Test run
    (unless (gptel-verify-tests (plist-get change :file))
      (push "Tests failed" errors))
    (if errors
        (list :passed nil :error (string-join errors "; "))
      (list :passed t))))

(defun gptel-verify-syntax (file)
  "Verify FILE has valid Emacs Lisp syntax."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (condition-case nil
        (progn (read (current-buffer)) t)
      (error nil))))

(defun gptel-verify-byte-compile (file)
  "Verify FILE compiles without errors."
  (eq 0 (apply #'call-process "emacs" nil nil nil
               "--batch" "-l" file "-f" "batch-byte-compile"
               (list (expand-file-name file)))))
```

---

### 10. P(Success) Confidence Tracking

**Source**: [genesis-agent](https://github.com/davidwuchn/genesis-agent) + [MetaAgent](https://arxiv.org/abs/2508.00271)

**Problem Addressed**: No confidence estimation for task outcomes; equal weight given to untested and proven patterns.

**Technique**: [PLAN] + [EXPECT] with P(success) confidence scoring based on prior outcomes. Self-reflection + answer verification → distill experience into concise texts.

**Implementation**:

```elisp
(defvar gptel-confidence-history (make-hash-table :test 'equal))

(defun gptel-calculate-confidence (task-type context)
  "Calculate P(success) for TASK-TYPE in CONTEXT.
Based on historical success rate with Bayesian smoothing."
  (let* ((history (gethash (list task-type context) gptel-confidence-history))
         (n (length history))
         (successes (cl-count-if #'identity history))
         (base-rate 0.5))
    (if (< n 5)
        base-rate  ; Insufficient data
      (/ (+ successes (* 0.5 (- n successes)))
         n))))  ; Bayesian smoothing

(defun gptel-record-outcome (task-type context success)
  "Record OUTCOME for TASK-TYPE in CONTEXT."
  (let* ((key (list task-type context))
         (history (gethash key gptel-confidence-history)))
    (push success history)
    ;; Keep last 100 outcomes
    (when (> (length history) 100)
      (setq history (cl-subseq history 0 100)))
    (puthash key history gptel-confidence-history)))

(defun gptel-decide-with-confidence (task-type context threshold)
  "Decide whether to attempt TASK-TYPE based on confidence vs THRESHOLD."
  (let ((p-success (gptel-calculate-confidence task-type context)))
    (cons p-success
          (if (>= p-success threshold)
              :proceed
            :defer))))
```

---

## Tier 3: Resilience & Recovery Patterns

### 11. Provider Fallback Chains

**Source**: [Azure AI Agent Orchestration](https://learn.microsoft.com/en-us/azure/architecture/ai-ml/guide/ai-agent-design-patterns) + [zeroclaw](https://github.com/davidwuchn/zeroclaw)

**Problem Addressed**: Single provider failure breaks entire workflow.

**Technique**: Provider A → Provider B → Provider C with automatic failover.

**Implementation**:

```elisp
(defcustom gptel-provider-chain
  '(openai anthropic ollama)
  "Fallback chain of providers, tried in order."
  :type '(repeat symbol))

(defcustom gptel-timeout-map
  '((openai . 60)
    (anthropic . 90)
    (ollama . 30))
  "Timeout per provider in seconds."
  :type '(alist :key-type symbol :value-type integer))

(defun gptel-request-with-fallback (prompt &optional params)
  "Request PROMPT with automatic provider fallback."
  (let ((providers gptel-provider-chain)
        (last-error nil))
    (while providers
      (let* ((provider (pop providers))
             (circuit-state (gptel--check-circuit-breaker provider)))
        (unless (eq circuit-state 'open)
          (condition-case err
              (let ((timeout (or (alist-get provider gptel-timeout-map) 60)))
                (gptel--with-timeout timeout
                  (let ((result (gptel--call-provider provider prompt params)))
                    (gptel--record-success provider)
                    (cl-return-from gptel-request-with-fallback result))))
            (gptel-timeout
             (push (cons provider "timeout") last-error)
             (gptel--record-failure provider))
            (error
             (push (cons provider (error-message-string err)) last-error)
             (gptel--record-failure provider))))))
    (signal 'gptel-all-providers-failed (list last-error))))
```

---

### 12. Exponential Backoff with Jitter

**Source**: [AI Agent Error Recovery Patterns](https://aiagentsblog.com/blog/agent-error-recovery-patterns/)

**Problem Addressed**: Retries hammer failing services; thundering herd on recovery.

**Technique**: Retry delays increase exponentially with random jitter to prevent cascade.

**Implementation**:

```elisp
(defun gptel-exponential-backoff (attempt base-delay max-delay)
  "Calculate delay for ATTEMPT with exponential backoff and jitter.
BASE-DELAY and MAX-DELAY in seconds."
  (let* ((exponential-delay (* base-delay (expt 2 attempt)))
         (jitter (* exponential-delay (random 0.3)))
         (total-delay (+ exponential-delay jitter)))
    (min total-delay max-delay)))

(defun gptel-retry-with-backoff (fn &optional max-attempts base-delay)
  "Retry FN with exponential backoff up to MAX-ATTEMPTS times."
  (let ((attempt 0)
        (max-attempts (or max-attempts 5))
        (base-delay (or base-delay 1.0)))
    (while (< attempt max-attempts)
      (condition-case err
          (cl-return-from gptel-retry-with-backoff (funcall fn))
        (error
         (when (< attempt (1- max-attempts))
           (let ((delay (gptel-exponential-backoff attempt base-delay 60)))
             (message "Retry %d/%d failed, waiting %.1fs: %s"
                      (1+ attempt) max-attempts delay (error-message-string err))
             (sleep-for delay))))
        (gptel-retryable
         (when (< attempt (1- max-attempts))
           (let ((delay (gptel-exponential-backoff attempt base-delay 60)))
             (message "Retryable error, waiting %.1fs" delay)
             (sleep-for delay)))))
      (cl-incf attempt))
    (signal 'gptel-max-retries-exceeded (list max-attempts))))
```

---

### 13. DEGRADED State Circuit Breaker

**Source**: External (Hannecke Medium article)

**Problem Addressed**: Binary open/close circuit breaker too coarse; forces hard fail when partial capability acceptable.

**Technique**: DEGRADED state between CLOSED/OPEN allows graceful degradation. Five failure categories need different handling. Graduated re-enablement: L1 (5% traffic), L2 (20%), L3 (50%).

**Implementation**:

```elisp
(defvar gptel-capability-levels
  '(:full :l3-reduced :l2-limited :l1-minimal :degraded))

(defvar gptel-degraded-configs
  '((:full . (:risky-tools t :human-review nil :conservative nil))
    (:l3-reduced . (:risky-tools nil :human-review nil :conservative nil))
    (:l2-limited . (:risky-tools nil :human-review t :conservative nil))
    (:l1-minimal . (:risky-tools nil :human-review t :conservative t))
    (:degraded . (:risky-tools nil :human-review t :conservative t :limited-providers t))))

(defun gptel--compute-capability-level (failure-count)
  "Compute capability level based on FAILURE-COUNT."
  (cond
   ((>= failure-count 10) :degraded)
   ((>= failure-count 7) :l1-minimal)
   ((>= failure-count 5) :l2-limited)
   ((>= failure-count 3) :l3-reduced)
   (t :full)))

(defun gptel-with-capability-level (fn)
  "Execute FN with current capability restrictions."
  (let* ((failure-count (gptel-get-failure-count))
         (level (gptel--compute-capability-level failure-count))
         (config (alist-get level gptel-degraded-configs)))
    (cl-flet ((risky-tools-allowed? () (plist-get config :risky-tools))
              (requires-human-review? () (plist-get config :human-review))
              (conservative-mode? () (plist-get config :conservative)))
      (funcall fn config))))
```

---

## Tier 4: Orchestration & Evaluation Patterns

### 14. Trajectory-Aware Metrics

**Source**: [NVIDIA AI Agent Evaluation Guide](https://developer.nvidia.com/blog/mastering-agentic-techniques-ai-agent-evaluation/)

**Problem Addressed**: Only final answers evaluated; no visibility into reasoning quality or efficiency.

**Technique**: Evaluate trajectories, not just final answers. Track steps/tokens per success.

**Metrics Table**:

| Metric | Formula | Target |
|--------|---------|--------|
| **Task Success Rate (TSR)** | successes / total_tasks | > 0.85 |
| **Tool Call Accuracy** | correct_calls / total_calls | > 0.90 |
| **Trajectory Efficiency** | 1 / (steps × tokens) | maximize |
| **Reasoning Soundness** | validated_steps / total_steps | > 0.80 |

**Implementation**:

```elisp
(defvar gptel-trajectory-log nil)

(defun gptel-trajectory-record (phase data)
  "Record trajectory event for PHASE with DATA."
  (push (cons (list :phase phase :timestamp (float-time)) data)
        gptel-trajectory-log))

(defun gptel-calculate-metrics ()
  "Calculate trajectory metrics from logged data."
  (let* ((steps (length gptel-trajectory-log))
         (total-tokens (cl-reduce '+ (mapcar (lambda (e) (or (plist-get e :tokens) 0))
                                            gptel-trajectory-log)))
         (successful-steps (cl-count-if (lambda (e) (plist-get e :success))
                                        gptel-trajectory-log)))
    (list :steps steps
          :total-tokens total-tokens
          :efficiency (/ 1.0 (max 1 (* steps total-tokens)))
          :reasoning-soundness (/ (float successful-steps) (max 1 steps))
          :trajectory gptel-trajectory-log)))
```

---

### 15. Multi-Agent Workspace Orchestration

**Source**: [gastown](https://github.com/davidwuchn/gastown)

**Problem Addressed**: Single agent bottleneck; no coordination between specialized workers.

**Technique**: Git-backed hooks for persistent work state; mailboxes and handoffs. Scales to 20-30 agents.

**Implementation**:

```elisp
(defvar gptel-work-beads nil)

(defun gptel-work-bead-create (task-id agent-id action)
  "Create immutable work bead for TASK-ID by AGENT-ID performing ACTION."
  (let ((bead `( :id ,(format "bead-%s" (cl-gensym))
                 :task ,task-id
                 :agent ,agent-id
                 :action ,action
                 :timestamp ,(float-time)
                 :status :pending)))
    (push bead gptel-work-beads)
    (gptel-work-bead-persist bead)
    bead))

(defun gptel-work-bead-persist (bead)
  "Persist BEAD as git commit with structured metadata."
  (let ((commit-file (expand-file-name
                      (format "beads/%s.json" (plist-get bead :id))
                      gptel-data-dir)))
    (make-directory (file-name-directory commit-file) t)
    (with-temp-file commit-file
      (insert (json-serialize bead)))
    (when (gptel-git-available-p)
      (gptel-work-bead-git-commit bead))))

(defun gptel-work-bead-git-commit (bead)
  "Commit BEAD to git for durability."
  (let ((dir default-directory))
    (unwind-protect
        (progn
          (cd (expand-file-name "beads" gptel-data-dir))
          (shell-command "git add -A && git commit -m 'bead'")
          (cd dir))
      (cd dir))))
```

---

## Actionable Patterns Summary

### High Impact, Medium Difficulty

1. **Circuit Breaker + Checkpoint/Restore**
   - File: `gptel-auto-workflow-daemon.el`
   - Action: Track `(failure-count success-count last-failure provider)` per provider
   - Trigger: Open circuit after 5 consecutive failures

2. **Tool Receipts Audit Trail**
   - File: `gptel-tools-memory.el`
   - Action: Implement `gptel-tool-log` using sqlite.el
   - Schema: `(tool-executed tool-name input-hash output-hash timestamp duration success)`

3. **Three-Tier Watchdog**
   - Files: `gptel-auto-workflow-daemon.el`, new `gptel-witness.el`, `gptel-deacon.el`
   - Action: Separate lifecycle management from execution

### High Impact, High Difficulty

4. **Think-in-Code Context Reduction**
   - File: `gptel-auto-workflow-projects.el`
   - Action: Refactor analysis passes to accept executable scripts
   - Target: 98% context reduction for file-heavy operations

5. **Self-Wiring Knowledge Graph**
   - File: `gptel-tools-memory.el`
   - Action: Parse `[[category/name]]` refs, create typed edges
   - Target: +31 P@5 lift over vector-only RAG

6. **Hybrid Search (Vector + BM25)**
   - File: `gptel-auto-workflow-projects.el`
   - Action: Use ollama embeddings + ripgrep BM25
   - Target: P@5 49.1%

### Quick Wins

7. **P(Success) Confidence Tracking**
   - File: `gptel-auto-workflow-evolution.el`
   - Action: Bayesian confidence scoring per task type

8. **Provider Fallback Chain**
   - File: `gptel-ext-core.el`
   - Action: Implement `openai → anthropic → ollama` chain

9. **Exponential Backoff with Jitter**
   - File: `gptel-tools-agent-runtime.el`
   - Action: Wrap provider calls with retry logic

---

## Related

- [[research-strategies]] - Research strategy patterns and selection criteria
- [[module-complexity-analysis]] - Analysis of complex modules requiring nil-safety
- [[self-evolution-controller]] - Controller implementation patterns
- [[experiment-loop-patterns]] - Experiment execution and logging patterns
- [[memory-synthesis]] - Knowledge synthesis from experiment outcomes

---

## Changelog

| Date | Hash | Modules Targeted | Retention |
|------|------|------------------|-----------|
| 2026-05-25 | e438c226 | gptel-auto-workflow-strategic.el, gptel-tools-agent-prompt-build.el | 0/15 (0%) |
| 2026-05-22 | 9bbb457 | gptel-tools-agent-runtime.el, gptel-tools-memory.el | 9/39 (23%) |
| 2026-05-20 | 9af4a35c | gptel-tools-memory.el, gptel-benchmark-integrate.el | 4/24 (17%) |
| 2026-05-22 | 1d3ac048 | gptel-tools-preview.el, gptel-auto-workflow-mementum.el | 2/56 (4%) |
| 2026-05-22 | 1cc6c4c | gptel-benchmark-evolution.el, gptel-tools-agent-strategy-harness.el | 3/9 (33%) |

---

*Generated by auto-workflow*
*Research quality measured by downstream experiment success*
```