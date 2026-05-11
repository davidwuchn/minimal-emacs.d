;;; strategy-skill-dependency-graph.el --- Load skills based on dependency analysis -*- lexical-binding: t; -*-
;; Hypothesis: Loading skills dynamically based on import/require analysis improves relevance.
;; Axis: E (Skill loading)
;;
(require 'gptel-tools-agent-prompt-build)

(defun strategy-skill-dependency-graph-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with dependency-analyzed skill loading."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         ;; Detect file type from target
         (file-type (cond ((string-match-p "\\.el$" target) "emacs-lisp")
                          ((string-match-p "\\.py$" target) "python")
                          ((string-match-p "\\.js$" target) "javascript")
                          (t "generic")))
         ;; Analyze imports/requires to determine needed skills
         (deps (when (file-exists-p target)
                 (with-temp-buffer
                   (insert-file-contents target)
                   (let ((imports nil))
                     (goto-char (point-min))
                     ;; Detect requires/imports based on file type
                     (cond ((string-match-p "emacs-lisp" file-type)
                            (while (re-search-forward "(require '\\([a-z0-9-]+\\)" nil t)
                              (push (match-string 1) imports)))
                           ((string-match-p "python" file-type)
                            (while (re-search-forward "^import \\([a-z_]+\\)" nil t)
                              (push (match-string 1) imports))
                            (while (re-search-forward "^from \\([a-z_.]+\\) import" nil t)
                              (push (match-string 1) imports)))
                           ((string-match-p "javascript" file-type)
                            (while (re-search-forward "require(['\"]\\([a-z@/]+\\)['\"])" nil t)
                              (push (match-string 1) imports))
                            (while (re-search-forward "import .* from ['\"]\\([a-z@/]+\\)['\"]" nil t)
                              (push (match-string 1) imports))))
                     imports))))
         ;; Map dependencies to relevant skills
         (needed-skills (cl-loop for dep in deps
                                 when (or (string-match-p "test" dep)
                                          (string-match-p "spec" dep))
                                 collect "testing"
                                 when (or (string-match-p "async" dep)
                                          (string-match-p "promise" dep))
                                 collect "concurrency"
                                 when (or (string-match-p "db" dep)
                                          (string-match-p "sql" dep)
                                          (string-match-p "data" dep))
                                 collect "database"
                                 when (string-match-p "log" dep)
                                 collect "logging"
                                 when (string-match-p "auth" dep)
                                 collect "security"))
         (unique-skills (delete-dups needed-skills)))
    ;; Load only needed skills
    (if unique-skills
        (concat base-prompt "\n\n;; Skills loaded via dependency analysis: "
                (mapconcat #'identity unique-skills ", "))
      base-prompt)))

(defun strategy-skill-dependency-graph-get-metadata ()
  (list :name "skill-dependency-graph"
        :version "1.0"
        :hypothesis "Loading skills dynamically based on import/require analysis improves relevance."
        :axis "E"
        :components ["skill-loading" "dependency-analysis"]))

(provide 'strategy-skill-dependency-graph)