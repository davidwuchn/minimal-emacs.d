;;; gptel-tools-agent-prompt-build.el --- Prompt building - construction & logging -*- lexical-binding: t; -*-
;; Part of gptel-tools-agent split

;; ─── Knowledge Cache ───

(defvar gptel-auto-workflow--knowledge-cache (make-hash-table :test 'equal)
  "Hash table mapping knowledge keys to cached content.
Keys: 'self-evolution or topic names like 'context-cache.
Values: (content . timestamp) cons cells.
Cache is invalidated after synthesis runs.")

(defvar gptel-auto-workflow--knowledge-cache-max-age 3600
  "Maximum age of cached knowledge in seconds (1 hour).")

(defvar gptel-auto-workflow--topic-knowledge-max-chars 400
  "Maximum chars for topic-specific knowledge compression.
Self-evolution adjusts this based on token efficiency analysis.
Default 400, range 100-800.")

(defun gptel-auto-workflow--knowledge-cache-get (key)
  "Get cached knowledge for KEY if fresh.
Returns cached content or nil if missing/stale."
  (let ((entry (gethash key gptel-auto-workflow--knowledge-cache)))
    (when entry
      (let ((content (car entry))
            (timestamp (cdr entry))
            (age (float-time (time-subtract (current-time) (cdr entry)))))
        (if (< age gptel-auto-workflow--knowledge-cache-max-age)
            content
          ;; Stale - remove from cache
          (remhash key gptel-auto-workflow--knowledge-cache)
          nil)))))

(defun gptel-auto-workflow--knowledge-cache-set (key content)
  "Cache CONTENT for KEY with current timestamp."
  (puthash key (cons content (current-time)) gptel-auto-workflow--knowledge-cache))

(defun gptel-auto-workflow--knowledge-cache-invalidate (key)
  "Invalidate cache for KEY, or all keys if KEY is t."
  (if (eq key t)
      (clrhash gptel-auto-workflow--knowledge-cache)
    (remhash key gptel-auto-workflow--knowledge-cache)))

(defun gptel-auto-workflow--knowledge-cache-stats ()
  "Return cache statistics as string."
  (let ((count 0)
        (total-age 0))
    (maphash (lambda (key entry)
               (setq count (1+ count))
               (setq total-age (+ total-age (float-time (time-subtract (current-time) (cdr entry))))))
             gptel-auto-workflow--knowledge-cache)
    (format "[knowledge-cache] %d entries, avg age %.0fs"
            count (if (> count 0) (/ total-age count) 0))))

(defun gptel-auto-workflow--load-token-efficiency-skill ()
  "Load token efficiency skill and return parsed config.
Returns plist with :compression :section-stats or nil."
  (let ((skill-file (expand-file-name
                     "assistant/skills/auto-workflow/token-efficiency.md"
                     (or (and (fboundp 'gptel-auto-workflow--worktree-base-root)
                              (gptel-auto-workflow--worktree-base-root))
                         (gptel-auto-workflow--project-root)))))
    (when (file-exists-p skill-file)
      (with-temp-buffer
        (insert-file-contents skill-file)
        (goto-char (point-min))
        (let ((config (list :file skill-file)))
          ;; Parse compression config
          (when (re-search-forward "topic-knowledge-max-chars: \\([0-9]+\\)" nil t)
            (plist-put config :compression (string-to-number (match-string 1))))
          ;; Parse section A/B results
          (goto-char (point-min))
          (let ((section-stats (make-hash-table :test 'equal)))
            (while (re-search-forward "^- \\**\\(.+\\)*\\*: \\([0-9.]+\\)% success (\\([0-9]+\\)/\\([0-9]+\\) experiments)" nil t)
              (let ((section (match-string 1))
                     (rate (string-to-number (match-string 2)))
                     (kept (string-to-number (match-string 3)))
                     (total (string-to-number (match-string 4))))
                (puthash section (list :rate rate :kept kept :total total) section-stats)))
            (plist-put config :section-stats section-stats))
          config)))))

(defun gptel-auto-workflow--adapt-prompt-compression ()
  "Adapt topic knowledge compression based on token efficiency skill.
Reads optimization-skills/token-efficiency.md and adjusts max chars.
Returns the adjusted max chars value."
  (let* ((skill (gptel-auto-workflow--load-token-efficiency-skill))
         (compression (when skill (plist-get skill :compression))))
    (when (and compression (> compression 0))
      (setq gptel-auto-workflow--topic-knowledge-max-chars compression)
      (message "[prompt-efficiency] Skill-guided compression: %d chars" compression)))
  gptel-auto-workflow--topic-knowledge-max-chars)

;;; Section A/B Testing

(defvar gptel-auto-workflow--ab-test-sections
  '(suggestions self-evolution topic-specific git-history
    axis-performance cross-target-patterns failure-patterns)
  "Prompt sections that can be individually included/excluded for A/B testing.")

(defvar gptel-auto-workflow--ab-test-omit-rate 0.2
  "Probability of randomly omitting a section to gather A/B data.")

(defvar gptel-auto-workflow--ab-test-min-samples 10
  "Minimum experiments before using A/B data for section selection.")

(defun gptel-auto-workflow--analyze-section-performance ()
  "Analyze which prompt sections correlate with success.
Returns hash table: section-name -> (kept-count . total-count)."
  (let ((results-file (gptel-auto-workflow--results-file-path))
        (section-stats (make-hash-table :test 'equal)))
    (when (file-exists-p results-file)
      (with-temp-buffer
        (insert-file-contents results-file)
        (goto-char (point-min))
        (forward-line 1) ; skip header
        (while (not (eobp))
          (let* ((fields (split-string
                          (buffer-substring (line-beginning-position)
                                           (line-end-position))
                          "\t"))
                 (decision (nth 7 fields))
                 (sections-str (or (nth 16 fields) "all"))
                 (kept (equal decision "kept")))
            (when (not (equal sections-str "all"))
              (dolist (section (split-string sections-str ","))
                (let* ((key (intern section))
                       (current (gethash key section-stats '(0 . 0)))
                       (curr-kept (car current))
                       (curr-total (cdr current)))
                  (puthash key
                           (cons (if kept (1+ curr-kept) curr-kept)
                                 (1+ curr-total))
                           section-stats))))
          (forward-line 1))))
    section-stats))

(defun gptel-auto-workflow--select-ab-test-sections ()
  "Select which prompt sections to include based on A/B test data.
Returns list of section symbols to include.
With insufficient data, includes all sections.
With sufficient data, includes only sections with positive correlation."
  (let* ((section-stats (gptel-auto-workflow--analyze-section-performance))
         (total-experiments 0)
         (effective-sections '()))
    ;; Count total experiments with section tracking
    (maphash (lambda (_ stats)
               (setq total-experiments (+ total-experiments (cdr stats))))
             section-stats)
    (cond
     ;; Not enough data: include all, occasionally omit random section for exploration
     ((< total-experiments gptel-auto-workflow--ab-test-min-samples)
      (if (< (random 100) (* 100 gptel-auto-workflow--ab-test-omit-rate))
          ;; Randomly omit one section to gather data
          (let ((to-omit (nth (random (length gptel-auto-workflow--ab-test-sections))
                              gptel-auto-workflow--ab-test-sections)))
            (message "[ab-test] Omitting %s for exploration (data gathering phase)" to-omit)
            (remove to-omit gptel-auto-workflow--ab-test-sections))
        gptel-auto-workflow--ab-test-sections))
     ;; Sufficient data: include only effective sections
     (t
      (dolist (section gptel-auto-workflow--ab-test-sections)
        (let* ((stats (gethash section section-stats '(0 . 0)))
               (kept (car stats))
               (total (cdr stats))
               (rate (if (> total 0) (/ (float kept) total) 0.5)))
          (when (or (= total 0)  ; no data yet, give benefit of doubt
                    (>= rate 0.3))  ; at least 30% success rate
            (push section effective-sections))))
      (message "[ab-test] Selected sections (%d/%d): %s"
               (length effective-sections)
               (length gptel-auto-workflow--ab-test-sections)
               (mapconcat #'symbol-name effective-sections ","))
      (nreverse effective-sections))))))

(defun gptel-auto-workflow--load-skill-content (skill-name)
  "Load SKILL-NAME from assistant/skills/ directories.
Returns skill content string or empty string if not found.
Searches: ~/.emacs.d/assistant/skills/ then project assistant/skills/"
  (let* ((base-dirs (list (expand-file-name "assistant/skills"
                                             (gptel-auto-workflow--project-root))
                          (expand-file-name "~/.emacs.d/assistant/skills")))
         (skill-file nil))
    ;; Find skill file (supports both flat .md and directory/SKILL.md)
    (dolist (dir base-dirs)
      (let ((flat-file (expand-file-name (format "%s.md" skill-name) dir))
            (nested-file (expand-file-name (format "%s/SKILL.md" skill-name) dir)))
        (cond
         ((and (not skill-file) (file-exists-p flat-file))
          (setq skill-file flat-file))
         ((and (not skill-file) (file-exists-p nested-file))
          (setq skill-file nested-file)))))
    ;; Read and return content
    (if skill-file
        (with-temp-buffer
          (insert-file-contents skill-file)
          (goto-char (point-min))
          ;; Skip frontmatter
          (when (looking-at "---")
            (forward-line 1)
            (while (not (looking-at "---"))
              (forward-line 1))
            (forward-line 1))
          (buffer-string))
      "")))

(defun gptel-auto-workflow--substitute-template (template variables)
  "Substitute VARIABLES into TEMPLATE.
VARIABLES is an alist of (NAME . VALUE) where NAME is a symbol.
Replaces {{name}} in template with value.
Missing variables are replaced with empty string."
  (let ((result template))
    (dolist (var variables)
      (let ((name (symbol-name (car var)))
            (value (or (cdr var) "")))
        (setq result
              (replace-regexp-in-string
               (format "{{%s}}" (regexp-quote name))
               (if (stringp value) value (format "%s" value))
               result t t))))
    ;; Remove any remaining unreplaced variables
    (replace-regexp-in-string "{{[a-z-]+}}" "" result)))

(defun gptel-auto-workflow--load-prompt-template ()
  "Load prompt template from skill file.
Returns template string or fallback hardcoded template."
  (let ((skill-content (gptel-auto-workflow--load-skill-content "auto-workflow/prompt-template")))
    (if (> (length skill-content) 0)
        skill-content
      ;; Fallback: inline template (for bootstrapping)
      "You are running experiment {{experiment-id}} of {{max-experiments}} to optimize {{target}}.

## Working Directory
{{worktree-path}}

## Target File (full path)
{{target-full-path}}

{{large-target-guidance}}

{{controller-focus}}

{{inspection-thrash-contract}}

## Previous Experiment Analysis
{{previous-experiment-analysis}}

## Suggestions
{{suggestions}}

## Skills (Context from Learned Patterns)
{{self-evolution}}

## Previous Experiments
{{topic-knowledge}}

## Current Baseline
Overall Eight Keys score: {{baseline}}

{{weakest-keys}}

{{suggested-hypothesis}}

{{mutation-templates}}

## Objective
Improve the CODE QUALITY for {{target}}.
Focus on one improvement at a time.
Make minimal, targeted changes to CODE, not documentation.

## Constraints
- Time budget: {{time-budget}} minutes
- Immutable files: early-init.el, pre-early-init.el, lisp/eca-security.el
- Must pass tests: ./scripts/verify-nucleus.sh
- FORBIDDEN: Adding comments, docstrings, or documentation-only changes
- REQUIRED: Actual code changes (bug fixes, performance, refactoring, error handling)

## Code Improvement Types (PICK ONE)
1. **Bug Fix**: Fix an actual bug or error handling gap
2. **Performance**: Reduce complexity, add caching, optimize hot path
3. **Refactoring**: Extract functions, remove duplication, improve naming
4. **Safety**: Add validation, prevent edge cases, improve error messages
5. **Test Coverage**: Add missing tests for existing functionality

## Instructions
1. FIRST LINE must be: HYPOTHESIS: [What CODE change and why]
2. If a Controller-Selected Starting Symbol is present, line 2 must be exactly `{{focus-line}}`
3. If a Mandatory Focus Contract is present, obey it exactly; otherwise start from one concrete function or variable and prefer focused Grep or narrow Read before broader Code_Map surveys
4. Read only focused line ranges from the target file using its full path; avoid reading the entire file unless absolutely necessary
5. IDENTIFY a real code issue (bug, performance, duplication, missing validation)
6. Implement the CODE change minimally using Edit tool
7. BEFORE finishing, verify your changes have balanced parentheses:
   - Run: {{sexp-check-command}}
   - If you see an error, FIX IT before submitting
8. Run tests to verify: ./scripts/verify-nucleus.sh && ./scripts/run-tests.sh
9. DO NOT run git add, git commit, git push, or stage changes yourself.
   Leave edits uncommitted in the worktree; the auto-workflow controller
   handles grading, commit creation, review, and staging.
10. FINAL RESPONSE must include:
    - CHANGED: exact file path(s) and function/variable names touched
    - EVIDENCE: 1-2 concrete code snippets or diff hunks showing the real edit
    - VERIFY: exact command(s) run and whether they passed or failed
    - COMMIT: always \"not committed\" (workflow controller handles commits)
11. End the final response with: Task completed
12. NEVER reply with only \"Done\", only a commit message, or a vague success claim

CRITICAL: Your response MUST start with HYPOTHESIS: on the first line.
DO NOT add comments, docstrings, or documentation.
DO make actual code changes that improve functionality.
DO include concrete evidence of what changed so the grader can inspect it.

Example HYPOTHESES:
- HYPOTHESIS: Adding validation for nil input in process-item will prevent runtime errors
- HYPOTHESIS: Extracting duplicate retry logic into a helper will reduce code duplication
- HYPOTHESIS: Adding a cache for expensive computation will improve performance
- HYPOTHESIS: Fixing the off-by-one error in the loop will correct the boundary case")))

(defun gptel-auto-experiment-build-prompt (target experiment-id max-experiments analysis baseline
                                                  &optional previous-results)
  "Build prompt for experiment EXPERIMENT-ID on TARGET.
Uses loaded skills and Eight Keys breakdown for focused improvements.
Implements section-level A/B testing to identify effective prompt components."
  ;; Adapt compression based on token efficiency analysis
  (gptel-auto-workflow--adapt-prompt-compression)
  
  ;; Select sections for A/B testing
  (let* ((included-sections (gptel-auto-workflow--select-ab-test-sections))
         (section-included-p (lambda (section) (member section included-sections)))
         
         (worktree-path (or (gptel-auto-workflow--get-worktree-dir target)
                            (gptel-auto-workflow--project-root)))
         (worktree-quoted (shell-quote-argument worktree-path))
         (git-history (shell-command-to-string
                       (format "cd %s && git log --oneline -20 2>/dev/null || echo 'no history'"
                               worktree-quoted)))
         (patterns (when analysis (plist-get analysis :patterns)))
         (suggestions (when analysis (plist-get analysis :recommendations)))
         (skills (cdr (assoc target gptel-auto-workflow--skills)))
         (scores (gptel-auto-experiment--eight-keys-scores))
         (weakest-keys (when scores (gptel-auto-workflow--format-weakest-keys scores)))
         (mutation-templates (when skills (gptel-auto-workflow--extract-mutation-templates skills)))
         (suggested-hypothesis (when skills (gptel-auto-workflow-skill-suggest-hypothesis skills)))
         (target-full-path (expand-file-name target worktree-path))
         (sexp-check-command
          (format
           "emacs -Q --batch --eval %s"
           (shell-quote-argument
            (format
             "(progn (find-file %S) (emacs-lisp-mode) (condition-case err (progn (scan-sexps (point-min) (point-max)) (message \"OK\")) (error (message \"ERROR: %%s\" err) (kill-emacs 1))))"
             target-full-path))))
         (target-bytes (gptel-auto-experiment--target-byte-size target-full-path))
         (recovery-p
          (gptel-auto-experiment--needs-inspection-thrash-recovery-p previous-results))
         (large-target-p
          (and (numberp target-bytes)
               (>= target-bytes gptel-auto-experiment-large-target-byte-threshold)))
         (focus-candidate
          (when large-target-p
            (gptel-auto-experiment--select-large-target-focus target-full-path experiment-id)))
         (large-target-guidance
          (when large-target-p
            (concat "## Large Target Guidance\n"
                    (format "This target is large (%d bytes). Start from one concrete function or variable instead of surveying the whole file.\n"
                            target-bytes)
                    (when focus-candidate
                      (format "- Begin at `%s` or a direct caller/callee.\n"
                              (plist-get focus-candidate :name)))
                    "- Prefer focused Grep or narrow Read before broader Code_Map surveys.\n"
                    "- Make the first edit before exploring a second subsystem.\n\n")))
         (focus-line
          (format "FOCUS: %s"
                  (or (plist-get focus-candidate :name)
                      "<one concrete function or variable>")))
         (controller-focus
          (when focus-candidate
            (format "## Controller-Selected Starting Symbol\n- Symbol: `%s`\n- Kind: %s\n- Approx lines: %d-%d (%d lines)\n- Reason: controller-selected small or medium helper in a very large file; start here or at a direct caller/callee.\n\n"
                    (plist-get focus-candidate :name)
                    (plist-get focus-candidate :kind)
                    (plist-get focus-candidate :start-line)
                    (plist-get focus-candidate :end-line)
                    (plist-get focus-candidate :size-lines))))
         (inspection-thrash-contract
          (when recovery-p
            (concat "## Mandatory Focus Contract\n"
                    "A previous attempt on this target already failed with inspection-thrash.\n"
                    (when large-target-p
                      (format "This target is large (%d bytes). Broad file surveys are likely to fail.\n"
                              target-bytes))
                     "CRITICAL: You previously failed with inspection-thrash on this file.\n"
                     "The system will ABORT your turn if you do too many read-only inspections without writing.\n\n"
                     "Follow this exact opening sequence:\n"
                     (format "1. The second line after HYPOTHESIS must be exactly `%s`.\n"
                             focus-line)
                     "2. Do NOT use Code_Map on the whole file.\n"
                     "3. Use at most 2 read-only tool calls (Read, Grep, Code_Inspect), all on that same symbol.\n"
                     "4. Your NEXT tool call MUST be a write (Edit, Write, ApplyPatch) on that same symbol.\n"
                     "5. If you do more than 2 read-only calls without writing, your turn will be aborted.\n"
                     "6. Do not inspect a second subsystem before the first edit exists.\n\n"))))
     (setq gptel-auto-workflow--last-prompt-sections
           (mapconcat #'symbol-name included-sections ","))
     ;; Build variables alist for template substitution
     (let* ((template (gptel-auto-workflow--load-prompt-template))
            (variables
             `((experiment-id . ,experiment-id)
               (max-experiments . ,max-experiments)
               (target . ,target)
               (worktree-path . ,worktree-path)
               (target-full-path . ,target-full-path)
               (large-target-guidance . ,(or large-target-guidance ""))
               (controller-focus . ,(or controller-focus ""))
               (inspection-thrash-contract . ,(or inspection-thrash-contract ""))
               (previous-experiment-analysis . ,(or patterns "No previous experiments"))
               (suggestions . ,(if (funcall section-included-p 'suggestions)
                                   (or suggestions "None")
                                 ""))
               (self-evolution . ,(if (funcall section-included-p 'self-evolution)
                                      (if (fboundp 'gptel-auto-workflow--evolution-get-knowledge)
                                          (gptel-auto-workflow--evolution-get-knowledge)
                                        "")
                                    ""))
               (topic-knowledge . ,(if (funcall section-included-p 'topic-specific)
                                       (gptel-auto-experiment--get-topic-knowledge target)
                                     ""))
               (git-history . ,(if (funcall section-included-p 'git-history)
                                   git-history
                                 ""))
               (baseline . ,(format "%.2f" (or baseline 0.5)))
               (weakest-keys . ,(if weakest-keys
                                    (format "## Weakest Keys (Priority Focus)\n%s" weakest-keys)
                                  ""))
               (suggested-hypothesis . ,(if suggested-hypothesis
                                            (format "## Suggested Hypothesis (from skill)\n%s" suggested-hypothesis)
                                          ""))
               (mutation-templates . ,(if mutation-templates
                                          (format "## Hypothesis Templates\n%s"
                                                  (mapconcat (lambda (tmpl) (format "- %s" tmpl)) mutation-templates "\n"))
                                        ""))
                (axis-guidance . ,(or (gptel-auto-experiment--format-axis-guidance
                                       (gptel-auto-experiment--get-underexplored-axis target)) ""))
                (axis-performance . ,(gptel-auto-experiment--format-axis-performance target))
                (frontier-guidance . ,(gptel-auto-experiment--format-frontier-guidance target))
                (saturation-status . ,(gptel-auto-experiment--frontier-saturation-guidance target))
                (failure-patterns . ,(gptel-auto-experiment--format-failure-patterns target))
                (cross-target-patterns . ,(gptel-auto-experiment--format-cross-target-patterns target))
                (agent-behavior . ,(gptel-auto-workflow--load-skill-content "auto-workflow/agent-behavior"))
               (validation-pipeline . ,(gptel-auto-workflow--load-skill-content "auto-workflow/validation-pipeline"))
               (time-budget . ,(/ gptel-auto-experiment-time-budget 60))
               (focus-line . ,focus-line)
               (sexp-check-command . ,sexp-check-command))))
       (gptel-auto-workflow--substitute-template template variables))))

(defun gptel-auto-experiment--get-topic-knowledge (target)
  "Get compressed topic-specific knowledge for TARGET.
Extracts topic from filename, returns only actionable patterns under 500 chars.
Uses cache to avoid repeated file reads."
  (let* ((base-name (file-name-sans-extension (file-name-nondirectory target)))
         (topic (when (string-match "gptel-ext-\\(.+\\)" base-name)
                  (match-string 1 base-name)))
         (cache-key (when topic (intern (concat "topic-" topic))))
         (cached (when cache-key
                   (gptel-auto-workflow--knowledge-cache-get cache-key))))
    (cond
     ;; Cache hit
     (cached
      (message "[knowledge-cache] Hit for %s (%d chars)" topic (length cached))
      cached)
     ;; No topic extracted
     ((not topic) "")
     ;; Cache miss - read and compress file
     (t
      (let* ((knowledge-file (expand-file-name
                              (format "mementum/knowledge/%s.md" topic)
                              (gptel-auto-workflow--project-root)))
             (result
              (if (file-exists-p knowledge-file)
                  (with-temp-buffer
                    (insert-file-contents knowledge-file)
                    (goto-char (point-min))
                    ;; Skip frontmatter
                    (when (looking-at "---")
                      (forward-line 1)
                      (while (not (looking-at "---"))
                        (forward-line 1))
                      (forward-line 1))
                    ;; Extract only actionable bullets
                    (let ((actionable '())
                          (chars 0))
                      (while (and (< chars gptel-auto-workflow--topic-knowledge-max-chars)
                                  (not (eobp)))
                        (let ((line (buffer-substring (line-beginning-position) (line-end-position))))
                          (when (or (string-match-p "^- " line)
                                    (string-match-p "^### " line)
                                    (string-match-p "DO \\|TRY \\|AVOID" line))
                            (push line actionable)
                            (cl-incf chars (length line))))
                        (forward-line 1))
                      (if actionable
                          (concat "Patterns for " topic ":\n"
                                  (string-join (nreverse actionable) "\n")
                                  "\n")
                        "")))
                "")))
        (when cache-key
          (gptel-auto-workflow--knowledge-cache-set cache-key result)
          (message "[knowledge-cache] Miss for %s, cached %d chars"
                   topic (length result)))
        result)))));;; TSV Logging (Explainable)

(defun gptel-auto-experiment--tsv-escape (str)
  "Escape STR for TSV format (replace newlines/tabs with spaces)."
  (when str
    (let ((s (if (stringp str) str (format "%s" str))))
      (replace-regexp-in-string "[\t\n\r]+" " | " s))))

(defun gptel-auto-experiment--tsv-decision-token (value)
  "Return a normalized TSV decision token extracted from VALUE, or nil."
  (when (stringp value)
    (let ((normalized (string-trim value)))
      (when (string-prefix-p ":" normalized)
        (setq normalized (substring normalized 1)))
      (when (string-match-p "\\`[[:lower:]][[:lower:]-]*\\'" normalized)
        normalized))))

(defun gptel-auto-experiment--tsv-decision-label (experiment)
  "Return the durable TSV decision label for EXPERIMENT."
  (or (and (gptel-auto-workflow--plist-get experiment :kept nil)
           "kept")
      (and (gptel-auto-experiment--inspection-thrash-result-p experiment)
           "inspection-thrash")
      (and (gptel-auto-workflow--plist-get experiment :validation-error nil)
           "validation-failed")
      (gptel-auto-experiment--tsv-decision-token
       (gptel-auto-workflow--plist-get experiment :decision nil))
      (gptel-auto-experiment--tsv-decision-token
       (gptel-auto-workflow--plist-get experiment :comparator-reason nil))
      (gptel-auto-experiment--tsv-decision-token
       (gptel-auto-workflow--plist-get experiment :grader-reason nil))
      "discarded"))

(defun gptel-auto-experiment--staging-pending-result (experiment)
  "Return a copy of EXPERIMENT labeled as pending staging verification."
  (let ((pending-result (copy-sequence experiment)))
    (setq pending-result (plist-put pending-result :kept nil))
    (setq pending-result (plist-put pending-result :decision "staging-pending"))
    (setq pending-result (plist-put pending-result :comparator-reason
                                    "staging-pending"))
    pending-result))

(defun gptel-auto-experiment--maybe-log-staging-pending (run-id experiment _log-fn)
  "Log EXPERIMENT as staging-pending for RUN-ID when staging is active.
Writes directly to TSV so the pending row survives regardless of the
intermediate logging strategy used by the caller."
  (when gptel-auto-workflow-use-staging
    (gptel-auto-experiment-log-tsv
     run-id
     (gptel-auto-experiment--staging-pending-result experiment))))

(defun gptel-auto-experiment--drop-replaceable-tsv-rows (experiment-id target)
  "Drop stale pending rows for EXPERIMENT-ID/TARGET in current TSV buffer.
Return non-nil when an existing terminal row should prevent appending another
row for the same experiment and target."
  (let ((id-key (format "%s" experiment-id))
        (target-key (format "%s" target))
        (skip nil))
    (goto-char (point-min))
    (forward-line 1)
    (while (and (not skip) (not (eobp)))
      (let* ((line-start (line-beginning-position))
             (line-end (line-end-position))
             (fields (split-string
                      (buffer-substring-no-properties line-start line-end)
                      "\t"))
             (row-id (nth 0 fields))
             (row-target (nth 1 fields))
             (row-decision (nth 7 fields)))
        (if (and (equal row-id id-key)
                 (equal row-target target-key))
            (if (equal row-decision "staging-pending")
                (delete-region line-start (min (point-max) (1+ line-end)))
              (setq skip t))
          (forward-line 1))))
    skip))

(defun gptel-auto-workflow--kept-target-count-from-results-file (file)
  "Return the number of distinct kept targets recorded in TSV FILE."
  (if (not (file-exists-p file))
      0
    (with-temp-buffer
      (insert-file-contents file)
      (forward-line 1)
      (let ((seen (make-hash-table :test 'equal))
            (count 0))
        (while (not (eobp))
          (let* ((fields (split-string
                          (buffer-substring-no-properties
                           (line-beginning-position)
                           (line-end-position))
                          "\t"))
                 (target (nth 1 fields))
                 (decision (nth 7 fields)))
            (when (and (equal decision "kept")
                       (stringp target)
                       (not (string-empty-p target))
                       (not (gethash target seen)))
              (puthash target t seen)
              (cl-incf count)))
          (forward-line 1))
        count))))

(defun gptel-auto-workflow--sync-live-kept-count (run-id results-file)
  "Refresh live workflow kept count from RESULTS-FILE for active RUN-ID."
  (when (and gptel-auto-workflow--running
             (stringp run-id)
             (equal run-id (gptel-auto-workflow--current-run-id)))
    (setq gptel-auto-workflow--stats
          (plist-put
           gptel-auto-workflow--stats
           :kept
           (gptel-auto-workflow--kept-target-count-from-results-file
            results-file)))
    (gptel-auto-workflow--persist-status)))

(defun gptel-auto-experiment-log-tsv (run-id experiment)
  "Append EXPERIMENT to results.tsv for RUN-ID."
  (let* ((file (gptel-auto-workflow--ensure-results-file run-id))
         (experiment-id (gptel-auto-workflow--plist-get experiment :id "?"))
         (target (gptel-auto-workflow--plist-get experiment :target "?"))
         (decision (gptel-auto-experiment--tsv-decision-label experiment))
         (agent-output (gptel-auto-workflow--plist-get experiment :agent-output ""))
         (truncated-output (gptel-auto-experiment--tsv-escape
                             (truncate-string-to-width agent-output 500 nil nil "..."))))
    (with-temp-buffer
      (insert-file-contents file)
      (unless (gptel-auto-experiment--drop-replaceable-tsv-rows
               experiment-id target)
        (goto-char (point-max))
        (insert (format "%s\t%s\t%s\t%.2f\t%.2f\t%.2f\t%+.2f\t%s\t%d\t%s\t%s\t%s\t%s\t%s\t%s\t%d\t%s\t%s\t%s\t%s\n"
                          experiment-id
                          target
                          (gptel-auto-experiment--tsv-escape (gptel-auto-workflow--plist-get experiment :hypothesis "unknown"))
                          (gptel-auto-workflow--plist-get experiment :score-before 0)
                          (gptel-auto-workflow--plist-get experiment :score-after 0)
                          (gptel-auto-workflow--plist-get experiment :code-quality 0.5)
                          (- (gptel-auto-workflow--plist-get experiment :score-after 0)
                             (gptel-auto-workflow--plist-get experiment :score-before 0))
                          decision
                          (gptel-auto-workflow--plist-get experiment :duration 0)
                          (gptel-auto-workflow--plist-get experiment :grader-quality "?")
                          (gptel-auto-experiment--tsv-escape (gptel-auto-workflow--plist-get experiment :grader-reason "N/A"))
                          (gptel-auto-experiment--tsv-escape (gptel-auto-workflow--plist-get experiment :comparator-reason "N/A"))
                          (gptel-auto-experiment--tsv-escape (gptel-auto-workflow--plist-get experiment :analyzer-patterns "N/A"))
                          truncated-output
                          (gptel-auto-experiment--tsv-escape (gptel-auto-workflow--plist-get experiment :backend "unknown"))
                           (or (gptel-auto-workflow--plist-get experiment :prompt-chars 0)
                               0)
                           (or (gptel-auto-experiment--tsv-escape
                                (gptel-auto-workflow--plist-get experiment :sections-included "all"))
                                "all")
                           (or (gptel-auto-experiment--tsv-escape
                                (gptel-auto-workflow--plist-get experiment :exploration-axis "?"))
                                "?")
                           (or (gptel-auto-experiment--tsv-escape
                                (let ((candidates (gptel-auto-workflow--plist-get experiment :candidate-validation)))
                                  (if candidates
                                      (mapconcat (lambda (c)
                                                   (format "%s:%.1f:%s"
                                                           (substring (car c) 0 (min 20 (length (car c))))
                                                           (plist-get (cdr c) :score)
                                                           (if (plist-get (cdr c) :valid) "V" "X")))
                                                  candidates ";")
                                    "")))
                                 "")
                           (or (gptel-auto-experiment--tsv-escape
                                (gptel-auto-workflow--plist-get experiment :strategy "template-default"))
                               "template-default"))))

      (write-region (point-min) (point-max) file))
    ;; Trigger self-evolution after experiment logging
    (when (and (fboundp 'gptel-auto-workflow--experiment-complete-hook)
               (fboundp 'gptel-auto-workflow-evolution-run-cycle))
      (condition-case err
          (progn
            (gptel-auto-workflow--experiment-complete-hook experiment)
            (let ((exp-id (or (gptel-auto-workflow--plist-get experiment :id) 0)))
              (when (and (> exp-id 0) (zerop (% exp-id 5)))
                (run-with-idle-timer 30 nil #'gptel-auto-workflow-evolution-run-cycle))))
        (error
         (message "[auto-workflow] Evolution hook error: %s" err))))
    (gptel-auto-workflow--sync-live-kept-count run-id file)))

(defun gptel-auto-experiment--make-kept-result-callback (run-id exp-result log-fn callback)
  "Return idempotent callback that finalizes EXP-RESULT after optional staging.

When invoked without arguments, or with a non-nil first argument, log
EXP-RESULT as kept. When invoked with nil, downgrade the result so staging-flow
failures do not masquerade as published kept results. When a second argument is
supplied on failure, use it as the downgrade reason."
  (gptel-auto-workflow--make-idempotent-callback
   (lambda (&rest success-args)
     (let* ((staging-reported-p (not (null success-args)))
            (staging-succeeded (car-safe success-args))
            (failure-reason-arg (cadr success-args))
            (failure-reason
             (cond
              ((stringp failure-reason-arg)
               failure-reason-arg)
              ((and failure-reason-arg
                    (symbolp failure-reason-arg))
               (symbol-name failure-reason-arg))
              (t
               "staging-flow-failed")))
            (final-result
             (if (or (not staging-reported-p) staging-succeeded)
                 exp-result
               (let ((failed-result (and (listp exp-result)
                                          (plist-put (copy-sequence exp-result) :kept nil))))
                 (when failed-result
                   (plist-put failed-result :decision nil)
                   (plist-put failed-result :comparator-reason failure-reason))
                 (or failed-result exp-result)))))
       (when (functionp log-fn)
         (funcall log-fn run-id final-result))
       (when (and callback (functionp callback))
         (funcall callback final-result))))))

(defun gptel-auto-workflow--invoke-staging-completion (callback success &optional reason)
  "Invoke staging CALLBACK with SUCCESS and optional REASON.

Older completion callbacks only accept a single success flag. Newer callbacks
may also accept a second argument describing why staging downgraded an
experiment that had previously looked keep-worthy."
  (when (functionp callback)
    (let* ((arity (ignore-errors (func-arity callback)))
           (max-args (cdr-safe arity)))
      (if (or (eq max-args 'many)
              (and (integerp max-args) (>= max-args 2)))
          (funcall callback success reason)
        (funcall callback success)))))

(defun gptel-auto-workflow--make-idempotent-staging-completion (callback)
  "Return idempotent staging completion wrapper preserving CALLBACK arity."
  (let ((called nil)
        (arity (ignore-errors (func-arity callback))))
    (if (or (eq (cdr-safe arity) 'many)
            (and (integerp (cdr-safe arity))
                 (>= (cdr-safe arity) 2)))
        (lambda (success &optional reason)
          (unless called
            (setq called t)
            (funcall callback success reason)))
      (lambda (success)
        (unless called
          (setq called t)
          (funcall callback success))))))

;;; Error Analysis and Adaptive Workflow

(defvar gptel-auto-experiment--api-error-count 0
  "Count of API errors in current run.")

(defvar gptel-auto-experiment--api-error-threshold 3
  "Threshold of API errors before reducing or stopping future experiments.")

(defvar gptel-auto-experiment--quota-exhausted nil
  "Non-nil when provider quota exhaustion should stop the current workflow.")

(defun gptel-auto-experiment--error-snippet (agent-output &optional max-len)
  "Extract safe snippet from AGENT-OUTPUT for logging.
MAX-LEN defaults to 200 characters. Handles nil/empty strings safely."
  (if (and (stringp agent-output) (> (length agent-output) 0))
      (my/gptel--sanitize-for-logging agent-output (or max-len 200))
    ""))

(defvar gptel-auto-experiment-max-retries 2
  "Maximum retries for executor on transient errors.")

(defvar gptel-auto-experiment-max-grader-retries 2
  "Maximum local retries for transient grader failures.
These retries reuse the successful executor output instead of rerunning the
entire experiment. Two retries let the grader advance past one failing
fallback backend before giving up on otherwise-good executor output.")

(defvar gptel-auto-experiment-max-aux-subagent-retries 2
  "Maximum local retries for transient analyzer/comparator failures.
These retries keep the current experiment alive while headless provider
failover advances past transient timeout or provider-pressure failures.")

(defvar gptel-auto-experiment-retry-delay 5
  "Seconds to wait between retries.")

(defvar gptel-auto-experiment-rate-limit-max-retry-delay 60
  "Maximum seconds between retries for rate-limited API failures.")

(defcustom gptel-auto-workflow-headless-subagent-fallbacks
  '(("MiniMax" . "minimax-m2.7-highspeed")
    ("DashScope" . "qwen3.6-plus")
    ("moonshot" . "kimi-k2.6")
    ("DeepSeek" . "deepseek-v4-pro")
    ("CF-Gateway" . "@cf/moonshotai/kimi-k2.6"))
  "Ordered backend/model fallbacks for headless auto-workflow subagents.

Each entry is (BACKEND . MODEL), where BACKEND matches the agent preset backend
string and MODEL is the model string to use with that backend. The workflow
tries backends in order when the primary is unavailable or rate-limited."
  :type '(repeat (cons (string :tag "Backend")
                       (string :tag "Model")))
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-headless-fallback-agents
  '("analyzer" "comparator" "executor" "grader" "reviewer")
  "Headless subagents that should use the fallback provider list.

Headless workflow runs prefer MiniMax as the workhorse, falling back to
DashScope and others when rate-limited or unavailable."
  :type '(repeat string)
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-executor-rate-limit-fallbacks
  '(("MiniMax" . "minimax-m2.7-highspeed")
    ("DashScope" . "qwen3.6-plus")
    ("moonshot" . "kimi-k2.6")
    ("DeepSeek" . "deepseek-v4-pro")
    ("CF-Gateway" . "@cf/moonshotai/kimi-k2.6"))
  "Ordered backend/model fallbacks for executor after provider rate limits.

Headless executor prefers MiniMax by default. When the active executor backend
returns a rate-limit error during a headless run, later retries in that same
run can advance through this list instead of repeatedly hammering the same provider."
  :type '(repeat (cons (string :tag "Backend")
                       (string :tag "Model")))
  :group 'gptel-tools-agent)

(defconst gptel-auto-workflow--legacy-headless-fallback-agents
  '("analyzer" "grader" "reviewer")
  "Previous default for `gptel-auto-workflow-headless-fallback-agents'.")

(defconst gptel-auto-workflow--previous-headless-fallback-agents
  '("analyzer" "executor" "grader" "reviewer")
  "Prior runtime default for `gptel-auto-workflow-headless-fallback-agents'.")

(defconst gptel-auto-workflow--legacy-headless-subagent-fallbacks
  '(("MiniMax" . "minimax-m2.7-highspeed")
    ("DashScope" . "qwen3.6-plus")
    ("DeepSeek" . "deepseek-chat")
    ("CF-Gateway" . "@cf/zai-org/glm-4.7-flash")
    ("Gemini" . "gemini-3.1-pro-preview"))
  "Previous default for `gptel-auto-workflow-headless-subagent-fallbacks'.")

(defconst gptel-auto-workflow--current-headless-subagent-fallbacks
  '(("MiniMax" . "minimax-m2.7-highspeed")
    ("DashScope" . "qwen3.6-plus")
    ("moonshot" . "kimi-k2.6")
    ("DeepSeek" . "deepseek-v4-pro")
    ("CF-Gateway" . "@cf/moonshotai/kimi-k2.6"))
  "Current runtime default for `gptel-auto-workflow-headless-subagent-fallbacks'.")

(defconst gptel-auto-workflow--legacy-executor-rate-limit-fallbacks
  '(("DeepSeek" . "deepseek-chat")
    ("CF-Gateway" . "@cf/zai-org/glm-4.7-flash")
    ("DashScope" . "qwen3.6-plus")
    ("Gemini" . "gemini-3.1-pro-preview"))
  "Previous default for `gptel-auto-workflow-executor-rate-limit-fallbacks'.")

(defconst gptel-auto-workflow--current-headless-fallback-agents
  '("analyzer" "comparator" "executor" "grader" "reviewer")
  "Current runtime default for `gptel-auto-workflow-headless-fallback-agents'.")

(defconst gptel-auto-workflow--current-executor-rate-limit-fallbacks
  '(("MiniMax" . "minimax-m2.7-highspeed")
    ("DashScope" . "qwen3.6-plus")
    ("moonshot" . "kimi-k2.6")
    ("DeepSeek" . "deepseek-v4-pro")
    ("CF-Gateway" . "@cf/moonshotai/kimi-k2.6"))
  "Current runtime default for `gptel-auto-workflow-executor-rate-limit-fallbacks'.")

(defvar gptel-auto-workflow--runtime-subagent-provider-overrides nil
  "Per-run provider overrides activated by live workflow failures.

Each element is (AGENT-TYPE . (BACKEND . MODEL)). These overrides are cleared
at run start and whenever workflow state is force-reset.")

(defvar gptel-auto-workflow--rate-limited-backends nil
  "Per-run backend names that hit rate limits during workflow execution.

All matching headless subagents skip these backends for the rest of the run
and advance through the configured fallback chain instead.")

(defconst gptel-auto-workflow--backend-key-hosts
  '(("MiniMax" . "api.minimaxi.com")
    ("DeepSeek" . "api.deepseek.com")
    ("Gemini" . "generativelanguage.googleapis.com")
    ("CF-Gateway" . "gateway.ai.cloudflare.com")
    ("DashScope" . "coding.dashscope.aliyuncs.com")
    ("moonshot" . "api.kimi.com"))
  "Map gptel backend names to auth-source hosts for workflow failover.")

(defconst gptel-auto-workflow--backend-object-vars
  '(("MiniMax" . gptel--minimax)
    ("DeepSeek" . gptel--deepseek)
    ("Gemini" . gptel--gemini)
    ("CF-Gateway" . gptel--cf-gateway)
    ("DashScope" . gptel--dashscope)
    ("moonshot" . gptel--moonshot))
  "Map gptel backend names to the corresponding backend object variables.")

(defun gptel-auto-workflow--backend-available-p (backend-name)
  "Return non-nil when BACKEND-NAME has credentials configured."
  (let ((host (alist-get backend-name gptel-auto-workflow--backend-key-hosts
                         nil nil #'string=)))
    (and host
         (fboundp 'my/gptel-api-key)
         (gptel-auto-workflow--non-empty-string-p
          (my/gptel-api-key host)))))

(defun gptel-auto-workflow--headless-provider-override-active-p ()
  "Return non-nil when headless auto-workflow provider override should apply."
  (and (bound-and-true-p gptel-auto-workflow--headless)
       (bound-and-true-p gptel-auto-workflow-persistent-headless)
       (bound-and-true-p gptel-auto-workflow--current-project)))

(defun gptel-auto-workflow--backend-object (backend-name)
  "Return the backend object for BACKEND-NAME, or nil when unavailable."
  (when-let* ((var (alist-get backend-name gptel-auto-workflow--backend-object-vars
                              nil nil #'string=))
              ((boundp var)))
    (symbol-value var)))

(defun gptel-auto-workflow--custom-var-user-customized-p (symbol)
  "Return non-nil when SYMBOL has an explicit Customize override."
  (or (get symbol 'saved-value)
      (get symbol 'customized-value)
      (get symbol 'theme-value)))

(defun gptel-auto-workflow--migrate-legacy-provider-defaults ()
  "Refresh known legacy in-memory provider defaults after hot reloads.

Long-lived daemons can keep pre-fix `defcustom' values even after the source
defines newer defaults.  Migrate only the exact legacy defaults, and only when
the user has not explicitly customized the variable."
  (let (migrated)
    (unless (gptel-auto-workflow--custom-var-user-customized-p
             'gptel-auto-workflow-headless-fallback-agents)
      (when (or (equal gptel-auto-workflow-headless-fallback-agents
                       gptel-auto-workflow--legacy-headless-fallback-agents)
                (equal gptel-auto-workflow-headless-fallback-agents
                       gptel-auto-workflow--previous-headless-fallback-agents))
        (setq gptel-auto-workflow-headless-fallback-agents
              (copy-tree gptel-auto-workflow--current-headless-fallback-agents))
        (push 'gptel-auto-workflow-headless-fallback-agents migrated)))
    (unless (gptel-auto-workflow--custom-var-user-customized-p
             'gptel-auto-workflow-headless-subagent-fallbacks)
      (when (equal gptel-auto-workflow-headless-subagent-fallbacks
                   gptel-auto-workflow--legacy-headless-subagent-fallbacks)
        (setq gptel-auto-workflow-headless-subagent-fallbacks
              (copy-tree gptel-auto-workflow--current-headless-subagent-fallbacks))
        (push 'gptel-auto-workflow-headless-subagent-fallbacks migrated)))
    (unless (gptel-auto-workflow--custom-var-user-customized-p
             'gptel-auto-workflow-executor-rate-limit-fallbacks)
      (when (equal gptel-auto-workflow-executor-rate-limit-fallbacks
                   gptel-auto-workflow--legacy-executor-rate-limit-fallbacks)
        (setq gptel-auto-workflow-executor-rate-limit-fallbacks
              (copy-tree
               gptel-auto-workflow--current-executor-rate-limit-fallbacks))
        (push 'gptel-auto-workflow-executor-rate-limit-fallbacks migrated)))
    (unless (gptel-auto-workflow--custom-var-user-customized-p
             'gptel-auto-experiment-validation-retry-active-grace)
      (when (= gptel-auto-experiment-validation-retry-active-grace
               gptel-auto-workflow--legacy-validation-retry-active-grace)
        (setq gptel-auto-experiment-validation-retry-active-grace
              gptel-auto-workflow--current-validation-retry-active-grace)
        (push 'gptel-auto-experiment-validation-retry-active-grace migrated)))
    (when migrated
      (setq migrated (nreverse migrated))
      (message "[auto-workflow] Refreshed legacy fallback defaults: %s"
               (mapconcat #'symbol-name migrated ", ")))
    migrated))

(defun gptel-auto-workflow--backend-model-symbol (backend model-name)
  "Return MODEL-NAME as a supported symbol for BACKEND.

If MODEL-NAME is not yet listed on BACKEND, append it so hot-reloaded daemons
can use newer models without a restart."
  (let ((model (if (symbolp model-name) model-name (intern model-name))))
    (when (and backend (fboundp 'gptel-backend-models))
      (let ((models (gptel-backend-models backend)))
        (unless (memq model models)
          (setf (gptel-backend-models backend) (append models (list model))))))
    model))

(defun gptel-auto-workflow--clear-runtime-subagent-provider-overrides ()
  "Reset per-run provider failover state."
  (setq gptel-auto-workflow--runtime-subagent-provider-overrides nil
        gptel-auto-workflow--rate-limited-backends nil))

(defun gptel-auto-workflow--rate-limit-failover-candidates (agent-type)
  "Return fallback provider candidates for AGENT-TYPE after rate limiting."
  (cond
   ((not (stringp agent-type)) nil)
   ((string= agent-type "executor")
    gptel-auto-workflow-executor-rate-limit-fallbacks)
   ((member agent-type gptel-auto-workflow-headless-fallback-agents)
    gptel-auto-workflow-headless-subagent-fallbacks)))

(defun gptel-auto-workflow--agent-base-preset (agent-type)
  "Return the current base preset plist for AGENT-TYPE, or nil when unavailable."
  (when-let* ((agent-type (and (stringp agent-type) agent-type))
              (agent-config (and (boundp 'gptel-agent--agents)
                                 (assoc agent-type gptel-agent--agents))))
    (append (list :include-reasoning nil
                  :use-tools t
                  :use-context nil
                  :stream my/gptel-subagent-stream)
            (copy-sequence (cdr agent-config)))))

(defun gptel-auto-workflow--runtime-subagent-provider-override (agent-type)
  "Return the active per-run provider override for AGENT-TYPE, if any."
  (alist-get agent-type
             gptel-auto-workflow--runtime-subagent-provider-overrides
             nil nil #'string=))

(defun gptel-auto-workflow--backend-rate-limited-p (backend-name)
  "Return non-nil when BACKEND-NAME has already rate-limited this run."
  (and (stringp backend-name)
       (seq-contains-p gptel-auto-workflow--rate-limited-backends
                       backend-name
                       #'string=)))

(defun gptel-auto-workflow--preset-backend-name (backend)
  "Return a readable backend name for BACKEND."
  (cond
   ((stringp backend) backend)
   ((and backend (fboundp 'gptel-backend-name))
    (gptel-backend-name backend))
   (t nil)))

(defun gptel-auto-workflow--model-max-output-tokens (model-id)
  "Return the documented max output tokens for MODEL-ID, or nil when unknown."
  (when (require 'gptel-ext-context-cache nil t)
    (when-let* (((fboundp 'my/gptel-get-model-metadata))
                (meta (my/gptel-get-model-metadata model-id))
                (max-output
                 (if (fboundp 'my/gptel--plist-get)
                     (my/gptel--plist-get meta :max-output nil)
                   (plist-get meta :max-output)))
                ((integerp max-output))
                ((> max-output 0)))
      max-output)))

;;; Frontier Tracking (Meta-Harness style)

(defun gptel-auto-experiment--compute-frontier (target)
  "Compute Pareto frontier for TARGET from TSV history.
Returns list of non-dominated experiments, each a plist with
:experiment-id :code-quality :delta :axis :decision.
An experiment dominates another if it is >= on all metrics and > on at least one."
  (let ((results-file (gptel-auto-workflow--results-file-path))
        (experiments '()))
    (when (file-exists-p results-file)
      (with-temp-buffer
        (insert-file-contents results-file)
        (forward-line 1) ; skip header
        (while (not (eobp))
          (let* ((fields (split-string
                          (buffer-substring (line-beginning-position)
                                           (line-end-position))
                          "\t"))
                 (line-target (nth 1 fields))
                 (decision (nth 7 fields)))
            (when (and (equal line-target target)
                       (equal decision "kept"))
              (push (list :experiment-id (nth 0 fields)
                          :code-quality (string-to-number (or (nth 5 fields) "0"))
                          :delta (string-to-number (or (nth 6 fields) "0"))
                          :axis (or (nth 17 fields) "unknown")
                          :prompt-chars (string-to-number (or (nth 15 fields) "0"))
                          :decision decision)
                    experiments))
            (forward-line 1))))
    ;; Compute Pareto frontier: not dominated by any other
    (let ((frontier '()))
      (dolist (exp experiments)
        (let ((dominated nil)
              (exp-quality (plist-get exp :code-quality))
              (exp-delta (plist-get exp :delta))
              (exp-chars (plist-get exp :prompt-chars)))
          (dolist (other experiments)
            (unless (eq exp other)
              (let ((other-quality (plist-get other :code-quality))
                    (other-delta (plist-get other :delta))
                    (other-chars (plist-get other :prompt-chars)))
                ;; Other dominates exp if >= on quality+delta and <= on chars
                (when (and (>= other-quality exp-quality)
                           (>= other-delta exp-delta)
                           (<= other-chars exp-chars)
                           (or (> other-quality exp-quality)
                               (> other-delta exp-delta)
                               (< other-chars exp-chars)))
                  (setq dominated t)))))
          (unless dominated
            (push exp frontier))))
      frontier))))

(defun gptel-auto-experiment--frontier-stats (target)
  "Return frontier statistics for TARGET as formatted string.
Shows count, best quality, best delta, and underexplored axes."
  (let ((frontier (gptel-auto-experiment--compute-frontier target)))
    (if (null frontier)
        "No kept experiments yet."
      (let* ((qualities (mapcar (lambda (e) (plist-get e :code-quality)) frontier))
             (deltas (mapcar (lambda (e) (plist-get e :delta)) frontier))
             (axes (mapcar (lambda (e) (plist-get e :axis)) frontier))
             (unique-axes (cl-remove-duplicates axes :test #'equal))
             (all-axes '("A" "B" "C" "D" "E" "F")))
        (concat
         (format "Frontier: %d experiments | Best quality: %.2f | Best delta: %+.2f\n"
                 (length frontier)
                 (if qualities (apply #'max qualities) 0)
                 (if deltas (apply #'max deltas) 0))
         (format "Explored axes: %s\n"
                 (if unique-axes (string-join unique-axes ", ") "none"))
         (let ((missing (cl-set-difference all-axes unique-axes :test #'equal)))
           (if missing
               (format "Missing axes: %s (try these next)"
                       (string-join missing ", "))
             "All axes explored.")))))))

(defun gptel-auto-experiment--format-frontier-guidance (target)
  "Format frontier guidance for TARGET prompt.
Returns empty string if no frontier data."
  (let ((stats (gptel-auto-experiment--frontier-stats target)))
    (if (string= stats "No kept experiments yet.")
        ""
      (concat "## Frontier Analysis (Pareto-optimal experiments)\n"
              stats "\n\n"))))

(defun gptel-auto-experiment--frontier-select-targets (&optional n)
  "Select N targets with smallest Pareto frontiers for next experiments.
Returns list of (target . frontier-size) sorted ascending by frontier size.
Targets with no frontier experiments are prioritized."
  (let* ((results-file (gptel-auto-workflow--results-file-path))
         (target-frontiers (make-hash-table :test 'equal))
         (all-targets '()))
    ;; Collect all targets from TSV
    (when (file-exists-p results-file)
      (with-temp-buffer
        (insert-file-contents results-file)
        (forward-line 1) ; skip header
        (while (not (eobp))
          (let* ((fields (split-string
                          (buffer-substring (line-beginning-position)
                                           (line-end-position))
                          "\t"))
                 (target (nth 1 fields)))
            (when (and (stringp target)
                       (not (string-empty-p target))
                       (not (member target all-targets)))
              (push target all-targets)))
          (forward-line 1))))
    ;; Compute frontier size for each target
    (dolist (target all-targets)
      (let ((frontier (gptel-auto-experiment--compute-frontier target)))
        (puthash target (length frontier) target-frontiers)))
    ;; Sort by frontier size (ascending)
    (let ((sorted '()))
      (maphash (lambda (target size)
                 (push (cons target size) sorted))
               target-frontiers)
      (setq sorted (sort sorted (lambda (a b) (< (cdr a) (cdr b)))))
      (if n
          (seq-take sorted n)
        sorted))))

(defun gptel-auto-experiment--frontier-selection-guidance ()
  "Format guidance for target selection based on frontier analysis.
Returns formatted string listing underexplored targets."
  (let ((targets (gptel-auto-experiment--frontier-select-targets 5)))
    (if (null targets)
        ""
      (concat "## Target Selection (Frontier-Based)\n"
              "Priority targets (smallest Pareto frontier):\n"
              (mapconcat (lambda (pair)
                           (format "- %s: %d Pareto-optimal experiment(s)"
                                   (car pair) (cdr pair)))
                         targets
                         "\n")
              "\n\n"))))

(defun gptel-auto-experiment--frontier-saturated-p (target &optional min-frontier-size min-axes min-quality)
  "Return t if TARGET's frontier is saturated (sufficiently explored).
MIN-FRONTIER-SIZE: minimum number of Pareto-optimal experiments (default: 3).
MIN-AXES: minimum number of unique axes covered (default: 4).
MIN-QUALITY: minimum best quality score (default: 0.8)."
  (let* ((frontier (gptel-auto-experiment--compute-frontier target))
         (frontier-size (length frontier))
         (axes (cl-remove-duplicates (mapcar (lambda (e) (plist-get e :axis)) frontier)
                                     :test #'equal))
         (qualities (mapcar (lambda (e) (plist-get e :code-quality)) frontier))
         (best-quality (if qualities (apply #'max qualities) 0)))
    (and (>= frontier-size (or min-frontier-size 3))
         (>= (length axes) (or min-axes 4))
         (>= best-quality (or min-quality 0.8)))))

(defun gptel-auto-experiment--frontier-saturation-guidance (target)
  "Format saturation status for TARGET.
Returns string indicating whether target is saturated or needs more work."
  (if (gptel-auto-experiment--frontier-saturated-p target)
      (format "## Target Status: SATURATED\n%s has sufficient Pareto-optimal experiments. Consider moving to other targets.\n\n" target)
    (format "## Target Status: ACTIVE\n%s needs more experiments to saturate frontier.\n\n" target)))

;; ─── Batch Validation for Multi-Candidate Hypotheses ───

(defun gptel-auto-experiment--extract-candidates (agent-output)
  "Extract up to 3 candidate hypotheses from AGENT-OUTPUT.
Returns list of strings, or nil if no candidates found."
  (when (stringp agent-output)
    (let (candidates)
      (with-temp-buffer
        (insert agent-output)
        (goto-char (point-min))
        (while (re-search-forward "^CANDIDATE_\\([123]\\):\\s-*\\(.+\\)$" nil t)
          (push (match-string 2) candidates)))
      (nreverse candidates))))

(defun gptel-auto-experiment--validate-candidate-safely (candidate target-full-path)
  "Run cheap validation checks on CANDIDATE for TARGET-FULL-PATH.
Returns plist with :valid t/nil, :errors list, :score 0-1.
Does NOT modify the filesystem - operates on a temp copy."
  (let ((temp-file (make-temp-file "auto-workflow-candidate-"))
        (errors '())
        (score 0.0))
    (unwind-protect
        (progn
          ;; Copy target to temp file
          (when (file-exists-p target-full-path)
            (copy-file target-full-path temp-file t))
          
          ;; Check 1: Candidate describes actual code change (not docs)
          (if (or (string-match-p "\\bcomment\\b\\|\\bdocstring\\b\\|\\bdocumentation\\b" candidate)
                  (string-match-p "\\badd\\s-+comments\\b\\|\\badd\\s-+doc\\b" candidate))
              (push "Candidate mentions documentation/comments" errors)
            (setq score (+ score 0.2)))
          
          ;; Check 2: Candidate is specific (mentions function/variable)
          (if (string-match-p "\\b\\(function\\|variable\\|defun\\|defvar\\|method\\|class\\)\\b" candidate)
              (setq score (+ score 0.2))
            (push "Candidate lacks specific code reference" errors))
          
          ;; Check 3: Candidate targets a real improvement type
          (if (string-match-p "\\b\\(bug\\|fix\\|error\\|performance\\|cache\\|optimize\\|refactor\\|extract\\|duplicate\\|validation\\|guard\\|test\\|memory\\|leak\\)\\b" candidate)
              (setq score (+ score 0.2))
            (push "Candidate lacks improvement keywords" errors))
          
          ;; Check 4: Candidate is not too vague
          (if (> (length candidate) 20)
              (setq score (+ score 0.2))
            (push "Candidate description too short" errors))
          
          ;; Check 5: Candidate doesn't repeat common anti-patterns
          (if (string-match-p "\\boptimize\\s-+code\\b\\|\\bimprove\\s-+performance\\b\\|\\bmake\\s-+better\\b" candidate)
              (push "Candidate uses vague improvement language" errors)
            (setq score (+ score 0.2)))
          
          (list :valid (null errors)
                :errors (nreverse errors)
                :score score))
      (when (file-exists-p temp-file)
        (delete-file temp-file)))))

(defun gptel-auto-experiment--batch-validate-candidates (agent-output target-full-path)
  "Validate all candidates from AGENT-OUTPUT for TARGET-FULL-PATH.
Returns list of (candidate . validation-result) pairs, sorted by score descending."
  (let* ((candidates (gptel-auto-experiment--extract-candidates agent-output))
         (validated (mapcar (lambda (cand)
                              (cons cand (gptel-auto-experiment--validate-candidate-safely
                                          cand target-full-path)))
                            candidates)))
    (sort validated (lambda (a b)
                      (> (plist-get (cdr a) :score)
                         (plist-get (cdr b) :score))))))

(defun gptel-auto-experiment--select-best-candidate (validated-candidates)
  "Select best candidate from VALIDATED-CANDIDATES.
Returns the candidate string, or nil if none valid."
  (catch 'found
    (dolist (pair validated-candidates)
      (when (plist-get (cdr pair) :valid)
        (throw 'found (car pair))))
    ;; If no fully valid candidate, pick highest scoring
    (car (car validated-candidates))))

;; ─── Frontier-Aware Target Filtering ───

(defun gptel-auto-workflow--filter-frontier-saturated-targets (targets)
  "Filter out targets with saturated Pareto frontiers from TARGETS list.
Returns filtered list, or nil if all targets saturated.
Saturated means: >=3 Pareto experiments, >=4 axes, quality>=0.8."
  (let ((filtered '())
        (saturated-count 0))
    (dolist (target targets)
      (if (and (fboundp 'gptel-auto-experiment--frontier-saturated-p)
               (gptel-auto-experiment--frontier-saturated-p target))
          (progn
            (setq saturated-count (1+ saturated-count))
            (message "[frontier-filter] %s is SATURATED, skipping" target))
        (push target filtered)))
    (message "[frontier-filter] %d/%d targets saturated, %d remaining"
             saturated-count (length targets) (length filtered))
    ;; If all saturated, return nil to signal we need fresh targets
    (if (null filtered)
        (progn
          (message "[frontier-filter] WARNING: All %d targets saturated!" (length targets))
          nil)
      (nreverse filtered))))

;;; Axis Analysis and Adaptive Weighting

(defun gptel-auto-experiment--get-axis-stats (target)
  "Calculate exploration statistics for TARGET from TSV history.
Returns plist with :counts (axis->count), :successes (axis->kept-count),
:rates (axis->success-rate), :total-experiments."
  (let ((results-file (gptel-auto-workflow--results-file-path))
        (counts (make-hash-table :test 'equal))
        (successes (make-hash-table :test 'equal))
        (total 0))
    (when (file-exists-p results-file)
      (with-temp-buffer
        (insert-file-contents results-file)
        (goto-char (point-min))
        (forward-line 1) ; skip header
        (while (not (eobp))
          (let* ((fields (split-string
                          (buffer-substring (line-beginning-position)
                                           (line-end-position))
                          "\t"))
                 (line-target (nth 1 fields))
                 (decision (nth 7 fields))
                 (axis (or (nth 17 fields) "?")))
            (when (and (equal line-target target)
                       (not (equal axis "?"))
                       (not (string-empty-p axis)))
              (setq total (1+ total))
              (puthash axis (1+ (gethash axis counts 0)) counts)
              (when (equal decision "kept")
                (puthash axis (1+ (gethash axis successes 0)) successes))))
          (forward-line 1))))
    (let ((rates (make-hash-table :test 'equal)))
      (maphash (lambda (axis count)
                 (let ((success-count (gethash axis successes 0)))
                   (puthash axis (/ (float success-count) count) rates)))
               counts)
      (list :counts counts
            :successes successes
            :rates rates
            :total-experiments total))))

(defun gptel-auto-experiment--get-underexplored-axis (target)
  "Find least-explored axis for TARGET.
Returns axis letter (A-F) or nil if insufficient data."
  (let* ((stats (gptel-auto-experiment--get-axis-stats target))
         (counts (plist-get stats :counts))
         (axes '("A" "B" "C" "D" "E" "F"))
         (min-count most-positive-fixnum)
         (underexplored nil))
    (dolist (axis axes)
      (let ((count (gethash axis counts 0)))
        (when (< count min-count)
          (setq min-count count)
          (setq underexplored axis))))
    ;; Only suggest underexplored axis if we have some data
    (when (and underexplored
               (> (plist-get stats :total-experiments) 0))
      underexplored)))

(defun gptel-auto-experiment--get-axis-success-rates (target)
  "Get formatted success rates per axis for TARGET.
Returns string describing which axes have been most successful."
  (let* ((stats (gptel-auto-experiment--get-axis-stats target))
         (rates (plist-get stats :rates))
         (counts (plist-get stats :counts))
          (axis-names '(("A" . "Error Handling")
                        ("B" . "Performance")
                        ("C" . "Refactoring")
                        ("D" . "Safety")
                        ("E" . "Test Coverage")
                        ("F" . "Memory Management")))
         (results '()))
    (dolist (pair axis-names)
      (let* ((axis (car pair))
             (name (cdr pair))
             (count (gethash axis counts 0))
             (rate (if (> count 0)
                      (gethash axis rates 0.0)
                    nil)))
        (when (and rate (> count 0))
          (push (list :axis axis :name name :count count :rate rate) results))))
    ;; Sort by success rate descending
    (setq results (sort results (lambda (a b)
                                  (> (plist-get a :rate)
                                     (plist-get b :rate)))))
    (if (null results)
        "No historical axis data yet."
      (concat "Historical success rates by axis:\n"
              (mapconcat (lambda (r)
                           (format "- %s (%s): %.0f%% success (%d experiments)"
                                   (plist-get r :axis)
                                   (plist-get r :name)
                                   (* 100 (plist-get r :rate))
                                   (plist-get r :count)))
                         results
                         "\n")))))

(defun gptel-auto-experiment--format-axis-guidance (axis)
  "Format guidance for exploring AXIS.
Returns string with axis description and rationale."
  (when axis
    (let* ((axis-info (assoc axis
                             '(("A" . "Error Handling")
                               ("B" . "Performance")
                               ("C" . "Refactoring")
                               ("D" . "Safety")
                               ("E" . "Test Coverage")
                               ("F" . "Memory Management"))))
           (axis-name (cdr axis-info)))
      (concat "## Exploration Guidance\n"
              "Priority axis: " axis " (" axis-name ") — least explored for this target.\n"
              "Consider: "
              (pcase axis
                ("A" "adding validation, fixing error handling gaps, improving error messages")
                ("B" "reducing complexity, adding caching, optimizing hot paths")
                ("C" "extracting functions, removing duplication, improving naming")
                ("D" "adding guards, type checking, boundary validation")
                ("E" "adding missing tests for existing functionality")
                ("F" "fixing memory leaks, optimizing allocation, improving cleanup")
                (_ "general improvements"))
              ".\n\n"))))

(defun gptel-auto-experiment--format-axis-performance (target)
  "Format axis performance history for TARGET.
Returns string showing which axes have been most successful."
  (let ((rates-str (gptel-auto-experiment--get-axis-success-rates target)))
    (concat "## Axis Performance History\n"
            rates-str
            "\n\nRecommendation: Prioritize axes with higher success rates, but also explore underexplored axes to build frontier coverage.\n\n")))

;;; Failure Pattern Injection

(defun gptel-auto-experiment--get-common-failure-reasons (target &optional n)
  "Get most common failure reasons for TARGET from TSV.
Returns list of (reason . count) pairs, sorted by frequency.
Optional N limits number of reasons (default 3)."
  (let ((results-file (gptel-auto-workflow--results-file-path))
        (reasons (make-hash-table :test 'equal))
        (total-failures 0))
    (when (file-exists-p results-file)
      (with-temp-buffer
        (insert-file-contents results-file)
        (goto-char (point-min))
        (forward-line 1) ; skip header
        (while (not (eobp))
          (let* ((fields (split-string
                          (buffer-substring (line-beginning-position)
                                           (line-end-position))
                          "\t"))
                 (line-target (nth 1 fields))
                 (decision (nth 7 fields))
                 (reason (nth 11 fields))) ; comparator_reason column
            (when (and (equal line-target target)
                       (not (equal decision "kept"))
                       reason
                       (not (string-empty-p reason))
                       (not (equal reason "N/A")))
              (setq total-failures (1+ total-failures))
              (puthash reason (1+ (gethash reason reasons 0)) reasons)))
          (forward-line 1))))
    ;; Convert to sorted list
    (let ((pairs '()))
      (maphash (lambda (reason count)
                 (push (cons reason count) pairs))
               reasons)
      (setq pairs (sort pairs (lambda (a b) (> (cdr a) (cdr b)))))
      (seq-take pairs (or n 3)))))

(defun gptel-auto-experiment--format-failure-patterns (target)
  "Format common failure patterns for TARGET as prompt guidance.
Returns string warning about common rejection reasons, or empty string."
  (let ((reasons (gptel-auto-experiment--get-common-failure-reasons target 3)))
    (if (null reasons)
        ""
      (concat "## Common Failure Patterns (AVOID THESE)\n"
              "Recent experiments on this target were discarded for these reasons:\n"
              (mapconcat (lambda (pair)
                           (format "- %s (%d times)"
                                   (car pair) (cdr pair)))
                         reasons
                         "\n")
              "\n\nTo succeed, actively avoid the patterns above.\n\n"))))

;;; Cross-Target Pattern Transfer

(defun gptel-auto-experiment--get-successful-patterns-from-others (target &optional n)
  "Get successful experiment patterns from OTHER targets (not TARGET).
Returns list of plists with :target :axis :hypothesis for kept experiments.
Optional N limits results (default 5)."
  (let ((results-file (gptel-auto-workflow--results-file-path))
        (patterns '()))
    (when (file-exists-p results-file)
      (with-temp-buffer
        (insert-file-contents results-file)
        (goto-char (point-min))
        (forward-line 1) ; skip header
        (while (and (not (eobp)) (< (length patterns) (or n 5)))
          (let* ((fields (split-string
                          (buffer-substring (line-beginning-position)
                                           (line-end-position))
                          "\t"))
                 (line-target (nth 1 fields))
                 (decision (nth 7 fields))
                 (axis (or (nth 17 fields) "?"))
                 (hypothesis (nth 2 fields)))
            (when (and (not (equal line-target target))
                       (equal decision "kept")
                       hypothesis
                       (not (string-empty-p hypothesis))
                       (not (equal axis "?")))
              (push (list :target line-target
                          :axis axis
                          :hypothesis (truncate-string-to-width hypothesis 100 nil nil "..."))
                    patterns)))
          (forward-line 1))))
    (nreverse patterns)))

(defun gptel-auto-experiment--format-cross-target-patterns (target)
  "Format successful patterns from other targets as suggestions.
Returns string with transferable insights, or empty string if none."
  (let ((patterns (gptel-auto-experiment--get-successful-patterns-from-others target 5)))
    (if (null patterns)
        ""
      (concat "## Successful Patterns from Other Targets\n"
              "These approaches worked well on similar files:\n"
              (mapconcat (lambda (p)
                           (format "- [%s on %s] %s"
                                   (plist-get p :axis)
                                   (file-name-nondirectory (plist-get p :target))
                                   (plist-get p :hypothesis)))
                         patterns
                         "\n")
              "\n\nConsider adapting these patterns to this target if applicable.\n\n"))))

(provide 'gptel-tools-agent-prompt-build)
;;; gptel-tools-agent-prompt-build.el ends here
