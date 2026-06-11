;;; test-daemon-repl-structural.el --- TDD for structural validation -*- lexical-binding: t; no-byte-compile: t; -*-

(require 'ert)

(add-to-list 'load-path
             (expand-file-name "lisp/modules"
                               (file-name-directory (or load-file-name
                                                        (buffer-file-name)
                                                        default-directory))))

;; ── Test 1: Self-heal audit detects provide inside defun ──

(ert-deftest test-daemon-repl/self-heal-detects-swallowed-provide ()
  "Audit should detect when provide is inside a defun due to missing close paren."
  (require 'gptel-auto-workflow-self-heal-semantic)
  (let* ((temp-file (make-temp-file "self-heal-test-" nil ".el"))
         ;; Missing one close paren before provide - provide gets swallowed
         (bad-content ";;; test-bad.el -*- lexical-binding: t; -*-\n(defun test-func ()\n  \"Doc.\"\n  (when t\n    (let ((x nil))\n      (dolist (item '(1 2))\n        (message \"%s\" item))\n      x)))\n\n(provide 'test-bad)\n"))
    (unwind-protect
        (progn
          ;; Create the bad file by removing one close paren
          (with-temp-file temp-file
            (insert bad-content)
            (goto-char (point-min))
            (search-forward "      x)))")
            (replace-match "      x))")
            (write-region (point-min) (point-max) temp-file))
          ;; Audit should detect the problem
          (let ((result (gptel-auto-workflow--audit-provide-inside-defun temp-file)))
            (should (= result 1))))
      (when (file-exists-p temp-file)
        (delete-file temp-file)))))

;; ── Test 2: Self-heal fixer corrects swallowed provide ──

(ert-deftest test-daemon-repl/self-heal-fixes-swallowed-provide ()
  "Fixer should insert missing close parens before provide."
  (require 'gptel-auto-workflow-self-heal-semantic)
  (let* ((temp-file (make-temp-file "self-heal-fix-" nil ".el"))
         (bad-content ";;; test-fix.el -*- lexical-binding: t; -*-\n(defun test-func ()\n  \"Doc.\"\n  (when t\n    (let ((x nil))\n      (dolist (item '(1 2))\n        (message \"%s\" item))\n      x)))\n\n(provide 'test-fix)\n"))
    (unwind-protect
        (progn
          (with-temp-file temp-file
            (insert bad-content)
            (goto-char (point-min))
            (search-forward "      x)))")
            (replace-match "      x))")
            (write-region (point-min) (point-max) temp-file))
          ;; Verify audit detects it
          (let ((audit (gptel-auto-workflow--audit-provide-inside-defun temp-file)))
            (should (= audit 1)))
          ;; Apply fix
          (let ((fixed (gptel-auto-workflow--fix-provide-inside-defun temp-file)))
            (should (= fixed 1)))
          ;; Verify audit now passes
          (let ((audit (gptel-auto-workflow--audit-provide-inside-defun temp-file)))
            (should (= audit 0)))
          ;; Verify file loads and function returns nil
          (load temp-file nil t)
          (should (null (test-func))))
      (when (file-exists-p temp-file)
        (delete-file temp-file)))))

;; ── Test 3: Good file passes audit ──

(ert-deftest test-daemon-repl/self-heal-good-file-passes ()
  "A properly structured file should pass the audit."
  (require 'gptel-auto-workflow-self-heal-semantic)
  (let* ((temp-file (make-temp-file "self-heal-good-" nil ".el"))
         (good-content ";;; test-good.el -*- lexical-binding: t; -*-\n(defun test-func ()\n  \"Doc.\"\n  (when t\n    (let ((x nil))\n      (dolist (item '(1 2))\n        (message \"%s\" item))\n      x)))\n\n(provide 'test-good)\n"))
    (unwind-protect
        (progn
          (with-temp-file temp-file
            (insert good-content))
          (let ((result (gptel-auto-workflow--audit-provide-inside-defun temp-file)))
            (should (= result 0)))
          (load temp-file nil t)
          (should (null (test-func))))
      (when (file-exists-p temp-file)
        (delete-file temp-file)))))

(provide 'test-daemon-repl-structural)
;;; test-daemon-repl-structural.el ends here
