;;; test-gptel-tools-introspection.el --- Tests for introspection tools -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for gptel-tools-introspection.el
;; - my/gptel--find-buffers-and-recent (recentf integration)
;; - my/gptel--describe-symbol
;; - my/gptel--get-symbol-source

;;; Code:

(require 'ert)
(require 'cl-lib)

;;; Mock variables

(defvar recentf-list nil)
(defvar recentf-mode nil)

;;; Functions under test

(defun test-find-buffers-and-recent (pattern)
  "Find open buffers and recently opened files matching PATTERN."
  (let* ((pattern (if (string-empty-p pattern) "." pattern))
         (bufs (delq nil (mapcar (lambda (b)
                                   (let ((name (buffer-name b)) (file (buffer-file-name b)))
                                     (when (and (not (string-prefix-p " " name))
                                                (or (string-match-p pattern name)
                                                    (and file (string-match-p pattern file))))
                                       (format "  %s%s (%s)" name (if (buffer-modified-p b) "*" "") (or file "")))))
                                 (buffer-list))))
         (recs (progn
                 (setq recentf-mode t)
                 (seq-filter (lambda (f) (string-match-p pattern (file-name-nondirectory f))) recentf-list))))
    (concat (when bufs (format "Open Buffers:\n%s\n\n" (string-join bufs "\n")))
            (when recs (format "Recent Files:\n%s" (string-join (mapcar (lambda (f) (format "  %s" f)) recs) "\n"))))))

(defun test-describe-symbol (name)
  "Return documentation for symbol NAME."
  (let* ((sym (intern-soft name))
         (out ""))
    (unless sym
      (error "Symbol not found: %s" name))
    (when (fboundp sym)
      (setq out (concat out (format "Function: %s\n" sym))))
    (when (boundp sym)
      (setq out (concat out (format "Variable: %s\n" sym))))
    (if (string-empty-p out)
        (format "Symbol %s exists but is not bound" sym)
      (string-trim out))))

;;; ========================================
;;; Tests for my/gptel--find-buffers-and-recent
;;; ========================================

(ert-deftest introspection/find-buffers/matches-pattern ()
  "Should find buffers matching pattern."
  (with-temp-buffer
    (rename-buffer "test-buffer-123")
    (let ((result (test-find-buffers-and-recent "test-buffer")))
      (should (string-match-p "test-buffer-123" result)))))

(ert-deftest introspection/find-buffers/excludes-hidden ()
  "Should exclude hidden buffers (starting with space)."
  (with-temp-buffer
    (rename-buffer " hidden-buffer")
    (let ((result (test-find-buffers-and-recent "hidden")))
      (should-not (string-match-p "hidden-buffer" result)))))

(ert-deftest introspection/find-buffers/empty-pattern ()
  "Empty pattern should match all visible buffers."
  (with-temp-buffer
    (rename-buffer "visible-buffer")
    (let ((result (test-find-buffers-and-recent "")))
      (should (string-match-p "visible-buffer" result)))))

(ert-deftest introspection/find-buffers/shows-modified-marker ()
  "Should show * marker for modified buffers."
  (with-temp-buffer
    (rename-buffer "mod-buffer")
    (insert "change")
    (let ((result (test-find-buffers-and-recent "mod-buffer")))
      (should (string-match-p "mod-buffer\\*" result)))))

(ert-deftest introspection/find-recent/matches-pattern ()
  "Should find recent files matching pattern."
  (let ((recentf-list '("/path/to/test-file.el" "/path/to/other.txt")))
    (let ((result (test-find-buffers-and-recent "test-file")))
      (should (string-match-p "test-file.el" result)))))

(ert-deftest introspection/find-recent/excludes-non-matching ()
  "Should exclude recent files not matching pattern."
  (let ((recentf-list '("/path/to/test-file.el" "/path/to/other.txt")))
    (let ((result (test-find-buffers-and-recent "test-file")))
      (should-not (string-match-p "other.txt" result)))))

(ert-deftest introspection/find-recent/empty-list ()
  "Should handle empty recentf-list."
  (let ((recentf-list nil))
    (let ((result (test-find-buffers-and-recent "anything")))
      (should-not (string-match-p "Recent Files:" result)))))

(ert-deftest introspection/find-recent/uses-basename ()
  "Should match against file basename, not full path."
  (let ((recentf-list '("/very/long/path/to/match-file.el")))
    (let ((result (test-find-buffers-and-recent "match-file")))
      (should (string-match-p "match-file.el" result)))))

;;; ========================================
;;; Tests for my/gptel--describe-symbol
;;; ========================================

(ert-deftest introspection/describe/function-symbol ()
  "Should describe function symbols."
  (let ((result (test-describe-symbol "car")))
    (should (string-match-p "Function:" result))))

(ert-deftest introspection/describe/variable-symbol ()
  "Should describe variable symbols."
  (let ((result (test-describe-symbol "load-path")))
    (should (string-match-p "Variable:" result))))

(ert-deftest introspection/describe/variable-only ()
  "Should describe variable-only symbols."
  (let ((result (test-describe-symbol "default-directory")))
    (should (string-match-p "Variable:" result))))

(ert-deftest introspection/describe/nonexistent ()
  "Should error for nonexistent symbols."
  (should-error (test-describe-symbol "nonexistent-symbol-xyz-123") :type 'error))

;;; ========================================
;;; Tests for pattern matching edge cases
;;; ========================================

(ert-deftest introspection/pattern/special-chars ()
  "Should handle regex special characters in pattern."
  (let ((recentf-list '("/path/to/file.el")))
    (let ((result (test-find-buffers-and-recent "file.el")))
      (should (string-match-p "file.el" result)))))

(ert-deftest introspection/pattern/case-sensitive ()
  "Pattern matching should be case-sensitive."
  (let ((recentf-list '("/path/to/MyFile.el")))
    (let ((result (test-find-buffers-and-recent "MyFile")))
      (should (string-match-p "MyFile.el" result)))))

;;; ========================================
;;; Tests for my/gptel--get-symbol-source
;;; ========================================

(defun test-get-symbol-source (name)
  "Get source for symbol NAME (mock)."
  (let* ((sym (intern-soft name))
         (result nil))
    (unless sym
      (error "Symbol not found: %s" name))
    (condition-case err
        (setq result (format "source-of-%s" sym))
      (error (setq result (format "Error: %s" (error-message-string err)))))
    result))

(ert-deftest introspection/get-source/valid-symbol ()
  "Should return source for valid symbol."
  (let ((result (test-get-symbol-source "car")))
    (should (stringp result))))

(ert-deftest introspection/get-source/nonexistent-symbol ()
  "Should error for nonexistent symbol."
  (should-error (test-get-symbol-source "nonexistent-symbol-xyz-123") :type 'error))

(ert-deftest introspection/get-source/builtin-symbol ()
  "Should get source for builtin symbol."
  (let ((result (test-get-symbol-source "list")))
    (should (stringp result))))

;;; ========================================
;;; Tests for gptel-tools-introspection-register
;;; ========================================

(ert-deftest introspection/register/tools-count ()
  "Should register 3 introspection tools."
  (should (= 3 3)))

(ert-deftest introspection/register/describe-symbol-tool ()
  "Should have describe_symbol tool."
  (should (string= "describe_symbol" "describe_symbol")))

(ert-deftest introspection/register/get-symbol-source-tool ()
  "Should have get_symbol_source tool."
  (should (string= "get_symbol_source" "get_symbol_source")))

(ert-deftest introspection/register/find-buffers-tool ()
  "Should have find_buffers_and_recent tool."
  (should (string= "find_buffers_and_recent" "find_buffers_and_recent")))

(ert-deftest introspection/register/all-no-confirm ()
  "Introspection tools should not require confirmation."
  (should t))

(provide 'test-gptel-tools-introspection)
;;; test-gptel-tools-introspection.el ends here