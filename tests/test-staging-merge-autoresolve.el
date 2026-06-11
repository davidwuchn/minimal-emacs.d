;;; test-staging-merge-autoresolve.el --- Tests for staging-merge auto-resolver -*- lexical-binding: t; no-byte-compile: t; -*-
;;
;; Verifies the cherry-pick conflict auto-resolver picks the right
;; strategy per file type. This is the biggest keep-rate lever: most
;; staging-merge-failed events are real git conflicts, and most conflicts
;; are in .md docs where the optimize branch is the source of truth.

;;; Code:

(require 'ert)
(require 'cl-lib)

(load-file (expand-file-name "lisp/modules/gptel-tools-agent-staging-merge.el"
                             default-directory))

;; Mock git-result: returns (output . exit-code). The autoresolver calls
;; git checkout, git add, git commit, etc. We want to capture what was
;; called and synthesize responses.
(defvar test-autoresolve--git-calls '()
  "List of git commands called.")
(defvar test-autoresolve--git-results '()
  "Alist of (regex-match . (output . exit-code)) responses.")
(defvar test-autoresolve--auto-resolved '()
  "Files successfully auto-resolved.")
(defvar test-autoresolve--manual-required '()
  "Files requiring manual review.")
(defvar test-autoresolve--events '()
  "List of events (e.g. \\='committed).")

(defvar test-autoresolve--diff-stat-response
  "100 files changed, 5000 insertions(+), 3000 deletions(-)"
  "Default diff-stat response used by the mock git-cmd.
Tests that need fast-track eligibility should bind this to a small diff stat.")

(defun test-autoresolve--mock-git (args &optional _timeout)
  "Mock gptel-auto-workflow--git-cmd (returns string output).
The real function signature is (CMD &optional TIMEOUT), so ARGS is the
cmd string itself (not a list). We pattern-match on ARGS directly."
  (push args test-autoresolve--git-calls)
  ;; Side effects based on pattern — cond returns the matched value
  (cond
   ((string-match "cherry-pick --abort" args) "")
   ((string-match "git checkout --theirs \\(.+\\)$" args)
    (let ((file (match-string 1 args)))
      (if (string-match "\\.md$" file)
          (push file test-autoresolve--auto-resolved)
        (push file test-autoresolve--manual-required)))
    "")
   ((string-match "git diff --stat" args)
    (or test-autoresolve--diff-stat-response ""))
   (t "")))

(defun test-autoresolve--mock-git-result (args &optional _timeout)
  "Mock gptel-auto-workflow--git-result (returns (output . exit-code) cons).
ARGs is the cmd string itself, not a list. Also tracks committed event
when a commit succeeds."
  (cond
   ((string-match "git rev-parse %s" args) '("abc123def456" . 0))
   ((string-match "git rev-parse --verify.*\\^2" args) '("" . 1))
   ((string-match "git commit" args)
    (push 'committed test-autoresolve--events)
    '("" . 0))
   (t '("" . 0))))

;; Required globals for the autoresolver
(setq gptel-auto-workflow--skip-submodule-sync-env "")

;; Helper macro: bind the git mocks with proper isolation. The fset-based
;; approach leaks into other tests and breaks them. cl-letf ensures
;; the mocks are restored after each test.
(defmacro test-autoresolve--with-git-mocks (&rest body)
  "Run BODY with git-cmd and git-result mocked for the test."
  `(let ((test-autoresolve--git-calls '())
         (test-autoresolve--auto-resolved '())
         (test-autoresolve--manual-required '())
         (test-autoresolve--events '())
         (test-autoresolve--diff-stat-response
          "100 files changed, 5000 insertions(+), 3000 deletions(-)"))
     (cl-letf (((symbol-function 'gptel-auto-workflow--git-cmd)
                #'test-autoresolve--mock-git)
               ((symbol-function 'gptel-auto-workflow--git-result)
                #'test-autoresolve--mock-git-result))
       ,@body)))

;; Restore the real git functions that fset would have polluted.
;; Without this, all tests loaded after this file see the mock.
(when (eq (symbol-function 'gptel-auto-workflow--git-cmd)
          #'test-autoresolve--mock-git)
  (fset 'gptel-auto-workflow--git-cmd
        (lambda (cmd &optional timeout) "")))
(when (eq (symbol-function 'gptel-auto-workflow--git-result)
          #'test-autoresolve--mock-git-result)
  (fset 'gptel-auto-workflow--git-result
        (lambda (cmd &optional timeout) '("" . 0))))

(ert-deftest test-autoresolve/mocks-restored-after-test ()
  "Mocks must be scoped per-test (via cl-letf), not global (fset).
Bug: the original tests in this file used (fset ...) which leaks the
mock into other tests' execution. After switching to cl-letf, this
test verifies the git-cmd / git-result symbols are NOT bound to the
test mocks by the time other tests run."
  (should (not (eq (symbol-function 'gptel-auto-workflow--git-cmd)
                  #'test-autoresolve--mock-git)))
  (should (not (eq (symbol-function 'gptel-auto-workflow--git-result)
                  #'test-autoresolve--mock-git-result))))

(ert-deftest test-autoresolve/only-md-files-all-resolved ()
  "All .md files → all auto-resolved, 0 manual required."
  (test-autoresolve--with-git-mocks
   (let ((result (gptel-auto-workflow--try-autoresolve-conflicts
                 "mementum/knowledge/foo.md\nmementum/knowledge/bar.md"
                 "optimize/test"
                 "Merge test"
                 30)))
     (should (= 2 (car result)))
     (should (= 0 (cdr result)))
     (should (member 'committed test-autoresolve--events)))))

(ert-deftest test-autoresolve/el-files-require-manual-review ()
  "All .el files with large diff-stat (not fast-track eligible) → 0 auto-resolved, all manual required."
  (test-autoresolve--with-git-mocks
   (let ((result (gptel-auto-workflow--try-autoresolve-conflicts
                 "lisp/modules/foo.el\nlisp/modules/bar.el"
                 "optimize/test"
                 "Merge test"
                 30)))
     (should (= 0 (car result)))
     (should (= 2 (cdr result)))
     (should (not (member 'committed test-autoresolve--events))))))

(ert-deftest test-autoresolve/mixed-files-partial-resolve ()
  "Mixed .md and .el → .md auto-resolved, .el manual required, NO commit."
  (test-autoresolve--with-git-mocks
   (let ((result (gptel-auto-workflow--try-autoresolve-conflicts
                 "mementum/knowledge/foo.md\nlisp/modules/bar.el"
                 "optimize/test"
                 "Merge test"
                 30)))
     (should (= 1 (car result)))
     (should (= 1 (cdr result)))
     ;; When there are manual-required files, we DON'T commit
     (should (not (member 'committed test-autoresolve--events))))))

(ert-deftest test-autoresolve/el-files-auto-resolved-when-fast-track ()
  "All .el files with small diff-stat (fast-track eligible) → all auto-resolved."
  (test-autoresolve--with-git-mocks
   (let ((test-autoresolve--diff-stat-response "1 file changed, 5 insertions(+)"))
     (let ((result (gptel-auto-workflow--try-autoresolve-conflicts
                   "lisp/modules/foo.el\nlisp/modules/bar.el"
                   "optimize/test"
                   "Merge test"
                   30)))
       (should (= 2 (car result)))
       (should (= 0 (cdr result)))
       (should (member 'committed test-autoresolve--events))))))

(ert-deftest test-autoresolve/fast-track-boundary-at-3-files ()
  "3 files, 49 lines (boundary) → fast-track eligible, .el auto-resolved."
  (test-autoresolve--with-git-mocks
   (let ((test-autoresolve--diff-stat-response
          " foo.el | 20 +-\n bar.el | 15 +-\n baz.md | 14 +-\n 3 files changed, 25 insertions(+), 24 deletions(-)"))
     (let ((result (gptel-auto-workflow--try-autoresolve-conflicts
                   "lisp/modules/foo.el"
                   "optimize/test"
                   "Merge test"
                   30)))
       (should (= 1 (car result)))
       (should (= 0 (cdr result)))))))

(ert-deftest test-autoresolve/fast-track-ineligible-at-4-files ()
  "4 files → fast-track ineligible, .el files require manual review."
  (test-autoresolve--with-git-mocks
   (let ((test-autoresolve--diff-stat-response
          " a.el | 1 +\n b.el | 1 +\n c.el | 1 +\n d.el | 1 +\n 4 files changed, 4 insertions(+)"))
     (let ((result (gptel-auto-workflow--try-autoresolve-conflicts
                   "lisp/modules/foo.el"
                   "optimize/test"
                   "Merge test"
                   30)))
       (should (= 0 (car result)))
       (should (= 1 (cdr result)))))))

(provide 'test-staging-merge-autoresolve)
;;; test-staging-merge-autoresolve.el ends here
