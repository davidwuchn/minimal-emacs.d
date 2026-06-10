;;; test-brepl.el --- Regression tests for gptel-ext-brepl -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

;; Load brepl module
(add-to-list 'load-path
             (expand-file-name "lisp/modules"
                               (file-name-directory (or load-file-name
                                                        (buffer-file-name)
                                                        default-directory))))
(require 'gptel-ext-brepl)

;; ── Group 1: Binary detection ──

(ert-deftest test-brepl/binary-available-p-when-exists ()
  "available-p returns non-nil when binary exists and port is found."
  (cl-letf (((symbol-function 'executable-find) (lambda (_) "/usr/local/bin/brepl"))
            ((symbol-function 'gptel-brepl-nrepl-port) (lambda () "7888")))
    (should (gptel-brepl-available-p))))

(ert-deftest test-brepl/available-p-nil-when-no-binary ()
  "available-p returns nil when binary not found."
  (cl-letf (((symbol-function 'executable-find) (lambda (_) nil))
            ((symbol-function 'gptel-brepl-nrepl-port) (lambda () "7888")))
    (should-not (gptel-brepl-available-p))))

;; ── Group 2: nREPL port discovery ──

(ert-deftest test-brepl/port-from-env-var ()
  "nrepl-port returns value from BREPL_PORT env var."
  (let ((old-env (getenv "BREPL_PORT")))
    (unwind-protect
        (progn
          (setenv "BREPL_PORT" "7888")
          (should (string= (gptel-brepl-nrepl-port) "7888")))
      (setenv "BREPL_PORT" old-env))))

(ert-deftest test-brepl/port-from-dotfile-in-cwd ()
  "nrepl-port discovers port from .nrepl-port file in cwd."
  (let ((tmpdir (make-temp-file "brepl-test-" t)))
    (unwind-protect
        (let ((default-directory tmpdir))
          (with-temp-file (expand-file-name ".nrepl-port" tmpdir)
            (insert "9999"))
          (should (string= (gptel-brepl-nrepl-port) "9999")))
      (delete-directory tmpdir t))))

(ert-deftest test-brepl/port-from-dotfile-in-parent ()
  "nrepl-port discovers port from .nrepl-port in parent directory."
  (let ((tmpdir (make-temp-file "brepl-test-" t)))
    (unwind-protect
        (let ((subdir (expand-file-name "sub" tmpdir)))
          (make-directory subdir)
          (with-temp-file (expand-file-name ".nrepl-port" tmpdir)
            (insert "5555"))
          (let ((default-directory subdir))
            (should (string= (gptel-brepl-nrepl-port) "5555"))))
      (delete-directory tmpdir t))))

(ert-deftest test-brepl/port-returns-nil-when-none ()
  "nrepl-port returns nil when no env var and no .nrepl-port file."
  (let ((tmpdir (make-temp-file "brepl-test-" t))
        (old-env (getenv "BREPL_PORT")))
    (unwind-protect
        (let ((default-directory tmpdir))
          (setenv "BREPL_PORT" nil)
          (should-not (gptel-brepl-nrepl-port)))
      (delete-directory tmpdir t)
      (setenv "BREPL_PORT" old-env))))

;; ── Group 3: Eval ──

(ert-deftest test-brepl/eval-returns-plist-shape ()
  "eval returns plist with :success t, :result string, :error nil."
  (cl-letf (((symbol-function 'gptel-brepl--call)
             (lambda (args) (list :success t :result "42" :error nil))))
    (let ((result (gptel-brepl-eval "(+ 1 2 3)")))
      (should (plist-get result :success))
      (should (string= (plist-get result :result) "42"))
      (should (null (plist-get result :error))))))

(ert-deftest test-brepl/eval-error-returns-nil-success ()
  "eval returns :success nil when brepl fails."
  (cl-letf (((symbol-function 'gptel-brepl--call)
             (lambda (args) (list :success nil :result nil :error "Syntax error"))))
    (let ((result (gptel-brepl-eval "(+ 1 ")))
      (should-not (plist-get result :success))
      (should (stringp (plist-get result :error))))))

(ert-deftest test-brepl/eval-passes-expr-as-arg ()
  "eval passes expression string as argument to brepl."
  (let ((captured nil))
    (cl-letf (((symbol-function 'gptel-brepl--call)
               (lambda (args) (setq captured args) (list :success t :result "nil" :error nil))))
      (gptel-brepl-eval "(println \"hello\")")
      (should (equal captured '("(println \"hello\")"))))))

;; ── Group 4: Load file ──

(ert-deftest test-brepl/load-file-returns-plist-shape ()
  "load-file returns plist with :success, :result, :error."
  (cl-letf (((symbol-function 'gptel-brepl--call)
             (lambda (args) (list :success t :result "Loaded" :error nil))))
    (let ((result (gptel-brepl-load-file "/tmp/test.clj")))
      (should (plist-get result :success))
      (should (string= (plist-get result :result) "Loaded"))
      (should (null (plist-get result :error))))))

(ert-deftest test-brepl/load-file-passes-f-flag ()
  "load-file passes -f flag and file path to brepl."
  (let ((captured nil))
    (cl-letf (((symbol-function 'gptel-brepl--call)
               (lambda (args) (setq captured args) (list :success t :result "" :error nil))))
      (gptel-brepl-load-file "/tmp/test.clj")
      (should (member "-f" captured))
      (should (member "/tmp/test.clj" captured)))))

;; ── Group 5: Balance ──

(ert-deftest test-brepl/balance-returns-plist-shape ()
  "balance returns plist with :success, :output, :error."
  (cl-letf (((symbol-function 'gptel-brepl--call)
             (lambda (args) (list :success t :result "fixed content" :error nil))))
    (let ((result (gptel-brepl-balance "/tmp/test.clj")))
      (should (plist-get result :success))
      (should (string= (plist-get result :output) "fixed content"))
      (should (null (plist-get result :error))))))

(ert-deftest test-brepl/balance-dry-run-adds-flag ()
  "balance with dry-run t passes --dry-run to brepl."
  (let ((captured nil))
    (cl-letf (((symbol-function 'gptel-brepl--call)
               (lambda (args) (setq captured args) (list :success t :result "" :error nil))))
      (gptel-brepl-balance "/tmp/test.clj" t)
      (should (member "--dry-run" captured))
      (should (member "balance" captured))
      (should (member "/tmp/test.clj" captured)))))

(ert-deftest test-brepl/balance-no-dry-run-flag ()
  "balance without dry-run omits --dry-run flag."
  (let ((captured nil))
    (cl-letf (((symbol-function 'gptel-brepl--call)
               (lambda (args) (setq captured args) (list :success t :result "" :error nil))))
      (gptel-brepl-balance "/tmp/test.clj")
      (should (member "balance" captured))
      (should (member "/tmp/test.clj" captured))
      (should-not (member "--dry-run" captured)))))

;; ── Group 6: Status ──

(ert-deftest test-brepl/status-returns-plist ()
  "status returns a valid plist."
  (let ((status (gptel-brepl-status)))
    (should (plistp status))))

(ert-deftest test-brepl/status-has-expected-keys ()
  "status plist has :binary, :binary-exists, :port, :available keys."
  (let ((status (gptel-brepl-status)))
    (should (plist-member status :binary))
    (should (plist-member status :binary-exists))
    (should (plist-member status :port))
    (should (plist-member status :available))
    (should (booleanp (plist-get status :binary-exists)))
    (should (booleanp (plist-get status :available)))))

(ert-deftest test-brepl/status-reflects-binary-path ()
  "status :binary reflects the defcustom value."
  (let ((status (gptel-brepl-status)))
    (should (stringp (plist-get status :binary)))
    (should (string= (plist-get status :binary) gptel-brepl-binary))))

;; ── Group 7: Internal edge cases ──

(ert-deftest test-brepl/call-returns-error-when-no-binary ()
  "--call returns :success nil when binary is not found."
  (cl-letf (((symbol-function 'executable-find) (lambda (_) nil)))
    (let ((result (gptel-brepl--call '("(+ 1 2)"))))
      (should-not (plist-get result :success))
      (should (stringp (plist-get result :error)))
      (should (string-match-p "[Nn]ot found" (plist-get result :error))))))

(ert-deftest test-brepl/defcustom-exists ()
  "gptel-brepl-binary defcustom is defined and a string."
  (should (boundp 'gptel-brepl-binary))
  (should (stringp gptel-brepl-binary)))

(provide 'test-brepl)
;;; test-brepl.el ends here
