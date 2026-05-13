;;; strategy-skill-cascade-loading.el --- Cascaded skill loading based on failure types -*- lexical-binding: t; -*-
;; Hypothesis: Cascading skill loading from primary failures reveals related systemic issues.
;; Axis: E

(require 'gptel-tools-agent-prompt-build)

(defvar strategy-skill-cascade-loading--cascade-map
  '((naming . (naming-conventions refactoring))
    (structure . (modularity documentation))
    (documentation . (testing naming))
    (error-handling . (defcustom-patterns edge-cases))
    (performance . (optimization profiling))
    (default . (best-practices general-patterns)))
  "Map failure types to cascaded skills to load.")

(defun strategy-skill-cascade-loading-build-prompt
    (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with cascaded skill loading based on detected failure types."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (patterns (plist-get analysis :patterns))
         (failure-types (strategy-skill-cascade-loading--extract-types patterns))
         (cascade-skills (strategy-skill-cascade-loading--resolve-cascade failure-types))
         (cascade-content (mapconcat #'strategy-skill-cascade-loading--load-skill
                                     cascade-skills
                                     "\n\n---\n\n")))
    (if cascade-content
        (concat base-prompt
                (format "\n\n;; Cascaded Skill Context\n;; Based on detected failures (%s), exploring related skills:\n\n%s"
                        (mapconcat #'symbol-name failure-types ", ")
                        cascade-content))
      base-prompt)))

(defun strategy-skill-cascade-loading--extract-types (patterns)
  "Extract failure types from PATTERNS."
  (let ((types '()))
    (dolist (pat (if (listp patterns) patterns (list patterns)))
      (let ((type (plist-get pat :type)))
        (when type
          (cl-pushnew (if (symbolp type) type (intern type)) types))))
    (delete-dups types)))

(defun strategy-skill-cascade-loading--resolve-cascade (types)
  "Resolve cascade skills for TYPES, removing duplicates."
  (let ((resolved '()))
    (dolist (type types)
      (let ((cascade (or (cdr-safe (assoc type strategy-skill-cascade-loading--cascade-map))
                         (cdr-safe (assoc 'default strategy-skill-cascade-loading--cascade-map)))))
        (dolist (skill cascade)
          (cl-pushnew skill resolved))))
    (delete-dups resolved)))

(defun strategy-skill-cascade-loading--load-skill (skill-sym)
  "Load content for SKILL-SYM."
  (let* ((skill-name (symbol-name skill-sym))
         (worktree (gptel-auto-workflow--get-worktree-dir))
         (skill-file (expand-file-name (concat "skills/" skill-name ".md") worktree)))
    (when (file-exists-p skill-file)
      (format ";;; Skill: %s\n%s" skill-name
              (with-temp-buffer
                (insert-file-contents skill-file)
                (string-trim (buffer-string)))))))

(defun strategy-skill-cascade-loading-get-metadata ()
  (list :name "skill-cascade-loading"
        :version "1.0"
        :hypothesis "Cascading skill load from primary failures reveals related systemic issues"
        :axis "E"
        :components ["skill-cascade" "failure-typing"]))

(provide 'strategy-skill-cascade-loading)