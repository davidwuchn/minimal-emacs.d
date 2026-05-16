;;; test-gptel-ext-streaming.el --- Tests for streaming jit-lock protection -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for gptel-ext-streaming.el functions.
;; Run with:
;;   emacs --batch -L tests -l test-gptel-ext-streaming.el -f ert-run-tests-batch

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gptel-ext-streaming)

;;; Streaming flag tests

(ert-deftest test-streaming/flag-nil-initially ()
  "Streaming flag should be nil initially."
  (let ((buf (generate-new-buffer "*test-stream*")))
    (with-current-buffer buf
      (setq-local my/gptel--streaming-p nil)
      (should-not my/gptel--streaming-p))
    (kill-buffer buf)))

(ert-deftest test-streaming/set-flag ()
  "Setting streaming flag should make it non-nil."
  (let ((buf (generate-new-buffer "*test-stream*"))
        (info (list :position nil)))
    (with-current-buffer buf
      (setq-local my/gptel--streaming-p nil)
      (let ((marker (set-marker (make-marker) 1 buf)))
        (plist-put info :position marker)
        (my/gptel--stream-set-flag "text" info nil)
        (should my/gptel--streaming-p)))
    (kill-buffer buf)))

(ert-deftest test-streaming/set-flag-skips-non-string ()
  "Setting streaming flag should skip non-string response."
  (let ((buf (generate-new-buffer "*test-stream*"))
        (info (list :position nil)))
    (with-current-buffer buf
      (setq-local my/gptel--streaming-p nil)
      (let ((marker (set-marker (make-marker) 1 buf)))
        (plist-put info :position marker)
        (my/gptel--stream-set-flag nil info nil)
        (should-not my/gptel--streaming-p)))
    (kill-buffer buf)))

(ert-deftest test-streaming/clear-flag ()
  "Clearing streaming flag should set it to nil."
  (let ((buf (generate-new-buffer "*test-stream*")))
    (with-current-buffer buf
      (setq-local my/gptel--streaming-p t)
      (my/gptel--stream-clear-flag)
      (should-not my/gptel--streaming-p))
    (kill-buffer buf)))

;;; Jit-lock safety tests

(ert-deftest test-streaming/jit-lock-safe-wraps-in-gptel-mode ()
  "jit-lock-safe should use condition-case in gptel-mode buffers."
  (let ((buf (generate-new-buffer "*test-jit*"))
        (gptel-mode t)
        (called-with-error nil))
    (with-current-buffer buf
      (cl-letf (((symbol-function 'test--jit-lock-thrower)
                 (lambda (_start)
                   (setq called-with-error t)
                   (signal 'error '("test error"))))
                ((symbol-function 'jit-lock-refontify) #'ignore))
        (should-not called-with-error)
        (my/gptel--jit-lock-safe #'test--jit-lock-thrower 1)
        (should called-with-error)))
    (kill-buffer buf)))

(ert-deftest test-streaming/jit-lock-safe-passes-through-non-gptel ()
  "jit-lock-safe should call original directly in non-gptel buffers."
  (let ((buf (generate-new-buffer "*test-jit*"))
        (gptel-mode nil)
        (called-directly nil))
    (with-current-buffer buf
      (cl-letf (((symbol-function 'test--jit-lock-direct)
                 (lambda (_start)
                   (setq called-directly t))))
        (should-not called-directly)
        (my/gptel--jit-lock-safe #'test--jit-lock-direct 1)
        (should called-directly)))
    (kill-buffer buf)))

(provide 'test-gptel-ext-streaming)
;;; test-gptel-ext-streaming.el ends here