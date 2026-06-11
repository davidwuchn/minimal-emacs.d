;;; test-skill-eval-opencode.el --- Tests for skill eval assertion engine -*- lexical-binding: t; no-byte-compile: t; -*-

(require 'ert)
(require 'cl-lib)

;; Load the module under test
(add-to-list 'load-path
             (expand-file-name "lisp/modules"
                               (file-name-directory (or load-file-name
                                                        (buffer-file-name)
                                                        default-directory))))
(require 'gptel-auto-workflow-skill-eval-opencode)

(defvar test-skill-eval--project-root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name
                             (buffer-file-name)
                             default-directory))))
  "Project root directory for test file resolution.")

;; ── Group 1: YAML Parsing ──

(ert-deftest test-skill-eval/parse-task-yaml ()
  "Parse a temporary YAML task file and verify the plist structure."
  (let ((temp-file (make-temp-file "skill-eval-test-" nil ".yaml")))
    (unwind-protect
        (progn
          (with-temp-file temp-file
            (insert "---\n")
            (insert "name: test-task\n")
            (insert "skill: brepl\n")
            (insert "description: \"A test task\"\n")
            (insert "prompt: |\n")
            (insert "  Evaluate (+ 1 2) in Clojure.\n")
            (insert "  Use the brepl SKILL.md.\n")
            (insert "expected_behaviors:\n")
            (insert "  - type: tool-used\n")
            (insert "    tool: nrepl\n")
            (insert "    description: \"Uses nREPL\"\n")
            (insert "  - type: output-contains\n")
            (insert "    text: \"3\"\n")
            (insert "    description: \"Result is 3\"\n")
            (insert "forbidden_behaviors:\n")
            (insert "  - type: pattern-absent\n")
            (insert "    pattern: \"ert-run-tests-batch\"\n")
            (insert "    description: \"No test runner\"\n")
            (insert "---\n"))
          (let ((task (gptel-auto-workflow-skill-eval-parse-task temp-file)))
            (should (string= (plist-get task :name) "test-task"))
            (should (string= (plist-get task :skill) "brepl"))
            (should (string= (plist-get task :description) "A test task"))
            (should (string= (plist-get task :prompt)
                             "Evaluate (+ 1 2) in Clojure.\nUse the brepl SKILL.md."))
            (let ((expected (plist-get task :expected)))
              (should (= (length expected) 2))
              (should (string= (plist-get (nth 0 expected) :type) "tool-used"))
              (should (string= (plist-get (nth 1 expected) :type) "output-contains")))
            (let ((forbidden (plist-get task :forbidden)))
              (should (= (length forbidden) 1))
              (should (string= (plist-get (nth 0 forbidden) :type) "pattern-absent")))))
      (ignore-errors (delete-file temp-file)))))

;; ── Group 2: Assertion Checks ──

(ert-deftest test-skill-eval/assertion-tool-used-pass ()
  "tool-used assertion passes when tool name is in transcript."
  (let* ((assertion '(:type "tool-used" :tool "emacsclient" :description "Uses emacsclient"))
         (transcript "Connecting with emacsclient --socket-name...")
         (result (gptel-auto-workflow-skill-eval-check-assertion assertion transcript)))
    (should (plist-get result :pass))
    (should (string= (plist-get result :description) "Uses emacsclient"))))

(ert-deftest test-skill-eval/assertion-tool-used-fail ()
  "tool-used assertion fails when tool name is not in transcript."
  (let* ((assertion '(:type "tool-used" :tool "emacsclient" :description "Uses emacsclient"))
         (transcript "Using curl to fetch the endpoint.")
         (result (gptel-auto-workflow-skill-eval-check-assertion assertion transcript)))
    (should-not (plist-get result :pass))))

(ert-deftest test-skill-eval/assertion-pattern-present-pass ()
  "pattern-present passes when regex matches transcript."
  (let* ((assertion '(:type "pattern-present" :pattern "nrepl-send-request" :description "nREPL used"))
         (transcript "Calling nrepl-send-request with eval op...")
         (result (gptel-auto-workflow-skill-eval-check-assertion assertion transcript)))
    (should (plist-get result :pass))))

(ert-deftest test-skill-eval/assertion-pattern-absent-pass ()
  "pattern-absent passes when pattern is NOT in transcript."
  (let* ((assertion '(:type "pattern-absent" :pattern "ert-run-tests-batch" :description "No Emacs test runner"))
         (transcript "Hello world, this is a simple response.")
         (result (gptel-auto-workflow-skill-eval-check-assertion assertion transcript)))
    (should (plist-get result :pass))))

(ert-deftest test-skill-eval/assertion-pattern-absent-fail ()
  "pattern-absent fails when pattern IS in transcript."
  (let* ((assertion '(:type "pattern-absent" :pattern "ert-run-tests-batch" :description "No Emacs test runner"))
         (transcript "I'll run ert-run-tests-batch to execute the tests.")
         (result (gptel-auto-workflow-skill-eval-check-assertion assertion transcript)))
    (should-not (plist-get result :pass))))

(ert-deftest test-skill-eval/assertion-output-contains-pass ()
  "output-contains passes when literal text is in transcript."
  (let* ((assertion '(:type "output-contains" :text "3" :description "Result includes 3"))
         (transcript "Computing sum... Result: 3")
         (result (gptel-auto-workflow-skill-eval-check-assertion assertion transcript)))
    (should (plist-get result :pass))))

;; ── Group 3: Full Grading ──

(ert-deftest test-skill-eval/grade-good-transcript ()
  "Full grading of a good transcript yields a high pass count."
  (let* ((task '(:name "brepl-basic"
                 :expected ((:type "tool-used" :tool "nrepl" :description "Uses nREPL")
                            (:type "pattern-present" :pattern "nrepl-send-request\\|bb.*nrepl\\|brepl" :description "nREPL protocol")
                            (:type "output-contains" :text "3" :description "Result is 3"))
                 :forbidden ((:type "pattern-absent" :pattern "ert-run-tests-batch" :description "No test runner"))))
         (transcript "I'll connect to the brepl using nrepl-send-request.\nStarting nREPL connection via bb.\nEvaluating (+ 1 2)...\nResult: 3\n")
         (result (gptel-auto-workflow-skill-eval-grade task transcript)))
    (should (= (plist-get result :pass-count) 4))
    (should (= (plist-get result :fail-count) 0))
    (should (= (plist-get result :total) 4))
    (should (= (length (plist-get result :results)) 4))))

(ert-deftest test-skill-eval/grade-bad-transcript ()
  "Grading an empty/bad transcript yields mostly failures."
  (let* ((task '(:name "brepl-basic"
                 :expected ((:type "tool-used" :tool "nrepl" :description "Uses nREPL")
                            (:type "pattern-present" :pattern "nrepl-send-request\\|bb.*nrepl\\|brepl" :description "nREPL protocol")
                            (:type "output-contains" :text "3" :description "Result is 3"))
                 :forbidden ((:type "pattern-absent" :pattern "ert-run-tests-batch" :description "No test runner"))))
         (transcript "I don't know how to help with that.")
         (result (gptel-auto-workflow-skill-eval-grade task transcript)))
    (should (= (plist-get result :pass-count) 1))
    (should (= (plist-get result :fail-count) 3))
    (should (= (plist-get result :total) 4))))

;; ── Group 4: Batch Loading ──

(ert-deftest test-skill-eval/load-tasks-from-dir ()
  "Load tasks from the actual task directory and verify at least 3 found."
  (let* ((task-dir (expand-file-name "assistant/skills/_eval-tasks/"
                                      test-skill-eval--project-root))
         (tasks (gptel-auto-workflow-skill-eval-load-tasks task-dir)))
    (should (>= (length tasks) 3))
    ;; Verify each task has the expected keys
    (dolist (task tasks)
      (should (plist-get task :name))
      (should (plist-get task :skill))
      (should (plist-get task :prompt))
      (should (listp (plist-get task :expected)))
       (should (listp (plist-get task :forbidden))))))

;; ── Group 5: Transcript Parsing ──

(ert-deftest test-skill-eval/parse-transcript-text ()
  "Text event appears in transcript."
  (let* ((json "{\"type\":\"text\",\"text\":\"Hello world\"}")
         (result (gptel-auto-workflow-skill-eval--parse-transcript-json json)))
    (should (string-match-p "Hello world" result))))

(ert-deftest test-skill-eval/parse-transcript-tool ()
  "Tool event produces TOOL: <name> OUTPUT: <output> in transcript."
  (let* ((json "{\"type\":\"tool\",\"tool\":\"bash\",\"state\":{\"input\":{\"command\":\"ls\"},\"output\":\"file.txt\"}}")
         (result (gptel-auto-workflow-skill-eval--parse-transcript-json json)))
    (should (string-match-p "TOOL: bash" result))
    (should (string-match-p "file.txt" result))))

(ert-deftest test-skill-eval/parse-transcript-mixed ()
  "Multiple events produce combined transcript."
  (let* ((lines '("{\"type\":\"text\",\"text\":\"I will run ls.\"}"
                   "{\"type\":\"tool\",\"tool\":\"bash\",\"state\":{\"input\":{\"command\":\"ls\"},\"output\":\"README.md\"}}"
                   "{\"type\":\"text\",\"text\":\"Done.\"}"))
         (json (string-join lines "\n"))
         (result (gptel-auto-workflow-skill-eval--parse-transcript-json json)))
    (should (string-match-p "I will run ls" result))
    (should (string-match-p "TOOL: bash" result))
    (should (string-match-p "Done" result))))

(ert-deftest test-skill-eval/parse-transcript-empty ()
  "Empty input produces empty transcript."
  (let ((result (gptel-auto-workflow-skill-eval--parse-transcript-json "")))
    (should (string= result ""))))

;; ── Group 6: Result Persistence ──

(ert-deftest test-skill-eval/save-result ()
  "Save result to JSON file and verify contents."
  (let* ((tmp-dir (make-temp-file "skill-eval-results-" t))
         (gptel-auto-workflow-skill-eval-results-dir tmp-dir)
         (result (list :skill "brepl" :task "brepl-basic" :variant "baseline"
                       :grade (list :pass-count 3 :fail-count 1 :total 4)
                       :duration 42.5
                       :transcript "Using nrepl to evaluate Clojure...")))
    (unwind-protect
        (let ((saved-path (gptel-auto-workflow-skill-eval-save-result result)))
          (should (file-exists-p saved-path))
          (with-temp-buffer
            (insert-file-contents saved-path)
            (let ((content (buffer-string)))
              (should (string-match-p "brepl" content))
              (should (string-match-p "pass-count" content))
              (should (string-match-p "42.5" content))))
          (delete-file saved-path))
      (ignore-errors (delete-directory tmp-dir t)))))

;; ── Group 7: A/B Recommendations ──

(defun test-skill-eval--mock-run (pass-count total)
  "Return a mock run result with PASS-COUNT and TOTAL."
  (list :transcript "mock transcript"
        :grade (list :pass-count pass-count
                     :fail-count (- total pass-count)
                     :total total)
        :duration 1.0))

(ert-deftest test-skill-eval/ab-recommendation-promote ()
  "Treatment clearly better than baseline -> promote."
  (cl-letf* (((symbol-function 'gptel-auto-workflow-skill-eval--locate-treatment-variant)
              (lambda (_) "/fake/treatment.md"))
             ((symbol-function 'gptel-auto-workflow-skill-eval-run)
              (lambda (_task file)
                (if (string-match-p "treatment" (or file ""))
                    (test-skill-eval--mock-run 4 4)
                  (test-skill-eval--mock-run 1 4)))))
    (let* ((task (list :name "test-task" :skill "brepl"
                       :expected nil :forbidden nil))
           (result (gptel-auto-workflow-skill-eval-ab "brepl" task 1)))
      (should (string= (plist-get result :recommendation) "promote")))))

(ert-deftest test-skill-eval/ab-recommendation-reject ()
  "Treatment clearly worse than baseline -> reject."
  (cl-letf* (((symbol-function 'gptel-auto-workflow-skill-eval--locate-treatment-variant)
              (lambda (_) "/fake/treatment.md"))
             ((symbol-function 'gptel-auto-workflow-skill-eval-run)
              (lambda (_task file)
                (if (string-match-p "treatment" (or file ""))
                    (test-skill-eval--mock-run 1 4)
                  (test-skill-eval--mock-run 4 4)))))
    (let* ((task (list :name "test-task" :skill "brepl"
                       :expected nil :forbidden nil))
           (result (gptel-auto-workflow-skill-eval-ab "brepl" task 1)))
      (should (string= (plist-get result :recommendation) "reject")))))

(ert-deftest test-skill-eval/ab-recommendation-indeterminate ()
  "Similar results -> indeterminate."
  (let ((run-call-count 0))
    (cl-letf (((symbol-function 'gptel-auto-workflow-skill-eval--locate-treatment-variant)
               (lambda (_) "/fake/treatment.md"))
              ((symbol-function 'gptel-auto-workflow-skill-eval-run)
               (lambda (_task _file)
                 (test-skill-eval--mock-run 3 4))))
      (let* ((task (list :name "test-task" :skill "brepl"
                         :expected nil :forbidden nil))
             (result (gptel-auto-workflow-skill-eval-ab "brepl" task 1)))
        (should (string= (plist-get result :recommendation)
                         "indeterminate"))))))

;;; test-skill-eval-opencode.el ends here
