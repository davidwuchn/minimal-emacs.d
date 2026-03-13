;;; gptel-ext-tool-permits.el --- Tool confirmation modes -*- no-byte-compile: t; lexical-binding: t -*-

;;; Commentary:
;; Tool confirmation system with per-tool permit memory.
;;
;; Two modes:
;;   auto        → gptel-confirm-tool-calls nil   (no confirmation)
;;   confirm-all → gptel-confirm-tool-calls t     (confirm every call)
;;
;; Per-tool permit memory: once you approve a tool in confirm-all mode,
;; it's remembered for the Emacs session. Toggle clears permits.

;;; Code:

(require 'gptel)

;;; --- State ---

(defvar my/gptel-confirm-mode 'auto
  "Current confirmation mode: `auto' or `confirm-all'.")

(defvar my/gptel-permitted-tools (make-hash-table :test 'equal)
  "Session-scoped set of permitted tool names.
Keys are tool name strings, values are t.")

;;; --- Core API ---

(defun my/gptel-tool-permitted-p (tool-name)
  "Return non-nil if TOOL-NAME has been permitted this session."
  (gethash tool-name my/gptel-permitted-tools))

(defun my/gptel-permit-tool (tool-name)
  "Permit TOOL-NAME for the rest of this Emacs session."
  (puthash tool-name t my/gptel-permitted-tools))

(defun my/gptel-clear-permits ()
  "Clear all per-tool permits."
  (clrhash my/gptel-permitted-tools))

(defun my/gptel--sync-to-upstream ()
  "Sync `my/gptel-confirm-mode' to upstream `gptel-confirm-tool-calls'."
  (let ((val (if (eq my/gptel-confirm-mode 'auto) nil t)))
    (setq gptel-confirm-tool-calls val)
    (setq-default gptel-confirm-tool-calls val)
    (dolist (b (buffer-list))
      (with-current-buffer b
        (when (derived-mode-p 'gptel-mode)
          (setq-local gptel-confirm-tool-calls val))))))

;;; --- User Commands ---

;;;###autoload
(defun my/gptel-toggle-confirm ()
  "Toggle between auto and confirm-all modes.
Switching to confirm-all clears all per-tool permits."
  (interactive)
  (setq my/gptel-confirm-mode
        (if (eq my/gptel-confirm-mode 'auto) 'confirm-all 'auto))
  (when (eq my/gptel-confirm-mode 'confirm-all)
    (my/gptel-clear-permits))
  (my/gptel--sync-to-upstream)
  (message "Tool confirmation: %s%s"
           (if (eq my/gptel-confirm-mode 'auto) "AUTO" "CONFIRM-ALL")
           (if (eq my/gptel-confirm-mode 'auto)
               ""
             (format " (%d tools permitted)"
                     (hash-table-count my/gptel-permitted-tools)))))

;;;###autoload
(defun my/gptel-show-permits ()
  "Show currently permitted tools."
  (interactive)
  (if (zerop (hash-table-count my/gptel-permitted-tools))
      (message "No tools permitted (mode: %s)" my/gptel-confirm-mode)
    (message "Permitted tools: %s (mode: %s)"
             (string-join (hash-table-keys my/gptel-permitted-tools) ", ")
             my/gptel-confirm-mode)))

;;;###autoload
(defun my/gptel-emergency-stop ()
  "Emergency stop: abort all requests, clear permits, switch to confirm-all.

Use this when the agent is misbehaving or you need immediate control back."
  (interactive)
  (my/gptel-clear-permits)
  (setq my/gptel-confirm-mode 'confirm-all)
  (my/gptel--sync-to-upstream)
  (when (fboundp 'my/gptel-abort-here)
    (my/gptel-abort-here))
  (message "EMERGENCY STOP - Permits cleared, confirm-all mode, requests aborted"))

;;;###autoload
(defun my/gptel-health-check ()
  "Show tool system status: mode, permits, preset, registered tools."
  (interactive)
  (let* ((mode my/gptel-confirm-mode)
         (permits (hash-table-count my/gptel-permitted-tools))
         (preset (and (boundp 'gptel--preset) gptel--preset))
         (tools (and (boundp 'gptel-tools) (length gptel-tools)))
         (active-procs
          (cl-count-if (lambda (p)
                         (and (process-live-p p)
                              (or (process-get p 'my/gptel-managed)
                                  (string-prefix-p "gptel-" (process-name p)))))
                       (process-list))))
    (message "Tool Health: %s | Permits: %d | Preset: %s | Tools: %s | Active: %d"
             (if (eq mode 'auto) "AUTO" "CONFIRM")
             permits
             (or preset "none")
             (or tools 0)
             active-procs)))

;;; --- Setup ---

(defun my/gptel-setup-tool-ui ()
  "Initialize tool confirmation system."
  (my/gptel--sync-to-upstream)
  (message "Tool UI: %s" my/gptel-confirm-mode))

(with-eval-after-load 'gptel
  (my/gptel-setup-tool-ui))

(provide 'gptel-ext-tool-permits)

;;; gptel-ext-tool-permits.el ends here
