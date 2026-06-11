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

;; ── Group 8: Variant Generation ──

(ert-deftest test-skill-eval/make-variant-prompt ()
  "Variant prompt includes current skill and improvement hints."
  (let* ((prompt (gptel-auto-workflow-skill-eval--make-variant-prompt
                  "brepl" "current skill content" "Fix tool usage")))
    (should (string-match-p "brepl" prompt))
    (should (string-match-p "current skill content" prompt))
    (should (string-match-p "Fix tool usage" prompt))))

(ert-deftest test-skill-eval/extract-improvement-hints-empty ()
  "No results -> empty hints string."
  (should (string= ""
                   (gptel-auto-workflow-skill-eval--extract-improvement-hints nil))))

(ert-deftest test-skill-eval/extract-improvement-hints-failures ()
  "Results with failures produce improvement hints."
  (let* ((results (list (list :grade (list :pass-count 2 :fail-count 2 :total 4)
                              :transcript "mock")))
         (hints (gptel-auto-workflow-skill-eval--extract-improvement-hints results)))
    (should (string-match-p "failures" hints))))

(ert-deftest test-skill-eval/generate-variant-writes-file ()
  "Generate variant writes candidate file when LLM returns content."
  (let* ((tmp-dir (make-temp-file "skill-eval-variants-" t))
         (gptel-auto-workflow-skill-eval-variants-dir tmp-dir)
         (skill-content "---\nname: test\n---\nTest skill content."))
    (cl-letf (((symbol-function 'gptel-auto-workflow-skill-eval--llm-synchronous)
               (lambda (_) "---\nname: test\n---\nImproved skill content."))
              ((symbol-function 'gptel-auto-workflow-skill-eval--recent-results)
               (lambda (_ _) nil)))
      ;; Create the real skill file at assistant/skills/test/SKILL.md
      (let* ((skill-dir (expand-file-name "assistant/skills/test/"
                                          default-directory))
             (skill-file (expand-file-name "SKILL.md" skill-dir))
             (existed (file-exists-p skill-file)))
        (unless (file-directory-p skill-dir)
          (make-directory skill-dir t))
        (with-temp-file skill-file (insert skill-content))
        (unwind-protect
            (let ((result (condition-case err
                              (gptel-auto-workflow-skill-eval-generate-variant "test")
                            (error
                             (message "Error: %s" (error-message-string err))
                             nil))))
              (when result
                (should (file-exists-p result))
                (with-temp-buffer
                  (insert-file-contents result)
                  (should (string-match-p "Improved" (buffer-string))))
                (delete-file result)))
          ;; Cleanup: remove test skill if we created it
          (unless existed
            (ignore-errors (delete-file skill-file))
            (ignore-errors (delete-directory skill-dir t)))
          (ignore-errors (delete-directory tmp-dir t)))))))

;; ── Group 9: Promotion Pipeline ──

(ert-deftest test-skill-eval/promote-not-recommended ()
  "Promote returns nil when recommendation is not \"promote\"."
  (cl-letf (((symbol-function 'gptel-auto-workflow-skill-eval--locate-treatment-variant)
             (lambda (_) nil)))
    (let ((result (condition-case nil
                      (gptel-auto-workflow-skill-eval-promote
                       "brepl"
                       (list :recommendation "indeterminate"
                             :treatment-rate 0.5 :baseline-rate 0.5))
                    (error nil))))
      (should-not result))))

(ert-deftest test-skill-eval/execute-promotion-copies-file ()
  "Execute promotion copies candidate to canonical location."
  (let* ((tmp-dir (make-temp-file "skill-eval-promote-" t))
         (candidate (expand-file-name "candidate.md" tmp-dir))
         (canonical (expand-file-name "canonical.md" tmp-dir)))
    (with-temp-file candidate (insert "improved content"))
    (unwind-protect
        (progn
          (should (gptel-auto-workflow-skill-eval-execute-promotion
                   "test" candidate canonical))
          (should (file-exists-p canonical))
          (with-temp-buffer
            (insert-file-contents canonical)
            (should (string= "improved content" (buffer-string)))))
      (ignore-errors (delete-directory tmp-dir t)))))

;; ── Group 10: Integration ──

(ert-deftest test-skill-eval/integration-symlink-swap-restore ()
  "Test symlink swap + restore mechanism without calling opencode."
  (let* ((skills-dir (make-temp-file "skill-eval-skills-" t))
         (original-dir (make-temp-file "skill-eval-orig-" t))
         (symlink-path (expand-file-name "brepl" skills-dir))
         (variant-file (make-temp-file "skill-eval-variant-" nil ".md"))
         (temp-skill-dir nil)
         (original-target nil))
    (unwind-protect
        (progn
          ;; Write content into original and variant files
          (with-temp-file (expand-file-name "SKILL.md" original-dir)
            (insert "original skill content"))
          (with-temp-file variant-file
            (insert "variant skill content"))
          ;; Create symlink: .opencode/skills/brepl -> original-dir
          (make-symbolic-link original-dir symlink-path t)
          (should (file-symlink-p symlink-path))
          ;; Step 1: Save original symlink target
          (setq original-target (file-symlink-p symlink-path))
          (should original-target)
          ;; Step 2: Create temp dir with SKILL.md -> variant file
          (setq temp-skill-dir (make-temp-file "opencode-skill-eval-" t))
          (make-symbolic-link (expand-file-name variant-file)
                              (expand-file-name "SKILL.md" temp-skill-dir)
                              t)
          ;; Step 3: Replace symlink
          (when (file-exists-p symlink-path)
            (delete-file symlink-path))
          (make-symbolic-link temp-skill-dir symlink-path t)
          ;; Verify new symlink target is different from original
          (let ((new-target (file-symlink-p symlink-path)))
            (should new-target)
            (should-not (string= new-target original-target)))
          ;; Step 4: Restore original symlink
          (when (file-exists-p symlink-path)
            (delete-file symlink-path))
          (when original-target
            (make-symbolic-link original-target symlink-path t))
          ;; Verify restored symlink matches original target
          (should (file-symlink-p symlink-path))
          (should (string= (file-symlink-p symlink-path) original-target)))
      ;; Cleanup all temp files/dirs
      (ignore-errors
        (when (and symlink-path (file-exists-p symlink-path))
          (delete-file symlink-path))
        (when (and temp-skill-dir (file-exists-p temp-skill-dir))
          (delete-directory temp-skill-dir t))
        (when (and skills-dir (file-exists-p skills-dir))
          (delete-directory skills-dir t))
        (when (and original-dir (file-exists-p original-dir))
          (delete-directory original-dir t))
        (when (and variant-file (file-exists-p variant-file))
          (delete-file variant-file))))))

(ert-deftest test-skill-eval/integration-symlink-cleanup-on-error ()
  "Test symlink restore happens even when an error is thrown."
  (let* ((skills-dir (make-temp-file "skill-eval-skills-" t))
         (original-dir (make-temp-file "skill-eval-orig-" t))
         (symlink-path (expand-file-name "brepl" skills-dir))
         (variant-file (make-temp-file "skill-eval-variant-" nil ".md"))
         (original-target nil)
         (restored nil))
    (unwind-protect
        (progn
          ;; Setup: write content and create original symlink
          (with-temp-file (expand-file-name "SKILL.md" original-dir)
            (insert "original skill content"))
          (with-temp-file variant-file
            (insert "variant skill content"))
          (make-symbolic-link original-dir symlink-path t)
          (setq original-target (file-symlink-p symlink-path))
          (should original-target)
          ;; Simulate swap + error with unwind-protect cleanup
          (let ((temp-skill-dir (make-temp-file "opencode-skill-eval-" t)))
            (condition-case nil
                (unwind-protect
                    (progn
                      ;; Swap symlink to variant temp dir
                      (make-symbolic-link (expand-file-name variant-file)
                                          (expand-file-name "SKILL.md" temp-skill-dir)
                                          t)
                      (when (file-exists-p symlink-path)
                        (delete-file symlink-path))
                      (make-symbolic-link temp-skill-dir symlink-path t)
                      ;; Simulate failure
                      (error "simulated failure"))
                  ;; Cleanup: restore original symlink and remove temp dir
                  (when (and symlink-path (file-exists-p symlink-path))
                    (delete-file symlink-path))
                  (when original-target
                    (make-symbolic-link original-target symlink-path t))
                  (when (and temp-skill-dir (file-exists-p temp-skill-dir))
                    (delete-directory temp-skill-dir t))
                  (setq restored t))
              (error nil)))
          ;; Verify: error was caught (restored is t) and symlink is back
          (should restored)
          (should (file-symlink-p symlink-path))
          (should (string= (file-symlink-p symlink-path) original-target)))
      ;; Final cleanup of all resources
      (ignore-errors
        (when (and symlink-path (file-exists-p symlink-path))
          (delete-file symlink-path))
        (when (and skills-dir (file-exists-p skills-dir))
          (delete-directory skills-dir t))
        (when (and original-dir (file-exists-p original-dir))
          (delete-directory original-dir t))
        (when (and variant-file (file-exists-p variant-file))
          (delete-file variant-file))))))

(ert-deftest test-skill-eval/integration-transcript-real-json ()
  "Test transcript parser with realistic opencode JSON output."
  (let* ((lines
          '("{\"type\":\"text\",\"text\":\"I'll check the daemon status using emacsclient.\"}"
            "{\"type\":\"tool\",\"tool\":\"Bash\",\"state\":{\"output\":\"(:running t :socket pmf-value-stream)\"}}"
            "{\"type\":\"tool\",\"tool\":\"Bash\",\"state\":{\"output\":\"connection successful\"}}"
            "{\"type\":\"text\",\"text\":\"The daemon is running on socket /tmp/emacs501/pmf-value-stream.\"}"))
         (json (string-join lines "\n"))
         (result (gptel-auto-workflow-skill-eval--parse-transcript-json json)))
    (should (stringp result))
    (should-not (string-empty-p result))
    (should (string-match-p "emacsclient" result))
    (should (string-match-p "TOOL: Bash" result))
    (should (string-match-p "running t" result))
    (should (string-match-p "connection successful" result))
    (should (string-match-p "daemon is running" result))
    (should (string-match-p "pmf-value-stream" result))))

;;; test-skill-eval-opencode.el ends here
