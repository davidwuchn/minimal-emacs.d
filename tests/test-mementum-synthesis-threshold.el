;;; test-mementum-synthesis-threshold.el --- Tests for synthesis threshold -*- lexical-binding: t; -*-
;;
;; Verifies that brief LLM synthesis results are accepted for
;; research-derived topics (insight-proposal-*, mistake-failure-pattern-*)
;; rather than skipped. The 15-line threshold is too strict when the LLM
;; already has enough context to give a 3-5 line summary.

;;; Code:

(require 'ert)
(require 'cl-lib)

(load-file (expand-file-name "lisp/modules/gptel-tools-agent-research.el"
                             default-directory))

(setq gptel-auto-workflow--headless t
      gptel-mementum-headless-auto-approve t)

(defvar test-synth--captured-msgs nil)

(defun test-synth--run (fn)
  "Run FN capturing all message output to test-synth--captured-msgs."
  (let ((test-synth--captured-msgs nil))
    (cl-letf (((symbol-function 'message)
               (lambda (fmt &rest args)
                 (push (apply #'format fmt args) test-synth--captured-msgs))))
      (funcall fn))
    (nreverse test-synth--captured-msgs)))

(defun test-synth--count-skips (msgs)
  (length (cl-remove-if-not (lambda (m) (string-match-p "Skip '" m)) msgs)))

(ert-deftest test-synth/insight-proposal-3-lines-accepted ()
  "insight-proposal-* with 3-line synthesis should NOT be skipped (>=3 threshold)."
  (let ((msgs (test-synth--run
              (lambda ()
                (gptel-mementum--handle-synthesis-result
                 "insight-proposal-foo-bar"
                 ["memory1.md" "memory2.md"]
                 "---\ntitle: Foo\nstatus: active\n---\n\n# Foo\n\nBrief insight about foo.")))))
    (should (= 0 (test-synth--count-skips msgs)))))

(ert-deftest test-synth/insight-proposal-1-line-skipped ()
  "insight-proposal-* with 1-line synthesis (below 3-line threshold) is skipped."
  (let ((msgs (test-synth--run
              (lambda ()
                (gptel-mementum--handle-synthesis-result
                 "insight-proposal-foo-bar"
                 ["memory1.md"]
                 "Brief one-liner.")))))
    (should (= 1 (test-synth--count-skips msgs)))))

(ert-deftest test-synth/general-topic-1-line-skipped ()
  "General topics still require >=15 lines (preserved original threshold)."
  (let ((msgs (test-synth--run
              (lambda ()
                (gptel-mementum--handle-synthesis-result
                 "random-foo-topic"
                 ["memory1.md"]
                 "Brief content.")))))
    (should (= 1 (test-synth--count-skips msgs)))))

(ert-deftest test-synth/research-prefix-3-lines-accepted ()
  "research-* topic with 3-line synthesis accepted (research-derived)."
  (let ((msgs (test-synth--run
              (lambda ()
                (gptel-mementum--handle-synthesis-result
                 "research-foo-persisted"
                 ["memory1.md" "memory2.md"]
                 "---\ntitle: Research\nstatus: active\n---\n\n# Research Foo\n\nKey finding here.")))))
    (should (= 0 (test-synth--count-skips msgs)))))

(ert-deftest test-synth/mistake-failure-pattern-3-lines-accepted ()
  "mistake-failure-pattern-* with 3-line synthesis accepted (>=3 threshold)."
  (let ((msgs (test-synth--run
              (lambda ()
                (gptel-mementum--handle-synthesis-result
                 "mistake-failure-pattern-foo-bar"
                 ["memory1.md" "memory2.md"]
                 "---\ntitle: Mistake\nstatus: active\n---\n\n# Mistake\n\nCommon pattern.")))))
    (should (= 0 (test-synth--count-skips msgs)))))

(provide 'test-mementum-synthesis-threshold)
;;; test-mementum-synthesis-threshold.el ends here
