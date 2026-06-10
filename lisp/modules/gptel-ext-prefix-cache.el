;;; gptel-ext-prefix-cache.el --- Prefix-cache-stable prompt architecture for OV5 -*- lexical-binding: t; -*-

;; Part of the Ouroboros V5 self-evolving pipeline.
;; Inspired by DeepSeek-Reasonix prefix-cache stability design.
;;
;; Core invariant: The system-prompt prefix (base prompt + tools + memory)
;; stays byte-stable across experiments so LLM prefix cache stays warm.
;; Never mutate it mid-run — ride the turn tail instead.

;;; Commentary:
;; This module separates experiment prompts into:
;;   - STABLE PREFIX: computed once per run, reused across all experiments
;;   - DYNAMIC SUFFIX: target-specific content that changes per experiment
;;
;; The stable prefix includes:
;;   - Project conventions (AGENTS.md, lambda notation)
;;   - Available tool schemas
;;   - Standing mementum knowledge
;;   - OV5 architecture context
;;
;; The dynamic suffix includes:
;;   - Target file content
;;   - Current hypothesis
;;   - Recent experiment results (last 3)
;;   - Task-specific hints

;;; Code:

(require 'cl-lib)

;; ─── Forward Declarations ───

(declare-function gptel-tool-name "gptel" (tool))
(declare-function gptel-tool-description "gptel" (tool))
(defvar gptel-tools)

(declare-function gptel-auto-workflow--project-root "gptel-tools-agent-benchmark")
(declare-function gptel-auto-workflow--worktree-base-root "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--categorize-target "gptel-auto-workflow-ontology-router")
(declare-function gptel-mementum--recall "gptel-auto-workflow-mementum" (query depth))

;; ─── Customization ───

(defcustom gptel-prefix-cache-enabled t
  "When non-nil, use prefix-cache-stable prompt architecture.
Disabling falls back to monolithic prompt building (legacy behavior)."
  :type 'boolean
  :group 'gptel-tools-agent)

(defcustom gptel-prefix-cache-max-chars 8000
  "Maximum characters for the stable prefix.
Longer prefixes cost more tokens but provide richer context.
Reasonix uses ~4000-8000 chars for REASONIX.md + tool schemas."
  :type 'integer
  :group 'gptel-tools-agent)

(defcustom gptel-prefix-cache-includes-agents-md t
  "When non-nil, include AGENTS.md conventions in stable prefix."
  :type 'boolean
  :group 'gptel-tools-agent)

(defcustom gptel-prefix-cache-includes-tools t
  "When non-nil, include available tool schemas in stable prefix."
  :type 'boolean
  :group 'gptel-tools-agent)

(defcustom gptel-prefix-cache-includes-mementum t
  "When non-nil, include standing mementum knowledge in stable prefix."
  :type 'boolean
  :group 'gptel-tools-agent)

;; ─── State ───

(defvar gptel-prefix-cache--content nil
  "The computed stable prefix content for current run.
Computed once by `gptel-prefix-cache-compute' and reused across experiments.")

(defvar gptel-prefix-cache--valid-p nil
  "Non-nil when `gptel-prefix-cache--content' is valid for current run.")

(defvar gptel-prefix-cache--run-id nil
  "Run ID for which the cache was computed.
Used to detect run changes and invalidate stale cache.")

(defvar gptel-prefix-cache--timestamp nil
  "Timestamp when cache was last computed.")

(defvar gptel-prefix-cache--stats nil
  "Plist of cache statistics: (:size :sections :compute-time-ms).")

;; ─── Core Functions ───

(defun gptel-prefix-cache-compute (&optional run-id force-recompute)
  "Compute the stable prefix cache for current run.
If RUN-ID is provided, associate cache with that run.
If FORCE-RECOMPUTE is non-nil, invalidate existing cache first.
Returns the computed prefix string."
  (when force-recompute
    (gptel-prefix-cache-invalidate))
  (when (or (not gptel-prefix-cache--valid-p)
            (not (equal gptel-prefix-cache--run-id run-id))
            (not gptel-prefix-cache--content))
    (let* ((start-time (current-time))
           (sections nil)
           (add-section (lambda (name content)
                          (when (and content (not (string-empty-p content)))
                            (push (cons name content) sections)))))
      ;; Section 1: Project Identity (AGENTS.md conventions)
      (when gptel-prefix-cache-includes-agents-md
        (funcall add-section "identity" (gptel-prefix-cache--agents-md-summary)))
      ;; Section 2: Tool Schemas
      (when gptel-prefix-cache-includes-tools
        (funcall add-section "tools" (gptel-prefix-cache--tool-schemas-summary)))
      ;; Section 3: Standing Mementum Knowledge
      (when gptel-prefix-cache-includes-mementum
        (funcall add-section "mementum" (gptel-prefix-cache--mementum-summary)))
      ;; Section 4: OV5 Architecture Context
      (funcall add-section "architecture" (gptel-prefix-cache--architecture-context))
      ;; Assemble prefix with section delimiters
      (let* ((assembled (gptel-prefix-cache--assemble-sections sections))
             (truncated (if (> (length assembled) gptel-prefix-cache-max-chars)
                           (concat (substring assembled 0 gptel-prefix-cache-max-chars)
                                   "\n\n[...prefix truncated...]")
                         assembled))
             (compute-ms (* 1000 (float-time (time-since start-time)))))
        (setq gptel-prefix-cache--content truncated
              gptel-prefix-cache--valid-p t
              gptel-prefix-cache--run-id run-id
              gptel-prefix-cache--timestamp (current-time)
              gptel-prefix-cache--stats
              (list :size (length truncated)
                    :sections (length sections)
                    :compute-time-ms compute-ms))
         (message "[prefix-cache] Computed %d sections, %d chars in %.0fms for run %s"
                  (length sections) (length truncated) compute-ms
                  (or run-id "unknown")))))
  gptel-prefix-cache--content)

(defun gptel-prefix-cache-invalidate ()
  "Invalidate the prefix cache.
Call when run ends or when configuration changes."
  (setq gptel-prefix-cache--content nil
        gptel-prefix-cache--valid-p nil
        gptel-prefix-cache--run-id nil
        gptel-prefix-cache--timestamp nil
        gptel-prefix-cache--stats nil)
  (message "[prefix-cache] Invalidated"))

(defun gptel-prefix-cache-get ()
  "Return current stable prefix content, computing if necessary.
Safe to call multiple times — returns cached content after first computation."
  (or (and gptel-prefix-cache--valid-p gptel-prefix-cache--content)
      (gptel-prefix-cache-compute)))

(defun gptel-prefix-cache-stats ()
  "Return cache statistics as a human-readable string."
  (if gptel-prefix-cache--stats
      (format "[prefix-cache] %d chars, %d sections, compute=%.0fms, run=%s, age=%.0fs"
              (plist-get gptel-prefix-cache--stats :size)
              (plist-get gptel-prefix-cache--stats :sections)
              (plist-get gptel-prefix-cache--stats :compute-time-ms)
              (or gptel-prefix-cache--run-id "none")
              (if gptel-prefix-cache--timestamp
                  (float-time (time-since gptel-prefix-cache--timestamp))
                0))
    "[prefix-cache] No cache computed"))

;; ─── Section Builders ───

(defun gptel-prefix-cache--agents-md-summary ()
  "Extract stable conventions from AGENTS.md.
Returns compact summary of lambda notation, key principles, and conventions."
  (let ((file (expand-file-name "AGENTS.md" (gptel-prefix-cache--project-root))))
    (if (not (file-exists-p file))
        ""
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (let ((sections nil))
          ;; Extract lambda notation reference
          (when (re-search-forward "^## Lambda Notation Reference" nil t)
            (let ((start (point)))
              (when (re-search-forward "^---" nil t)
                (push (buffer-substring start (match-beginning 0)) sections))))
          ;; Extract S5 Identity principles
          (goto-char (point-min))
          (when (re-search-forward "^## S5 -- Identity" nil t)
            (let ((start (point)))
              (when (re-search-forward "^---" nil t)
                (push (buffer-substring start (match-beginning 0)) sections))))
          ;; Extract vocabulary
          (goto-char (point-min))
          (when (re-search-forward "^## Vocabulary" nil t)
            (let ((start (point)))
              (when (re-search-forward "^---" nil t)
                (push (buffer-substring start (match-beginning 0)) sections))))
          ;; Compact and return
          (if sections
              (concat "## Project Conventions (AGENTS.md)\n\n"
                      (mapconcat (lambda (s)
                                   (replace-regexp-in-string
                                    "\n\n\n+" "\n\n"
                                    (string-trim s)))
                                 (nreverse sections)
                                 "\n\n")
                      "\n")
            ""))))))

(defun gptel-prefix-cache--tool-schemas-summary ()
  "Return compact summary of available tool schemas.
Lists tool names and brief descriptions only (not full JSON schemas)."
  (if (not (and (boundp 'gptel-tools) gptel-tools))
      ""
    (let ((tool-lines nil))
      (dolist (tool gptel-tools)
        (when tool
          (let* ((name (gptel-tool-name tool))
                 (desc (gptel-tool-description tool))
                 (line (format "- %s: %s"
                               name
                               (truncate-string-to-width desc 100 nil nil "..."))))
            (push line tool-lines))))
      (if tool-lines
          (concat "## Available Tools\n\n"
                  (mapconcat #'identity (nreverse tool-lines) "\n")
                  "\n")
        ""))))

(defun gptel-prefix-cache--mementum-summary ()
  "Return standing mementum knowledge summary.
Fetches top-level knowledge pages and recent memories."
  (ignore-errors
    (let ((knowledge nil)
          (root (gptel-prefix-cache--project-root)))
      ;; Read key knowledge files if they exist
      (dolist (file '("mementum/knowledge/project-facts.md"
                      "mementum/knowledge/backend-comparison.md"
                      "mementum/knowledge/model-comparison.md"
                      "mementum/state.md"))
        (let ((path (expand-file-name file root)))
          (when (file-exists-p path)
            (with-temp-buffer
              (insert-file-contents path)
              (let ((content (buffer-string)))
                (when (and content (not (string-empty-p content)))
                   (push (cons file (gptel-prefix-cache--truncate-content content 500))
                         knowledge)))))))
      (if knowledge
          (concat "## Standing Knowledge\n\n"
                  (mapconcat (lambda (entry)
                               (format "### %s\n%s"
                                       (car entry)
                                       (cdr entry)))
                             knowledge
                             "\n\n")
                   "\n")
        ""))))

(defun gptel-prefix-cache--architecture-context ()
  "Return OV5 architecture context for the stable prefix.
Describes the self-evolving pipeline structure and agent roles."
  (concat "## OV5 Architecture Context\n\n"
          "You are part of the Ouroboros V5 (OV5) self-evolving pipeline.\n"
          "- Pipeline phases: target selection → categorization → backend routing → "
          "experiment generation → validation → grading → review → merge/learn\n"
          "- Your role: EXECUTOR — you receive a target file and hypothesis, "
          "then make concrete code improvements\n"
          "- Constraints: All changes must pass tests, byte-compile cleanly, "
          "and follow project conventions\n"
          "- Safety: Experiments run in isolated git worktrees; "
          "changes only merge after passing all gates\n"
          "\n"))

;; ─── Helpers ───

(defun gptel-prefix-cache--project-root ()
  "Return project root for prefix cache computation."
  (or (and (fboundp 'gptel-auto-workflow--project-root)
           (gptel-auto-workflow--project-root))
      (and (fboundp 'gptel-auto-workflow--worktree-base-root)
           (gptel-auto-workflow--worktree-base-root))
      default-directory))

(defun gptel-prefix-cache--assemble-sections (sections)
  "Assemble SECTIONS into final prefix string.
SECTIONS is an alist of (name . content) pairs."
  (if (null sections)
      ""
    (concat "=== STABLE PREFIX (cached across experiments) ===\n\n"
            (mapconcat (lambda (section)
                         (cdr section))
                       (reverse sections)
                       "\n")
            "\n=== DYNAMIC CONTENT (changes per experiment) ===\n\n")))

(defun gptel-prefix-cache--truncate-content (content max-len)
  "Truncate CONTENT to MAX-LEN chars, preserving complete lines."
  (if (<= (length content) max-len)
      content
    (let ((truncated (substring content 0 max-len)))
      ;; Cut to last complete line
      (if (string-match "\n.*\'" truncated)
          (concat (substring truncated 0 (match-beginning 0)) "\n[...]")
        (concat truncated "...")))))

;; ─── Prompt Building Integration ───

(defun gptel-prefix-cache-prepend (dynamic-prompt)
  "Prepend stable prefix to DYNAMIC-PROMPT.
If prefix cache is disabled or empty, returns DYNAMIC-PROMPT unchanged.
Otherwise returns concatenation of stable prefix + dynamic content."
  (if (or (not gptel-prefix-cache-enabled)
          (not gptel-prefix-cache--valid-p)
          (not gptel-prefix-cache--content))
      dynamic-prompt
    (concat gptel-prefix-cache--content dynamic-prompt)))

(defun gptel-prefix-cache-extract-dynamic (full-prompt)
  "Extract dynamic portion from FULL-PROMPT if it contains our prefix marker.
Returns FULL-PROMPT unchanged if no marker found."
  (if (string-match "=== DYNAMIC CONTENT (changes per experiment) ===\n\n" full-prompt)
      (substring full-prompt (match-end 0))
    full-prompt))

;; ─── Context Window Tracking ───

(defvar gptel-prefix-cache--context-window-size 100000
  "Context window size in tokens for current backend.
Should be set from backend registry config.")

(defvar gptel-prefix-cache--context-compact-ratio 0.8
  "Ratio of context window at which to trigger compaction.")

(defvar gptel-prefix-cache--estimated-tokens-per-char 0.3
  "Estimated tokens per character (~3.5 bytes/token ≈ 0.3 tokens/char).")

(defun gptel-prefix-cache-set-context-window (tokens)
  "Set context window size to TOKENS.
Should be called when backend is selected."
  (setq gptel-prefix-cache--context-window-size tokens))

(defun gptel-prefix-cache-sync-from-backend (backend model)
  "Sync context window from BACKEND/MODEL registry.
BACKEND is a symbol (e.g. \='DeepSeek), MODEL is a symbol (e.g. \='deepseek-v4-pro).
Looks up context-window in `gptel-backend-registry' and sets it locally."
  (when (and backend model
             (fboundp 'gptel-backend-registry-context-window))
    (let ((window (gptel-backend-registry-context-window backend model)))
      (when window
        (setq gptel-prefix-cache--context-window-size window)
        (message "[prefix-cache] Context window set: %s/%s → %d tokens"
                 backend model window)))))

(defun gptel-prefix-cache-estimate-tokens (text)
  "Estimate token count for TEXT.
Uses chars × tokens-per-char heuristic."
  (round (* (length text) gptel-prefix-cache--estimated-tokens-per-char)))

(defun gptel-prefix-cache-context-usage (dynamic-prompt)
  "Return estimated token usage for full prompt (prefix + dynamic).
Returns plist: (:total :prefix :dynamic :ratio :compaction-needed-p)."
  (let* ((prefix-tokens (gptel-prefix-cache-estimate-tokens gptel-prefix-cache--content))
         (dynamic-tokens (gptel-prefix-cache-estimate-tokens dynamic-prompt))
         (total-tokens (+ prefix-tokens dynamic-tokens))
         (ratio (if (> gptel-prefix-cache--context-window-size 0)
                    (/ (float total-tokens) gptel-prefix-cache--context-window-size)
                  0.0)))
    (list :total total-tokens
          :prefix prefix-tokens
          :dynamic dynamic-tokens
          :ratio ratio
          :compaction-needed-p (>= ratio gptel-prefix-cache--context-compact-ratio))))

;; ─── Proactive Compaction (Gap 3) ───

(defvar gptel-prefix-cache--compaction-archive nil
  "List of compacted summaries from previous compactions.
Each entry is a timestamped summary string.")

(defun gptel-prefix-cache-compact-dynamic (dynamic-prompt previous-results)
  "Compact DYNAMIC-PROMPT by summarizing older PREVIOUS-RESULTS.
Keeps last 3 experiments verbatim; summarizes older ones into categories.
Returns compacted prompt string."
  (if (or (null previous-results)
          (<= (length previous-results) 3))
      dynamic-prompt
    (let* ((recent (cl-subseq previous-results 0 3))
           (older (nthcdr 3 previous-results))
           (summary (gptel-prefix-cache--summarize-results older))
            (compact-section
             (concat "## Previous Experiment Summary (" (number-to-string (length older)) " compacted)\n"
                     summary
                     "\n\n## Recent Experiments (last 3, verbatim)\n"
                     (gptel-prefix-cache--format-results recent)
                     "\n\n"))
           ;; Replace the previous results section in the dynamic prompt
           (compacted
            (if (string-match-p "## Previous Results" dynamic-prompt)
                (replace-regexp-in-string
                 "## Previous Results.*\(?:\n## \|\\'\)"
                 (concat compact-section "\n")
                 dynamic-prompt t t)
              (concat compact-section dynamic-prompt))))
      (message "[prefix-cache] Compacted %d older results into summary"
               (length older))
      compacted)))

(defun gptel-prefix-cache--summarize-results (results)
  "Summarize RESULTS into compact categories.
Returns string with: kept count, common failure modes, best hypothesis."
  (let ((kept 0)
        (discarded 0)
        (failures (make-hash-table :test 'equal))
        (best-hypothesis nil)
        (best-score 0.0))
    (dolist (r results)
      (if (plist-get r :kept)
          (progn
            (cl-incf kept)
            (let ((score (or (plist-get r :score-after) 0.0)))
              (when (> score best-score)
                (setq best-score score
                      best-hypothesis (plist-get r :hypothesis)))))
        (cl-incf discarded)
        (let ((reason (or (plist-get r :comparator-reason)
                         (plist-get r :grader-reason)
                         "unknown")))
          (puthash reason (1+ (gethash reason failures 0)) failures))))
    (concat
     (format "- Kept: %d, Discarded: %d (%.0f%% keep rate)\n"
             kept discarded
             (if (> (+ kept discarded) 0)
                 (* 100.0 (/ kept (float (+ kept discarded))))
               0.0))
     (when best-hypothesis
       (format "- Best hypothesis: %.0f%% score → %s\n"
               (* 100.0 best-score)
               (truncate-string-to-width best-hypothesis 80 nil nil "...")))
     (when (> (hash-table-count failures) 0)
       (concat "- Common failure modes:\n"
               (let ((lines nil))
                 (maphash
                  (lambda (reason count)
                    (push (format "  - %s: %d×" reason count) lines))
                  failures)
                 (string-join (sort lines #'string<) "\n"))
               "\n")))))

(defun gptel-prefix-cache--format-results (results)
  "Format RESULTS as compact bullet list."
  (mapconcat
   (lambda (r)
     (format "- Exp %s: %s | Score %.2f→%.2f | %s"
             (or (plist-get r :id) "?")
             (truncate-string-to-width
              (or (plist-get r :hypothesis) "no hypothesis") 50 nil nil "...")
             (or (plist-get r :score-before) 0.0)
             (or (plist-get r :score-after) 0.0)
             (if (plist-get r :kept) "KEPT" "DISCARDED")))
   results
   "\n"))

;; ─── Run Lifecycle Hooks ───

(defun gptel-prefix-cache-on-run-start (&optional run-id)
  "Hook to call when a new run starts.
Computes prefix cache for RUN-ID."
  (setq gptel-prefix-cache--compaction-archive nil)
  (gptel-prefix-cache-compute run-id t))

(defun gptel-prefix-cache-on-run-end ()
  "Hook to call when run ends.
Invalidates prefix cache."
  (gptel-prefix-cache-invalidate)
  (setq gptel-prefix-cache--compaction-archive nil))

;; ─── Session Separation (Gap 4) ───

(defvar gptel-prefix-cache--role-caches (make-hash-table :test 'equal)
  "Hash table mapping role names to their prefix caches.
Keys are role symbols: \='executor, \='grader, \='reviewer, \='comparator.
Values are plists: (:content :valid-p :run-id :timestamp :stats).")

(defcustom gptel-prefix-cache-role-aware t
  "When non-nil, use per-role prefix caches for subagent isolation.
Each subagent role (executor, grader, reviewer) gets its own stable prefix,
preventing cross-contamination between roles."
  :type 'boolean
  :group 'gptel-tools-agent)

(defvar gptel-prefix-cache--default-roles
  '(executor grader reviewer comparator)
  "List of subagent roles that get isolated prefix caches.")

(defun gptel-prefix-cache-role-get (role)
  "Get cached prefix for ROLE (symbol). Returns content string or nil."
  (when role
    (let ((entry (gethash role gptel-prefix-cache--role-caches)))
      (when entry
        (let ((content (plist-get entry :content))
              (run-id (plist-get entry :run-id))
              (valid-p (plist-get entry :valid-p)))
          (when (and valid-p content
                     (equal run-id gptel-prefix-cache--run-id))
            content))))))

(defun gptel-prefix-cache-role-set (role content)
  "Set cached prefix CONTENT for ROLE."
  (when role
    (puthash role
             (list :content content
                   :valid-p t
                   :run-id gptel-prefix-cache--run-id
                   :timestamp (current-time)
                   :stats (list :size (length content)))
             gptel-prefix-cache--role-caches)))

(defun gptel-prefix-cache-role-invalidate (role)
  "Invalidate cache for ROLE, or all roles if ROLE is t."
  (if (eq role t)
      (clrhash gptel-prefix-cache--role-caches)
    (remhash role gptel-prefix-cache--role-caches)))

(defun gptel-prefix-cache--role-context (role)
  "Return role-specific context string for ROLE.
Each role gets tailored instructions that don't leak between sessions."
  (pcase role
    ('executor
     (concat "## Role: EXECUTOR\n"
             "You make concrete code improvements.\n"
             "- Read target file, understand the hypothesis\n"
             "- Make minimal, focused edits\n"
             "- Verify changes compile and tests pass\n"
             "- Output: edited code + summary of changes\n\n"))
    ('grader
     (concat "## Role: GRADER\n"
             "You evaluate code changes objectively.\n"
             "- Score 0.0-1.0 on structure, correctness, safety\n"
             "- Check Eight Keys compliance\n"
             "- Identify specific issues with file:line references\n"
             "- Output: score + detailed feedback\n\n"))
    ('reviewer
     (concat "## Role: REVIEWER\n"
             "You review changes for merge readiness.\n"
             "- Verify tests pass, no regressions\n"
             "- Check style and convention compliance\n"
             "- Assess risk: safe / needs-more-testing / reject\n"
             "- Output: approval decision + rationale\n\n"))
    ('comparator
     (concat "## Role: COMPARATOR\n"
             "You decide keep vs discard.\n"
             "- Compare before/after scores and quality\n"
             "- Check for regressions or new issues\n"
             "- Decision: kept / discarded + reason\n"
             "- Output: decision + justification\n\n"))
    (_ "")))

(defun gptel-prefix-cache-compute-for-role (role &optional run-id force-recompute)
  "Compute prefix cache for specific ROLE.
If FORCE-RECOMPUTE is non-nil, invalidate existing cache first.
Returns the computed prefix string for this role."
  (when force-recompute
    (gptel-prefix-cache-role-invalidate role))
  (or (gptel-prefix-cache-role-get role)
      (let* ((base-prefix (gptel-prefix-cache-compute run-id))
             (role-context (gptel-prefix-cache--role-context role))
             (role-prefix (concat base-prefix role-context)))
        (gptel-prefix-cache-role-set role role-prefix)
        (message "[prefix-cache] Computed %s prefix: %d chars"
                 role (length role-prefix))
        role-prefix)))

(defun gptel-prefix-cache-prepend-for-role (role dynamic-prompt)
  "Prepend role-specific stable prefix to DYNAMIC-PROMPT.
If role cache is disabled or empty, falls back to global prefix."
  (if (or (not gptel-prefix-cache-role-aware)
          (not role))
      (gptel-prefix-cache-prepend dynamic-prompt)
    (let ((role-prefix (gptel-prefix-cache-role-get role)))
      (if (and role-prefix (not (string-empty-p role-prefix)))
          (concat role-prefix dynamic-prompt)
        ;; Fallback: compute on demand
        (let ((computed (gptel-prefix-cache-compute-for-role role)))
          (if computed
              (concat computed dynamic-prompt)
            dynamic-prompt))))))

(defun gptel-prefix-cache-role-stats ()
  "Return statistics for all role caches as human-readable string."
  (let ((lines nil))
    (maphash
     (lambda (role entry)
       (let ((size (plist-get (plist-get entry :stats) :size))
             (valid (if (plist-get entry :valid-p) "valid" "stale"))
             (run (or (plist-get entry :run-id) "none")))
         (push (format "  %s: %d chars (%s, run=%s)"
                       role size valid run)
               lines)))
     gptel-prefix-cache--role-caches)
    (if lines
        (concat "[prefix-cache] Role caches:\n"
                (string-join (sort lines #'string<) "\n"))
      "[prefix-cache] No role caches active")))

;; ─── Provide ───

(provide 'gptel-ext-prefix-cache)

;;; gptel-ext-prefix-cache.el ends here
