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
(require 'json)

;; ─── Forward Declarations ───

(declare-function gptel-tool-name "gptel" (tool))
(declare-function gptel-tool-description "gptel" (tool))
(defvar gptel-tools nil)

(declare-function gptel-auto-workflow--project-root "gptel-tools-agent-benchmark")
(declare-function gptel-auto-workflow--worktree-base-root "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--categorize-target "gptel-auto-workflow-ontology-router")
(declare-function gptel-mementum--recall "gptel-auto-workflow-mementum" (query depth))
(declare-function gptel-auto-experiment--rank-relevant "gptel-tools-agent-experiment-loop"
                  (target previous-results &optional n))

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
Safe to call multiple times — returns cached content after first computation.
Tracks hit/miss statistics for cross-run analysis."
  (let ((cached (and gptel-prefix-cache--valid-p gptel-prefix-cache--content)))
    (if cached
        (progn
          (gptel-prefix-cache--record-hit)
          cached)
      (gptel-prefix-cache--record-miss)
      (gptel-prefix-cache-compute))))

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
BACKEND is a symbol (e.g. \='DeepSeek).
MODEL is a symbol (e.g. \='deepseek-v4-pro).
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
       (gptel-prefix-cache--record-compaction)
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

(defcustom gptel-prefix-cache-relevant-results-count 10
  "Number of most relevant previous results to include in prompt.
Uses AttnRes-inspired relevance scoring (Jaccard similarity).
Set to nil to include all results (legacy behavior)."
  :type '(choice (const :tag "All results" nil)
                 (integer :tag "Max relevant results"))
  :group 'gptel-tools-agent)

(defun gptel-prefix-cache--format-results-weighted (scored-results)
  "Format SCORED-RESULTS as compact bullet list with relevance scores.
SCORED-RESULTS is a list of (RELEVANCE . EXPERIMENT-PLIST) pairs."
  (mapconcat
   (lambda (pair)
     (let* ((relevance (car pair))
            (r (cdr pair))
            (rel-pct (round (* 100 relevance))))
       (format "- Exp %s [rel=%d%%]: %s | Score %.2f→%.2f | %s"
               (or (plist-get r :id) "?")
               rel-pct
               (truncate-string-to-width
                (or (plist-get r :hypothesis) "no hypothesis") 45 nil nil "...")
               (or (plist-get r :score-before) 0.0)
               (or (plist-get r :score-after) 0.0)
               (if (plist-get r :kept) "KEPT" "DISCARDED"))))
   scored-results
   "\n"))

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

;; ─── Token-Aware Prompt Building (Gap 5) ───

(defcustom gptel-prefix-cache-dynamic-token-budget 4000
  "Max tokens for dynamic content per experiment turn.
Sections are included in priority order until this budget is exhausted.
Set to nil to disable budget-aware prompt building."
  :type '(choice (const :tag "Disabled" nil)
                 (integer :tag "Token budget"))
  :group 'gptel-tools-agent)

(defvar gptel-prefix-cache--output-reservation 2000
  "Tokens reserved for LLM output.
Subtracted from context window when computing dynamic budget.")

(defun gptel-prefix-cache-compute-dynamic-budget ()
  "Compute token budget for dynamic content.
Returns number of tokens available, or nil if budget management disabled.
Formula: context-window - prefix-tokens - output-reservation."
  (when (and gptel-prefix-cache-dynamic-token-budget
             (> gptel-prefix-cache--context-window-size 0))
    (let* ((prefix-tokens (gptel-prefix-cache-estimate-tokens
                           gptel-prefix-cache--content))
           (available (- gptel-prefix-cache--context-window-size
                        prefix-tokens
                        gptel-prefix-cache--output-reservation)))
      (max 0 (min available gptel-prefix-cache-dynamic-token-budget)))))

(defun gptel-prefix-cache-build-with-budget (sections)
  "Build prompt from SECTIONS respecting token budget.
SECTIONS is an alist of (priority . (name . content)) pairs.
Priority: 1=highest (essential), 5=lowest (optional).
Returns concatenated string of included sections.
Logs which sections were included/excluded."
  (let* ((budget (gptel-prefix-cache-compute-dynamic-budget))
         (sorted (sort (copy-sequence sections)
                       (lambda (a b) (< (car a) (car b)))))
         (included nil)
         (excluded nil)
         (used-tokens 0))
    (if (null budget)
        ;; Budget management disabled: include all sections
        (mapconcat (lambda (s) (cddr s)) sorted "\n\n")
      (dolist (entry sorted)
         (let* ((name (cadr entry))
                (content (cddr entry))
                (tokens (gptel-prefix-cache-estimate-tokens content)))
          (if (<= (+ used-tokens tokens) budget)
              (progn
                (push (cons name tokens) included)
                (setq used-tokens (+ used-tokens tokens)))
            (push (cons name tokens) excluded))))
      (when excluded
        (message "[prefix-cache] Budget %d tokens: included %d sections (%d tokens), excluded %d: %s"
                 budget
                 (length included) used-tokens
                 (length excluded)
                 (mapconcat (lambda (e) (car e)) excluded ", ")))
      (mapconcat (lambda (s) (cddr s)) sorted "\n\n"))))

(defun gptel-prefix-cache-sections-for-experiment (target experiment-id max-experiments analysis previous-results)
  "Return prioritized sections for experiment prompt.
Returns alist of (priority . (name . content)) pairs.
Priority 1 = essential, 5 = optional."
  (list
    ;; Priority 1: Essential
    (cons 1 (cons "target"
                  (format "## Target: %s\nExperiment %d/%d"
                          target experiment-id max-experiments)))
    ;; Priority 1: Hypothesis
    (cons 1 (cons "hypothesis"
                  (or (and (fboundp 'gptel-auto-experiment--select-diverse-hypothesis)
                           (gptel-auto-experiment--select-diverse-hypothesis target previous-results))
                      "Make targeted improvements")))
    ;; Priority 2: Task hint
    (cons 2 (cons "task-hint"
                  (or (and (boundp 'gptel-auto-experiment--current-task-hint)
                           gptel-auto-experiment--current-task-hint)
                      "")))
    ;; Priority 2: Analysis
    (cons 2 (cons "analysis"
                  (if analysis
                      (format "## Analysis\n%s" (plist-get analysis :patterns))
                      "")))
    ;; Priority 3: Recent results (relevance-weighted if available)
    (cons 3 (cons "recent-results"
                  (if (and previous-results (> (length previous-results) 0))
                      (let* ((use-relevance
                              (and gptel-prefix-cache-relevant-results-count
                                   (fboundp 'gptel-auto-experiment--rank-relevant)))
                             (formatted
                              (if use-relevance
                                  (let ((scored (gptel-auto-experiment--rank-relevant
                                                 target previous-results
                                                 gptel-prefix-cache-relevant-results-count)))
                                    (if scored
                                        (format "## Previous Results (top %d by relevance)\n%s"
                                                (length scored)
                                                (gptel-prefix-cache--format-results-weighted scored))
                                      (format "## Previous Results\n%s"
                                              (gptel-prefix-cache--format-results previous-results))))
                                (format "## Previous Results\n%s"
                                        (gptel-prefix-cache--format-results previous-results)))))
                        formatted)
                      "")))
   ;; Priority 4: Mementum
   (cons 4 (cons "mementum"
                 (or (and (boundp 'gptel-auto-experiment--mementum-recall)
                          gptel-auto-experiment--mementum-recall)
                     "")))
   ;; Priority 5: Git history
   (cons 5 (cons "git-history"
                 "Recent commits..."))))

;; ─── Context State Persistence (Gap 6) ───

(defcustom gptel-prefix-cache-persist-enabled t
  "When non-nil, save prefix cache state across daemon restarts.
State is saved to `gptel-prefix-cache-persist-file' on run end
and loaded on run start."
  :type 'boolean
  :group 'gptel-tools-agent)

(defcustom gptel-prefix-cache-persist-file
  (expand-file-name "var/tmp/prefix-cache-state.eld"
                    (or (and (fboundp 'gptel-auto-workflow--project-root)
                             (gptel-auto-workflow--project-root))
                        default-directory))
  "File path for saving/loading prefix cache state.
Uses Emacs Lisp data format (.eld)."
  :type 'file
  :group 'gptel-tools-agent)

(defcustom gptel-prefix-cache-persist-max-age-hours 24
  "Maximum age in hours for persisted cache state.
Older state is discarded as stale."
  :type 'integer
  :group 'gptel-tools-agent)

(defun gptel-prefix-cache-save-to-file ()
  "Save current prefix cache state to disk.
Includes main cache, role caches, context window, and compaction archive.
Only saves when `gptel-prefix-cache-persist-enabled' is non-nil."
  (when (and gptel-prefix-cache-persist-enabled
             gptel-prefix-cache--valid-p
             gptel-prefix-cache--content)
     (let ((state
            (list
              ;; Main cache state
              :version 2
              :timestamp (current-time)
              :run-id gptel-prefix-cache--run-id
              :content gptel-prefix-cache--content
              :valid-p gptel-prefix-cache--valid-p
              :stats gptel-prefix-cache--stats
             ;; Context configuration
             :context-window gptel-prefix-cache--context-window-size
             :compact-ratio gptel-prefix-cache--context-compact-ratio
             ;; Compaction archive
             :compaction-archive gptel-prefix-cache--compaction-archive
             ;; Cross-run statistics (Phase 3)
             :cross-run-stats gptel-prefix-cache--cross-run-stats
             ;; Role caches
             :role-caches
            (let ((role-data nil))
              (maphash
               (lambda (role entry)
                 (push (list role
                             :content (plist-get entry :content)
                             :run-id (plist-get entry :run-id)
                             :valid-p (plist-get entry :valid-p)
                             :stats (plist-get entry :stats))
                       role-data))
               gptel-prefix-cache--role-caches)
              role-data))))
      (condition-case save-err
          (progn
            (make-directory (file-name-directory gptel-prefix-cache-persist-file) t)
            (with-temp-file gptel-prefix-cache-persist-file
              (prin1 state (current-buffer)))
            (message "[prefix-cache] State saved to %s (%d chars)"
                     gptel-prefix-cache-persist-file
                     (length gptel-prefix-cache--content)))
        (error
         (message "[prefix-cache] Save failed: %s" (error-message-string save-err)))))))

(defun gptel-prefix-cache-load-from-file ()
  "Load prefix cache state from disk if available and not stale.
Returns t if state was restored, nil otherwise."
  (when (and gptel-prefix-cache-persist-enabled
             (file-exists-p gptel-prefix-cache-persist-file))
    (let* ((state (with-temp-buffer
                    (insert-file-contents gptel-prefix-cache-persist-file)
                    (read (current-buffer))))
           (timestamp (plist-get state :timestamp))
           (age-hours (if timestamp
                          (/ (float-time (time-subtract (current-time) timestamp))
                             3600.0)
                        9999))
            (version (plist-get state :version)))
       (cond
        ((not (memq version '(1 2)))
         (message "[prefix-cache] State file version mismatch: %s" version)
         nil)
       ((> age-hours gptel-prefix-cache-persist-max-age-hours)
        (message "[prefix-cache] State file stale (%.1f hours old), discarding"
                 age-hours)
        (delete-file gptel-prefix-cache-persist-file)
        nil)
       (t
        ;; Restore main cache
        (setq gptel-prefix-cache--content (plist-get state :content)
              gptel-prefix-cache--valid-p (plist-get state :valid-p)
              gptel-prefix-cache--run-id (plist-get state :run-id)
              gptel-prefix-cache--stats (plist-get state :stats)
              gptel-prefix-cache--timestamp timestamp
              gptel-prefix-cache--context-window-size
              (or (plist-get state :context-window) 100000)
              gptel-prefix-cache--context-compact-ratio
              (or (plist-get state :compact-ratio) 0.8)
              gptel-prefix-cache--compaction-archive
              (plist-get state :compaction-archive)
              ;; Restore cross-run stats (added in version 2)
              gptel-prefix-cache--cross-run-stats
              (plist-get state :cross-run-stats))
         ;; Restore role caches
        (clrhash gptel-prefix-cache--role-caches)
        (dolist (role-entry (plist-get state :role-caches))
          (let ((role (car role-entry))
                (entry (cdr role-entry)))
            (puthash role
                     (list :content (plist-get entry :content)
                           :valid-p (plist-get entry :valid-p)
                           :run-id (plist-get entry :run-id)
                           :stats (plist-get entry :stats))
                     gptel-prefix-cache--role-caches)))
         (message "[prefix-cache] State restored from %s (%.1f hours old, %d roles)"
                  gptel-prefix-cache-persist-file
                  age-hours
                  (hash-table-count gptel-prefix-cache--role-caches))
         t)))))

(defun gptel-prefix-cache-clear-persisted-state ()
  "Delete persisted cache state file if it exists."
  (when (and gptel-prefix-cache-persist-file
             (file-exists-p gptel-prefix-cache-persist-file))
    (delete-file gptel-prefix-cache-persist-file)
    (message "[prefix-cache] Persisted state cleared")))

;; ─── Cross-Run Statistics (Phase 3) ───

(defvar gptel-prefix-cache--cross-run-stats nil
  "Plist of aggregated statistics across runs.
Keys: :runs :total-hits :total-misses :total-compactions
      :avg-prefix-size :avg-compute-time-ms :last-tune-timestamp")

(defvar gptel-prefix-cache--hit-counter 0
  "Counter for cache hits in current run.
Incremented each time `gptel-prefix-cache-get' returns cached content.")

(defvar gptel-prefix-cache--miss-counter 0
  "Counter for cache misses in current run.")

(defvar gptel-prefix-cache--compaction-counter 0
  "Counter for compaction operations in current run.")

(defvar gptel-prefix-cache--auto-tune-enabled t
  "When non-nil, auto-tune compaction threshold based on performance.")

(defvar gptel-prefix-cache--auto-tune-min-threshold 0.6
  "Minimum compaction ratio (never compact below this).")

(defvar gptel-prefix-cache--auto-tune-max-threshold 0.95
  "Maximum compaction ratio (never compact above this).")

(defvar gptel-prefix-cache--auto-tune-interval 10
  "Number of runs between auto-tune evaluations.")

(defun gptel-prefix-cache--record-hit ()
  "Record a cache hit."
  (cl-incf gptel-prefix-cache--hit-counter))

(defun gptel-prefix-cache--record-miss ()
  "Record a cache miss."
  (cl-incf gptel-prefix-cache--miss-counter))

(defun gptel-prefix-cache--record-compaction ()
  "Record a compaction operation."
  (cl-incf gptel-prefix-cache--compaction-counter))

(defun gptel-prefix-cache-stats-current-run ()
  "Return statistics for current run as a plist."
  (let ((total (+ gptel-prefix-cache--hit-counter
                  gptel-prefix-cache--miss-counter)))
    (list :hits gptel-prefix-cache--hit-counter
          :misses gptel-prefix-cache--miss-counter
          :compactions gptel-prefix-cache--compaction-counter
          :hit-rate (if (> total 0)
                        (/ (float gptel-prefix-cache--hit-counter) total)
                      0.0)
          :prefix-size (or (plist-get gptel-prefix-cache--stats :size) 0)
          :compute-time-ms (or (plist-get gptel-prefix-cache--stats :compute-time-ms) 0))))

(defun gptel-prefix-cache--auto-tune-threshold ()
  "Auto-tune compaction threshold based on cross-run statistics.
Adjusts `gptel-prefix-cache--context-compact-ratio' to balance
prefix cache stability vs. context window pressure.
Strategy:
- If hit rate < 0.5: lower threshold (compact less aggressively)
- If hit rate > 0.8 AND compactions/run > 2: raise threshold (compact more)
- If compactions/run = 0: lower threshold (prevent overflow)
- Keep within [min-threshold, max-threshold]."
  (when gptel-prefix-cache--auto-tune-enabled
    (let* ((runs (or (plist-get gptel-prefix-cache--cross-run-stats :runs) 0))
           (total-hits (or (plist-get gptel-prefix-cache--cross-run-stats :total-hits) 0))
           (total-compactions (or (plist-get gptel-prefix-cache--cross-run-stats :total-compactions) 0))
           (hit-rate (if (> runs 0) (/ (float total-hits) runs) 0.0))
           (compactions-per-run (if (> runs 0) (/ (float total-compactions) runs) 0.0))
           (current gptel-prefix-cache--context-compact-ratio)
           (new current))
      (cond
       ;; Low hit rate: compact less aggressively to keep more context
       ((< hit-rate 0.5)
        (setq new (max gptel-prefix-cache--auto-tune-min-threshold
                       (- current 0.05))))
       ;; High hit rate with frequent compactions: compact more aggressively
       ((and (> hit-rate 0.8) (> compactions-per-run 2.0))
        (setq new (min gptel-prefix-cache--auto-tune-max-threshold
                       (+ current 0.03))))
       ;; No compactions: lower threshold slightly to prevent future overflow
       ((and (> runs 5) (= compactions-per-run 0.0))
        (setq new (max gptel-prefix-cache--auto-tune-min-threshold
                       (- current 0.02)))))
      (when (/= new current)
        (setq gptel-prefix-cache--context-compact-ratio new)
        (message "[prefix-cache] Auto-tuned compaction: %.0f%% → %.0f%% (hit-rate=%.2f,
compactions/run=%.1f)"
                 (* 100.0 current) (* 100.0 new) hit-rate compactions-per-run))
      new)))

(defun gptel-prefix-cache-stats-report ()
  "Generate a human-readable statistics report."
  (let* ((current (gptel-prefix-cache-stats-current-run))
         (cross gptel-prefix-cache--cross-run-stats)
         (runs (or (plist-get cross :runs) 0))
         (total-hits (or (plist-get cross :total-hits) 0))
         (total-compactions (or (plist-get cross :total-compactions) 0)))
    (format (concat "=== Prefix Cache Statistics ===\n"
                    "Current run: hits=%d misses=%d compactions=%d hit-rate=%.1f%%\n"
                    "Prefix: %d chars, compute=%.0fms\n"
                    "Cross-run (%d runs): total-hits=%d total-compactions=%d\n"
                    "Compaction threshold: %.0f%% (auto-tune=%s)\n"
                    "==============================")
            (plist-get current :hits)
            (plist-get current :misses)
            (plist-get current :compactions)
            (* 100.0 (plist-get current :hit-rate))
            (plist-get current :prefix-size)
            (plist-get current :compute-time-ms)
            runs total-hits total-compactions
            (* 100.0 gptel-prefix-cache--context-compact-ratio)
            (if gptel-prefix-cache--auto-tune-enabled "on" "off"))))

;; ─── Metrics Export ───

(defun gptel-prefix-cache-export-metrics ()
  "Export current run metrics to var/metrics/prefix-cache-stats.json.
Creates the directory if needed. Appends to existing metrics array.
Returns the metrics file path."
  (let* ((metrics-dir (expand-file-name "var/metrics"
                                          (or (and (fboundp 'gptel-auto-workflow--worktree-base-root)
                                                   (gptel-auto-workflow--worktree-base-root))
                                              user-emacs-directory)))
         (metrics-file (expand-file-name "prefix-cache-stats.json" metrics-dir))
         (current (gptel-prefix-cache-stats-current-run))
         (cross gptel-prefix-cache--cross-run-stats)
         (entry `((timestamp . ,(format-time-string "%Y-%m-%dT%H:%M:%S"))
                  (run-id . ,(or gptel-prefix-cache--run-id "unknown"))
                  (hits . ,(plist-get current :hits))
                  (misses . ,(plist-get current :misses))
                  (compactions . ,(plist-get current :compactions))
                  (hit-rate . ,(plist-get current :hit-rate))
                  (prefix-size . ,(plist-get current :prefix-size))
                  (compute-time-ms . ,(plist-get current :compute-time-ms))
                  (compact-ratio . ,gptel-prefix-cache--context-compact-ratio)
                  (auto-tune-enabled . ,gptel-prefix-cache--auto-tune-enabled)
                  (cross-run-runs . ,(or (plist-get cross :runs) 0))
                  (cross-run-total-hits . ,(or (plist-get cross :total-hits) 0))
                  (cross-run-total-compactions . ,(or (plist-get cross :total-compactions) 0)))))
    (make-directory metrics-dir t)
    (let ((existing
           (if (file-exists-p metrics-file)
               (condition-case nil
                   (with-temp-buffer
                     (insert-file-contents metrics-file)
                     (json-read))
                 (error (vector)))
             (vector))))
      (setq existing (vconcat existing (vector entry)))
      ;; Keep only last 1000 entries to prevent unbounded growth
      (when (> (length existing) 1000)
        (setq existing (seq-subseq existing (- (length existing) 1000))))
      (with-temp-file metrics-file
        (insert (json-encode existing)))
      (message "[prefix-cache] Metrics exported to %s (%d entries)"
               metrics-file (length existing))
      metrics-file)))

;; ─── Integration Hooks ───

(defun gptel-prefix-cache-on-run-start (&optional run-id)
  "Hook to call when a new run starts.
Computes prefix cache for RUN-ID, optionally restoring persisted state.
Resets per-run counters."
  (setq gptel-prefix-cache--compaction-archive nil
        gptel-prefix-cache--hit-counter 0
        gptel-prefix-cache--miss-counter 0
        gptel-prefix-cache--compaction-counter 0)
  ;; Try to load persisted state first
  (unless (gptel-prefix-cache-load-from-file)
    ;; Fall back to computing fresh
    (gptel-prefix-cache-compute run-id t)))

(defun gptel-prefix-cache-on-run-end ()
  "Hook to call when run ends.
Saves prefix cache state, aggregates statistics, auto-tunes threshold,
then invalidates in-memory cache."
  ;; Aggregate cross-run statistics
  (let ((current (gptel-prefix-cache-stats-current-run)))
    (setq gptel-prefix-cache--cross-run-stats
          (list :runs (1+ (or (plist-get gptel-prefix-cache--cross-run-stats :runs) 0))
                :total-hits (+ (plist-get current :hits)
                               (or (plist-get gptel-prefix-cache--cross-run-stats :total-hits) 0))
                :total-misses (+ (plist-get current :misses)
                                 (or (plist-get gptel-prefix-cache--cross-run-stats :total-misses) 0))
                :total-compactions (+ (plist-get current :compactions)
                                      (or (plist-get gptel-prefix-cache--cross-run-stats :total-compactions) 0))
                :last-tune-timestamp (current-time)))
    ;; Auto-tune every N runs
    (when (zerop (mod (or (plist-get gptel-prefix-cache--cross-run-stats :runs) 0)
                      gptel-prefix-cache--auto-tune-interval))
      (gptel-prefix-cache--auto-tune-threshold)))
  (gptel-prefix-cache-save-to-file)
  ;; Export metrics for observability
  (when (fboundp 'json-encode)
    (condition-case nil
        (gptel-prefix-cache-export-metrics)
      (error nil)))
  (gptel-prefix-cache-invalidate)
  (setq gptel-prefix-cache--compaction-archive nil))

;; ─── Provide ───

(provide 'gptel-ext-prefix-cache)

;;; gptel-ext-prefix-cache.el ends here
