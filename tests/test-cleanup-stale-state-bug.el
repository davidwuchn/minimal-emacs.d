;;; test-cleanup-stale-state-bug.el --- Regression test for clrhash on nil worktree-state -*- lexical-binding: t; -*-

;; gptel-auto-workflow--cleanup-stale-state (line 1281) calls
;;   (clrhash gptel-auto-workflow--worktree-state)
;; unconditionally at line 1366.  But that var is declared as
;;   (defvar gptel-auto-workflow--worktree-state nil)
;; and may be nil in fresh sessions before any worktree state is set up.
;;
;; (clrhash nil) signals wrong-type-argument hash-table-p nil.
;; This was the actual cause of the "hash-table-p nil" error that
;; ab31920b7 added backtrace logging for in dispatch.
;;
;; TDD contract: any code path that calls clrhash/maphash/gethash etc.
;; on a defvar-defaulted-to-nil must guard with hash-table-p first.

(require 'ert)
(require 'cl-lib)

(unless (featurep 'gptel-tools-agent-main)
  (load (expand-file-name "lisp/modules/gptel-tools-agent-main.el"
                          default-directory)))

(ert-deftest test-cleanup-stale-state/clrhash-on-nil-is-undefined-behavior ()
  "Document the broken behavior so the fix is measurable.
This test currently PASSES because (clrhash nil) errors with
wrong-type-argument hash-table-p nil — which is exactly the bug.
After the fix (guard with hash-table-p), this test should be
replaced with one that asserts the cleanup function is safe."
  (let ((errored-with-hash-table-p nil))
    (condition-case err
        (clrhash nil)
      (wrong-type-argument
       ;; err shape: (wrong-type-argument PREDICATE-VALUE) where
       ;; PREDICATE is 'hash-table-p and VALUE is nil.
       (when (and (eq 'wrong-type-argument (car err))
                  (eq 'hash-table-p (cadr err))
                  (null (caddr err)))
         (setq errored-with-hash-table-p t))))
    (should errored-with-hash-table-p)))

(ert-deftest test-cleanup-stale-state/must-guard-clrhash-on-worktree-state ()
  "TDD red-phase test: the production code calls
(clrhash gptel-auto-workflow--worktree-state) at line 1366 without
guarding with hash-table-p.  When worktree-state is nil, this
signals wrong-type-argument hash-table-p nil.

This test fails on the current implementation, demonstrating the
bug.  The fix is to guard the clrhash call with hash-table-p.

We test the contract directly via the defun source — that the
clause `(clrhash gptel-auto-workflow--worktree-state)` is
preceded by a `when` or `unless` containing `hash-table-p
gptel-auto-workflow--worktree-state`."
  (let* ((file (locate-library "gptel-tools-agent-main"))
         (content (with-temp-buffer
                    (insert-file-contents file)
                    (buffer-string)))
         ;; Find all clrhash lines and check the surrounding context
         (lines (split-string content "\n"))
         (violations nil))
    (dolist (line lines)
      (when (string-match "clrhash\\s-+gptel-auto-workflow--worktree-state" line)
        ;; Check if previous 5 lines contain hash-table-p
        (let* ((idx (cl-position line lines :test 'string=))
               (start (max 0 (- idx 5)))
               (window (mapconcat #'identity (cl-subseq lines start (1+ idx)) "\n")))
          (unless (string-match-p "hash-table-p" window)
            (push line violations)))))
    (should (null violations))))
