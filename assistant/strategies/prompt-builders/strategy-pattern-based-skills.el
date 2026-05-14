;;; strategy-pattern-based-skills.el --- Dynamic skill selection -*- lexical-binding: t; -*-
;; Hypothesis: Dynamically selecting skills based on detected code patterns improves relevance.
;; Axis: E

(require 'gptel-tools-agent-prompt-build)

(defun strategy-pattern-based-skills-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with pattern-based dynamic skill selection."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (file-content (when (file-exists-p target)
                         (with-temp-buffer
                           (insert-file-contents target)
                           (buffer-string))))
         (detected-patterns (when file-content
                              (gptel-auto-workflow--detect-code-patterns file-content)))
         (selected-skills (when detected-patterns
                            (gptel-auto-workflow--select-skills-by-patterns detected-patterns)))
         (skills-section (if selected-skills
                             (concat "\n\n;; Pattern-Detected Skills\n"
                                     (mapconcat 'identity selected-skills "\n"))
                           "")))
    (concat base-prompt skills-section)))

(defun gptel-auto-workflow--detect-code-patterns (content)
  "Detect code patterns in CONTENT. Returns list of pattern keywords."
  (let ((patterns nil))
    (when (string-match-p "cl-\\|defmacro\\|macroexpand" content)
      (push "macros" patterns))
    (when (string-match-p "lambda\\|closure\\|lexical" content)
      (push "functional" patterns))
    (when (string-match-p "thread-first\\|thread-last\\|-->\\|\\.\\.>" content)
      (push "threading" patterns))
    (when (string-match-p "condition-case\\|signal\\|error\\|debugger" content)
      (push "error-handling" patterns))
    (when (string-match-p "mapcar\\|mapc\\|mapconcat\\|seq-" content)
      (push "iteration" patterns))
    (when (string-match-p "defstruct\\|cl-defstruct\\|make-" content)
      (push "data-structures" patterns))
    (when (string-match-p "advice\\|add-hook\\|run-hook" content)
      (push "hooks" patterns))
    (when (string-match-p "plist-get\\|alist-get\\|hash-table" content)
      (push "lookup-tables" patterns))
    patterns))

(defun gptel-auto-workflow--select-skills-by-patterns (patterns)
  "Select skill names based on PATTERNS list."
  (mapcar (lambda (p)
            (cond ((string= p "macros") "-elisp/macros")
                  ((string= p "functional") "-elisp/functional")
                  ((string= p "threading") "-elisp/threading")
                  ((string= p "error-handling") "-elisp/errors")
                  ((string= p "iteration") "-elisp/iteration")
                  ((string= p "data-structures") "-elisp/structs")
                  ((string= p "hooks") "-elisp/hooks")
                  ((string= p "lookup-tables") "-elisp/lookup")
                  (t (format "-elisp/%s" p))))
          patterns))

(defun strategy-pattern-based-skills-get-metadata ()
  (list :name "pattern-based-skills"
        :version "1.0"
        :hypothesis "Dynamically selecting skills based on detected code patterns improves skill relevance."
        :axis "E"
        :components ["pattern-detection" "dynamic-skills"]))

(provide 'strategy-pattern-based-skills)