<!--
Synthesis verification:
- Confidence: 24%
- Sources: 6 memories
- Warnings: No code examples or concrete references, Content does not mention topic 'research-research-persisted'
- Auto-approved: yes (flagged)
--->

---
title: Research Persistence Patterns for AI Agent Systems
status: active
category: knowledge
tags: [research, persistence, self-evolution, agent-architecture, circuit-breaker, checkpoint]
---

# Research Persistence Patterns for AI Agent Systems

## Overview

This knowledge page synthesizes research findings on persisting agent research and memory across sessions, with focus on patterns that enable self-evolution, failure recovery, and knowledge continuity. The findings come from multiple research sessions targeting Emacs AI agent modules with varying retention rates (0%–33%), indicating the importance of quality filtering and structured output formats.

## Core Principles

### Research-Experiment Feedback Loop

The most critical pattern discovered: every experiment row must include a non-none research hash so AutoTTS can link outcomes back to the research trace.

```elisp
;; Research hash tracking structure
(defvar gptel-research-hash nil
  "Hash of the research findings used for current experiment run.")

(defvar gptel-research-trace '()
  "Trace of research sessions leading to current state.")

(defun gptel-research--persist-hash (hash targets outcome)
  "Persist research hash with metadata for future linking."
  (push `(,hash ,targets ,outcome ,(current-time)) gptel-research-trace))
```

### Structured Machine-Parseable Output

Research outputs must be structured with source, technique, apply-to-us, and verification fields:

```elisp
(defstruct gptel-research-finding
  (source nil :read-only)
  (technique nil :read-only)
  (apply-to-us nil :read-only)
  (difficulty nil :read-only)  ; HARD/MEDIUM/EASY
  (impact nil :read-only)     ; HIGH/MEDIUM/LOW
  (verification nil :read-only))
```

---

## Tier 1: Directly Applicable Patterns (Emacs Lisp + AI Agents)

### 1. Circuit Breaker + Checkpoint/Restore Pattern

**Source**: efrit (davidwuchn/efrit)

Circuit breaker monitors failure rates per provider, transitions through CLOSED→OPEN→HALF-OPEN states to prevent cascading failures. Checkpoint/restore stores state snapshots before risky operations.

**Implementation**:

```elisp
(defvar gptel-circuit-breaker-state
  '((openai . (:failures 0 :successes 0 :last-failure nil :state closed))
    (anthropic . (:failures 0 :successes 0 :last-failure nil :state closed))))

(defcustom gptel-circuit-breaker-threshold 5
  "Consecutive failures before opening circuit."
  :type 'integer)

(defcustom gptel-checkpoint-dir
  (expand-file-name ".gptel/checkpoints/" user-emacs-directory)
  "Directory for state checkpoint snapshots.")

(defun gptel-circuit-breaker--record (provider success)
  "Record outcome and transition circuit state if needed."
  (let* ((state (assoc provider gptel-circuit-breaker-state))
         (data (cdr state))
         (current-state (plist-get data :state)))
    (cond
     ((eq current-state 'open)
      ;; After timeout, transition to half-open
      (when (> (float-time (time-since (plist-get data :last-failure))) 60)
        (setf (plist-get data :state) 'half-open)))
     ((eq current-state 'half-open)
      (if success
          (setf (plist-get data :state) 'closed
                (plist-get data :failures) 0)
        (setf (plist-get data :state) 'open
              (plist-get data :last-failure) (current-time))))
     (t ;; CLOSED state
      (if success
          (setf (plist-get data :successes) (1+ (plist-get data :successes))
                (plist-get data :failures) 0)
        (setf (plist-get data :failures) (1+ (plist-get data :failures))
              (plist-get data :last-failure) (current-time))
        (when (>= (plist-get data :failures) gptel-circuit-breaker-threshold)
          (setf (plist-get data :state) 'open)))))))

(defun gptel-circuit-breaker--can-proceed (provider)
  "Check if circuit allows requests to proceed."
  (let* ((state (assoc provider gptel-circuit-breaker-state))
         (data (cdr state)))
    (not (eq (plist-get data :state) 'open))))

(defun gptel-checkpoint-save (experiment-id data)
  "Save checkpoint before risky operation."
  (let* ((checkpoint-file (expand-file-name
                           (format "%s-%s.el" experiment-id (format-time-string "%Y%m%d-%H%M%S"))
                           gptel-checkpoint-dir)))
    (make-directory gptel-checkpoint-dir t)
    (with-temp-file checkpoint-file
      (prin1 `(defvar ,(intern experiment-id) ',data) (current-buffer)))
    checkpoint-file))

(defun gptel-checkpoint-restore (experiment-id)
  "Restore from most recent checkpoint."
  (let* ((checkpoints (directory-files gptel-checkpoint-dir t
                                       (format "^%s-" (regexp-quote experiment-id))))
         (latest (car (sort checkpoints #'file-newer-than-file-p))))
    (when latest
      (with-temp-buffer
        (insert-file-contents latest)
        (read (current-buffer))))))
```

### 2. Tool Receipts for Audit Trail

**Source**: efrit (35+ tools with security controls)

Every tool execution generates structured metadata: `(input-hash output-hash timestamp duration tool-name)`. Shell commands have allowed/forbidden pattern matching.

**Implementation**:

```elisp
(require 'sqlite)
(require 'secure-hash)

(defvar gptel-tool-log-db
  (expand-file-name ".gptel/tool-log.db" user-emacs-directory))

(defun gptel-tool-log--init ()
  "Initialize tool log database."
  (make-directory (file-name-directory gptel-tool-log-db) t)
  (sqlite-execute gptel-tool-log-db
    "CREATE TABLE IF NOT EXISTS tool_receipts (
       id INTEGER PRIMARY KEY AUTOINCREMENT,
       tool_name TEXT NOT NULL,
       input_hash TEXT NOT NULL,
       output_hash TEXT,
       timestamp REAL NOT NULL,
       duration_ms INTEGER,
       success INTEGER,
       session_id TEXT
     )")
  (sqlite-execute gptel-tool-log-db
    "CREATE INDEX IF NOT EXISTS idx_tool_name ON tool_receipts(tool_name)")
  (sqlite-execute gptel-tool-log-db
    "CREATE INDEX IF NOT EXISTS idx_session ON tool_receipts(session_id)"))

(defun gptel-tool-log--record (tool-name input output start-time success)
  "Record tool execution with structured metadata."
  (let* ((input-hash (secure-hash 'sha256 (prin1-to-string input)))
         (output-hash (and output (secure-hash 'sha256 (prin1-to-string output))))
         (duration-ms (floor (* 1000 (float-time (time-since start-time)))))
         (timestamp (float-time)))
    (sqlite-execute gptel-tool-log-db
      (format "INSERT INTO tool_receipts (tool_name, input_hash, output_hash, timestamp, duration_ms, success, session_id)
              VALUES ('%s', '%s', %s, %f, %d, %d, '%s')"
              tool-name input-hash
              (if output-hash (format "'%s'" output-hash) "NULL")
              timestamp duration-ms
              (if success 1 0)
              gptel-session-id))))

;; Shell command security patterns
(defcustom gptel-shell-allowed-patterns
  '("^git " "^find " "^rg " "^fd " "^emacsclient ")
  "Allowed shell command patterns.")

(defcustom gptel-shell-forbidden-patterns
  '("rm -rf /" "dd if=" ":(){ :|:& };:" "mkfs" "cryptsetup")
  "Forbidden shell command patterns.")

(defun gptel-shell--validate (command)
  "Validate shell command against security patterns."
  (or (seq-some (lambda (pat) (string-match pat command))
                gptel-shell-allowed-patterns)
      (seq-some (lambda (pat) (string-match pat command))
                gptel-shell-forbidden-patterns)
      (signal 'gptel-shell-command-blocked
              (format "Command blocked: %s" command))))
```

### 3. Lambda Notation + Mathematical Attention Magnets

**Source**: nucleus

Greek letters and math symbols as compressed prompt preamble: `λ engage(nucleus). [phi fractal euler tao pi mu ∃ ∀]`. Primes formal reasoning patterns.

**Implementation**:

```elisp
(defvar gptel-nucleus-preamble-map
  '(("λ engage(nucleus)" . :mode-engage)
    ("[φ ψ Δ λ]" . :mode-formal-reasoning)
    ("[Δ λ Ω ∞/0]" . :mode-change-analysis)
    ("[ε/φ Σ/μ c/h]" . :mode-error-analysis)
    ("[∃ ∀]" . :mode-exists-forall)
    ("OODA" . :mode-ooda-loop)
    ("REPL" . :mode-repl-loop)))

(defcustom gptel-system-prompt-nucleus-lambda
  "λ engage(gptel). [φ ψ Δ λ] | [Δ λ Ω ∞/0 | ε/φ Σ/μ c/h] | OODA"
  "Lambda notation preamble for system prompts.")

(defun gptel-nucleus--build-preamble (&rest symbols)
  "Build nucleus-style preamble from symbols."
  (mapconcat (lambda (sym)
               (or (car (rassoc sym gptel-nucleus-preamble-map))
                   (format "[%s]" sym)))
             symbols " "))

;; EDN statecharts for workflow states
(defvar gptel-workflow-state-example
  "{:phase :planning
    :actions [research analyze synthesize]
    :confidence 0.75
    :constraints {:max-tokens 4000
                  :timeout-seconds 120}}")
```

### 4. Think-in-Code Context Reduction

**Source**: context-mode

Instead of dumping raw file reads (700KB), execute analysis script that returns only result (3.6KB). 98% context reduction via sandbox tools.

**Implementation**:

```elisp
(defcustom gptel-sandbox-max-context-kb 50
  "Maximum context size in KB before triggering analysis script.")

(defvar gptel-sandbox-analysis-scripts
  '(("git-diff" . gptel-sandbox--analyze-git-diff)
    ("file-stats" . gptel-sandbox--analyze-file-stats)
    ("module-complexity" . gptel-sandbox--analyze-module-complexity)))

(defun gptel-sandbox-execute (script-name input-data)
  "Execute analysis script in isolated context, return structured result."
  (let* ((script-fn (cdr (assoc script-name gptel-sandbox-analysis-scripts))))
    (if script-fn
        (funcall script-fn input-data)
      (error "Unknown analysis script: %s" script-name))))

(defun gptel-sandbox--analyze-git-diff (repo-path)
  "Return compressed git diff analysis."
  (let* ((diff-output (shell-command-to-string
                       (format "git -C %s diff --stat HEAD~10..HEAD" repo-path)))
         (lines (split-string diff-output "\n" t))
         (stats (seq-take-while (lambda (l) (string-match "^ " l)) lines)))
    `(:files-changed ,(length stats)
      :additions ,(seq-reduce (lambda (acc l)
                                (let ((added (when (string-match "\\+[0-9]+" l)
                                               (string-to-number (match-string 0 l)))))
                                  (+ acc (or added 0))))
                              stats 0)
      :deletions ,(seq-reduce (lambda (acc l)
                                (let ((deleted (when (string-match "\\-[0-9]+" l)
                                                  (string-to-number (match-string 0 l)))))
                                  (+ acc (or deleted 0))))
                              stats 0))))

(defun gptel-sandbox--analyze-module-complexity (modules-list)
  "Return module complexity analysis without full file contents."
  (mapcar (lambda (module-path)
            (let* ((lines (when (file-exists-p module-path)
                           (with-temp-buffer
                             (insert-file-contents module-path nil 0 10000)
                             (split-string (buffer-string) "\n" t))))
                   (defuns (seq-count (lambda (l) (string-match "^;;;" l)) lines)))
              `(:path ,module-path
                :estimated-lines ,(or (car (last lines)) 0)
                :defun-markers ,defuns)))
          modules-list))
```

### 5. Session Continuity via FTS5

**Source**: context-mode

Every edit, git op, task, error tracked in SQLite with FTS5. When context compacts, retrieves only relevant events via BM25 search—not dumps raw data.

**Implementation**:

```elisp
(require 'sqlite)

(defvar gptel-session-db
  (expand-file-name ".gptel/session.db" user-emacs-directory))

(defun gptel-session-db--init ()
  "Initialize session continuity database with FTS5."
  (make-directory (file-name-directory gptel-session-db) t)
  (sqlite-execute gptel-session-db
    "CREATE TABLE IF NOT EXISTS session_events (
       id INTEGER PRIMARY KEY AUTOINCREMENT,
       session_id TEXT NOT NULL,
       timestamp REAL NOT NULL,
       event_type TEXT NOT NULL,
       data TEXT NOT NULL
     )")
  (sqlite-execute gptel-session-db
    "CREATE VIRTUAL TABLE IF NOT EXISTS session_fts USING fts5(
       event_type, data, content='session_events', content_rowid='id')")
  (sqlite-execute gptel-session-db
    "CREATE TRIGGER IF NOT EXISTS session_ai AFTER INSERT ON session_events BEGIN
       INSERT INTO session_fts(rowid, event_type, data) VALUES (new.id, new.event_type, new.data);
     END"))

(defun gptel-session--track-event (event-type data)
  "Track session event for continuity across compactions."
  (sqlite-execute gptel-session-db
    (format "INSERT INTO session_events (session_id, timestamp, event_type, data)
             VALUES ('%s', %f, '%s', '%s')"
            gptel-session-id (float-time) event-type
            (json-encode data))))

(defun gptel-session--retrieve-relevant (query &optional limit)
  "Retrieve relevant events via FTS5 BM25 search."
  (let* ((results (sqlite-select gptel-session-db
                   (format "SELECT session_events.*, bm25(session_fts) as rank
                            FROM session_fts
                            JOIN session_events ON session_fts.rowid = session_events.id
                            WHERE session_fts MATCH '%s'
                            ORDER BY rank
                            LIMIT %d"
                           query (or limit 10))
                   :columns '("id" "session_id" "timestamp" "event_type" "data" "rank"))))
    (mapcar (lambda (row)
              (cons (oref (cl-loop for col in '("id" "session_id" "timestamp" "event_type" "data" "rank")
                                   for val in (append row nil)
                                   collect (cons col val))
                          'data)
                    (json-read-from-string (elt row 4))))
            results)))
```

### 6. Feed-Forward Memory Protocol

**Source**: mementum

Three storage types (working memory/state.md, memories <200 words, synthesized knowledge). Human governance: AI proposes, human approves, AI commits.

**Implementation**:

```elisp
(defvar gptel-memory-types
  '(:working  ; state.md - current context
    :memory   ; <200 words - short-term facts
    :knowledge)) ; synthesized - long-term patterns

(defcustom gptel-memory-synthesize-threshold 10
  "Number of similar outcomes before synthesizing knowledge.")

(defun gptel-memory--synthesize (pattern-data)
  "Synthesize new knowledge from repeated patterns."
  (when (>= (length pattern-data) gptel-memory-synthesize-threshold)
    (let* ((outcomes (mapcar #'car pattern-data))
           (success-rate (/ (seq-count #'identity outcomes)
                           (float (length outcomes))))
           (common-patterns (gptel-memory--extract-common pattern-data)))
      `(:pattern ,common-patterns
        :success-rate ,success-rate
        :sample-size ,(length pattern-data)
        :synthesized ,(format "When %s, success rate is %.0f%%"
                              common-patterns
                              (* 100 success-rate))))))

(defun gptel-memory--human-approval-workflow (proposed-knowledge)
  "Human governance workflow for memory synthesis."
  (let* ((proposal-file (expand-file-name "memory-proposal.org"
                                           gptel-checkpoint-dir)))
    (with-temp-file proposal-file
      (princ "* Proposed Memory Synthesis\n\n")
      (princ (format "%s\n\n" proposed-knowledge))
      (princ "* Action: Approve, Reject, or Modify\n"))
    ;; Return nil to signal human review needed
    ;; In production, hook into notification system
    (message "Memory proposal written to %s - awaiting approval" proposal-file)
    nil))
```

---

## Tier 2: Agent Architecture Patterns

### 7. Three-Tier Watchdog Architecture

**Source**: gastown

Systematized lifecycle management via three tiers: Witness (session lifecycle), Deacon (continuous background patrol), Dogs (dispatched workers). Convoy system bundles work items with autonomous stall detection.

**Implementation**:

```elisp
;; Three-tier watchdog system
(defstruct gptel-watchdog
  (type nil)   ; :witness :deacon :dog
  (name nil)
  (interval nil)
  (handler nil))

(defvar gptel-watchdogs '())

(defun gptel-watchdog--register (type name interval handler)
  "Register a watchdog in the system."
  (push (make-gptel-watchdog
         :type type
         :name name
         :interval interval
         :handler handler)
        gptel-watchdogs))

(defun gptel-watchdog--witness ()
  "Witness: monitors session lifecycle health."
  (let* ((session-age (float-time (time-since gptel-session-start)))
         (inactive-time (float-time (time-since gptel-last-activity)))
         (stalled-p (> inactive-time 300))) ; 5 minutes
    (when stalled-p
      (gptel-watchdog--escalate :stalled-session session-age))))

(defun gptel-watchdog--deacon ()
  "Deacon: continuous background patrol."
  (dolist (task gptel-active-tasks)
    (when (gptel-task--stalled-p task)
      (gptel-watchdog--dispatch-dog task))))

(defun gptel-watchdog--dispatch-dog (stalled-task)
  "Dispatch a dog to handle stalled task."
  (push (list 'gptel-dog-rescue stalled-task (current-time))
        gptel-watchdogs)
  (gptel-watchdog--run-dog stuck-task))

(defun gptel-watchdog--escalate (issue data)
  "Escalate issue based on severity."
  (pcase issue
    (:stalled-session (message "Session stalled for %.0f seconds" data))
    (:critical-failure (gptel-circuit-breaker--record gptel-current-provider nil))
    (_ (message "Watchdog alert: %s - %s" issue data))))

;; Convoy system for bundling work
(defvar gptel-convoy-bundle-size 5
  "Number of work items per convoy.")

(defun gptel-convoy--create (tasks)
  "Bundle tasks into a convoy with stall detection."
  (let* ((bundled (seq-take tasks gptel-convoy-bundle-size)))
    `(:convoy-id ,(format "convoy-%s" (format-time-string "%Y%m%d-%H%M%S"))
      :tasks ,bundled
      :created ,(current-time)
      :stall-threshold 120)))
```

### 8. Genesis Agent Self-Verification Engine

**Source**: genesis-agent

Genesis uses 66 deterministic checks where "the LLM proposes — the machine verifies." AST parsing, exit codes, import resolution, file validation, module signatures.

**Implementation**:

```elisp
(defvar gptel-verification-gates '()
  "List of verification functions to run before trusting output.")

(defmacro gptel-defverification (name arglist &rest body)
  "Define a verification gate."
  (declare (indent defun))
  `(progn
     (defun ,name ,arglist ,@body)
     (push ',name gptel-verification-gates)))

(gptel-defverification gptel-verify-elisp-syntax (code)
  "Verify Emacs Lisp syntax before applying changes."
  (condition-case err
      (progn
        (read code)
        t)
    (error
     (message "Syntax verification failed: %s" err)
     nil)))

(gptel-defverification gptel-verify-byte-compile (file-path)
  "Verify file compiles without errors."
  (zerop (apply #'call-process "emacs" nil nil nil
                "--batch" "--eval"
                (format "(condition-case e (progn (byte-compile-file %S) t) (error (message \"Compile error: %s\" e) nil))"
                        file-path))))

(gptel-defverification gptel-verify-module-signature (module exports)
  "Verify expected exports are present in module."
  (let* ((actual-exports (gptel-module--extract-exports module)))
    (seq-every-p (lambda (exp) (member exp actual-exports)) exports)))

(defun gptel-verify-all (proposed-change)
  "Run all verification gates on proposed change."
  (let* ((results (mapcar (lambda (gate)
                            (cons gate (funcall gate proposed-change)))
                          gptel-verification-gates))
         (failures (seq-filter (lambda (r) (not (cdr r))) results)))
    (if failures
        (progn
          (message "Verification failed: %s" failures)
          nil)
      (progn
        (message "All %d gates passed" (length results))
        t))))
```

### 9. Worktree Isolation for Agent Runs

**Source**: symphony

Isolated workspaces per task, workflow policy in-repo. Per-issue git worktrees prevent cross-contamination.

**Implementation**:

```elisp
(defcustom gptel-worktree-base-dir
  (expand-file-name ".gptel/worktrees/" user-emacs-directory)
  "Base directory for isolated experiment worktrees.")

(defun gptel-worktree--create (experiment-id)
  "Create isolated worktree for experiment."
  (let* ((worktree-path (expand-file-name experiment-id gptel-worktree-base-dir))
         (branch-name (format "experiment/%s" experiment-id)))
    (make-directory worktree-path t)
    ;; Link to main repo
    (shell-command
     (format "cd %s && git init && git remote add origin %s"
             worktree-path
             (expand-file-name user-emacs-directory)))
    worktree-path))

(defun gptel-worktree--cleanup (experiment-id)
  "Clean up worktree after experiment."
  (let* ((worktree-path (expand-file-name experiment-id gptel-worktree-base-dir)))
    (when (file-directory-p worktree-path)
      (delete-directory worktree-path t))))
```

### 10. Multi-Agent Workspace Orchestration

**Source**: gastown

Git-backed hooks for persistent work state. Polecats (worker agents), Hooks (persistent storage), Beads ledger. Scales to 20-30 agents with coordination.

**Implementation**:

```elisp
(defvar gptel-hooks-dir
  (expand-file-name ".gptel/hooks/" user-emacs-directory))

(defstruct gptel-bead
  (type nil)   ; :task :status :handoff
  (agent-id nil)
  (timestamp nil)
  (data nil))

(defun gptel-bead--create (type agent-id data)
  "Create immutable bead (work state) for ledger."
  (let* ((bead (make-gptel-bead
                :type type
                :agent-id agent-id
                :timestamp (current-time)
                :data data))
         (bead-id (format "bead-%s-%s" agent-id (format-time-string "%Y%m%d-%H%M%S")))
         (bead-file (expand-file-name bead-id gptel-hooks-dir)))
    (make-directory gptel-hooks-dir t)
    (with-temp-file bead-file
      (prin1 bead (current-buffer)))
    bead-id))

(defun gptel-bead--ledger-query (agent-id &optional type limit)
  "Query beads ledger for agent's work history."
  (let* ((bead-files (directory-files gptel-hooks-dir t "^bead-"))
         (agent-beads (seq-filter (lambda (f)
                                    (let* ((bead (with-temp-buffer
                                                  (insert-file-contents f)
                                                  (read (current-buffer)))))
                                      (and (string= (gptel-bead-agent-id bead) agent-id)
                                           (or (null type)
                                               (eq (gptel-bead-type bead) type)))))
                                  bead-files)))
    (seq-take (sort agent-beads (lambda (a b)
                                 (file-newer-than-file-p a b)))
              (or limit 50))))
```

---

## Tier 3: External Research Patterns

### 11. Agent Design Pattern Catalogue

**Source**: arXiv:2405.10467 — 18 Architectural Patterns

| Pattern | Context | Forces | Trade-off |
|---------|---------|--------|-----------|
| ReAct | Dynamic tool use | Reasoning traces needed | Token overhead |
| CoT | Multi-step reasoning | Explicit justification | Latency |
| Toolformer | Tool synthesis | Unknown tool needs | Quality variance |
| Reflexion | Self-reflection | Error recovery needed | Overfitting risk |

**Implementation**:

```elisp
(defvar gptel-pattern-decision-matrix
  '((:task-type . ((:single-step . :direct-call)
                   (:multi-step . :react)
                   (:reasoning-heavy . :cot)
                   (:tool-synthesis . :toolformer)
                   (:error-prone . :reflexion)))))

(defun gptel-pattern-select (task-type)
  "Select appropriate orchestration pattern based on task."
  (or (cdr (assq task-type gptel-pattern-decision-matrix))
      :react)) ; default
```

### 12. Azure AI Agent Orchestration Patterns

**Source**: Azure Architecture Guide

| Level | Use When | Implementation |
|-------|----------|----------------|
| 1: Direct call | Single-step, prompt engineering suffices | Simple function call |
| 2: Agent + tools | Varied queries, dynamic tool use | gptel-agent with tool registry |
| 3: Sequential | Linear dependencies, progressive refinement | Pipeline with checkpoints |
| 4: Concurrent | Independent perspectives, fan-out/fan-in | Parallel task dispatch |
| 5: Hierarchical | Master-slave coordination, complex delegation | Multi-level controller |

### 13. AI Agent Error Recovery Patterns

**Source**: AI Agents Blog

| Pattern | Description | Emacs Implementation |
|---------|-------------|---------------------|
| Exponential Backoff | Retry delays increase exponentially with jitter | `gptel-retry--with-backoff` |
| Circuit Breaker | Open circuit after N failures | `gptel-circuit-breaker-*` |
| Checkpoint-and-Resume | Save state at each step | `gptel-checkpoint-*` |
| Fallback Chains | Provider A → B → C | `gptel-provider-chain` |
| Escalation Queues | Failed tasks to human review | `gptel-escalation-queue` |

**Implementation**:

```elisp
(defcustom gptel-provider-chain '(openai anthropic ollama)
  "Fallback chain of providers.")

(defcustom gptel-retry-base-delay 1.0
  "Base delay in seconds for exponential backoff.")

(defcustom gptel-retry-max-delay 60.0
  "Maximum delay cap for backoff.")

(defcustom gptel-retry-jitter 0.5
  "Jitter factor for randomization.")

(defun gptel-retry--with-backoff (max-attempts fn &rest args)
  "Retry function with exponential backoff and jitter."
  (let* ((attempt 0)
         (delay gptel-retry-base-delay))
    (while (< attempt max-attempts)
      (condition-case err
          (return (apply fn args))
        (error
         (setq attempt (1+ attempt))
         (when (< attempt max-attempts)
           (let* ((jitter (* delay gptel-retry-jitter (random 1.0)))
                  (actual-delay (+ delay jitter)))
             (message "Retry %d/%d after %.1fs: %s"
                      attempt max-attempts actual-delay err)
             (sleep-for actual-delay)
             (setq delay (min (* delay 2) gptel-retry-max-delay)))))))
    (signal 'gptel-retry-exhausted (list max-attempts))))

(defun gptel-provider-chain--call (prompt)
  "Call providers in fallback chain until success."
  (dolist (provider gptel-provider-chain)
    (condition-case err
        (let* ((fn (intern (format "gptel-call-%s" provider))))
          (return (funcall fn prompt)))
      (error
       (message "Provider %s failed: %s, trying next..." provider err)
       (gptel-circuit-breaker--record provider nil)))))
```

### 14. DEGRADED State Circuit Breaker

**Source**: Hannecke Medium article

Five failure categories need different handling. DEGRADED state between CLOSED/OPEN allows graceful degradation.

**Implementation**:

```elisp
(defvar gptel-failure-categories
  '(:hard           ; Hard failures (network, auth)
    :structural     ; Module loading, dependencies
    :semantic       ; Logic errors, wrong outputs
    :behavioral     ; Side effects, timing issues
    :resource))     ; Memory, CPU, tokens

(defvar gptel-circuit-degraded-levels
  '(:l1-disable-risky   ; Disable file write, shell exec
    :l2-add-review      ; Add human review flag
    :l3-conservative))  ; Conservative mode, minimal tools

(defun gptel-circuit-breaker--degraded (provider failure-category)
  "Transition to degraded state based on failure category."
  (let* ((state (cdr (assoc provider gptel-circuit-breaker-state)))
         (level (case failure-category
                  (:hard :l3-conservative)
                  (:structural :l2-add-review)
                  (:semantic :l1-disable-risky)
                  (:behavioral :l1-disable-risky)
                  (:resource :l2-add-review))))
    (setf (plist-get state :degraded-level) level)
    (message "Degraded to %s for %s" level provider)))

(defun gptel-circuit-breaker--re-enable (provider level)
  "Gradually re-enable capabilities (5% → 20% → 50% → 100%)."
  (let* ((state (cdr (assoc provider gptel-circuit-breaker-state)))
         (traffic-percentage (pcase level
                                (:l1 50)
                                (:l2 20)
                                (:l3 5))))
    (when (> (random 100) traffic-percentage)
      (signal 'gptel-circuit-throttled
              (format "Traffic throttled at %d%%" traffic-percentage)))))
```

### 15. Hybrid Search Fusion (Vector + BM25)

**Source**: gbrain

P@5 49.1% via hybrid search combining vector embeddings + BM25 keyword + reciprocal-rank fusion.

**Implementation**:

```elisp
(defcustom gptel-hybrid-search-alpha 0.5
  "Weight for vector search (1-alpha for BM25).")

(defun gptel-hybrid-search (query &optional top-k)
  "Combine vector and BM25 search with reciprocal rank fusion."
  (let* ((vector-results (gptel-vector-search query top-k))
         (bm25-results (gptel-bm25-search query top-k))
         (fused (gptel-rrf-fuse vector-results bm25-results)))
    (seq-take fused (or top-k 10))))

(defun gptel-rrf-fuse (list-a list-b &optional k)
  "Reciprocal Rank Fusion: RRF(d) = 1 / (k + rank(d))."
  (let* ((k (or k 60))
         (scores (make-hash-table :test 'equal)))
    (cl-loop for item in list-a
             for rank from 1
             do (incf (gethash item scores 0)
                      (/ 1.0 (+ k rank))))
    (cl-loop for item in list-b
             for rank from 1
             do (incf (gethash item scores 0)
                      (/ 1.0 (+ k rank))))
    (sort (cl-loop for (item . score) in (hash-table->alist scores)
                   collect (cons score item))
          (lambda (a b) (> (car a) (car b))))))

(defun gptel-bm25-search (query &optional top-k)
  "BM25 keyword search using ripgrep."
  (let* ((terms (split-string query))
         (rg-command (format "rg -l '%s' %s"
                             (mapconcat #'identity terms "\\|")
                             gptel-modules-dir)))
    (seq-take (split-string (shell-command-to-string rg-command) "\n" t)
              (or top-k 10))))
```

### 16. Self-Wiring Knowledge Graph

**Source**: gbrain

Every page write extracts entity references and creates typed links with zero LLM calls. +31.4 P@5 lift over vector-only RAG.

**Implementation**:

```elisp
(defvar gptel-entity-types
  '(person location organization project module function concept))

(defvar gptel-entity-link-pattern
  "\\[\\[\\([^]]+\\)\\]\\]")

(defstruct gptel-entity-edge
  (from nil)
  (to nil)
  (type nil)    ; attended, works_at, uses, calls, etc.
  (weight 1.0))

(defvar gptel-knowledge-graph (make-hash-table :test 'equal))

(defun gptel-entity--extract (content)
  "Extract entity references with zero LLM calls."
  (let* ((matches (s-matched-positions-all gptel-entity-link-pattern content))
         (entities (mapcar (lambda (pos)
                            (substring content (car pos) (cdr pos)))
                          matches)))
    entities))

(defun gptel-entity--auto-link (from-page content)
  "Auto-create typed edges when page is written."
  (let* ((entities (gptel-entity--extract content))
         (edges (mapcar (lambda (entity)
                        (let* ((type (gptel-entity--infer-type entity)))
                          (make-gptel-entity-edge
                           :from from-page
                           :to entity
                           :type type)))
                      entities)))
    (dolist (edge edges)
      (let* ((key (format "%s->%s"
                          (gptel-entity-edge-from edge)
                          (gptel-entity-edge-to edge))))
        (puthash key edge gptel-knowledge-graph)))))
```

---

## Daemon Orchestration Patterns

### Research Daemon Failure Handling

**Critical Pattern**: Guard daemon orchestration boundaries; if researcher daemon disappears after being observed, fail fast and fall back instead of waiting until global timeout.

**Implementation**:

```elisp
(defvar gptel-research-daemon-timeout 300
  "Seconds before research daemon is considered unresponsive.")

(defvar gptel-research-daemon-pid nil)

(defun gptel-research-daemon--start ()
  "Start research daemon with watchdog."
  (let* ((pid (start-process "gptel-research-daemon" "*gptel-research*"
                             "emacs" "--batch" "-l" "gptel-auto-workflow-research.el"))
         (start-time (current-time)))
    (setq gptel-research-daemon-pid pid)
    (set-process-sentinel pid (lambda (p s)
                                (message "Research daemon terminated: %s" s)
                                (gptel-research-daemon--handle-exit)))
    (gptel-watchdog--register :deacon "research-daemon-health"
                              60
                              (lambda ()
                                (when (> (float-time (time-since start-time))
                                       gptel-research-daemon-timeout)
                                  (gptel-research-daemon--fail-fast))))))

(defun gptel-research-daemon--fail-fast ()
  "Fail fast when daemon disappears instead of waiting for global timeout."
  (message "Research daemon unresponsive - triggering local fallback")
  (gptel-research--local-fallback))
```

### Missing Research File as Pipeline Defect

Research files must exist with valid hash — treat missing files as pipeline defect, not successful empty run.

```elisp
(defun gptel-research--validate-findings-file (hash)
  "Validate research findings file exists and is parseable."
  (let* ((file (expand-file-name (format "research-%s.org" hash)
                                gptel-checkpoint-dir)))
    (if (and (file-exists-p file)
             (> (file-attribute-size (file-attributes file)) 100))
        (progn
          (message "Research findings validated: %s" hash)
          t)
      (progn
        (message "ERROR: Research file missing or empty for hash %s" hash)
        nil)))

(defun gptel-research--local-fallback ()
  "Fallback when no fresh external findings available."
  (list :source "local-fallback"
        :reason "external-research-unavailable"
        :directives
        (list "Preserve feedback loop with research hash in experiment rows"
              "Treat missing research files as pipeline defect"
              "Prefer structured machine-parseable outputs"
              "Prioritize observable self-evolution via results.tsv")))
```

---

## Module Complexity Reference

Top modules by lines requiring special attention for nil-safety patterns:

```
58031 total lines in lisp/modules/
├── 5822 gptel-auto-workflow-evolution.el    (HIGH COMPLEXITY - needs guards)
├── 2698 gptel-auto-workflow-strategic.el     (MEDIUM - needs nil-safety)
├── 2431 gptel-tools-agent-prompt-build.el    (MEDIUM - needs validation)
├── 1742 gptel-auto-workflow-research-benchmark.el
```

---

## Actionable Patterns Checklist

### High Priority (Do First)

- [ ] Implement `gptel-circuit-breaker-*` with CLOSED→DEGRADED→OPEN→HALF-OPEN states
- [ ] Add `gptel-checkpoint-save/restore` for experiment state persistence
- [ ] Implement structured research output with source/technique/apply-to-us fields
- [ ] Add research hash tracking to every experiment row
- [ ] Implement `gptel-tool-log--record` with SQLite audit trail

### Medium Priority

- [ ] Implement `gptel-sandbox-execute` for 98% context reduction
- [ ] Add `gptel-session-db--init` with FTS5 for session continuity
- [ ] Implement `gptel-verify-*` gates before trusting LLM output
- [ ] Add hybrid search fusion (vector + BM25 + RRF)
- [ ] Implement three-tier watchdog (Witness/Deacon/Dogs)

### Lower Priority

- [ ] Lambda notation preamble library for prompts
- [ ] Worktree isolation for experiment runs
- [ ] Self-wiring knowledge graph with typed edges
- [ ] Provider fallback chain (OpenAI → Anthropic → Ollama)
- [ ] Human governance workflow for memory synthesis

---

## Related

- [[agent-architecture]] — Agent design patterns and orchestration
- [[circuit-breaker]] — Failure handling and recovery patterns
- [[checkpoint-restore]] — State persistence and recovery
- [[context-reduction]] — Context window optimization techniques
- [[knowledge-synthesis]] — Feed-forward knowledge protocols
- [[evaluation-metrics]] — Trajectory-aware evaluation
- [[self-evolution]] — Self-modifying verification and meta-learning

---

## Meta-learning

Research quality is measured by downstream experiment success. Prioritize patterns with:
1. Concrete implementation sketches
2. Measurable success criteria
3. Observable feedback loops
4. Integration with existing modules

Retention rates from research sessions (0%–33%) indicate the need for stricter quality filtering and structured output formats.

---
*Generated from synthesized research sessions 2026-05-20 to 2026-05-25*
*Research hash: synthesized-e438c226-9bbb457e-9af4a35c*
*Next action: Apply nil-safety patterns to highest-failure modules*