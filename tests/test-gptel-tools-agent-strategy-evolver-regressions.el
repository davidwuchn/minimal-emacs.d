;;; test-gptel-tools-agent-strategy-evolver-regressions.el --- Strategy evolver regressions -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)

(load-file (expand-file-name "../lisp/modules/gptel-tools-agent-strategy-evolver.el"
                              (file-name-directory
                               (or load-file-name buffer-file-name default-directory))))

(ert-deftest regression/strategy-evolver/prototype-rejects-missing-dynamic-skills ()
  "Prototype validation should reject strategies that route to non-existent skills."
  (let ((strategy-code
         ";;; strategy-pattern-driven-skills.el --- Pattern-matched skill loading -*- lexical-binding: t; -*-

(require 'gptel-tools-agent-prompt-build)

(defun strategy-pattern-driven-skills-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  (let* ((base-prompt \"base prompt long enough to pass minimum output checks and show fallback behavior\")
         (patterns (plist-get analysis :patterns))
         (matched-skills \"\"))
    (when patterns
      (let* ((anti-patterns '(\"memory-leak\" \"null-check\"))
             (pattern-skills-alist '((\"memory-leak\" . \"memory-management\")
                                     (\"null-check\" . \"null-safety\")))
             (detected-patterns (seq-filter
                                 (lambda (p) (member (plist-get p :type) anti-patterns))
                                 patterns))
             (skills-to-load (mapcar
                              (lambda (p) (cdr (assoc (plist-get p :type) pattern-skills-alist)))
                              detected-patterns)))
        (setq matched-skills
              (mapconcat (lambda (skill)
                           (or (gptel-auto-workflow--load-skill-content skill) \"\"))
                         skills-to-load \"\\n\"))))
    (concat base-prompt matched-skills)))

(provide 'strategy-pattern-driven-skills)
"))
    (cl-letf (((symbol-function 'gptel-auto-workflow--find-skill-file)
               (lambda (_skill-name) nil))
              ((symbol-function 'gptel-auto-workflow--project-root)
               (lambda () temporary-file-directory))
              ((symbol-function 'gptel-auto-workflow--load-skill-content)
               (lambda (_skill-name) "")))
      (let ((result (gptel-auto-workflow--prototype-strategy
                     strategy-code
                     "lisp/modules/gptel-tools-agent-base.el")))
        (should-not (plist-get result :valid))
        (should (string-match-p "Missing referenced skills"
                                (mapconcat #'identity (plist-get result :errors) "\n")))))))

(ert-deftest regression/strategy-evolver/extracts-literal-skill-loads ()
  "Static skill reference extraction should capture literal skill names."
  (should (equal (gptel-auto-workflow--extract-loaded-skill-names
                  "(gptel-auto-workflow--load-skill-content \"elisp-expert\")")
                 '("elisp-expert"))))

(provide 'test-gptel-tools-agent-strategy-evolver-regressions)

;;; test-gptel-tools-agent-strategy-evolver-regressions.el ends here
