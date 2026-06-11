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

;;; test-skill-eval-opencode.el ends here
