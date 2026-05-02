;;; gptel-tools-agent-strategy-evolver.el --- Meta-Harness style strategy evolution -*- lexical-binding: t; -*-
;; Part of gptel-tools-agent split
;;
;; This module implements the Meta-Harness outer loop for evolving prompt-building strategies.
;; It generates new strategy files, validates them, and tracks their performance.
;;
;; Key principle: We evolve the HARNESS (how prompts are built), not just the prompt content.

;;; Strategy Generation

(defvar gptel-auto-workflow--strategy-evolution-axes
  '((A . "Prompt template architecture")
    (B . "Context retrieval and selection")
    (C . "Section ordering and inclusion")
    (D . "Variable computation and formatting")
    (E . "Skill loading and integration")
    (F . "Adaptive compression and filtering"))
  "Exploration axes for strategy evolution, analogous to Meta-Harness exploitation axes.")

(defvar gptel-auto-workflow--strategy-generation-count 0
  "Counter for generated strategy names.")

(defun gptel-auto-workflow--generate-strategy-name ()
  "Generate a unique strategy name."
  (setq gptel-auto-workflow--strategy-generation-count
        (1+ gptel-auto-workflow--strategy-generation-count))
  (format "evolved-%04d" gptel-auto-workflow--strategy-generation-count))

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
  "Build prompt using evolved strategy %s.
HYPOTHESIS: %s"
  %s)

(defun strategy-%s-get-metadata ()
  "Return metadata for this strategy."
  (list :name "%s"
        :version "1.0"
        :hypothesis "%s"
        :axis "%s"
        :created "%s"
        :parent-strategies '%s
        :description "%s"))

;; Register self
(when (fboundp 'gptel-auto-workflow--register-strategy)
  (gptel-auto-workflow--register-strategy
   "%s"
   #'strategy-%s-build-prompt
   (strategy-%s-get-metadata)))

(provide 'strategy-%s)
;;; strategy-%s.el ends here"
          name
          hypothesis
          axis
          (cdr (assoc axis gptel-auto-workflow--strategy-evolution-axes))
          (prin1-to-string parent-strategies)
          (format-time-string "%Y-%m-%d")
          name
          name
          hypothesis
          code
          name
          name
          hypothesis
          axis
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

(defun gptel-auto-workflow--extract-function-names (code)
  "Extract defined function names from CODE."
  (let (names)
    (with-temp-buffer
      (insert code)
      (goto-char (point-min))
      (while (re-search-forward "(defun\\s-+\\([^ ]+\\)" nil t)
        (push (match-string 1) names)))
    (sort names #'string<)))

(defun gptel-auto-workflow--extract-control-flow (code)
  "Extract control flow structure from CODE (if/cond/while/etc)."
  (let (structures)
    (with-temp-buffer
      (insert code)
      (goto-char (point-min))
      (while (re-search-forward "(\\(if\\|cond\\|when\\|unless\\|while\\|dolist\\|dotimes\\|cl-loop\\)" nil t)
        (push (match-string 1) structures)))
    (sort structures #'string<)))

(defun gptel-auto-workflow--extract-constants (code)
  "Extract string and number constants from CODE."
  (let (constants)
    (with-temp-buffer
      (insert code)
      (goto-char (point-min))
      ;; Extract strings
      (while (re-search-forward "\"[^\"]*\"" nil t)
        (push (match-string 0) constants))
      ;; Extract numbers
      (goto-char (point-min))
      (while (re-search-forward "\\b[0-9]+\\b" nil t)
        (push (match-string 0) constants)))
    (sort constants #'string<)))

;;; Prototyping Phase

(defun gptel-auto-workflow--prototype-strategy (strategy-code test-target)
  "Prototype STRATEGY-CODE against TEST-TARGET before finalizing.
Returns plist with :valid t/nil :errors list :test-output string."
  (let ((temp-file (make-temp-file "strategy-prototype-"))
        (errors '())
        (test-output ""))
    (unwind-protect
        (progn
          ;; Write strategy to temp file
          (with-temp-file temp-file
            (insert strategy-code))
          
          ;; Test 1: Load without errors
          (condition-case err
              (load temp-file nil t t)
            (error
             (push (format "Load error: %s" err) errors)))
          
          ;; Test 2: Build function exists and is callable
          (unless errors
            (condition-case err
                (let* ((build-fn-name (gptel-auto-workflow--extract-build-function-name strategy-code))
                       (build-fn (intern build-fn-name)))
                  (if (fboundp build-fn)
                      (setq test-output
                            (funcall build-fn test-target 1 10 nil 0.5 nil))
                    (push "Build function not found after loading" errors)))
              (error
               (push (format "Build error: %s" err) errors))))
          
          ;; Test 3: Output is a string
          (when (and (not errors) (not (stringp test-output)))
            (push (format "Build function returned %s instead of string" (type-of test-output)) errors))
          
          (list :valid (null errors)
                :errors (nreverse errors)
                :output test-output))
      (when (file-exists-p temp-file)
        (delete-file temp-file)))))

(defun gptel-auto-workflow--extract-build-function-name (code)
  "Extract the build function name from strategy CODE."
  (with-temp-buffer
    (insert code)
    (goto-char (point-min))
    (if (re-search-forward "(defun\\s-+(strategy-[^ ]+-build-prompt)" nil t)
        (match-string 1)
      "strategy-unknown-build-prompt")))

;;; Strategy Evolution Loop

(defun gptel-auto-workflow--evolve-strategy (parent-strategy-name hypothesis axis)
  "Evolve a new strategy from PARENT-STRATEGY-NAME.
HYPOTHESIS describes the mechanism change.
AXIS is the exploitation axis (A-F).
Returns new strategy name or nil if rejected."
  (let* ((parent-file (expand-file-name
                       (format "strategy-%s.el" parent-strategy-name)
                       (gptel-auto-workflow--strategies-directory)))
         (parent-code (when (file-exists-p parent-file)
                        (with-temp-buffer
                          (insert-file-contents parent-file)
                          (buffer-string))))
         (new-name (gptel-auto-workflow--generate-strategy-name))
         ;; Generate new strategy code (in real Meta-Harness, this would be done by proposer agent)
         (new-code (gptel-auto-workflow--strategy-template
                    new-name
                    hypothesis
                    axis
                    (list parent-strategy-name)
                    ";; TODO: Implement evolved mechanism here
;; This should change a fundamental aspect of prompt building
;; Example: Different section ordering, new context selection, etc.
(gptel-auto-experiment-build-prompt target experiment-id max-experiments analysis baseline previous-results)")))
    
    ;; Self-critique: Is this a parameter variant?
    (when (and parent-code
               (gptel-auto-workflow--is-parameter-variant-p new-code parent-code))
      (message "[strategy-evolution] REJECTED %s: Parameter variant of %s" new-name parent-strategy-name)
      (return-from gptel-auto-workflow--evolve-strategy nil))
    
    ;; Prototype validation
    (let ((prototype (gptel-auto-workflow--prototype-strategy
                      new-code
                      "lisp/modules/gptel-tools-agent-base.el")))
      (unless (plist-get prototype :valid)
        (message "[strategy-evolution] REJECTED %s: Prototype failed: %s"
                 new-name
                 (mapconcat #'identity (plist-get prototype :errors) ", "))
        (return-from gptel-auto-workflow--evolve-strategy nil)))
    
    ;; Write strategy to filesystem
    (let ((strategy-file (expand-file-name
                          (format "strategy-%s.el" new-name)
                          (gptel-auto-workflow--strategies-directory))))
      (make-directory (file-name-directory strategy-file) t)
      (with-temp-file strategy-file
        (insert new-code))
      (message "[strategy-evolution] ACCEPTED %s (axis %s)" new-name axis)
      new-name)))

;;; Periodic Strategy Evolution

(defun gptel-auto-workflow--maybe-evolve-strategy (target)
  "Maybe evolve a new strategy for TARGET based on recent performance.
Called periodically from the experiment loop.
If current strategy is underperforming, tries to generate a new one."
  (when (and gptel-auto-workflow--strategy-evolution-enabled
             (fboundp 'gptel-auto-workflow--select-best-strategy))
    (let* ((current-strategy gptel-auto-workflow--active-strategy)
           (current-perf (gptel-auto-workflow--get-strategy-performance current-strategy))
           (current-success-rate (plist-get current-perf :success-rate))
           (current-total (plist-get current-perf :total)))
      ;; Only evolve if we have enough data and performance is mediocre
      (when (and (>= current-total 5)  ; At least 5 experiments
                 (<= current-success-rate 0.4))  ; 40% or less success
        (message "[strategy] Current strategy '%s' has %.0f%% success rate, triggering evolution"
                 current-strategy (* 100 current-success-rate))
        ;; Pick an exploitation axis that's been least explored
        (let* ((axis-perf (make-hash-table :test 'equal))
               (all-axes '("A" "B" "C" "D" "E" "F")))
          ;; Count experiments per axis for current strategy
          (let ((eval-file (expand-file-name gptel-auto-workflow--strategy-evaluations-file
                                            (gptel-auto-workflow--project-root))))
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
                            (when (and (equal entry-strategy current-strategy)
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
            ;; Evolve strategy
            (let ((new-strategy
                   (gptel-auto-workflow--evolve-strategy
                    current-strategy
                    (format "Improve strategy by targeting axis %s (%s)"
                            target-axis
                            (cdr (assoc target-axis gptel-auto-workflow--strategy-evolution-axes)))
                    target-axis)))
              (when new-strategy
                (message "[strategy] Evolved new strategy: %s" new-strategy)
                ;; Switch to new strategy if it passed validation
                (setq gptel-auto-workflow--active-strategy new-strategy))))))))

(provide 'gptel-tools-agent-strategy-evolver)
;;; gptel-tools-agent-strategy-evolver.el ends here