;;; strategy-failure-pattern-skill-routing.el --- Route to relevant skills based on failure patterns -*- lexical-binding: t; -*-
;; Hypothesis: Matching skills to failure patterns instead of loading all skills improves guidance precision.
;; Axis: E

(require 'gptel-tools-agent-prompt-build)
(require 'cl-lib)

(defun strategy-failure-pattern-skill-routing--extract-failure-keywords (patterns)
  "Extract keywords from failure PATTERNS to match with skills."
  (let* ((all-patterns (cl-loop for p in patterns
                                append (append (plist-get p :patterns) nil)))
         (keywords (cl-loop for pat in all-patterns
                            append (mapcar #'downcase
                                          (split-string (format "%s" pat) "\\s-+" t)))))
    (delete-dups (cl-remove-if (lambda (w) (< (length w) 4)) keywords))))

(defun strategy-failure-pattern-skill-routing--compute-skill-relevance (skill-name skill-content keywords)
  "Compute relevance score between SKILL-CONTENT and KEYWORDS."
  (let* ((content-lower (downcase skill-content))
         (score (cl-reduce #'+ (mapcar (lambda (kw)
                                         (if (string-match-p kw content-lower) 1 0))
                                       keywords))))
    (cons skill-name score)))

(defun strategy-failure-pattern-skill-routing--load-top-skills (target patterns skill-dir n)
  "Load top N most relevant skills based on failure PATTERNS."
  (let* ((keywords (strategy-failure-pattern-skill-routing--extract-failure-keywords patterns))
         (skill-files (directory-files skill-dir t "\\.el$" t))
         (relevance-scores (mapcar (lambda (f)
                                     (let* ((name (file-name-base f))
                                            (content (with-temp-buffer
                                                       (insert-file-contents f)
                                                       (buffer-string))))
                                       (strategy-failure-pattern-skill-routing--compute-skill-relevance
                                        name content keywords)))
                                   skill-files))
         (sorted (cl-sort relevance-scores #'> :key #'cdr))
         (top-n (cl-subseq sorted 0 (min n (length sorted)))))
    (mapcar #'car top-n)))

(defun strategy-failure-pattern-skill-routing--format-routed-skills (target patterns)
  "Load and format skills routed by failure pattern relevance."
  (let* ((worktree (gptel-auto-workflow--get-worktree-dir))
         (skill-dir (expand-file-name "skills" worktree))
         (top-skills (if (file-directory-p skill-dir)
                         (strategy-failure-pattern-skill-routing--load-top-skills target patterns skill-dir 3)
                       (list "general" "refactoring" "testing")))
         (skill-contents (mapcar (lambda (s) (gptel-auto-workflow--load-skill-content s)) top-skills)))
    (when (cl-some (lambda (c) (and c (not (string= c "")))) skill-contents)
      (concat "\n\n;; === ROUTED SKILL GUIDANCE (by failure pattern match) ===\n"
              (mapconcat (lambda (pair)
                           (format ";; Skill: %s\n%s"
                                   (car pair)
                                   (or (cdr pair) "")))
                         (cl-remove-if-not #'cdr (mapcar #'cons top-skills skill-contents))
                         "\n\n")))))

(defun strategy-failure-pattern-skill-routing-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with failure-pattern routed skill loading."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (patterns (plist-get analysis :patterns))
         (routed-skills (if patterns
                            (strategy-failure-pattern-skill-routing--format-routed-skills target patterns)
                          "")))
    (concat base-prompt routed-skills)))

(defun strategy-failure-pattern-skill-routing-get-metadata ()
  (list :name "failure-pattern-skill-routing"
        :version "1.0"
        :hypothesis "Matching skills to failure patterns instead of loading all skills improves guidance precision."
        :axis "E"
        :components ["skill-routing" "failure-matching"]))

(provide 'strategy-failure-pattern-skill-routing)