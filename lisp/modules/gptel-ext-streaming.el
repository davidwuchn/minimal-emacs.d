;;; gptel-ext-streaming.el --- Streaming jit-lock protection -*- lexical-binding: t; -*-

;;; Commentary:
;; Fix: jit-lock error during streaming.
;; During streaming, gptel inserts text chunks into a markdown-mode buffer.
;; Each insert triggers jit-lock-after-change, which marks the region for
;; refontification.  On next redisplay, jit-lock--run-functions calls
;; font-lock-fontify-region, which invokes markdown-mode's syntax-propertize
;; and extend-region machinery.  With incomplete streaming content (e.g., an
;; open ``` fence without a closing one), markdown-code-block-at-pos returns
;; bogus values, causing nil to reach (max ...) or (min ...) in jit-lock,
;; producing: (jit-lock-function N) signaled (wrong-type-argument
;; integer-or-marker-p nil).
;;
;; Fix: suppress jit-lock errors unconditionally in gptel-mode buffers.
;; A streaming flag tracks when gptel is actively inserting chunks, but the
;; condition-case protection must NOT be gated on it: the most dangerous
;; refontification happens AFTER streaming ends — my/gptel--stream-clear-flag
;; calls jit-lock-refontify after clearing the flag, and upstream font-lock-flush
;; runs on post-response hooks.  Both can trigger errors on malformed markdown.
;; Using (bound-and-true-p gptel-mode) as the gate makes protection unconditional
;; for gptel buffers while leaving non-gptel buffers completely unaffected.

;;; Code:

(require 'gptel)

(defvar-local my/gptel--streaming-p nil
  "Non-nil while gptel is actively streaming into this buffer.")

(defun my/gptel--stream-set-flag (response info &optional _raw)
  "Set streaming flag when first text chunk arrives.
RESPONSE and INFO are from `gptel-curl--stream-insert-response'."
  (when (stringp response)
    (when-let* ((marker (plist-get info :position))
                (buf (marker-buffer marker)))
      (with-current-buffer buf
        (setq my/gptel--streaming-p t)))))

(advice-add 'gptel-curl--stream-insert-response :before
            #'my/gptel--stream-set-flag)

(defun my/gptel--stream-clear-flag (&rest _args)
  "Clear streaming flag after response completes."
  (setq my/gptel--streaming-p nil)
  ;; Force a full refontification now that text is complete.
  (when jit-lock-mode
    (jit-lock-refontify)))

(add-hook 'gptel-post-response-functions #'my/gptel--stream-clear-flag)

(defun my/gptel--jit-lock-safe (orig-fn start)
  "Catch jit-lock errors in gptel buffers.
Wrap ORIG-FN in `condition-case' when `gptel-mode' is active to prevent
markdown-mode fontification errors from propagating to the redisplay engine.

The protection is unconditional for gptel-mode buffers (not gated on the
streaming flag) because the most dangerous refontification happens AFTER
streaming completes: `my/gptel--stream-clear-flag' calls `jit-lock-refontify'
after clearing `my/gptel--streaming-p', and upstream `font-lock-flush' runs
on post-response hooks.  Both trigger jit-lock with incomplete/malformed
markdown content that can throw errors.  START is the position to fontify."
  (if (bound-and-true-p gptel-mode)
      (condition-case err
          (funcall orig-fn start)
        (error
         ;; Mark the region as needing refontification on next cycle.
         ;; jit-lock-after-change already did this, but the fontified=nil
         ;; property may have been overwritten by the failed attempt.
         (with-silent-modifications
           (put-text-property start (min (+ start 1) (point-max)) 'fontified nil))
         (when gptel-log-level
           (message "gptel: suppressed jit-lock error in gptel buffer: %S" err))))
    (funcall orig-fn start)))

(advice-add 'jit-lock-function :around #'my/gptel--jit-lock-safe)

(provide 'gptel-ext-streaming)
;;; gptel-ext-streaming.el ends here
