;;; test-gptel-ext-backends.el --- Tests for backend configurations -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for gptel-ext-backends.el functions.
;; Run with:
;;   emacs --batch -L tests -l test-gptel-ext-backends.el -f ert-run-tests-batch

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gptel-ext-backends)

;;; API key helper tests

(ert-deftest test-backends/api-key-returns-nil-for-missing ()
  "API key lookup should return nil for unknown host."
  (should-not (my/gptel-api-key "nonexistent.host")))

;;; Backend existence tests

(ert-deftest test-backends/copilot-backend-exists ()
  "Copilot backend should be registered."
  (should (boundp 'gptel--copilot)))

(ert-deftest test-backends/gemini-backend-exists ()
  "Gemini backend should be registered."
  (should (boundp 'gptel--gemini)))

(ert-deftest test-backends/minimax-backend-exists ()
  "MiniMax backend should be registered."
  (should (boundp 'gptel--minimax)))

(ert-deftest test-backends/moonshot-backend-exists ()
  "Moonshot backend should be registered."
  (should (boundp 'gptel--moonshot)))

(ert-deftest test-backends/deepseek-backend-exists ()
  "DeepSeek backend should be registered."
  (should (boundp 'gptel--deepseek)))

;;; Model list tests

(ert-deftest test-backends/minimax-has-models ()
  "MiniMax backend should have models defined."
  (let ((backend gptel--minimax))
    (should (gptel-backend-models backend))))

(ert-deftest test-backends/moonshot-has-models ()
  "Moonshot backend should have models defined."
  (let ((backend gptel--moonshot))
    (should (gptel-backend-models backend))))

;;; Curl args tests

(ert-deftest test-backends/minimax-has-curl-args ()
  "MiniMax backend should have custom curl args."
  (let ((backend gptel--minimax))
    (should (gptel-backend-curl-args backend))))

(provide 'test-gptel-ext-backends)
;;; test-gptel-ext-backends.el ends here