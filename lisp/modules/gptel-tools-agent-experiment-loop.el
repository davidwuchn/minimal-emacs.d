; -*- lexical-binding: t; -*-
(require 'cl-lib)
(require 'subr-x)
(declare-function magit-git-success "magit-git")
(declare-function cl-subseq "cl-lib")
(declare-function gptel-auto-workflow--call-in-run-context "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--default-dir "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--plist-get "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--resolve-run-root "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--results-relative-path "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--shell-command-string "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--shell-command-with-timeout "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--validate-non-empty-string "gptel-tools-agent-base")
(declare-function gptel-auto-experiment--code-quality-score "gptel-tools-agent-benchmark")
(declare-function gptel-auto-experiment-benchmark "gptel-tools-agent-benchmark")
(declare-function gptel-auto-experiment--aborted-agent-output-p "gptel-tools-agent-error")
(declare-function gptel-auto-experiment--adaptive-max-experiments "gptel-tools-agent-error")
(declare-function my/gptel--sanitize-for-logging "gptel-tools-agent-git")
(declare-function gptel-auto-workflow--stop-status-refresh-timer "gptel-tools-agent-main")
(declare-function gptel-auto-workflow--clear-runtime-subagent-provider-overrides "gptel-tools-agent-prompt-build")
(declare-function gptel-auto-workflow--create-staging-worktree "gptel-tools-agent-worktree")
(declare-function gptel-auto-workflow--staging-submodule-gitlink-revision "gptel-tools-agent-worktree")
(declare-function gptel-auto-workflow--staging-submodule-paths "gptel-tools-agent-worktree")
(declare-function gptel-auto-experiment--run-with-retry "gptel-tools-agent-error")
(declare-function gptel-auto-experiment--result-hard-timeout-p "gptel-tools-agent-error")
(declare-function gptel-auto-workflow--run-callback-live-p "gptel-tools-agent-base")
;;; gptel-tools-agent-experiment-loop.el --- Experiment loop, status management -*- lexical-binding: t; -*-
;; Part of gptel-tools-agent split

(declare-function gptel-auto-experiment--frontier-saturated-p "gptel-tools-agent-prompt-build" (target &optional min-frontier-size min-axes min-quality))
(declare-function gptel-auto-experiment--compute-frontier "gptel-tools-agent-prompt-build" (target))
(declare-function gptel-auto-workflow--target-saturated-p "gptel-auto-workflow-ontology-predict" (target &optional max-experiments))

(defvar gptel-auto-experiment-max-per-target)
(defvar gptel-auto-experiment-no-improvement-threshold)
(defvar gptel-auto-workflow--run-id nil)
(defvar gptel-auto-experiment--quota-exhausted nil)
(defvar gptel-auto-experiment--consecutive-timeout-threshold 3
  "Stop experiments on a target after this many consecutive timeouts.")
(defvar gptel-auto-experiment--api-error-count nil)
(defvar gptel-auto-experiment--api-error-threshold 5)
(defvar gptel-auto-experiment-delay-between)
(defvar gptel-auto-workflow--status-run-id nil)
(defvar gptel-auto-workflow--defer-subagent-env-persistence nil)
(defvar gptel-auto-workflow--staging-worktree-dir nil)
(defvar gptel-auto-workflow--run-project-root nil)
(defvar gptel-auto-workflow--current-project nil)

(defconst gptel-auto-experiment--placeholder-hypothesis-exact-patterns
  '("[What CODE change and why]"
    "What CODE change and why")
  "Exact hypothesis strings that indicate unresolved placeholder prompts.")

(defun gptel-auto-experiment--placeholder-hypothesis-p (hypothesis)
  "Return non-nil when HYPOTHESIS is still an unresolved prompt template."
  (cond
   ((not (stringp hypothesis)) t)
   (t
    (let ((trimmed (string-trim hypothesis)))
      (or (string-empty-p trimmed)
          (string-match-p "\\`\\[What\\b.*\\]\\'" trimmed)
          (member trimmed gptel-auto-experiment--placeholder-hypothesis-exact-patterns))))))

(defun gptel-auto-experiment--extract-last-explicit-hypothesis (output pattern)
  "Return the last non-placeholder hypothesis in OUTPUT matching PATTERN."
  (when (and (stringp output)
             (stringp pattern)
             (not (string-empty-p pattern)))
    (let ((start 0)
          candidate)
      (while (and (< start (length output))
                  (string-match pattern output start))
        (let ((match (string-trim (match-string 1 output))))
          (unless (gptel-auto-experiment--placeholder-hypothesis-p match)
            (setq candidate match)))
        ;; Advance from the current match start so nested/repeated markers on the
        ;; same logical line still get a chance to replace malformed earlier text.
        (setq start (1+ (match-beginning 0))))
      candidate)))

(defun gptel-auto-experiment--extract-hypothesis (output)
  "Extract HYPOTHESIS from agent OUTPUT.
Tries multiple patterns in order:
1. Check for error message (returns \='Agent error\=')
2. Explicit HYPOTHESIS: prefix
3. **HYPOTHESIS** markdown
4. Sentence with \='will improve\=' (predictive statement)
5. Action verb at start of sentence
6. Summary after ✓ checkmark (fallback)"
  (cond
   ;; Guard against non-string input
   ((not (stringp output))
    "No hypothesis stated")
   ;; Check for error message first
   ((gptel-auto-experiment--agent-error-p output)
    "Agent error")
   ((gptel-auto-experiment--extract-last-explicit-hypothesis
     output
     "HYPOTHESIS:\\s-*\\([^\n]+\\)"))
   ((gptel-auto-experiment--extract-last-explicit-hypothesis
     output
     "\\*\\*HYPOTHESIS\\*\\*:?\\s-*\\([^\n]+\\)"))
   ((string-match "[^.]*\\s-+will improve\\s-+[^.]*\\.?" output)
    (let ((match (match-string 0 output)))
      (string-trim match)))
   ((string-match "\\(?:Adding\\|Changing\\|Improving\\|Enhancing\\|Removing\\|Refactoring\\)\\s-+[^.\n]+\\." output)
    (let ((match (match-string 0 output)))
      (string-trim match)))
   ((string-match "✓\\s-+[^:]+:\\s-+\\([^\n|]+\\)" output)
    (let ((match (match-string 1 output)))
      (string-trim match)))
   (t "No hypothesis stated")))

(defun gptel-auto-experiment--agent-error-p (output)
  "Check if OUTPUT is an error message from agent tool."
  (and (stringp output)
       (or (string-match-p "^Error:" output)
           (gptel-auto-experiment--aborted-agent-output-p output))))

(defun gptel-auto-experiment--target-keep-rate (target previous-results)
  "Return keep-rate (0.0-1.0) for TARGET from PREVIOUS-RESULTS, or nil."
  (when (and target previous-results (listp previous-results) (> (length previous-results) 0))
    (let ((kept 0) (total 0))
      (dolist (r previous-results)
        (when (equal (plist-get r :target) target)
          (when (plist-get r :kept) (cl-incf kept))
          (cl-incf total)))
      (when (> total 0)
        (/ (float kept) total)))))

(defun gptel-auto-experiment--target-keep-rate-from-tsv (target)
  "Return keep-rate (0.0-1.0) for TARGET from TSV results file, or nil."
  (when (fboundp 'gptel-auto-workflow--results-file-path)
    (let ((results-file (gptel-auto-workflow--results-file-path)))
      (when (and results-file (file-exists-p results-file))
        (let ((kept 0) (total 0))
          (with-temp-buffer
            (insert-file-contents results-file)
            (goto-char (point-min))
            (forward-line 1) ; skip header
            (while (not (eobp))
              (let* ((line (buffer-substring (line-beginning-position) (line-end-position)))
                     (fields (split-string line "\t"))
                     (r-target (nth 1 fields))
                     (r-decision (nth 7 fields)))
                (when (and r-target (string-match-p (regexp-quote (file-name-nondirectory target)) r-target))
                  (cl-incf total)
                  (when (equal r-decision "kept")
                    (cl-incf kept))))
              (forward-line 1)))
          (when (> total 0)
            (/ (float kept) total)))))))

(defun gptel-auto-experiment--count-consecutive-strategy (target strategy previous-results)
  "Count consecutive experiments on TARGET using STRATEGY, 0-indexed.
Returns number of consecutive experiments with this strategy."
  (let ((count 0))
    (dolist (r (reverse previous-results))
      (when (and (equal (plist-get r :target) target)
                 (equal (plist-get r :strategy) strategy))
        (cl-incf count))
      (when (and (equal (plist-get r :target) target)
                 (not (equal (plist-get r :strategy) strategy)))
        ;; Found a different strategy — stop counting
        (cl-return)))
    count))

(defun gptel-auto-experiment--summarize (hypothesis)
  "Create short summary of HYPOTHESIS."
  (when (stringp hypothesis)
    (let ((words (split-string hypothesis)))
      (string-join (cl-subseq words 0 (min 6 (length words))) " "))))

(defun gptel-auto-experiment--hypothesis-already-tested-p (hypothesis previous-results)
  "Return non-nil when HYPOTHESIS was already tested on this target.
Compares against `:hypothesis' fields in PREVIOUS-RESULTS.
Uses fuzzy matching: share at least 2 significant tokens after normalization.
P1.2 FIX: Stricter enforcement with 2-token threshold (was 3)."
  (when (and hypothesis previous-results (listp previous-results))
    (let* ((normalized (replace-regexp-in-string
                        "[^a-zA-Z0-9 ]" " " (downcase hypothesis)))
           (tokens (delete-dups (split-string normalized "[ \t]+" t)))
           (sig-tokens (cl-remove-if (lambda (tkn) (< (length tkn) 4)) tokens)))
      (catch 'found
        (dolist (prev previous-results)
          (let ((prev-hyp (plist-get prev :hypothesis)))
            (when (stringp prev-hyp)
              (let* ((prev-norm (replace-regexp-in-string
                                 "[^a-zA-Z0-9 ]" " " (downcase prev-hyp)))
                     (prev-tokens (split-string prev-norm "[ \t]+" t))
                     (shared 0))
                (dolist (tkn sig-tokens)
                  (when (member tkn prev-tokens)
                    (cl-incf shared)))
                (when (>= shared 2)
                  (throw 'found prev-hyp))))))))))

(defun gptel-auto-experiment--hypothesis-diversity (hypothesis previous-results)
  "Compute diversity score (0.0-1.0) for HYPOTHESIS relative to PREVIOUS-RESULTS.
Returns minimum similarity (maximum diversity) across all previous hypotheses.
0.0 = identical to some previous hypothesis, 1.0 = completely novel.
Uses Jaccard similarity on significant tokens (length >= 4).
Inspired by PlanSearch (arXiv:2409.03733): plan diversity predicts
performance."
  (if (or (not hypothesis) (not previous-results) (not (listp previous-results)))
      1.0  ; No previous results = maximally diverse
    (let* ((normalized (replace-regexp-in-string
                        "[^a-zA-Z0-9 ]" " " (downcase hypothesis)))
           (tokens (delete-dups (split-string normalized "[ \t]+" t)))
           (sig-tokens (cl-remove-if (lambda (tkn) (< (length tkn) 4)) tokens))
           (min-similarity 1.0))
      (if (null sig-tokens)
          0.0  ; No significant tokens = no diversity signal
        (dolist (prev previous-results)
          (let ((prev-hyp (plist-get prev :hypothesis)))
            (when (stringp prev-hyp)
              (let* ((prev-norm (replace-regexp-in-string
                                 "[^a-zA-Z0-9 ]" " " (downcase prev-hyp)))
                     (prev-tokens (split-string prev-norm "[ \t]+" t))
                     (prev-sig (cl-remove-if (lambda (tkn) (< (length tkn) 4)) prev-tokens))
                     (shared 0))
                (dolist (tkn sig-tokens)
                  (when (member tkn prev-sig)
                    (cl-incf shared)))
                ;; Jaccard similarity: |intersection| / |union|
                (let* ((union-size (length (delete-dups (append sig-tokens prev-sig))))
                       (similarity (if (> union-size 0) (/ (float shared) union-size) 0.0)))
                  (setq min-similarity (min min-similarity similarity)))))))
        ;; Return diversity (1 - similarity)
        (- 1.0 min-similarity)))))

;;; Plan-Level Search (PlanSearch arXiv:2409.03733)

(defun gptel-auto-experiment--generate-candidate-hypotheses (target previous-results &optional n-candidates)
  "Generate N-CANDIDATES diverse hypothesis candidates for TARGET.
Returns list of plists with :hypothesis :source :diversity.
Sources: skill suggestions, mutation templates, previous successful
hypotheses.
N-CANDIDATES defaults to 5."
  (let* ((n (or n-candidates 5))
         (candidates nil)
         (skill-hyp (when (fboundp 'gptel-auto-workflow-skill-suggest-hypothesis)
                      (ignore-errors
                        (gptel-auto-workflow-skill-suggest-hypothesis
                         (when (fboundp 'gptel-auto-workflow-orient)
                           (gptel-auto-workflow-orient))))))
         (templates (when (fboundp 'gptel-auto-workflow--extract-mutation-templates)
                      (ignore-errors
                        (gptel-auto-workflow--extract-mutation-templates
                         (when (fboundp 'gptel-auto-workflow-orient)
                           (gptel-auto-workflow-orient))))))
         ;; Get previous successful hypotheses for this target
         (prev-success (cl-remove-if-not
                        (lambda (r)
                          (and (equal (plist-get r :target) target)
                               (plist-get r :kept)))
                        previous-results))
         (prev-hypotheses (mapcar (lambda (r) (plist-get r :hypothesis))
                                  (seq-take prev-success 3))))
    ;; Collect candidates from different sources
    (when (and skill-hyp (stringp skill-hyp) (> (length skill-hyp) 10))
      (push (list :hypothesis skill-hyp :source "skill") candidates))
    ;; Add mutation templates
    (dolist (tmpl (seq-take (or templates nil) 2))
      (when (and (stringp tmpl) (> (length tmpl) 10))
        (push (list :hypothesis tmpl :source "template") candidates)))
    ;; Add variations of previous successful hypotheses
    (dolist (prev-hyp prev-hypotheses)
      (when (and (stringp prev-hyp) (> (length prev-hyp) 10))
        ;; Create variation by prepending "Improve: "
        (let ((variation (format "Improve: %s" prev-hyp)))
          (push (list :hypothesis variation :source "variation") candidates))))
    ;; If we have fewer than N candidates, add generic ones
    (when (< (length candidates) n)
      (let ((generic-hyps
             '("Add nil guards before dangerous operations"
               "Simplify complex conditional logic"
               "Extract repeated code into helper functions"
               "Improve error messages for debugging"
               "Add documentation for public functions")))
        (dolist (hyp generic-hyps)
          (when (< (length candidates) n)
            (unless (cl-some (lambda (c) (string= (plist-get c :hypothesis) hyp))
                             candidates)
              (push (list :hypothesis hyp :source "generic") candidates))))))
    ;; Compute diversity for each candidate
    (setq candidates
          (mapcar (lambda (c)
                    (plist-put c :diversity
                               (gptel-auto-experiment--hypothesis-diversity
                                (plist-get c :hypothesis) previous-results)))
                  candidates))
    ;; Return top N by diversity
    (seq-take (sort candidates (lambda (a b)
                                 (> (plist-get a :diversity)
                                    (plist-get b :diversity))))
              n)))

(defun gptel-auto-experiment--select-diverse-hypothesis (target previous-results &optional min-diversity)
  "Select the most diverse hypothesis for TARGET.
Returns hypothesis string or nil if no good candidates.
MIN-DIVERSITY defaults to 0.3 (30% different from previous).
Implements plan-level search from PlanSearch (arXiv:2409.03733)."
  (let* ((min-div (or min-diversity 0.3))
         (candidates (gptel-auto-experiment--generate-candidate-hypotheses
                      target previous-results 5))
         ;; Filter out duplicates (already tested)
         (non-duplicates (cl-remove-if
                          (lambda (c)
                            (gptel-auto-experiment--hypothesis-already-tested-p
                             (plist-get c :hypothesis) previous-results))
                          candidates))
         ;; Filter by minimum diversity
         (diverse-enough (cl-remove-if
                          (lambda (c) (< (plist-get c :diversity) min-div))
                          non-duplicates)))
    (when diverse-enough
      (let* ((best (car diverse-enough))
             (hyp (plist-get best :hypothesis))
             (div (plist-get best :diversity))
             (src (plist-get best :source)))
        (message "[plan-search] Selected: %s (diversity=%.2f, source=%s)"
                 (truncate-string-to-width hyp 50 nil nil "...")
                 div src)
        hyp))))

;;; Experiment Relevance Scoring (AttnRes arXiv:2603.15031)

(defun gptel-auto-experiment--compute-relevance (target previous-experiment)
  "Compute relevance score (0.0-1.0) for PREVIOUS-EXPERIMENT to TARGET.
Uses Jaccard similarity on target path and hypothesis tokens.
Inspired by AttnRes: selectively weight past experiments by content relevance,
not just recency.  Replaces fixed-weight accumulation with learned attention.
PREVIOUS-EXPERIMENT is a plist with :target and :hypothesis."
  (let ((prev-target (plist-get previous-experiment :target))
        (prev-hypothesis (plist-get previous-experiment :hypothesis)))
    (if (or (not target) (not prev-target) (not (stringp prev-target))
            (not (stringp prev-hypothesis)))
        0.0
      (let* ((target-tokens (gptel-auto-experiment--tokenize target))
             (prev-target-tokens (gptel-auto-experiment--tokenize prev-target))
             (hyp-tokens (gptel-auto-experiment--tokenize prev-hypothesis))
             ;; Target similarity: how similar are the file paths?
             (target-similarity (gptel-auto-experiment--jaccard
                                 target-tokens prev-target-tokens))
             ;; Hypothesis relevance: how relevant is the hypothesis to current target?
             (hyp-relevance (gptel-auto-experiment--jaccard
                             target-tokens hyp-tokens))
             ;; Combined: 60% hypothesis relevance, 40% target similarity
             (combined (+ (* 0.6 hyp-relevance) (* 0.4 target-similarity))))
        combined))))

(defun gptel-auto-experiment--jaccard (tokens1 tokens2)
  "Compute Jaccard similarity between two token lists.
Returns 0.0 (no overlap) to 1.0 (identical)."
  (let ((t1 (delete-dups tokens1))
        (t2 (delete-dups tokens2)))
    (if (or (null t1) (null t2))
        0.0
      (let ((shared (cl-count-if (lambda (tkn) (member tkn t2)) t1))
            (union (length (delete-dups (append t1 t2)))))
        (if (> union 0) (/ (float shared) union) 0.0)))))

(defun gptel-auto-experiment--tokenize (text)
  "Tokenize TEXT into significant tokens (length >= 4, lowercase, alphanumeric)."
  (let ((normalized (replace-regexp-in-string "[^a-zA-Z0-9./_-]" " " (downcase (or text "")))))
    (cl-remove-if (lambda (tkn) (< (length tkn) 4))
                  (split-string normalized "[ \t/_-]+" t))))

(defun gptel-auto-experiment--rank-relevant (target previous-results &optional n)
  "Return top N most relevant experiments for TARGET from PREVIOUS-RESULTS.
Returns list of (RELEVANCE . EXPERIMENT-PLIST) sorted by relevance descending.
N defaults to 10.  AttnRes-inspired: selective aggregation over history."
  (let* ((n (or n 10))
         (scored (mapcar (lambda (exp)
                           (cons (gptel-auto-experiment--compute-relevance target exp) exp))
                         previous-results))
         (relevant (cl-remove-if (lambda (pair) (< (car pair) 0.1)) scored)))
    (seq-take (sort relevant (lambda (a b) (> (car a) (car b)))) n)))

(defvar gptel-auto-experiment-max-validation-retries 1
  "Maximum retries when validation fails due to teachable patterns.
Executor will be instructed to load relevant skill and regenerate.")

(defun gptel-auto-experiment--elisp-syntax-error-p (target error)
  "Return non-nil when ERROR indicates an Elisp syntax issue in TARGET."
  (and (stringp error)
       (or (string-match-p
            "cl-return-from.*without.*cl-block\\|Dangerous pattern"
            error)
           (string-match-p
            "Unbalanced parentheses\\|End of file during parsing\\|Scan error\\|Invalid read syntax"
            error)
           (and (stringp target)
                (string-suffix-p ".el" target)
                (string-match-p "\\`\\(Syntax error in \\|Elisp parse error in \\)" error)))))

(defun gptel-auto-experiment--teachable-validation-error-p (target validation-error)
  "Return non-nil when VALIDATION-ERROR should trigger an immediate retry.
TARGET is the file currently being optimized.
Retries for: Elisp syntax errors, defensive code removal, and other
fixable validation failures that the executor can correct."
  (and (stringp validation-error)
       (> (length validation-error) 0)
       (or (gptel-auto-experiment--elisp-syntax-error-p target validation-error)
           (string-match-p "Defensive code removal detected\\|removing.*fallbacks\\|without proof"
                           validation-error)
           (string-match-p "Undefined function introduced\\|undefined.*runtime.*call"
                            validation-error)
            (string-match-p "security|injection|eval.*without.*guard"
                            validation-error)
            (string-match-p "no code changes\\|no file modifications\\|experiment produced no file changes\\|Agent made no"
                            validation-error))))

(defun gptel-auto-experiment--make-retry-prompt (target validation-error original-prompt)
  "Create retry prompt after validation failure.
TARGET is the file being edited.
VALIDATION-ERROR is the error message.
Instructs executor to load relevant skill instead of hardcoding patterns."
  ;; ASSUMPTION: target and validation-error must be non-empty strings for meaningful retry
  ;; EDGE CASE: nil or empty inputs produce safe defaults rather than malformed prompts
  (let* ((target (if (and (stringp target) (not (string-empty-p target)))
                     target
                   "unknown-file"))
         (validation-error (if (and (stringp validation-error) (not (string-empty-p validation-error)))
                               validation-error
                             "Unknown validation error"))
         (skill-guidance
         (cond
          ;; Elisp syntax and dangerous patterns - tell executor to load skill
          ((gptel-auto-experiment--elisp-syntax-error-p target validation-error)
           "CALL THIS FIRST: Skill(\"elisp-expert\")
This skill teaches syntax-safe Elisp edits and dangerous patterns including
cl-return-from requirements.")
           ;; Undefined function calls - guide the agent to check Emacs Lisp availability
           ((string-match-p "Undefined function introduced\\|undefined.*runtime.*call"
                            validation-error)
            "The undefined function was rejected because it does not exist in this Emacs
Lisp runtime.
Before writing a function call, verify it exists in Emacs Lisp. When
uncertain, use
well-known Emacs builtins only. Common Lisp functions NOT available in Emacs:
getf (use plist-get), plusp (use (> n 0)), remf (use cl-remf),
psetq (use setq), incf/decf (use setq with +), key (use plist-get),
cons? (use consp), atom? (use atom).
CRITICAL: Do NOT call single-letter or short variable names as functions.
If you see a function like \='tool\=' or \='key\=' in the error, it means you
wrote
(tool ...) or (key ...) — these are NOT valid Emacs Lisp functions.
Replace undefined calls with valid Emacs Lisp equivalents or remove them.
Use function-quote #' for symbols meant as functions, not bare-quote \='.")
             ;; Agent made no file modifications — it only analyzed, didn't edit
            ((string-match-p "no code changes\\|no file modifications\\|experiment produced no file changes\\|Agent made no"
                             validation-error)
             "TOOL-CALL-FAILURE")
            ;; Add more skill mappings here as needed
            (t "")))
        (tool-call-failure (string= skill-guidance "TOOL-CALL-FAILURE"))
        (original-contract
         (if (and (stringp original-prompt)
                  (> (length original-prompt) 0))
             original-prompt
           (concat
            "FINAL RESPONSE must include:\n"
            "- CHANGED: exact file path(s) and function/variable names touched\n"
            "- EVIDENCE: 1-2 concrete code snippets or diff hunks showing the real edit\n"
            "- VERIFY: exact command(s) run and whether they passed or failed\n"
            "- COMMIT: always \"not committed\"\n"
            "End the final response with: Task completed")))
        (retry-error (if tool-call-failure
                         "You output code as text instead of calling Edit/Write tool. No files were modified."
                       validation-error))
        (retry-header
         (if tool-call-failure
             (concat
             "## SELF-HEAL: Tool-Call Required\n"
             "λ self-heal(x).    output(code_as_text) → ¬tool_call ∧ ¬file_change\n"
             "                   | ¬code_in_text | ¬description | ∀change: ∃tool_call\n"
             "                   | text_only(x) ≡ reject(x) | repeat → fail(experiment)\n\n")
           "")))
    (concat
     retry-header
     (format "Your previous edit to %s was REJECTED due to validation error:

ERROR: %s

IMPORTANT:
1. This is a focused repair retry, not a fresh experiment.
2. Fix ONLY the reported validation issue in %s with the smallest possible edit.
3. Keep the earlier improvement if it still makes sense after the repair; do not broaden the change.
4. Prefer focused reads near the reported failure instead of rereading large files.
5. Do not run broad repo tests or compile unrelated files until the validation issue is fixed.
6. For Elisp syntax errors, repair the parse error first and confirm the file reads or byte-compiles before broader verification.
7. Reuse the original experiment contract and final response format below.

Before retrying, load the relevant skill for guidance.

%s

ORIGINAL TASK:
%s"
             target
             retry-error
             target
             (if tool-call-failure "" (or skill-guidance ""))
             original-contract))))

;;; Experiment Loop

(defun gptel-auto-experiment-loop (target callback)
  "Run experiments for TARGET until stop condition. Call CALLBACK with results.
Uses local state captured in closure for parallel execution safety.
Adapts max-experiments based on API error rate."
  (cl-block gptel-auto-experiment-loop
    (let* ((workflow-root (gptel-auto-workflow--resolve-run-root))
         (loop-buffer (current-buffer))
         baseline
         baseline-code-quality)
    (gptel-auto-workflow--call-in-run-context
     workflow-root
     (lambda ()
        (setq baseline (gptel-auto-experiment-benchmark t nil)
              baseline-code-quality (or (gptel-auto-experiment--code-quality-score) 0.5)))
     loop-buffer
     workflow-root)
    ;; Ontology gate: check if target is suitable for experimentation
    (when (and (fboundp 'gptel-auto-workflow--categorize-target)
               (fboundp 'gptel-auto-workflow--check-action-preconditions))
      (let* ((category (gptel-auto-workflow--categorize-target target))
             (precondition-error (gptel-auto-workflow--check-action-preconditions target))
             (saturated (and category
                              (boundp 'gptel-auto-workflow--category-saturation)
                              (assoc category gptel-auto-workflow--category-saturation))))
        (when precondition-error
          (message "[ontology-gate] 🚫 %s: %s — skipping experiment" target precondition-error)
          (funcall callback nil)
          (cl-return-from gptel-auto-experiment-loop))
        (when saturated
          (message "[ontology-gate] ⚠ %s: category %s saturated — reducing experiments" target category)
          (setq gptel-auto-experiment-max-per-target
                (min gptel-auto-experiment-max-per-target 3)))
        ;; Target-level saturation: skip if same error 3+ times
        (when (and (fboundp 'gptel-ai-behaviors--target-saturated-p)
                   (gptel-ai-behaviors--target-saturated-p target))
          (message "[saturation] ⏭ %s: skipping due to repeated failure pattern" target)
          (funcall callback nil)
           (cl-return-from gptel-auto-experiment-loop))))
        ;; Target-experiment saturation: skip if target has enough experiments
        (when (and (fboundp 'gptel-auto-workflow--target-saturated-p)
                   (gptel-auto-workflow--target-saturated-p target))
          (message "[onto-sat] ⏭ %s: skipping — target has enough experiments" target)
          (funcall callback nil)
          (cl-return-from gptel-auto-experiment-loop))
    (let* ((original-max gptel-auto-experiment-max-per-target)
           (max-exp (gptel-auto-experiment--adaptive-max-experiments original-max))
           ;; Adjust max-exp based on frontier size: underexplored targets get more experiments
           (max-exp (if (fboundp 'gptel-auto-experiment--compute-frontier)
                        (let* ((frontier (gptel-auto-experiment--compute-frontier target))
                               (frontier-size (length frontier)))
                          (cond
                           ;; No frontier yet: extra experiments to bootstrap
                           ((= frontier-size 0)
                            (message "[auto-workflow] %s has no frontier yet; allowing +2 experiments" target)
                            (+ max-exp 2))
                           ;; Small frontier: allow more experiments
                           ((< frontier-size 3)
                            (message "[auto-workflow] %s frontier size %d; allowing +1 experiment" target frontier-size)
                            (+ max-exp 1))
                           ;; Large frontier: reduce experiments
                           ((> frontier-size 6)
                            (message "[auto-workflow] %s frontier size %d; reducing by 1" target frontier-size)
                            (max 2 (1- max-exp)))
                           ;; Medium frontier: keep default
                           (t max-exp)))
                      max-exp))
           (threshold gptel-auto-experiment-no-improvement-threshold)
           (run-id gptel-auto-workflow--run-id)
           (results nil)
           (best-score (let ((score (gptel-auto-workflow--plist-get baseline :eight-keys nil)))
                         (if (numberp score) score 0.0)))
            (no-improvement-count 0)
            (consecutive-timeouts 0))
      (message "[auto-experiment] Baseline for %s: %.2f (max-exp: %d)"
               target best-score max-exp)
      (cl-labels ((run-next (exp-id)
                    (gptel-auto-workflow--update-progress)
                     (when gptel-auto-experiment--quota-exhausted
                       (message "[auto-workflow] ⏹ All backends exhausted — stopping early for %s"
                                target)
                       (setq max-exp (1- exp-id))
                       (cl-return-from gptel-auto-experiment-loop))
                    (when (and (>= gptel-auto-experiment--api-error-count
                                   gptel-auto-experiment--api-error-threshold)
                               (< exp-id max-exp))
                      (message "[auto-workflow] API pressure reached threshold (%d), stopping early for %s"
                               gptel-auto-experiment--api-error-count target)
                      (setq max-exp (1- exp-id)))
                    ;; Check frontier saturation: stop if target sufficiently explored
                    (when (and (fboundp 'gptel-auto-experiment--frontier-saturated-p)
                               (gptel-auto-experiment--frontier-saturated-p target)
                               (< exp-id max-exp))
                      (message "[auto-workflow] Target %s frontier saturated; stopping early"
                               target)
                      (setq max-exp (1- exp-id)))
                    (if (or (> exp-id max-exp)
                             (>= no-improvement-count threshold)
                             (>= consecutive-timeouts gptel-auto-experiment--consecutive-timeout-threshold))
                        (progn
                           (message "[auto-experiment] Done with %s: %d experiments, best score %.2f (timeouts=%d)"
                                    target (length results)
                                    best-score consecutive-timeouts)
                           (funcall callback (nreverse results)))
                      (gptel-auto-experiment--run-with-retry
                       target exp-id max-exp
                       best-score
                       baseline-code-quality
                       results
                         (lambda (result)
                           (push result results)
                          (gptel-auto-workflow--update-progress)
                          (let* ((raw-score-after (gptel-auto-workflow--plist-get result :score-after 0))
                                 (score-after
                                  (cond
                                   ((numberp raw-score-after) raw-score-after)
                                   ((and (stringp raw-score-after)
                                         (string-match-p
                                          "\\`[[:space:]]*[+-]?[0-9]+\\(?:\\.[0-9]+\\)?[[:space:]]*\\'"
                                          raw-score-after))
                                    (string-to-number raw-score-after))
                                   (t 0)))
                                 (kept (gptel-auto-workflow--plist-get result :kept nil))
                                 (raw-quality-after
                                  (gptel-auto-workflow--plist-get result :code-quality baseline-code-quality))
                                 (quality-after
                                  (if (numberp raw-quality-after)
                                      raw-quality-after
                                    baseline-code-quality))
                                 (hard-timeout
                                  (gptel-auto-experiment--result-hard-timeout-p result))
                                 (grader-only-failure
                                  (plist-get result :grader-only-failure))
                                 (next-exp-id (1+ exp-id)))
                            ;; P1 FIX: Don't stop loop on grader-only-failure.
                            ;; Grader-only failure means the grader couldn't evaluate,
                            ;; not that the code is bad. Continue with different strategies.
                            ;; Only stop after 3 consecutive grader failures.
                            (when grader-only-failure
                              (setq consecutive-timeouts (1+ consecutive-timeouts))
                              (message "[auto-experiment] Grader-only failure for %s in experiment %d (%d consecutive); %s"
                                       target exp-id consecutive-timeouts
                                       (if (>= consecutive-timeouts gptel-auto-experiment--consecutive-timeout-threshold)
                                           "threshold reached — stopping target"
                                         "continuing with next experiment")))
                            (when kept
                              (setq best-score score-after
                                    baseline-code-quality quality-after
                                    no-improvement-count 0
                                    consecutive-timeouts 0))
                             (when (and (not kept)
                                        score-after
                                        (<= score-after (if (numberp best-score) best-score 0)))
                                (setq no-improvement-count (1+ no-improvement-count)))
                             (unless hard-timeout
                               (setq consecutive-timeouts 0))
                             (when hard-timeout
                               (setq consecutive-timeouts (1+ consecutive-timeouts))
                              (message "[auto-experiment] Hard timeout for %s in experiment %d (%d consecutive); %s"
                                       target exp-id consecutive-timeouts
                                       (if (>= consecutive-timeouts gptel-auto-experiment--consecutive-timeout-threshold)
                                           "threshold reached — stopping target"
                                         "continuing if budget remains")))
                            ;; Trigger strategy evolution periodically
                            (when (and (fboundp 'gptel-auto-workflow--maybe-evolve-strategy)
                                       (zerop (% next-exp-id 5)))
                              (message "[strategy] Triggering strategy evolution after %d experiments" next-exp-id)
                              (condition-case err
                                  (gptel-auto-workflow--maybe-evolve-strategy target)
                                (error
                                 (message "[strategy] Evolution error during experiment callback: %s" err)
                                 (message "[strategy] Evolution error debug: next-exp-id=%S type=%S" next-exp-id (type-of next-exp-id)))))
                            (let ((continue
                                   (lambda ()
                                     (if (gptel-auto-workflow--run-callback-live-p run-id)
                                         (gptel-auto-workflow--call-in-run-context
                                          workflow-root
                                          (lambda () (run-next next-exp-id))
                                          loop-buffer
                                          workflow-root)
                                       (progn
                                         (message "[auto-experiment] Run %s no longer active; returning accumulated results for %s"
                                                  run-id target)
                                         (funcall callback (nreverse results))))))
                                  (headless-run
                                   (or (bound-and-true-p gptel-auto-workflow--headless)
                                       (bound-and-true-p gptel-auto-workflow-persistent-headless)
                                       (bound-and-true-p gptel-auto-workflow--cron-job-running))))
                              (if (and (> gptel-auto-experiment-delay-between 0)
                                       (not headless-run))
                                  (run-with-timer gptel-auto-experiment-delay-between nil continue)
                                ;; Headless cron runs should advance immediately. The
                                ;; async subagent callbacks already break the stack, and
                                ;; timer-based continuation has proven unreliable there.
                                (funcall continue)))))))))
        (gptel-auto-workflow--call-in-run-context
         workflow-root
         (lambda () (run-next 1))
         loop-buffer
         workflow-root))))))

;;; Main Entry Point

(defvar gptel-auto-workflow--running nil
  "Flag to track if auto-workflow is currently running.")

(defvar gptel-auto-workflow--headless nil
  "Flag to suppress interactive prompts during headless operation.")

(defvar gptel-auto-workflow--auto-revert-was-enabled nil
  "Remember if global-auto-revert-mode was enabled before headless operation.")

(defvar gptel-auto-workflow--uniquify-style nil
  "Remember uniquify-buffer-name-style before headless operation.")

(defvar gptel-auto-workflow--compile-angel-on-load-was-enabled nil
  "Remember whether `compile-angel-on-load-mode' was enabled
before headless operation.")

(defvar gptel-auto-workflow--undo-fu-session-was-enabled nil
  "Remember whether `undo-fu-session-global-mode' was enabled
before headless operation.")

(defvar gptel-auto-workflow--recentf-was-enabled nil
  "Remember whether `recentf-mode' was enabled before headless operation.")

(defvar gptel-auto-workflow--apheleia-was-enabled nil
  "Remember whether `apheleia-global-mode' was enabled before headless operation.")

(defvar gptel-auto-workflow--create-lockfiles-value t
  "Remember `create-lockfiles' before headless operation.")

(defvar gptel-auto-workflow--stats nil
  "Current run statistics: (:kept :total :phase).")

(defvar gptel-auto-workflow--current-target nil
  "Current target file being processed by auto-workflow.")

(defvar gptel-auto-workflow--cron-job-running nil
  "Non-nil while a queued cron job is executing.")

(defvar gptel-auto-workflow--cron-job-timer nil
  "Timer object for a queued cron job that has not started yet.")

(defvar gptel-auto-workflow--watchdog-timer nil
  "Watchdog timer to prevent workflow from getting stuck.")

(defvar gptel-auto-workflow--status-refresh-timer nil
  "Timer that keeps the persisted workflow status snapshot fresh.")

(defvar gptel-auto-workflow--force-idle-status-overwrite nil
  "When non-nil, allow an idle status snapshot to replace an active snapshot.")

(defvar gptel-auto-workflow--last-progress-time nil
  "Timestamp of last progress update.")

(defvar gptel-auto-workflow--messages-start-pos nil
  "Buffer position where the current workflow run's messages begin.")

(defvar gptel-auto-workflow--max-stuck-minutes 20
  "Maximum minutes without progress before watchdog force-stops the workflow.
Increased from 10m to 20m: experiments with slow backends (2-5min per call)
can exceed the old limit across multiple phases (executor, validation,
grading).
Each phase is a separate subagent call with no progress update between them.")

(defvar gptel-auto-workflow--total-budget-minutes 120
  "Maximum TOTAL minutes for a workflow before watchdog force-stops.
Set to 120min: 5 targets × 2 experiments × 10min avg = 100min budget.")

(defvar gptel-auto-workflow--watchdog-start-time nil
  "Timestamp when the current workflow run started.
Set by `gptel-auto-workflow--restart-watchdog-timer'.")

(defvar gptel-auto-workflow--rss-force-stop-kb 4194304
  "RSS threshold (KB) at which the watchdog force-stops the workflow.
Default: 4GB. Pi5 has 8GB total; 4GB leaves headroom for OS + other
processes while still catching genuine memory leaks. The old 1.5GB
threshold (1572864) killed legitimate subagent work — Emacs + gptel
buffers + subagent state easily reach 2-3GB during normal operation.
Set to nil to disable RSS-based force-stop entirely.")

(defvar gptel-auto-workflow--rss-gc-kb 3145728
  "RSS threshold (KB) at which the watchdog triggers aggressive GC.
Default: 3GB. This is below force-stop so we get a chance to reclaim
memory before killing the workflow.")

(defvar gptel-auto-workflow--rss-allow-active-tasks t
  "When non-nil, skip RSS-based force-stop if there are active subagent tasks.
Active subagent tasks mean work is in progress, not a memory leak. The
old code killed workflows at 2GB while a subagent was making progress.")

(defvar gptel-auto-workflow--heartbeat-timer nil
  "Repeating timer that writes a heartbeat timestamp file for external watchdog.")

(defvar gptel-auto-workflow--heartbeat-file "var/tmp/daemon-heartbeat"
  "Relative path to the daemon heartbeat file.
Resolved from the project root via `gptel-auto-workflow--default-dir'.")

(defconst gptel-auto-workflow--heartbeat-interval 30
  "Seconds between heartbeat file writes.")

(defun gptel-auto-workflow--write-heartbeat (&optional override-path)
  "Write current epoch timestamp to the heartbeat file.
OVERRIDE-PATH, if non-nil, is the absolute path to write to (for testing).
Never signals — errors are silently swallowed so the timer stays alive."
  (condition-case nil
      (let ((path (or override-path
                      (expand-file-name
                       gptel-auto-workflow--heartbeat-file
                       (gptel-auto-workflow--default-dir)))))
        (make-directory (file-name-directory path) t)
        (write-region (format-time-string "%s") nil path nil 'silent))
    (error nil)))

(defun gptel-auto-workflow--start-heartbeat-timer ()
  "Start the repeating heartbeat timer.  Cancels any existing one first."
  (when (timerp gptel-auto-workflow--heartbeat-timer)
    (cancel-timer gptel-auto-workflow--heartbeat-timer))
  ;; Fire first beat immediately, then repeat every HEARTBEAT-INTERVAL seconds.
  (gptel-auto-workflow--write-heartbeat)
  (setq gptel-auto-workflow--heartbeat-timer
        (run-with-timer gptel-auto-workflow--heartbeat-interval
                        gptel-auto-workflow--heartbeat-interval
                        #'gptel-auto-workflow--write-heartbeat)))

(defcustom gptel-auto-workflow-status-file "var/tmp/cron/auto-workflow-status.sexp"
  "Path to the persisted auto-workflow status snapshot.
Relative paths are resolved from the project root."
  :type 'file
  :group 'gptel)

(defcustom gptel-auto-workflow-messages-file "var/tmp/cron/auto-workflow-messages-tail.txt"
  "Path to the persisted auto-workflow messages snapshot.
Relative paths are resolved from the project root."
  :type 'file
  :group 'gptel)

(defcustom gptel-auto-workflow-messages-chars 16000
  "Maximum number of trailing *Messages* characters to persist for cron tools."
  :type 'integer
  :group 'gptel)

(defcustom gptel-auto-workflow-status-refresh-interval 10
  "Seconds between persisted status refreshes during active workflow runs."
  :type 'integer
  :group 'gptel)

(defun gptel-auto-workflow--status-file ()
  "Return absolute path to the persisted workflow status snapshot."
  (let* ((configured-file gptel-auto-workflow-status-file)
         (default-file "var/tmp/cron/auto-workflow-status.sexp")
         (env-file (getenv "AUTO_WORKFLOW_STATUS_FILE")))
    (cond
     ((not (equal configured-file default-file))
      (if (file-name-absolute-p configured-file)
          configured-file
        (expand-file-name configured-file
                          (gptel-auto-workflow--default-dir))))
     ((and (stringp env-file)
           (not (string-empty-p env-file)))
      env-file)
     ((file-name-absolute-p configured-file)
      configured-file)
     (t
      (expand-file-name configured-file
                        (gptel-auto-workflow--default-dir))))))

(defun gptel-auto-workflow--messages-file ()
  "Return absolute path to the persisted workflow messages snapshot."
  (let* ((configured-file gptel-auto-workflow-messages-file)
         (default-file "var/tmp/cron/auto-workflow-messages-tail.txt")
         (env-file (getenv "AUTO_WORKFLOW_MESSAGES_FILE")))
    (cond
     ((not (equal configured-file default-file))
      (if (file-name-absolute-p configured-file)
          configured-file
        (expand-file-name configured-file
                          (gptel-auto-workflow--default-dir))))
     ((and (stringp env-file)
           (not (string-empty-p env-file)))
      env-file)
     ((file-name-absolute-p configured-file)
      configured-file)
     (t
      (expand-file-name configured-file
                        (gptel-auto-workflow--default-dir))))))

(defun gptel-auto-workflow--messages-chars ()
  "Return the configured trailing *Messages* snapshot size."
  (let* ((env-value (getenv "AUTO_WORKFLOW_MESSAGES_CHARS"))
         (parsed-env (and (stringp env-value)
                          (not (string-empty-p env-value))
                          (string-to-number env-value))))
    (if (and parsed-env (> parsed-env 0))
        parsed-env
      gptel-auto-workflow-messages-chars)))

(defun gptel-auto-workflow--mark-messages-start ()
  "Mark the current end of *Messages* as the start of a new workflow run."
  (with-current-buffer (get-buffer-create "*Messages*")
    (setq gptel-auto-workflow--messages-start-pos (point-max))))

(defun gptel-auto-workflow--persist-messages-tail ()
  "Persist the trailing *Messages* tail for non-blocking cron inspection."
  (let* ((file (gptel-auto-workflow--messages-file))
         (dir (file-name-directory file))
         (max-chars (gptel-auto-workflow--messages-chars)))
    (when dir
      (condition-case err
          (make-directory dir t)
        (error
         (message "[auto-workflow] Failed to create messages directory %s: %s" dir err)
         (setq dir nil))))
    (when (and dir (get-buffer "*Messages*"))
      (with-current-buffer "*Messages*"
        (let* ((start-pos (cond
                           ((integer-or-marker-p gptel-auto-workflow--messages-start-pos)
                            (max (point-min)
                                 (min (point-max)
                                      gptel-auto-workflow--messages-start-pos)))
                           (t (point-min))))
               (tail-start (max (point-min) (- (point-max) max-chars))))
          (write-region (max start-pos tail-start)
                        (point-max)
                        file nil 'silent))))))

(defun gptel-auto-workflow--status-plist ()
  "Return current workflow status as a plist."
  (let* ((running (or gptel-auto-workflow--running
                      (bound-and-true-p gptel-auto-workflow--cron-job-running)))
         (stats (and (proper-list-p gptel-auto-workflow--stats)
                     gptel-auto-workflow--stats))
         (phase (gptel-auto-workflow--plist-get stats :phase "idle"))
         (active-run-id (and (stringp gptel-auto-workflow--run-id)
                             (not (string-empty-p gptel-auto-workflow--run-id))
                             gptel-auto-workflow--run-id))
         (status-run-id (and (stringp gptel-auto-workflow--status-run-id)
                             (not (string-empty-p gptel-auto-workflow--status-run-id))
                             gptel-auto-workflow--status-run-id))
         (run-id (or active-run-id
                     (and running status-run-id)
                     (and (member phase '("complete" "quota-exhausted" "error"))
                          status-run-id))))
    (list :running running
          :kept (gptel-auto-workflow--plist-get stats :kept 0)
          :total (gptel-auto-workflow--plist-get stats :total 0)
          :phase phase
          :run-id run-id
          :results (and run-id
                        (gptel-auto-workflow--results-relative-path run-id)))))

(defun gptel-auto-workflow--status-active-p (status)
  "Return non-nil when STATUS reflects an active workflow snapshot."
  (and (proper-list-p status)
       (or (plist-get status :running)
           (let ((phase (plist-get status :phase)))
             (and (stringp phase)
                  (not (member phase '("idle" "complete" "skipped"))))))))

(defun gptel-auto-workflow--status-placeholder-p (status)
  "Return non-nil when STATUS is only an idle placeholder snapshot."
  (and (proper-list-p status)
       (not (plist-get status :running))
       (equal (plist-get status :phase) "idle")
       (zerop (or (plist-get status :kept) 0))
       (zerop (or (plist-get status :total) 0))))

(defun gptel-auto-workflow--status-owned-by-current-run-p (status)
  "Return non-nil when STATUS belongs to the current workflow run."
  (and (proper-list-p status)
       (stringp gptel-auto-workflow--run-id)
       (not (string-empty-p gptel-auto-workflow--run-id))
       (equal (plist-get status :run-id)
              gptel-auto-workflow--run-id)))

(defun gptel-auto-workflow--persist-status ()
  "Persist current workflow status for non-blocking cron health checks."
  (let* ((file (gptel-auto-workflow--status-file))
         (dir (when file (file-name-directory file)))
         (status (gptel-auto-workflow--status-plist))
         (existing-status (gptel-auto-workflow-read-persisted-status)))
    ;; Guard against nil file path (can happen if status file not configured)
    (unless file
      (message "[auto-workflow] Status file not configured, skipping persist")
      (cl-return-from gptel-auto-workflow--persist-status))
    ;; Preserve the last active snapshot when an unrelated process only has an
    ;; idle placeholder view of workflow state. The shell wrapper already owns
    ;; stale-active detection; this guard prevents bogus idle rewrites with
    ;; synthetic run ids while a real run is still active elsewhere.
    ;; Use condition-case to handle stale native-comp function signature errors.
    (condition-case err
        (when (and (not gptel-auto-workflow--force-idle-status-overwrite)
                   (gptel-auto-workflow--status-placeholder-p status)
                   (gptel-auto-workflow--status-active-p existing-status)
                   (not (gptel-auto-workflow--status-owned-by-current-run-p
                         existing-status)))
          (setq status existing-status))
      (error
       (message "[auto-workflow] Status guard error (native-comp stale?): %s" err)))
    (when dir
      (make-directory dir t))
    (with-temp-file file
      (let ((print-length nil)
            (print-level nil))
        (prin1 status (current-buffer))
        (insert "\n")))
    (gptel-auto-workflow--persist-messages-tail)))

(defun gptel-auto-workflow-read-persisted-status ()
  "Read the persisted workflow status snapshot, or nil if unavailable."
  (let ((file (gptel-auto-workflow--status-file)))
    (when (file-readable-p file)
      (condition-case err
          (with-temp-buffer
            (insert-file-contents file)
            (goto-char (point-min))
            (read (current-buffer)))
        (error
         (message "[auto-workflow] Failed to read status snapshot: %s" err)
         (cl-return))))))

(defun gptel-auto-workflow--suppress-ask-user-about-supersession-threat (orig-fn &rest args)
  "Suppress supersession threat prompts in headless mode."
  (if gptel-auto-workflow--headless
      'revert
    (apply orig-fn args)))

(defun gptel-auto-workflow--suppress-yes-or-no-p (orig-fn prompt)
  "Suppress yes-or-no prompts in headless mode, auto-answer yes."
  (if gptel-auto-workflow--headless
      t
    (funcall orig-fn prompt)))

(defun gptel-auto-workflow--suppress-y-or-n-p (orig-fn prompt)
  "Suppress y-or-n prompts in headless mode, auto-answer yes."
  (if gptel-auto-workflow--headless
      t
    (funcall orig-fn prompt)))

(defun gptel-auto-workflow--suppress-ask-user-about-lock (orig-fn file opponent)
  "Suppress lock prompts in headless mode by grabbing the lock.
FILE and OPPONENT match `ask-user-about-lock'."
  (if gptel-auto-workflow--headless
      t
    (funcall orig-fn file opponent)))

(defun gptel-auto-workflow--suppress-kill-buffer-query ()
  "Suppress kill-buffer queries in headless mode.
Returns t to allow killing modified buffers without asking.
When not in headless mode, returns t to not interfere with normal behavior."
  (or gptel-auto-workflow--headless t))

(defun gptel-auto-workflow--suppress-kill-buffer-modified (orig-fn &optional buffer-or-name)
  "Suppress \='Buffer modified; kill anyway?\=' prompt in headless mode.
ORIG-FN is the original `kill-buffer'. BUFFER-OR-NAME is the buffer to kill.
In headless mode, marks buffer as unmodified before killing to bypass prompt."
  (if gptel-auto-workflow--headless
      (let ((buf (if buffer-or-name
                     (get-buffer buffer-or-name)
                   (current-buffer))))
        (when (and buf (buffer-live-p buf))
          (with-current-buffer buf
            (set-buffer-modified-p nil)))
        (funcall orig-fn buffer-or-name))
    (funcall orig-fn buffer-or-name)))

(defun gptel-auto-workflow--suppress-apheleia-p ()
  "Skip Apheleia formatting while headless workflow mode is active."
  gptel-auto-workflow--headless)

(defun gptel-auto-workflow--enable-headless-suppression ()
  "Enable suppression of interactive prompts for headless operation.
Also disables auto-revert, compile-angel, Apheleia, undo-fu-session,
recentf, and uniquify to prevent buffer churn in ephemeral workflow
worktrees."
  (setq gptel-auto-workflow--headless t)
  ;; Remember and disable auto-revert
  (setq gptel-auto-workflow--auto-revert-was-enabled 
        (bound-and-true-p global-auto-revert-mode))
  (when gptel-auto-workflow--auto-revert-was-enabled
    (global-auto-revert-mode -1))
  ;; Disable on-load auto-compilation so clean replay/worktree buffers do not
  ;; spend their first analyzer/executor pass byte-compiling repo files.
  (setq gptel-auto-workflow--compile-angel-on-load-was-enabled
        (bound-and-true-p compile-angel-on-load-mode))
  (when (and gptel-auto-workflow--compile-angel-on-load-was-enabled
             (fboundp 'compile-angel-on-load-mode))
    (compile-angel-on-load-mode -1))
  ;; Disable undo-fu session recovery so worker daemons do not spam *Messages*
  ;; with stale-session mismatch warnings while replaying repo/worktree files.
  (setq gptel-auto-workflow--undo-fu-session-was-enabled
        (bound-and-true-p undo-fu-session-global-mode))
  (when (and gptel-auto-workflow--undo-fu-session-was-enabled
             (fboundp 'undo-fu-session-global-mode))
    (undo-fu-session-global-mode -1))
  ;; Disable recentf cleanup so worker daemons do not pollute *Messages* with
  ;; background recentf maintenance while experiments are running.
  (setq gptel-auto-workflow--recentf-was-enabled
        (bound-and-true-p recentf-mode))
  (when (and gptel-auto-workflow--recentf-was-enabled
             (fboundp 'recentf-mode))
    (recentf-mode -1))
  ;; Disable Apheleia so save-time formatting does not spawn async formatter
  ;; work inside headless experiment buffers. Keep a skip function installed so
  ;; old prog-mode hooks in long-lived daemons cannot re-enable formatter runs.
  (setq gptel-auto-workflow--apheleia-was-enabled
        (bound-and-true-p apheleia-global-mode))
  (when (boundp 'apheleia-skip-functions)
    (add-to-list 'apheleia-skip-functions
                 #'gptel-auto-workflow--suppress-apheleia-p))
  (when (and gptel-auto-workflow--apheleia-was-enabled
             (fboundp 'apheleia-global-mode))
    (apheleia-global-mode -1))
  ;; Disable lockfiles so repeated experiment/worktree reuse does not prompt.
  (setq gptel-auto-workflow--create-lockfiles-value create-lockfiles
        create-lockfiles nil)
  ;; Remember and disable uniquify (prevents ".emacs.d/" prefix in buffer names)
  (setq gptel-auto-workflow--uniquify-style 
        (when (boundp 'uniquify-buffer-name-style)
          uniquify-buffer-name-style))
  (when (boundp 'uniquify-buffer-name-style)
    (setq uniquify-buffer-name-style nil))
  (advice-add 'ask-user-about-lock :around
              #'gptel-auto-workflow--suppress-ask-user-about-lock)
  (advice-add 'ask-user-about-supersession-threat :around 
              #'gptel-auto-workflow--suppress-ask-user-about-supersession-threat)
  (advice-add 'yes-or-no-p :around 
              #'gptel-auto-workflow--suppress-yes-or-no-p)
  (advice-add 'y-or-n-p :around 
              #'gptel-auto-workflow--suppress-y-or-n-p)
  (advice-add 'kill-buffer :around 
              #'gptel-auto-workflow--suppress-kill-buffer-modified)
  ;; Suppress kill-buffer queries for modified buffers
  (add-hook 'kill-buffer-query-functions 
            #'gptel-auto-workflow--suppress-kill-buffer-query))

(defcustom gptel-auto-workflow-persistent-headless nil
  "If non-nil, keep headless suppression enabled between runs.
Set to t when running as daemon/cron to prevent interactive prompts."
  :type 'boolean
  :group 'gptel-tools-agent)

(defun gptel-auto-workflow--disable-headless-suppression ()
  "Disable suppression of interactive prompts.
Restores auto-revert, compile-angel, Apheleia, undo-fu-session, recentf,
and uniquify if they were enabled before headless operation.
Does nothing if `gptel-auto-workflow-persistent-headless' is non-nil."
  (when (and (not gptel-auto-workflow-persistent-headless)
             gptel-auto-workflow--headless)
    (setq gptel-auto-workflow--headless nil)
    ;; Restore auto-revert
    (when (and (boundp 'gptel-auto-workflow--auto-revert-was-enabled)
               gptel-auto-workflow--auto-revert-was-enabled)
      (global-auto-revert-mode 1))
    ;; Restore on-load auto-compilation only when this session disabled it.
    (when (and gptel-auto-workflow--compile-angel-on-load-was-enabled
               (fboundp 'compile-angel-on-load-mode))
      (compile-angel-on-load-mode 1))
    (setq gptel-auto-workflow--compile-angel-on-load-was-enabled nil)
    ;; Restore undo-fu-session only when this session disabled it.
    (when (and gptel-auto-workflow--undo-fu-session-was-enabled
               (fboundp 'undo-fu-session-global-mode))
      (undo-fu-session-global-mode 1))
    (setq gptel-auto-workflow--undo-fu-session-was-enabled nil)
    ;; Restore recentf only when this session disabled it.
    (when (and gptel-auto-workflow--recentf-was-enabled
               (fboundp 'recentf-mode))
      (recentf-mode 1))
    (setq gptel-auto-workflow--recentf-was-enabled nil)
    ;; Restore Apheleia only when this session disabled it.
    (when (boundp 'apheleia-skip-functions)
      (setq apheleia-skip-functions
            (delq #'gptel-auto-workflow--suppress-apheleia-p
                  apheleia-skip-functions)))
    (when (and gptel-auto-workflow--apheleia-was-enabled
               (fboundp 'apheleia-global-mode))
      (apheleia-global-mode 1))
    (setq gptel-auto-workflow--apheleia-was-enabled nil)
    ;; Restore lockfile behavior
    (setq create-lockfiles gptel-auto-workflow--create-lockfiles-value)
    ;; Restore uniquify
    (when (and (boundp 'gptel-auto-workflow--uniquify-style)
               gptel-auto-workflow--uniquify-style)
      (setq uniquify-buffer-name-style gptel-auto-workflow--uniquify-style))
    (advice-remove 'ask-user-about-lock
                   #'gptel-auto-workflow--suppress-ask-user-about-lock)
    (advice-remove 'ask-user-about-supersession-threat 
                   #'gptel-auto-workflow--suppress-ask-user-about-supersession-threat)
    (advice-remove 'yes-or-no-p 
                   #'gptel-auto-workflow--suppress-yes-or-no-p)
    (advice-remove 'y-or-n-p 
                   #'gptel-auto-workflow--suppress-y-or-n-p)
    (advice-remove 'kill-buffer 
                   #'gptel-auto-workflow--suppress-kill-buffer-modified)
    (remove-hook 'kill-buffer-query-functions 
                 #'gptel-auto-workflow--suppress-kill-buffer-query)))

(defcustom gptel-auto-workflow-git-timeout 120
  "Timeout in seconds for git commands during auto-workflow.
Default 120s (2 minutes) handles slow network connections.
Increase if git operations frequently timeout."
  :type 'integer
  :group 'gptel-tools-agent)

(defun gptel-auto-workflow--git-cmd (cmd &optional timeout)
  "Run git command CMD with TIMEOUT (default: gptel-auto-workflow-git-timeout).
Returns command output as string.
Automatically adds --no-pager to prevent blocking on pager output."
  (gptel-auto-workflow--validate-non-empty-string cmd "command")
  (let ((git-cmd (if (string-match-p "^git " cmd)
                     (concat "git --no-pager " (substring cmd 4))
                   cmd)))
    (gptel-auto-workflow--shell-command-string git-cmd (or timeout gptel-auto-workflow-git-timeout))))


(defun gptel-auto-workflow--git-result (cmd &optional timeout)
  "Run git command CMD with TIMEOUT and return (OUTPUT . EXIT-CODE).
Automatically adds --no-pager to prevent blocking on pager output."
  (gptel-auto-workflow--validate-non-empty-string cmd "command")
  (let ((git-cmd (if (string-match-p "^git " cmd)
                     (concat "git --no-pager " (substring cmd 4))
                   cmd)))
    (gptel-auto-workflow--shell-command-with-timeout
     git-cmd
     (or timeout gptel-auto-workflow-git-timeout))))

(defconst gptel-auto-workflow--skip-submodule-sync-env
  "VERIFY_NUCLEUS_SKIP_SUBMODULE_SYNC=1"
  "Environment override used to skip workflow git-hook submodule sync checks.")

(defun gptel-auto-workflow--with-skipped-submodule-sync (fn)
  "Run FN with workflow git hooks skipping submodule sync."
  (let ((process-environment
         (cons gptel-auto-workflow--skip-submodule-sync-env
               process-environment)))
    (funcall fn)))

(defconst gptel-auto-workflow--isolated-state-env-prefixes
  '("AUTO_WORKFLOW_STATUS_FILE="
    "AUTO_WORKFLOW_MESSAGES_FILE="
    "AUTO_WORKFLOW_SNAPSHOT_PATHS_FILE="
    "AUTO_WORKFLOW_EMACS_SERVER=")
  "Environment prefixes that bind a process to workflow state.")

(defvar gptel-auto-workflow--subagent-process-environment nil
  "Full isolated env to persist on routed headless subagent buffers.")

(defun gptel-auto-workflow--isolated-state-env-entry-p (entry)
  "Return non-nil when ENTRY binds shared workflow state."
  (and (stringp entry)
       (cl-some (lambda (prefix)
                  (string-prefix-p prefix entry))
                gptel-auto-workflow--isolated-state-env-prefixes)))

(defun gptel-auto-workflow--isolated-state-environment (&optional server-prefix extra-env include-messages-p)
  "Return `process-environment' isolated from live workflow state.
SERVER-PREFIX customizes the temporary daemon name prefix.
EXTRA-ENV entries are prepended ahead of the isolated workflow vars.
When INCLUDE-MESSAGES-P is non-nil, also isolate messages and snapshot files."
  (let* ((isolated-status-file (make-temp-file "auto-workflow-status-" nil ".sexp"))
         (isolated-messages-file
          (and include-messages-p
               (make-temp-file "auto-workflow-messages-" nil ".txt")))
         (isolated-snapshot-file
          (and include-messages-p
               (make-temp-file "auto-workflow-snapshot-paths-" nil ".txt")))
         (isolated-server-name
          (make-temp-name (or server-prefix "ov5-auto-workflow-test-")))
         (env
          (append
           extra-env
           (list (format "AUTO_WORKFLOW_STATUS_FILE=%s" isolated-status-file))
           (when include-messages-p
             (list (format "AUTO_WORKFLOW_MESSAGES_FILE=%s" isolated-messages-file)
                   (format "AUTO_WORKFLOW_SNAPSHOT_PATHS_FILE=%s" isolated-snapshot-file)))
           (list (format "AUTO_WORKFLOW_EMACS_SERVER=%s" isolated-server-name)))))
    (dolist (path (delq nil (list isolated-status-file
                                  (and include-messages-p isolated-messages-file)
                                  (and include-messages-p isolated-snapshot-file))))
      (when (file-exists-p path)
        (delete-file path)))
    (append (flatten-tree env)
            (cl-remove-if #'gptel-auto-workflow--isolated-state-env-entry-p
                          process-environment))))

(defun gptel-auto-workflow--persist-subagent-process-environment (&optional buffer env)
  "Persist isolated workflow ENV onto BUFFER for later async tool processes."
  (let ((target (or buffer (current-buffer)))
        (effective-env (or env gptel-auto-workflow--subagent-process-environment)))
    (when (and (not gptel-auto-workflow--defer-subagent-env-persistence)
               (buffer-live-p target)
               (listp effective-env))
      (with-current-buffer target
        (unless (and (local-variable-p 'gptel-auto-workflow--subagent-process-environment target)
                     (local-variable-p 'process-environment target)
                     (equal gptel-auto-workflow--subagent-process-environment effective-env)
                     (equal process-environment effective-env))
          (setq-local gptel-auto-workflow--subagent-process-environment
                      (copy-sequence effective-env))
          (setq-local process-environment
                      (copy-sequence effective-env)))))))

(defun gptel-auto-workflow--git-step-success-p (cmd action &optional timeout)
  "Run git CMD and report whether it succeeded.
ACTION is a short description used in the failure message."
  (pcase-let ((`(,output . ,exit-code)
               (gptel-auto-workflow--git-result cmd timeout)))
    (if (= exit-code 0)
        t
      (message "[auto-workflow] %s failed: %s"
               action
               (my/gptel--sanitize-for-logging output 200))
      nil)))

(defun gptel-auto-workflow--empty-commit-output-p (output)
  "Return non-nil when OUTPUT describes a localized clean no-op commit."
  (and (stringp output)
       (string-match-p
        "nothing to commit\\|working tree clean\\|无文件要提交\\|工作区干净"
        output)))

(defun gptel-auto-workflow--commit-step-success-p (cmd action &optional timeout)
  "Run commit CMD and report whether it succeeded or was already captured.
ACTION is a short description used in the failure message."
  (pcase-let ((`(,output . ,exit-code)
               (gptel-auto-workflow--git-result cmd timeout)))
    (cond
     ((= exit-code 0) t)
     ((gptel-auto-workflow--empty-commit-output-p output)
      (message "[auto-workflow] %s already captured (nothing new to commit)" action)
      t)
     (t
      (message "[auto-workflow] %s failed: %s"
               action
               (my/gptel--sanitize-for-logging output 200))
      nil))))

(defun gptel-auto-workflow--current-head-hash ()
  "Return the current HEAD hash in `default-directory', or nil on failure."
  (let ((hash (string-trim (or (ignore-errors
                                 (gptel-auto-workflow--git-cmd "git rev-parse HEAD" 30))
                               ""))))
    (when (string-match-p "^[a-f0-9]\\{7,40\\}$" hash)
      hash)))

(defun gptel-auto-workflow--checked-out-submodule-head (&optional worktree path)
  "Return the checked-out HEAD for top-level submodule PATH in WORKTREE.
Return nil on failure."
  (let* ((root (or worktree default-directory))
         (target (and (stringp path) (expand-file-name path root)))
         (git-marker (and target (expand-file-name ".git" target)))
         (result (and target
                      (file-directory-p target)
                      (file-exists-p git-marker)
                      (gptel-auto-workflow--git-result
                       (format "git -C %s rev-parse HEAD"
                               (shell-quote-argument target))
                       60)))
         (hash (and (consp result)
                    (car result)
                    (string-trim (car result)))))
    (when (and result
               (= 0 (cdr result))
               (string-match-p "^[a-f0-9]\\{40\\}$" hash))
      hash)))

(defun gptel-auto-workflow--restage-top-level-submodule-gitlinks (&optional worktree)
  "Restore top-level submodule gitlinks in WORKTREE after `git add -A'.
Hydrated experiment worktrees materialize submodules as checked-out
directories.
Reassert gitlink index entries so commits do not record those paths as
typechanges."
  (let* ((root (or worktree default-directory))
         (paths (gptel-auto-workflow--staging-submodule-paths root))
         failure)
    (dolist (path paths)
      (unless failure
        (let* ((commit (or (gptel-auto-workflow--checked-out-submodule-head root path)
                           (gptel-auto-workflow--staging-submodule-gitlink-revision root path)))
               (result (and commit
                            (gptel-auto-workflow--git-result
                             (format "git update-index --cacheinfo 160000 %s %s"
                                     (shell-quote-argument commit)
                                     (shell-quote-argument path))
                             60)))
               (result-output (and (consp result)
                                   (stringp (car result))
                                   (string-trim (car result)))))
          (cond
           ((not commit)
            (setq failure
                  (format "Missing gitlink revision for submodule %s" path)))
           ((or (null result) (/= 0 (cdr result)))
            (setq failure
                  (format "Failed to restage %s as gitlink: %s"
                          path
                          (or result-output "unknown error"))))))))
    (if failure
        (progn
          (message "[auto-workflow] Failed to preserve submodule gitlinks: %s"
                   (my/gptel--sanitize-for-logging failure 200))
          nil)
      t)))

(defun gptel-auto-workflow--stage-worktree-changes (action &optional timeout)
  "Stage current worktree changes for ACTION while preserving submodule gitlinks.
Returns t on success, nil on failure.
P0 FIX: More resilient to edge cases - check for changes before staging,
make submodule restaging non-fatal since it's a preservation step."
  (let ((git-add-ok (gptel-auto-workflow--git-step-success-p
                     "git add -A"
                     action
                     timeout)))
    (when git-add-ok
      ;; Restage submodule gitlinks - non-fatal if it fails
      ;; (the commit can still proceed, just may have typechange warnings)
      (let ((restage-result (condition-case err
                                (gptel-auto-workflow--restage-top-level-submodule-gitlinks)
                              (error
                               (message "[auto-workflow] Submodule restage error (non-fatal): %s"
                                        (error-message-string err))
                               t))))
        (unless restage-result
          (message "[auto-workflow] Submodule restage failed (non-fatal), continuing")))
      ;; Check if there are actually changes to commit
      (let ((status-output (gptel-auto-workflow--git-cmd
                            "git status --porcelain" 30)))
        (if (and (stringp status-output)
                 (> (length (string-trim status-output)) 0))
            t
          ;; No changes staged - this is OK for bypass commits where
          ;; the executor may have already committed or worktree is clean
          (message "[auto-workflow] No changes to stage (worktree clean)")
          t)))))

(defun gptel-auto-workflow--create-provisional-experiment-commit (target hypothesis &optional timeout)
  "Create a provisional WIP commit for TARGET and return its hash.
Returns nil when the commit could not be created."
  (let ((msg (format "WIP: experiment %s\n\nHYPOTHESIS: %s"
                     target
                     (or hypothesis "Improve code quality"))))
    (when (and (gptel-auto-workflow--stage-worktree-changes
                (format "Stage provisional experiment for %s" target)
                60)
               (gptel-auto-workflow--git-step-success-p
                (format "%s git commit -m %s"
                        gptel-auto-workflow--skip-submodule-sync-env
                        (shell-quote-argument msg))
                (format "Create provisional experiment commit for %s" target)
                (or timeout gptel-auto-workflow-git-timeout)))
      (gptel-auto-workflow--current-head-hash))))

(defun gptel-auto-workflow--promote-provisional-commit (message action provisional-hash &optional timeout)
  "Create final commit with MESSAGE, amending PROVISIONAL-HASH when needed.
ACTION is used for failure logging."
  (let* ((head-hash (and provisional-hash
                         (gptel-auto-workflow--current-head-hash)))
         (commit-command
          (format "%s git commit -m %s"
                  gptel-auto-workflow--skip-submodule-sync-env
                  (shell-quote-argument message)))
         (amend-command
          (format "%s git commit --amend -m %s"
                  gptel-auto-workflow--skip-submodule-sync-env
                  (shell-quote-argument message))))
    (if (and provisional-hash head-hash (equal provisional-hash head-hash))
        (gptel-auto-workflow--git-step-success-p
         amend-command
         (format "%s (promote provisional commit)" action)
         timeout)
      (gptel-auto-workflow--commit-step-success-p
       commit-command
       action
       timeout))))

(defun gptel-auto-workflow--drop-provisional-commit (provisional-hash action &optional timeout)
  "Drop PROVISIONAL-HASH when it is still the current HEAD.
ACTION is used for failure logging."
  (when (and provisional-hash
             (equal provisional-hash (gptel-auto-workflow--current-head-hash)))
    (gptel-auto-workflow--git-step-success-p
     "git reset --hard HEAD~1"
     action
     (or timeout 60))))

(defun gptel-auto-experiment--prepare-validation-retry-worktree (target provisional-hash)
  "Reset experiment worktree to clean base before retrying validation.
Drops PROVISIONAL-HASH when it is still the current HEAD so retries
start from a clean state."
  (and (magit-git-success "checkout" "--" ".")
       (or (null provisional-hash)
           (not (equal provisional-hash (gptel-auto-workflow--current-head-hash)))
           (gptel-auto-workflow--drop-provisional-commit
            provisional-hash
            (format "Drop provisional commit before validation retry for %s" target)))))

(defun gptel-auto-workflow--with-staging-worktree (fn)
  "Run FN with `default-directory' bound to the staging worktree.
Creates the worktree on demand and returns nil if unavailable.
Handles stale cached path: if gptel-auto-workflow--staging-worktree-dir
is set but the path doesn't exist, recreates the worktree."
  (let ((worktree (or (and gptel-auto-workflow--staging-worktree-dir
                           (file-exists-p gptel-auto-workflow--staging-worktree-dir)
                           gptel-auto-workflow--staging-worktree-dir)
                       (gptel-auto-workflow--create-staging-worktree))))
    (when (and worktree (file-exists-p worktree))
      (let ((default-directory worktree))
        ;; Merge latest main so staging tests include recent fixes
        (let ((main-merge (gptel-auto-workflow--git-result
                           (format "git merge -X theirs %s --no-ff -m %s"
                                   (shell-quote-argument "main")
                                   (shell-quote-argument "Sync main into staging for verification"))
                           180)))
          (cond
           ((null main-merge)
            (message "[auto-workflow] Main merge command returned nil (non-fatal)"))
           ((= 0 (cdr main-merge))
            (message "[auto-workflow] Merged main into staging worktree"))
           (t
            (message "[auto-workflow] Main merge into staging failed (non-fatal): %s"
                     (my/gptel--sanitize-for-logging (car main-merge) 160))
            (ignore-errors (gptel-auto-workflow--git-cmd "git merge --abort" 60)))))
        (funcall fn)))))


(defun gptel-auto-workflow--watchdog-check ()
  "Check if workflow is stuck and force-stop if necessary.
Prevents workflow from hanging indefinitely due to callback failures.
Force-stops when:
- No progress time recorded (stuck before first subagent)
- Zero active subagent tasks but workflow still says running
- Stuck for more than `gptel-auto-workflow--max-stuck-minutes' minutes"
  (condition-case err
      (when gptel-auto-workflow--running
        (let* ((stuck-minutes (and gptel-auto-workflow--last-progress-time
                                   (/ (float-time (time-subtract (current-time) gptel-auto-workflow--last-progress-time))
                                      60)))
               (elapsed-minutes (and gptel-auto-workflow--watchdog-start-time
                                    (/ (float-time (time-subtract (current-time) gptel-auto-workflow--watchdog-start-time))
                                       60)))
               (active-tasks (and (boundp 'my/gptel--agent-task-state)
                                  (hash-table-p my/gptel--agent-task-state)
                                  (hash-table-count my/gptel--agent-task-state))))
            (let ((rss-kb (and (fboundp 'gptel-auto-workflow--process-rss-kb)
                               (gptel-auto-workflow--process-rss-kb))))
               (cond
                ;; RSS exceeds force-stop threshold — memory leak or accumulation
                ;; Pi5 has 8GB total; default 4GB leaves headroom for OS + other processes
                ;; Skip force-stop if active subagent tasks are making progress
                ((and rss-kb
                      gptel-auto-workflow--rss-force-stop-kb
                      (> rss-kb gptel-auto-workflow--rss-force-stop-kb)
                      (not (and gptel-auto-workflow--rss-allow-active-tasks
                                (numberp active-tasks)
                                (> active-tasks 0))))
                 (let ((rss-mb (/ rss-kb 1024.0))
                       (threshold-mb (/ gptel-auto-workflow--rss-force-stop-kb 1024.0)))
                   (message "[auto-workflow] WATCHDOG: RSS %.0fMB exceeds %.0fMB threshold (no active subagent tasks), force-stopping" rss-mb threshold-mb)
                   (gptel-auto-workflow--force-stop)))
                ;; RSS exceeds GC threshold — trigger aggressive GC to reclaim memory
                ((and rss-kb
                      gptel-auto-workflow--rss-gc-kb
                      (> rss-kb gptel-auto-workflow--rss-gc-kb))
                 (let ((rss-mb (/ rss-kb 1024.0))
                       (threshold-mb (/ gptel-auto-workflow--rss-gc-kb 1024.0)))
                   (message "[auto-workflow] WATCHDOG: RSS %.0fMB exceeds %.0fMB GC threshold — triggering aggressive GC" rss-mb threshold-mb)
                   (garbage-collect)
                   (garbage-collect)
                   (setq gc-cons-threshold (* 50 1024 1024))  ; 50MB threshold
                   (run-with-timer 10 nil (lambda () (setq gc-cons-threshold (* 16 1024 1024))))))  ; restore after 10s
               ;; Total budget exceeded — workflow ran too long overall
            ((and (numberp elapsed-minutes) (> elapsed-minutes gptel-auto-workflow--total-budget-minutes))
             (message "[auto-workflow] WATCHDOG: Workflow exceeded total budget (%.0f > %d min), force-stopping"
                      elapsed-minutes gptel-auto-workflow--total-budget-minutes)
             (gptel-auto-workflow--force-stop))
            ;; No active subagent tasks and stuck for grace period
            ((and (numberp stuck-minutes)
                  (> stuck-minutes 10)  ; 10 min grace for backend delays (2-5min per call)
                  (not (and (numberp active-tasks) (> active-tasks 0))))
             (message "[auto-workflow] WATCHDOG: No active subagent tasks for %.1f min, force-stopping"
                      stuck-minutes)
             (gptel-auto-workflow--force-stop))
            ((null stuck-minutes)
             (message "[auto-workflow] WATCHDOG: No progress time recorded, force-stopping")
             (gptel-auto-workflow--force-stop))
            ((> stuck-minutes gptel-auto-workflow--max-stuck-minutes)
             (message "[auto-workflow] WATCHDOG: Workflow stuck for %.1f minutes, force-stopping"
                      stuck-minutes)
             (gptel-auto-workflow--force-stop))
            (t
             t)))))
    (error
     (message "[auto-workflow] WATCHDOG: Check failed: %S\n%s"
              err
              (with-output-to-string (backtrace)))
     nil)))

(defun gptel-auto-workflow--force-stop ()
  "Force-stop the current workflow run and clean up state."
  (gptel-auto-workflow--clear-runtime-subagent-provider-overrides)
  (setq gptel-auto-workflow--running nil
        gptel-auto-workflow--cron-job-running nil
        gptel-auto-workflow--run-project-root nil
        gptel-auto-workflow--current-project nil
        gptel-auto-workflow--current-target nil)
  (setq gptel-auto-workflow--stats
        (if (proper-list-p gptel-auto-workflow--stats)
            (plist-put gptel-auto-workflow--stats :phase "idle")
          (list :phase "idle")))
  (gptel-auto-workflow--persist-status)
  (when gptel-auto-workflow--watchdog-timer
    (cancel-timer gptel-auto-workflow--watchdog-timer)
    (setq gptel-auto-workflow--watchdog-timer nil))
  (gptel-auto-workflow--stop-status-refresh-timer)
  nil)

(defun gptel-auto-workflow--update-progress ()
  "Update progress timestamp for watchdog tracking."
  (setq gptel-auto-workflow--last-progress-time (current-time)))

(defun gptel-auto-workflow--restart-watchdog-timer ()
  "Restart the workflow watchdog timer if a workflow run is active."
  (when (timerp gptel-auto-workflow--watchdog-timer)
    (cancel-timer gptel-auto-workflow--watchdog-timer))
  (setq gptel-auto-workflow--watchdog-timer nil)
  (setq gptel-auto-workflow--watchdog-start-time (current-time))
  (when (or gptel-auto-workflow--running
            gptel-auto-workflow--cron-job-running)
    (setq gptel-auto-workflow--watchdog-timer
          (run-with-timer 60 60 #'gptel-auto-workflow--watchdog-check))
    (gptel-auto-workflow--start-heartbeat-timer)))

(provide 'gptel-tools-agent-experiment-loop)
;;; gptel-tools-agent-experiment-loop.el ends here
