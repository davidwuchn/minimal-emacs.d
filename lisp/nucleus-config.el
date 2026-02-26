;;; nucleus-config.el --- Nucleus prompt loader -*- lexical-binding: t; -*-

(require 'project)
(require 'cl-lib)
(require 'seq)
(require 'subr-x)

;; Silence compile-time warnings; these are defined in gptel-agent.
;; Important: keep these compile-time only so we don't pre-bind variables
;; like `gptel-agent-dirs` to nil before `gptel-agent` loads.
(eval-when-compile
  ;; Silence byte-compiler warnings; these are defined in gptel-agent and
  ;; related packages.  Keep compile-time only so we don't pre-bind variables
  ;; to nil before the packages load.
  (defvar gptel-agent-dirs)
  (defvar gptel-agent-skill-dirs)
  (defvar gptel-backend)
  (defvar gptel-mode)
  (defvar gptel-use-header-line)
  (defvar header-line-format)
  (declare-function gptel-agent-update "gptel-agent")
  (declare-function gptel-agent "gptel-agent")
  (declare-function gptel--apply-preset "gptel-transient")
  (declare-function gptel-backend-name "gptel")
  (declare-function buttonize "button"))

(defun nucleus--project-root ()
  "Return the current project root or `default-directory`."
  (if-let ((proj (project-current nil)))
      (project-root proj)
    default-directory))

(defgroup nucleus nil
  "Prompt loading helpers for gptel."
  :group 'tools)

(defcustom nucleus-prompts-dir (expand-file-name "assistant/prompts/" (if (boundp 'minimal-emacs-user-directory) minimal-emacs-user-directory user-emacs-directory))
  "Directory containing nucleus prompt templates (agents)."
  :type 'directory)

(defcustom nucleus-tool-prompts-dir
  (expand-file-name "assistant/prompts/tools/" (if (boundp 'minimal-emacs-user-directory) minimal-emacs-user-directory user-emacs-directory))
  "Directory containing tool prompt templates."
  :type 'directory)

(defcustom nucleus-log-events t
  "Whether to log nucleus workflow events."
  :type 'boolean)

(defun nucleus--log (fmt &rest args)
  "Log a nucleus workflow message when `nucleus-log-events' is non-nil."
  (when nucleus-log-events
    (apply #'message (concat "[nucleus] " fmt) args)))

;; Default gptel-agent preset; toggle between plan and code agents.
(defvar nucleus-agent-default 'gptel-plan
  "Default gptel agent preset.  Use `nucleus-agent-toggle' to switch.")

(defvar nucleus-tools-readonly nil
  "Tool list for read-only (plan) profile.  Set by gptel-config after tool registration.")

(defvar nucleus-tools-action nil
  "Tool list for action (agent) profile.  Set by gptel-config after tool registration.")

(defun nucleus--effective-preset ()
  "Return the active gptel preset, preferring `gptel--preset` when available."
  (if (and (boundp 'gptel--preset)
           (memq gptel--preset '(gptel-plan gptel-agent)))
      gptel--preset
    nucleus-agent-default))

(defun nucleus--sync-tool-profile ()
  "Sync `gptel-tools` to match the active preset."
  (when (boundp 'gptel-tools)
    (let ((preset (nucleus--effective-preset)))
      ;; Do NOT update `nucleus-agent-default' from restored buffers.
      ;; Only `nucleus-agent-toggle' should change the default.
      ;; This ensures startup always defaults to Plan (the safe default).

      ;; If gptel has applied a preset (Plan/Agent), do not override its tool
      ;; list.  Presets provide tools like TodoWrite, Edit, Write, etc.
      (if (and (boundp 'gptel--preset)
               (memq gptel--preset '(gptel-plan gptel-agent)))
          (nucleus--log "tool profile left to preset: %s" gptel--preset)
        (pcase preset
          ('gptel-plan
           (when nucleus-tools-readonly
             (setq-local gptel-tools nucleus-tools-readonly)))
          ('gptel-agent
           (when nucleus-tools-action
             (setq-local gptel-tools nucleus-tools-action))))
        (nucleus--log "tool profile synced to %s" preset)))))

(defun nucleus-agent-toggle ()
  "Toggle the default gptel agent preset between plan and code.

Syncs the tool profile to match: plan → readonly tools, agent → action tools."
  (interactive)
  (setq nucleus-agent-default
        (if (eq nucleus-agent-default 'gptel-plan) 'gptel-agent 'gptel-plan))
  ;; If we're in a gptel buffer and preset application is available, switch the
  ;; active preset in-buffer (not just the default for future sessions).
  (when (and (derived-mode-p 'gptel-mode)
             (fboundp 'gptel--apply-preset))
    (gptel--apply-preset
     nucleus-agent-default
     (lambda (sym val)
       (set (make-local-variable sym) val))))
  (nucleus--sync-tool-profile)
  (let* ((preset (nucleus--effective-preset))
         (prompt-file (if (eq preset 'gptel-plan)
                          "plan_agent.md"
                        "code_agent.md")))
    (nucleus--log "gptel default agent: %s (prompt: %s)" preset prompt-file))
  (force-mode-line-update t))

(defun nucleus-header-toggle-preset (&rest _)
  "Toggle gptel preset between Plan and Agent for the current buffer.
Updates `nucleus-agent-default' so new buffers use the same preset."
  (interactive)
  (when (fboundp 'gptel--apply-preset)
    (let* ((current (nucleus--effective-preset))
           (new (if (eq current 'gptel-agent) 'gptel-plan 'gptel-agent)))
      (setq nucleus-agent-default new)
      (gptel--apply-preset
       new
       (lambda (sym val) (set (make-local-variable sym) val)))
      (force-mode-line-update))))

(defun nucleus--header-line-apply-preset-label (&rest _)
  "Set the gptel header-line to show the active preset with a toggle button.
Only applies when a gptel--preset is active in the current buffer."
  (when (and (bound-and-true-p gptel-mode)
             (bound-and-true-p gptel-use-header-line)
             (consp header-line-format)
             (bound-and-true-p gptel--preset))
    (setcar
     header-line-format
     '(:eval
       (let* ((preset (nucleus--effective-preset))
              (agent-mode (eq preset 'gptel-agent))
              (label (if agent-mode "[Agent]" "[Plan]"))
              (help  (if agent-mode "Switch to Plan preset" "Switch to Agent preset"))
              (face  (if agent-mode 'font-lock-keyword-face 'font-lock-doc-face)))
         (concat
          (propertize " " 'display '(space :align-to 0))
          (format "%s" (gptel-backend-name gptel-backend))
          (propertize (buttonize label #'nucleus-header-toggle-preset nil help)
                      'face face)))))))

(defun nucleus--agent-around (orig &optional project-dir agent-preset)
  "Around-advice for `gptel-agent': normalize args and fix header.

1. Coerce PROJECT-DIR to an existing directory.
2. Override AGENT-PRESET with `nucleus-agent-default'.
3. After the call, replace gptel-agent's hardcoded header-line closure
   with the preset-aware version."
  (ignore agent-preset)
  (when project-dir
    (setq project-dir (nucleus--ensure-directory project-dir)))
  (let* ((existing (mapcar #'buffer-name
                           (seq-filter (lambda (b)
                                         (buffer-local-value 'gptel-mode b))
                                       (buffer-list))))
         (_result (funcall orig project-dir nucleus-agent-default))
         (new-buf (seq-find (lambda (b)
                              (and (buffer-local-value 'gptel-mode b)
                                   (not (member (buffer-name b) existing))))
                            (buffer-list))))
    (when (and new-buf (buffer-live-p new-buf))
      (with-current-buffer new-buf
        (nucleus--header-line-apply-preset-label)))))

(with-eval-after-load 'gptel-agent
  (advice-add 'gptel-agent :around #'nucleus--agent-around))

(defun nucleus--read-gptel-agent-system (file)
  "Read FILE as a gptel-agent definition and return its :system text."
  (when (and file (file-readable-p file))
    (let* ((parsed (gptel-agent-read-file file nil nil))
           (plist (cdr parsed))
           (sys (plist-get plist :system)))
      (and (stringp sys) (string-trim sys)))))

(defun nucleus--replace-tag-block (base tag new-block)
  "Replace <TAG>...</TAG> in BASE with NEW-BLOCK.

If BASE has no such block, or NEW-BLOCK is nil, return BASE unchanged."
  (if (and (stringp base) (stringp tag) (stringp new-block))
      (let ((re (format "<%s>\\(?:.\\|%c\\)*?</%s>"
                        (regexp-quote tag) ?\n (regexp-quote tag))))
        (if (string-match re base)
            (replace-regexp-in-string re new-block base t t)
          base))
    base))

(defconst nucleus--gptel-tool-usage-policy-agent
  (string-join
   (list
    "<tool_usage_policy>"
    "Selection & safety:"
    "- File ops: prefer standard tools (Glob/Grep/Read/Edit/Insert/Write/Mkdir)."
    "- Bash: use for non-file ops (git, tests/builds, package managers, system inspection)."
    "- For large/risky changes: preview diff first, then apply."
    "- Prefer parallel tool calls when independent; sequence when dependent."
    "</tool_usage_policy>")
   "\n")
  "Compact, schema-faithful tool usage policy for the action agent.")

(defconst nucleus--gptel-tool-usage-policy-plan
  (string-join
   (list
    "<tool_usage_policy>"
    "Read-only planning: prefer Glob/Grep/Read for repo context; use WebSearch/WebFetch/YouTube for external context."
    "- Bash{command}: READ-ONLY commands only (ls, git status). Do NOT modify files or system state via Bash."
    ""
    "Disallowed in plan mode (even if known elsewhere):"
    "- Edit/Insert/Write/Mkdir/ApplyPatch/preview_*"
    "</tool_usage_policy>")
   "\n")
  "Compact, schema-faithful tool usage policy for the plan agent.")

(defconst nucleus--gptel-tool-usage-policy-introspector
  (string-join
   (list
    "<tool_usage_policy>"
    "Introspection-only: prefer completions/discovery tools, then documentation, then source."
    "Use Eval only for small checks and to confirm live values."
    "</tool_usage_policy>")
   "\n")
  "Compact tool usage policy for the introspector agent.")

(defconst nucleus--gptel-tool-usage-policy-researcher
  (string-join
   (list
    "<tool_usage_policy>"
    "Read-only research: use Glob/Grep/Read for repo context; WebSearch/WebFetch/YouTube for external context."
    "</tool_usage_policy>")
   "\n")
  "Compact tool usage policy for the researcher agent.")

(defun nucleus--register-gptel-directives ()
  "Register nucleus gptel-agent system prompts as gptel directives."
  ;; Ensure gptel-directives exists before trying to register
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
               (and chunks (string-join chunks "\n\n"))))))
      (let* ((dir nucleus-prompts-dir)
             (agent-file (expand-file-name "code_agent.md" dir))
             (plan-file (expand-file-name "plan_agent.md" dir))
             (agent-sys (nucleus--read-gptel-agent-system agent-file))
             (plan-sys (nucleus--read-gptel-agent-system plan-file))
             (agent-sys (nucleus--replace-tag-block agent-sys "tool_usage_policy"
                                                    nucleus--gptel-tool-usage-policy-agent))
             (plan-sys (nucleus--replace-tag-block plan-sys "tool_usage_policy"
                                                   nucleus--gptel-tool-usage-policy-plan))
             ;; Inject tool snippets only for nucleus agent chats.
             (agent-tools nucleus--gptel-agent-snippet-tools)
             (agent-snips (tool-snippets-for agent-tools))
             (agent-sys (if agent-snips
                            (concat agent-sys "\n\n## Nucleus Tool Prompts (Supplemental)\n" agent-snips)
                          agent-sys)))
        (when (stringp agent-sys)
          (setf (alist-get 'nucleus-gptel-agent gptel-directives nil nil #'eq)
                agent-sys)
          ;; Friendly alias at front so header-line shows "Agent" not "nucleus-gptel-agent"
          (setq gptel-directives
                (cons (cons 'Agent agent-sys)
                      (assq-delete-all 'Agent gptel-directives))))
        (when (stringp plan-sys)
          (setf (alist-get 'nucleus-gptel-plan gptel-directives nil nil #'eq)
                plan-sys)
          ;; Friendly alias at front so header-line shows "Plan" not "nucleus-gptel-plan"
          (setq gptel-directives
                (cons (cons 'Plan plan-sys)
                       (assq-delete-all 'Plan gptel-directives))))))))

(defvar nucleus--gptel-agent-core-tools
  '("Agent" "ApplyPatch" "Bash" "Edit" "Eval" "Glob" "Grep" "Insert" "Mkdir" "Read" "RunAgent" "Skill" "TodoWrite" "WebFetch" "WebSearch" "Write" "YouTube")
  "Core gptel-agent tools to be included in presets by default.")

(defvar nucleus--gptel-plan-readonly-tools
  '("Agent" "Bash" "Glob" "Grep" "Read" "Skill" "WebFetch" "WebSearch" "YouTube"
    "find_buffers_and_recent" "describe_symbol" "Eval")
  "Read-only subset of gptel-agent tools for planning.")

(defvar nucleus--gptel-agent-nucleus-tools
  (append
   nucleus--gptel-agent-core-tools
   '("preview_file_change" "preview_patch" "list_skills" "load_skill" "create_skill"))
  "Nucleus toolset for gptel-agent.

This is the canonical nucleus agent experience: the core tools plus
preview + skill management helpers.")

(defvar nucleus--gptel-agent-snippet-tools
  nil
  "Tools whose supplemental snippets are injected into `nucleus-gptel-agent`.

Keep this list nil or small for token efficiency.")

(defvar nucleus--gptel-agent-action-tools
  nucleus--gptel-agent-nucleus-tools
  "Nucleus agent tools for action profile.")

(defvar-local nucleus--tool-sanity-last-report nil
  "Last tool sanity mismatch reported in this buffer.")

(defun nucleus--tool-name (tool)
  "Return TOOL name as a string when possible."
  (cond
   ((stringp tool) tool)
   ((and (fboundp 'gptel-tool-name) tool)
    (ignore-errors (gptel-tool-name tool)))
   ((and (listp tool) (plist-get tool :name)) (plist-get tool :name))
   (t nil)))

(defun nucleus--tool-names-from-tools (tools)
  "Return tool name strings from TOOLS."
  (delq nil (mapcar #'nucleus--tool-name tools)))

(defun nucleus--expected-tools-for-preset (&optional preset)
  "Return expected tool names for PRESET."
  (pcase (or preset (nucleus--effective-preset))
    ('gptel-plan nucleus--gptel-plan-readonly-tools)
    ('gptel-agent nucleus--gptel-agent-nucleus-tools)
    (_ nil)))

(defun nucleus--tool-sanity-check (&optional preset context)
  "Warn when current `gptel-tools' mismatches expected tools for PRESET."
  (when (and (boundp 'gptel-tools) (listp gptel-tools))
    (let* ((preset (or preset (nucleus--effective-preset)))
           (expected (nucleus--expected-tools-for-preset preset))
           (actual (nucleus--tool-names-from-tools gptel-tools)))
      (when (and expected actual)
        (let* ((missing (seq-filter (lambda (n) (not (member n actual))) expected))
               (extra (seq-filter (lambda (n) (not (member n expected))) actual))
               (report (list preset missing extra)))
          (cond
           ((and (not missing) (not extra))
            (setq-local nucleus--tool-sanity-last-report nil))
           ((not (equal report nucleus--tool-sanity-last-report))
            (setq-local nucleus--tool-sanity-last-report report)
            (nucleus--log "tool sanity mismatch%s preset=%s missing=[%s] extra=[%s]"
                          (if context (format " %s" context) "")
                          preset
                          (if missing (string-join missing ", ") "none")
                          (if extra (string-join extra ", ") "none")))))))))

(defun nucleus--override-gptel-agent-presets ()
  "Make gptel-agent's Plan/Agent presets use nucleus system prompts and full toolsets."
  (when (and (fboundp 'gptel-get-preset)
             (fboundp 'gptel-make-preset))
    (let* ((agent-backend (and (boundp 'gptel--gemini) gptel--gemini))
           (preferred-model (and (fboundp 'nucleus-resolve-model) agent-backend
                                 (nucleus-resolve-model agent-backend)))
           (preferred-backend agent-backend))
      (when-let ((agent (gptel-get-preset 'gptel-agent)))
        ;; `copy-sequence' is a shallow copy: the top-level plist cons cells are
        ;; new, but nested values (e.g. a `:tools' list) remain shared.  This is
        ;; safe here because every `plist-put' below replaces the value with a
        ;; fresh binding — no in-place mutation of nested structures occurs.
        (let ((plist (copy-sequence agent)))
          (setq plist (plist-put plist :system 'nucleus-gptel-agent))
          (setq plist (plist-put plist :tools nucleus--gptel-agent-nucleus-tools))
          (when preferred-model
            (setq plist (plist-put plist :model preferred-model))
            (setq plist (plist-put plist :backend preferred-backend)))
          (apply #'gptel-make-preset 'gptel-agent plist)))

      (when-let ((plan (gptel-get-preset 'gptel-plan)))
        ;; Same shallow-copy contract as above: safe because all mutations use
        ;; `plist-put' with fresh values, not in-place nested mutation.
        (let ((plist (copy-sequence plan)))
          (setq plist (plist-put plist :system 'nucleus-gptel-plan))
          (setq plist (plist-put plist :tools nucleus--gptel-plan-readonly-tools))
          (when preferred-model
            (setq plist (plist-put plist :model preferred-model))
            (setq plist (plist-put plist :backend preferred-backend)))
          (apply #'gptel-make-preset 'gptel-plan plist))))

    ;; Also patch subagents in `gptel-agent--agents` if they exist.
    ;; This ensures delegated agents keep the same toolset and a compact,
    ;; schema-faithful tool usage policy (token-efficient and avoids arg drift).
    (when (boundp 'gptel-agent--agents)
      (cl-labels
          ((sys->string (sys)
             (cond
              ((stringp sys) sys)
              ((and (listp sys) (seq-every-p #'stringp sys)) (string-join sys "\n"))
              (t nil)))
           (patch-agent (name tools policy)
             (when-let ((cell (assoc name gptel-agent--agents)))
               (when tools
                 (setf (plist-get (cdr cell) :tools) tools))
               (when-let* ((sys (plist-get (cdr cell) :system))
                           (sys (sys->string sys))
                           (sys (nucleus--replace-tag-block sys "tool_usage_policy" policy)))
                 ;; Store back as a string to avoid mixed representations.
                 (setf (plist-get (cdr cell) :system) sys)))))
        (patch-agent "executor" nucleus--gptel-agent-nucleus-tools nucleus--gptel-tool-usage-policy-agent)
        ;; Do not override researcher tools; keep them minimal.
        (patch-agent "researcher" nil nucleus--gptel-tool-usage-policy-researcher)
        ;; Do not override introspector tools (it relies on `introspection`).
        (patch-agent "introspector" nil nucleus--gptel-tool-usage-policy-introspector)))))

(defun nucleus--ensure-directory (path)
  "Return PATH coerced to an existing directory path."
  (let* ((expanded (expand-file-name (or path default-directory)))
         (dir (if (file-directory-p expanded)
                  expanded
                (file-name-directory expanded))))
    (file-name-as-directory dir)))

(defun nucleus--after-agent-update (&rest _)
  "Post-agent-update hook: re-register directives and override presets."
  (when (featurep 'gptel)
    (nucleus--register-gptel-directives)
    (nucleus--override-gptel-agent-presets)))

(defun nucleus--after-apply-preset (&rest _)
  "Nucleus post-preset hook: tool sanity check and header line refresh.
Runs as :after advice on `gptel--apply-preset', registered after
gptel-config loads so custom tools and nucleus presets are in place."
  (when (and (boundp 'gptel--preset) gptel--preset
             (bound-and-true-p gptel-mode)
             (memq gptel--preset '(gptel-plan gptel-agent)))
    (nucleus--tool-sanity-check gptel--preset "after-preset"))
  (nucleus--header-line-apply-preset-label))

(with-eval-after-load 'gptel-agent
  ;; Prefer project-local agents when present, but keep package defaults.
  (let* ((base-dir (if (boundp 'minimal-emacs-user-directory) minimal-emacs-user-directory user-emacs-directory))
         (user-agents (expand-file-name "assistant/agents/" base-dir))
         (proj-agents (expand-file-name "assistant/agents/" (nucleus--project-root)))
         (skill-dir (expand-file-name "assistant/skills/" base-dir))
         (agent-dirs (seq-remove (lambda (dir)
                                   (member dir (list user-agents proj-agents)))
                                 gptel-agent-dirs)))
    (when (file-directory-p user-agents)
      (setq agent-dirs (append agent-dirs (list user-agents))))
    (when (file-directory-p proj-agents)
      (setq agent-dirs (append agent-dirs (list proj-agents))))
    (setq gptel-agent-dirs agent-dirs)
    (when (and (boundp 'gptel-agent-skill-dirs)
               (file-directory-p skill-dir))
      (add-to-list 'gptel-agent-skill-dirs skill-dir)))
  (gptel-agent-update)

  ;; Defer preset override until custom tools are registered in gptel-config.el
(defconst nucleus-prompt-files
  '((nucleus-gptel-agent . "code_agent.md")
    (chatTitle  . "title.md")
    (compact    . "compact.md")
    (init       . "init.md")
    (skillCreate . "skill_create.md")
    (completion . "inline_completion.md")
    (rewrite    . "rewrite.md")
    (nucleus-gptel-plan . "plan_agent.md")
    (explorer   . "explorer_agent.md"))
  "Prompt file map.")

(defconst nucleus-tool-prompt-files
  '((Bash                 . "shell_command.md")
    (ApplyPatch           . "apply_patch.md")
    (Write               . "write_file.md")
    (Read                . "read_file.md")
    (Grep                . "grep.md")
    (Glob                . "directory_tree.md")
    (find_buffers_and_recent . "find_buffers_and_recent.md")
    (describe_symbol       . "describe_symbol.md")
    (WebSearch            . "web_search.md")
    (WebFetch             . "read_url.md")
    (compact_chat          . "compact_chat.md")
    (preview_file_change   . "preview_file_change.md")
    (list_skills           . "list_skills.md")
    (load_skill            . "skill.md")
    (create_skill          . "create_skill.md")
    (Edit                . "edit_file.md")
    (Move                . "move_file.md"))
  "Tool prompt files.")

(defvar nucleus-prompts nil)
(defvar nucleus-tool-prompts nil)

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
  (when (file-readable-p path) (nucleus--read-file path)))

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
          (nucleus--read-file-if-exists (expand-file-name "AGENTS.md" (nucleus--project-root))))
         (mementum-text
          (nucleus--read-file-if-exists (expand-file-name "MEMENTUM.md" (nucleus--project-root))))
         (parts (seq-filter #'identity (list nucleus-text agents-text mementum-text))))
    (when parts (string-join parts "\n\n"))))

(defun nucleus-load-prompts ()
  "Load all prompt files into `nucleus-prompts'.  Returns the alist."
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
                (when text (cons key text))))
            nucleus-prompt-files))))
  nucleus-prompts)

(defun nucleus-load-tool-prompts ()
  "Load all tool prompt files into `nucleus-tool-prompts'.  Returns the alist."
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
                (when text (cons key text))))
            nucleus-tool-prompt-files))))
  nucleus-tool-prompts)

(defun nucleus-refresh-prompts ()
  "Force-reload all nucleus prompts from disk.
Use interactively when prompt files change on disk.
At load time, prefer `nucleus-ensure-loaded' instead."
  (setq nucleus-prompts nil nucleus-tool-prompts nil)
  (nucleus-load-prompts)
  (nucleus-load-tool-prompts))

(defun nucleus-ensure-loaded ()
  "Load nucleus prompts lazily — only if not already loaded."
  (unless nucleus-prompts (nucleus-load-prompts))
  (unless nucleus-tool-prompts (nucleus-load-tool-prompts)))

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
         ;; Filter out agents and internal tool directives from the prompt menu.
         ;; These are used programmatically (by nucleus presets, compact tool,
         ;; skill tools etc.) and should not appear in the interactive picker.
         (filtered (seq-remove (lambda (entry)
                                  (memq (car entry)
                                        '(nucleus-gptel-agent nucleus-gptel-plan
                                          explorer reviewer
                                          chatTitle compact init
                                          skillCreate completion rewrite)))
                                all-prompts)))
    (if merged-default
        (cons (cons 'default merged-default) filtered)
      filtered)))

(defun nucleus-gptel-tool-prompts ()
  "Return the nucleus tool-prompt alist, loading lazily if needed."
  (nucleus-ensure-loaded) nucleus-tool-prompts)

(defun nucleus-gptel-tools-instructions ()
  "Return all tool prompts as a single formatted string, or nil if none loaded."
  (nucleus-ensure-loaded)
  (when nucleus-tool-prompts
    (string-join
     (mapcar (lambda (entry) (format "[%s]\n%s" (car entry) (cdr entry)))
             nucleus-tool-prompts)
     "\n\n")))

  (with-eval-after-load 'gptel-config
    (nucleus--register-gptel-directives)
    (nucleus--override-gptel-agent-presets)
    (add-hook 'gptel-mode-hook #'nucleus--sync-tool-profile)
    (add-hook 'gptel-mode-hook #'nucleus--tool-sanity-check)

    ;; Ensure prompts are loaded.
    ;; Note: nucleus-internal entries are filtered from the interactive picker
    ;; by `my/gptel--filter-directive-menu' in gptel-config.el, but the directives
    ;; must remain in gptel-directives for preset resolution.
    (nucleus-ensure-loaded)

    ;; Register post-preset hook: nucleus-side sanity check + header refresh.
    ;; The defun is at top-level above; only the advice registration is deferred.
    (when (fboundp 'gptel--apply-preset)
      (advice-add 'gptel--apply-preset :after #'nucleus--after-apply-preset)))

  (unless (advice-member-p #'nucleus--after-agent-update 'gptel-agent-update)
    (advice-add 'gptel-agent-update :after #'nucleus--after-agent-update)))

(with-eval-after-load 'gptel
  (when (require 'gptel-agent nil t)
    (gptel-agent-update)))

(provide 'nucleus-config)
;;; nucleus-config.el ends here
