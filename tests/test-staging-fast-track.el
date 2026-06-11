;;; test-staging-fast-track.el --- Tests for fast-track staging eligibility -*- lexical-binding: t; no-byte-compile: t; -*-
;;
;; Tests for the fast-track staging pathway. Fast-track allows small verified
;; experiments to skip full staging verification (unit tests, submodule
;; hydration) and do syntax + behavioral checks only.

;;; Code:

(require 'ert)
(require 'cl-lib)

(load-file (expand-file-name "lisp/modules/gptel-tools-agent-staging-merge.el"
                             default-directory))

(defvar test-fast-track--diff-stat nil
  "Configurable diff stat response for testing.")

(defun test-fast-track--mock-git (cmd &optional _timeout)
  "Mock git-cmd that returns configured diff stat."
  (cond
   ((string-match "git diff --stat" cmd)
    (or test-fast-track--diff-stat ""))
   (t "")))

(defmacro test-fast-track--with-mock (&rest body)
  "Run BODY with git-cmd mocked and fast-track settings at defaults."
  `(let ((test-fast-track--diff-stat nil))
     (setq gptel-auto-workflow-fast-track-enabled t
           gptel-auto-workflow-fast-track-max-files 3
           gptel-auto-workflow-fast-track-max-lines 50)
     (cl-letf (((symbol-function 'gptel-auto-workflow--git-cmd)
                #'test-fast-track--mock-git))
       ,@body)))

(ert-deftest test-fast-track/disabled-globally ()
  "When fast-track is disabled, predicate returns nil."
  (test-fast-track--with-mock
   (setq gptel-auto-workflow-fast-track-enabled nil)
   (should-not (gptel-auto-workflow--fast-track-eligible-p "optimize/test"))))

(ert-deftest test-fast-track/single-file-small-change ()
  "1 file, 10 lines total → eligible."
  (test-fast-track--with-mock
   (setq test-fast-track--diff-stat " lisp/modules/foo.el | 5 insertions(+), 5 deletions(-)\n 1 file changed, 5 insertions(+), 5 deletions(-)")
   (should (gptel-auto-workflow--fast-track-eligible-p "optimize/test"))))

(ert-deftest test-fast-track/exactly-at-boundary ()
  "3 files, 50 lines total → eligible (boundary)."
  (test-fast-track--with-mock
   (setq test-fast-track--diff-stat " foo.el | 20 +-\n bar.el | 15 +-\n baz.md | 15 +-\n 3 files changed, 25 insertions(+), 25 deletions(-)")
   (should (gptel-auto-workflow--fast-track-eligible-p "optimize/test"))))

(ert-deftest test-fast-track/exceeds-file-limit ()
  "4 files → not eligible."
  (test-fast-track--with-mock
   (setq test-fast-track--diff-stat " a.el | 1 +\n b.el | 1 +\n c.el | 1 +\n d.el | 1 +\n 4 files changed, 4 insertions(+)")
   (should-not (gptel-auto-workflow--fast-track-eligible-p "optimize/test"))))

(ert-deftest test-fast-track/exceeds-line-limit ()
  "2 files, 60 lines total → not eligible."
  (test-fast-track--with-mock
   (setq test-fast-track--diff-stat " foo.el | 30 +-\n bar.el | 30 +-\n 2 files changed, 30 insertions(+), 30 deletions(-)")
   (should-not (gptel-auto-workflow--fast-track-eligible-p "optimize/test"))))

(ert-deftest test-fast-track/nil-diff-stat ()
  "When git returns empty/nil, predicate returns nil."
  (test-fast-track--with-mock
   (setq test-fast-track--diff-stat nil)
   (should-not (gptel-auto-workflow--fast-track-eligible-p "optimize/test"))))

(provide 'test-staging-fast-track)
;;; test-staging-fast-track.el ends here
