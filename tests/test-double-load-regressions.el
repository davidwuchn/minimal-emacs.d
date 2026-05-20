;;; test-double-load-regressions.el --- Tests for double-load prevention guards -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests that bootstrap, research-cache, and projects.el are not loaded
;; twice by redundant load-file calls in the hot-reload chain.
;; Run with:
;;   emacs --batch -L tests -L lisp/modules -l test-double-load-regressions.el -f ert-run-tests-batch

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gptel-tools-agent-base)
(require 'gptel-tools-agent-main)

;; ─── Fix 1: bootstrap double-load guard in seed-live-root-load-path ───

(ert-deftest test-double-load/seed-load-path-guards-bootstrap-featurep ()
  "seed-live-root-load-path uses (unless (featurep ...) (load-file ...)).
After bootstrap is loaded once, the featurep guard prevents a second
load-file call."
  ;; Work with the GLOBAL features list (featurep C function bypasses let-bindings).
  ;; Remove the bootstrap feature globally for the test, then restore it.
  (let ((loaded-count 0)
        (bootstrap-sym 'gptel-auto-workflow-bootstrap))
    (unwind-protect
        (progn
          ;; Remove bootstrap from global features (if present from prior requires)
          (setq features (delq bootstrap-sym features))
          (cl-letf (((symbol-function 'load-file)
                     (lambda (file)
                       (when (string-match-p "gptel-auto-workflow-bootstrap\\.el" file)
                         (cl-incf loaded-count))
                       (provide bootstrap-sym))))
            ;; First call — should load bootstrap
            (gptel-auto-workflow--seed-live-root-load-path default-directory)
            (should (= loaded-count 1))
            ;; Second call — featurep is t, should NOT load bootstrap
            (gptel-auto-workflow--seed-live-root-load-path default-directory)
            (should (= loaded-count 1))))
      ;; Restore bootstrap feature
      (unless (memq bootstrap-sym features)
        (setq features (cons bootstrap-sym features))))))

(ert-deftest test-double-load/seed-load-path-still-calls-seed-load-path-twice ()
  "Even when bootstrap load-file is skipped (already loaded),
the seed-load-path function should still be called on every invocation."
  (let ((seed-called 0))
    (cl-letf (((symbol-function 'gptel-auto-workflow-bootstrap--seed-load-path)
               (lambda (_root) (cl-incf seed-called)))
              ((symbol-function 'load-file)
               (lambda (file)
                 (when (string-match-p "gptel-auto-workflow-bootstrap" file)
                   (provide 'gptel-auto-workflow-bootstrap)))))
      (gptel-auto-workflow--seed-live-root-load-path default-directory)
      (should (= seed-called 1))
      (gptel-auto-workflow--seed-live-root-load-path default-directory)
      (should (= seed-called 2)))))

;; ─── Fix 2: research-cache double-load guard in reload-live-support ───
;; This tests the featurep guard directly by checking that the function
;; correctly skips load-file when the feature is already declared.

(ert-deftest test-double-load/featurep-guard-syntax ()
  "The featurep guard should wrap the research-cache load-file call in
gptel-tools-agent-main.el, preventing double-loading."
  (let* ((repo-dir (or (getenv "DIR")
                       (locate-dominating-file default-directory ".git")))
         (file (expand-file-name "lisp/modules/gptel-tools-agent-main.el" repo-dir))
         (source (with-temp-buffer
                   (insert-file-contents file)
                   (buffer-string))))
    ;; The guard pattern (unless (featurep ...)) should exist
    (should (string-match-p
             "(unless (featurep 'gptel-auto-workflow-research-cache)"
             source))
    ;; The load-file for research-cache should appear AFTER the guard
    ;; (not as a standalone unconditional call)
    (let* ((guard-start (string-match
                         "(unless (featurep 'gptel-auto-workflow-research-cache)"
                         source))
           (guard-end (with-temp-buffer
                        (insert source)
                        (goto-char guard-start)
                        (forward-sexp)  ; skip past the entire (unless ...) form
                        (point))))
      ;; Within the guard body, there should be a load-file for research-cache
      (should (string-match-p
               "research-cache"
               (substring source guard-start guard-end)))
      ;; Before the guard start, there should NOT be an unconditional
      ;; load-file of research-cache (only guarded versions)
      (let ((before-guard (substring source 0 guard-start)))
        (dolist (line (split-string before-guard "\n"))
          (when (string-match-p "load-file[^)|\"]*research-cache" line)
            (ert-fail (format "Unprotected research-cache load-file found: %s" line)))))
      (message "TDD: research-cache guard wraps at %d-%d" guard-start guard-end))))

;; ─── Fix 3: cron script no longer has redundant projects.el load ───

(ert-deftest test-double-load/cron-eval-no-redundant-projects-load ()
  "The cron script's emacsclient --eval should not directly load projects.el
since reload-live-support already handles it."
  (let* ((repo-dir (or (getenv "DIR")
                       (locate-dominating-file default-directory ".git")))
         (cron-file (expand-file-name "scripts/run-auto-workflow-cron.sh" repo-dir))
         (found-pattern nil))
    (skip-unless (file-exists-p cron-file))
    (let ((script (with-temp-buffer
                    (insert-file-contents cron-file)
                    (buffer-string))))
      (dolist (line (split-string script "\n"))
        (when (string-match "printf.*load-file.*gptel-auto-workflow-projects" line)
          (setq found-pattern t)))
      (should-not found-pattern)
      (message "TDD: cron eval no longer has direct projects.el load-file: %s"
               (if found-pattern "FAIL" "OK")))))

(provide 'test-double-load-regressions)
;;; test-double-load-regressions.el ends here
