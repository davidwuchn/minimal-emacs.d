<!--
Synthesis verification:
- Confidence: 24%
- Sources: 5 memories
- Warnings: No code examples or concrete references, Content does not mention topic 'research-research-persisted'
- Auto-approved: yes (flagged)
--->

---
title: Research Patterns & Persistence Strategies
status: active
category: knowledge
tags: [agent-architecture, error-recovery, circuit-breaker, checkpoint-restore, context-reduction, memory-systems, workflow-design]
---

# Research Patterns & Persistence Strategies

## Overview

This knowledge page synthesizes research findings from multiple sources into actionable patterns for the Emacs AI agent system. The patterns are organized by complexity and impact, with concrete implementation guidance for each.

**Research Quality Principle**: Research quality is measured by downstream experiment success. Every experiment row must include a non-None research hash so outcomes link back to the research trace.

## Pattern Tier 1: High-Impact, Directly Applicable

### 1. Circuit Breaker with Checkpoint/Restore

**Source**: [efrit](https://github.com/davidwuchn/efrit)

**Problem**: Cascading failures can freeze the entire agent system when a provider becomes unreliable.

**Solution**: Implement a three-state circuit breaker that monitors failure rates and transitions through CLOSED→OPEN→HALF-OPEN states. Store state snapshots before risky operations for automatic recovery.

#### Implementation

```elisp
(defcustom gptel-circuit-breaker-config
  '((failure-threshold . 5)
    (recovery-timeout . 60)
    (half-open-max-calls . 3))
  "Circuit breaker configuration per provider."
  :type '(alist :key-type symbol :value-type number))

(defvar gptel-circuit-breaker-state
  (make-hash-table :test 'equal)
  "Hash table storing (failure-count success-count last-failure provider) triples.")

(defun gptel-circuit-breaker--record (provider success)
  "Record SUCCESS for PROVIDER in circuit breaker state."
  (let* ((state (gethash provider gptel-circuit-breaker-state
                         '(0 0 nil)))
         (failures (car state))
         (successes (cadr state))
         (last-failure (caddr state)))
    (puthash provider
             (if success
                 (list failures (1+ successes) last-failure)
               (list (1+ failures) successes (current-time)))
             gptel-circuit-breaker-state)))

(defun gptel-circuit-breaker--should-trip (provider)
  "Return t if circuit for PROVIDER should trip to OPEN."
  (let* ((state (gethash provider gptel-circuit-breaker-state '(0 0 nil)))
         (failures (car state))
         (threshold (alist-get 'failure-threshold
                               gptel-circuit-breaker-config)))
    (>= failures threshold)))

(defun gptel-circuit-breaker--state (provider)
  "Return circuit state for PROVIDER: 'closed, 'open, or 'half-open."
  (let* ((state (gethash provider gptel-circuit-breaker-state '(0 0 nil)))
         (last-failure (caddr state)))
    (cond
     ((not last-failure) 'closed)
     ((>= (float-time (time-since last-failure))
          (alist-get 'recovery-timeout gptel-circuit-breaker-config))
      'half-open)
     ((gptel-circuit-breaker--should-trip provider) 'open)
     (t 'closed))))
```

#### Checkpoint System

```elisp
(defcustom gptel-checkpoint-dir
  (expand-file-name ".gptel/checkpoints/" user-emacs-directory)
  "Directory for checkpoint storage.")

(defun gptel-checkpoint-save (session-id data)
  "Save checkpoint for SESSION-ID with DATA."
  (let ((checkpoint-file (expand-file-name
                          (format "%s.el" session-id)
                          gptel-checkpoint-dir)))
    (make-directory gptel-checkpoint-dir t)
    (with-temp-file checkpoint-file
      (prin1 `(checkpoint
               :session-id ,session-id
               :timestamp ,(current-time)
               :data ,data)
             (current-buffer)))))

(defun gptel-checkpoint-restore (session-id)
  "Restore checkpoint data for SESSION-ID."
  (let ((checkpoint-file (expand-file-name
                          (format "%s.el" session-id)
                          gptel-checkpoint-dir)))
    (when (file-exists-p checkpoint-file)
      (with-temp-buffer
        (insert-file-contents checkpoint-file)
        (goto-char (point-min))
        (let ((checkpoint (read (current-buffer))))
          (plist-get (cddr checkpoint) :data))))))
```

**When to Use**: Every API call, file modification operation, or external command execution.

**Cross-references**: See [Error Recovery Patterns](#5-error-recovery-patterns) for fallback chains.

---

### 2. Tool Receipts for Audit Trail

**Source**: [efrit](https://github.com/davidwuchn/efrit) (35+ tools with security controls)

**Problem**: Need complete traceability of agent actions for compliance, debugging, and learning.

**Solution**: Every tool execution generates structured metadata recorded in SQLite for replay and audit.

#### Implementation

```elisp
(require 'sqlite)

(defcustom gptel-tool-log-db
  (expand-file-name ".gptel/tool-log.db" user-emacs-directory)
  "SQLite database for tool execution logs.")

(defun gptel-tool-log--init ()
  "Initialize tool log database."
  (sqlite-open gptel-tool-log-db)
  (sqlite-execute gptel-tool-log-db
    (format "CREATE TABLE IF NOT EXISTS tool_receipts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      tool_name TEXT NOT NULL,
      input_hash TEXT NOT NULL,
      output_hash TEXT,
      timestamp REAL NOT NULL,
      duration_ms INTEGER,
      success INTEGER NOT NULL,
      session_id TEXT,
      error_message TEXT
    )"))
  (sqlite-execute gptel-tool-log-db
    "CREATE INDEX IF NOT EXISTS idx_tool_name ON tool_receipts(tool_name)")
  (sqlite-execute gptel-tool-log-db
    "CREATE INDEX IF NOT EXISTS idx_timestamp ON tool_receipts(timestamp)"))

(defun gptel-tool-log--receipt (tool-name input output duration-ms success
                                 &optional session-id error-message)
  "Record a tool execution receipt."
  (let* ((input-hash (secure-hash 'sha256 (prin1-to-string input)))
         (output-hash (when output
                        (secure-hash 'sha256 (prin1-to-string output))))
         (timestamp (float-time)))
    (sqlite-execute gptel-tool-log-db
      "INSERT INTO tool_receipts
       (tool_name, input_hash, output_hash, timestamp, duration_ms,
        success, session_id, error_message)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
      (vector tool-name input-hash output-hash timestamp
              duration-ms (if success 1 0) session-id error-message))))

(defun gptel-tool-log--query (tool-name &optional limit)
  "Query receipts for TOOL-NAME, limited to LIMIT results."
  (sqlite-select gptel-tool-log-db
    (format "SELECT * FROM tool_receipts
             WHERE tool_name = ? ORDER BY timestamp DESC LIMIT ?")
    (vector tool-name (or limit 100))))
```

#### Shell Command Security Patterns

```elisp
(defcustom gptel-shell-allowed-patterns
  '("git " "find " "grep " "ls " "cat ")
  "Allowed command patterns for shell execution.")

(defcustom gptel-shell-forbidden-patterns
  '("rm -rf /" "dd if=" "mkfs" ":(){ :|:& };:" "curl.*-o.*/etc/"
    "wget.*-O.*/etc/" "chmod 777" "ssh.*@.*\"")
  "Forbidden command patterns (regexps).")

(defun gptel-shell-validate (command)
  "Validate COMMAND against allowed/forbidden patterns.
Return (ok . reason) tuple."
  (let ((allowed nil)
        (forbidden nil))
    (dolist (pattern gptel-shell-allowed-patterns)
      (when (string-match-p (regexp-quote pattern) command)
        (setq allowed t)))
    (dolist (pattern gptel-shell-forbidden-patterns)
      (when (string-match-p pattern command)
        (push pattern forbidden)))
    (if forbidden
        (cons nil (format "Forbidden pattern matched: %s" (car forbidden)))
      (if (not allowed)
          (cons nil "No allowed pattern matched")
        (cons t "Command validated")))))
```

**Cross-references**: See [Trajectory-Aware Metrics](#4-trajectory-aware-metrics) for evaluation integration.

---

### 3. Mathematical Attention Magnets (Lambda Notation)

**Source**: [nucleus](https://github.com/davidwuchn/nucleus)

**Problem**: Verbose prompts waste context tokens and dilute the LLM's focus on key reasoning patterns.

**Solution**: Use Greek letters and mathematical symbols as compressed prompt preambles that prime formal reasoning.

#### Preamble Library

```elisp
(defvar gptel-nucleus-preambles
  '(("λ engage" .
     "λ engage(nucleus). [φ fractal euler tao π μ ∃ ∀] | [Δ λ Ω ∞/0 | ε/φ Σ/μ c/h] | OODA")
    ("λ formal" .
     "λ formal(mode). ∀ premises ⊢ conclusions. ¬∃ paradox. ✓ verification required.")
    ("λ iterative" .
     "λ iterative(REPL). observe → hypothesize → test → refine. cycle until stable.")
    ("λ explore" .
     "λ explore(search). breadth-first with pruning. track frontier, visited.")
    ("λ structured" .
     "λ structured(edn). {:phase :planning :actions [] :state {}}"))
  "Lambda notation preambles for different reasoning modes.")

(defun gptel-system-prompt--append-preamble (mode)
  "Append nucleus-style preamble for MODE to system prompt."
  (when-let ((preamble (alist-get mode gptel-nucleus-preambles)))
    (goto-char (point-max))
    (insert "\n\n" preamble "\n")))

;; EDN Statechart for Workflow States
(defvar gptel-workflow-statechart
  '(:state-machine
    :initial :idle
    :states
    (:idle {:enter (lambda () (message "Workflow idle"))
            :transitions
            ({:event :start :to :researching})})
    (:researching {:enter (lambda () (message "Researching"))
                   :transitions
                   ({:event :complete :to :planning}
                    {:event :fail :to :degraded})})
    (:planning {:enter (lambda () (message "Planning"))
                :transitions
                ({:event :approve :to :executing}
                 {:event :reject :to :idle}
                 {:event :fail :to :degraded})})
    (:executing {:enter (lambda () (message "Executing"))
                 :transitions
                 ({:event :complete :to :idle}
                  {:event :fail :to :degraded})})
    (:degraded {:enter (lambda () (message "Degraded mode"))
                :transitions
                ({:event :recover :to :idle}
                 {:event :escalate :to :blocked})})
    (:blocked {:enter (lambda () (message "Blocked - human intervention"))
               :transitions
               ({:event :resolve :to :idle})})))
```

**Cross-references**: See [EDN Statechart Workflow](#2-statechart-driven-workflow) for state machine implementation.

---

### 4. Think-in-Code Context Reduction

**Source**: [context-mode](https://github.com/davidwuchn/context-mode)

**Problem**: Dumping raw file reads (700KB+) via 47+ tool calls wastes context and makes the LLM a data processor instead of an agent.

**Solution**: Execute analysis scripts in isolated subprocesses that return only structured results.

#### Implementation

```elisp
(defcustom gptel-sandbox-execute-timeout 30
  "Timeout in seconds for sandboxed execution.")

(defun gptel-sandbox-execute (analysis-script &optional params)
  "Execute ANALYSIS-SCRIPT with PARAMS in isolated subprocess.
Returns only structured result, not raw output."
  (let* ((temp-script (make-temp-file "gptel-analysis-" nil ".el"))
         (temp-params (make-temp-file "gptel-params-" nil ".json"))
         (result-file (make-temp-file "gptel-result-" nil ".json")))
    (unwind-protect
        (progn
          ;; Write analysis script
          (with-temp-file temp-script
            (insert analysis-script))
          ;; Write parameters
          (with-temp-file temp-params
            (insert (json-encode params)))
          ;; Execute with timeout
          (let ((exit-code
                 (call-process "timeout"
                               nil
                               (list result-file (format "%s.stderr" temp-script))
                               nil
                               (number-to-string gptel-sandbox-execute-timeout)
                               "emacs" "--batch"
                               "-l" temp-script
                               "--eval" (format "(json-encode-params '%s)"
                                                (json-encode params))
                               "--eval" (format "(with-temp-file \"%s\" (prin1 result))"
                                                result-file))))
            (if (and (file-exists-p result-file)
                     (= exit-code 0))
                (with-temp-buffer
                  (insert-file-contents result-file)
                  (goto-char (point-min))
                  (json-parse-buffer :object-type 'alist))
              (list :error t
                    :exit-code exit-code
                    :stderr (when (file-exists-p (format "%s.stderr" temp-script))
                               (with-temp-buffer
                                 (insert-file-contents (format "%s.stderr" temp-script))
                                 (buffer-string)))))))
      ;; Cleanup
      (dolist (f (list temp-script temp-params result-file))
        (when (and f (file-exists-p f))
          (delete-file f))))))

;; Example analysis script for project complexity
(defvar gptel-analysis-scripts
  '(("project-complexity" .
     "(defun analyze-project (params)
  (let* ((root (alist-get 'root params))
         (el-files (directory-files-recursively root \"\\\\.el$\"))
         (total-lines (apply '+ (mapcar (lambda (f)
                                          (with-temp-buffer
                                            (insert-file-contents f)
                                            (count-lines (point-min) (point-max))))
                                        el-files)))
         (deps (remove-duplicates
                (mapcan (lambda (f)
                          (when (string-match \"require '[a-z0-9-]+\" 
                                              (with-temp-buffer
                                                (insert-file-contents f)
                                                (buffer-string)))
                            (list (match-string 0 (buffer-string)))))
                        el-files)
                :test 'string=)))
    `(:file-count ,(length el-files)
      :total-lines ,total-lines
      :complexity-score ,(/ total-lines (length el-files))
      :dependencies ,deps)))
  (analyze-project (json-parse-buffer :object-type 'alist))"))
  "Registry of named analysis scripts for sandbox execution.")
```

**Context Reduction Example**:

| Approach | Raw Output | Effective Result |
|----------|------------|------------------|
| 47× Read() calls | 700KB | 700KB in context |
| Think-in-Code | 5KB script | 3.6KB result |
| **Reduction** | **98%** | — |

**Cross-references**: See [Session Continuity via FTS5](#5-session-continuity-via-fts5) for retrieval after compaction.

---

### 5. Session Continuity via FTS5

**Source**: [context-mode](https://github.com/davidwuchn/context-mode)

**Problem**: When context compacts, the agent loses history and must rebuild context from scratch.

**Solution**: Track every edit, git op, task, and error in SQLite with FTS5. On compaction, retrieve only relevant events via BM25 search.

#### Implementation

```elisp
(require 'sqlite)

(defcustom gptel-session-db
  (expand-file-name ".gptel/session.db" user-emacs-directory)
  "SQLite database for session continuity.")

(defun gptel-session--init ()
  "Initialize session database with FTS5 support."
  (sqlite-open gptel-session-db)
  (sqlite-execute gptel-session-db
    "CREATE TABLE IF NOT EXISTS session_events (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id TEXT NOT NULL,
      timestamp REAL NOT NULL,
      event_type TEXT NOT NULL,
      data TEXT NOT NULL,
      relevance_score REAL
    )")
  (sqlite-execute gptel-session-db
    "CREATE VIRTUAL TABLE IF NOT EXISTS session_events_fts
     USING fts5(session_id, event_type, data,
                content='session_events',
                content_rowid='id')")
  (sqlite-execute gptel-session-db
    "CREATE TRIGGER IF NOT EXISTS session_events_ai AFTER INSERT ON session_events
     BEGIN
       INSERT INTO session_events_fts(rowid, session_id, event_type, data)
       VALUES (new.id, new.session_id, new.event_type, new.data);
     END")
  (sqlite-execute gptel-session-db
    "CREATE INDEX IF NOT EXISTS idx_session_timestamp
     ON session_events(session_id, timestamp)"))

(defun gptel-session--track (session-id event-type data)
  "Track SESSION-ID EVENT-TYPE with DATA."
  (sqlite-execute gptel-session-db
    "INSERT INTO session_events (session_id, timestamp, event_type, data)
     VALUES (?, ?, ?, ?)"
    (vector session-id (float-time) event-type (json-encode data))))

(defun gptel-session--compact-retrieve (session-id query &optional limit)
  "Retrieve relevant events from SESSION-ID matching QUERY after context compaction."
  (let* ((bm25-results
          (sqlite-select gptel-session-db
            (format "SELECT id, session_events.rowid, bm25(session_events_fts) as rank,
                            snippet(session_events_fts, 2, '<<', '>>', '...', %d) as snippet
                     FROM session_events_fts
                     WHERE session_events_fts MATCH ?
                     ORDER BY rank
                     LIMIT ?")
            (vector query (or limit 20)))))
    (mapcar (lambda (row)
              (let ((event-id (car row)))
                (car (sqlite-select gptel-session-db
                      "SELECT * FROM session_events WHERE id = ?"
                      (vector event-id)))))
            bm25-results)))

;; Event type definitions
(defvar gptel-session-event-types
  '(edit git task error tool-call checkpoint restore user-feedback)
  "Valid session event types.")
```

**Cross-references**: See [Hybrid Search Fusion](#8-hybrid-search-fusion) for advanced retrieval combining vector + BM25.

---

### 6. Feed-Forward Memory Protocol

**Source**: [mementum](https://github.com/davidwuchn/mementum)

**Problem**: Each agent session starts cold with no knowledge of previous experiments, strategies, or outcomes.

**Solution**: Implement three-tier memory storage (state/memories/knowledge) with human governance for synthesized insights.

#### Implementation

```elisp
(defcustom gptel-memory-dir
  (expand-file-name ".gptel/memory/" user-emacs-directory)
  "Directory for memory storage.")

(defvar gptel-memory--state-file
  (expand-file-name "state.md" gptel-memory-dir)
  "Current working memory state file.")

(defvar gptel-memory--memories-file
  (expand-file-name "memories.md" gptel-memory-dir)
  "Synthesized memories file (each <200 words).")

(defvar gptel-memory--knowledge-dir
  (expand-file-name "knowledge/" gptel-memory-dir)
  "Directory for synthesized knowledge pages.")

(defun gptel-memory--load-state ()
  "Load current working memory state."
  (when (file-exists-p gptel-memory--state-file)
    (with-temp-buffer
      (insert-file-contents gptel-memory--state-file)
      (buffer-string))))

(defun gptel-memory--save-state (state)
  "Save STATE to working memory."
  (make-directory gptel-memory-dir t)
  (with-temp-file gptel-memory--state-file
    (insert state)))

(defun gptel-memory--synthesize (proposed-knowledge)
  "Propose KNOWLEDGE for synthesis. Returns t if human approves.
Implements AI proposes → human approves → AI commits protocol."
  (let ((proposal-file (expand-file-name "pending-proposal.md"
                                         gptel-memory-dir)))
    (make-directory gptel-memory-dir t)
    (with-temp-file proposal-file
      (insert "# Proposed Knowledge\n\n")
      (insert proposed-knowledge)
      (insert "\n\n---\n*Awaiting human approval*"))
    (when (y-or-n-p "Approve this knowledge synthesis? ")
      (let ((approved-file (expand-file-name
                            (format "knowledge/%s.md"
                                    (format-time-string "%Y%m%d-%H%M%S"))
                            gptel-memory-dir)))
        (make-directory gptel-memory--knowledge-dir t)
        (rename-file proposal-file approved-file)
        t))))

(defun gptel-memory--search (query &optional limit)
  "Search all memory tiers for QUERY."
  (let ((results '()))
    ;; Search state
    (when (file-exists-p gptel-memory--state-file)
      (when (string-match-p query (gptel-memory--load-state))
        (push (cons 'state (gptel-memory--load-state)) results)))
    ;; Search memories
    (when (file-exists-p gptel-memory--memories-file)
      (when (string-match-p query
                            (with-temp-buffer
                              (insert-file-contents gptel-memory--memories-file)
                              (buffer-string)))
        (push (cons 'memories (with-temp-buffer
                                 (insert-file-contents gptel-memory--memories-file)
                                 (buffer-string)))
              results)))
    ;; Search knowledge pages
    (when (file-exists-p gptel-memory--knowledge-dir)
      (dolist (page (directory-files gptel-memory--knowledge-dir
                                      t "\\.md$"))
        (when (string-match-p query
                              (with-temp-buffer
                                (insert-file-contents page)
                                (buffer-string)))
          (push (cons 'knowledge (cons page
                                       (with-temp-buffer
                                         (insert-file-contents page)
                                         (buffer-string))))
                results))))
    results))
```

**Cross-references**: See [Self-Wiring Knowledge Graph](#9-self-wiring-knowledge-graph) for automated entity linking.

---

## Pattern Tier 2: Agent Architecture Patterns

### 7. Beads Ledger for Work Tracking

**Source**: [gastown](https://github.com/davidwuchn/gastown)

**Problem**: Work state is lost when agent crashes or restarts mid-experiment.

**Solution**: Persist work state as immutable beads (git commits) with typed metadata. Enables recovery and multi-agent coordination.

#### Implementation

```elisp
(defcustom gptel-worktree-base
  (expand-file-name ".gptel/worktrees/" user-emacs-directory)
  "Base directory for git worktrees per task.")

(defun gptel-work-bead (task-id status metadata)
  "Create an immutable bead (git commit) for TASK-ID with STATUS and METADATA.
Returns the commit hash."
  (let* ((worktree-dir (expand-file-name task-id gptel-worktree-base))
         (bead-file (expand-file-name ".bead" worktree-dir)))
    (make-directory worktree-dir t)
    ;; Initialize worktree as git repo if needed
    (unless (file-exists-p (expand-file-name ".git" worktree-dir))
      (shell-command (format "cd %s && git init && git commit --allow-empty -m 'init'"
                             worktree-dir)))
    ;; Write bead data
    (with-temp-file bead-file
      (prin1 `(bead
               :task-id ,task-id
               :status ,status
               :metadata ,metadata
               :timestamp ,(current-time))
             (current-buffer)))
    ;; Commit bead
    (shell-command (format "cd %s && git add .bead && git commit -m '%s'"
                           worktree-dir
                           (format "[bead] %s: %s" task-id status)))
    ;; Return commit hash
    (string-trim
     (shell-command-to-string
      (format "cd %s && git rev-parse HEAD" worktree-dir)))))

(defun gptel-work-bead--latest (task-id)
  "Retrieve the latest bead for TASK-ID."
  (let* ((worktree-dir (expand-file-name task-id gptel-worktree-base))
         (commit (string-trim
                  (shell-command-to-string
                   (format "cd %s && git log -1 --format=%%H" worktree-dir))))
         (bead-data
          (string-trim
           (shell-command-to-string
            (format "cd %s && git show %s:.bead" worktree-dir commit)))))
    (when (and commit (not (string-empty-p commit)))
      (with-temp-buffer
        (insert bead-data)
        (goto-char (point-min))
        (read (current-buffer))))))

(defun gptel-work-bead--history (task-id &optional limit)
  "Retrieve bead history for TASK-ID, limited to LIMIT entries."
  (let* ((worktree-dir (expand-file-name task-id gptel-worktree-base))
         (log-output
          (shell-command-to-string
           (format "cd %s && git log --oneline -%d"
                   worktree-dir (or limit 20)))))
    (mapcar (lambda (line)
              (when (string-match "^\\([a-f0-9]+\\) \\(.*\\)" line)
                (list :commit (match-string 1 line)
                      :message (match-string 2 line))))
            (split-string log-output "\n" t))))
```

**Cross-references**: See [Worktree Isolation](#10-worktree-isolation-for-agent-runs) for experiment run isolation.

---

### 8. Self-Verification Engine

**Source**: [genesis-agent](https://github.com/davidwuchn/genesis-agent)

**Problem**: LLM-generated code may have subtle bugs, syntax errors, or incorrect implementations that aren't caught until runtime.

**Solution**: Implement deterministic verification functions where "the LLM proposes — the machine verifies."

#### Verification Gates Implementation

```elisp
(defvar gptel-verification-gates
  '(syntax-check
    test-exit-code
    import-resolution
    file-existence
    output-schema
    security-check)
  "Available verification gate types.")

(defun gptel-verify-syntax (code)
  "Verify CODE has valid Emacs Lisp syntax."
  (condition-case err
      (progn
        (read code)
        (list :passed t :message "Syntax valid"))
    (error
     (list :passed nil
           :message (format "Syntax error: %s" (error-message-string err))))))

(defun gptel-verify-test-exit-code (command expected-code)
  "Verify COMMAND exits with EXPECTED-CODE."
  (let ((exit-code
         (shell-command
          (format "%s > /dev/null 2>&1; echo $?" command))))
    (list :passed (= exit-code expected-code)
          :message (format "Exit code: %d (expected: %d)"
                          exit-code expected-code))))

(defun gptel-verify-imports (file-path)
  "Verify all required imports in FILE-PATH are resolvable."
  (with-temp-buffer
    (insert-file-contents file-path)
    (let ((missing '())
          (require-forms (when (string-match "(\\(require\\|load\\)\\s-+'\\([^)]+\\)"
                                            (buffer-string))
                           (match-string 2 (buffer-string)))))
      (dolist (lib require-forms)
        (unless (locate-library (symbol-name lib))
          (push lib missing)))
      (list :passed (null missing)
            :message (if missing
                         (format "Missing libraries: %s" missing)
                       "All imports resolved")))))

(defun gptel-verify-output-schema (output expected-keys)
  "Verify OUTPUT matches EXPECTED-KEYS schema."
  (let* ((parsed (condition-case nil
                     (json-parse-string output :object-type 'plist)
                   (error nil)))
         (missing (set-difference expected-keys (if parsed
                                                     (mapcar 'car parsed)
                                                   '()))))
    (list :passed (null missing)
          :message (if missing
                       (format "Missing keys: %s" missing)
                     "Schema valid"))))

(defun gptel-verify-p (task-type result)
  "Calculate P(success) confidence score based on VERIFICATION-RESULTS."
  (let* ((gates (alist-get task-type gptel-verification-gates))
         (passed (cl-count-if (lambda (r) (plist-get r :passed))
                              result))
         (total (length result)))
    (if (eq total 0)
        0.5  ; No data, neutral confidence
      (/ (float passed) total))))
```

**Cross-references**: See [Error Recovery Patterns](#5-error-recovery-patterns) for escalation on verification failure.

---

### 9. Three-Tier Watchdog Architecture

**Source**: [gastown](https://github.com/davidwuchn/gastown)

**Problem**: Lifecycle management is mixed with execution logic, making it hard to detect and recover from stalls.

**Solution**: Separate watchdog into three tiers — Witness (session lifecycle), Deacon (background patrol), Dogs (dispatched workers).

#### Implementation

```elisp
(defvar gptel-watchdog--witness-active nil
  "Flag indicating witness is monitoring.")
(defvar gptel-watchdog--deacon-timer nil
  "Timer for deacon background checks.")
(defvar gptel-watchdog--dogs '()
  "List of dispatched cleanup/error recovery tasks.")

(defun gptel-watchdog--witness-start ()
  "Start witness monitoring for session lifecycle."
  (setq gptel-watchdog--witness-active t)
  (add-hook 'kill-emacs-hook #'gptel-watchdog--witness-cleanup))

(defun gptel-watchdog--witness-cleanup ()
  "Witness cleanup on session end."
  (when gptel-watchdog--witness-active
    (gptel-session--track (gptel-session-current-id)
                         'session-end
                         `(:timestamp ,(float-time)
                           :reason "emacs-exit"))))

(defun gptel-watchdog--deacon-start (interval-seconds)
  "Start deacon background patrol every INTERVAL-SECONDS."
  (setq gptel-watchdog--deacon-timer
        (run-at-time interval-seconds interval-seconds
                     #'gptel-watchdog--deacon-patrol)))

(defun gptel-watchdog--deacon-patrol ()
  "Deacon: continuous background health checks."
  (let ((health (gptel-workflow--health-check)))
    (when (plist-get health :stalled-workflows)
      (gptel-watchdog--dispatch-dog
       'stall-recovery
       (plist-get health :stalled-workflows)))
    (when (plist-get health :missed-checkpoints)
      (gptel-watchdog--dispatch-dog
       'checkpoint-recovery
       (plist-get health :missed-checkpoints)))))

(defun gptel-watchdog--dispatch-dog (dog-type payload)
  "Dispatch a dog worker for DOG-TYPE with PAYLOAD."
  (push (list :type dog-type
              :payload payload
              :dispatched-at (current-time))
        gptel-watchdog--dogs)
  (pcase dog-type
    ('stall-recovery
     (gptel-workflow--recover-stalled payload))
    ('checkpoint-recovery
     (gptel-checkpoint-restore payload))))

(defun gptel-watchdog--dog-complete (dog-id)
  "Mark DOG-ID as complete."
  (setq gptel-watchdog--dogs
        (cl-remove-if (lambda (d) (eq (car d) dog-id))
                      gptel-watchdog--dogs)))
```

**Cross-references**: See [Circuit Breaker](#1-circuit-breaker-with-checkpointrestore) for integration with failure monitoring.

---

## Pattern Tier 3: External Research Patterns

### 10. Orchestration Spectrum

**Source**: [Azure AI Agent Orchestration Patterns](https://learn.microsoft.com/en-us/azure/architecture/ai-ml/guide/ai-ml/guide/ai-agent-design-patterns)

**Problem**: The system uses a one-size-fits-all approach to agent orchestration.

**Solution**: Implement explicit orchestration level selection based on task requirements.

#### Orchestration Levels

| Level | Name | Use When | Implementation |
|-------|------|----------|----------------|
| 1 | Direct Call | Single-step tasks, prompt engineering suffices | `gptel-direct-call` |
| 2 | Single Agent + Tools | Varied queries, dynamic tool use | `gptel-agent-execute` |
| 3 | Sequential | Linear dependencies, progressive refinement | `gptel-sequential-pipeline` |
| 4 | Concurrent | Independent perspectives, fan-out/fan-in | `gptel-concurrent-map` |
| 5 | Hierarchical | Master-slave coordination, complex delegation | `gptel-hierarchical-delegate` |

#### Implementation

```elisp
(defcustom gptel-orchestration-default 'sequential
  "Default orchestration level."
  :type '(choice (const :tag "Direct" direct)
                 (const :tag "Agent" agent)
                 (const :tag "Sequential" sequential)
                 (const :tag "Concurrent" concurrent)
                 (const :tag "Hierarchical" hierarchical)))

(defun gptel-orchestration-select (task)
  "Select appropriate orchestration level for TASK."
  (let* ((complexity (plist-get task :complexity))
         (dependencies (plist-get task :dependencies))
         (parallelizable (plist-get task :parallelizable)))
    (cond
     ((and (eq complexity 'simple)
           (null dependencies))
      'direct)
     ((and (eq complexity 'medium)
           (null dependencies)
           parallelizable)
      'concurrent)
     ((and (null dependencies)
           (not parallelizable))
      'agent)
     ((and dependencies
           (not parallelizable))
      'sequential)
     (t 'hierarchical))))

(defun gptel-sequential-pipeline (stages)
  "Execute STAGES sequentially, passing output to next stage."
  (let ((result nil))
    (dolist (stage stages)
      (let* ((stage-fn (plist-get stage :function))
             (stage-input (plist-get stage :input))
             (stage-params (or (plist-get stage :params) result)))
        (setq result (funcall stage-fn stage-params stage-input))))
    result))

(defun gptel-concurrent-map (tasks concurrency-limit)
  "Execute TASKS concurrently with CONCURRENCY-LIMIT parallel workers."
  (let* ((semaphore (make-semaphore concurrency-limit))
         (results (list))
         (mutex (make-mutex)))
    (dolist (task tasks)
      (semaphore-wait semaphore)
      (make-thread
       (lambda ()
         (unwind-protect
             (let ((result (funcall (plist-get task :function)
                                    (plist-get task :params))))
               (mutex-lock mutex)
               (push result results)
               (mutex-unlock mutex))
           (semaphore-signal semaphore)))))
    ;; Wait for completion
    (dotimes (_ concurrency-limit)
      (semaphore-wait semaphore))
    results))
```

---

### 11. Trajectory-Aware Metrics

**Source**: [NVIDIA AI Agent Evaluation Guide](https://developer.nvidia.com/blog/mastering-agentic-techniques-ai-agent-evaluation/)

**Problem**: Evaluation focuses only on final answers, ignoring the quality of the reasoning process.

**Solution**: Log complete trajectories and evaluate process metrics alongside outcome metrics.

#### Metrics Implementation

| Metric | Formula | Target |
|--------|---------|--------|
| **Task Success Rate (TSR)** | successes / total | > 0.85 |
| **Tool Call Accuracy** | correct_calls / total_calls | > 0.90 |
| **Trajectory Efficiency** | 1 / (steps × tokens_per_success) | maximize |
| **Reasoning Soundness** | valid_reasoning_steps / total_steps | > 0.80 |

```elisp
(defcustom gptel-metrics-db
  (expand-file-name ".gptel/metrics.db" user-emacs-directory)
  "SQLite database for trajectory metrics.")

(defun gptel-metrics--init ()
  "Initialize metrics database."
  (sqlite-open gptel-metrics-db)
  (sqlite-execute gptel-metrics-db
    "CREATE TABLE IF NOT EXISTS trajectories (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      experiment_id TEXT,
      task_type TEXT,
      started_at REAL,
      completed_at REAL,
      success INTEGER,
      total_steps INTEGER,
      total_tokens INTEGER,
      trajectory_json TEXT
    )")
  (sqlite-execute gptel-metrics-db
    "CREATE TABLE IF NOT EXISTS tool_calls (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      trajectory_id INTEGER,
      step_index INTEGER,
      tool_name TEXT,
      correct INTEGER,
      FOREIGN KEY (trajectory_id) REFERENCES trajectories(id)
    )"))

(defun gptel-metrics--record-trajectory (experiment-id task-type steps tokens success-p)
  "Record a trajectory with STEPS, TOKENS, and SUCCESS-P for EXPERIMENT-ID."
  (sqlite-execute gptel-metrics-db
    "INSERT INTO trajectories
     (experiment_id, task_type, started_at, completed_at, success,
      total_steps, total_tokens, trajectory_json)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
    (vector experiment-id
            task-type
            (plist-get steps :started-at)
            (float-time)
            (if success-p 1 0)
            (length (plist-get steps :actions))
            tokens
            (json-encode steps))))

(defun gptel-metrics--tsr (&optional task-type limit)
  "Calculate Task Success Rate for TASK-TYPE."
  (let* ((query (if task-type
                    "SELECT COUNT(*) as total,
                            SUM(success) as successes
                     FROM trajectories WHERE task_type = ?"
                  "SELECT COUNT(*) as total, SUM(success) as successes
                   FROM trajectories"))
         (result (if task-type
                     (sqlite-select gptel-metrics-db query (vector task-type))
                   (sqlite-select gptel-metrics-db query))))
    (when result
      (let ((total (caar result))
            (successes (cadar result)))
        (if (and total (> total 0))
            (/ (float successes) total)
          0)))))

(defun gptel-metrics--trajectory-efficiency (&optional task-type)
  "Calculate Trajectory Efficiency (1 / (steps × tokens_per_success))."
  (let* ((result (sqlite-select gptel-metrics-db
                (format "SELECT AVG(total_steps), AVG(total_tokens)
                         FROM trajectories %s"
                        (if task-type "WHERE task_type = ?" ""))
                (if task-type (vector task-type) nil))))
    (when result
      (let ((avg-steps (caar result))
            (avg-tokens (cadar result)))
        (if (and avg-steps avg-tokens (> avg-steps 0))
            (/ 1.0 (* avg-steps avg-tokens))
          0)))))
```

---

### 12. Error Recovery Patterns

**Source**: [AI Agent Error Recovery Patterns](https://aiagentsblog.com/blog/agent-error-recovery-patterns/)

Five production-ready error recovery patterns for resilient agent systems.

#### Pattern 1: Exponential Backoff with Jitter

```elisp
(defun gptel-retry--backoff (attempt base-delay max-delay)
  "Calculate exponential backoff delay for ATTEMPT with BASE-DELAY and MAX-DELAY.
Includes jitter to prevent thundering herd."
  (let* ((exp-delay (* base-delay (expt 2 attempt)))
         (jitter (* exp-delay (random 0.3)))  ; 0-30% jitter
         (total (+ exp-delay jitter)))
    (min total max-delay)))

(defun gptel-retry-with-backoff (fn max-attempts base-delay max-delay)
  "Retry FN up to MAX-ATTEMPTS with exponential backoff."
  (let ((attempt 0))
    (while (< attempt max-attempts)
      (let ((result (funcall fn)))
        (if (plist-get result :success)
            (return result)
          (when (< attempt (1- max-attempts))
            (sleep-for (gptel-retry--backoff attempt base-delay max-delay)))
          (setq attempt (1+ attempt)))))
    (list :success nil :error "Max retry attempts exceeded")))
```

#### Pattern 2: Fallback Chains

```elisp
(defcustom gptel-provider-fallback-chain
  '(openai anthropic ollama)
  "Fallback chain for provider failures.")

(defun gptel-execute-with-fallback (prompt)
  "Execute PROMPT with provider fallback chain."
  (let ((providers gptel-provider-fallback-chain)
        (last-error nil))
    (dolist (provider providers)
      (condition-case err
          (let ((result (funcall (intern (format "gptel-%s-execute" provider))
                                 prompt)))
            (when (plist-get result :success)
              (return result)))
        (error
         (setq last-error err)
         (gptel-circuit-breaker--record provider nil)
         (when (eq (gptel-circuit-breaker--state provider) 'open)
           (message "Circuit open for %s, skipping" provider)))))
    (list :success nil
          :error (format "All providers failed: %s" last-error))))
```

#### Pattern 3: Escalation Queues

```elisp
(defcustom gptel-escalation-queue
  (expand-file-name ".gptel/escalation-queue/" user-emacs-directory)
  "Directory for escalation queue.")

(defun gptel-escalate (task priority reason)
  "Escalate TASK with PRIORITY and REASON to human review.
PRIORITY is one of: critical, high, medium, low."
  (make-directory gptel-escalation-queue t)
  (let ((esc-file (expand-file-name
                   (format "%s-%s.json"
                           (format-time-string "%Y%m%d-%H%M%S")
                           priority)
                   gptel-escalation-queue)))
    (with-temp-file esc-file
      (prin1 `(:task ,task
                    :priority ,priority
                    :reason ,reason
                    :timestamp ,(current-time)
                    :status pending)
             (current-buffer)))
    (message "Escalated task to %s queue: %s" priority esc-file)
    esc-file))

(defun gptel-escalation--list (&optional priority)
  "List escalations, optionally filtered by PRIORITY."
  (let* ((files (directory-files gptel-escalation-queue
                                  nil "\\.json$"))
         (filtered (if priority
                       (cl-remove-if-not
                        (lambda (f) (string-match-p priority f))
                        files)
                     files)))
    (mapcar (lambda (f)
              (with-temp-buffer
                (insert-file-contents (expand-file-name f
                                                        gptel-escalation-queue))
                (read (current-buffer))))
            filtered)))
```

---

### 13. Hybrid Search Fusion

**Source**: [gbrain](https://github.com/davidwuchn/gbrain)

**Problem**: Pure vector search misses exact keyword matches; pure BM25 ignores semantic similarity.

**Solution**: Combine vector embeddings + BM25 keyword search + reciprocal rank fusion for +31.4 P@5 lift.

#### Implementation

```elisp
(require 'seq)

(defcustom gptel-hybrid-search-vector-model "nomic-embed-text"
  "Embedding model for vector search.")
(defcustom gptel-hybrid-search-k 20
  "Number of results to retrieve per search method.")

(defun gptel-hybrid-search (query &optional sources)
  "Perform hybrid search over QUERY across SOURCES.
Combines vector + BM25 with reciprocal rank fusion."
  (let* ((vector-results (gptel-hybrid--vector-search query sources))
         (bm25-results (gptel-hybrid--bm25-search query sources))
         (fused (gptel-hybrid--reciprocal-rank-fusion
                 vector-results bm25-results)))
    fused))

(defun gptel-hybrid--vector-search (query sources)
  "Search SOURCES using vector embeddings for QUERY."
  (when (featurep 'ollama)
    (let* ((embedding (ollama-embed gptel-hybrid-search-vector-model query))
           (results (mapcar (lambda (source)
                              (cons source
                                    (ollama-similarity embedding
                                                       (gptel-source-embed source))))
                            sources)))
      (sort results (lambda (a b) (> (cdr a) (cdr b)))))))

(defun gptel-hybrid--bm25-search (query sources)
  "Search SOURCES using BM25 keyword matching for QUERY."
  (let* ((query-terms (split-string query))
         (results (mapcar (lambda (source)
                            (cons source
                                  (gptel-bm25-score
                                   query-terms
                                   (gptel-source-text source))))
                          sources)))
    (sort results (lambda (a b) (> (cdr a) (cdr b))))))

(defun gptel-bm25-score (terms text &optional (k1 1.5) (b 0.75))
  "Calculate BM25 score for TERMS against TEXT."
  (let ((doc-len (length (split-string text)))
        (avg-doc-len (gptel-bm25--avg-doc-len))
        (term-freqs (gptel-bm25--term-freqs terms text)))
    (apply '+
           (mapcar (lambda (term)
                     (let ((tf (or (cdr (assoc term term-freqs)) 0))
                           (idf (gptel-bm25--idf term)))
                       (* idf
                          (/ (* tf (1+ k1))
                             (+ tf (* k1 (- 1 b b (/ (float doc-len) avg-doc-len))))))))
                   terms))))

(defun gptel-hybrid--reciprocal-rank-fusion (list-a list-b &optional (k 60))
  "Fuse LIST-A and LIST-B using Reciprocal Rank Fusion with constant K."
  (let ((scores (make-hash-table :test 'equal)))
    (dolist (item (seq-take list-a gptel-hybrid-search-k))
      (puthash (car item)
               (+ (gethash (car item) scores 0)
                  (/ 1.0 (+ k (1+ (seq-position list-a item)))))
               scores))
    (dolist (item (seq-take list-b gptel-hybrid-search-k))
      (puthash (car item)
               (+ (gethash (car item) scores 0)
                  (/ 1.0 (+ k (1+ (seq-position list-b item)))))
               scores))
    (sort (hash-table->alist scores)
          (lambda (a b) (> (cdr a) (cdr b))))))
```

---

### 14. Self-Wiring Knowledge Graph

**Source**: [gbrain](https://github.com/davidwuchn/gbrain)

**Problem**: Entity relationships must be manually created, requiring LLM calls for every link.

**Solution**: Parse wiki-link-style references on page writes and auto-create typed graph edges with zero LLM calls.

#### Implementation

```elisp
(defcustom gptel-knowledge-graph-dir
  (expand-file-name ".gptel/knowledge-graph/" user-emacs-directory)
  "Directory for knowledge graph storage.")

(defvar gptel-entity-types
  '(person project tool technique repository concept experiment)
  "Valid entity types for knowledge graph.")

(defvar gptel-relation-types
  '(works_on created_by depends_on uses implements research_by
    tested_in influenced_by preceded_by succeeded_by)
  "Valid relation types for knowledge graph.")

(defun gptel-graph--parse-entities (text)
  "Parse [[wiki/...]] references from TEXT.
Returns list of (entity-type entity-name) tuples."
  (let ((entities '())
        (case-fold-search nil))
    (save-match-data
      (when (string-match "\\[\\[wiki/\\([a-z]+\\)/\\([^]]+\\)\\]\\]"
                          text)
        (push (list (intern (match-string 1 text))
                    (match-string 2 text))
              entities)))
    entities))

(defun gptel-graph--parse-typed-links (text)
  "Parse [[entity::relation::target]] typed links from TEXT."
  (let ((links '()))
    (save-match-data
      (while (string-match "\\[\\[\\([^:]+\\)::\\([^:]+\\)::\\([^]]+\\)\\]\\]"
                          text)
        (push (list (match-string 1 text)
                    (intern (match-string 2 text))
                    (match-string 3 text))
              links)
        (setq text (substring text (match-end 0)))))
    links))

(defun gptel-graph--add-edges (source-page edges)
  "Add EDGES from SOURCE-PAGE to knowledge graph."
  (make-directory gptel-knowledge-graph-dir t)
  (let ((graph-file (expand-file-name "graph.edn"
                                       gptel-knowledge-graph-dir)))
    (with-temp-file graph-file
      (if (file-exists-p graph-file)
          (progn
            (insert-file-contents graph-file)
            (goto-char (point-max))
            (insert "\n")
            (dolist (edge edges)
              (prin1 `(edge :from ,source-page
                            :type ,(cadr edge)
                            :to ,(caddr edge)
                            :added-at ,(current-time))
                     (current-buffer))
              (insert "\n")))
        (insert "[\n")
        (dolist (edge edges)
          (prin1 `(edge :from ,source-page
                        :type ,(cadr edge)
                        :to ,(caddr edge)
                        :added-at ,(current-time))
                 (current-buffer))
          (insert "\n"))
        (insert "]")))))

(defun gptel-graph--query (entity-type entity-name)
  "Query graph for ENTITY-TYPE ENTITY-NAME, returning connected entities."
  (let ((graph-file (expand-file-name "graph.edn"
                                       gptel-knowledge-graph-dir))
        (results '()))
    (when (file-exists-p graph-file)
      (with-temp-buffer
        (insert-file-contents graph-file)
        (goto-char (point-min))
        (while (not (eobp))
          (let ((edge (ignore-errors (read (current-buffer)))))
            (when (and (listp edge)
                       (eq (car edge) 'edge)
                       (or (equal (cadr (memq :from edge)) entity-name)
                           (equal (caddr (memq :to edge)) entity-name)))
              (push edge results)))))
        results)))
```

---

### 15. Worktree Isolation for Agent Runs

**Source**: [symphony](https://github.com/davidwuchn/symphony)

**Problem**: Multiple experiment runs can contaminate each other through shared git state.

**Solution**: Isolate each experiment run in its own git worktree with versioned workflow policy.

```elisp
(defcustom gptel-worktree-experiment-dir
  (expand-file-name ".gptel/experiments/" user-emacs-directory)
  "Base directory for experiment worktrees.")

(defun gptel-worktree--create (experiment-id)
  "Create isolated git worktree for EXPERIMENT-ID."
  (let* ((experiment-dir (expand-file-name experiment-id
                                           gptel-worktree-experiment-dir))
         (worktree-branch (format "experiment/%s" experiment-id)))
    (make-directory experiment-dir t)
    ;; Create new branch for experiment
    (shell-command (format "git worktree add -b %s %s HEAD"
                           worktree-branch experiment-dir))
    ;; Copy workflow policy to worktree
    (when (file-exists-p "WORKFLOW.md")
      (copy-file "WORKFLOW.md"
                 (expand-file-name "WORKFLOW.md" experiment-dir)
                 t))
    experiment-dir))

(defun gptel-worktree--cleanup (experiment-id)
  "Remove worktree for EXPERIMENT-ID after completion."
  (let* ((experiment-dir (expand-file-name experiment-id
                                           gptel-worktree-experiment-dir))
         (worktree-branch (format "experiment/%s" experiment-id)))
    (shell-command (format "git worktree remove %s" experiment-dir))
    (shell-command (format "git branch -D %s" worktree-branch))))
```

---

### 16. DEGRADED State Circuit Breaker

**Source**: External (Hannecke Medium article)

**Problem**: Standard circuit breakers only have CLOSED/OPEN states, causing hard failures.

**Solution**: Add DEGRADED state with graduated capability reduction before hard stop.

```elisp
(defvar gptel-degraded-config
  '(:failure-threshold 3
    :degraded-tools-disabled '(shell-execute file-write batch-edit)
    :review-required t
    :conservative-mode t
    :graduated-recovery
    ((:level . 1) (:traffic . 0.05))
    ((:level . 2) (:traffic . 0.20))
    ((:level . 3) (:traffic . 0.50))))

(defun gptel-circuit-breaker--degraded-p (provider)
  "Return t if PROVIDER should enter DEGRADED state."
  (let ((state (gethash provider gptel-circuit-breaker-state '(0 0 nil))))
    (and (>= (car state) 2)
         (< (car state) (alist-get :failure-threshold
                                   gptel-degraded-config)))))

(defun gptel-circuit-breaker--state (provider)
  "Return circuit state for PROVIDER: 'closed, 'degraded, 'open, or 'half-open."
  (let* ((state (gethash provider gptel-circuit-breaker-state '(0 0 nil)))
         (last-failure (caddr state)))
    (cond
     ((not last-failure) 'closed)
     ((gptel-circuit-breaker--degraded-p provider) 'degraded)
     ((>= (float-time (time-since last-failure))
          (alist-get 'recovery-timeout gptel-circuit-breaker-config))
      'half-open)
     ((gptel-circuit-breaker--should-trip provider) 'open)
     (t 'closed))))

(defun gptel-circuit-breaker--apply-degraded-mode ()
  "Apply degraded mode restrictions."
  (let ((disabled-tools (alist-get :degraded-tools-disabled
                                   gptel-degraded-config)))
    (dolist (tool disabled-tools)
      (message "Degraded mode: disabled %s" tool))
    (when (alist-get :review-required gptel-degraded-config)
      (message "Degraded mode: human review required"))
    (alist-get :conservative-mode gptel-degraded-config)))
```

---

## Research Pipeline Integration

### Research Quality Metrics

Every experiment must include research traceability:

```elisp
(defcustom gptel-research-hash-required t
  "If non-nil, experiments must include research hash.")

(defun gptel-experiment--validate-research (experiment)
  "Validate EXPERIMENT has research hash if required."
  (when gptel-research-hash-required
    (unless (plist-get experiment :research-hash)
      (signal 'gptel-validation-error
              "Experiment missing research hash"))))
```

### Missing Research Fallback Protocol

```elisp
(defun gptel-research--fallback-handler ()
  "Handle missing research findings gracefully.
Use this when researcher daemon disappears after being observed."
  (list
   :action 'use-cached-patterns
   :priority-changes
   '("Ensure every experiment row includes non-None research hash"
     "Treat missing research files as pipeline defect"
     "Prefer structured machine-parseable outputs"
     "Guard daemon boundaries - fail fast on disappearance"
     "Prioritize observable self-evolution")))
```

---

## Related Topics

- [auto-workflow-design](auto-workflow-design) — Daemon architecture and workflow states
- [gptel-ext-fsm](gptel-ext-fsm) — FSM utilities for state machine implementation
- [gptel-tools-agent-runtime](gptel-tools-agent-runtime) — Agent execution runtime patterns
- [gptel-tools-memory](gptel-tools-memory) — Memory system integration
- [gptel-benchmark-evolution](gptel-benchmark-evolution) — Experiment tracking and evolution metrics
- [mementum-knowledge](mementum-knowledge) — Knowledge synthesis and persistence
- [agent-error-recovery](agent-error-recovery) — Error handling best practices
- [sqlite-patterns](sqlite-patterns) — SQLite usage patterns across the codebase

---

## Appendix: External Sources Reference

| Source | URL | Key Patterns |
|--------|-----|--------------|
| efrit | https://github.com/davidwuchn/efrit | Circuit breaker, tool receipts |
| nucleus | https://github.com/davidwuchn/nucleus | Lambda notation, VSM |
| context-mode | https://github.com/davidwuchn/context-mode | Think-in-code, FTS5 |
| mementum | https://github.com/davidwuchn/mementum | Feed-forward memory |
| gastown | https://github.com/davidwuchn/gastown | Beads ledger, watchdog |
| genesis-agent | https://github.com/davidwuchn/genesis-agent | Self-verification |
| gbrain | https://github.com/davidwuchn/gbrain | Hybrid search, knowledge graph |
| symphony | https://github.com/davidwuchn/symphony | Worktree isolation |
| zeroclaw | https://github.com/davidwuchn/zeroclaw | Security-first design |
| psi | https://github.com/davidwuchn/psi | Statechart architecture |
| arXiv 2405.10467 | https://arxiv.org/abs/2405.10467 | 18 agent patterns |
| Azure Agent Patterns | https://learn.microsoft.com/.../ai-agent-design-patterns | Orchestration spectrum |
| NVIDIA Agent Eval | https://developer.nvidia.com/.../ai-agent-evaluation | Trajectory metrics |
| AI Agent Error Recovery | https://aiagentsblog.com/blog/agent-error-recovery-patterns | Error recovery |

---

*Generated from research findings synthesized across multiple experiment sessions.*
*Research quality measured by downstream experiment success.*
```