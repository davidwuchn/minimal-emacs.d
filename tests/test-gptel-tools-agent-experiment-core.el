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

(ert-deftest test-experiment-core/git-timeout-uses-default-when-no-config ()
  "When no config exists, return default minimum (300s)."
  (fmakunbound 'gptel-auto-workflow-git-timeout)
  (should (= 300 (gptel-auto-experiment--git-timeout))))

(ert-deftest test-experiment-core/git-timeout-uses-configured-value ()
  "When configured value exists, return max(configured, default)."
  (defvar gptel-auto-workflow-git-timeout 600)
  (should (= 600 (gptel-auto-experiment--git-timeout)))
  (makunbound 'gptel-auto-workflow-git-timeout))

(ert-deftest test-experiment-core/git-timeout-respects-minimum-override ()
  "Minimum override is the floor."
  (defvar gptel-auto-workflow-git-timeout 100)
  (should (= 300 (gptel-auto-experiment--git-timeout 300)))
  (makunbound 'gptel-auto-workflow-git-timeout))

(ert-deftest test-experiment-core/increment-no-improvement-count-from-zero ()
  "Counter starts at 0, increments to 1."
  (makunbound 'gptel-auto-experiment--no-improvement-count)
  (gptel-auto-experiment--increment-no-improvement-count)
  (should (= 1 gptel-auto-experiment--no-improvement-count)))

(ert-deftest test-experiment-core/increment-no-improvement-count-from-n ()
  "Counter increments from existing value."
  (makunbound 'gptel-auto-experiment--no-improvement-count)
  (setq gptel-auto-experiment--no-improvement-count 5)
  (gptel-auto-experiment--increment-no-improvement-count)
  (should (= 6 gptel-auto-experiment--no-improvement-count))
  (gptel-auto-experiment--increment-no-improvement-count)
  (should (= 7 gptel-auto-experiment--no-improvement-count)))

(ert-deftest test-experiment-core/increment-no-improvement-count-resilience-test ()
  "TDD regression: ensure the function isn't broken by special-form renames.
Calls the function with various inputs to ensure it returns a number.
Catches auto-evolution rename bugs (_if, _let*, _when)."
  (makunbound 'gptel-auto-experiment--no-improvement-count)
  (should (numberp (gptel-auto-experiment--increment-no-improvement-count)))
  (should (numberp (gptel-auto-experiment--increment-no-improvement-count)))
  (should (numberp (gptel-auto-experiment--increment-no-improvement-count)))
  (should (>= gptel-auto-experiment--no-improvement-count 3)))
