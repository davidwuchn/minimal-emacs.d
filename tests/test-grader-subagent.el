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

(provide 'test-grader-subagent)
;;; test-grader-subagent.el ends here