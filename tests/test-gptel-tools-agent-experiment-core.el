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

(ert-deftest test-experiment-core/grader-bypass-p-all-conditions-met ()
  "All conditions met: t."
  (should (gptel-auto-experiment--grader-bypass-p
           t 9 10 nil (list :nucleus-passed t) nil t)))

(ert-deftest test-experiment-core/grader-bypass-p-grade-passed-nil ()
  "grade-passed nil → nil."
  (should-not (gptel-auto-experiment--grader-bypass-p
               nil 9 10 nil nil nil t)))

(ert-deftest test-experiment-core/grader-bypass-p-score-below-threshold ()
  "Score 5/10 (50%) < 0.75 → nil."
  (should-not (gptel-auto-experiment--grader-bypass-p
               t 5 10 nil nil nil t)))

(ert-deftest test-experiment-core/grader-bypass-p-zero-total ()
  "Total=0 → nil (avoid divide-by-zero)."
  (should-not (gptel-auto-experiment--grader-bypass-p
               t 5 0 nil nil nil t)))

(ert-deftest test-experiment-core/grader-bypass-p-grader-only-failure ()
  ":grader-only-failure → nil."
  (should-not (gptel-auto-experiment--grader-bypass-p
               t 9 10 (list :grader-only-failure t) nil nil t)))

(ert-deftest test-experiment-core/grader-bypass-p-quota-exhausted ()
  ":quota-exhausted → nil."
  (should-not (gptel-auto-experiment--grader-bypass-p
               t 9 10 (list :quota-exhausted t) nil nil t)))

(ert-deftest test-experiment-core/grader-bypass-p-blind-mode ()
  ":blind-mode → nil."
  (should-not (gptel-auto-experiment--grader-bypass-p
               t 9 10 (list :blind-mode t) nil nil t)))

(ert-deftest test-experiment-core/grader-bypass-p-auto-pass-details ()
  ":details containing 'auto-pass' → nil."
  (should-not (gptel-auto-experiment--grader-bypass-p
               t 9 10 (list :details "auto-pass: skipped") nil nil t)))

(ert-deftest test-experiment-core/grader-bypass-p-validation-error ()
  "validation-error non-nil → nil."
  (should-not (gptel-auto-experiment--grader-bypass-p
               t 9 10 nil nil "syntax error" t)))

(ert-deftest test-experiment-core/grader-bypass-p-tests-not-passed ()
  "tests-passed nil → nil."
  (should-not (gptel-auto-experiment--grader-bypass-p
               t 9 10 nil nil nil nil)))

(ert-deftest test-experiment-core/grader-bypass-p-nucleus-not-passed ()
  ":nucleus-passed nil → nil."
  (should-not (gptel-auto-experiment--grader-bypass-p
               t 9 10 nil (list :nucleus-passed nil) nil t)))

(ert-deftest test-experiment-core/grader-bypass-p-threshold-exact ()
  "Score 75/100 = 0.75 exact → t."
  (should (gptel-auto-experiment--grader-bypass-p
           t 75 100 nil (list :nucleus-passed t) nil t)))

(ert-deftest test-experiment-core/grader-bypass-p-threshold-just-below ()
  "Score 74/100 < 0.75 → nil."
  (should-not (gptel-auto-experiment--grader-bypass-p
               t 74 100 nil nil nil t)))
