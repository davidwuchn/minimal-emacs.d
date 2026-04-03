;;; test-auto-workflow-batch.el --- Batch bootstrap test for auto-workflow -*- lexical-binding: t; -*-

;;; Commentary:
;; Verifies that auto-workflow modules can be loaded in batch mode and that
;; the cron entrypoints are available without relying on a running daemon.

;;; Code:

(require 'seq)
(require 'gptel-tools-agent)
(require 'gptel-auto-workflow-projects)
(require 'gptel-auto-workflow-strategic)

(defun test-auto-workflow-batch-run ()
  "Validate that auto-workflow bootstrap succeeds in batch mode."
  (let* ((checks `((status . ,(fboundp 'gptel-auto-workflow-status))
                   (cron-safe . ,(fboundp 'gptel-auto-workflow-cron-safe))
                   (workflow . ,(fboundp 'gptel-auto-workflow-run-all-projects))
                   (workflow-queue . ,(fboundp 'gptel-auto-workflow-queue-all-projects))
                   (research . ,(fboundp 'gptel-auto-workflow-run-all-research))
                   (research-queue . ,(fboundp 'gptel-auto-workflow-queue-all-research))
                   (mementum . ,(fboundp 'gptel-auto-workflow-run-all-mementum))
                   (mementum-queue . ,(fboundp 'gptel-auto-workflow-queue-all-mementum))
                   (instincts . ,(fboundp 'gptel-auto-workflow-run-all-instincts))
                   (instincts-queue . ,(fboundp 'gptel-auto-workflow-queue-all-instincts))))
         (missing (seq-remove #'cdr checks)))
    (princ "Auto-workflow batch bootstrap\n")
    (princ (format "Status: %S\n" (gptel-auto-workflow-status)))
    (dolist (entry checks)
      (princ (format "  %s: %s\n" (car entry) (if (cdr entry) "ok" "missing"))))
    (if missing
        (progn
          (princ (format "Missing entrypoints: %S\n" (mapcar #'car missing)))
          (kill-emacs 1))
      (kill-emacs 0))))

(provide 'test-auto-workflow-batch)
;;; test-auto-workflow-batch.el ends here
