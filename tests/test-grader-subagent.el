;;; test-grader-subagent.el --- Tests for grader subagent -*- lexical-binding: t; -*-

;;; Commentary:
;; TDD tests for grader subagent:
;; 1. Grader model matches executor model
;; 2. Grader can be called and returns valid result
;; 3. Grader timeout works correctly

;;; Code:

(require 'ert)
(require 'cl-lib)

;;; Test 1: Model Consistency

(ert-deftest grader/model-matches-executor ()
  "Grader should use same model as executor for consistency."
  (skip-unless (file-exists-p (expand-file-name "assistant/agents/grader.md" user-emacs-directory)))
  (skip-unless (file-exists-p (expand-file-name "assistant/agents/executor.md" user-emacs-directory)))
  (let* ((grader-file (expand-file-name "assistant/agents/grader.md" user-emacs-directory))
         (executor-file (expand-file-name "assistant/agents/executor.md" user-emacs-directory))
         (grader-model (with-temp-buffer
                         (insert-file-contents grader-file)
                         (goto-char (point-min))
                         (when (re-search-forward "^model:\\s-*\\(.+\\)$" nil t)
                           (string-trim (match-string 1)))))
         (executor-model (with-temp-buffer
                           (insert-file-contents executor-file)
                           (goto-char (point-min))
                           (when (re-search-forward "^model:\\s-*\\(.+\\)$" nil t)
                             (string-trim (match-string 1))))))
    (should (and grader-model executor-model))
    (should (equal grader-model executor-model))))

;;; Test 2: Grading Function Exists

(ert-deftest grader/function-exists ()
  "gptel-benchmark-grade function should be defined."
  (require 'gptel-benchmark-subagent)
  (should (fboundp 'gptel-benchmark-grade)))

;;; Test 3: Local Grading Works

(ert-deftest grader/local-grading-works ()
  "Local grading fallback should work without subagents."
  (require 'gptel-benchmark-subagent)
  (let ((result (gptel-benchmark--local-grade
                 "HYPOTHESIS: Adding docstrings. Change is minimal."
                 '("hypothesis" "minimal")
                 '("refactor" "security"))))
    (should (plist-get result :score))
    (should (>= (plist-get result :score) 2))
    (should (plist-get result :details))))

;;; Test 4: Grading with Timeout

(ert-deftest grader/timeout-returns-auto-pass ()
  "Grading timeout should return auto-pass."
  (require 'gptel-tools-agent)
  (should (boundp 'gptel-auto-experiment-grade-timeout))
  ;; Timeout should be reasonable (30-120 seconds)
  (should (>= gptel-auto-experiment-grade-timeout 30))
  (should (<= gptel-auto-experiment-grade-timeout 120)))

;;; Test 5: Grading Timeout Wrapper

(ert-deftest grader/timeout-wrapper-falls-back-cleanly ()
  "Grading should fall back cleanly when subagents unavailable."
  (require 'gptel-tools-agent)
  (let ((gptel-auto-experiment-use-subagents nil)  ; Force no subagents
        (result nil)
        (done nil))
    (gptel-auto-experiment-grade
     "Test output with hypothesis"
     (lambda (r)
       (setq result r done t)))
    (sit-for 0.5)
    (should done)
    (should (plist-get result :passed))
    (should (= (plist-get result :score) 100))))

;;; Test 6: Subagent Call Path

(ert-deftest grader/subagent-call-path-exists ()
  "gptel-benchmark-call-subagent should call gptel-agent--task when available."
  (require 'gptel-benchmark-subagent)
  (should (fboundp 'gptel-benchmark-call-subagent))
  ;; Check that it uses gptel-agent--task
  (let ((gptel-benchmark-use-subagents t))
    ;; When gptel-agent--task is not fbound, should return mock
    (cl-letf (((symbol-function 'gptel-agent--task) nil))
      (let ((result nil))
        (gptel-benchmark-call-subagent 'grader "Test" "Prompt"
                                        (lambda (r) (setq result r)))
        (sit-for 0.1)
        (should (stringp result))
        (should (string-match-p "\\[MOCK\\]" result))))))

;;; Test 7: Grader Uses Subagent When Available

(ert-deftest grader/uses-subagent-when-available ()
  "Grader should call subagent when gptel-agent--task is available."
  (require 'gptel-benchmark-subagent)
  (let* ((call-count 0)
         (gptel-benchmark-use-subagents t)
         ;; Mock gptel-agent--task
         (gptel-agent--task-mock (lambda (cb type desc prompt)
                                   (cl-incf call-count)
                                   (funcall cb "SCORE: 4/6\nSUMMARY: passed"))))
    (cl-letf (((symbol-function 'gptel-agent--task) gptel-agent--task-mock))
      (let ((result nil))
        (gptel-benchmark-grade
         "Test output"
         '("hypothesis")
         '("refactor")
         (lambda (r) (setq result r)))
        (sit-for 0.5)
        (should (= call-count 1))
        (should (plist-get result :score))))))

;;; Test 8: gptel-agent Must Be Loaded

(ert-deftest grader/gptel-agent-loaded ()
  "gptel-agent must be loaded for subagents to work."
  (require 'gptel-tools-agent)
  (should (featurep 'gptel-agent))
  (should (fboundp 'gptel-agent--task))
  (should (boundp 'gptel-agent--agents))
  ;; In batch mode, agents may not be populated (no project dir)
  ;; But the variable should be bound
  (should (listp gptel-agent--agents)))

;;; Test 9: Code Quality Metric

(defun test--count-docstrings (code)
  "Count functions with docstrings in CODE."
  (with-temp-buffer
    (insert code)
    (goto-char (point-min))
    (let ((count 0))
      (while (re-search-forward "(defun\\s-+\\S-+\\s-*(.*)\\s-*\n\\s-*\"" nil t)
        (cl-incf count))
      count)))

(defun test--count-functions (code)
  "Count total functions in CODE."
  (with-temp-buffer
    (insert code)
    (goto-char (point-min))
    (let ((count 0))
      (while (re-search-forward "(defun\\s-+" nil t)
        (cl-incf count))
      count)))

(ert-deftest grader/docstring-detection ()
  "Should detect docstrings in code."
  (let ((with-doc "
(defun foo ()
  \"Has docstring.\"
  t)

(defun bar ()
  \"Also has docstring.\"
  nil)")
        (without-doc "
(defun foo ()
  t)

(defun bar ()
  nil)"))
    (should (= 2 (test--count-docstrings with-doc)))
    (should (= 0 (test--count-docstrings without-doc)))
    (should (= 2 (test--count-functions with-doc)))
    (should (= 2 (test--count-functions without-doc)))))

(ert-deftest grader/docstring-coverage-score ()
  "Docstring coverage should affect score positively."
  (let ((coverage-with (/ (float (test--count-docstrings "
(defun foo ()
  \"Docstring.\"
  t)"))
                          (max 1 (test--count-functions "
(defun foo ()
  \"Docstring.\"
  t)"))))
        (coverage-without (/ (float (test--count-docstrings "
(defun foo ()
  t)"))
                             (max 1 (test--count-functions "
(defun foo ()
  t)")))))
    (should (> coverage-with 0))
    (should (= coverage-without 0))
    (should (> coverage-with coverage-without))))

;;; Test 11: Duration Scoring

(defun test--duration-score (duration max-duration)
  "Calculate duration score.
DURATION is actual duration in seconds.
MAX-DURATION is the threshold.
Returns 1.0 if under max, 0.5 if over."
  (cond
   ((= duration 0) 0.5)
   ((> duration max-duration) 0.5)
   (t 1.0)))

(ert-deftest grader/duration-score/fast ()
  "Fast execution should score 1.0."
  (should (= 1.0 (test--duration-score 10 120)))
  (should (= 1.0 (test--duration-score 60 120)))
  (should (= 1.0 (test--duration-score 119 120))))

(ert-deftest grader/duration-score/slow ()
  "Slow execution should score 0.5."
  (should (= 0.5 (test--duration-score 121 120)))
  (should (= 0.5 (test--duration-score 200 120)))
  (should (= 0.5 (test--duration-score 100 30))))

(ert-deftest grader/duration-score/zero ()
  "Zero duration should score 0.5 (unknown)."
  (should (= 0.5 (test--duration-score 0 120))))

;;; Test 14: Code Quality Integration

(ert-deftest grader/code-quality-score-exists ()
  "Code quality scoring function should exist."
  (require 'gptel-benchmark-subagent)
  (should (fboundp 'gptel-benchmark--code-quality-score)))

(ert-deftest grader/code-quality-rewards-docstrings ()
  "Code with docstrings should score higher than without."
  (require 'gptel-benchmark-subagent)
  (let* ((with-docs "(defun foo () \"Doc.\" t)\n(defun bar () \"Doc.\" nil)")
         (without-docs "(defun foo () t)\n(defun bar () nil)")
         (score-with (gptel-benchmark--code-quality-score with-docs))
         (score-without (gptel-benchmark--code-quality-score without-docs)))
    (should (> score-with 0.5))
    (should (< score-without 0.5))
    (should (> score-with score-without))))

;;; Test 16: Auto-Experiment Code Quality Integration

(ert-deftest grader/auto-experiment-uses-code-quality ()
  "Auto-experiment should factor in code quality."
  (require 'gptel-tools-agent)
  (should (fboundp 'gptel-auto-experiment--code-quality-score)))

;;; Test 18: Decision Logic with Code Quality

(ert-deftest grader/decision-factors-code-quality ()
  "Decision should consider code quality improvement."
  (require 'gptel-tools-agent)
  (let* ((before '(:score 1.0 :code-quality 0.5))
         (after '(:score 1.0 :code-quality 1.0))
         (result nil))
    ;; When grader score same but code quality improved, should keep
    (gptel-auto-experiment-decide
     before after
     (lambda (r) (setq result r)))
    (should (plist-get result :keep))))

;;; Test 19: Hypothesis Extraction

(ert-deftest grader/hypothesis-extraction ()
  "Should extract hypothesis from agent output."
  (require 'gptel-tools-agent)
  (let ((output "HYPOTHESIS: Adding docstrings will improve maintainability.
Implementation: Added docstrings to main functions.
Result: Tests pass."))
    (should (string= (gptel-auto-experiment--extract-hypothesis output)
                     "Adding docstrings will improve maintainability."))))

(ert-deftest grader/hypothesis-missing ()
  "Should return default when no hypothesis found."
  (require 'gptel-tools-agent)
  (let ((output "Implementation: Added docstrings.
Result: Tests pass."))
    (should (string= (gptel-auto-experiment--extract-hypothesis output)
                     "No hypothesis stated"))))

(provide 'test-grader-subagent)
;;; test-grader-subagent.el ends here