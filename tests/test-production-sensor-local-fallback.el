;;; test-production-sensor-local-fallback.el --- Tests for local sensor layer -*- lexical-binding: t; -*-
;;
;; Verifies the user-feedback and support-ticket functions provide meaningful
;; local signals when external APIs (Slack, Zendesk) are not configured.
;; YC Sensor layer: real business context from local reality, not just stubs.

;;; Code:

(require 'ert)

;; Load the module under test
(load-file (expand-file-name "lisp/modules/gptel-auto-workflow-production-metrics.el"
                             default-directory))

;; Reset external hooks (in case prior tests set them)
(setq gptel-auto-workflow--external-user-feedback-fn nil
      gptel-auto-workflow--external-support-tickets-fn nil)

;; Mock: simulate gh CLI not being available
(defvar test-sensor--gh-available t)

(defun test-sensor--fake-executable-find (cmd)
  (if (and (string= cmd "gh") test-sensor--gh-available)
      "/fake/gh"
    nil))

(ert-deftest test-sensor/user-feedback-with-gh-unavailable-returns-zero ()
  "When gh CLI not available, user-feedback returns 0.0 (neutral)."
  (let ((test-sensor--gh-available nil)
        (executable-find-orig (symbol-function 'executable-find)))
    (unwind-protect
        (progn
          (fset 'executable-find #'test-sensor--fake-executable-find)
          (let ((result (gptel-auto-workflow--query-user-feedback "lisp/modules/foo.el")))
            (should (= result 0.0))))
      (fset 'executable-find executable-find-orig))))

(ert-deftest test-sensor/support-tickets-counts-error-log-hits ()
  "Support-tickets counts error log entries mentioning target."
  (let* ((tmp-dir (make-temp-file "ov5-test-" t))
         (root tmp-dir)
         (log-dir (expand-file-name "var/log/" tmp-dir))
         (target "gptel-ext-retry"))
    (unwind-protect
        (progn
          (make-directory log-dir t)
          (with-temp-file (expand-file-name "emacs-test.log" log-dir)
            (insert "2026-06-07T10:00:00 [error] test
2026-06-07T10:01:00 [error] gptel-ext-retry: parens
2026-06-07T10:02:00 [error] gptel-ext-retry: parens again
2026-06-07T10:03:00 [error] gptel-ext-retry: still broken
2026-06-07T10:04:00 [error] unrelated
"))
          (let ((gptel-auto-workflow--expand-workspace-path
                 (lambda (_) root)))
            (let ((result (gptel-auto-workflow--query-support-tickets
                           (expand-file-name target root))))
              (should (>= result 1))
              (should (<= result 10)))))
      (delete-directory tmp-dir t))))

(ert-deftest test-sensor/support-tickets-caps-at-10 ()
  "Support-tickets count is capped at 10 (sanity bound)."
  (let* ((tmp-dir (make-temp-file "ov5-test-" t))
         (root tmp-dir)
         (log-dir (expand-file-name "var/log/" tmp-dir))
         (target "gptel-ext-retry"))
    (unwind-protect
        (progn
          (make-directory log-dir t)
          (with-temp-file (expand-file-name "emacs-test.log" log-dir)
            (dotimes (i 50)
              (insert (format "2026-06-07T10:%02d:00 [error] gptel-ext-retry: hit %d\n" i i))))
          (let ((gptel-auto-workflow--expand-workspace-path
                 (lambda (_) root)))
            (let ((result (gptel-auto-workflow--query-support-tickets
                           (expand-file-name target root))))
              (should (= result 10)))))
      (delete-directory tmp-dir t))))

(ert-deftest test-sensor/user-feedback-external-hook-overrides ()
  "External user-feedback hook takes precedence over local fallback."
  (let ((gptel-auto-workflow--external-user-feedback-fn
         (lambda (_target) 0.7)))
    (let ((result (gptel-auto-workflow--query-user-feedback "anything.el")))
      (should (= result 0.7)))))

(provide 'test-production-sensor-local-fallback)
;;; test-production-sensor-local-fallback.el ends here
