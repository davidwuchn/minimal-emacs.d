;;; strategy-file-role-skill-loading.el --- Load skills based on file role -*- lexical-binding: t; -*-
;; Hypothesis: Loading role-specific skill subsets based on file type (test vs source vs config) improves targeted code improvements.
;; Axis: E (Skill loading)

(require 'gptel-tools-agent-prompt-build)

(defun strategy-file-role-skill-loading-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt for TARGET using role-based skill loading."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (filename (file-name-nondirectory target))
         (file-ext (file-name-extension target))
         (role (cond
                ((string-match-p "\\btest\\b" filename) "testing")
                ((string-match-p "\\btest\\b" filename) "testing")
                ((string-match-p "-test\\'" filename) "testing")
                ((string-match-p "\\`_test\\'" filename) "testing")
                ((string-match-p "\\`_tests?\\'" filename) "testing")
                ((string-match-p "/tests?/" filename) "testing")
                ((member file-ext '("el" "clj" "cl" "lisp")) "lisp-source")
                ((member file-ext '("yaml" "yml" "toml" "json")) "configuration")
                (t "general")))
         (role-guidance (pcase role
                          ("testing"
                           "\n\n;; Role-Specific Loading: TESTING\n;; Load skills: test-patterns, mocking-strategies, assertion-patterns")
                          ("lisp-source"
                           "\n\n;; Role-Specific Loading: LISP SOURCE\n;; Load skills: emacs-lisp-idioms, common-lisp-compat, macro-patterns")
                          ("configuration"
                           "\n\n;; Role-Specific Loading: CONFIGURATION\n;; Load skills: config-validation, schema-patterns, migration-patterns")
                          (_
                           "\n\n;; Role-Specific Loading: GENERAL\n;; Load skills: general-refactoring, documentation-standards")))
         (skills-loaded (gptel-auto-workflow--load-skill-content
                         (pcase role
                           ("testing" '("test-patterns" "mocking-strategies"))
                           ("lisp-source" '("emacs-lisp-idioms"))
                           (_ '("general-refactoring"))))))
    (concat base-prompt role-guidance "\n;; Loaded skills: " (mapconcat 'identity skills-loaded ", "))))

(defun strategy-file-role-skill-loading-get-metadata ()
  (list :name "file-role-skill-loading"
        :version "1.0"
        :hypothesis "Loading role-specific skill subsets based on file type (test vs source vs config) improves targeted code improvements."
        :axis "E"
        :components ["file-role" "role-based-skills"]))

(provide 'strategy-file-role-skill-loading)