;;; test-evolution-parens.el --- TDD: evolution module paren balance and loadability -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests that gptel-auto-workflow-evolution.el loads correctly after
;; paren balance fixes and ignore-errors guard.
;;
;; Run:
;;   emacs --batch -L tests -L lisp/modules \
;;         -l test-evolution-parens.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)

(ert-deftest test-evolution/paren-balance ()
  "The evolution file should have balanced parens (check-parens passes)."
  (let* ((repo-dir (locate-dominating-file default-directory ".git"))
         (evo-file (expand-file-name "lisp/modules/gptel-auto-workflow-evolution.el" repo-dir)))
    (skip-unless (file-exists-p evo-file))
    (with-temp-buffer
      (insert-file-contents evo-file)
      (emacs-lisp-mode)
      (condition-case err
          (progn
            (check-parens)
            (message "TDD: paren balance OK"))
        (user-error
         (ert-fail (format "Paren mismatch: %S" err)))))))

(ert-deftest test-evolution/read-all-sexps ()
  "All top-level sexps in the evolution file should be readable."
  (let* ((repo-dir (locate-dominating-file default-directory ".git"))
         (evo-file (expand-file-name "lisp/modules/gptel-auto-workflow-evolution.el" repo-dir)))
    (skip-unless (file-exists-p evo-file))
    (with-temp-buffer
      (insert-file-contents evo-file)
      (emacs-lisp-mode)
      (let ((sexp-count 0)
            (errors nil))
        (goto-char (point-min))
        (while (and (< (point) (point-max))
                    (not errors))
          (condition-case err
              (progn
                (read (current-buffer))
                (cl-incf sexp-count))
            (end-of-file nil)
            (error (setq errors (format "Read error at sexp %d: %S" sexp-count err)))))
        (if errors
            (ert-fail errors)
          (message "TDD: %d sexps read successfully" sexp-count))))))

(ert-deftest test-evolution/file-ends-at-top-level ()
  "The provide form should be at depth 0 (top-level)."
  (let* ((repo-dir (locate-dominating-file default-directory ".git"))
         (evo-file (expand-file-name "lisp/modules/gptel-auto-workflow-evolution.el" repo-dir)))
    (skip-unless (file-exists-p evo-file))
    (with-temp-buffer
      (insert-file-contents evo-file)
      (emacs-lisp-mode)
      (goto-char (point-min))
      (let ((provide-pos (search-forward "(provide 'gptel-auto-workflow-evolution)" nil t)))
        (skip-unless provide-pos)
        (let ((ppss (syntax-ppss (1- (match-beginning 0)))))
          (should (= (car ppss) 0))
          (message "TDD: provide at depth %d (expected 0)" (car ppss)))))))

(ert-deftest test-evolution/no-void-functions-on-load ()
  "Loading the evolution module (after gptel-tools-agent) should not error."
  (require 'gptel-tools-agent)
  (should (fboundp 'gptel-auto-workflow--worktree-base-root))
  (let ((errs nil))
    (condition-case err
        (progn
          (require 'gptel-auto-workflow-evolution)
          (message "TDD: evolution module loaded OK"))
      (error (setq errs (format "Load error: %S" err))))
    (should-not errs)
    (should (featurep 'gptel-auto-workflow-evolution))
    (should (fboundp 'gptel-auto-workflow--detect-minimal-pairs))
    (should (fboundp 'gptel-auto-workflow--score-knowledge-pages))
    (should (fboundp 'gptel-auto-workflow--generate-experiment-ontology))
    (should (fboundp 'gptel-auto-workflow--detect-hypothesis-conflicts))))

(provide 'test-evolution-parens)
;;; test-evolution-parens.el ends here
