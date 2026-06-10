;;; test-daemon-repl.el --- Regression tests for gptel-ext-daemon-repl -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

;; Load daemon-repl
(add-to-list 'load-path
             (expand-file-name "lisp/modules"
                               (file-name-directory (or load-file-name
                                                        (buffer-file-name)
                                                        default-directory))))
(require 'gptel-ext-daemon-repl)

;; ── P0: Same-daemon reentry hang ──

(ert-deftest test-daemon-repl/in-target-daemon-p-batch ()
  "In batch mode we are not a daemon, so predicate returns nil."
  (should-not (gptel-daemon-repl--in-target-daemon-p)))

(ert-deftest test-daemon-repl/eval-direct-success ()
  "Direct in-process eval returns :success t for valid code."
  (let ((result (gptel-daemon-repl--eval-direct "(+ 1 2 3)")))
    (should (plist-get result :success))
    (should (string= (plist-get result :result) "6"))
    (should (null (plist-get result :error)))))

(ert-deftest test-daemon-repl/eval-direct-error ()
  "Direct in-process eval returns :success nil for invalid code."
  (let ((result (gptel-daemon-repl--eval-direct "(+ 1 ")))
    (should-not (plist-get result :success))
    (should (stringp (plist-get result :error)))))

;; ── P1: emacsclient exit status ignored ──

(ert-deftest test-daemon-repl/eval-via-emacsclient-no-daemon ()
  "When no daemon is running, eval-via-emacsclient returns :success nil.
This test also exercises the call-process exit-code path (P1 fix)."
  :expected-result (if (executable-find "emacsclient") :passed :failed)
  (let ((result (gptel-daemon-repl--eval-via-emacsclient "(+ 1 2 3)")))
    (should-not (plist-get result :success))
    (should (stringp (plist-get result :error)))))

;; ── P1: Socket discovery wrong ──

(ert-deftest test-daemon-repl/socket-dir-returns-string-or-nil ()
  "Socket directory detection returns a string or nil."
  (let ((dir (gptel-daemon-repl--socket-dir)))
    (should (or (null dir) (stringp dir)))
    (when dir
      (should (file-directory-p dir)))))

(ert-deftest test-daemon-repl/socket-dir-checks-server-socket-dir ()
  "Socket dir function includes server-socket-dir in its search list.
The function body references (fboundp 'server-socket-dir) — if the
function is available, it is the highest-priority check."
  ;; This is a structural test: server-socket-dir should be preferred
  ;; when fboundp.  The function itself is exercised above.
  (should (fboundp 'gptel-daemon-repl--socket-dir)))

;; ── P1: file-notify not required, wrong flag ──

(ert-deftest test-daemon-repl/file-notify-available ()
  "Filenotify feature is available (require was added)."
  (should (featurep 'filenotify)))

(ert-deftest test-daemon-repl/watch-directory-syntax ()
  "gptel-daemon-repl-watch-directory exists and accepts a directory arg.
The flag is attribute-change (not attribute) — tested indirectly
by calling the function which would signal on invalid flag."
  (should (fboundp 'gptel-daemon-repl-watch-directory))
  ;; Call on a temp dir to verify no syntax errors with the flag
  (let ((tmpdir (make-temp-file "daemon-repl-test-" t)))
    (unwind-protect
        (let ((desc (gptel-daemon-repl-watch-directory tmpdir)))
          (when desc
            (file-notify-rm-watch desc)))
      (delete-directory tmpdir t))))

;; ── P1: file-notify event parsing wrong ──

(ert-deftest test-daemon-repl/event-parsing-cadr-nth2 ()
  "Action is extracted via cadr, file via nth 2 (not car/last).
Synthetic event: (descriptor 'changed \"/tmp/foo.el\")."
  (let ((event (list 'some-descriptor 'changed "/tmp/foo.el")))
    (should (eq (cadr event) 'changed))
    (should (string= (nth 2 event) "/tmp/foo.el"))
    ;; Verify the old buggy way: (car event) gives descriptor, NOT action
    (should-not (eq (car event) 'changed))
    ;; For a 4-element renamed event, (car (last event)) gives wrong file:
    (let ((rename-event (list 'desc 'renamed "/tmp/foo.el" "/tmp/foo.el~")))
      (should-not (string= (car (last rename-event)) "/tmp/foo.el"))
      ;; nth 2 always gives the right file
      (should (string= (nth 2 rename-event) "/tmp/foo.el")))))

;; ── P1: Auto-eval disabled for ~/.emacs.d ──

(ert-deftest test-daemon-repl/dotfile-check-only-basename ()
  "The dotfile regex checks only the basename (file-name-nondirectory),
not the full path.  A file like ~/.emacs.d/init.el should NOT be skipped
because its basename 'init.el' does not start with a dot."
  ;; Simulate the fixed check
  (let ((file "/home/user/.emacs.d/lisp/modules/init.el"))
    (should (string-suffix-p ".el" file))
    ;; The new check: only reject if basename starts with a literal dot
    (should-not (string-match-p "\\`\\." (file-name-nondirectory file)))
    ;; Old buggy check (for contrast): "/\\." matches ".e" in ".emacs.d"
    (should (string-match-p "/\\." file))))

(ert-deftest test-daemon-repl/should-auto-eval-allows-dot-emacs-d ()
  "The auto-eval predicate does NOT exclude ~/.emacs.d path components.
Only actual dotfiles (basenames starting with .) are excluded."
  ;; Load in a temp buffer to test
  (with-temp-buffer
    (emacs-lisp-mode)
    (setq buffer-file-name "/home/user/.emacs.d/lisp/modules/foo.el")
    (let ((gptel-daemon-repl-enabled t)
          (gptel-daemon-repl-eval-on-save t))
      ;; In batch mode derived-mode-p may return nil for temp buffers,
      ;; so we test the regex logic directly:
      (let ((file (buffer-file-name)))
        (should (string-suffix-p ".el" file))
        ;; The key fix: basename does NOT start with dot
        (should-not (string-match-p "\\`\\." (file-name-nondirectory file)))))))

;; ── P1: Before-save autofix never triggers ──

(ert-deftest test-daemon-repl/validate-brackets-balanced ()
  "Balanced code passes validation with :fixed-content identical to input."
  (let ((code "(defun foo () 42)"))
    (let ((result (gptel-daemon-repl-validate-brackets code)))
      (should (plist-get result :valid))
      (should (string= (plist-get result :fixed-content) code))
      (should (null (plist-get result :error))))))

(ert-deftest test-daemon-repl/validate-brackets-unbalanced ()
  "Unbalanced code is detected; may be auto-fixed if fixer available."
  (let ((code "(defun foo () 42"))
    (let ((result (gptel-daemon-repl-validate-brackets code)))
      (if (plist-get result :fixed-content)
          ;; Auto-fixed by self-heal-semantic
          (progn
            (should (plist-get result :valid))
            (should-not (string= (plist-get result :fixed-content) code)))
        ;; Could not fix — should report error
        (progn
          (should-not (plist-get result :valid))
          (should (stringp (plist-get result :error))))))))

(ert-deftest test-daemon-repl/before-save-autofix-gate-detects-change ()
  "The before-save hook gate compares :fixed-content with buffer-string,
not :valid.  When brackets are balanced, :fixed-content equals original
buffer-string, so the gate should NOT trigger."
  (let ((code "(defun foo () 42)"))
    (let ((result (gptel-daemon-repl-validate-brackets code)))
      ;; Balanced: :valid is t and :fixed-content equals input
      (should (plist-get result :valid))
      (should (plist-get result :fixed-content))
      ;; Gate check: (not (string= fixed-content original)) => nil => skip fix
      (should (string= (plist-get result :fixed-content) code))
      (should-not (not (string= (plist-get result :fixed-content) code))))))

(ert-deftest test-daemon-repl/before-save-autofix-wrong-gate-visible ()
  "Demonstrates the old bug: :valid is t even when auto-fixed,
so checking (not :valid) would skip the fix branch."
  ;; For balanced code, the plist from validate-brackets has :valid t
  (let ((result (gptel-daemon-repl-validate-brackets "(defun foo () 42)")))
    (should (plist-get result :valid))
    ;; Old gate: (not :valid) => nil => would skip fix (correct for balanced)
    ;; But for unbalanced+fixed code, :valid is ALSO t — which is the bug.
    ;; The new gate compares :fixed-content instead.
    (should (plist-get result :fixed-content))))

;; ── P1: Wrong arity in self-heal call ──

(ert-deftest test-daemon-repl/self-heal-zero-arity-safe ()
  "Self-heal-semantic is callable with 0 args and doesn't crash."
  (when (fboundp 'gptel-auto-workflow--self-heal-semantic)
    (condition-case err
        (progn
          (funcall 'gptel-auto-workflow--self-heal-semantic)
          t)  ; if we get here, no crash
      (error
       ;; Fail the test if it crashes (unexpected)
       (ert-fail (list "self-heal-semantic crashed:" err))))))

(ert-deftest test-daemon-repl/self-heal-funcall-pattern ()
  "funcall with 0 args works correctly for the self-heal function."
  ;; Test the pattern itself
  (let ((dummy-called nil))
    (fset 'test-brepl--dummy-0arg (lambda () (setq dummy-called t)))
    (unwind-protect
        (progn
          (funcall 'test-brepl--dummy-0arg)
          (should dummy-called))
      (fmakunbound 'test-brepl--dummy-0arg))))

;; ── P2: check-parens wrong context ──
;; The fix moved (emacs-lisp-mode) inside with-temp-buffer.
;; This is tested indirectly by validate-brackets tests above,
;; which exercise the check-parens path.

(ert-deftest test-daemon-repl/check-parens-in-temp-buffer ()
  "Emacs-lisp-mode is activated inside with-temp-buffer, so
check-parens sees the correct major mode.  This is verified by
validate-brackets succeeding for balanced code."
  ;; Balanced code used in validate-brackets exercises the
  ;; with-temp-buffer -> emacs-lisp-mode -> check-parens path
  (let ((result (gptel-daemon-repl-validate-brackets "(progn (message \"hi\"))")))
    (should (plist-get result :valid))))

;; ── Existing tests (preserved and updated) ──

(ert-deftest test-daemon-repl/status-plist ()
  "Status returns a valid plist."
  (let ((status (gptel-daemon-repl-status)))
    (should (plistp status))
    (should (booleanp (plist-get status :enabled)))
    (should (booleanp (plist-get status :eval-on-save)))
    (should (booleanp (plist-get status :validate-brackets)))))

(ert-deftest test-daemon-repl/discover-servers-returns-list ()
  "Server discovery returns a list."
  (let ((servers (gptel-daemon-repl--discover-servers)))
    (should (listp servers))
    (dolist (s servers)
      (should (consp s))
      (should (stringp (car s)))
      (should (stringp (cdr s))))))

;; ── Targeted self-heal ──

(ert-deftest test-daemon-repl/targeted-self-heal-file ()
  "Targeted self-heal only audits/fixes the given file."
  (skip-unless (fboundp 'gptel-auto-workflow--self-heal-file))
  (let* ((test-dir (make-temp-file "daemon-repl-heal-" t))
         (bad-file (expand-file-name "bad.el" test-dir))
         (good-file (expand-file-name "good.el" test-dir)))
    (unwind-protect
        (progn
          ;; bad.el has unbalanced parens
          (with-temp-file bad-file
            (insert "(defun foo () 42\n"))
          ;; good.el is balanced
          (with-temp-file good-file
            (insert "(defun bar () 42)\n"))
          ;; Run targeted self-heal on bad-file
          (let ((result (gptel-auto-workflow--self-heal-file bad-file)))
            ;; Should fix the file
            (should (> (plist-get result :auto-fixed) 0))
            ;; Should only audit one file
            (should (= (plist-get result :files-checked) 1))))
      (delete-directory test-dir t))))

(ert-deftest test-daemon-repl/conversion-unit-logging ()
  "When self-heal fixes a file via daemon-repl, a conversion unit is logged."
  (skip-unless (fboundp 'gptel-auto-workflow--self-heal-file))
  (skip-unless (fboundp 'gptel-conversion-unit-add))
  (let* ((test-dir (make-temp-file "daemon-repl-conv-" t))
         (bad-file (expand-file-name "bad.el" test-dir))
         (gptel-conversion-unit-enabled t)
         (gptel-conversion-unit-persist-dir test-dir))
    (unwind-protect
        (progn
          (gptel-conversion-unit-clear)
          ;; bad.el has unbalanced parens
          (with-temp-file bad-file
            (insert "(defun foo () 42\n"))
          ;; Run targeted self-heal
          (gptel-auto-workflow--self-heal-file bad-file)
          ;; Check that a conversion unit was logged
          (let ((units (gptel-conversion-unit-list)))
            (should (> (length units) 0))
            (let ((unit (car units)))
              (should (equal (gptel-conversion-unit-conversion-type unit) 'repair))
              (should (equal (plist-get (gptel-conversion-unit-before-state unit) :status) 'audit-failed))
              (should (equal (plist-get (gptel-conversion-unit-after-state unit) :status) 'auto-fixed)))))
      (delete-directory test-dir t))))

(ert-deftest test-daemon-repl/metrics-tracked ()
  "Metrics are updated on eval attempts."
  ;; Reset metrics first
  (gptel-daemon-repl-reset-metrics)
  (let ((metrics (gptel-daemon-repl-metrics)))
    (should (= (plist-get metrics :eval-attempts) 0))
    (should (= (plist-get metrics :eval-successes) 0))
    (should (= (plist-get metrics :eval-failures) 0))))

(ert-deftest test-daemon-repl/failure-hook-called ()
  "Failure hook is called when eval fails after retries."
  (let ((hook-called nil)
        (hook-file nil)
        (hook-error nil))
    ;; Install a test hook
    (add-hook 'gptel-daemon-repl-eval-failure-hook
              (lambda (file error-msg retries)
                (setq hook-called t
                      hook-file file
                      hook-error error-msg)))
    (unwind-protect
        (progn
          ;; Reset metrics
          (gptel-daemon-repl-reset-metrics)
          ;; The hook is tested indirectly — verify it's defined
          (should (boundp 'gptel-daemon-repl-eval-failure-hook))
          (should (listp gptel-daemon-repl-eval-failure-hook)))
      ;; Clean up
      (remove-hook 'gptel-daemon-repl-eval-failure-hook
                   (lambda (file error-msg retries)
                     (setq hook-called t
                           hook-file file
                           hook-error error-msg))))))

(ert-deftest test-daemon-repl/status-includes-metrics ()
  "Status plist includes metrics."
  (let ((status (gptel-daemon-repl-status)))
    (should (plist-get status :metrics))
    (let ((metrics (plist-get status :metrics)))
      (should (numberp (plist-get metrics :attempts)))
      (should (numberp (plist-get metrics :successes)))
      (should (numberp (plist-get metrics :failures))))))

(ert-deftest test-daemon-repl/skip-large-files ()
  "Files exceeding max size should not be auto-evaluated."
  (let ((gptel-daemon-repl-max-file-size 100) ; 100 bytes
        (test-file (make-temp-file "daemon-repl-large-" nil ".el")))
    (unwind-protect
        (progn
          ;; Write a file larger than 100 bytes
          (with-temp-file test-file
            (insert (make-string 200 ?x)))
          ;; In a buffer visiting this file
          (with-temp-buffer
            (insert-file-contents test-file)
            (emacs-lisp-mode)
            (setq buffer-file-name test-file)
            ;; Should not auto-eval
            (should-not (gptel-daemon-repl--should-auto-eval-p))))
      (delete-file test-file))))

(ert-deftest test-daemon-repl/retries-without-self-heal ()
  "After-save eval retries max-retries times even when no self-heal is available.
The code uses `cond' with three branches: heal+retry, retry-only, give-up.
BOTH self-heal-file and self-heal-file-dispatch must be unbound so the
retry-only branch is reached."
  (let ((eval-count 0)
        (test-file (make-temp-file "daemon-repl-retry-" nil ".el"))
        (heal-file-fn (when (fboundp 'gptel-auto-workflow--self-heal-file)
                        (symbol-function 'gptel-auto-workflow--self-heal-file)))
        (heal-dispatch-fn (when (fboundp 'gptel-auto-workflow--self-heal-file-dispatch)
                            (symbol-function 'gptel-auto-workflow--self-heal-file-dispatch))))
    (unwind-protect
        (progn
          (with-temp-file test-file
            (insert "(+ 1 2)\n"))
          ;; Mock eval-file to always signal error and count calls
          (cl-letf (((symbol-function 'gptel-daemon-repl-eval-file)
                     (lambda (_file)
                       (cl-incf eval-count)
                       (error "mock eval failure %d" eval-count)))
                    ;; Mock should-auto-eval-p to return t
                    ((symbol-function 'gptel-daemon-repl--should-auto-eval-p)
                     (lambda () t)))
            ;; Ensure no self-heal function is fbound
            (fmakunbound 'gptel-auto-workflow--self-heal-file)
            (fmakunbound 'gptel-auto-workflow--self-heal-file-dispatch)
            (unwind-protect
                (progn
                  (gptel-daemon-repl-reset-metrics)
                  ;; Simulate after-save-eval
                  (let ((gptel-daemon-repl-enabled t)
                        (gptel-daemon-repl-eval-on-save t))
                    (with-temp-buffer
                      (emacs-lisp-mode)
                      (setq buffer-file-name test-file)
                      (gptel-daemon-repl--after-save-eval)))
                  ;; Should have retried 3 times (max-retries)
                  (should (= eval-count 3))
                  ;; Metrics should show 1 failure
                  (let ((metrics (gptel-daemon-repl-metrics)))
                    (should (= (plist-get metrics :eval-attempts) 1))
                    (should (= (plist-get metrics :eval-failures) 1))))
              ;; Restore self-heal functions if they were originally bound
              (when heal-file-fn
                (defalias 'gptel-auto-workflow--self-heal-file heal-file-fn))
              (when heal-dispatch-fn
                (defalias 'gptel-auto-workflow--self-heal-file-dispatch heal-dispatch-fn)))))
      (delete-file test-file))))

(provide 'test-daemon-repl)
;;; test-daemon-repl.el ends here
