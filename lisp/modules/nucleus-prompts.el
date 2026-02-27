;;; nucleus-prompts.el --- Prompt loading for nucleus -*- lexical-binding: t; -*-

;; Author: David Wu
;; Version: 1.0.0
;;
;; Prompt loading and directive registration for nucleus gptel-agent.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'project)

;;; Customization

(defgroup nucleus-prompts nil
  "Prompt loading for nucleus."
  :group 'nucleus)

(defcustom nucleus-prompts-dir
  (expand-file-name "assistant/prompts/"
                    (if (boundp 'minimal-emacs-user-directory)
                        minimal-emacs-user-directory
                      user-emacs-directory))
  "Directory containing nucleus prompt templates (agents)."
  :type 'directory)

(defcustom nucleus-tool-prompts-dir
  (expand-file-name "assistant/prompts/tools/"
                    (if (boundp 'minimal-emacs-user-directory)
                        minimal-emacs-user-directory
                      user-emacs-directory))
  "Directory containing tool prompt templates."
  :type 'directory)

(defcustom nucleus-log-events t
  "Whether to log nucleus workflow events."
  :type 'boolean)

;;; Internal Variables

(defvar nucleus-prompts nil
  "Alist of loaded prompt templates.")

(defvar nucleus-tool-prompts nil
  "Alist of loaded tool prompt templates.")

(defconst nucleus-prompt-files
  '((nucleus-gptel-agent . "code_agent.md")
    (chatTitle           . "title.md")
    (compact             . "compact.md")
    (init                . "init.md")
    (skillCreate         . "skill_create.md")
    (completion          . "inline_completion.md")
    (rewrite             . "rewrite.md")
    (nucleus-gptel-plan  . "plan_agent.md")
    (explorer            . "explorer_agent.md"))
  "Prompt file map.")

(defconst nucleus-tool-prompt-files
  '((Bash                . "shell_command.md")
    (ApplyPatch          . "apply_patch.md")
    (Write               . "write_file.md")
    (Read                . "read_file.md")
    (Grep                . "grep.md")
    (Glob                . "directory_tree.md")
    (find_buffers_and_recent . "find_buffers_and_recent.md")
    (describe_symbol     . "describe_symbol.md")
    (WebSearch           . "web_search.md")
    (WebFetch            . "read_url.md")
    (compact_chat        . "compact_chat.md")
    (preview_file_change . "preview_file_change.md")
    (list_skills         . "list_skills.md")
    (load_skill          . "skill.md")
    (create_skill        . "create_skill.md")
    (Edit                . "edit_file.md")
    (Move                . "move_file.md"))
  "Tool prompt files.")

;;; Helper Functions

(defun nucleus--log (fmt &rest args)
  "Log a nucleus workflow message when `nucleus-log-events' is non-nil."
  (when nucleus-log-events
    (apply #'message (concat "[nucleus] " fmt) args)))

(defun nucleus--project-root ()
  "Return the current project root or `default-directory`."
  (if-let ((proj (project-current nil)))
      (project-root proj)
    default-directory))

(defun nucleus--resolve-prompts-dir ()
  "Return `nucleus-prompts-dir' if it exists as a directory, else nil."
  (when (file-directory-p nucleus-prompts-dir)
    nucleus-prompts-dir))

(defun nucleus--resolve-tool-prompts-dir ()
  "Return `nucleus-tool-prompts-dir' if it exists as a directory, else nil."
  (when (file-directory-p nucleus-tool-prompts-dir)
    nucleus-tool-prompts-dir))

(defun nucleus--read-file (path)
  "Read PATH and return its trimmed string contents."
  (string-trim (with-temp-buffer (insert-file-contents path) (buffer-string))))

(defun nucleus--read-file-if-exists (path)
  "Return trimmed contents of PATH if readable, else nil."
  (when (file-readable-p path)
    (nucleus--read-file path)))

(defun nucleus--parse-nucleus-file (init-text)
  "Extract the nucleus: file reference from INIT-TEXT, or nil."
  (when (string-match "^nucleus:\\s-*\\(.+\\)$" init-text)
    (string-trim (match-string 1 init-text))))

(defun nucleus--build-init-prompt ()
  "Build the init system prompt by composing nucleus, AGENTS.md, and MEMENTUM.md."
  (let* ((base (nucleus--resolve-prompts-dir))
         (init-path (and base (expand-file-name "init.md" base)))
         (init-text (and init-path (nucleus--read-file-if-exists init-path)))
         (nucleus-file (and init-text (nucleus--parse-nucleus-file init-text)))
         (nucleus-text
          (when (and base nucleus-file)
            (nucleus--read-file-if-exists (expand-file-name nucleus-file base))))
         (agents-text
          (nucleus--read-file-if-exists
           (expand-file-name "AGENTS.md" (nucleus--project-root))))
         (mementum-text
          (nucleus--read-file-if-exists
           (expand-file-name "MEMENTUM.md" (nucleus--project-root))))
         (parts (seq-filter #'identity
                           (list nucleus-text agents-text mementum-text))))
    (when parts
      (string-join parts "\n\n"))))

;;; Prompt Loading

(defun nucleus-load-prompts ()
  "Load all prompt files into `nucleus-prompts'. Returns the alist."
  (let ((base (nucleus--resolve-prompts-dir)))
    (setq nucleus-prompts
          (seq-filter
           #'identity
           (mapcar
            (lambda (entry)
              (let* ((key (car entry))
                     (file (cdr entry))
                     (path (and base (expand-file-name file base)))
                     (text (if (eq key 'init)
                               (nucleus--build-init-prompt)
                             (and path (nucleus--read-file-if-exists path)))))
                (when text
                  (cons key text))))
            nucleus-prompt-files))))
  nucleus-prompts)

(defun nucleus-load-tool-prompts ()
  "Load all tool prompt files into `nucleus-tool-prompts'. Returns the alist."
  (let ((base (nucleus--resolve-tool-prompts-dir)))
    (setq nucleus-tool-prompts
          (seq-filter
           #'identity
           (mapcar
            (lambda (entry)
              (let* ((key (car entry))
                     (file (cdr entry))
                     (path (and base (expand-file-name file base)))
                     (text (and path (nucleus--read-file-if-exists path))))
                (when text
                  (cons key text))))
            nucleus-tool-prompt-files))))
  nucleus-tool-prompts)

(defun nucleus-refresh-prompts ()
  "Force-reload all nucleus prompts from disk.

Use interactively when prompt files change on disk.
At load time, prefer `nucleus-ensure-loaded' instead."
  (interactive)
  (setq nucleus-prompts nil
        nucleus-tool-prompts nil)
  (nucleus-load-prompts)
  (nucleus-load-tool-prompts)
  (nucleus--log "Prompts refreshed from disk"))

(defun nucleus-ensure-loaded ()
  "Load nucleus prompts lazily — only if not already loaded."
  (unless nucleus-prompts
    (nucleus-load-prompts))
  (unless nucleus-tool-prompts
    (nucleus-load-tool-prompts))
  nucleus-prompts)

;;; Directive Registration

(defun nucleus--read-gptel-agent-system (file)
  "Read FILE as a gptel-agent definition and return its :system text."
  (when (and file (file-readable-p file))
    (let* ((parsed (if (fboundp 'gptel-agent-read-file)
                       (gptel-agent-read-file file nil nil)
                     nil))
           (plist (cdr parsed))
           (sys (plist-get plist :system)))
      (and (stringp sys)
           (string-trim sys)))))

(defun nucleus--register-gptel-directives ()
  "Register nucleus gptel-agent system prompts as gptel directives."
  (nucleus-ensure-loaded)
  
  (unless (boundp 'gptel-directives)
    (setq gptel-directives '()))
  
  (when (boundp 'gptel-directives)
    (cl-labels
        ((tool-snippets-for (tool-names)
           (when (and tool-names (fboundp 'nucleus-gptel-tool-prompts))
             (let* ((snips (nucleus-gptel-tool-prompts))
                    (chunks
                     (delq nil
                           (mapcar
                            (lambda (name)
                              (when-let ((txt (alist-get (intern name) snips)))
                                (format "[%s]\n%s" name (string-trim txt))))
                            tool-names))))
               (and chunks
                    (string-join chunks "\n\n"))))))
      (let* ((dir nucleus-prompts-dir)
             (agent-file (expand-file-name "code_agent.md" dir))
             (plan-file (expand-file-name "plan_agent.md" dir))
             (agent-sys (nucleus--read-gptel-agent-system agent-file))
             (plan-sys (nucleus--read-gptel-agent-system plan-file))
             (agent-tools (nucleus-get-tools :snippets))
             (agent-snips (tool-snippets-for agent-tools))
             (agent-sys (if agent-snips
                            (concat agent-sys
                                    "\n\n## Nucleus Tool Prompts (Supplemental)\n"
                                    agent-snips)
                          agent-sys)))
        (when (stringp agent-sys)
          (setf (alist-get 'nucleus-gptel-agent
                          gptel-directives nil nil #'eq)
                agent-sys))
        (when (stringp plan-sys)
          (setf (alist-get 'nucleus-gptel-plan
                          gptel-directives nil nil #'eq)
                plan-sys))
        (nucleus--log "Registered %d directives"
                     (length gptel-directives))))))

;;; Public API

(defun nucleus-gptel-directives ()
  "Build gptel directives from nucleus prompts."
  (nucleus-ensure-loaded)
  (let* ((all-prompts (copy-sequence nucleus-prompts))
         (agent (alist-get 'nucleus-gptel-agent all-prompts))
         (init (alist-get 'init all-prompts))
         (default-text (or (alist-get 'default all-prompts) agent))
         (merged-default (if (and init default-text)
                             (concat init "\n\n" default-text)
                           default-text))
         (hidden '(explorer reviewer chatTitle compact init
                   skillCreate completion rewrite))
         (filtered (seq-remove (lambda (entry)
                                (memq (car entry) hidden))
                              all-prompts)))
    (if merged-default
        (cons (cons 'default merged-default) filtered)
      filtered)))

(defun nucleus-gptel-tool-prompts ()
  "Return the nucleus tool-prompt alist, loading lazily if needed."
  (nucleus-ensure-loaded)
  nucleus-tool-prompts)

(defun nucleus-gptel-tools-instructions ()
  "Return all tool prompts as a single formatted string, or nil if none loaded."
  (nucleus-ensure-loaded)
  (when nucleus-tool-prompts
    (string-join
     (mapcar (lambda (entry)
               (format "[%s]\n%s" (car entry) (cdr entry)))
             nucleus-tool-prompts)
     "\n\n")))

;;; Integration

(defun nucleus-prompts-setup ()
  "Setup nucleus prompts module.

Call this after gptel loads to register directives."
  (nucleus-ensure-loaded)
  (nucleus--register-gptel-directives))

;;; Footer

(provide 'nucleus-prompts)

;;; nucleus-prompts.el ends here
