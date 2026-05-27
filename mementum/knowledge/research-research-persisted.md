<!--
Synthesis verification:
- Confidence: 24%
- Sources: 6 memories
- Warnings: No code examples or concrete references, Content does not mention topic 'research-research-persisted'
- Auto-approved: yes (flagged)
--->

---
title: Research Patterns & External Sources Knowledge Page
status: active
category: knowledge
tags: [research, patterns, external-sources, agent-architecture, self-evolution]
---

# Research Patterns & External Sources Knowledge Page

## Executive Summary

This knowledge page synthesizes research findings from multiple research sessions across the auto-workflow system. It captures architectural patterns, resilience mechanisms, and evaluation frameworks derived from external repositories and academic sources. The primary goal is to establish actionable patterns for improving the Emacs AI agent system through systematic self-evolution.

**Key metrics tracked:**
- Research retention rate: 4-33% across sessions
- Module complexity baseline: 58,031 total lines in `lisp/modules/`
- Focus shift: 8 bug fixes vs 0 feature commits (stabilization phase)
- Self-evolution directive: Apply nil-safety patterns and validation guards to high-failure modules

---

## 1. Tier 1: Directly Applicable Patterns (Emacs Lisp + AI Agents)

### 1.1 Circuit Breaker + Checkpoint/Restore Pattern

**Source:** [efrit](https://github.com/davidwuchn/efrit)  
**Impact:** HIGH | **Difficulty:** MEDIUM

**Pattern Description:**
Circuit breaker monitors failure rates per provider, transitioning through CLOSED→OPEN→HALF-OPEN states to prevent cascading failures. Checkpoint/restore stores state snapshots before risky operations.

**Implementation Sketch:**
```elisp
(defcustom gptel-circuit-breaker
  '((provider . ((failure-count . 0)
                 (success-count . 0)
                 (last-failure . nil)
                 (state . closed))))
  "Circuit breaker state per provider.
State transitions: closed → open (5 consecutive failures)
                 open → half-open (timeout expired)
                 half-open → closed (1 success)
                 half-open → open (1 failure)")

(defun gptel--check-circuit (provider)
  "Check if circuit is open for PROVIDER."
  (let ((state (alist-get 'state (alist-get provider gptel-circuit-breaker))))
    (not (eq state 'open))))

(defun gptel--record-failure (provider)
  "Record failure for PROVIDER, potentially opening circuit."
  (let ((pb (alist-get provider gptel-circuit-breaker)))
    (setf (alist-get 'failure-count pb) (1+ (alist-get 'failure-count pb)))
    (setf (alist-get 'last-failure pb) (current-time))
    (when (>= (alist-get 'failure-count pb) 5)
      (setf (alist-get 'state pb) 'open)
      (message "Circuit OPEN for %s after %d failures" provider (alist-get 'failure-count pb)))))

(defun gptel--record-success (provider)
  "Record success for PROVIDER, potentially closing circuit."
  (let ((pb (alist-get provider gptel-circuit-breaker)))
    (setf (alist-get 'success-count pb) (1+ (alist-get 'success-count pb)))
    (setf (alist-get 'failure-count pb) 0)
    (setf (alist-get 'state pb) 'closed)))
```

**Checkpoint/Restore Implementation:**
```elisp
(defvar gptel-checkpoint-dir (expand-file-name ".gptel/checkpoints/" user-emacs-directory))

(defun gptel--checkpoint-save (experiment-id data)
  "Save checkpoint for EXPERIMENT-ID with DATA."
  (let ((file (expand-file-name (format "%s.eld" experiment-id) gptel-checkpoint-dir)))
    (make-directory gptel-checkpoint-dir t)
    (with-temp-file file
      (pp data (current-buffer)))))

(defun gptel--checkpoint-restore (experiment-id)
  "Restore checkpoint for EXPERIMENT-ID."
  (let ((file (expand-file-name (format "%s.eld" experiment-id) gptel-checkpoint-dir)))
    (when (file-exists-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (read (current-buffer))))))
```

---

### 1.2 Tool Receipts for Audit Trail

**Source:** [efrit](https://github.com/davidwuchn/efrit) (35+ tools with security controls)  
**Impact:** HIGH | **Difficulty:** MEDIUM

**Pattern Description:**
Every tool execution generates structured metadata: `(input-hash output-hash timestamp duration tool-name)`. Shell commands have allowed/forbidden pattern matching.

**Implementation:**
```elisp
(defvar gptel-tool-log-db (expand-file-name ".gptel/tool-log.db" user-emacs-directory))

(defun gptel--tool-log-init ()
  "Initialize SQLite tool log database."
  (require 'sqlite)
  (make-directory (file-name-directory gptel-tool-log-db) t)
  (sqlite-execute (sqlite-open gptel-tool-log-db)
    "CREATE TABLE IF NOT EXISTS tool_receipts (
       id INTEGER PRIMARY KEY AUTOINCREMENT,
       tool_name TEXT NOT NULL,
       input_hash TEXT NOT NULL,
       output_hash TEXT,
       timestamp REAL NOT NULL,
       duration_ms INTEGER,
       success INTEGER NOT NULL,
       error TEXT
     )"))

(defun gptel--tool-log-record (tool-name input output start-time success &optional error)
  "Record tool execution TOOL-NAME with INPUT/OUTPUT hashes."
  (let* ((end-time (current-time))
         (duration (floor (* 1000 (float-time (time-subtract end-time start-time)))))
         (input-hash (secure-hash 'sha256 (prin1-to-string input)))
         (output-hash (when output (secure-hash 'sha256 (prin1-to-string output)))))
    (sqlite-execute (sqlite-open gptel-tool-log-db)
      (format "INSERT INTO tool_receipts 
               (tool_name, input_hash, output_hash, timestamp, duration_ms, success, error)
               VALUES ('%s', '%s', '%s', %.3f, %d, %d, %s)"
        tool-name input-hash (or output-hash "NULL")
        (float-time start-time) duration (if success 1 0)
        (if error (format "'%s'" error) "NULL")))))

(defun gptel--tool-log-query (tool-name &optional limit)
  "Query recent receipts for TOOL-NAME."
  (sqlite-select (sqlite-open gptel-tool-log-db)
    (format "SELECT * FROM tool_receipts WHERE tool_name = '%s' ORDER BY timestamp DESC LIMIT %d"
      tool-name (or limit 10))))
```

---

### 1.3 Lambda Notation + Mathematical Attention Magnets

**Source:** [nucleus](https://github.com/davidwuchn/nucleus)  
**Impact:** MEDIUM | **Difficulty:** MEDIUM

**Pattern Description:**
Greek letters and math symbols as compressed prompt preamble: `λ engage(nucleus). [phi fractal euler tao pi mu ∃ ∀] | [Δ λ Ω ∞/0 | ε/φ Σ/μ c/h] | OODA`. Primes formal reasoning patterns.

**Implementation:**
```elisp
(defvar gptel-nucleus-preamble
  "λ engage(workflow). [φ ψ Δ λ ε] | [OODA REPL] | [plan act eval reflect]")

(defvar gptel-attention-magnets
  '(("φ" . "formal rigor, precision, constraint satisfaction")
    ("ψ" . "psychological state, intent alignment, user satisfaction")
    ("Δ" . "change detection, delta analysis, diff focus")
    ("λ" . "recursion, function composition, transformation")
    ("ε" . "error tolerance, bounded rationality, approximation")
    ("Ω" . "completion, finality, termination condition")
    ("∞" . "infinite loops, unbounded search (avoid)")
    ("Σ" . "aggregation, summation, cumulative metrics")
    ("μ" . "mean, average, expected value")
    ("∀" . "universality, all cases, generalization")
    ("∃" . "existence, at least one, search goal")))

(defun gptel--build-nucleus-prompt (context)
  "Build nucleus-inspired prompt with mathematical attention magnets."
  (format "%s\n\n## Context\n%s\n\n## Constraints\n- Signal > Noise\n- Order > Entropy\n- Verify > Trust\n"
    gptel-nucleus-preamble
    context))
```

---

### 1.4 Think-in-Code Context Reduction

**Source:** [context-mode](https://github.com/davidwuchn/context-mode)  
**Impact:** HIGH | **Difficulty:** HARD

**Pattern Description:**
Instead of dumping raw file reads (700KB), execute analysis script that returns only result (3.6KB). 98% context reduction via sandbox tools.

**Implementation:**
```elisp
(defvar gptel-sandbox-dir (expand-file-name ".gptel/sandbox/" user-emacs-directory))

(defun gptel--sandbox-execute (script content)
  "Execute SCRIPT with CONTENT in isolated sandbox.
Returns only structured result, not raw output.
Achieves ~98% context reduction vs raw data dumps."
  (make-directory gptel-sandbox-dir t)
  (let* ((input-file (make-temp-file (expand-file-name "input-" gptel-sandbox-dir)))
         (output-file (make-temp-file (expand-file-name "output-" gptel-sandbox-dir)))
         (result nil))
    (unwind-protect
        (progn
          (with-temp-file input-file
            (insert content))
          (let ((exit-code (call-process "bash" nil nil nil "-c"
                           (format "cd %s && %s < %s > %s 2>&1 && echo DONE >> %s"
                             gptel-sandbox-dir script input-file output-file output-file))))
            (when (file-exists-p output-file)
              (with-temp-buffer
                (insert-file-contents output-file)
                (goto-char (point-min))
                (when (re-search-forward "^DONE$" nil t)
                  (delete-region (match-beginning 0) (point-max)))
                (setq result (buffer-string))))))
      (ignore-errors (delete-file input-file))
      (ignore-errors (delete-file output-file)))
    result))

(defun gptel--compute-analysis (analysis-type data)
  "Compute ANALYSIS-TYPE on DATA using sandbox.
ANALYSIS-TYPE is a symbol like 'git-stats, 'module-complexity, 'error-pattern."
  (let* ((script-file (expand-file-name (format "analyze-%s.sh" analysis-type) gptel-sandbox-dir))
         (script (cond
                   ((eq analysis-type 'git-stats)
                    "jq '{commits: length, authors: [.[].author] | unique, types: group_by(.type)}'")
                   ((eq analysis-type 'module-complexity)
                    "awk 'FNR>1 {lines[$1]+=$2} END {for(m in lines) print m, lines[m]}' | sort -k2 -rn")
                   (t "cat"))))
    (gptel--sandbox-execute (format "echo '%s' | %s" data script) script)))
```

---

### 1.5 Session Continuity via FTS5

**Source:** [context-mode](https://github.com/davidwuchn/context-mode)  
**Impact:** MEDIUM | **Difficulty:** HARD

**Pattern Description:**
Every edit, git op, task, error tracked in SQLite with FTS5. When context compacts, retrieves only relevant events via BM25 search—not dumps raw data.

**Implementation:**
```elisp
(defvar gptel-session-db (expand-file-name ".gptel/session.db" user-emacs-directory))

(defun gptel--session-db-init ()
  "Initialize session continuity database with FTS5."
  (require 'sqlite)
  (make-directory (file-name-directory gptel-session-db) t)
  (let ((db (sqlite-open gptel-session-db)))
    (sqlite-execute db "CREATE TABLE IF NOT EXISTS session_events (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id TEXT NOT NULL,
      timestamp REAL NOT NULL,
      event_type TEXT NOT NULL,
      data TEXT
    )")
    (sqlite-execute db "CREATE VIRTUAL TABLE IF NOT EXISTS session_fts USING fts5(
      event_type, data, content='session_events', content_rowid='id'
    )")
    (sqlite-execute db "CREATE TRIGGER IF NOT EXISTS session_ai AFTER INSERT ON session_events BEGIN
      INSERT INTO session_fts(rowid, event_type, data) VALUES (new.id, new.event_type, new.data);
    END")
    db))

(defun gptel--session-track (session-id event-type data)
  "Track SESSION-ID EVENT-TYPE with DATA in session continuity DB."
  (sqlite-execute (sqlite-open gptel-session-db)
    (format "INSERT INTO session_events (session_id, timestamp, event_type, data)
             VALUES ('%s', %.3f, '%s', '%s')"
      session-id (float-time (current-time)) event-type
      (sqlite-escape-string (prin1-to-string data)))))

(defun gptel--session-retrieve (session-id query &optional limit)
  "Retrieve relevant events from SESSION-ID matching QUERY using FTS5 BM25."
  (sqlite-select (sqlite-open gptel-session-db)
    (format "SELECT e.*, bm25(session_fts) as rank
             FROM session_events e
             JOIN session_fts f ON e.id = f.rowid
             WHERE e.session_id = '%s' AND session_fts MATCH '%s'
             ORDER BY rank
             LIMIT %d"
      session-id (sqlite-escape-string query) (or limit 20))))
```

---

### 1.6 Feed-Forward Memory Protocol

**Source:** [mementum](https://github.com/davidwuchn/mementum)  
**Impact:** MEDIUM | **Difficulty:** MEDIUM

**Pattern Description:**
Three storage types (working memory/state.md, memories <200 words, synthesized knowledge). Human governance: AI proposes, human approves, AI commits.

**Implementation:**
```elisp
(defvar gptel-memory-synthesize--state-file
  (expand-file-name "mementum/state.md" user-emacs-directory))

(defvar gptel-memory-synthesize--memory-dir
  (expand-file-name "mementum/memories/" user-emacs-directory))

(defvar gptel-memory-synthesize--knowledge-dir
  (expand-file-name "mementum/knowledge/" user-emacs-directory))

(defun gptel-memory-synthesize ()
  "Synthesize knowledge from state.md on session start.
Three storage types:
1. Working memory: mementum/state.md (< 500 lines)
2. Memories: mementum/memories/*.md (< 200 words each)
3. Knowledge: mementum/knowledge/*.md (synthesized patterns)"
  (let ((state (when (file-exists-p gptel-memory-synthesize--state-file)
                 (with-temp-buffer
                   (insert-file-contents gptel-memory-synthesize--state-file)
                   (buffer-string)))))
    (list :state state
          :memories (gptel--memory-load-recent)
          :knowledge (gptel--knowledge-load-synthesized))))

(defun gptel--memory-load-recent ()
  "Load recent memories from mementum/memories/."
  (when (file-directory-p gptel-memory-synthesize--memory-dir)
    (mapcar (lambda (f)
              (with-temp-buffer
                (insert-file-contents f)
                (list :file (file-name-nondirectory f)
                      :content (gptel--memory-truncate (buffer-string) 200))))
            (seq-take (sort (directory-files gptel-memory-synthesize--memory-dir t)
                            (lambda (a b) (> (file-attribute-modification-time (file-attributes a))
                                           (file-attribute-modification-time (file-attributes b)))))
                      10))))

(defun gptel--memory-truncate (text max-words)
  "Truncate TEXT to MAX-WORDS words."
  (let ((words (split-string text)))
    (if (<= (length words) max-words)
        text
      (concat (string-join (seq-take words max-words) " ") "..."))))
```

---

## 2. Tier 2: Agent Architecture Patterns

### 2.1 Three-Tier Watchdog Architecture

**Source:** [gastown](https://github.com/davidwuchn/gastown)  
**Impact:** HIGH | **Difficulty:** MEDIUM

**Pattern Description:**
Systematized lifecycle management via three tiers:
- **Witness**: Session lifecycle management
- **Deacon**: Continuous background patrol
- **Dogs**: Dispatched workers for cleanup/error recovery

**Implementation:**
```elisp
(defvar gptel-watchdog-witness nil "Witness process timer")
(defvar gptel-watchdog-deacon nil "Deacon process timer")
(defvar gptel-watchdog-dogs '() "List of dispatched dog processes")

(defun gptel-watchdog-start ()
  "Start three-tier watchdog system."
  (setq gptel-watchdog-witness
        (run-at-time 0 60 #'gptel--witness-check))
  (setq gptel-watchdog-deacon
        (run-at-time 0 300 #'gptel--deacon-patrol)))

(defun gptel-watchdog-stop ()
  "Stop all watchdog tiers."
  (cancel-timer gptel-watchdog-witness)
  (cancel-timer gptel-watchdog-deacon)
  (dolist (dog gptel-watchdog-dogs)
    (cancel-timer dog)))

(defun gptel--witness-check ()
  "Witness: Check session health and lifecycle."
  (let ((session-age (gptel--session-age-seconds))
        (last-activity (gptel--last-activity-seconds)))
    (cond
     ((> session-age 7200) ; 2 hours
      (gptel--session-snapshot)
      (gptel--session-pause))
     ((> last-activity 600) ; 10 minutes
      (gptel--dispatch-dog 'gptel--dog-wake-session)))))

(defun gptel--deacon-patrol ()
  "Deacon: Continuous background health patrol."
  (gptel--patrol-memory-usage)
  (gptel--patrol-disk-space)
  (gptel--patrol-stale-checkpoints)
  (gptel--patrol-pending-experiments))

(defun gptel-dispatch-dog (dog-fn &optional delay)
  "Dispatch DOG-FN as a dog worker with optional DELAY."
  (let ((dog (run-at-time (or delay 0) nil
                          (lambda ()
                            (funcall dog-fn)
                            (setq gptel-watchdog-dogs
                                  (delq dog gptel-watchdog-dogs))))))
    (push dog gptel-watchdog-dogs)
    dog))

(defun gptel--dog-cleanup-stale ()
  "Dog: Clean up stale temporary files."
  (let ((stale-threshold (* 24 3600))) ; 24 hours
    (dolist (file (directory-files temporary-file-directory t))
      (when (and (string-prefix-p "gptel-" (file-name-nondirectory file))
                 (> (- (float-time) (file-attribute-modification-time (file-attributes file)))
                    stale-threshold))
        (delete-file file)))))
```

---

### 2.2 DEGRADED State Circuit Breaker

**Source:** External (Hannecke Medium article)  
**Impact:** MEDIUM | **Difficulty:** MEDIUM

**Pattern Description:**
Five failure categories (Hard, Structural, Semantic, Behavioral, Resource) need different handling. DEGRADED state between CLOSED/OPEN allows graceful degradation instead of hard fail.

**State Machine:**

```
CLOSED ──(3 failures)──► DEGRADED ──(2 more failures)──► OPEN
   ▲                         │                                │
   │                         │                                ▼
   └──(3 successes)──────────┘                          HALF-OPEN
```

**Implementation:**
```elisp
(defvar gptel-failure-categories
  '(hard structural semantic behavioral resource))

(defun gptel--classify-failure (error)
  "Classify ERROR into failure category."
  (cond
   ((string-match-p "void-function\\|wrong-type-argument\\|invalid-syntax" error)
    'hard)
   ((string-match-p "file-missing\\|dir-missing\\|module-not-found" error)
    'structural)
   ((string-match-p "wrong-answer\\|misinterpretation\\|hallucination" error)
    'semantic)
   ((string-match-p "timeout\\|hang\\|no-response" error)
    'behavioral)
   ((string-match-p "memory\\|disk\\|quota" error)
    'resource)
   (t 'unknown)))

(defun gptel--apply-degraded-mode (category)
  "Apply degraded mode based on failure CATEGORY."
  (pcase category
    ('hard
     (setq gptel-enable-mutation nil)
     (setq gptel-require-human-approval t)
     (message "DEGRADED: Hard failure - mutation disabled, approval required"))
    ('semantic
     (setq gptel-max-tool-calls (* gptel-max-tool-calls 2))
     (setq gptel-verification-required t)
     (message "DEGRADED: Semantic failure - extended verification"))
    ('resource
     (gptel--reduce-context-window)
     (gptel--disable-heavy-tools)
     (message "DEGRADED: Resource failure - context reduced"))
    (_
     (setq gptel-retry-delay (* gptel-retry-delay 2))
     (message "DEGRADED: %s failure - retry delay doubled" category))))

(defun gptel--recover-from-degraded ()
  "Gradually recover from degraded mode."
  (let ((current-ratio (/ (float gptel-success-count) (+ gptel-success-count gptel-failure-count))))
    (cond
     ((>= current-ratio 0.9) ; Full recovery at 90% success
      (gptel--reset-to-nominal)
      (message "RECOVERED: Full nominal mode restored"))
     ((>= current-ratio 0.7) ; Level 3 at 70%
      (gptel--enable-most-capabilities)
      (message "RECOVERED: Level 3 - 50% traffic allowed"))
     ((>= current-ratio 0.5) ; Level 2 at 50%
      (gptel--enable-some-capabilities)
      (message "RECOVERED: Level 2 - 20% traffic allowed")))))
```

---

### 2.3 Self-Verification Engine

**Source:** [genesis-agent](https://github.com/davidwuchn/genesis-agent)  
**Impact:** HIGH | **Difficulty:** MEDIUM

**Pattern Description:**
Genesis uses 66 deterministic checks where "the LLM proposes — the machine verifies." AST parsing, exit codes, import resolution, file validation, module signatures.

**Implementation:**
```elisp
(defvar gptel-verification-checks
  '(syntax-check byte-compile file-exists module-signature test-run output-valid))

(defun gptel--verify-llm-proposal (proposal)
  "Verify LLM PROPOSAL before execution.
Returns (success . details) or (failure . error-message)."
  (let ((checks-to-run gptel-verification-checks)
        (details '()))
    (dolist (check checks-to-run)
      (pcase check
        ('syntax-check
         (let ((syntax-errors (gptel--verify-elisp-syntax proposal)))
           (push (list check syntax-errors) details)
           (when syntax-errors
             (return (cons nil (format "Syntax errors: %s" syntax-errors))))))
        ('byte-compile
         (let ((compile-result (gptel--verify-byte-compile proposal)))
           (push (list check compile-result) details)
           (unless (plist-get compile-result :success)
             (return (cons nil (format "Compile failed: %s"
                                       (plist-get compile-result :error)))))))
        ('file-exists
         (dolist (file (gptel--extract-file-refs proposal))
           (unless (file-exists-p file)
             (return (cons nil (format "File not found: %s" file))))))
        ('module-signature
         (let ((sig-issues (gptel--verify-module-signatures proposal)))
           (push (list check sig-issues) details)
           (when sig-issues
             (return (cons nil (format "Signature issues: %s" sig-issues))))))))
    (cons t details)))

(defun gptel--verify-elisp-syntax (code)
  "Check syntax validity of elisp CODE."
  (with-temp-buffer
    (insert code)
    (let ((errors '()))
      (condition-case err
          (read (current-buffer))
        (error (push (format "%s at position %d" (cadr err) (caddr err)) errors)))
      (when (gptel--scan-syntax-errors)
        (setq errors (append errors (gptel--scan-syntax-errors))))
      errors)))

(defun gptel--verify-byte-compile (code)
  "Attempt to byte-compile CODE, return result."
  (let ((temp-file (make-temp-file "gptel-verify-" nil ".el")))
    (unwind-protect
        (progn
          (with-temp-file temp-file
            (insert code))
          (let ((compilation-finish-hook nil)
                (output nil))
            (condition-case err
                (progn
                  (byte-compile-file temp-file)
                  (list :success t :file (concat temp-file "c")))
              (error
               (list :success nil :error (format "%s" err))))))
      (ignore-errors (delete-file temp-file))
      (ignore-errors (delete-file (concat temp-file "c"))))))
```

---

### 2.4 P(Success) Confidence Scoring

**Source:** [genesis-agent](https://github.com/davidwuchn/genesis-agent) + [MetaAgent](https://arxiv.org/abs/2508.00271)  
**Impact:** MEDIUM | **Difficulty:** MEDIUM

**Pattern Description:**
Track P(success) confidence scoring based on prior outcomes. Generate help requests when task pattern unrecognized.

**Implementation:**
```elisp
(defvar gptel-p-success-history '() "List of (task-pattern . success-rate)")
(defvar gptel-p-success-threshold 0.6 "Minimum confidence to proceed")

(defun gptel--compute-p-success (task-context)
  "Compute P(success) for TASK-CONTEXT based on history."
  (let ((pattern (gptel--extract-task-pattern task-context))
        (history (alist-get pattern gptel-p-success-history)))
    (if history
        (let* ((n (length history))
               (successes (cl-count t history))
               (raw-rate (/ (float successes) n)))
          ;; Bayesian smoothing with prior of 0.5
          (/ (+ successes 2.0) (+ n 4.0)))
      0.5))) ; Default 0.5 for unseen patterns

(defun gptel--record-outcome (task-context success)
  "Record OUTCOME for TASK-CONTEXT."
  (let ((pattern (gptel--extract-task-pattern task-context)))
    (push success (alist-get pattern gptel-p-success-history t '()))
    ;; Keep only last 100 observations per pattern
    (setf (alist-get pattern gptel-p-success-history)
          (seq-take (alist-get pattern gptel-p-success-history) 100))))

(defun gptel--check-proceed (task-context)
  "Check if should proceed with TASK-CONTEXT based on P(success)."
  (let ((p (gptel--compute-p-success task-context)))
    (cond
     ((>= p gptel-p-success-threshold)
      (cons 'proceed p))
     ((>= p 0.3)
      (cons 'caution p))
     (t
      (cons 'defer p)))))

(defun gptel--generate-help-request (task-context unknown-aspects)
  "Generate help request for UNKNOWN-ASPECTS in TASK-CONTEXT."
  (format "## Help Request\n\nTask: %s\nUnknown aspects:\n%s\n\nP(success): %.2f\n\nPlease clarify:\n"
    (gptel--summarize-task task-context)
    (string-join (mapcar (lambda (a) (format "- %s" a)) unknown-aspects) "\n")
    (gptel--compute-p-success task-context)))
```

---

## 3. Tier 3: Evaluation & Metrics Patterns

### 3.1 Trajectory-Aware Metrics

**Source:** [NVIDIA AI Agent Evaluation Guide](https://developer.nvidia.com/blog/mastering-agentic-techniques-ai-agent-evaluation/)  
**Impact:** HIGH | **Difficulty:** MEDIUM

**Metrics Table:**

| Metric | What It Measures | Formula |
|--------|-------------------|---------|
| **Task Success Rate (TSR)** | Intent resolution within constraints | successes / total_tasks |
| **Tool Call Accuracy** | Precision in function calling | correct_calls / total_calls |
| **Trajectory Efficiency** | Steps/tokens per success | (steps × 10 + tokens) / successes |
| **Reasoning Soundness** | Trace quality, evidence usage | valid_traces / total_traces |

**Implementation:**
```elisp
(defvar gptel-metrics-db (expand-file-name ".gptel/metrics.db" user-emacs-directory))

(defun gptel--metrics-init ()
  "Initialize metrics database."
  (require 'sqlite)
  (make-directory (file-name-directory gptel-metrics-db) t)
  (sqlite-execute (sqlite-open gptel-metrics-db)
    "CREATE TABLE IF NOT EXISTS trajectories (
       id INTEGER PRIMARY KEY AUTOINCREMENT,
       experiment_id TEXT NOT NULL,
       task TEXT NOT NULL,
       success INTEGER NOT NULL,
       steps INTEGER NOT NULL,
       tokens INTEGER NOT NULL,
       duration_ms INTEGER NOT NULL,
       tool_calls TEXT NOT NULL,
       timestamp REAL NOT NULL
     )"))

(defun gptel--log-trajectory (experiment-id task steps tokens duration-ms tool-calls success)
  "Log complete trajectory for metrics analysis."
  (sqlite-execute (sqlite-open gptel-metrics-db)
    (format "INSERT INTO trajectories 
             (experiment_id, task, success, steps, tokens, duration_ms, tool_calls, timestamp)
             VALUES ('%s', '%s', %d, %d, %d, %d, '%s', %.3f)"
      experiment-id (sqlite-escape-string task) (if success 1 0)
      steps tokens duration-ms
      (sqlite-escape-string (prin1-to-string tool-calls))
      (float-time (current-time)))))

(defun gptel--compute-metrics (&optional experiment-id)
  "Compute trajectory-aware metrics for EXPERIMENT-ID or all experiments."
  (let ((query (if experiment-id
                   (format "WHERE experiment_id = '%s'" experiment-id)
                 "")))
    (sqlite-select (sqlite-open gptel-metrics-db)
      (format "SELECT 
                COUNT(*) as total_tasks,
                SUM(success) as successes,
                SUM(steps) as total_steps,
                SUM(tokens) as total_tokens,
                AVG(steps) as avg_steps,
                AVG(tokens) as avg_tokens
               FROM trajectories %s" query)
      :columns-as 'alist)))

(defun gptel--compute-tsr (&optional experiment-id)
  "Compute Task Success Rate for EXPERIMENT-ID."
  (let ((metrics (gptel--compute-metrics experiment-id)))
    (when metrics
      (let ((total (alist-get 'total_tasks (car metrics)))
            (successes (alist-get 'successes (car metrics))))
        (when (and total (> total 0))
          (/ (float successes) total))))))

(defun gptel--compute-trajectory-efficiency (&optional experiment-id)
  "Compute Trajectory Efficiency = (steps × 10 + tokens) / successes."
  (let ((metrics (gptel--compute-metrics experiment-id)))
    (when metrics
      (let ((total-steps (alist-get 'total_steps (car metrics)))
            (total-tokens (alist-get 'total_tokens (car metrics)))
            (successes (alist-get 'successes (car metrics))))
        (when (and successes (> successes 0))
          (/ (+ (* total-steps 10) total-tokens) (float successes)))))))

(defun gptel--compute-tool-call-accuracy ()
  "Compute Tool Call Accuracy from logged trajectories."
  (sqlite-select (sqlite-open gptel-metrics-db)
    "SELECT 
       SUM(json_each.value->>'correct') as correct_calls,
       COUNT(*) as total_calls
     FROM trajectories,
     json_each(tool_calls)"
    :columns-as 'alist))
```

---

### 3.2 Error Recovery Patterns

**Source:** [AI Agent Error Recovery Patterns](https://aiagentsblog.com/blog/agent-error-recovery-patterns/)  
**Impact:** MEDIUM | **Difficulty:** LOW

**Five Production Patterns:**

```elisp
;; Pattern 1: Exponential Backoff with Jitter
(defvar gptel-retry-delays '(1 2 4 8 16 32) "Base delays in seconds")

(defun gptel--retry-with-backoff (fn max-retries &optional jitter)
  "Retry FN with exponential backoff, optionally adding JITTER."
  (let ((attempt 0)
        (delays gptel-retry-delays))
    (while (< attempt max-retries)
      (condition-case err
          (return (funcall fn))
        (error
         (when (< attempt (1- max-retries))
           (let* ((base-delay (nth (min attempt (1- (length delays))) delays))
                  (jitter-ms (if jitter (random jitter) 0))
                  (total-delay (+ base-delay (/ jitter-ms 1000.0))))
             (message "Retry %d/%d after %.1fs: %s" 
                      (1+ attempt) max-retries total-delay (cadr err))
             (sleep-for total-delay))))
         (setq attempt (1+ attempt))))
    (signal 'gptel-max-retries-exceeded (list max-retries))))

;; Pattern 4: Fallback Chains
(defvar gptel-provider-chain '(openai anthropic ollama) "Provider fallback chain")

(defun gptel--execute-with-fallback (prompt)
  "Execute PROMPT with provider fallback chain."
  (let ((errors '())
        (providers gptel-provider-chain))
    (while providers
      (let ((provider (pop providers)))
        (condition-case err
            (progn
              (gptel--ensure-circuit-closed provider)
              (let ((result (gptel--call-provider provider prompt)))
                (gptel--record-success provider)
                (return result)))
          (error
           (push (cons provider (cadr err)) errors)
           (gptel--record-failure provider)
           (gptel--open-circuit provider)))))
    (signal 'gptel-all-providers-failed errors)))

;; Pattern 5: Escalation Queues
(defvar gptel-escalation-queue (expand-file-name ".gptel/escalations/" user-emacs-directory))

(defun gptel--escalate-to-human (task context error)
  "Escalate failed TASK to human review."
  (make-directory gptel-escalation-queue t)
  (let ((esc-id (format-time-string "%Y%m%d-%H%M%S"))
        (esc-file (expand-file-name (format "esc-%s.eld" esc-id) gptel-escalation-queue)))
    (with-temp-file esc-file
      (pp `(,esc-id ,task ,context ,error ,(current-time)) (current-buffer)))
    (message "ESCALATED: Task queued for human review at %s" esc-file)
    esc-id))
```

---

## 4. Orchestration Spectrum

**Source:** [Azure AI Agent Orchestration Patterns](https://learn.microsoft.com/en-us/azure/architecture/ai-ml/guide/ai-agent-design-patterns)

**Complexity Levels:**

| Level | Pattern | Use When | gptel Status |
|-------|---------|----------|--------------|
| 1 | Direct model call | Single-step tasks | ✓ Implemented |
| 2 | Single agent + tools | Varied queries, dynamic tool use | ✓ Implemented |
| 3 | Sequential | Linear dependencies, progressive refinement | 🔄 In Progress |
| 4 | Concurrent | Independent perspectives, fan-out/fan-in | 🔜 Planned |
| 5 | Hierarchical | Master-slave coordination, complex delegation | 🔜 Planned |

**Implementation for Level 3 (Sequential):**
```elisp
(defun gptel--sequential-workflow (stages task)
  "Execute TASK through sequential STAGES.
STAGES is a list of (name . fn) where fn receives previous stage output."
  (let ((context task)
        (stage-results '()))
    (while stages
      (let* ((stage (pop stages))
             (name (car stage))
             (fn (cdr stage))
             (start-time (current-time)))
        (message "Stage: %s" name)
        (condition-case err
            (let ((result (funcall fn context)))
              (push (list name result :duration (float-time (time-subtract (current-time) start-time)))
                    stage-results)
              (setq context result))
          (error
           (push (list name nil :error (cadr err) :duration (float-time (time-subtract (current-time) start-time)))
                 stage-results)
           (return (cons nil stage-results))))))
    (cons t (nreverse stage-results))))

;; Example sequential workflow
(defun gptel-research-workflow (query)
  "Research QUERY through sequential stages."
  (gptel--sequential-workflow
   '((research . gptel--stage-research)
     (analyze . gptel--stage-analyze)
     (synthesize . gptel--stage-synthesize)
     (verify . gptel--stage-verify)
     (format . gptel--stage-format))
   query))
```

---

## 5. Self-Evolution Directive Implementation

**From:** 2026-05-25 research (0% retention rate indicates critical focus needed)

**Directive:** Focus on highest-failure modules. Apply nil-safety patterns and validation guards.

### 5.1 Target Modules by Failure Risk

| Module | Lines | Priority | Focus |
|--------|-------|----------|-------|
| `gptel-auto-workflow-evolution.el` | 5822 | CRITICAL | Nil-safety, validation guards |
| `gptel-auto-workflow-strategic.el` | 2698 | HIGH | Nil-safety, validation guards |
| `gptel-tools-agent-prompt-build.el` | 2431 | HIGH | Nil-safety, validation guards |
| `gptel-auto-workflow-research-benchmark.el` | 1742 | MEDIUM | Nil-safety |

### 5.2 Nil-Safety Pattern Library

```elisp
;; Macro for safe access with defaults
(defmacro gptel-safely (expr &optional default)
  "Safely evaluate EXPR, returning DEFAULT (or nil) on error."
  (declare (debug t))
  `(condition-case-unless-debug nil
       ,expr
     (error ,default)))

;; Safe alist access
(defun gptel-alist-get-safe (key alist &optional default)
  "Safe version of alist-get with DEFAULT for missing keys."
  (gptel-safely (alist-get key alist) default))

;; Safe plist access
(defun gptel-plist-get-safe (key plist &optional default)
  "Safe version of plist-get with DEFAULT for missing keys."
  (gptel-safely (plist-get plist key) default))

;; Safe function call with arity checking
(defun gptel-call-safe (fn &rest args)
  "Call FN with ARGS, returning nil on any error or wrong arity."
  (condition-case-unless-debug nil
      (apply fn args)
    (wrong-number-of-arguments nil)
    (wrong-number-of-args nil)
    (error nil)))

;; Validation guards macro
(defmacro gptel-guard (condition message &rest body)
  "Guard BODY execution with CONDITION, raise error with MESSAGE if violated."
  (declare (debug t))
  `(if ,condition
       (progn ,@body)
     (error "Guard failed: %s" ,message)))

;; Guard examples for module authors
(defun gptel-validate-experiment-row (row)
  "Validate experiment ROW has required fields."
  (gptel-guard (listp row) "Experiment row must be a list"
    (gptel-guard (stringp (car row)) "First field must be experiment-id string"
      (gptel-guard (plistp (cdr row)) "Remaining fields must be plist"
        (gptel-guard (gptel-safely (plist-get (cdr row) :timestamp))
                     "Missing required :timestamp field"
          t)))))
```

---

## 6. Git Activity Analysis

**Last 30 commits to lisp/modules/:**

| Metric | Value | Interpretation |
|--------|-------|----------------|
| Bug fixes | 8 | Active stabilization |
| Feature commits | 0 | Feature freeze mode |
| Ratio | 100% stabilization | Current phase = polish & harden |

**Implication:** Research should focus on resilience patterns, not feature discovery. Apply existing patterns more robustly.

---

## 7. Cross-References

- **Circuit Breaker**: See [[research-error-recovery]] for provider fallback implementation
- **Checkpoint/Restore**: See [[research-persistence]] for experiment state persistence
- **FTS5 Search**: See [[research-memory]] for session continuity implementation
- **Nil-Safety**: See [[elisp-patterns-nil-safety]] for defensive programming
- **Metrics**: See [[benchmark-trajectory-metrics]] for TSR tracking
- **Verification**: See [[agent-verification-gates]] for self-check implementation

---

## 8. Related Topics

- [[agent-architecture-patterns]]
- [[self-evolution-system]]
- [[benchmark-metrics]]
- [[memory-systems]]
- [[error-recovery-patterns]]
- [[context-compression]]
- [[provider-fallback-chains]]
- [[validation-guard-patterns]]
- [[sqlite-tool-logging]]
- [[hybrid-search-rag]]

---

## 9. Meta-Learning

**Research quality measured by downstream experiment success.**

Key learnings from research sessions:

1. **Preserve the feedback loop**: Every experiment row must include a non-None research hash so AutoTTS can link outcomes back to the research trace.

2. **Treat missing research as pipeline defect**: Missing research files are not successful empty research runs—they indicate daemon orchestration issues.

3. **Prefer structured outputs**: Machine-parseable research with source, technique, apply-to-us, and verification fields has higher retention than prose.

4. **Guard daemon boundaries**: If a researcher daemon disappears after being observed, fail fast and fall back instead of waiting until global timeout.

5. **Prioritize observability**: Changes that make self-evolution observable through results.tsv metadata, research traces, and controller decisions have higher impact.

---

*Generated: 2026-05-25*  
*Source: Research sessions 2026-05-20 through 2026-05-25*  
*Hash: e438c2269d429af9e2c655b676710024094299f6*