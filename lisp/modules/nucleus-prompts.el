;;; nucleus-prompts.el --- Prompt loading for nucleus -*- no-byte-compile: t; lexical-binding: t; -*-

;; Author: David Wu
;; Version: 1.0.0
;;
;; Prompt loading and directive registration for nucleus gptel-agent.
;;
;; DIRECTORY STRUCTURE:
;; - assistant/prompts/     → Utility prompts (directives)
;;   - init.md              → AGENTS.md loader
;;   - compact.md           → Auto-compaction summary
;;   - title.md             → Title generation
;;   - skill_create.md      → Skill creation
;;   - inline_completion.md → Inline completion
;;   - rewrite.md           → Text rewriting
;;   - tools/               → Tool-specific prompts (Read, Write, Bash, etc.)
;;
;; - assistant/agents/      → ALL agent prompts (primary + subagents)
;;   - code_agent.md        → Primary agent (nucleus-gptel-agent)
;;   - plan_agent.md        → Plan mode (nucleus-gptel-plan)
;;   - executor.md          → RunAgent("executor", ...)
;;   - researcher.md        → RunAgent("researcher", ...)
;;   - explorer_agent.md    → RunAgent("explorer", ...) [name in YAML is "explorer"]
;;   - reviewer.md          → RunAgent("reviewer", ...)
;;   - introspector.md      → RunAgent("introspector", ...)
;;   - analyzer.md          → RunAgent("analyzer", ...)
;;   - comparator.md        → RunAgent("comparator", ...)
;;   - grader.md            → RunAgent("grader", ...)

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
  "Directory containing utility prompt templates."
  :type 'directory)

(defcustom nucleus-agents-dir
  (expand-file-name "assistant/agents/"
                    (if (boundp 'minimal-emacs-user-directory)
                        minimal-emacs-user-directory
                      user-emacs-directory))
  "Directory containing agent prompts (primary + subagents)."
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

(defvar nucleus--directives-registered nil
  "Non-nil after `nucleus--register-gptel-directives' has run once.")

(defconst nucleus-prompt-files
  '((chatTitle           . "title.md")
    (compact             . "compact.md")
    (init                . "init.md")
    (skillCreate         . "skill_create.md")
    (completion          . "inline_completion.md")
    (rewrite             . "rewrite.md"))
  "Prompt file map for utility prompts loaded from `nucleus-prompts-dir'.
Agent prompts (code_agent.md, plan_agent.md) are loaded separately from `nucleus-agents-dir'.")

(defconst nucleus-tool-prompt-files
  '((Bash                . "bash.md")
    (ApplyPatch          . "apply_patch.md")
    (Write               . "write_file.md")
    (Read                . "read_file.md")
    (Grep                . "grep.md")
    (Glob                . "glob.md")
    (find_buffers_and_recent . "find_buffers_and_recent.md")
    (describe_symbol     . "describe_symbol.md")
    (WebSearch           . "web_search.md")
    (WebFetch            . "web_fetch.md")
    (compact_chat        . "compact_chat.md")
    (Preview             . "preview.md")
    (list_skills         . "list_skills.md")
    (load_skill          . "skill.md")
    (create_skill        . "create_skill.md")
    (Skill               . "skill.md")
    (describe_symbol     . "describe_symbol.md")
    (get_symbol_source   . "get_symbol_source.md")
    (Edit                . "edit_file.md")
    (Move                . "move.md")
     (RunAgent            . "run_agent.md")
     (Programmatic        . "programmatic.md")
     (Eval                . "eval.md")
    (Insert              . "insert.md")
    (Mkdir               . "mkdir.md")
    (TodoWrite           . "todo_write.md")
    (YouTube             . "youtube.md")
    ;; Code_* tools (unified AST/LSP interface)
    (Code_Map            . "code_map.md")
    (Code_Inspect        . "code_inspect.md")
    (Code_Replace        . "code_replace.md")
    (Code_Usages         . "code_usages.md")
    (Diagnostics         . "diagnostics.md")
    ;; Deprecated: LSP tools replaced by Code_* tools
    )
  "Tool prompt files. Code_* tools provide unified AST/LSP interface.")

;;; Helper Functions

(defun nucleus--log (fmt &rest args)
  "Log a nucleus workflow message when `nucleus-log-events' is non-nil."
  (when nucleus-log-events
    (apply #'message (concat "[nucleus] " fmt) args)))

(defun nucleus--project-root ()
  "Return the current project root or `default-directory`."
  (let* ((fallback-dir (if (boundp 'minimal-emacs-user-directory)
                           minimal-emacs-user-directory
                         user-emacs-directory))
         (active-dir (if (and (stringp default-directory)
                              (file-directory-p default-directory))
                         default-directory
                       fallback-dir)))
    (let ((default-directory active-dir))
      (if-let ((proj (project-current nil)))
          (project-root proj)
        active-dir))))

(defun nucleus--resolve-prompts-dir ()
  "Return `nucleus-prompts-dir' if it exists as a directory, else nil."
  (when (file-directory-p nucleus-prompts-dir)
    nucleus-prompts-dir))

(defun nucleus--resolve-agents-dir ()
  "Return `nucleus-agents-dir' if it exists as a directory, else nil."
  (when (file-directory-p nucleus-agents-dir)
    nucleus-agents-dir))

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
  "Build the init system prompt by composing nucleus and AGENTS.md."
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
         (parts (seq-filter #'identity
                           (list nucleus-text agents-text))))
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
  "Register nucleus gptel-agent system prompts as gptel directives.
Idempotent: only registers and logs once per session."
  (unless nucleus--directives-registered
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
        (let* ((dir nucleus-agents-dir)
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
          ;; Add compact directive for auto-compaction
          (setf (alist-get 'compact
                          gptel-directives nil nil #'eq)
                "Summarize this conversation history for LLM context continuity.
Keep all key information: decisions made, files modified, commands run, errors encountered.
Format as a structured brief with: [progress] [decisions] [next_steps] [tech_details]")
          (nucleus--log "Registered %d directives"
                       (length gptel-directives))
          (setq nucleus--directives-registered t))))))
;;; Public API

(defun nucleus-gptel-tool-prompts ()
  "Return the nucleus tool-prompt alist, loading lazily if needed."
  (nucleus-ensure-loaded)
  nucleus-tool-prompts)

;;; Footer

(provide 'nucleus-prompts)

;;; nucleus-prompts.el ends here
