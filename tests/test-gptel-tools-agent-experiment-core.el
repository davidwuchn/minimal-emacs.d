;;; test-gptel-tools-agent-experiment-core.el --- TDD tests for experiment-core -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'gptel-tools-agent-experiment-core)

(ert-deftest test-experiment-core/placeholder-hypothesis-p-non-string-is-t ()
  "Non-string hypothesis is always a placeholder (unresolved)."
  (should (gptel-auto-experiment--placeholder-hypothesis-p nil))
  (should (gptel-auto-experiment--placeholder-hypothesis-p 42))
  (should (gptel-auto-experiment--placeholder-hypothesis-p '(a b))))

(ert-deftest test-experiment-core/placeholder-hypothesis-p-empty-string ()
  "Empty or whitespace-only string is a placeholder."
  (should (gptel-auto-experiment--placeholder-hypothesis-p ""))
  (should (gptel-auto-experiment--placeholder-hypothesis-p "   "))
  (should (gptel-auto-experiment--placeholder-hypothesis-p "\n\t")))

(ert-deftest test-experiment-core/placeholder-hypothesis-p-bracketed-question ()
  "A hypothesis of the form '[What ...]' is a placeholder template."
  (should (gptel-auto-experiment--placeholder-hypothesis-p "[What is the impact?]"))
  (should (gptel-auto-experiment--placeholder-hypothesis-p "[What is X?]"))
  (should-not (gptel-auto-experiment--placeholder-hypothesis-p "[Why is the impact?]")))

(ert-deftest test-experiment-core/placeholder-hypothesis-p-real-hypothesis ()
  "A concrete hypothesis is not a placeholder."
  (should-not (gptel-auto-experiment--placeholder-hypothesis-p
               "Reduce TDD cycle time by 20%"))
  (should-not (gptel-auto-experiment--placeholder-hypothesis-p
               "Use φ-curve to estimate keep-rate"))
  (should-not (gptel-auto-experiment--placeholder-hypothesis-p
               "What if we tried a different approach?")))  ; not bracketed
