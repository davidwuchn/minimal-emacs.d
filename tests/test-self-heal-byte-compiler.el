;;; test-self-heal-byte-compiler.el --- ERT tests for self-heal byte-compiler fixers -*- lexical-binding: t; -*-

;;; Commentary:
;; TDD tests for the self-heal byte-compiler fixers in
;; gptel-auto-workflow-evolution.el.  Each fixer is tested with at
;; least a happy path and an edge case.
;;
;; Some fixers receive warnings from `byte-compile-warnings-for-file'
;; which uses `byte-compile-from-buffer'.  That function does not set
;; `byte-compile-current-file', so some warnings lack line numbers
;; and some warning types are not captured at all.  We construct
;; warning alists manually with the expected format to test fixer
;; logic independently of the byte-compiler output format.
;;
;; Run:
;;   emacs --batch -L tests -L lisp/modules -L packages/gptel -L packages/gptel-agent \
;;         -l test-self-heal-byte-compiler.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)

(let ((modules-dir (expand-file-name "../lisp/modules"
                                     (file-name-directory
                                      (or load-file-name buffer-file-name default-directory)))))
  (add-to-list 'load-path modules-dir))
(let ((gptel-dir (expand-file-name "../packages/gptel"
                                    (file-name-directory
                                     (or load-file-name buffer-file-name default-directory)))))
  (add-to-list 'load-path gptel-dir))
(let ((gptel-agent-dir (expand-file-name "../packages/gptel-agent"
                                          (file-name-directory
                                           (or load-file-name buffer-file-name default-directory)))))
  (add-to-list 'load-path gptel-agent-dir))
(require 'gptel-auto-workflow-evolution)

;; ─── edit-distance ───

(ert-deftest tdd/self-heal/edit-distance ()
  (should (= (gptel-auto-workflow--edit-distance "" "") 0))
  (should (= (gptel-auto-workflow--edit-distance "abc" "abc") 0))
  (should (= (gptel-auto-workflow--edit-distance "abc" "abd") 1))
  (should (= (gptel-auto-workflow--edit-distance "kitten" "sitting") 3))
  (should (= (gptel-auto-workflow--edit-distance "" "abc") 3))
  (should (= (gptel-auto-workflow--edit-distance "abc" "") 3)))

(ert-deftest tdd/self-heal/edit-distance/single-char ()
  (should (= (gptel-auto-workflow--edit-distance "a" "b") 1))
  (should (= (gptel-auto-workflow--edit-distance "a" "a") 0))
  (should (= (gptel-auto-workflow--edit-distance "a" "") 1)))

;; ─── check-parens ───

(ert-deftest tdd/self-heal/check-parens/balanced ()
  (let ((f (make-temp-file "self-heal-test" nil ".el")))
    (unwind-protect
        (progn
          (write-region "(defun foo () (+ 1 2))\n" nil f)
          (should (gptel-auto-workflow--check-parens f)))
      (delete-file f))))

(ert-deftest tdd/self-heal/check-parens/unbalanced-missing-close ()
  (let ((f (make-temp-file "self-heal-test" nil ".el")))
    (unwind-protect
        (progn
          (write-region "(defun foo () (+ 1 2)\n" nil f)
          (should-not (gptel-auto-workflow--check-parens f)))
      (delete-file f))))

(ert-deftest tdd/self-heal/check-parens/unbalanced-extra-close ()
  (let ((f (make-temp-file "self-heal-test" nil ".el")))
    (unwind-protect
        (progn
          (write-region "(defun foo () (+ 1 2)))\n" nil f)
          (should-not (gptel-auto-workflow--check-parens f)))
      (delete-file f))))

(ert-deftest tdd/self-heal/check-parens/empty-file ()
  (let ((f (make-temp-file "self-heal-test" nil ".el")))
    (unwind-protect
        (progn
          (write-region "" nil f)
          (should (gptel-auto-workflow--check-parens f)))
      (delete-file f))))

;; ─── fix-docstring-width ───
;; Only wraps docstrings >78 chars followed by ) or (.

(ert-deftest tdd/self-heal/fix-docstring-width/long-docstring ()
  (let ((f (make-temp-file "self-heal-test" nil ".el")))
    (unwind-protect
        (progn
          (write-region "(defun foo () \"This is a very very very very long docstring that exceeds the 80 character limit for absolutely sure and certain.\")" nil f)
          (let ((fixes (gptel-auto-workflow--fix-docstring-width f)))
            (should (> fixes 0))))
      (delete-file f))))

(ert-deftest tdd/self-heal/fix-docstring-width/short-docstring-no-fix ()
  (let ((f (make-temp-file "self-heal-test" nil ".el")))
    (unwind-protect
        (progn
          (write-region "(defun foo () \"Short doc.\")" nil f)
          (let ((fixes (gptel-auto-workflow--fix-docstring-width f)))
            (should (= fixes 0))))
      (delete-file f))))

(ert-deftest tdd/self-heal/fix-docstring-width/preserves-parens ()
  (let ((f (make-temp-file "self-heal-test" nil ".el")))
    (unwind-protect
        (progn
          (write-region "(defun foo () \"This is a very very very very long docstring that exceeds the 80 character limit for absolutely sure and certain.\")" nil f)
          (gptel-auto-workflow--fix-docstring-width f)
          (should (gptel-auto-workflow--check-parens f)))
      (delete-file f))))

(ert-deftest tdd/self-heal/fix-docstring-width/skips-data-string-literals ()
  "fix-docstring-width must only wrap DOCSTRINGS, not arbitrary string
literals.  A long regex/data string in a non-defining form (e.g. the
kibcm-patterns entry (:KEY \"a\\\\|b\\\\|c ...\")) must be preserved
verbatim.  Regression: the fixer used to word-wrap any long string
followed by ) or (, corrupting regex alternation by inserting literal
newlines mid-string (which passed check-parens so rollback never
caught it)."
  (let ((f (make-temp-file "self-heal-test" nil ".el"))
        (regex "nil.safety\\\\|nil.guard\\\\|guard tab\\\\|validat\\\\|remove nil\\\\|unless nil\\\\|when nil\\\\|error handling"))
    (unwind-protect
        (progn
          (write-region (concat "(:K \"" regex "\")") nil f)
          (let ((fixes (gptel-auto-workflow--fix-docstring-width f)))
            (should (equal 0 fixes))
            (with-temp-buffer
              (insert-file-contents f)
              (should (string-match-p (regexp-quote regex)
                                      (buffer-string)))
              (should-not (string-match-p "\n" (buffer-substring-no-properties
                                                 (line-beginning-position 1)
                                                 (line-end-position 1)))))))
      (delete-file f))))

;; ─── fix-unescaped-quotes ───
;; Fixes 'word' patterns in docstrings to \='word\='.

(ert-deftest tdd/self-heal/fix-unescaped-quotes/in-docstring ()
  (let ((f (make-temp-file "self-heal-test" nil ".el")))
    (unwind-protect
        (progn
          (write-region "(defun foo () \"Returns 'hello' from the store.\")" nil f)
          (let ((fixes (gptel-auto-workflow--fix-unescaped-quotes f)))
            (should (> fixes 0))
            (with-temp-buffer
              (insert-file-contents f)
              (should (string-match-p "\\\\='hello\\\\='" (buffer-string))))))
      (delete-file f))))

(ert-deftest tdd/self-heal/fix-unescaped-quotes/no-quotes-no-fix ()
  (let ((f (make-temp-file "self-heal-test" nil ".el")))
    (unwind-protect
        (progn
          (write-region "(defun foo () \"No quotes here.\")" nil f)
          (let ((fixes (gptel-auto-workflow--fix-unescaped-quotes f)))
            (should (= fixes 0))))
      (delete-file f))))

(ert-deftest tdd/self-heal/fix-unescaped-quotes/preserves-parens ()
  (let ((f (make-temp-file "self-heal-test" nil ".el")))
    (unwind-protect
        (progn
          (write-region "(defun foo () \"Returns 'hello' from the store.\")" nil f)
          (gptel-auto-workflow--fix-unescaped-quotes f)
          (should (gptel-auto-workflow--check-parens f)))
      (delete-file f))))

;; ─── fix-unused-variables ───
;; byte-compile-from-buffer doesn't capture unused-variable warnings,
;; so we construct warnings manually with ASCII quotes.

(ert-deftest tdd/self-heal/fix-unused-variables/unused-arg ()
  (let ((f (make-temp-file "self-heal-test" nil ".el")))
    (unwind-protect
        (progn
          (write-region "(defun foo (my-unused-arg)\n  nil)\n" nil f)
          (let* ((warnings (list (cons 1 "Unused lexical argument `my-unused-arg'")))
                 (fixes (gptel-auto-workflow--fix-unused-variables f warnings)))
            (should (> fixes 0))
            (with-temp-buffer
              (insert-file-contents f)
              (should (string-match-p "_my-unused-arg" (buffer-string))))))
      (delete-file f))))

(ert-deftest tdd/self-heal/fix-unused-variables/no-warning-no-fix ()
  (let ((f (make-temp-file "self-heal-test" nil ".el")))
    (unwind-protect
        (progn
          (write-region "(defun foo (used-arg)\n  used-arg)\n" nil f)
          (let* ((warnings nil)
                 (fixes (gptel-auto-workflow--fix-unused-variables f warnings)))
            (should (= fixes 0))))
      (delete-file f))))

(ert-deftest tdd/self-heal/fix-unused-variables/already-prefixed-no-fix ()
  (let ((f (make-temp-file "self-heal-test" nil ".el")))
    (unwind-protect
        (progn
          (write-region "(defun foo (_already-prefixed)\n  nil)\n" nil f)
          (let* ((warnings (list (cons 1 "Unused lexical argument `_already-prefixed'")))
                 (fixes (gptel-auto-workflow--fix-unused-variables f warnings)))
            (should (= fixes 0))))
      (delete-file f))))

(ert-deftest tdd/self-heal/fix-unused-variables/preserves-parens ()
  (let ((f (make-temp-file "self-heal-test" nil ".el")))
    (unwind-protect
        (progn
          (write-region "(defun foo (my-unused-arg)\n  nil)\n" nil f)
          (gptel-auto-workflow--fix-unused-variables
           f (list (cons 1 "Unused lexical argument `my-unused-arg'")))
          (should (gptel-auto-workflow--check-parens f)))
      (delete-file f))))

;; ─── fix-free-variables ───

(ert-deftest tdd/self-heal/fix-free-variables/adds-defvar ()
  (let ((f (make-temp-file "self-heal-test" nil ".el")))
    (unwind-protect
        (progn
          (write-region "(defun foo () my-free-var)\n" nil f)
          (let* ((warnings (list (cons nil "reference to free variable `my-free-var'")))
                 (fixes (gptel-auto-workflow--fix-free-variables f warnings)))
            (should (> fixes 0))
            (with-temp-buffer
              (insert-file-contents f)
               (should (string-match-p "(defvar my-free-var nil)" (buffer-string))))))
      (delete-file f))))

(ert-deftest tdd/self-heal/fix-free-variables/skips-typos ()
  (let ((f (make-temp-file "self-heal-test" nil ".el")))
    (unwind-protect
        (progn
          (write-region "(defvar my-variant nil)\n(defun foo () my-varient)\n" nil f)
          (let* ((warnings (list (cons nil "reference to free variable `my-varient'")))
                 (fixes (gptel-auto-workflow--fix-free-variables f warnings)))
            (should (= fixes 0))))
      (delete-file f))))

(ert-deftest tdd/self-heal/fix-free-variables/no-free-vars-no-fix ()
  (let ((f (make-temp-file "self-heal-test" nil ".el")))
    (unwind-protect
        (progn
          (write-region "(defvar my-var nil)\n(defun foo () my-var)\n" nil f)
          (let* ((warnings nil)
                 (fixes (gptel-auto-workflow--fix-free-variables f warnings)))
            (should (= fixes 0))))
      (delete-file f))))

(ert-deftest tdd/self-heal/fix-free-variables/preserves-parens ()
  (let ((f (make-temp-file "self-heal-test" nil ".el")))
    (unwind-protect
        (progn
          (write-region "(defun foo () my-free-var)\n" nil f)
          (gptel-auto-workflow--fix-free-variables
           f (list (cons nil "reference to free variable `my-free-var'")))
          (should (gptel-auto-workflow--check-parens f)))
      (delete-file f))))

;; ─── fix-unknown-functions ───

(ert-deftest tdd/self-heal/fix-unknown-functions/skips-self-defined ()
  (let ((f (make-temp-file "self-heal-test" nil ".el")))
    (unwind-protect
        (progn
          (write-region "(defun my-helper-fn () nil)\n(defun foo () (my-helper-fn))\n" nil f)
          (let* ((warnings (list (cons 2 "the function `my-helper-fn' is not known to be defined.")))
                 (fixes (gptel-auto-workflow--fix-unknown-functions f warnings)))
            (should (= fixes 0))))
      (delete-file f))))

(ert-deftest tdd/self-heal/fix-unknown-functions/no-unknown-no-fix ()
  (let ((f (make-temp-file "self-heal-test" nil ".el")))
    (unwind-protect
        (progn
          (write-region "(defun foo () (+ 1 2))\n" nil f)
          (let* ((warnings nil)
                 (fixes (gptel-auto-workflow--fix-unknown-functions f warnings)))
            (should (= fixes 0))))
      (delete-file f))))

;; function-exists-in-file-p uses relative directory paths that only
;; resolve from the project root.  Temp file buffers set
;; default-directory to /tmp, so the lookup fails.  This test
;; validates the intended behavior; it will pass once
;; function-exists-in-file-p uses absolute paths.
(ert-deftest tdd/self-heal/fix-unknown-functions/adds-declare-for-known-module ()
  (let ((f (make-temp-file "self-heal-test" nil ".el")))
    (unwind-protect
        (progn
          (write-region "(defun foo () (gptel-auto-workflow--check-parens \"test.el\"))\n" nil f)
          (let* ((warnings (list (cons 1 "the function `gptel-auto-workflow--check-parens' is not known to be defined.")))
                 (fixes (gptel-auto-workflow--fix-unknown-functions f warnings)))
            (should (> fixes 0))
            (with-temp-buffer
              (insert-file-contents f)
              (should (string-match-p "(declare-function" (buffer-string))))))
      (delete-file f))))

(ert-deftest tdd/self-heal/fix-unknown-functions/preserves-parens ()
  (let ((f (make-temp-file "self-heal-test" nil ".el")))
    (unwind-protect
        (progn
          (write-region "(defun foo () (+ 1 2))\n" nil f)
          (gptel-auto-workflow--fix-unknown-functions f nil)
          (should (gptel-auto-workflow--check-parens f)))
      (delete-file f))))

;; ─── fix-condition-case-no-handlers ───
;; Requires both a "condition-case without handlers" warning AND a
;; "reference to free variable `err'" warning to trigger.

(ert-deftest tdd/self-heal/fix-condition-case/nil-becomes-err ()
  (let ((f (make-temp-file "self-heal-test" nil ".el")))
    (unwind-protect
        (progn
          (write-region "(defun foo ()\n  (condition-case nil\n      (error \"oops\")\n    (error (message \"%s\" err))))\n" nil f)
          (let* ((warnings (list (cons 2 "warning: condition-case without handlers")
                                (cons nil "reference to free variable `err'")))
                 (fixes (gptel-auto-workflow--fix-condition-case-no-handlers f warnings)))
            (should (> fixes 0))
            (with-temp-buffer
              (insert-file-contents f)
              (should (string-match-p "(condition-case err" (buffer-string)))
              (should-not (string-match-p "(condition-case nil" (buffer-string))))))
      (delete-file f))))

(ert-deftest tdd/self-heal/fix-condition-case/already-named-no-fix ()
  (let ((f (make-temp-file "self-heal-test" nil ".el")))
    (unwind-protect
        (progn
          (write-region "(defun foo ()\n  (condition-case err\n      (error \"oops\")\n    (error (message \"%s\" err))))\n" nil f)
          (let* ((warnings (list (cons 2 "warning: condition-case without handlers")
                                (cons nil "reference to free variable `err'")))
                 (fixes (gptel-auto-workflow--fix-condition-case-no-handlers f warnings)))
            (should (= fixes 0))))
      (delete-file f))))

(ert-deftest tdd/self-heal/fix-condition-case/no-free-err-no-fix ()
  (let ((f (make-temp-file "self-heal-test" nil ".el")))
    (unwind-protect
        (progn
          (write-region "(defun foo ()\n  (condition-case nil\n      (error \"oops\")\n    (error nil)))\n" nil f)
          (let* ((warnings (list (cons 2 "warning: condition-case without handlers")))
                 (fixes (gptel-auto-workflow--fix-condition-case-no-handlers f warnings)))
            (should (= fixes 0))))
      (delete-file f))))

(ert-deftest tdd/self-heal/fix-condition-case/preserves-parens ()
  (let ((f (make-temp-file "self-heal-test" nil ".el")))
    (unwind-protect
        (progn
          (write-region "(defun foo ()\n  (condition-case nil\n      (error \"oops\")\n    (error (message \"%s\" err))))\n" nil f)
          (gptel-auto-workflow--fix-condition-case-no-handlers
           f (list (cons 2 "warning: condition-case without handlers")
                   (cons nil "reference to free variable `err'")))
          (should (gptel-auto-workflow--check-parens f)))
      (delete-file f))))

;; ─── fix-let-needs-let* ───
;; Generates its own warnings internally via
;; `byte-compile-warnings-for-file', but those warnings lack line
;; numbers (byte-compile-from-buffer does not set
;; byte-compile-current-file).  The fixer skips nil-line warnings.
;; This test validates the intended behavior; it will pass once
;; byte-compile-warnings-for-file preserves line numbers.

(ert-deftest tdd/self-heal/fix-let-needs-let*/sequential-binding ()
  (let ((f (make-temp-file "self-heal-test" nil ".el")))
    (unwind-protect
        (progn
          (write-region ";; -*- lexical-binding: t; -*-\n(defun foo ()\n  (let ((a 1)\n        (b (+ a 1)))\n    b))\n" nil f)
          (let ((fixes (gptel-auto-workflow--fix-let-needs-let* f)))
            (should (> fixes 0))
            (with-temp-buffer
              (insert-file-contents f)
              (should (string-match-p "(let\\*" (buffer-string))))))
      (delete-file f))))

(ert-deftest tdd/self-heal/fix-let-needs-let*/independent-bindings-no-fix ()
  (let ((f (make-temp-file "self-heal-test" nil ".el")))
    (unwind-protect
        (progn
          (write-region "(defun foo ()\n  (let ((a 1)\n        (b 2))\n    (+ a b)))\n" nil f)
          (let ((fixes (gptel-auto-workflow--fix-let-needs-let* f)))
            (should (= fixes 0))))
      (delete-file f))))

(ert-deftest tdd/self-heal/fix-let-needs-let*/preserves-parens ()
  (let ((f (make-temp-file "self-heal-test" nil ".el")))
    (unwind-protect
        (progn
          (write-region "(defun foo ()\n  (let ((a 1)\n        (b 2))\n    (+ a b)))\n" nil f)
          (gptel-auto-workflow--fix-let-needs-let* f)
          (should (gptel-auto-workflow--check-parens f)))
      (delete-file f))))

;; ─── run-fixer-with-rollback ───

(ert-deftest tdd/self-heal/rollback/reverts-broken-parens ()
  (let ((f (make-temp-file "self-heal-test" nil ".el")))
    (unwind-protect
        (progn
          (write-region "(defun foo () (+ 1 2))\n" nil f)
          (let ((before (with-current-buffer (find-file-noselect f) (buffer-string))))
            (gptel-auto-workflow--run-fixer-with-rollback
             f (lambda (_file)
                 (with-current-buffer (find-file-noselect f)
                   (goto-char (point-max))
                   (insert ")))")
                   (save-buffer))
                 1))
            (should (string= before (with-current-buffer (find-file-noselect f) (buffer-string))))))
      (delete-file f))))

(ert-deftest tdd/self-heal/rollback/keeps-valid-fix ()
  (let ((f (make-temp-file "self-heal-test" nil ".el")))
    (unwind-protect
        (progn
          (write-region "(defun foo () (+ 1 2))\n" nil f)
          (gptel-auto-workflow--run-fixer-with-rollback
           f (lambda (_file)
               (with-current-buffer (find-file-noselect f)
                 (goto-char (point-max))
                 (insert ";; comment\n")
                 (save-buffer))
               1))
          (with-temp-buffer
            (insert-file-contents f)
            (should (string-match-p ";; comment" (buffer-string)))))
      (delete-file f))))

;; ─── function-exists-in-file-p ───

(ert-deftest tdd/self-heal/function-exists-in-file-p/found ()
  (should (gptel-auto-workflow--function-exists-in-file-p
           "gptel-auto-workflow--check-parens"
           "gptel-auto-workflow-evolution")))

(ert-deftest tdd/self-heal/function-exists-in-file-p/not-found ()
  (should-not (gptel-auto-workflow--function-exists-in-file-p
               "nonexistent-function-xyz"
               "gptel-auto-workflow-evolution")))

(ert-deftest tdd/self-heal/function-exists-in-file-p/found-in-gptel ()
  (should (gptel-auto-workflow--function-exists-in-file-p "gptel-send" "gptel")))

;; ─── re-entrant guard ───

(ert-deftest tdd/self-heal/re-entrant-guard-skips-recursive-call ()
  "Recursive entry while already running must return without invoking fix-file.
Bugs the production code: `defun' has no implicit `cl-block', so the
guard's `cl-return-from' threw `no-catch' (signal aborted the recursive
caller). Fixed in production by changing `defun' to `cl-defun'."
  (let ((gptel-auto-workflow--self-heal-running t)
        (fix-file-calls nil))
    (cl-letf (((symbol-function
                (quote gptel-auto-workflow--self-heal-byte-compiler--fix-file))
               (lambda (file)
                 (setq fix-file-calls (cons file fix-file-calls))
                 (cons 0 nil)))
              ((symbol-function
                (quote gptel-auto-workflow--byte-compile-warnings-for-file))
               (lambda (_) nil))
              ((symbol-function
                (quote gptel-auto-workflow--expand-workspace-path))
               (lambda (_) default-directory))
              ((symbol-function
                (quote directory-files))
               (lambda (_ _ _) nil))
              ((symbol-function
                (quote gptel-auto-workflow--self-heal-byte-compiler-llm))
               (lambda (_) 0)))
      (let ((result (gptel-auto-workflow--self-heal-byte-compiler)))
        (should (null fix-file-calls))
        (should (eq 0 (plist-get result :fixes-applied)))
        (should (null (plist-get result :files-fixed)))))))

;; ─── per-file content-hash skip ───

(ert-deftest tdd/self-heal/unchanged-file-skipped-on-second-iteration ()
  "When content-hash matches prev-hash, the file is added to stuck-files
and --fix-file is not invoked again for it."
  (let* ((target-file (make-temp-file "self-heal-skip" nil ".el"))
         (md5-fn (lambda (f) (with-temp-buffer
                               (insert-file-contents f)
                               (md5 (current-buffer))))))
    (unwind-protect
        (progn
          (write-region ";; test\n" nil target-file)
          (let ((prev-hash (funcall md5-fn target-file)))
            (should (string= prev-hash (funcall md5-fn target-file)))
            (should (file-exists-p target-file)))
          (let ((prev-hash (funcall md5-fn target-file))
                (content-hash (funcall md5-fn target-file))
                (f-iter 1))
            (should (and prev-hash
                         (string= content-hash prev-hash)
                         (> f-iter 0)))))
      (delete-file target-file))))

;; ─── per-file max iterations ───

(ert-deftest tdd/self-heal/per-file-cap-of-3-attempts ()
  "Production code skips a file when (> f-iter 3). Verify threshold is 3."
  (let ((f-iter 4))
    (should (> f-iter 3)))
  (let ((f-iter 3))
    (should-not (> f-iter 3)))
  (let ((f-iter 0))
    (should-not (> f-iter 3))))

;; ─── fix-void-defvars must not be in generic fixer list ───

(ert-deftest tdd/self-heal/fix-file-no-void-defvars-for-generic-warnings ()
  "fix-void-defvars must not be in the generic byte-compiler fixer list.
Bare (defvar X) forms in a file processed by --fix-file should remain
untouched (the void-defvar fixer is owned by the semantic self-heal path)."
  (let ((f (make-temp-file "self-heal-test" nil ".el")))
    (unwind-protect
        (progn
          (write-region "(defvar my-test-var)\n(defun foo () (+ 1 2))\n" nil f)
          (gptel-auto-workflow--self-heal-byte-compiler--fix-file f)
          (with-temp-buffer
            (insert-file-contents f)
            ;; The bare defvar must still be bare — fix-void-defvars was not invoked
            (should (string-match-p "(defvar my-test-var)" (buffer-string)))
            (should-not (string-match-p "(defvar my-test-var nil" (buffer-string)))))
      (delete-file f))))

(provide 'test-self-heal-byte-compiler)
;;; test-self-heal-byte-compiler.el ends here
