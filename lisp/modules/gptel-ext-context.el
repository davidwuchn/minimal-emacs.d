;;; gptel-ext-context.el --- Auto-compact gptel buffers -*- lexical-binding: t; -*-

;; Author: David Wu
;; Version: 2.0.0
;;
;; Auto-compaction: monitors gptel buffer size and triggers LLM-based
;; summarization when tokens approach the context window threshold.

;;; Code:

(require 'gptel)
(require 'gptel-request)
(require 'gptel-ext-context-cache)

;;; Customization

(defgroup my/gptel-auto-compact nil
  "Auto-compact gptel buffers when context grows too large."
  :group 'gptel)

(defcustom my/gptel-auto-compact-enabled t
  "Whether to auto-compact gptel buffers when they grow too large."
  :type 'boolean
  :group 'my/gptel-auto-compact)

(defcustom my/gptel-auto-compact-threshold 0.75
  "Fraction of context window at which to compact."
  :type 'number
  :group 'my/gptel-auto-compact)

(defcustom my/gptel-auto-compact-min-chars 4000
  "Minimum buffer size (chars) before auto-compacting."
  :type 'integer
  :group 'my/gptel-auto-compact)

(defcustom my/gptel-auto-compact-min-interval 45
  "Minimum seconds between auto-compactions per buffer."
  :type 'integer
  :group 'my/gptel-auto-compact)

;;; Internal Variables

(defvar-local my/gptel-auto-compact-running nil
  "Non-nil while auto-compaction is in progress for this buffer.")

(defvar-local my/gptel-auto-compact-last-run nil
  "Time of the last auto-compaction for this buffer.")

;;; Helpers

(defun my/gptel--compact-safe-p ()
  "Return non-nil if auto-compact is safe for the current buffer."
  (let ((elapsed (and my/gptel-auto-compact-last-run
                      (float-time (time-subtract (current-time)
                                                 my/gptel-auto-compact-last-run)))))
    (and (not my/gptel-auto-compact-running)
         (or (null elapsed)
             (>= elapsed my/gptel-auto-compact-min-interval)))))

(defun my/gptel--auto-compact-needed-p ()
  "Return non-nil when current buffer should be compacted."
  (let* ((chars (buffer-size))
         (tokens (my/gptel--estimate-tokens chars))
         (window (my/gptel--context-window))
         (threshold (* window my/gptel-auto-compact-threshold)))
    (and my/gptel-auto-compact-enabled
         (bound-and-true-p gptel-mode)
         (my/gptel--compact-safe-p)
         (>= chars my/gptel-auto-compact-min-chars)
         (>= tokens threshold))))

(defun my/gptel--directive-text (sym)
  "Resolve directive SYM to a string."
  (let ((val (alist-get sym gptel-directives)))
    (cond
     ((functionp val) (funcall val))
     ((stringp val) val)
     (t nil))))

;;; Core

(defun my/gptel-auto-compact (_start _end)
  "Compact current gptel buffer when it grows too large."
  (when (my/gptel--auto-compact-needed-p)
    (let ((system (my/gptel--directive-text 'compact))
          (buf (current-buffer)))
      (when system
        (setq my/gptel-auto-compact-running t)
        (gptel-request (buffer-string)
          :system system
          :buffer buf
          :callback (lambda (response _info)
                      (with-current-buffer buf
                        (setq my/gptel-auto-compact-running nil)
                        (setq my/gptel-auto-compact-last-run (current-time))
                        (when (stringp response)
                          (let ((inhibit-read-only t))
                            (erase-buffer)
                            (insert response))))))))))

;;; Hook Registration

(add-hook 'gptel-post-response-functions #'my/gptel-auto-compact)

;;; Footer

(provide 'gptel-ext-context)
;;; gptel-ext-context.el ends here
