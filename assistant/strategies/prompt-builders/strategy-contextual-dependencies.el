;;; strategy-contextual-dependencies.el --- Include required library signatures -*- lexical-binding: t; -*-
;; Hypothesis: Including signatures of functions from `require'd libraries helps the AI understand available utilities and their interfaces, improving code modifications.
;; Axis: B
;;
;; IMPORTANT: Use a MEANINGFUL name replacing NAME (e.g., strategy-weighted-skills,
;; strategy-outcome-reasoning, not strategy-evolved-0006).
;; The name should describe the core mechanism in 2-4 hyphenated words.

(require 'gptel-tools-agent-prompt-build)

(defun strategy-contextual-dependencies-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt for TARGET, adding signatures from required libraries.
EXPERIMENT-ID: current experiment number.
MAX-EXPERIMENTS: total experiments planned.
ANALYSIS: plist with :patterns :recommendations from previous experiments.
BASELINE: current baseline score.
PREVIOUS-RESULTS: list of previous experiment plists."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (library-signatures (strategy-contextual-dependencies--get-library-signatures target))
         (signatures-section (if library-signatures
                                 (concat "\n\n;; Contextual Library Signatures:\n"
                                         (mapconcat #'identity library-signatures "\n"))
                               "")))
    (concat base-prompt signatures-section)))

(defun strategy-contextual-dependencies--get-library-signatures (target)
  "Extract function signatures from libraries required by TARGET.
Returns a list of strings (signatures). Skips any libraries that cannot be located."
  (let (signatures)
    (condition-case nil
        (with-temp-buffer
          (insert-file-contents target)
          (goto-char (point-min))
          (while (re-search-forward "(require[ \t\n]+\\(?:'\\)?\\([^)]+\\)" nil t)
            (let ((lib-name (match-string 1)))
              ;; Remove quoting and whitespace
              (setq lib-name (replace-regexp-in-string "['()\" \t\n]" "" lib-name))
              (when (stringp lib-name)
                (let ((lib-file (locate-library lib-name)))
                  (when lib-file
                    (condition-case nil
                        (with-temp-buffer
                          (insert-file-contents lib-file)
                          (goto-char (point-min))
                          (while (re-search-forward "^(defun \\(\\S-+\\)" nil t)
                            (let ((fun-name (match-string 1))
                                  (fun-line (buffer-substring-no-properties
                                             (line-beginning-position)
                                             (line-end-position))))
                              (push (concat ";; " fun-name ":" (string-trim fun-line)) signatures))))
                      (error nil))))))))
      (error nil))
    (nreverse signatures)))

(defun strategy-contextual-dependencies-get-metadata ()
  "Return metadata for this strategy."
  (list :name "contextual-dependencies"
        :version "1.0"
        :hypothesis "Including signatures of functions from required libraries helps the AI understand available utilities"
        :axis "B"
        :components ["context" "libraries" "signatures"]))

(provide 'strategy-contextual-dependencies)