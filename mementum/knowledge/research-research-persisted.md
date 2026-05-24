<!--
Synthesis verification:
- Confidence: 24%
- Sources: 5 memories
- Warnings: No code examples or concrete references, Content does not mention topic 'research-research-persisted'
- Auto-approved: yes (flagged)
--->

---
title: Research Persisted Patterns Knowledge Base
status: active
category: knowledge
tags: [agent-architecture, error-recovery, memory-systems, context-management, self-evolution, circuit-breaker, checkpoint-restore, knowledge-graph, evaluation-metrics]
---

# Research Persisted Patterns Knowledge Base

## Overview

This knowledge page synthesizes patterns from external research across multiple agent systems and academic sources. The patterns are categorized by applicability and implementation difficulty, providing actionable guidance for the Emacs AI agent system (gptel-auto-workflow).

**Research sessions documented:**
- Session 1: 2026-05-20 (Targets: memory, benchmark, core modules) — 4/24 findings kept (17%)
- Session 2: 2026-05-22 04:11 (Targets: preview, FSM, agent runtime) — 2/56 findings kept (4%)
- Session 3: 2026-05-22 10:17 (Target: experiment-loop) — 3/9 findings kept (33%)
- Session 4: 2026-05-22 10:29 (Targets: agent runtime, memory, FSM) — 9/39 findings kept (23%)
- Session 5: 2026-05-22 12:10 (Targets: benchmark-evolution, strategy-harness) — 3/9 findings kept (33%)

---

## Tier 1: Directly Applicable Patterns

### 1. Circuit Breaker + Checkpoint/Restore Pattern

**Source:** [efrit](https://github.com/davidwuchn/efrit) — Native Elisp Coding Agent Architecture

**Pattern:** Circuit breaker monitors failure rates per provider, transitions through CLOSED→OPEN→HALF-OPEN states to prevent cascading failures. Checkpoint/restore stores state snapshots before risky operations.

**Implementation:**

```elisp
(defcustom gptel-circuit-breaker-config
  '(("openai" 5 300)
    ("claude" 5 300)
    ("ollama" 3 60))
  "Circuit breaker config: (provider failure-threshold reset-seconds)."
  :type '(alist :key-type string :value-type (list integer integer)))

(defvar gptel-circuit-breaker--state nil
  "Hash table tracking failure counts and states per provider.")

(defun gptel-circuit-breaker--get-state (provider)
  "Get circuit state for PROVIDER: 'closed, 'open, or 'half-open."
  (or (gethash provider gptel-circuit-breaker--state)
      'closed))

(defun gptel-circuit-breaker--record-success (provider)
  "Record successful call, reset failure count."
  (let ((state (gethash provider gptel-circuit-breaker--state)))
    (when state
      (setf (gethash 'failure-count state) 0)
      (setf (gethash 'state state) 'closed))))

(defun gptel-circuit-breaker--record-failure (provider)
  "Record failure, potentially open circuit."
  (let ((state (or (gethash provider gptel-circuit-breaker--state)
                   (progn (setq state (make-hash-table))
                          (puthash provider state gptel-circuit-breaker--state)
                          state))))
    (cl-incf (gethash 'failure-count state 0))
    (let ((threshold (car (alist-get provider gptel-circuit-breaker-config))))
      (when (>= (gethash 'failure-count state) threshold)
        (setf (gethash 'state state) 'open)
        (setf (gethash 'open-until state)
              (+ (float-time) (cadr (alist-get provider gptel-circuit-breaker-config))))))))

(defun gptel-circuit-breaker--check (provider)
  "Return t if circuit allows request, nil if blocked."
  (pcase (gptel-circuit-breaker--get-state provider)
    ('closed t)
    ('half-open t)  ; Allow probe requests
    ('open
     (if (> (float-time) (gethash 'open-until (gethash provider gptel-circuit-breaker--state) 0))
         (progn
           (setf (gethash 'state (gethash provider gptel-circuit-breaker--state)) 'half-open)
           t)
       nil))))
```

**Checkpoint/Restore Implementation:**

```elisp
(defvar gptel-checkpoint-dir
  (expand-file-name ".gptel/checkpoints/" user-emacs-directory))

(defun gptel-checkpoint-save (label &optional data)
  "Save checkpoint with LABEL and optional DATA."
  (unless (file-directory-p gptel-checkpoint-dir)
    (make-directory gptel-checkpoint-dir t))
  (let ((file (expand-file-name (format "%s-%s.el" label (format-time-string "%Y%m%d-%H%M%S"))
                                gptel-checkpoint-dir)))
    (with-temp-file file
      (insert ";; gptel-checkpoint: " label "\n")
      (insert ";; Created: " (format-time-string "%Y-%m-%d %H:%M:%S") "\n\n")
      (when data
        (pp data (current-buffer))))
    file))

(defun gptel-checkpoint-restore (label)
  "Restore most recent checkpoint matching LABEL glob pattern."
  (let* ((files (directory-files gptel-checkpoint-dir t (format "%s-.*\\.el" label) t))
         (latest (car (sort files #'file-newer-than-file-p))))
    (when latest
      (with-temp-buffer
        (insert-file-contents latest)
        (goto-char (point-min))
        (read (current-buffer))))))
```

**Trigger checkpoint before risky operations:**

```elisp
(defmacro gptel-with-checkpoint (label &rest body)
  "Execute BODY with automatic checkpoint on success."
  (declare (indent defun))
  `(let ((checkpoint-data nil))
     (unwind-protect
         (progn
           (setq checkpoint-data (progn ,@body))
           (gptel-checkpoint-save ,label checkpoint-data)
           checkpoint-data)
       ;; On error, checkpoint already saved from last successful run
       )))
```

**Apply to:** `gptel-tools-agent-runtime.el` — Implement circuit breaker for API calls, checkpoint before experiment runs.

---

### 2. Tool Receipts for Audit Trail

**Source:** [efrit](https://github.com/davidwuchn/efrit) (35+ tools with security controls)

**Pattern:** Every tool execution generates structured metadata: `(input-hash output-hash timestamp duration tool-name)`. Shell commands have allowed/forbidden pattern matching.

**Implementation:**

```elisp
(require 'sqlite nil t)

(defvar gptel-tool-log-db
  (expand-file-name ".gptel/tool-log.db" user-emacs-directory))

(defun gptel-tool-log--init ()
  "Initialize tool log database."
  (when (featurep 'sqlite)
    (sqlite-execute gptel-tool-log-db
      "CREATE TABLE IF NOT EXISTS tool_executions (
         id INTEGER PRIMARY KEY AUTOINCREMENT,
         session_id TEXT,
         tool_name TEXT,
         input_hash TEXT,
         output_hash TEXT,
         timestamp REAL,
         duration_ms INTEGER,
         success INTEGER,
         error TEXT
       )")
    (sqlite-execute gptel-tool-log-db
      "CREATE INDEX IF NOT EXISTS idx_tool_name ON tool_executions(tool_name)")
    (sqlite-execute gptel-tool-log-db
      "CREATE INDEX IF NOT EXISTS idx_session ON tool_executions(session_id)")))

(defun gptel-tool-log--record (tool-name input output success &optional error)
  "Record tool execution to audit log."
  (when (featurep 'sqlite)
    (let ((input-hash (secure-hash 'sha256 (prin1-to-string input)))
          (output-hash (when output (secure-hash 'sha256 (prin1-to-string output))))
          (start-time (or (get 'gptel-tool-log--start-times tool-name) (float-time)))
          (duration (- (float-time) (or (get 'gptel-tool-log--start-times tool-name)
                                         (float-time)))))
      (sqlite-execute gptel-tool-log-db
        (format "INSERT INTO tool_executions VALUES (NULL, '%s', '%s', '%s', '%s', %.3f, %d, %d, '%s')"
                (gptel-session-id)
                tool-name
                input-hash
                (or output-hash "")
                (float-time)
                (round (* 1000 duration))
                (if success 1 0)
                (or error ""))))))

(defmacro gptel-tool-wrapper (tool-name &rest body)
  "Wrap tool execution with logging and timing."
  (declare (indent defun))
  `(let ((start-time (float-time)))
     (put 'gptel-tool-log--start-times ',tool-name start-time)
     (condition-case err
         (let ((result (progn ,@body)))
           (gptel-tool-log--record ,tool-name nil result t)
           result)
       (error
        (gptel-tool-log--record ,tool-name nil nil nil (error-message-string err))
        (signal (car err) (cdr err))))))
```

**Shell command security patterns:**

```elisp
(defcustom gptel-shell-allowed-patterns
  '("git " "make " "cargo " "npm " "pip " "elisp/")
  "Allowed command prefixes for shell execution."
  :type '(repeat string))

(defcustom gptel-shell-forbidden-patterns
  '("rm -rf /" "dd if=" "mkfs" ":(){:|:&};" "curl.*-o /tmp/")
  "Forbidden command patterns (regex)."
  :type '(repeat string))

(defun gptel-shell-command-safe-p (command)
  "Check if COMMAND passes security patterns."
  (and (cl-every (lambda (pattern)
                   (string-match-p pattern command))
                 gptel-shell-allowed-patterns)
       (not (cl-notevery (lambda (pattern)
                           (null (string-match-p pattern command)))
                         gptel-shell-forbidden-patterns))))
```

**Apply to:** `gptel-tools-memory.el` — Track all tool calls with cryptographic hashes for replay and compliance audit.

---

### 3. Mathematical Attention Magnets (Lambda Notation)

**Source:** [nucleus](https://github.com/davidwuchn/nucleus) — VSM Architecture

**Pattern:** Greek letters and math symbols as compressed prompt preamble: `λ engage(nucleus). [phi fractal euler tao pi mu ∃ ∀]`. Primes formal reasoning patterns.

**Implementation:**

```elisp
(defvar gptel-preamble-templates
  '(("lambda-engage"
     . "λ engage(gptel). [φ ψ Δ λ ∇] | [signal/noise order/entropy] | OODA loop"))
    ("formal-reasoning"
     . "∀x ∈ workspace: verify(x) → valid(x). ∃ path: plan → execute → verify."))
  "Preamble templates with mathematical attention anchors.")

(defun gptel-build-system-prompt (&optional context)
  "Build system prompt with attention anchors for CONTEXT."
  (let ((base-prompt (or (car (alist-get 'system-prompt gptel-config))
                         "You are a helpful AI assistant.")))
    (concat base-prompt "\n\n"
            (cdr (alist-get (or (car (alist-get 'preamble-style context))
                                "lambda-engage")
                           gptel-preamble-templates))
            "\n\nMode: " (symbol-name (or (car (alist-get 'mode context))
                                        'standard)))))

;; EDN-style statechart for workflow phases
(defvar gptel-workflow-statechart
  '(:states
    (:idle {:enter "await-task", :transitions (:task-received :planning)})
    (:planning {:enter "analyze-goal", :transitions (:plan-ready :executing)
                                                  (:stalled :awaiting-human)})
    (:executing {:enter "apply-tools", :transitions (:complete :reviewing)
                                                     (:error :recovering)})
    (:reviewing {:enter "verify-output", :transitions (:approved :idle)
                                                        (:needs-work :executing)})
    (:recovering {:enter "apply-corrections", :transitions (:recovered :executing)
                                                     (:failed :awaiting-human)})
    (:awaiting-human {:enter "request-input", :transitions (:input-received :planning)})))
```

**Apply to:** `gptel-system-prompt` — Use EDN statecharts for `gptel-auto-workflow` states.

---

### 4. Think-in-Code Context Reduction

**Source:** [context-mode](https://github.com/davidwuchn/context-mode)

**Pattern:** Instead of dumping raw file reads (700KB), execute analysis script that returns only result (3.6KB). 98% context reduction via sandbox tools.

**Implementation:**

```elisp
(defvar gptel-sandbox-dir
  (expand-file-name ".gptel/sandbox/" user-emacs-directory))

(defun gptel-sandbox-execute (analysis-script &optional params)
  "Execute ANALYSIS-SCRIPT (elisp form) in isolated context, return structured result.
PARAMS are bound as variables during execution."
  (let ((script-file (expand-file-name "analysis.el" gptel-sandbox-dir))
        (result-file (expand-file-name "result.json" gptel-sandbox-dir)))
    (unless (file-directory-p gptel-sandbox-dir)
      (make-directory gptel-sandbox-dir t))
    ;; Write analysis script with result capture
    (with-temp-file script-file
      (insert ";; Sandbox analysis script\n")
      (insert "(setq sandbox-params '" (prin1-to-string params) ")\n\n")
      (insert "(let ((result\n")
      (insert "          (condition-case err\n")
      (insert "              (progn " (format "%s" analysis-script) ")\n")
      (insert "            (error (list 'error (error-message-string err))))))\n")
      (insert "  (with-temp-file \"" result-file "\"\n")
      (insert "    (insert (json-encode result))))\n"))
    ;; Execute in isolated subprocess
    (let ((exit-code (call-process "emacs" nil nil nil
                                   "--batch" "-Q"
                                   "--load" script-file)))
      (when (zerop exit-code)
        (when (file-exists-p result-file)
          (with-temp-buffer
            (insert-file-contents result-file)
            (json-parse-buffer :object-type 'alist))))))))

;; Example: Instead of reading 1000 lines, compute summary
(defun gptel-analyze-project-files ()
  "Analyze project files without dumping raw content."
  (gptel-sandbox-execute
   '(progn
     (require 'find-lisp)
     (let ((elisp-files (find-lisp-find-files user-emacs-directory "\\.el$"))
           (total-lines 0)
           (file-count 0))
       (dolist (file (cl-loop for f in elisp-files
                              when (string-match "gptel" f) collect f))
         (with-temp-buffer
           (insert-file-contents file)
           (cl-incf total-lines (count-lines (point-min) (point-max)))
           (cl-incf file-count)))
       `(:file-count ,file-count
         :total-lines ,total-lines
         :avg-lines-per-file ,(/ total-lines (max file-count 1))
         :recent-modules
         ,(mapcar (lambda (f) (file-name-nondirectory f))
                  (cl-subseq elisp-files 0 (min 5 (length elisp-files))))))))
   nil))
```

**Apply to:** `gptel-auto-workflow-projects.el` — Accept executable analysis scripts instead of data dumps.

---

### 5. Session Continuity via FTS5

**Source:** [context-mode](https://github.com/davidwuchn/context-mode)

**Pattern:** Every edit, git op, task, error tracked in SQLite with FTS5. When context compacts, retrieves only relevant events via BM25 search.

**Implementation:**

```elisp
(defvar gptel-session-db
  (expand-file-name ".gptel/sessions.db" user-emacs-directory))

(defun gptel-session--init ()
  "Initialize session continuity database."
  (when (featurep 'sqlite)
    (sqlite-execute gptel-session-db
      "CREATE TABLE IF NOT EXISTS events (
         id INTEGER PRIMARY KEY AUTOINCREMENT,
         session_id TEXT,
         timestamp REAL,
         event_type TEXT,
         data TEXT,
         full_text TEXT
       )")
    (sqlite-execute gptel-session-db
      "CREATE VIRTUAL TABLE IF NOT EXISTS events_fts USING fts5(
         session_id, event_type, data, full_text,
         content='events',
         content_rowid='id'
       )")
    (sqlite-execute gptel-session-db
      "CREATE TRIGGER IF NOT EXISTS events_ai AFTER INSERT ON events BEGIN
         INSERT INTO events_fts(rowid, session_id, event_type, data, full_text)
         VALUES (new.id, new.session_id, new.event_type, new.data, new.full_text);
       END")))

(defun gptel-session--log-event (event-type data)
  "Log EVENT-TYPE with DATA to session database."
  (when (featurep 'sqlite)
    (sqlite-execute gptel-session-db
      (format "INSERT INTO events VALUES (NULL, '%s', %.3f, '%s', '%s', '%s')"
              (gptel-session-id)
              (float-time)
              event-type
              (json-encode-string data)
              (json-encode-string data)))))

(defun gptel-session--retrieve-relevant (query session-id limit)
  "Retrieve events relevant to QUERY from SESSION-ID using BM25 ranking."
  (when (featurep 'sqlite)
    (let ((results (sqlite-select gptel-session-db
                    (format "SELECT e.*, bm25(events_fts) as rank
                             FROM events_fts f
                             JOIN events e ON e.id = f.rowid
                             WHERE events_fts MATCH '%s'
                               AND e.session_id = '%s'
                             ORDER BY rank
                             LIMIT %d"
                            (sqlite-escape-string query)
                            session-id
                            limit))))
      (mapcar (lambda (row)
                (list :timestamp (nth 2 row)
                      :event-type (nth 3 row)
                      :data (json-parse-string (nth 4 row) :object-type 'alist)))
              results))))

;; Log events
(gptel-session--log-event "edit" '(:file "gptel-tools-memory.el" :lines-added 5))
(gptel-session--log-event "tool-call" '(:tool "Read" :args ("file.el") :result :success))
(gptel-session--log-event "error" '(:type "api-timeout" :provider "claude"))
```

**Apply to:** `gptel-memory-synthesize` — Maintain continuity across context compaction events.

---

### 6. Feed-Forward Memory Protocol

**Source:** [mementum](https://github.com/davidwuchn/mementum) — Git Memory Protocol

**Pattern:** Three storage types (working memory/state.md, memories <200 words, synthesized knowledge). Human governance: AI proposes, human approves, AI commits.

**Implementation:**

```elisp
(defvar gptel-memory-structures
  '(("state.md" . "Working memory - current session context, active tasks")
    ("memories/" . "Short memories (<200 words) - transient insights")
    ("knowledge/" . "Synthesized knowledge - persistent patterns and learnings"))
  "Three-tier memory structure for gptel.")

(defun gptel-memory-synthesize ()
  "Read mementum-style state.md on session start."
  (let ((state-file (expand-file-name "state.md" gptel-config-dir)))
    (when (file-exists-p state-file)
      (with-temp-buffer
        (insert-file-contents state-file)
        (buffer-string)))))

(defun gptel-memory-propose (memory-text)
  "Propose MEMORY-TEXT for human review before committing."
  (let ((proposal-file (expand-file-name
                        (format "proposals/%s.md" (format-time-string "%Y%m%d-%H%M%S"))
                        gptel-config-dir)))
    (make-directory (file-name-directory proposal-file) t)
    (with-temp-file proposal-file
      (insert "# Memory Proposal\n\n")
      (insert "## Proposed Memory\n\n")
      (insert memory-text "\n\n")
      (insert "## Rationale\n")
      (insert (format "Auto-generated: %s\n" (format-time-string "%Y-%m-%d %H:%M:%S"))))
    (message "Memory proposal saved to %s - awaiting human approval" proposal-file)
    proposal-file))

(defun gptel-memory-commit (approved-file target-dir)
  "Commit APPROVED-FILE to TARGET-DIR after human approval."
  (let* ((content (with-temp-buffer
                    (insert-file-contents approved-file)
                    (goto-char (point-min))
                    (when (re-search-forward "^## Proposed Memory" nil t)
                      (forward-line 2)
                      (buffer-substring (point) (point-max)))))
         (target-file (expand-file-name
                       (format "%s/%s.md" target-dir
                               (file-name-base approved-file))
                       gptel-config-dir)))
    (with-temp-file target-file
      (insert content))
    (message "Memory committed to %s" target-file)
    target-file))
```

**Apply to:** Knowledge page creation with approval workflow for successful experiment patterns.

---

## Tier 2: Agent Architecture Patterns

### 7. Three-Tier Watchdog Architecture

**Source:** [gastown](https://github.com/davidwuchn/gastown) — Multi-Agent Workspace Orchestration

**Pattern:** Systematized lifecycle management via three tiers: Witness (session lifecycle), Deacon (continuous background patrol), Dogs (dispatched workers).

**Implementation:**

```elisp
;; Three-tier watchdog for auto-workflow daemon

(defvar gptel-workflow--witness nil "Witness timer for session lifecycle.")
(defvar gptel-workflow--deacon nil "Deacon timer for periodic health checks.")
(defvar gptel-workflow--dogs nil "Hash table of dispatched cleanup/error recovery tasks.")

(defun gptel-workflow--witness-start ()
  "Start Witness - monitors session lifecycle."
  (setq gptel-workflow--witness
        (run-at-time 0 30
          (lambda ()
            (when (gptel-session-valid-p)
              (gptel-session--heartbeat)
              (gptel-workflow--check-stalled-tasks))))))

(defun gptel-workflow--deacon-patrol ()
  "Deacon - continuous background patrol, runs every 60 seconds."
  (let ((health (gptel-workflow--health-check)))
    (pcase health
      (:healthy (message "gptel-workflow: healthy"))
      (:degraded
       (message "gptel-workflow: degraded - reducing concurrency")
       (gptel-workflow--reduce-concurrency))
      (:critical
       (message "gptel-workflow: critical - initiating recovery")
       (gptel-workflow--initiate-recovery)))))

(defun gptel-workflow--dispatch-dog (task-type task-fn &optional args)
  "Dispatch a Dog (worker) for TASK-TYPE with TASK-FN and ARGS."
  (let ((dog-id (format "dog-%s-%s" task-type (format-time-string "%H%M%S"))))
    (puthash dog-id (list :type task-type
                         :fn task-fn
                         :args args
                         :dispatched-at (float-time))
             gptel-workflow--dogs)
    (run-with-timer 0 nil
      (lambda ()
        (condition-case err
            (apply task-fn args)
          (error
           (message "Dog %s failed: %s" dog-id err)
           (gptel-workflow--dispatch-dog task-type task-fn args)
           (cl-incf (gethash 'retry-count (gethash dog-id gptel-workflow--dogs) 0))))
        (remhash dog-id gptel-workflow--dogs)))
    dog-id))

;; Convoy system for bundling work items with stall detection
(defvar gptel-workflow--convoys nil "Hash of work convoys.")

(defun gptel-workflow--convoy-create (items)
  "Create convoy from ITEMS with autonomous stall detection."
  (let ((convoy-id (format "convoy-%s" (format-time-string "%Y%m%d-%H%M%S"))))
    (puthash convoy-id
             (list :items items
                   :started-at (float-time)
                   :status 'active)
             gptel-workflow--convoys)
    convoy-id))

(defun gptel-workflow--convoy-check-stall (convoy-id timeout-seconds)
  "Check if CONVOY-ID has stalled (no progress for TIMEOUT-SECONDS)."
  (let ((convoy (gethash convoy-id gptel-workflow--convoys)))
    (when convoy
      (> (- (float-time) (gethash :started-at convoy)) timeout-seconds))))
```

**Apply to:** `gptel-auto-workflow-daemon.el` — Separate watchdog from execution logic.

---

### 8. Self-Wiring Knowledge Graph

**Source:** [gbrain](https://github.com/davidwuchn/gbrain)

**Pattern:** Every page write extracts entity references and creates typed links with **zero LLM calls**. Graph produces +31.4 P@5 lift over vector-only RAG.

**Implementation:**

```elisp
(defvar gptel-knowledge-graph nil "In-memory knowledge graph.")
(setq gptel-knowledge-graph (make-hash-table :test 'equal))

;; Entity types and their link patterns
(defvar gptel-entity-link-types
  '(("works_at" . "\\[\\[people/\\([^]]+\\)\\]\\]")
    ("uses" . "\\[\\[tools/\\([^]]+\\)\\]\\]")
    ("implemented_in" . "\\[\\[modules/\\([^]]+\\)\\]\\]")
    ("researched_via" . "\\[\\[research/\\([^]]+\\)\\]\\]")
    ("tested_with" . "\\[\\[benchmarks/\\([^]]+\\)\\]\\]")))

(defun gptel-graph-extract-entities (page-content page-id)
  "Extract [[entity]] references from PAGE-CONTENT and create typed edges.
Zero LLM calls - pure pattern matching."
  (maphash (lambda (link-type pattern)
             (dolist (match (seq-partition (string-match-pids pattern page-content) 2))
               (when (match-beginning 1)
                 (let* ((entity (match-string-no-properties 1 page-content))
                        (entity-id (concat (substring link-type 0 1) ":" entity)))
                   ;; Create entity if not exists
                   (unless (gethash entity-id gptel-knowledge-graph)
                     (puthash entity-id
                              (list :type link-type :name entity :pages nil)
                              gptel-knowledge-graph))
                   ;; Add bidirectional edge
                   (pushnew page-id (gethash entity-id gptel-knowledge-graph))
                   (pushnew entity-id (gethash page-id gptel-knowledge-graph))))))
           gptel-entity-link-types))

(defun gptel-graph-query (entity-id &optional depth)
  "Query ENTITY-ID with optional traversal DEPTH."
  (let ((visited (make-hash-table :test 'equal))
        (results nil))
    (cl-labels ((traverse (id d)
                  (unless (or (gethash id visited) (and depth (>= d depth)))
                    (puthash id t visited)
                    (push (gethash id gptel-knowledge-graph) results)
                    (dolist (linked-id (gethash id gptel-knowledge-graph))
                      (traverse linked-id (1+ d))))))
      (traverse entity-id 0))
    results))

;; Example usage in memory system
(defun gptel-memory--page-written (page-id content)
  "Hook called when a memory page is written - auto-wire graph."
  (gptel-graph-extract-entities content page-id))
```

**Apply to:** `mementum--memory` system for cross-experiment knowledge graph.

---

### 9. Self-Verification Engine

**Source:** [genesis-agent](https://github.com/davidwuchn/genesis-agent)

**Pattern:** Programmatic verification before trust; self-modification loop. [PLAN] + [EXPECT] with P(success) confidence scoring.

**Implementation:**

```elisp
;; Verification functions - "LLM proposes, machine verifies"
(defvar gptel-verification-functions nil
  "Registry of verification functions.")

(defun gptel-verify-register (name fn)
  "Register verification function NAME -> FN."
  (puthash name fn gptel-verification-functions))

;; Syntax verification
(gptel-verify-register "elisp-syntax"
  (lambda (code)
    (condition-case err
        (progn
          (read code)
          (list :pass t))
      (error
       (list :pass nil :reason (error-message-string err))))))

;; Exit code verification
(gptel-verify-register "exit-zero"
  (lambda (command)
    (let ((exit-code (shell-command command)))
      (list :pass (zerop exit-code) :exit-code exit-code))))

;; File existence verification
(gptel-verify-register "file-exists"
  (lambda (filepath)
    (list :pass (file-exists-p filepath) :path filepath)))

;; Module signature verification
(gptel-verify-register "module-provided"
  (lambda (feature)
    (list :pass (featurep (intern feature)) :feature feature)))

;; P(success) confidence tracking
(defvar gptel-confidence-scores nil
  "Hash of task-pattern -> (successes . attempts).")

(defun gptel-confidence-update (pattern success)
  "Update confidence score for PATTERN based on SUCCESS."
  (let ((score (or (gethash pattern gptel-confidence-scores) '(0 . 0))))
    (setf (car score) (+ (car score) (if success 1 0)))
    (setf (cdr score) (1+ (cdr score)))
    (puthash pattern score gptel-confidence-scores)))

(defun gptel-confidence-get (pattern)
  "Get P(success) for PATTERN."
  (let ((score (gethash pattern gptel-confidence-scores '(0 . 0))))
    (if (zerop (cdr score))
        0.5  ; Unknown, use neutral confidence
      (/ (float (car score)) (cdr score)))))

;; Verification gate
(defun gptel-verify-gate (plan checks)
  "Verify PLAN against CHECKS list. Return (pass . failures)."
  (let ((failures nil))
    (dolist (check checks)
      (let* ((fn (gethash (car check) gptel-verification-functions))
             (result (when fn (funcall fn (cadr check)))))
        (unless (and result (plist-get result :pass))
          (push (list check result) failures))))
    (if failures
        (cons nil failures)
      (cons t nil))))
```

**Apply to:** `gptel-auto-workflow` — Add verification gates before committing changes.

---

### 10. Statechart-Driven Architecture

**Source:** [psi](https://github.com/davidwuchn/psi) (Clojure)

**Pattern:** Statechart-driven agent with EQL-queryable graph. Extensions can completely customize the agent. Everything is introspectable.

**Implementation:**

```elisp
;; EDN-style statechart for auto-workflow
(defvar gptel-statechart
  '(:initial :idle
    :states
    (:idle {:entry :init-session
            :exit :clear-context
            :transitions
            ((:task-received :planning)
             (:research-available :researching))})
    (:planning {:entry :analyze-goal
                :exit :log-plan
                :transitions
                ((:plan-ready :executing)
                 (:stalled :awaiting-human)
                 (:timeout :degraded))})
    (:researching {:entry :fetch-external
                   :exit :synthesize-findings
                   :transitions
                   ((:findings-ready :planning)
                    (:no-findings :planning)
                    (:research-failed :degraded))})
    (:executing {:entry :run-experiment
                 :exit :record-results
                 :transitions
                 ((:complete :reviewing)
                  (:error :recovering)
                  (:max-iterations :degraded))})
    (:reviewing {:entry :verify-output
                 :transitions
                 ((:approved :idle)
                  (:needs-work :executing)
                  (:verification-failed :degraded))})
    (:recovering {:entry :apply-corrections
                  :transitions
                  ((:recovered :executing)
                   (:max-retries :awaiting-human))})
    (:degraded {:entry :reduce-capability
                :transitions
                ((:auto-recover :idle)
                 (:human-intervention :awaiting-human))})
    (:awaiting-human {:entry :pause-automation
                      :transitions
                      ((:human-resolved :planning)
                       (:human-aborted :idle))})))

(defun gptel-state-transition (current-state event)
  "Transition from CURRENT-STATE on EVENT using statechart."
  (let* ((state-def (plist-get (cdr (assq current-state (plist-get gptel-statechart :states)))
                               :transitions))
         (next-state (plist-get state-def event)))
    (when next-state
      ;; Run exit action
      (when (plist-member (cdr (assq current-state (plist-get gptel-statechart :states))) :exit)
        (funcall (plist-get (cdr (assq current-state (plist-get gptel-statechart :states))) :exit)))
      ;; Run entry action
      (when (plist-member (cdr (assq next-state (plist-get gptel-statechart :states))) :entry)
        (funcall (plist-get (cdr (assq next-state (plist-get gptel-statechart :states))) :entry)))
      (message "State transition: %s -[%s]-> %s" current-state event next-state)
      next-state)))
```

**Apply to:** `gptel-ext-fsm.el` — Replace prose state descriptions with formal EDN statecharts.

---

## Tier 3: Error Recovery & Evaluation Patterns

### 11. Error Recovery Patterns (5 Production Patterns)

**Source:** [AI Agent Error Recovery Patterns](https://aiagentsblog.com/blog/agent-error-recovery-patterns/)

| Pattern | Description | Implementation |
|---------|-------------|----------------|
| Exponential Backoff with Jitter | Retry delays increase exponentially with random jitter | `(min max-delay (* base-delay (expt 2 attempt)) (random jitter))` |
| Circuit Breakers | Open circuit after N failures | See Pattern 1 above |
| Checkpoint-and-Resume | Save state at each step | See Pattern 1 above |
| Fallback Chains | Provider A → Provider B → Provider C | See provider config below |
| Escalation Queues | Failed tasks moved to human review | `gptel-escalation-queue` |

**Provider fallback chain implementation:**

```elisp
(defcustom gptel-provider-chain
  '(("claude" :priority 1 :timeout 30)
    ("openai" :priority 2 :timeout 25)
    ("ollama" :priority 3 :timeout 60))
  "Provider fallback chain ordered by priority."
  :type '(alist :key-type string :value-type (plist :priority integer :timeout integer)))

(defun gptel-call-with-fallback (prompt)
  "Call providers in fallback order until success."
  (let ((providers (mapcar #'car gptel-provider-chain))
        (last-error nil))
    (dolist (provider providers)
      (condition-case err
          (let* ((config (alist-get provider gptel-provider-chain))
                 (timeout (plist-get config :timeout)))
            (message "Trying provider: %s" provider)
            (let ((result (gptel-call-with-timeout provider prompt timeout)))
              (gptel-circuit-breaker--record-success provider)
              (cl-return-from gptel-call-with-fallback result)))
        (error
         (progn
           (message "Provider %s failed: %s" provider err)
           (gptel-circuit-breaker--record-failure provider)
           (push (cons provider err) last-error)))))
    (signal 'gptel-all-providers-failed (list last-error))))

;; Escalation queue
(defvar gptel-escalation-queue nil "Queue of tasks requiring human review.")

(defun gptel-escalate-task (task reason)
  "Add TASK to escalation queue with REASON."
  (push (list :task task
              :reason reason
              :timestamp (float-time)
              :status 'pending)
        gptel-escalation-queue)
  (message "Task escalated: %s" reason))

(defun gptel-escalation-queue-view ()
  "Display pending escalation items."
  (when gptel-escalation-queue
    (message "Pending Escalations:")
    (dolist (item gptel-escalation-queue)
      (message "  - [%s] %s: %s"
              (format-time-string "%H:%M:%S" (list :timestamp item))
              (plist-get (cdr item) :reason)
              (plist-get (cdr item) :task)))))
```

---

### 12. Trajectory-Aware Evaluation Metrics

**Source:** [NVIDIA AI Agent Evaluation Guide](https://developer.nvidia.com/blog/mastering-agentic-techniques-ai-agent-evaluation/)

| Metric | What It Measures | Implementation |
|--------|------------------|----------------|
| **Task Success Rate (TSR)** | Intent resolution within constraints | `(/ successes total-attempts)` |
| **Tool Call Accuracy** | Precision in function calling | Compare called vs expected tools |
| **Trajectory Efficiency** | Steps/tokens per success | `(length trajectory) / success-count` |
| **Reasoning Soundness** | Trace quality, evidence usage | Post-hoc review or verification |

**Implementation:**

```elisp
(defvar gptel-metrics-db
  (expand-file-name ".gptel/metrics.db" user-emacs-directory))

(defun gptel-metrics--init ()
  "Initialize metrics database."
  (when (featurep 'sqlite)
    (sqlite-execute gptel-metrics-db
      "CREATE TABLE IF NOT EXISTS trajectories (
         id INTEGER PRIMARY KEY,
         experiment_id TEXT,
         timestamp REAL,
         steps INTEGER,
         tokens_used INTEGER,
         success INTEGER,
         tool_calls TEXT,
         final_state TEXT
       )")
    (sqlite-execute gptel-metrics-db
      "CREATE TABLE IF NOT EXISTS tool_accuracy (
         tool_name TEXT,
         total_calls INTEGER,
         successful_calls INTEGER,
         avg_latency_ms REAL
       )")))

(defun gptel-metrics--record-trajectory (experiment-id steps tokens-success tool-calls)
  "Record trajectory metrics for EXPERIMENT-ID."
  (when (featurep 'sqlite)
    (sqlite-execute gptel-metrics-db
      (format "INSERT INTO trajectories VALUES (
                 NULL, '%s', %.3f, %d, %d, %d, '%s', '%s')"
              experiment-id
              (float-time)
              (car steps)
              (cadr tokens-success)
              (if (cddr tokens-success) 1 0)
              (json-encode-string (mapcar #'car tool-calls))
              (json-encode-string (cddr tokens-success)))))))

(defun gptel-metrics--tsr (experiment-pattern)
  "Calculate Task Success Rate for experiments matching EXPERIMENT-PATTERN."
  (when (featurep 'sqlite)
    (let ((result (sqlite-select gptel-metrics-db
                    (format "SELECT
                               COUNT(*) as total,
                               SUM(success) as successes
                             FROM trajectories
                             WHERE experiment_id LIKE '%%%s%%'"
                            experiment-pattern))))
      (when result
        (let ((total (or (caar result) 0))
              (successes (or (cadar result) 0)))
          (if (zerop total) 0.0
            (/ (float successes) total)))))))

(defun gptel-metrics--trajectory-efficiency (experiment-pattern)
  "Calculate average trajectory efficiency (steps per success).")
  (when (featurep 'sqlite)
    (let ((result (sqlite-select gptel-metrics-db
                    (format "SELECT AVG(steps * 1.0 / success)
                             FROM trajectories
                             WHERE experiment_id LIKE '%%%s%%'
                               AND success = 1"
                            experiment-pattern))))
      (when result (caar result)))))
```

---

### 13. Agent Design Pattern Catalogue

**Source:** [arXiv:2405.10467](https://arxiv.org/abs/2405.10467) — 18 Architectural Patterns

**Orchestration Spectrum:**

| Level | Pattern | Use When |
|-------|---------|----------|
| 0 | Direct model call | Single-step tasks, prompt engineering suffices |
| 1 | Single agent + tools | Varied queries, dynamic tool use, iteration limits needed |
| 2 | Sequential | Linear dependencies, progressive refinement |
| 3 | Concurrent | Independent perspectives, fan-out/fan-in |
| 4 | Hierarchical | Master-slave coordination, complex delegation |

**Meta-Agent Self-Evolving Paradigm:**

| Phase | Implementation |
|-------|----------------|
| Help request | Generate when task pattern unrecognized |
| Self-reflection | Distill experience into concise texts |
| Answer verification | Programmatic output checking |
| Dynamic incorporation | Update future context with distilled experience |

```elisp
;; Three-Loop Meta-Learning Architecture (from HyperAgents)
(defvar gptel-three-loop-config
  '(:execution-loop :evaluation-loop :meta-loop)
  "Three-loop meta-learning configuration.")

(defun gptel-loop-execution (task)
  "Task Execution Loop - ReAct-style reasoning."
  (let ((observation nil)
        (thought nil))
    (while (and (< (get 'iteration-count 'workflow) (get 'max-iterations 'workflow))
                (not (funcall (get 'task-complete-p 'workflow) task observation)))
      (setq thought (gptel-reason task observation))
      (setq observation (gptel-act thought))
      (gptel-session--log-event "execution-step"
                                `(:thought ,thought :observation ,observation)))))

(defun gptel-loop-evaluation (result)
  "Evaluation Loop - test-based feedback."
  (let ((passed (gptel-verify-gate result (gptel-get-verification-checks result))))
    (if passed
        (progn
          (gptel-session--log-event "evaluation" '(:result :pass))
          (cl-return-from gptel-loop-evaluation (cons t result)))
      (progn
        (gptel-session--log-event "evaluation" `(:result :fail :reasons ,(cdr passed)))
        (cl-return-from gptel-loop-evaluation (cons nil (cdr passed)))))))

(defun gptel-loop-meta (execution-result evaluation-result)
  "Meta-Loop - self-improvement via distilled experience."
  (when (get 'auto-improve 'workflow)
    (let ((distilled (gptel-distill execution-result evaluation-result)))
      (gptel-memory-propose distilled)
      ;; Human approval workflow (from mementum)
      (when (gptel-human-approve-p distilled)
        (gptel-memory-commit distilled "knowledge")))))
```

---

## Implementation Roadmap

### Phase 1: Foundation (Week 1-2)
1. Implement `gptel-circuit-breaker` with configurable providers
2. Add checkpoint/restore to experiment execution
3. Set up `gptel-tool-log` with SQLite audit trail
4. Implement three-tier watchdog architecture

### Phase 2: Memory (Week 3-4)
1. Add `gptel-session-db` with FTS5 for continuity
2. Implement feed-forward memory protocol from mementum
3. Add self-wiring knowledge graph to memory system
4. Create knowledge page generation with approval workflow

### Phase 3: Intelligence (Week 5-6)
1. Implement P(success) confidence tracking
2. Add verification gates before commits
3. Implement EDN statecharts for workflow FSM
4. Add trajectory-aware metrics logging

### Phase 4: Evolution (Week 7-8)
1. Implement think-in-code context reduction
2. Add lambda notation preambles for attention anchoring
3. Implement provider fallback chains with escalation queues
4. Add three-loop meta-learning architecture

---

## Related

- [[knowledge/research-orchestration]] — Daemon orchestration patterns
- [[knowledge/agent-error-recovery]] — Error handling and recovery strategies
- [[knowledge/memory-synthesis]] — Memory and knowledge page patterns
- [[knowledge/evaluation-metrics]] — Trajectory metrics and success tracking
- [[knowledge/self-evolution]] — Self-improvement and meta-learning patterns
- [[knowledge/context-compression]] — Context reduction techniques
- [[knowledge/provider-fallback]] — Multi-provider architectures

---

**Meta-learning:** Research quality measured by downstream experiment success. Track research→experiment→outcome linkage via `research-hash` in `results.tsv` for feedback loop closure.

**Hash:** 9bbb457e1e0ddd347fecd8b40cbf8246031ea0ca
**Last Updated:** 2026-05-22 12:10
**Sources:** 8 GitHub repos (davidwuchn/*), 3 arXiv papers, 2 external blogs, 1 Azure architecture guide, 1 NVIDIA guide
```