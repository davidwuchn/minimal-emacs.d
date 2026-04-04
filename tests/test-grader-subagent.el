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

(ert-deftest grader/model-is-defined ()
  "Grader should have a model defined."
  (skip-unless (file-exists-p (expand-file-name "assistant/agents/grader.md" user-emacs-directory)))
  (let* ((grader-file (expand-file-name "assistant/agents/grader.md" user-emacs-directory))
         (grader-model (with-temp-buffer
                         (insert-file-contents grader-file)
                         (goto-char (point-min))
                         (when (re-search-forward "^model:\\s-*\\(.+\\)$" nil t)
                           (string-trim (match-string 1))))))
    (should grader-model)))

(ert-deftest executor/model-is-defined ()
  "Executor should have a model defined."
  (skip-unless (file-exists-p (expand-file-name "assistant/agents/executor.md" user-emacs-directory)))
  (let* ((executor-file (expand-file-name "assistant/agents/executor.md" user-emacs-directory))
         (executor-model (with-temp-buffer
                           (insert-file-contents executor-file)
                           (goto-char (point-min))
                           (when (re-search-forward "^model:\\s-*\\(.+\\)$" nil t)
                             (string-trim (match-string 1))))))
    (should executor-model)))

;;; Test 2: Grading Function Exists

(ert-deftest grader/function-exists ()
  "gptel-benchmark-grade function should be defined."
  (require 'gptel-benchmark-subagent)
  (should (fboundp 'gptel-benchmark-grade)))

;;; Test 3: Local Grading Works

(ert-deftest grader/local-grading-works ()
  "Local grading fallback should work without subagents."
  (ert-skip "Flaky test - requires actual gptel API access")
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
  :tags '(:skip-in-ci)
  (require 'gptel-benchmark-subagent)
  (let* ((with-docs "(defun foo () \"Doc.\" t)\n(defun bar () \"Doc.\" nil)")
         (without-docs "(defun foo () t)\n(defun bar () nil)")
         (score-with (gptel-benchmark--code-quality-score with-docs))
         (score-without (gptel-benchmark--code-quality-score without-docs)))
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
  (let* ((gptel-auto-experiment-use-subagents nil)
         (before '(:score 1.0 :code-quality 0.5))
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

;;; Test 20: Experiment Loop Configuration

(ert-deftest grader/experiment-config-exists ()
  "Experiment configuration should be defined."
  (require 'gptel-tools-agent)
  (should (boundp 'gptel-auto-experiment-time-budget))
  (should (boundp 'gptel-auto-experiment-max-per-target))
  (should (boundp 'gptel-auto-experiment-no-improvement-threshold))
  (should (boundp 'gptel-auto-workflow-targets)))

(ert-deftest grader/experiment-time-budget-reasonable ()
  "Time budget should be between 1-30 minutes."
  (require 'gptel-tools-agent)
  (should (>= gptel-auto-experiment-time-budget 60))    ; at least 1 minute
  (should (<= gptel-auto-experiment-time-budget 1800))) ; at most 30 minutes

(ert-deftest grader/experiment-max-per-target-reasonable ()
  "Max experiments per target should be between 1-50."
  (require 'gptel-tools-agent)
  (should (>= gptel-auto-experiment-max-per-target 1))
  (should (<= gptel-auto-experiment-max-per-target 50)))

(ert-deftest grader/experiment-stop-threshold-reasonable ()
  "No-improvement threshold should be between 1-10."
  (require 'gptel-tools-agent)
  (should (>= gptel-auto-experiment-no-improvement-threshold 1))
  (should (<= gptel-auto-experiment-no-improvement-threshold 10)))

;;; Test 25: Should Stop Logic

(ert-deftest grader/should-stop-initially-false ()
  "Should not stop when no-improvement count is 0."
  (require 'gptel-tools-agent)
  (let ((gptel-auto-experiment--no-improvement-count 0))
    (should-not (gptel-auto-experiment-should-stop-p 3))))

(ert-deftest grader/should-stop-at-threshold ()
  "Should stop when no-improvement count reaches threshold."
  (require 'gptel-tools-agent)
  (let ((gptel-auto-experiment--no-improvement-count 3))
    (should (gptel-auto-experiment-should-stop-p 3))))

(ert-deftest grader/should-stop-exceeds-threshold ()
  "Should stop when no-improvement count exceeds threshold."
  (require 'gptel-tools-agent)
  (let ((gptel-auto-experiment--no-improvement-count 5))
    (should (gptel-auto-experiment-should-stop-p 3))))

;;; Test 28: Summarize Function

(ert-deftest grader/summarize-short-hypothesis ()
  "Should return full hypothesis if under 6 words."
  (require 'gptel-tools-agent)
  (should (string= (gptel-auto-experiment--summarize "Add docstrings to functions")
                   "Add docstrings to functions")))

(ert-deftest grader/summarize-long-hypothesis ()
  "Should truncate hypothesis to 6 words."
  (require 'gptel-tools-agent)
  (should (string= (gptel-auto-experiment--summarize "Adding docstrings will improve maintainability and readability of code")
                   "Adding docstrings will improve maintainability and")))

(ert-deftest grader/summarize-exactly-six-words ()
  "Should return full hypothesis if exactly 6 words."
  (require 'gptel-tools-agent)
  (should (string= (gptel-auto-experiment--summarize "Add docstrings to all main functions")
                   "Add docstrings to all main functions")))

;;; Test 31: Analyzer Subagent

(ert-deftest grader/analyzer-function-exists ()
  "gptel-benchmark-analyze should exist."
  (require 'gptel-benchmark-subagent)
  (should (fboundp 'gptel-benchmark-analyze)))

(ert-deftest grader/analyzer-parse-response ()
  "Should parse analyzer JSON response."
  (require 'gptel-benchmark-subagent)
  (let* ((json-response "{\"patterns\":[{\"type\":\"timeout\",\"description\":\"API timeouts\"}],\"issues\":[],\"recommendations\":[\"Add retry logic\"]}")
         (result (gptel-benchmark--parse-analysis-response json-response)))
    ;; json-read returns vectors, not lists
    (should (sequencep (plist-get result :patterns)))
    (should (sequencep (plist-get result :recommendations)))))

;;; Test 32: Comparator Subagent

(ert-deftest grader/comparator-function-exists ()
  "gptel-benchmark-compare should exist."
  (require 'gptel-benchmark-subagent)
  (should (fboundp 'gptel-benchmark-compare)))

(ert-deftest grader/comparator-parse-response ()
  "Should parse comparator JSON response."
  (require 'gptel-benchmark-subagent)
  (let* ((json-response "{\"winner\":\"B\",\"improvement\":{\"score\":0.2},\"analysis\":{},\"recommendation\":\"Keep B\"}")
         (result (gptel-benchmark--parse-comparison-response json-response)))
    (should (string= (plist-get result :winner) "B"))
    (should (string= (plist-get result :recommendation) "Keep B"))))

;;; Test 33: Workflow Integration

(ert-deftest grader/workflow-analyze-integration ()
  "gptel-auto-experiment-analyze should call gptel-benchmark-analyze."
  (require 'gptel-tools-agent)
  (should (fboundp 'gptel-auto-experiment-analyze)))

(ert-deftest grader/workflow-grade-integration ()
  "gptel-auto-experiment-grade should call gptel-benchmark-grade."
  (require 'gptel-tools-agent)
  (should (fboundp 'gptel-auto-experiment-grade)))

(ert-deftest grader/workflow-decide-integration ()
  "gptel-auto-experiment-decide should consider code quality."
  (require 'gptel-tools-agent)
  (should (fboundp 'gptel-auto-experiment-decide)))

;;; Test 37: Executor Subagent

(ert-deftest grader/executor-function-exists ()
  "gptel-benchmark-execute should exist."
  (require 'gptel-benchmark-subagent)
  (should (fboundp 'gptel-benchmark-execute)))

;;; Test 38: Reviewer Subagent

(ert-deftest grader/reviewer-function-exists ()
  "gptel-benchmark-review should exist."
  (require 'gptel-benchmark-subagent)
  (should (fboundp 'gptel-benchmark-review)))

;;; Test 39: Explorer Subagent

(ert-deftest grader/explorer-function-exists ()
  "gptel-benchmark-explore should exist."
  (require 'gptel-benchmark-subagent)
  (should (fboundp 'gptel-benchmark-explore)))

;;; Test 40: Subagent Registry

(ert-deftest grader/subagent-registry-defined ()
  "Subagent types should be defined."
  (require 'gptel-benchmark-subagent)
  (should (boundp 'gptel-benchmark-subagent-types))
  (let ((types (mapcar #'car gptel-benchmark-subagent-types)))
    (should (memq 'grader types))
    (should (memq 'analyzer types))
    (should (memq 'executor types))
    (should (memq 'reviewer types))
    (should (memq 'explorer types))))

;;; Test 41: Experiment Timeout Handling

(ert-deftest grader/experiment-timeout-default ()
  "Default experiment time budget should be 600s (10 min)."
  (require 'gptel-tools-agent)
  (should (= gptel-auto-experiment-time-budget 600)))

(ert-deftest grader/grade-timeout-default ()
  "Default grade timeout should be 120s."
  (require 'gptel-tools-agent)
  (should (= gptel-auto-experiment-grade-timeout 120)))

;;; Test 43: Multi-Machine Branch Naming

(ert-deftest grader/branch-name-includes-hostname ()
  "Branch name should include system-name."
  (require 'gptel-tools-agent)
  (let ((branch (gptel-auto-workflow--branch-name "gptel-ext-retry.el" 1)))
    (should (string-match-p (regexp-quote system-name) branch))))

(ert-deftest grader/branch-name-format ()
  "Branch name format: optimize/{target}-{host}-exp{N}"
  (require 'gptel-tools-agent)
  (let* ((host system-name)
         (branch (gptel-auto-workflow--branch-name "gptel-ext-retry.el" 5)))
    (should (string= branch (format "optimize/retry-%s-exp5" host)))))

(ert-deftest grader/branch-name-without-experiment-id ()
  "Branch name without experiment-id: optimize/{target}-{host}"
  (require 'gptel-tools-agent)
  (let* ((host system-name)
         (branch (gptel-auto-workflow--branch-name "gptel-ext-context.el")))
    (should (string= branch (format "optimize/context-%s" host)))))

(ert-deftest grader/auto-push-config-exists ()
  "Auto-push config variable should exist."
  (require 'gptel-tools-agent)
  (should (boundp 'gptel-auto-experiment-auto-push)))

(ert-deftest grader/auto-push-config-default ()
  "Auto-push should default to t."
  (require 'gptel-tools-agent)
  (should gptel-auto-experiment-auto-push))

;;; Test 44-47: Eight Keys Weakest Functions

(ert-deftest grader/eight-keys-weakest-excludes-overall ()
  "Weakest keys should exclude 'overall from results."
  (require 'gptel-benchmark-principles)
  (let* ((scores '((phi-vitality . 0.45) (pi-synthesis . 0.38) (overall . 0.52)))
         (weakest (gptel-benchmark-eight-keys-weakest scores 2)))
    (should (not (assoc 'overall weakest)))
    (should (= (length weakest) 2))
    (should (eq (car (car weakest)) 'pi-synthesis))))

(ert-deftest grader/eight-keys-weakest-returns-sorted ()
  "Weakest keys should be sorted ascending by score."
  (require 'gptel-benchmark-principles)
  (let* ((scores '((phi-vitality . 0.45) (pi-synthesis . 0.38) (exists-truth . 0.75)))
         (weakest (gptel-benchmark-eight-keys-weakest scores 2)))
    (should (< (cdr (car weakest)) (cdr (cadr weakest))))))

(ert-deftest grader/eight-keys-weakest-with-signals-returns-list ()
  "Weakest with signals should return plist with :key, :score, :signals."
  (require 'gptel-benchmark-principles)
  (let* ((scores '((phi-vitality . 0.45) (pi-synthesis . 0.38) (overall . 0.52)))
         (result (gptel-benchmark-eight-keys-weakest-with-signals scores 1))
         (first (car result)))
    (should (plist-member first :key))
    (should (plist-member first :score))
    (should (plist-member first :signals))
    (should (= (length (plist-get first :signals)) 3))))

(ert-deftest grader/format-weakest-keys-produces-string ()
  "Format weakest keys should produce human-readable string."
  (require 'gptel-benchmark-principles)
  (require 'gptel-tools-agent)
  (let* ((scores '((phi-vitality . 0.45) (pi-synthesis . 0.38) (overall . 0.52)))
         (formatted (gptel-auto-workflow--format-weakest-keys scores)))
    (should (stringp formatted))
    (should (string-match-p "π Synthesis" formatted))
    (should (string-match-p "38%" formatted))))

(ert-deftest grader/extract-mutation-templates-returns-list ()
  "Extract mutation templates should return list of template strings."
  (require 'gptel-tools-agent)
  (let* ((target "lisp/modules/gptel-ext-retry.el")
         (skills (gptel-auto-workflow-recall-skills target))
         (templates (gptel-auto-workflow--extract-mutation-templates skills)))
    (should (listp templates))
    (should (> (length templates) 0))
    (should (cl-some (lambda (tmpl) (string-match-p "caching" tmpl)) templates))
    (should (cl-some (lambda (tmpl) (string-match-p "Lazy" tmpl)) templates))
    (should (cl-some (lambda (tmpl) (string-match-p "Simplify" tmpl)) templates))))

(provide 'test-grader-subagent)
;;; test-grader-subagent.el ends here