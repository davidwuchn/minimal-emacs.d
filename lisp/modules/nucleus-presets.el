;;; nucleus-presets.el --- Preset management for nucleus -*- lexical-binding: t; -*-

;; Author: David Wu
;; Version: 1.0.0
;;
;; Preset management for nucleus gptel-agent (plan/agent toggle).

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

;;; Customization

(defgroup nucleus-presets nil
  "Preset management for nucleus."
  :group 'nucleus)

;;; Internal Variables

(defvar nucleus-agent-default 'gptel-plan
  "Default gptel agent preset. Use `nucleus-agent-toggle' to switch.")

(defvar nucleus-hidden-directives
  '(explorer reviewer chatTitle compact init skillCreate completion rewrite)
  "Directives to hide from the transient menu.")

;;; Preset Functions

(defun nucleus--effective-preset ()
  "Return the active gptel preset, preferring `gptel--preset' when available."
  (if (and (boundp 'gptel--preset)
           (memq gptel--preset '(gptel-plan gptel-agent)))
      gptel--preset
    nucleus-agent-default))

(defun nucleus--ensure-directory (path)
  "Return PATH coerced to an existing directory path."
  (let* ((expanded (expand-file-name (or path default-directory)))
         (dir (if (file-directory-p expanded)
                  expanded
                (file-name-directory expanded))))
    (file-name-as-directory dir)))

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

(defun nucleus--override-gptel-agent-presets ()
  "Make gptel-agent's Plan/Agent presets use nucleus system prompts and toolsets."
  (when (and (fboundp 'gptel-get-preset)
             (fboundp 'gptel-make-preset))
    (let* ((agent-backend (and (boundp 'gptel--dashscope)
                               gptel--dashscope))
           (preferred-backend agent-backend)
           ;; Different models for agent (coding) vs plan (architecture)
           (agent-model 'glm-5)
           (plan-model 'qwen3.5-plus))
      
      ;; Override gptel-agent preset
      (when-let ((agent (gptel-get-preset 'gptel-agent)))
        (let ((plist (copy-sequence agent)))
          (setq plist (plist-put plist :system 'nucleus-gptel-agent))
          (setq plist (plist-put plist :description
                                 "Nucleus execution agent — full tool access, code changes"))
          (setq plist (plist-put plist :tools
                                 (nucleus-get-tools :nucleus)))
          (when agent-model
            (setq plist (plist-put plist :model agent-model))
            (setq plist (plist-put plist :backend preferred-backend)))
          (apply #'gptel-make-preset 'gptel-agent plist)))
      
      ;; Override gptel-plan preset
      (when-let ((plan (gptel-get-preset 'gptel-plan)))
        (let ((plist (copy-sequence plan)))
          (setq plist (plist-put plist :system 'nucleus-gptel-plan))
          (setq plist (plist-put plist :description
                                 "Nucleus planning agent — read-only, architecture & research"))
          (setq plist (plist-put plist :tools
                                 (nucleus-get-tools :readonly)))
          (when plan-model
            (setq plist (plist-put plist :model plan-model))
            (setq plist (plist-put plist :backend preferred-backend)))
          (apply #'gptel-make-preset 'gptel-plan plist)))
      
      ;; Patch subagents in gptel-agent--agents
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
         (patch-agent "executor" (nucleus-get-tools :nucleus))
         (patch-agent "researcher" (nucleus-get-tools :researcher))
         (patch-agent "introspector" (nucleus-get-tools :readonly))
         (patch-agent "explorer" (nucleus-get-tools :explorer))
         (patch-agent "reviewer" (nucleus-get-tools :reviewer))
         ;; Validate immediately after patching
         (when (and (boundp 'nucleus-tools-strict-validation)
                    nucleus-tools-strict-validation)
           (nucleus--validate-agent-tool-contracts))
         ;; Agent tool contracts:
         ;; - executor: full action tools for code changes (21 tools)
         ;; - researcher: repo exploration + web research + skill loading (18 tools)
         ;; - introspector: Emacs introspection tools (15 tools)
         ;; - explorer: minimal read-only set for codebase exploration (3 tools)
         ;; - reviewer: minimal read-only set for code review (3 tools)
         )))))

(defun nucleus--validate-agent-tool-contracts ()
  "Validate that agent tool contracts are correctly enforced.
Signals an error if any agent has incorrect tools."
  (when (and (boundp 'gptel-agent--agents) gptel-agent--agents)
    (let ((expected
           `(("executor" . ,(nucleus-get-tools :nucleus))
             ("researcher" . ,(nucleus-get-tools :researcher))
             ("introspector" . ,(nucleus-get-tools :readonly))
             ("explorer" . ,(nucleus-get-tools :explorer))
             ("reviewer" . ,(nucleus-get-tools :reviewer)))))
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
                #'nucleus--after-transform-apply-preset)))

;;; Footer

(provide 'nucleus-presets)

;;; nucleus-presets.el ends here
