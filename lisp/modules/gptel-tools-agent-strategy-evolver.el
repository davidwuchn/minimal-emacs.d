;;; gptel-tools-agent-strategy-evolver.el --- Meta-Harness style strategy evolution -*- lexical-binding: t; -*-
;; Part of gptel-tools-agent split
;;
;; This module implements the Meta-Harness outer loop for evolving prompt-building strategies.
;; It generates new strategy files, validates them, and tracks their performance.
;;
;; Key principle: We evolve the HARNESS (how prompts are built), not just the prompt content.

(require 'cl-lib)
(require 'subr-x)
(require 'json)

(eval-when-compile
  (require 'gptel-tools-agent-base nil t)
  (require 'gptel-tools-agent-strategy-harness nil t)
  (require 'gptel-tools-agent-prompt-build nil t)
  (require 'json))

(defvar gptel-auto-workflow--strategy-interrupted nil)
(defvar gptel-auto-workflow--strategy-evolution-enabled nil)
(defvar gptel-auto-workflow--active-strategy nil)
(declare-function gptel-auto-workflow--write-evolution-summary "gptel-tools-agent-strategy-harness")
(declare-function gptel-auto-workflow--ensure-strategy-run-directories "gptel-tools-agent-strategy-harness")
(declare-function gptel-auto-workflow--discover-strategies "gptel-tools-agent-strategy-harness")
(declare-function gptel-auto-workflow--get-strategy-performance "gptel-tools-agent-strategy-harness")
(declare-function gptel-auto-workflow--load-strategy "gptel-tools-agent-strategy-harness")
(declare-function gptel-auto-workflow--strategies-directory "gptel-tools-agent-strategy-harness")
(declare-function gptel-auto-workflow--strategy-results-file "gptel-tools-agent-strategy-harness")
(require 'gptel-tools-agent-strategy-harness nil t)

(declare-function gptel-auto-workflow--project-root "gptel-tools-agent-base" ())
(declare-function gptel-auto-workflow--results-file-path "gptel-tools-agent-base" (&optional run-id))
(declare-function gptel-request "gptel" (prompt &rest args))
(declare-function gptel-auto-workflow--load-skill-content "gptel-tools-agent-prompt-build")
(declare-function gptel-auto-workflow--find-skill-file "gptel-tools-agent-prompt-build" (skill-name))
(declare-function gptel-auto-workflow--substitute-template "gptel-tools-agent-prompt-build")
(defvar gptel-auto-workflow--suppress-strategy-metadata-persistence nil)
(defvar gptel-auto-workflow--strategy-prototype-analysis
  (list :patterns (list (list :type "memory-leak")
                        (list :type "null-check")
                        (list :type "resource-disposal")
                        (list :type "validation-guard")
                        (list :type "error-handling")
                        (list :type "nil-safety"))
        :target "lisp/modules/gptel-tools-agent-base.el"
        :failure-reasons (list "validation-failed" "syntax-error"))
  "Representative analysis plist used when validating evolved strategies.

The prototype should exercise pattern and skill-loading branches, not just the
empty-analysis happy path.")

;;; Strategy Generation

(defvar gptel-auto-workflow--strategy-evolution-axes
  '((A . "Prompt template architecture")
    (B . "Context retrieval and selection")
    (C . "Section ordering and inclusion")
    (D . "Variable computation and formatting")
    (E . "Skill loading and integration")
    (F . "Adaptive compression and filtering"))
  "Exploration axes for strategy evolution, analogous to Meta-Harness
exploitation axes.")

(defvar gptel-auto-workflow--recent-strategy-axes nil
  "Ring of last 3 axes used for strategy evolution.
∀ Vigilance: blocks same-axis proposals if all 3 are identical.")

(defun gptel-auto-workflow--check-axis-diversity (axis)
  "Return non-nil if AXIS passes diversity check.
fractal Clarity: each axis must have testable meaning.
∀ Vigilance: reject if last 3 proposals all target this axis.
Returns t if OK, or a rejection reason string if blocked."
  (let* ((symbol-axis (if (symbolp axis) axis (intern (format "%s" axis))))
         (recent gptel-auto-workflow--recent-strategy-axes)
         (last-three (seq-take recent 3)))
    (cond
     ((not (assq symbol-axis gptel-auto-workflow--strategy-evolution-axes))
      (format "Unknown axis %s — must be one of %s"
              symbol-axis
              (mapconcat (lambda (a) (format "%s" (car a)))
                         gptel-auto-workflow--strategy-evolution-axes ", ")))
     ((and (= (length last-three) 3)
           (cl-every (lambda (a) (eq a symbol-axis)) last-three))
      (message "[strategy] ∀ Vigilance: Axis %s blocked — last 3 proposals all target this axis"
               symbol-axis)
      (format "Axis %s overused — last 3 proposals all target it. Pick a different axis."
              symbol-axis))
     (t
      t))))

(defun gptel-auto-workflow--record-strategy-axis (axis)
  "Record AXIS in the recent axes ring (max 3 entries)."
  (let ((symbol-axis (if (symbolp axis) axis (intern (format "%s" axis)))))
    (push symbol-axis gptel-auto-workflow--recent-strategy-axes)
    (when (> (length gptel-auto-workflow--recent-strategy-axes) 3)
      (setq gptel-auto-workflow--recent-strategy-axes
            (seq-take gptel-auto-workflow--recent-strategy-axes 3)))))

(defun gptel-auto-workflow--strategy-axis-description (axis)
  "Return a human-readable description for strategy AXIS."
  (or (cdr (assoc (if (symbolp axis) axis (intern-soft (format "%s" axis)))
                  gptel-auto-workflow--strategy-evolution-axes))
      "Unknown strategy axis"))

(defun gptel-auto-workflow--extract-proposer-name (candidate-code)
  "Extract the strategy name proposed by the agent from CANDIDATE-CODE.
Looks for patterns like ';;; strategy-NAME.el ---' in the candidate.
Returns the extracted name, or nil if not found."
  (when (stringp candidate-code)
    (if (string-match ";;;\\s-+strategy-\\([^.]+\\)\\.el\\s-+---" candidate-code)
        (match-string 1 candidate-code)
      (if (string-match "strategy-\\([[:alnum:]-]+\\)-build-prompt" candidate-code)
          (match-string 1 candidate-code)
        nil))))

(defun gptel-auto-workflow--generate-strategy-name (&optional proposed-name)
  "Generate a unique strategy name.
If PROPOSED-NAME is provided, meaningful (not generic like evolved-NNNN),
and available, use it. Otherwise returns nil — the caller must reject
the candidate and ask the proposer for a better name."
  (if (and proposed-name
           (not (string-empty-p proposed-name))
           ;; Reject generic auto-generated names
           (not (string-match-p "\\`evolved-?[0-9]\\{1,4\\}\\'" proposed-name))
           (not (string-match-p "\\`candidate-" proposed-name))
           (not (file-exists-p
                 (expand-file-name
                  (format "strategy-%s.el" proposed-name)
                  (gptel-auto-workflow--strategies-directory)))))
      proposed-name
    (when (and proposed-name
               (or (string-match-p "\\`evolved-?[0-9]\\{1,4\\}\\'" proposed-name)
                   (string-match-p "\\`candidate-" proposed-name)))
      (message "[strategy-evolution] Rejected generic name '%s', proposer must use descriptive name"
               proposed-name))
    nil))

(defun gptel-auto-workflow--valid-strategy-name-p (name)
  "Return non-nil if NAME is a valid strategy name.
Rejects log messages and other garbage."
  (and (stringp name)
       (string-match-p "\\`[a-z][a-z0-9-]+\\'" name)
       (not (string-match-p "\\[strategy-evolution\\]\\|REJECTED\\|ACCEPTED" name))))

;;; Strategy Template

(defun gptel-auto-workflow--strategy-template (name hypothesis axis parent-strategies code)
  "Generate a strategy file from template.
NAME: strategy name
HYPOTHESIS: what this strategy changes and why
AXIS: which exploitation axis this targets (A-F)
PARENT-STRATEGIES: list of parent strategy names this builds on
CODE: the actual implementation code"
  (format ";;; strategy-%s.el --- Evolved prompt-building strategy -*- lexical-binding: t; -*-
;; Strategy for gptel-tools-agent-strategy-harness
;;
;; Hypothesis: %s
;; Axis: %s (%s)
;; Parents: %s
;; Generated: %s
;;
;; CRITICAL: This strategy introduces a NEW mechanism, not just parameter tuning.
;; If this is just changing constants or ordering, it should be rejected.

(require 'gptel-tools-agent-prompt-build)

(defun strategy-%s-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  %S
  %s)

(defun strategy-%s-get-metadata ()
  %S
  (list :name %S
        :version %S
        :hypothesis %S
        :axis %S
        :created %S
        :parent-strategies '%s
        :description %S))

;; Register self
(when (fboundp 'gptel-auto-workflow--register-strategy)
  (gptel-auto-workflow--register-strategy
   %S
   #'strategy-%s-build-prompt
   (strategy-%s-get-metadata)))

(provide 'strategy-%s)
;;; strategy-%s.el ends here"
          name
          hypothesis
          axis
          (gptel-auto-workflow--strategy-axis-description axis)
          (prin1-to-string parent-strategies)
          (format-time-string "%Y-%m-%d")
          name
          (format "Build prompt using evolved strategy %s.\nHYPOTHESIS: %s" name hypothesis)
          code
          name
          "Return metadata for this strategy."
          name
          "1.0"
          hypothesis
          (format "%s" axis)
          (format-time-string "%Y-%m-%d")
          (prin1-to-string parent-strategies)
          hypothesis
          name
          name
          name
          name
          name))

;;; Self-Critique: Parameter vs Mechanism Detection

(defun gptel-auto-workflow--is-parameter-variant-p (new-code parent-code)
  "Check if NEW-CODE is just a parameter variant of PARENT-CODE.
Returns t if the only changes are constants, ordering, or formatting.
Returns nil if there's a genuine new mechanism."
  (let ((new-clean (gptel-auto-workflow--normalize-code new-code))
        (parent-clean (gptel-auto-workflow--normalize-code parent-code)))
    ;; Check if the core logic structure is identical
    ;; A parameter variant will have the same function calls and control flow
    ;; but different constants/literals
    (and
     ;; Same top-level functions defined
     (equal (gptel-auto-workflow--extract-function-names new-clean)
            (gptel-auto-workflow--extract-function-names parent-clean))
     ;; Same control flow structures
     (equal (gptel-auto-workflow--extract-control-flow new-clean)
            (gptel-auto-workflow--extract-control-flow parent-clean))
     ;; But different constants
     (not (equal (gptel-auto-workflow--extract-constants new-clean)
                 (gptel-auto-workflow--extract-constants parent-clean))))))

(defun gptel-auto-workflow--normalize-code (code)
  "Normalize code for comparison by removing whitespace and comments."
  (when (null code)
    (setq code ""))
  (with-temp-buffer
    (insert code)
    ;; Remove comments
    (goto-char (point-min))
    (while (re-search-forward ";.*$" nil t)
      (replace-match ""))
    ;; Normalize whitespace
    (goto-char (point-min))
    (while (re-search-forward "[ \t\n]+" nil t)
      (replace-match " "))
    (buffer-string)))

(defun gptel-auto-workflow--valid-code-string-p (code)
  "Check if CODE is a non-empty string suitable for extraction.
Returns CODE if valid, nil otherwise."
  (and (stringp code) (not (string-empty-p code)) code))

(defun gptel-auto-workflow--extract-matches (code pattern &optional group-index)
  "Extract all matches of PATTERN from CODE.
PATTERN is a regex to search for.
GROUP-INDEX (default 0) is which match group to extract.
Returns sorted list of unique matches."
  (if-let ((valid-code (gptel-auto-workflow--valid-code-string-p code)))
      (let (matches)
        (with-temp-buffer
          (insert valid-code)
          (goto-char (point-min))
          (while (re-search-forward pattern nil t)
            (push (match-string (or group-index 0)) matches)))
        (sort (delete-dups matches) #'string<))
    '()))

(defun gptel-auto-workflow--extract-function-names (code)
  "Extract defined function names from CODE.
Returns empty list if CODE is nil or empty."
  (gptel-auto-workflow--extract-matches code "(defun\\s-+\\([^ ]+\\)" 1))

(defun gptel-auto-workflow--extract-control-flow (code)
  "Extract control flow structure from CODE (if/cond/while/etc).
Returns empty list if CODE is nil or empty."
  (gptel-auto-workflow--extract-matches code "(\\(if\\|cond\\|when\\|unless\\|while\\|dolist\\|dotimes\\|cl-loop\\)" 1))

(defun gptel-auto-workflow--extract-constants (code)
  "Extract string and number constants from CODE.
Returns empty list if CODE is nil or empty."
  (append
   (gptel-auto-workflow--extract-matches code "\"[^\"]*\"" 0)
   (gptel-auto-workflow--extract-matches code "\\b[0-9]+\\b" 0)))

;; ─── Prototype Error Tracking (Self-Evolution) ───

(defvar gptel-auto-workflow--prototype-error-log nil
  "List of (strategy-name . error-string) pairs from failed prototypes.")
(defvar gptel-auto-workflow--prototype-error-patterns nil
  "Persistent alist of ((:type :description) . count) from prototype failures.")

(defun gptel-auto-workflow--classify-prototype-error (error-string)
  "Classify ERROR-STRING into (:type :description) plist, or nil."
  (cond
   ((string-match-p "void-function" error-string)
    '(:type "undefined-function" :description "LLM called undefined function"))
   ((string-match-p "void-variable" error-string)
    '(:type "undefined-variable" :description "LLM referenced nonexistent variable"))
   ((string-match-p "wrong-number-of-arguments" error-string)
    '(:type "wrong-arity" :description "Lambda/call with wrong argument count"))
   ((string-match-p "wrong-type-argument" error-string)
    '(:type "wrong-type" :description "Wrong data type passed to function"))
   ((string-match-p "invalid-read-syntax" error-string)
    '(:type "syntax-error" :description "Unbalanced parens or invalid syntax"))
   ((string-match-p "Eager macro-expansion failure" error-string)
    '(:type "macro-expansion" :description "Macro expansion failure"))
   ((string-match-p "Unbalanced parens" error-string)
    '(:type "unbalanced-parens" :description "Unbalanced parentheses"))
   ((string-match-p "let binding.*>2 values" error-string)
    '(:type "let-multi-value" :description "Let binding with >1 value form"))
   ((string-match-p "Non-ELisp function" error-string)
    '(:type "cl-function" :description "CL-only function not in Emacs Lisp"))
   (t nil)))

(defun gptel-auto-workflow--record-prototype-error (_strategy-name error-string)
  "Record a prototype error, updating the persistent pattern counter."
  (let ((pattern (gptel-auto-workflow--classify-prototype-error error-string)))
    (when pattern
      (let ((cell (assoc pattern gptel-auto-workflow--prototype-error-patterns)))
        (if cell
            (setcdr cell (1+ (cdr cell)))
          (push (cons pattern 1) gptel-auto-workflow--prototype-error-patterns))))))

(defun gptel-auto-workflow--format-prototype-error-insights ()
  "Format top-5 prototype error patterns into prompt text, or empty string."
  (let* ((sorted (sort (copy-sequence gptel-auto-workflow--prototype-error-patterns)
                       (lambda (a b) (> (cdr a) (cdr b)))))
         (top5 (seq-take sorted (min 5 (length sorted))))
         (total (apply #'+ (mapcar #'cdr top5))))
    (if (= total 0) ""
      (concat "\n## Prototype Error Patterns (Self-Evolution)\n"
              "Avoid these mistakes found in recent prototypes:\n"
              (mapconcat
               (lambda (e)
                 (format "- %s (%.0f%%): %s"
                         (plist-get (car e) :type)
                         (* 100 (/ (float (cdr e)) total))
                         (plist-get (car e) :description)))
               top5 "\n") "\n"))))

(defun gptel-auto-workflow--clear-prototype-error-log ()
  "Clear the prototype error log for a new evolution cycle."
  (setq gptel-auto-workflow--prototype-error-log nil))

;;; Prototyping Phase

(defun gptel-auto-workflow--prevalidate-prototype (code)
  "Pre-validate strategy CODE for common LLM-generated syntax errors.
Returns list of error strings, nil if clean. Checks: paren balance,
let binding multi-value-forms, and ELisp-unknown function names."
  (let ((warnings '()))
    ;; 1. Paren balance: scan-sexps is the authoritative check
    (condition-case err
        (with-temp-buffer
          (insert code)
          (scan-sexps (point-min) (point-max)))
      (error
       (push (format "Unbalanced parens: %s" (error-message-string err)) warnings)))
    ;; 2. let / let* with multiple values per binding
    ;; Pattern: (let ((VAR VAL1 VAL2 VAL3 ...)) — match bindings with >2 value forms
    (let ((pos 0))
      (while (string-match "(let\\*?\\s-+((\\(\\w+\\)\\s-+\\S+\\s-+\\S+\\s-+\\S+" code pos)
        (push (format "let binding '%s' has >2 values" (match-string 1 code)) warnings)
        (setq pos (match-end 0))))
    ;; 3. Known CL-only or non-ELisp function names
    (let ((cl-only-fns '("howmany" "file" "cw" "format-t" "make-string-output-stream"
                         "get-output-stream-string" "with-output-to-string"
                         "pprint" "pprint-logical-block" "pprint-fill"
                         "pprint-indent" "pprint-newline" "map-into"
                         "reduce" "some" "every" "notevery" "notany" "mapcan" "mapcon"))
          (start 0))
      (while (string-match "\\_<\\(\\w+\\)\\_>" code start)
        (let ((word (match-string 1 code)))
          (when (member word cl-only-fns)
            (push (format "Non-ELisp function '%s' not available" word) warnings))
          (setq start (match-end 1)))))
    (nreverse warnings)))

(defun gptel-auto-workflow--prototype-strategy (strategy-code test-target)
  "Prototype STRATEGY-CODE against TEST-TARGET before finalizing.
Returns plist with :valid t/nil :errors list :test-output string."
  (let ((temp-file (make-temp-file "strategy-prototype-" nil ".el"))
        (errors '())
        (test-output "")
        (missing-skills nil))
    (unwind-protect
        (progn
          ;; Write strategy to temp file
          (with-temp-file temp-file
            (insert strategy-code))
          
          ;; Pre-validate before attempting load (catches common syntax errors)
          (setq errors (gptel-auto-workflow--prevalidate-prototype strategy-code))
          
          ;; Test 1: Load without errors (only if pre-validation passed)
          ;; Guard: strip lexical-binding from prototype (avoids reader bug
          ;; with invalid-read-syntax on some Emacs 30 builds) and verify
          ;; file ends with newline (avoids end-of-file from truncated write).
          (unless errors
          (condition-case err
              (let ((gptel-auto-workflow--suppress-strategy-metadata-persistence t)
                    (load-read-function #'read))
                (with-temp-buffer
                  (insert-file-contents temp-file)
                  (save-excursion
                    (goto-char (point-min))
                    (when (re-search-forward
                           "-\\*-.*lexical-binding: t[^-]*-\\*-" (line-end-position) t)
                      (replace-match "-*- lexical-binding: nil -*-")))
                  (let ((content (buffer-string)))
                    (unless (string-suffix-p "\n" content)
                      (setq content (concat content "\n"))
                      (with-temp-file temp-file
                        (insert content)))))
                (load temp-file nil t t))
             (error
              (push (format "Load error: %s" err) errors))))
          
          ;; Test 2: Build function exists and is callable
          (unless errors
            (condition-case err
                (let* ((build-fn-name (gptel-auto-workflow--extract-build-function-name strategy-code))
                        (build-fn (intern build-fn-name)))
                  (if (fboundp build-fn)
                      (let ((load-skill-fn (and (fboundp 'gptel-auto-workflow--load-skill-content)
                                                (symbol-function 'gptel-auto-workflow--load-skill-content))))
                        (if load-skill-fn
                            (cl-letf (((symbol-function 'gptel-auto-workflow--load-skill-content)
                                       (lambda (skill-name)
                                         (unless (and (fboundp 'gptel-auto-workflow--find-skill-file)
                                                      (gptel-auto-workflow--find-skill-file skill-name))
                                           (push skill-name missing-skills))
                                         (funcall load-skill-fn skill-name))))
                              (setq test-output
                                    (funcall build-fn test-target 1 10
                                             gptel-auto-workflow--strategy-prototype-analysis
                                             0.5
                                             (list (list :decision "discarded"
                                                         :reason "validation-failed"
                                                         :target test-target)))))
                          (setq test-output
                                (funcall build-fn test-target 1 10
                                         gptel-auto-workflow--strategy-prototype-analysis
                                         0.5
                                         (list (list :decision "discarded"
                                                     :reason "validation-failed"
                                                     :target test-target))))))
                    (push "Build function not found after loading" errors)))
              (error
                (push (format "Build error: %s" err) errors))))
          
          ;; Test 3: Output is a string
          (when (and (not errors) (not (stringp test-output)))
            (push (format "Build function returned %s instead of string" (type-of test-output)) errors))

          ;; Test 4: Skill-loading strategies must reference real skills.
          (when (and (not errors)
                     (string-match-p "gptel-auto-workflow--load-skill-content" strategy-code))
            (let ((static-missing-skills nil))
              (dolist (skill (gptel-auto-workflow--extract-loaded-skill-names strategy-code))
                (when (and (fboundp 'gptel-auto-workflow--find-skill-file)
                           (not (gptel-auto-workflow--find-skill-file skill)))
                  (push skill static-missing-skills)))
              (when (or missing-skills static-missing-skills)
                (push (format "Missing referenced skills: %s"
                              (mapconcat #'identity
                                         (sort (delete-dups (append missing-skills static-missing-skills)) #'string<)
                                         ", "))
                      errors))))

          ;; Record errors for self-evolution
          (dolist (err errors)
            (gptel-auto-workflow--record-prototype-error "prototype" err))
          (list :valid (null errors)
                 :errors (nreverse errors)
                 :output test-output))
      (when (file-exists-p temp-file)
        (delete-file temp-file)))))

(defun gptel-auto-workflow--extract-loaded-skill-names (code)
  "Return literal skill names loaded by strategy CODE."
  (let ((names nil))
    (when (stringp code)
      (with-temp-buffer
        (insert code)
        (goto-char (point-min))
        (while (re-search-forward "gptel-auto-workflow--load-skill-content[[:space:]\n]+\"\\([^\"]+\\)\"" nil t)
          (push (match-string 1) names))))
    (delete-dups (nreverse names))))

(defun gptel-auto-workflow--extract-build-function-name (code)
  "Extract the build function name from strategy CODE.
Returns default name if CODE is nil or invalid."
  (if-let ((valid-code (gptel-auto-workflow--valid-code-string-p code)))
      (with-temp-buffer
        (insert valid-code)
        (goto-char (point-min))
        (if (re-search-forward "(defun\\s-+\\(strategy-[^ ]+-build-prompt\\)" nil t)
            (match-string 1)
          "strategy-unknown-build-prompt"))
    "strategy-unknown-build-prompt"))

(defun gptel-auto-workflow--extract-build-function-body (code)
  "Extract just the function body from strategy CODE.
Returns the body as a string, or CODE if extraction fails or CODE is nil."
  (if-let ((valid-code (gptel-auto-workflow--valid-code-string-p code)))
      (with-temp-buffer
        (insert valid-code)
        (goto-char (point-min))
        ;; Find the build-prompt function
        (if (re-search-forward "(defun\\s-+strategy-[^ ]+-build-prompt\\s-+" nil t)
            (let ((start (point)))
              ;; Find matching closing paren
              (condition-case nil
                  (progn
                    (forward-sexp)
                    ;; Extract body (skip docstring if present)
                    (let ((func-end (point))
                          (body-start start))
                      (goto-char start)
                      ;; Skip docstring
                      (when (looking-at "\\s-*\"")
                        (forward-sexp)
                        (setq body-start (point)))
                      ;; Skip interactive declaration
                      (goto-char body-start)
                      (when (looking-at "\\s-*(interactive")
                        (forward-sexp)
                        (setq body-start (point)))
                      ;; Return body
                      (string-trim (buffer-substring body-start (1- func-end)))))
                (error valid-code)))
          valid-code))
    code))

;;; Warm-Start from Historical Trace Analysis

(defun gptel-auto-workflow--analyze-strategy-failures (strategy-name)
  "Analyze TSV results to find failure patterns for STRATEGY-NAME.
Returns formatted string of top 5 failure reasons, or empty string if
none found."
  (let ((results-file (gptel-auto-workflow--results-file-path))
        (failure-reasons (make-hash-table :test 'equal))
        (total-failures 0))
    (when (file-exists-p results-file)
      (with-temp-buffer
        (insert-file-contents results-file)
        (goto-char (point-min))
        (forward-line 1) ; Skip header
        (while (not (eobp))
          (let* ((line (buffer-substring (line-beginning-position) (line-end-position)))
                 (fields (split-string line "\t")))
             (when (>= (length fields) 20)
               (let* ((field-count (length fields))
                      ;; 20/24-col: strategy at index 19; 27-col: strategy at index 20
                      (strategy-idx (if (<= field-count 24) 19 20))
                      (entry-strategy (nth strategy-idx fields))
                      (decision (nth 7 fields))
                      (reason (nth 11 fields)))
                 (when (and (equal entry-strategy strategy-name)
                            (equal decision "discarded")
                            (not (string-empty-p reason)))
                   (setq total-failures (1+ total-failures))
                   (puthash reason (1+ (gethash reason failure-reasons 0)) failure-reasons)))))
          (forward-line 1))))

    (if (= total-failures 0)
        ""
      ;; Sort by frequency and take top 5
      (let ((sorted '()))
        (cl-flet ((collect-failure (reason count)
                   (push (cons count reason) sorted)))
          (maphash #'collect-failure failure-reasons))
        (setq sorted (sort sorted (lambda (a b) (> (car a) (car b)))))
        (concat "## Historical Failure Patterns for This Strategy\n"
                (format "Total discarded experiments: %d\n" total-failures)
                "Top failure reasons:\n"
                (mapconcat (lambda (pair)
                            (format "- %s (occurred %d times)" (cdr pair) (car pair)))
                          (cl-subseq sorted 0 (min 5 (length sorted)))
                          "\n")
                "\n\nAVOID these failure modes in your new strategy.\n\n")))))

(defvar gptel-auto-workflow--proposer-skill-path
  "assistant/skills/meta-harness-proposer/SKILL.md"
  "Path to the Meta-Harness proposer skill file.")

(defun gptel-auto-workflow--load-proposer-skill ()
  "Load the proposer skill content if available.
Uses standard skill loader for consistency."
  (let ((content (gptel-auto-workflow--load-skill-content "meta-harness-proposer")))
    (if (string-empty-p content)
        nil
      content)))

(defun gptel-auto-workflow--load-strategy-proposer-template ()
  "Load strategy proposer prompt template from skill.
Returns template string or nil if skill not available."
  (when (fboundp 'gptel-auto-workflow--load-skill-content)
    (let ((content (gptel-auto-workflow--load-skill-content "strategy-proposer")))
      (unless (string-empty-p content)
        content))))

(defun gptel-auto-workflow--propose-strategies (parent-strategy-name axis hypothesis parent-code parent-perf)
  "Use gptel to propose 3 new strategy implementations.
Returns list of 3 strategy code strings, or nil if generation fails."
  (cond
   (gptel-auto-workflow--strategy-interrupted
    (message "[strategy-evolution] Interrupted, skipping proposal")
    nil)
   ((not (fboundp 'gptel-request))
    (message "[strategy-evolution] gptel not available, cannot propose strategies")
    nil)
   (t
    (let* ((axis-desc (gptel-auto-workflow--strategy-axis-description axis))
           (failure-analysis (gptel-auto-workflow--analyze-strategy-failures parent-strategy-name))
           (allium-findings (if (fboundp 'gptel-auto-workflow--allium-load-issues-for-guidance)
                                (gptel-auto-workflow--allium-load-issues-for-guidance)
                              ""))
           (skill-content (gptel-auto-workflow--load-proposer-skill))
            (proposer-template (or (gptel-auto-workflow--load-strategy-proposer-template)
                                   "You are a Meta-Harness strategy proposer. Your job is to generate NEW Emacs Lisp prompt-building strategies.

## Context

We are evolving prompt-building STRATEGIES (not prompt content). Strategies are Emacs Lisp functions that build prompts for an AI code improvement system.

{{skill-content}}

Evolution hypothesis: {{hypothesis}}

## Parent Strategy

Current strategy: {{parent-strategy}}
Performance: {{total-experiments}} experiments, {{success-rate}}% success rate, avg score {{avg-score}}

Parent strategy code:
```elisp
{{parent-code}}
```

{{failure-analysis}}

{{prototype-errors}}

{{allium-findings}}

## Anti-Overfitting Rules

- NO target-specific hints. Do not hardcode knowledge about specific files or modules.
- NEVER mention target file names in strategy code, prompts, or comments.
- Strategies must work on ANY Emacs Lisp file. Do not assume specific module structures.
- General patterns are OK (e.g., 'prioritize failure patterns for large files').

## Task

Generate 3 NEW strategy implementations that target axis {{axis}} ({{axis-desc}}).

Axis {{axis}} means: {{axis-desc}}

## Requirements

1. Each strategy MUST introduce a genuinely NEW mechanism, not just parameter tuning
2. Valid mechanism changes:
   - Different section ordering or inclusion logic
   - New context retrieval (e.g., load additional files, use different git commands)
   - Different variable computation (e.g., compute new statistics, filter differently)
   - New skill loading patterns
   - Different adaptive compression strategies
3. INVALID changes (will be rejected):
   - Same logic, different constants
   - Just reordering existing code without changing behavior
   - Changing string literals but keeping same structure

## Common Lisp Functions NOT Available in Emacs Lisp

These Common Lisp functions DO NOT EXIST in Emacs Lisp and will cause errors:
- `getf` → use `plist-get`
- `plusp` → use `(> n 0)`
- `remf` → use `cl-remf` (requires cl-lib)
- `psetq` → use `setq`
- `incf` → use `(setq x (1+ x))`
- `decf` → use `(setq x (1- x))`
- `return-from` → requires `cl-block` wrapper

ALWAYS use `plist-get` for plist access, never `getf`.

## Output Format

For each candidate, output EXACTLY:

CANDIDATE_1:
```elisp
;;; strategy-NAME.el --- DESCRIPTION -*- lexical-binding: t; -*-
;; Hypothesis: ONE SENTENCE
;; Axis: {{axis}}
;;
;; IMPORTANT: Use a MEANINGFUL name replacing NAME (e.g., strategy-weighted-skills,
;; strategy-outcome-reasoning, not strategy-evolved-0006).
;; The name should describe the core mechanism in 2-4 hyphenated words.

(require 'gptel-tools-agent-prompt-build)
(declare-function gptel-auto-workflow--load-skill-content "gptel-tools-agent-prompt-build")
(declare-function gptel-auto-workflow--substitute-template "gptel-tools-agent-prompt-build")

(defun strategy-NAME-build-prompt (target experiment-id max-experiments
analysis baseline previous-results)
  ;; NEW MECHANISM HERE
  ;; Must return a string (the prompt)
  )

(defun strategy-NAME-get-metadata ()
  (list :name \"NAME\"
        :version \"1.0\"
        :hypothesis \"DESCRIPTION\"
        :axis \"{{axis}}\"
        :components [\"tag1\" \"tag2\"]))

(provide 'strategy-NAME)
```

CANDIDATE_2:
[same format, different mechanism]

CANDIDATE_3:
[same format, different mechanism]

## Important

- The build function MUST call functions from `gptel-tools-agent-prompt-build`
module
- Available functions include:
  - `gptel-auto-experiment-build-prompt` (baseline)
  - `gptel-auto-workflow--load-prompt-template`
  - `gptel-auto-workflow--substitute-template`
  - `gptel-auto-workflow--select-ab-test-sections`
  - `gptel-auto-workflow--adapt-prompt-compression`
  - `gptel-auto-experiment--format-failure-patterns`
  - `gptel-auto-experiment--format-axis-guidance`
  - `gptel-auto-experiment--frontier-saturation-guidance`
  - `gptel-auto-experiment--format-cross-target-patterns`
  - `gptel-auto-workflow--load-skill-content`
  - `gptel-auto-workflow--get-worktree-dir`
  - `gptel-auto-experiment--get-topic-knowledge`
- Each candidate should explore a DIFFERENT mechanism within axis {{axis}}
- Do NOT output any explanation, ONLY the 3 candidates"))
            (proposer-prompt
             (gptel-auto-workflow--substitute-template
              proposer-template
              `((skill-content . ,(if (and skill-content (not (string-empty-p skill-content)))
                                      (format "## Proposer Skill\n\n%s" skill-content)
                                    ""))
                (hypothesis . ,hypothesis)
                (parent-strategy . ,parent-strategy-name)
                (total-experiments . ,(format "%d" (plist-get parent-perf :total)))
                (success-rate . ,(format "%.0f" (* 100 (plist-get parent-perf :success-rate))))
                (avg-score . ,(format "%.2f" (plist-get parent-perf :avg-score)))
                (parent-code . ,(or parent-code "(baseline strategy)"))
                (failure-analysis . ,(or failure-analysis ""))
                (prototype-errors . ,(gptel-auto-workflow--format-prototype-error-insights))
                (allium-findings . ,(if (string-empty-p allium-findings) "" (concat "## Allium Behavioral Audit (coherence gaps from last cycle)\n\n" allium-findings)))
                (axis . ,(format "%s" axis))
                (axis-desc . ,axis-desc)))))

    ;; Make synchronous gptel request
    (message "[strategy-evolution] Requesting strategy proposals from agent...")
    (let ((responses nil)
          (done nil))
      (condition-case err
          (progn
            (gptel-request proposer-prompt
                          :system "You are a strategy proposer for an automated code improvement system. You generate Emacs Lisp code for prompt-building strategies. Output ONLY code, no explanations."
                          :callback (lambda (response _info)
                                     (setq responses
                                           (cond ((stringp response) response)
                                                 ((and (listp response) (plist-get response :content))
                                                  (plist-get response :content))
                                                  (t (prin1-to-string response)))
                                           done t)))
            ;; Wait for response (with timeout). Use accept-process-output
            ;; instead of sleep-for to allow network I/O callbacks to fire.
            ;; sleep-for blocks the event loop in daemon mode, preventing
            ;; gptel's async response handler from running.
            (with-timeout (120 (message "[strategy-evolution] Timeout waiting for proposals")
                             nil)
              (let ((iterations 0)
                    (max-iterations 300))
                (while (and (not done)
                            (< (cl-incf iterations) max-iterations))
                  (accept-process-output nil 0.5))
                (when (and (not done) (>= iterations max-iterations))
                  (message "[strategy-evolution] Exhausted %d iterations waiting for proposals" iterations))))

            (when responses
              (message "[strategy-evolution] Received proposals, parsing...")
              (gptel-auto-workflow--parse-strategy-candidates responses)))
        (error
         (message "[strategy-evolution] Error requesting proposals: %s" err)
         nil)))))))

(defun gptel-auto-workflow--parse-strategy-candidates (response)
  "Parse 3 strategy candidates from gptel RESPONSE.
Returns list of 3 code strings.  Handles multiple formats: CANDIDATE_N
markers, numbered lists, or bare code blocks."
  (if (or (null response) (not (stringp response)) (string-empty-p response))
      (progn
        (message "[strategy-evolution] Invalid response for parsing")
        (list nil nil nil))
    (let ((candidates '()))
    ;; Try CANDIDATE_N format first
    (dotimes (i 3)
      (let* ((start-label (format "CANDIDATE_%d:" (1+ i)))
             (end-label (format "CANDIDATE_%d:" (+ i 2)))
             (case-fold-search nil))
        (when (string-match (regexp-quote start-label) response)
          (let* ((start (match-end 0))
                 (end (if (string-match (regexp-quote end-label) response start)
                          (match-beginning 0)
                        (length response)))
                 (block (string-trim (substring response start end))))
            (when (string-match "```\\(?:elisp\\|emacs-lisp\\)?[[:space:]]*\\(\\(?:.\\|\n\\)*?\\)[[:space:]]*```" block)
              (setq block (string-trim (match-string 1 block))))
            (when (and block (> (length block) 50))
              (push block candidates))))))
    ;; Fallback: look for any elisp code blocks
    (when (< (length candidates) 3)
      (let ((pos 0))
        (while (and (< (length candidates) 3)
                    (string-match "```\\(?:elisp\\|emacs-lisp\\)?[[:space:]]*\\(\\(?:.\\|\n\\)*?\\)[[:space:]]*```" response pos))
          (let ((block (string-trim (match-string 1 response))))
            (when (and (> (length block) 50)
                       (string-match-p "(defun strategy-" block)
                       (not (member block candidates)))
              (push block candidates)))
          (setq pos (match-end 0)))))
    ;; Fallback 2: look for (defun strategy-... patterns directly
    (when (< (length candidates) 3)
      (let ((pos 0))
        (while (and (< (length candidates) 3)
                    (string-match "(defun strategy-[^[:space:]]+-build-prompt" response pos))
          (let ((start (match-beginning 0))
                (end (or (string-match "(provide " response (match-end 0))
                         (length response))))
            (let ((block (string-trim (substring response start end))))
              (when (and (> (length block) 50)
                         (not (member block candidates)))
                (push block candidates))))
          (setq pos (match-end 0)))))
    (setq candidates (nreverse candidates))
    (while (< (length candidates) 3)
      (setq candidates (append candidates (list nil))))
    (message "[strategy-evolution] Parsed %d valid candidates"
             (length (cl-remove-if #'null candidates)))
    candidates)))

(defun gptel-auto-workflow--strategy-code-rewrite-name (code old-name new-name)
  "Rewrite strategy CODE from OLD-NAME to NEW-NAME."
  (let ((rewritten code))
    (setq rewritten (replace-regexp-in-string
                     (regexp-quote old-name) new-name rewritten t t))
    (setq rewritten (replace-regexp-in-string
                     "(provide 'strategy-[^)]+)"
                     (format "(provide 'strategy-%s)" new-name)
                     rewritten t t))
    rewritten))

(defun gptel-auto-workflow--prepare-strategy-candidate (candidate-code candidate-name)
  "Prepare CANDIDATE-CODE as a standalone strategy named CANDIDATE-NAME."
  (let ((code (string-trim candidate-code)))
    (if (string-match "strategy-\\([^[:space:])]+\\)-build-prompt" code)
        (gptel-auto-workflow--strategy-code-rewrite-name
         code
         (match-string 1 code)
         candidate-name)
      (gptel-auto-workflow--strategy-template
       candidate-name
       "Agent-proposed strategy candidate"
       'A
       nil
       code))))

;;; Strategy Evolution Loop

(defun gptel-auto-workflow--evolve-strategy (parent-strategy-name hypothesis axis)
  "Evolve a new strategy from PARENT-STRATEGY-NAME.
HYPOTHESIS describes the mechanism change.
AXIS is the exploitation axis (A-F).
∀ Vigilance: rejects if axis has been overused (last 3 proposals same axis).
Returns new strategy name or nil if rejected."
  (let* ((diversity-check (gptel-auto-workflow--check-axis-diversity axis))
         (parent-file (expand-file-name
                       (format "strategy-%s.el" parent-strategy-name)
                       (gptel-auto-workflow--strategies-directory)))
         (parent-code (when (file-exists-p parent-file)
                        (with-temp-buffer
                          (insert-file-contents parent-file)
                          (buffer-string))))
         (parent-perf (gptel-auto-workflow--get-strategy-performance parent-strategy-name)))
    (if (not diversity-check)
        (progn
          (message "[strategy-evolution] REJECTED: Axis diversity check failed — %s" diversity-check)
          nil)
      (let* (;; Generate 3 candidates using agent-driven proposer
             (candidates (gptel-auto-workflow--propose-strategies
                          parent-strategy-name axis hypothesis parent-code parent-perf))
             (valid-candidates '()))
    
    ;; Validate each candidate
    (dolist (candidate (or candidates '()))
      (when candidate
        (let* ((candidate-index (1+ (- (length candidates)
                                        (length (member candidate candidates)))))
                (candidate-name (format "candidate-%s-%d" 
                                        (if parent-strategy-name
                                            (substring (format "%s" parent-strategy-name) 0 (min 10 (length parent-strategy-name)))
                                          "evolved")
                                        candidate-index))
                (proposer-name (gptel-auto-workflow--extract-proposer-name candidate))
                (candidate-code (gptel-auto-workflow--prepare-strategy-candidate candidate candidate-name)))

          ;; Check 1: Not a parameter variant
          (if (and parent-code
                   (gptel-auto-workflow--is-parameter-variant-p candidate-code parent-code))
              (progn
                (message "[strategy-evolution] REJECTED candidate: Parameter variant")
                nil)

            ;; Check 2: Prototype validation
            (let ((prototype (gptel-auto-workflow--prototype-strategy
                             candidate-code
                             "lisp/modules/gptel-tools-agent-base.el")))
              (if (not (plist-get prototype :valid))
                  (progn
                    (message "[strategy-evolution] REJECTED candidate: Prototype failed: %s"
                             (mapconcat #'identity (plist-get prototype :errors) ", "))
                    nil)

                ;; Check 3: Actually returns a non-empty string
                (let ((output (plist-get prototype :output)))
                  (if (or (not (stringp output))
                          (< (length output) 100))
                      (progn
                        (message "[strategy-evolution] REJECTED candidate: Output too short (%d chars)"
                                 (length output))
                        nil)

                    ;; Valid candidate
                    (push (list :code candidate-code
                               :name candidate-name
                               :proposer-name proposer-name
                               :output output
                               :output-length (length output))
                           valid-candidates)))))))))
    
    ;; Pick best candidate (longest output = most content, heuristic for completeness)
    (when valid-candidates
      (let* ((sorted (sort valid-candidates
                          (lambda (a b)
                            (> (plist-get a :output-length)
                               (plist-get b :output-length)))))
(best (car sorted))
              (best-code (plist-get best :code))
               ;; Use stored proposer-name from original candidate, reject if generic
               (proposer-name (plist-get best :proposer-name))
               (new-name (gptel-auto-workflow--generate-strategy-name proposer-name)))
         (if (not new-name)
             (progn
               (message "[strategy-evolution] REJECTED candidate: Proposed name '%s' is generic (must
be descriptive)"
                        (or proposer-name "nil"))
               nil)
           (let* ((final-code (gptel-auto-workflow--strategy-code-rewrite-name
                          best-code
                          (plist-get best :name)
                          new-name)))

        ;; Write strategy to filesystem
          (let ((strategy-file (expand-file-name
                              (format "strategy-%s.el" new-name)
                              (gptel-auto-workflow--strategies-directory))))
          (make-directory (file-name-directory strategy-file) t)
          (with-temp-file strategy-file
            (insert final-code))
          (let ((final-prototype
                 (gptel-auto-workflow--prototype-strategy
                  final-code
                  "lisp/modules/gptel-tools-agent-base.el")))
             (if (not (plist-get final-prototype :valid))
                 (progn
                   (delete-file strategy-file)
                   (message "[strategy-evolution] REJECTED %s: Final prototype failed: %s"
                            (format "%s" new-name)
                            (mapconcat #'identity (plist-get final-prototype :errors) ", "))
                   nil)
                (if (gptel-auto-workflow--load-strategy new-name)
                    (progn
                      (gptel-auto-workflow--record-strategy-axis axis)
                      (message "[strategy-evolution] ACCEPTED %s (axis %s) from %d candidates"
                               (format "%s" new-name)
                               (format "%s" axis)
                               (length valid-candidates))
                      ;; Queue for benchmarking — don't enter production unproven
                      (when (fboundp 'gptel-auto-workflow--queue-strategy-benchmark)
                        (gptel-auto-workflow--queue-strategy-benchmark new-name axis))
                      new-name)
                 (progn
                   (message "[strategy-evolution] REJECTED %s: Load failed after file write"
                            (format "%s" new-name))
                   nil)))))))))))))

;;; Periodic Strategy Evolution

(defun gptel-auto-workflow--maybe-evolve-strategy (_target)
  "Maybe evolve a new strategy for TARGET based on recent performance.
Called periodically from the experiment loop.
If current strategy is underperforming, tries to generate a new one.
When the active strategy is unevaluated, falls back to the worst evaluated
strategy as the parent for evolution."
  (when (and gptel-auto-workflow--strategy-evolution-enabled
             (fboundp 'gptel-auto-workflow--select-best-strategy))
    (let* ((current-strategy gptel-auto-workflow--active-strategy)
           (current-perf (gptel-auto-workflow--get-strategy-performance current-strategy))
           (_current-success-rate (plist-get current-perf :success-rate))
           (current-total (plist-get current-perf :total))
           ;; If active strategy is unevaluated, check evaluated strategies for evolution candidates
           (parent-strategy
            (if (>= current-total 5)
                current-strategy
              ;; Find the worst evaluated strategy to evolve from
              (let* ((all-strategies (gptel-auto-workflow--discover-strategies))
                     (evaluated
                      (cl-remove-if
                       (lambda (name)
                         (let ((p (gptel-auto-workflow--get-strategy-performance name)))
                           (or (< (plist-get p :total) 5)
                               (> (plist-get p :success-rate) 0.4))))
                       all-strategies))
                     (worst (car (last (sort evaluated
                                            (lambda (a b)
                                              (> (plist-get (gptel-auto-workflow--get-strategy-performance a) :success-rate)
                                                 (plist-get (gptel-auto-workflow--get-strategy-performance b) :success-rate))))))))
                (when worst
                   (message "[strategy] Active strategy %s is unevaluated, falling back to %s for evolution"
                            (format "%s" current-strategy)
                            (format "%s" worst)))
                worst)))
            (parent-perf (when parent-strategy
                           (gptel-auto-workflow--get-strategy-performance parent-strategy)))
            (parent-success-rate (plist-get parent-perf :success-rate))
            (parent-total (round (or (plist-get parent-perf :total) 0))))
      ;; Only evolve if we have enough data and performance is mediocre
      (when (and parent-strategy
                 (>= parent-total 5)
                 (<= parent-success-rate 0.4))
         (message "[strategy] Evolving from '%s' (%.0f%% success over %d experiments)"
                  (format "%s" parent-strategy) (* 100 parent-success-rate) parent-total)
        ;; Check for interruption before starting
        (if gptel-auto-workflow--strategy-interrupted
            (message "[strategy] Interrupted, skipping evolution")
          ;; Pick an exploitation axis that's been least explored
          (let* ((axis-perf (make-hash-table :test 'equal))
                 (all-axes '("A" "B" "C" "D" "E" "F")))
          ;; Count experiments per axis for current strategy
          (let ((eval-file (gptel-auto-workflow--strategy-results-file)))
            (when (file-exists-p eval-file)
              (with-temp-buffer
                (insert-file-contents eval-file)
                (goto-char (point-min))
                (while (not (eobp))
                  (let ((line (buffer-substring (line-beginning-position) (line-end-position))))
                    (when (not (string-empty-p line))
                      (condition-case nil
                          (let* ((entry (json-read-from-string line))
                                 (entry-strategy (cdr (assoc 'strategy entry)))
                                 (entry-axis (cdr (assoc 'axis entry))))
                             (when (and (equal entry-strategy parent-strategy)
                                       entry-axis)
                              (puthash entry-axis
                                       (1+ (gethash entry-axis axis-perf 0))
                                       axis-perf)))
                        (error nil)))
                    (forward-line 1))))))
          ;; Find least explored axis
          (let ((min-count most-positive-fixnum)
                (target-axis nil))
            (dolist (axis all-axes)
              (let ((count (gethash axis axis-perf 0)))
                (when (< count min-count)
                  (setq min-count count)
                  (setq target-axis axis))))
            ;; Evolve strategy (with interrupt protection)
            (let ((new-strategy
                   (condition-case _quit
                        (gptel-auto-workflow--evolve-strategy
                         parent-strategy
                        (format "Improve strategy by targeting axis %s (%s)"
                                target-axis
                                (gptel-auto-workflow--strategy-axis-description target-axis))
                        target-axis)
                     (quit
                      (setq gptel-auto-workflow--strategy-interrupted t)
                      (message "[strategy] Evolution interrupted by signal, got %.0f%% complete"
                               (* 100 (/ (float (length all-axes)) 6.0)))
                      nil))))
              (when (gptel-auto-workflow--valid-strategy-name-p new-strategy)
                 (message "[strategy] Evolved new strategy: %s" (format "%s" new-strategy))
                ;; Write evolution summary
                (let* ((perf (gptel-auto-workflow--get-strategy-performance new-strategy))
                       (val-scores (make-hash-table :test 'equal))
                       (candidates (list (list :name new-strategy
                                              :axis target-axis
                                              :hypothesis (format "Axis %s improvement" target-axis)
                                              :components (list (format "axis-%s" target-axis))))))
                  (puthash new-strategy (plist-get perf :avg-score) val-scores)
                  (gptel-auto-workflow--ensure-strategy-run-directories)
                  (gptel-auto-workflow--write-evolution-summary
                   (1+ (gethash parent-strategy val-scores 0))
                   candidates
                   val-scores
                   (list :propose 0.0 :bench 0.0 :wall 0.0)))
                 ;; Switch to new strategy if it passed validation
                  (setq gptel-auto-workflow--active-strategy new-strategy))))))))))

(provide 'gptel-tools-agent-strategy-evolver)
;;; gptel-tools-agent-strategy-evolver.el ends here
