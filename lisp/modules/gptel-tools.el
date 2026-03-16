;;; gptel-tools.el --- Tool registry for gptel -*- no-byte-compile: t; lexical-binding: t; -*-

;; Author: David Wu
;; Version: 1.1.0
;;
;; Main tool registry that loads and registers all gptel tools.

(require 'cl-lib)
(require 'subr-x)
(require 'seq)

;;; Hooks

(defvar gptel-tools-after-register-hook nil
  "Hook run after `gptel-tools-register-all' completes.
Use this to refresh presets or update buffers that depend on tool availability.")

;; Load individual tool modules
(require 'gptel-tools-bash)
(require 'gptel-tools-grep)
(require 'gptel-tools-glob)
(require 'gptel-tools-edit)
(require 'gptel-tools-apply)
(require 'gptel-tools-agent)
(require 'gptel-tools-preview)
(require 'gptel-tools-programmatic)
;; (require 'gptel-tools-lsp)  ; Deprecated, functionality merged into gptel-tools-code
(require 'gptel-tools-introspection)
;; (require 'gptel-tools-ast)  ; Deprecated, functionality merged into gptel-tools-code
(require 'gptel-tools-code)

;;; Customization

(defgroup gptel-tools nil
  "Tool registry and management for gptel-agent."
  :group 'gptel)

(defun gptel-tools-register-all ()
  "Register all gptel tools.

Call this after gptel-agent-tools loads."
  ;; Register individual tool modules
  (gptel-tools-bash-register)
  (gptel-tools-grep-register)
  (gptel-tools-glob-register)
  (gptel-tools-edit-register)
  (gptel-tools-apply-register)
  (gptel-tools-agent-register)
  (gptel-tools-preview-register)
  (gptel-tools-programmatic-register)
  ;; (gptel-tools-lsp-register)  ; Deprecated by gptel-tools-code
  (gptel-tools-introspection-register)
  ;; (gptel-tools-ast-register)  ; Deprecated by gptel-tools-code
  (gptel-tools-code-register)

  ;; Register nucleus-specific tools (not in gptel-agent-tools)
  (when (fboundp 'gptel-make-tool)
    ;; Move tool - not in gptel-agent-tools
    (gptel-make-tool
     :name "Move"
     :function (lambda (source dest)
                 (let ((src (expand-file-name source))
                       (dst (expand-file-name dest)))
                   (if (not (file-exists-p src))
                       (error "Source file does not exist: %s" src)
                     (rename-file src dst t)
                     (format "Moved %s to %s" src dst))))
     :description "Move or rename a file safely."
     :args '((:name "source" :type string :description "Source file path")
             (:name "dest" :type string :description "Destination file path"))
     :category "gptel-agent"
     :confirm t
     :include t)

    ;; Skill tool - nucleus extension, not in gptel-agent-tools
    (gptel-make-tool
     :name "Skill"
     :function #'my/gptel--skill-tool
     :description "Load a skill by name."
     :args '((:name "skill" :type string)
             (:name "args" :type string :optional t))
     :category "gptel-agent"
     :include t)

    ;; Skill management tools - nucleus extensions
    (gptel-make-tool
     :name "list_skills"
     :function (lambda (&optional dir)
                 (let* ((dir (or dir (expand-file-name "assistant/skills/" user-emacs-directory)))
                        (skills (when (file-directory-p dir)
                                  (seq-filter (lambda (d) (file-directory-p (expand-file-name d dir)))
                                              (directory-files dir)))))
                   (if skills
                       (format "Available skills:\n%s" (string-join (sort skills 'string-lessp) "\n"))
                     "No skills found.")))
     :description "List available skills in the skills directory."
     :args '((:name "dir" :type string :optional t))
     :category "gptel-agent")
    (gptel-make-tool
     :name "load_skill"
     :function #'my/gptel--skill-tool
     :description "Load a skill by name (alias for Skill tool)."
     :args '((:name "name" :type string)
             (:name "dir" :type string :optional t))
     :category "gptel-agent")
    (gptel-make-tool
     :name "create_skill"
     :function (lambda (skill-name user-prompt &optional dir)
                 (let* ((dir (or dir (expand-file-name "assistant/skills/" user-emacs-directory)))
                        (skill-dir (expand-file-name skill-name dir)))
                   (unless (file-directory-p dir)
                     (make-directory dir t))
                   (unless (file-directory-p skill-dir)
                     (make-directory skill-dir t))
                   (with-temp-file (expand-file-name "SKILL.md" skill-dir)
                     (insert (format "# Skill: %s\n\n%s\n" skill-name user-prompt)))
                   (format "Created skill: %s" skill-dir)))
     :description "Create a new skill with the given name and prompt."
     :args '((:name "skillName" :type string)
             (:name "userPrompt" :type string)
             (:name "dir" :type string :optional t))
     :category "gptel-agent"
     :confirm t))

  ;; Default toolset is set by nucleus-sync-tool-profile in gptel-mode-hook.
  ;; Use (nucleus-get-tools :readonly) or (nucleus-get-tools :nucleus) directly.
  )

;;; Utility Functions

(defun my/gptel--skill-tool (skill &optional args)
  "Wrapper for gptel-agent Skill tool."
  (let* ((skill (string-trim skill))
         (try (lambda (k)
                (car-safe (alist-get k gptel-agent--skills nil nil #'string-equal))))
         (hit (or (funcall try skill) (funcall try (downcase skill)))))
    (when (and (not hit) (fboundp 'gptel-agent-update))
      (ignore-errors (gptel-agent-update))
      (setq hit (or (funcall try skill) (funcall try (downcase skill)))))
    (if (not hit)
        (format "Error: skill %s not found." (if (string-empty-p skill) "<empty>" skill))
      (gptel-agent--get-skill (if (funcall try skill) skill (downcase skill)) args))))

;;; Integration

(defun gptel-tools-setup ()
  "Setup gptel tools.

Call this after gptel-agent-tools loads.
Runs `gptel-tools-after-register-hook' after registration."
  (gptel-tools-register-all)
  (run-hooks 'gptel-tools-after-register-hook))

;;; Footer

(provide 'gptel-tools)

;;; Auto-initialization

(with-eval-after-load 'gptel-agent-tools
  (gptel-tools-setup))

;;; gptel-tools.el ends here
