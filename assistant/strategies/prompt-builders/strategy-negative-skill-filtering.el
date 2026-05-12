;;; strategy-negative-skill-filtering.el --- Exclude irrelevant skills -*- lexical-binding: t; -*-
;; Hypothesis: Excluding skills irrelevant to the target code reduces noise more effectively than including only relevant ones.
;; Axis: E
;;
(require 'gptel-tools-agent-prompt-build)

(defun strategy-negative-skill-filtering-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt excluding skills that don't apply to TARGET."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (excluded-skills (strategy-nsf--determine-excluded-skills target))
         (included-skills (cl-set-difference '("lisp-refactoring" "elisp-patterns" "debugging" "performance")
                                            excluded-skills :test #'equal)))
    (concat base-prompt
            "\n\n;; Applicable Skills Priority\n"
            (mapconcat (lambda (s) (format "- %s (HIGH PRIORITY)" s)) included-skills "\n")
            "\n\n;; Excluded Skill Categories\n"
            (mapconcat (lambda (s) (format "- %s (not applicable to this code)" s)) excluded-skills "\n"))))

(defun strategy-nsf--determine-excluded-skills (target)
  "Determine which skill categories to exclude based on TARGET code characteristics."
  (when (file-readable-p target)
    (with-temp-buffer
      (insert-file-contents target)
      (let ((content (buffer-string))
            (excluded nil))
        (goto-char (point-min))
        ;; Check what patterns are absent to exclude irrelevant skills
        (unless (re-search-forward (rx (or "defun" "defmacro" "lambda")) nil t)
          (push "lisp-refactoring" excluded))
        (unless (re-search-forward (rx (or "cl-loop" "dolist" "mapcar" "reduce")) nil t)
          (push "elisp-patterns" excluded))
        (unless (re-search-forward (rx (or "condition-case" "signal" "error" "debug")) nil t)
          (push "debugging" excluded))
        (unless (or (re-search-forward (rx (or "sort" "delete-dups" "length")) nil t)
                    (re-search-forward (rx (1+ (in " \t\n"))) nil t))
          (push "performance" excluded))
        excluded))))

(defun strategy-negative-skill-filtering-get-metadata ()
  (list :name "negative-skill-filtering"
        :version "1.0"
        :hypothesis "Excluding skills irrelevant to the target code reduces noise more effectively than including only relevant ones"
        :axis "E"
        :components ["negative-filtering" "skill-exclusion"]))

(provide 'strategy-negative-skill-filtering)