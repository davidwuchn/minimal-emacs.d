;;; nucleus-presets.el --- Preset management for nucleus -*- no-byte-compile: t; lexical-binding: t; -*-

;; Author: David Wu
;; Version: 1.0.0
;;
;; Preset management for nucleus gptel-agent (plan/agent toggle).

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(defvar nucleus-agent-tool-contracts)  ; defined in nucleus-tools.el

;;; Customization

(defgroup nucleus-presets nil
  "Preset management for nucleus."
  :group 'nucleus)

;;; Internal Variables

(defvar nucleus-agent-default 'gptel-plan
  "Default gptel agent preset. Use `nucleus-agent-toggle' to switch.")

(defcustom nucleus-plan-model 'qwen3.5-plus
  "Model for gptel-plan preset (read-only planning)."
  :type 'symbol
  :group 'nucleus-presets)

(defcustom nucleus-agent-model 'glm-5
  "Fallback model for gptel-agent preset when YAML doesn't specify model.
YAML frontmatter in gptel-agent.md takes priority if model: is set."
  :type 'symbol
  :group 'nucleus-presets)

(defcustom nucleus-plan-model 'qwen3.5-plus
  "Fallback model for gptel-plan preset when YAML doesn't specify model.
YAML frontmatter in gptel-plan.md takes priority if model: is set."
  :type 'symbol
  :group 'nucleus-presets)

(defvar nucleus-hidden-directives
  '(chatTitle compact init skillCreate completion rewrite)
  "Directives to hide from the transient menu.
These are gptel-directives keys that should not appear in the menu.")

;;; Preset Functions

(defun nucleus--effective-preset ()
  "Return the active gptel preset, preferring `gptel--preset' when available."
  (if (and (boundp 'gptel--preset)
           (memq gptel--preset '(gptel-plan gptel-agent)))
      gptel--preset
    nucleus-agent-default))

(defun nucleus-agent-toggle ()
  "Toggle the default gptel agent preset between plan and agent.

Syncs the tool profile to match: plan → readonly tools, agent → action tools."
  (interactive)
  (setq nucleus-agent-default
        (if (eq nucleus-agent-default 'gptel-plan)
            'gptel-agent
          'gptel-plan))
  
  ;; If we're in a gptel buffer and preset application is available,
  ;; switch the active preset in-buffer
  (when (and (derived-mode-p 'gptel-mode)
             (fboundp 'gptel--apply-preset))
    (gptel--apply-preset
     nucleus-agent-default
     (lambda (sym val)
       (set (make-local-variable sym) val))))
  
  ;; Sync tool profile
  (nucleus-sync-tool-profile)
  
  ;; Log the change
  (let* ((preset (nucleus--effective-preset))
         (prompt-file (if (eq preset 'gptel-plan)
                          "plan_agent.md"
                        "code_agent.md")))
    (message "[nucleus] gptel default agent: %s (prompt: %s)"
             preset prompt-file))
  
  (force-mode-line-update t))

(defun nucleus-header-toggle-preset (&rest _)
  "Toggle gptel preset between Plan and Agent for the current buffer.

Updates `nucleus-agent-default' so new buffers use the same preset."
  (interactive)
  (when (fboundp 'gptel--apply-preset)
    (let* ((current (nucleus--effective-preset))
           (new (if (eq current 'gptel-agent)
                    'gptel-plan
                  'gptel-agent)))
      (setq nucleus-agent-default new)
      (gptel--apply-preset
       new
       (lambda (sym val)
         (set (make-local-variable sym) val)))
      (force-mode-line-update))))

(defun nucleus--override-preset (preset-name system-symbol description toolset model backend)
  "Override PRESET-NAME with nucleus SYSTEM-SYMBOL, DESCRIPTION, TOOLSET, MODEL, BACKEND.

Only override :model and :backend if the preset doesn't already have a model
(allowing YAML model: to take priority).

MODEL from YAML is a string; convert to symbol for gptel."
  (when-let ((base (gptel-get-preset preset-name)))
    (let ((plist (copy-sequence base)))
      (setq plist (plist-put plist :system system-symbol))
      (setq plist (plist-put plist :description description))
      (setq plist (plist-put plist :tools (nucleus-get-tools toolset)))
      ;; Only set model/backend if not already defined (YAML takes priority)
      (unless (plist-get plist :model)
        (when model
          (setq plist (plist-put plist :model model))
          (setq plist (plist-put plist :backend backend))))
      ;; Convert string model to symbol (YAML returns strings)
      (when-let ((m (plist-get plist :model)))
        (when (stringp m)
          (setq plist (plist-put plist :model (intern m)))))
      (apply #'gptel-make-preset preset-name plist))))

(defun nucleus--refresh-open-gptel-buffers ()
  "Re-apply active presets to already-open gptel buffers.
Existing buffers keep stale gptel-tools if the preset definition
changed (e.g. RunAgent added after buffer was created)."
  (when (fboundp 'gptel--apply-preset)
    (dolist (buf (buffer-list))
      (with-current-buffer buf
        (when (and (bound-and-true-p gptel-mode)
                   (boundp 'gptel--preset)
                   (memq gptel--preset '(gptel-plan gptel-agent)))
          (condition-case err
              (gptel--apply-preset gptel--preset
                                   (lambda (sym val)
                                     (set (make-local-variable sym) val)))
            (error
             (message "[nucleus] Warning: failed to re-apply preset %S to buffer %S: %s"
                      gptel--preset (buffer-name buf)
                      (error-message-string err)))))))))

(defun nucleus--override-gptel-agent-presets ()
  "Make gptel-agent's Plan/Agent presets use nucleus system prompts and toolsets."
  (when (and (fboundp 'gptel-get-preset)
             (fboundp 'gptel-make-preset))
    (let* ((preferred-backend gptel-backend))

      (nucleus--override-preset
       'gptel-agent 'nucleus-gptel-agent
       "Nucleus execution agent — full tool access, code changes"
       :nucleus nucleus-agent-model preferred-backend)

      (nucleus--override-preset
       'gptel-plan 'nucleus-gptel-plan
       "Nucleus planning agent — read-only, architecture & research"
       :readonly nucleus-plan-model preferred-backend)
      
      ;; Patch subagent tools in gptel-agent--agents (model from YAML)
      (when (boundp 'gptel-agent--agents)
        (cl-labels
         ((sys->string (sys)
            (cond
             ((stringp sys) sys)
             ((and (listp sys)
                   (seq-every-p #'stringp sys))
              (string-join sys "\n"))
             (t nil)))
          (patch-agent (name tools)
            (when-let ((cell (assoc name gptel-agent--agents)))
              (when tools
                (setf (plist-get (cdr cell) :tools) tools))
              (when-let* ((sys (plist-get (cdr cell) :system))
                          (sys (sys->string sys))
                          sys)
                (setf (plist-get (cdr cell) :system) sys)))))

         (dolist (contract nucleus-agent-tool-contracts)
           (patch-agent (car contract) (nucleus-get-tools (cdr contract))))
          ;; Validate immediately after patching
         (when (and (boundp 'nucleus-tools-strict-validation)
                    nucleus-tools-strict-validation)
           (nucleus--validate-agent-tool-contracts))
          ;; Agent tool contracts (counts must match nucleus-toolsets):
          ;; - executor:     :nucleus    (31 tools) - code changes & execution
         ;; - researcher:   :researcher (20 tools) - exploration & research
          ;; - introspector: :readonly   (19 tools) - Emacs introspection
          ;; - explorer:     :explorer    (3 tools) - read-only codebase exploration
          ;; - reviewer:     :reviewer    (3 tools) - read-only code review
          ))
      (nucleus--refresh-open-gptel-buffers))))

(defun nucleus--validate-agent-tool-contracts ()
  "Validate that agent tool contracts are correctly enforced.
Signals an error if any agent has incorrect tools."
  (when (and (boundp 'gptel-agent--agents) gptel-agent--agents)
    (let ((expected
           (mapcar (lambda (c) (cons (car c) (nucleus-get-tools (cdr c))))
                   nucleus-agent-tool-contracts)))
      (cl-loop for (agent-name . expected-tools) in expected
               for cell = (assoc agent-name gptel-agent--agents)
               when cell
               do (let* ((actual-tools (plist-get (cdr cell) :tools))
                         (actual-names (if (listp (car actual-tools))
                                           actual-tools
                                         (mapcar (lambda (tool) (if (stringp tool) tool (plist-get tool :name)))
                                                 actual-tools)))
                         (missing (seq-difference expected-tools actual-names #'string=))
                         (extra (seq-difference actual-names expected-tools #'string=)))
                    (when (or missing extra)
                      (warn "[nucleus] Agent tool contract violation for '%s': missing=[%s] extra=[%s]"
                            agent-name
                            (if missing (string-join missing ", ") "none")
                            (if extra (string-join extra ", ") "none"))))))))

(defun nucleus--after-agent-update (&rest _)
  "Post-agent-update hook: re-register directives and override presets."
  (when (featurep 'gptel)
    (nucleus--register-gptel-directives)
    (nucleus--override-gptel-agent-presets)
    ;; Validate agent tool contracts after update
    (ignore-errors (nucleus--validate-agent-tool-contracts))))

(defun nucleus--around-apply-preset (orig preset &optional setter)
  "Around advice: ensure `gptel--preset' is set even when PRESET is a raw plist.

`gptel--transform-apply-preset' passes a plist directly to
`gptel--apply-preset', bypassing the name→plist lookup that normally sets
`gptel--preset'.  This advice finds the matching preset name by scanning
`gptel--known-presets' for a cell whose cdr is `eq' to PRESET, then sets
`gptel--preset' buffer-locally before delegating."
  (when (and (consp preset)
             setter
             (boundp 'gptel--known-presets))
    (when-let* ((cell (cl-find preset gptel--known-presets
                               :key #'cdr :test #'eq)))
      (set (make-local-variable 'gptel--preset) (car cell))))
  (funcall orig preset setter))

(defun nucleus--after-transform-apply-preset (&rest args)
  "After advice on `gptel--transform-apply-preset': sync gptel--preset from header.

Fallback for when the plist eq-lookup in `nucleus--around-apply-preset'
fails (e.g. plist was re-consed between registration and send).  Reads
`gptel-backend' and `gptel-tools' to infer the active preset by checking
which nucleus preset's tool list matches the buffer-local tools.
It also updates the original chat buffer so the header-line reflects the new mode."
  (let* ((fsm (car args))
         (orig-buf (and fsm (fboundp 'gptel-fsm-info) (plist-get (gptel-fsm-info fsm) :buffer))))
    (when (and (boundp 'gptel--known-presets)
               (boundp 'gptel-tools))
      (let* ((current-tools (if (fboundp 'nucleus--tool-names-from-tools)
                                (nucleus--tool-names-from-tools gptel-tools)
                              gptel-tools))
             (agent-tools (nucleus-get-tools :nucleus))
             (plan-tools  (nucleus-get-tools :readonly))
             (tools-match-p (lambda (a b)
                              (and (= (length a) (length b))
                                   (null (seq-difference a b #'string=))
                                   (null (seq-difference b a #'string=)))))
             (inferred
              (cond
               ((funcall tools-match-p current-tools agent-tools) 'gptel-agent)
               ((funcall tools-match-p current-tools plan-tools)  'gptel-plan)
               (t nil))))
        (when inferred
          (let ((target-bufs (if (buffer-live-p orig-buf) (list (current-buffer) orig-buf) (list (current-buffer)))))
            (dolist (buf target-bufs)
              (with-current-buffer buf
                (when (not (eq (buffer-local-value 'gptel--preset buf) inferred))
                  (set (make-local-variable 'gptel--preset) inferred)
                  (setq nucleus-agent-default inferred)
                  (when (fboundp 'gptel--apply-preset)
                    ;; Apply preset to original buffer to make the mode switch permanent
                    (gptel--apply-preset inferred (lambda (sym val) (set (make-local-variable sym) val))))
                  (when (bound-and-true-p gptel-mode)
                    (nucleus--header-line-apply-preset-label)))))))))))

(defun nucleus--after-apply-preset (&rest _)
  "Nucleus post-preset hook: tool sanity check and header line refresh.

Runs as :after advice on `gptel--apply-preset'."
  (when (and (boundp 'gptel--preset)
             gptel--preset
             (bound-and-true-p gptel-mode)
             (memq gptel--preset '(gptel-plan gptel-agent))
             (bound-and-true-p nucleus-tools-sanity-check)
             nucleus-tools-sanity-check)
    (nucleus-tool-sanity-check gptel--preset "after-preset"))
  (nucleus--header-line-apply-preset-label))

;;; Agent Directory Setup

(defun nucleus-presets-setup-agents ()
  "Setup agent directories and update gptel-agent."
  (when (featurep 'gptel-agent)
    (let* ((base-dir (if (boundp 'minimal-emacs-user-directory)
                         minimal-emacs-user-directory
                       user-emacs-directory))
           (user-agents (expand-file-name "assistant/agents/" base-dir))
           (proj-agents (expand-file-name "assistant/agents/"
                                          (nucleus--project-root)))
           (skill-dir (expand-file-name "assistant/skills/" base-dir))
           (agent-dirs (seq-remove
                        (lambda (dir)
                          (member dir (list user-agents proj-agents)))
                        (if (boundp 'gptel-agent-dirs)
                            gptel-agent-dirs
                          '()))))
      (when (file-directory-p user-agents)
        (setq agent-dirs (append agent-dirs (list user-agents))))
      (when (file-directory-p proj-agents)
        (setq agent-dirs (append agent-dirs (list proj-agents))))
      (setq gptel-agent-dirs agent-dirs)
      (when (and (boundp 'gptel-agent-skill-dirs)
                 (file-directory-p skill-dir))
        (add-to-list 'gptel-agent-skill-dirs skill-dir)))
    (when (fboundp 'gptel-agent-update)
      (gptel-agent-update))))

;;; Integration

(defun nucleus-presets-setup ()
  "Setup nucleus presets module.

Call this after gptel-agent loads."
  (nucleus-presets-setup-agents)
  (nucleus--override-gptel-agent-presets)
  
  ;; Register advice for agent and preset hooks
  (when (fboundp 'gptel-agent)
    (advice-add 'gptel-agent :around #'nucleus--agent-around))
  
  (when (fboundp 'gptel-agent-update)
    (advice-add 'gptel-agent-update :after #'nucleus--after-agent-update))
  
  (when (fboundp 'gptel--apply-preset)
    (advice-add 'gptel--apply-preset :around #'nucleus--around-apply-preset)
    (advice-add 'gptel--apply-preset :after  #'nucleus--after-apply-preset))
  (when (fboundp 'gptel--transform-apply-preset)
    (advice-add 'gptel--transform-apply-preset :after
                #'nucleus--after-transform-apply-preset))
  
  ;; Fix load-order issue: refresh open buffers after tools are registered
  ;; This ensures presets have access to all registered tools
  (when (boundp 'gptel-tools-after-register-hook)
    (add-hook 'gptel-tools-after-register-hook #'nucleus--refresh-open-gptel-buffers))
  ;; Also refresh now in case tools already registered
  (when (and (boundp 'gptel--known-tools)
             (hash-table-p gptel--known-tools)
             (> (hash-table-count gptel--known-tools) 0))
    (nucleus--refresh-open-gptel-buffers)))

;;; Footer

(provide 'nucleus-presets)

;;; nucleus-presets.el ends here
