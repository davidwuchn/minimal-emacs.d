;;; gptel-tools.el --- Tool registry for gptel -*- lexical-binding: t; -*-

;; Author: David Wu
;; Version: 1.0.0
;;
;; Main tool registry that loads and registers all gptel tools.

(require 'cl-lib)
(require 'subr-x)
(require 'seq)

;; Load individual tool modules
(require 'gptel-tools-bash)
(require 'gptel-tools-grep)
(require 'gptel-tools-glob)
(require 'gptel-tools-edit)
(require 'gptel-tools-apply)
(require 'gptel-tools-agent)
(require 'gptel-tools-preview)
(require 'gptel-tools-lsp)
(require 'gptel-tools-introspection)
(require 'gptel-tools-ast)

;;; Customization

(defgroup gptel-tools nil
  "Tool registry and management for gptel-agent."
  :group 'gptel)

(defvar my/gptel-tools-readonly nil
  "Read-only toolset (populated after registration).")

(defvar my/gptel-tools-action nil
  "Action toolset (populated after registration).")

;;; Tool Registration

(defun my/gptel--safe-get-tool (name)
  "Return tool NAME from gptel registry, or nil if missing."
  (condition-case nil
      (gptel-get-tool name)
    (error nil)))

(defun my/gptel--dedup-tools-by-name (tools)
  "Return TOOLS with duplicates by tool name removed (last wins)."
  (let ((seen (make-hash-table :test #'equal)))
    (nreverse
     (cl-loop for tool in (nreverse (copy-sequence tools))
              for name = (ignore-errors (gptel-tool-name tool))
              when (and name (not (gethash name seen)))
              do (puthash name t seen)
              and collect tool))))

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
  (gptel-tools-lsp-register)
  (gptel-tools-introspection-register)
  (gptel-tools-ast-register)

  ;; Register standard gptel-agent tools
  (when (fboundp 'gptel-make-tool)
    ;; Write tool
    (gptel-make-tool
     :name "Write"
     :category "gptel-agent"
     :function (lambda (path filename content)
                 "Create a new file safely. Refuses to overwrite existing files."
                 (let ((filepath (expand-file-name filename path)))
                   (if (file-exists-p filepath)
                       (error "File already exists: %s. Use Edit or Insert instead." filepath)
                     (with-temp-file filepath (insert content)))
                   (format "Created new file: %s" filepath)))
     :description "Create a new file with the specified content. SAFETY: refuses to overwrite existing files."
     :args '((:name "path" :type string :description "Directory path")
             (:name "filename" :type string :description "File name")
             (:name "content" :type string :description "Content"))
     :confirm t
     :include t)

    ;; Read tool
    (gptel-make-tool
     :name "Read"
     :function #'gptel-agent--read-file-lines
     :description "Read file contents by line range."
     :args '((:name "file_path" :type string)
             (:name "start_line" :type integer :optional t)
             (:name "end_line" :type integer :optional t))
     :category "gptel-agent"
     :include t)

    ;; Insert tool
    (gptel-make-tool
     :name "Insert"
     :function #'gptel-agent--insert-in-file
     :description "Insert text at a line number in a file."
     :args '((:name "path" :type string)
             (:name "line_number" :type integer)
             (:name "new_str" :type string))
     :category "gptel-agent"
     :confirm t
     :include t)

    ;; Mkdir tool
    (gptel-make-tool
     :name "Mkdir"
     :function #'gptel-agent--make-directory
     :description "Create a directory under a parent directory."
     :args '((:name "parent" :type string)
             (:name "name" :type string))
     :category "gptel-agent"
     :confirm t
     :include t)

    ;; Move tool
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

    ;; Eval tool
    (gptel-make-tool
     :name "Eval"
     :function (lambda (expression)
                 (let ((standard-output (generate-new-buffer " *gptel-eval*"))
                       (result nil) (output nil))
                   (unwind-protect
                       (condition-case err
                           (progn
                             (setq result (eval (read expression) t))
                             (when (> (buffer-size standard-output) 0)
                               (setq output (with-current-buffer standard-output (buffer-string))))
                             (concat (format "Result:\n%S" result)
                                     (and output (format "\n\nSTDOUT:\n%s" output))))
                         ((error user-error)
                          (concat (format "Error: %S: %S" (car err) (cdr err))
                                  (and output (format "\n\nSTDOUT:\n%s" output)))))
                     (kill-buffer standard-output))))
     :description "Evaluate a single Elisp expression."
     :args '((:name "expression" :type string))
     :category "gptel-agent"
     :confirm t
     :include t)

    ;; WebSearch tool
    (gptel-make-tool
     :name "WebSearch"
     :function #'gptel-agent--web-search-eww
     :description "Search the web (returns top results)."
     :args '((:name "query" :type string)
             (:name "count" :type integer :optional t))
     :include t
     :async t
     :category "gptel-agent")

    ;; WebFetch tool
    (gptel-make-tool
     :name "WebFetch"
     :function #'gptel-agent--read-url
     :description "Fetch and read the text of a URL."
     :args '((:name "url" :type string))
     :async t
     :include t
     :category "gptel-agent")

    ;; YouTube tool
    (gptel-make-tool
     :name "YouTube"
     :function #'gptel-agent--yt-read-url
     :description "Fetch YouTube description and transcript."
     :args '((:name "url" :type string))
     :category "gptel-agent"
     :async t
     :include t)

    ;; TodoWrite tool
    (gptel-make-tool
     :name "TodoWrite"
     :function #'gptel-agent--write-todo
     :description "Update a session todo list."
     :args '((:name "todos"
                    :type array
                    :items (:type object
                                  :properties (:content (:type string :minLength 1)
                                                        :status (:type string :enum ["pending" "in_progress" "completed"])
                                                        :activeForm (:type string :minLength 1)))))
     :category "gptel-agent")

     ;; Skill tool
    (gptel-make-tool
     :name "Skill"
     :function #'my/gptel--skill-tool
     :description "Load a skill by name."
     :args '((:name "skill" :type string)
             (:name "args" :type string :optional t))
     :category "gptel-agent"
     :include t)

    ;; Skill management tools
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

  ;; Build tool lists
  (setq my/gptel-tools-readonly
        (my/gptel--dedup-tools-by-name
         (seq-filter #'identity
                     (mapcar #'my/gptel--safe-get-tool
                             '("Agent" "Bash" "Eval" "Glob" "Grep" "Read" "Skill"
                               "WebFetch" "WebSearch" "YouTube"
                               "find_buffers_and_recent" "describe_symbol" "get_symbol_source"
                               "lsp_diagnostics" "lsp_references" "lsp_workspace_symbol"
                               "lsp_definition" "lsp_hover" "AST_Map" "AST_Read")))))

  (setq my/gptel-tools-action
        (my/gptel--dedup-tools-by-name
         (append
          (seq-filter #'identity
                      (mapcar #'my/gptel--safe-get-tool
                              '("Agent" "ApplyPatch" "Bash" "Edit" "Eval" "Glob" "Grep"
                                "Insert" "Mkdir" "Move" "Read" "RunAgent" "Skill" "TodoWrite"
                                "WebFetch" "WebSearch" "Write" "YouTube"
                                "find_buffers_and_recent" "describe_symbol" "get_symbol_source"
                                "lsp_diagnostics" "lsp_references" "lsp_workspace_symbol"
                                "lsp_definition" "lsp_hover" "lsp_rename"
                                "preview_file_change" "preview_patch"
                                "list_skills" "load_skill" "create_skill"
                                "AST_Map" "AST_Read" "AST_Replace")))
          my/gptel-tools-readonly)))

  ;; Set default tool list
  (setq-default gptel-tools my/gptel-tools-readonly))

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

Call this after gptel-agent-tools loads."
  (gptel-tools-register-all))

;;; Footer

(provide 'gptel-tools)

;;; Auto-initialization

(with-eval-after-load 'gptel-agent-tools
  (gptel-tools-setup))

;;; gptel-tools.el ends here
