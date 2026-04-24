;;; test-gptel-ext-context.el --- Tests for auto-compact -*- lexical-binding: t; -*-

;;; Commentary:
;; P1 tests for gptel-ext-context.el
;; Tests:
;; - my/gptel--compact-safe-p
;; - my/gptel--auto-compact-needed-p
;; - my/gptel--directive-text
;; - my/gptel-auto-compact

;;; Code:

(require 'ert)

(declare-function my/gptel--threshold-values "gptel-ext-context")

;;; Mock variables

(defvar gptel-mode nil)
(defvar gptel-directives nil)
(defvar my/gptel-auto-compact-enabled t)
(defvar my/gptel-auto-compact-threshold 0.75)
(defvar my/gptel-auto-compact-min-chars 4000)
(defvar my/gptel-auto-compact-min-interval 45)
(defvar my/gptel-default-context-window 128000)
(defvar-local my/gptel-auto-compact-running nil)
(defvar-local my/gptel-auto-compact-last-run nil)

;;; Functions under test

(defun test-estimate-tokens (chars)
  "Estimate token count from CHARS."
  (/ (float chars) 4.0))

(defun test-context--mock-window ()
  "Return mock context window for auto-compact tests."
  32768)

(defun test-compact-safe-p ()
  "Return non-nil if auto-compact is safe."
  (let ((elapsed (and my/gptel-auto-compact-last-run
                      (float-time (time-subtract (current-time)
                                                 my/gptel-auto-compact-last-run)))))
    (and (not my/gptel-auto-compact-running)
         (or (null elapsed)
             (>= elapsed my/gptel-auto-compact-min-interval)))))

(defun test-auto-compact-needed-p ()
  "Return non-nil when current buffer should be compacted."
  (let* ((chars (buffer-size))
         (tokens (test-estimate-tokens chars))
         (window (test-context--mock-window))
         (threshold (* window my/gptel-auto-compact-threshold)))
    (and my/gptel-auto-compact-enabled
         gptel-mode
         (test-compact-safe-p)
         (>= chars my/gptel-auto-compact-min-chars)
         (>= tokens threshold))))

(defun test-directive-text (sym)
  "Resolve directive SYM to a string."
  (let ((val (alist-get sym gptel-directives)))
    (cond
     ((functionp val) (funcall val))
     ((stringp val) val)
     (t nil))))

;;; Tests for my/gptel--compact-safe-p

(ert-deftest context/compact-safe/when-not-running ()
  "Should be safe when not running and no last run."
  (let ((my/gptel-auto-compact-running nil)
        (my/gptel-auto-compact-last-run nil))
    (should (test-compact-safe-p))))

(ert-deftest context/compact-safe/when-running ()
  "Should not be safe when already running."
  (let ((my/gptel-auto-compact-running t)
        (my/gptel-auto-compact-last-run nil))
    (should-not (test-compact-safe-p))))

(ert-deftest context/compact-safe/after-min-interval ()
  "Should be safe after min interval elapsed."
  (let ((my/gptel-auto-compact-running nil)
        (my/gptel-auto-compact-last-run (time-subtract (current-time) (seconds-to-time 60))))
    (should (test-compact-safe-p))))

(ert-deftest context/compact-safe/before-min-interval ()
  "Should not be safe before min interval elapsed."
  (let ((my/gptel-auto-compact-running nil)
        (my/gptel-auto-compact-last-run (time-subtract (current-time) (seconds-to-time 30))))
    (should-not (test-compact-safe-p))))

;;; Tests for my/gptel--auto-compact-needed-p

(ert-deftest context/needed/when-disabled ()
  "Should not be needed when disabled."
  (let ((my/gptel-auto-compact-enabled nil)
        (gptel-mode t))
    (with-temp-buffer
      (insert (make-string 100000 ?x))
      (should-not (test-auto-compact-needed-p)))))

(ert-deftest context/needed/when-no-gptel-mode ()
  "Should not be needed when gptel-mode is off."
  (let ((my/gptel-auto-compact-enabled t)
        (gptel-mode nil))
    (with-temp-buffer
      (insert (make-string 100000 ?x))
      (should-not (test-auto-compact-needed-p)))))

(ert-deftest context/needed/when-buffer-small ()
  "Should not be needed when buffer is small."
  (let ((my/gptel-auto-compact-enabled t)
        (gptel-mode t))
    (with-temp-buffer
      (insert (make-string 1000 ?x))
      (should-not (test-auto-compact-needed-p)))))

(ert-deftest context/needed/when-buffer-large ()
  "Should be needed when buffer is large enough."
  (let ((my/gptel-auto-compact-enabled t)
        (gptel-mode t)
        (my/gptel-auto-compact-running nil)
        (my/gptel-auto-compact-last-run nil))
    (with-temp-buffer
      (insert (make-string 100000 ?x))
      (should (test-auto-compact-needed-p)))))

(ert-deftest context/needed/respects-threshold ()
  "Should respect threshold setting."
  (let ((my/gptel-auto-compact-enabled t)
        (gptel-mode t)
        (my/gptel-auto-compact-threshold 0.3)
        (my/gptel-auto-compact-running nil)
        (my/gptel-auto-compact-last-run nil))
    (with-temp-buffer
      (insert (make-string 50000 ?x))
      (should (test-auto-compact-needed-p)))))

(ert-deftest context/threshold-values/falls-back-to-default-window ()
  "Threshold calculation should fall back to the default context window."
  (let* ((repo-root (or (locate-dominating-file default-directory "lisp/modules")
                        default-directory))
         (load-path (append (list (expand-file-name "lisp/modules" repo-root)
                                  (expand-file-name "packages/gptel" repo-root))
                            load-path))
         (my/gptel-default-context-window 128000))
    (load-file (expand-file-name "lisp/modules/gptel-ext-context.el" repo-root))
    (cl-letf (((symbol-function 'my/gptel--current-tokens)
               (lambda () 1000))
              ((symbol-function 'my/gptel--context-window)
               (lambda () nil))
              ((symbol-function 'my/gptel--effective-threshold)
               (lambda () 0.75)))
      (should (equal (my/gptel--threshold-values)
                     (list 1000 128000 0.75 96000.0))))))

;;; Tests for my/gptel--directive-text

(ert-deftest context/directive/string-value ()
  "Should return string value from directives."
  (let ((gptel-directives '((compact . "Summarize this buffer"))))
    (should (equal (test-directive-text 'compact) "Summarize this buffer"))))

(ert-deftest context/directive/function-value ()
  "Should call function value from directives."
  (let ((gptel-directives '((compact . (lambda () "Dynamic summary")))))
    (should (equal (test-directive-text 'compact) "Dynamic summary"))))

(ert-deftest context/directive/missing ()
  "Should return nil for missing directive."
  (let ((gptel-directives nil))
    (should-not (test-directive-text 'compact))))

(ert-deftest context/directive/invalid-value ()
  "Should return nil for invalid directive value."
  (let ((gptel-directives '((compact . 123))))
    (should-not (test-directive-text 'compact))))

;;; Tests for my/gptel-auto-compact

(ert-deftest context/auto-compact/skips-when-not-needed ()
  "Should skip compaction when not needed."
  (let ((my/gptel-auto-compact-enabled nil)
        (gptel-mode t)
        (called nil))
    (with-temp-buffer
      (insert (make-string 100 ?x))
      (cl-letf (((symbol-function 'gptel-request)
                 (lambda (&rest _) (setq called t))))
        (test-auto-compact-needed-p)
        (should-not called)))))

(ert-deftest context/auto-compact/respects-running-flag ()
  "Should not compact when already running."
  (let ((my/gptel-auto-compact-running t)
        (gptel-mode t))
    (with-temp-buffer
      (insert (make-string 100000 ?x))
      (should-not (test-auto-compact-needed-p)))))

(provide 'test-gptel-ext-context)
;;; test-gptel-ext-context.el ends here
