;;; test-gptel-ext-tool-sanitize.el --- Tests for tool sanitization -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for gptel-ext-tool-sanitize.el:
;; - my/gptel--nil-tool-call-p
;; - my/gptel--sanitize-tool-calls
;; - my/gptel--tool-call-fingerprint
;; - my/gptel--detect-doom-loop
;; - my/gptel--dedup-tools-before-parse

;;; Code:

(require 'ert)
(require 'cl-lib)

;;; Mock variables

(defvar gptel-mode nil)
(defvar my/gptel-doom-loop-threshold 3)

;;; Functions under test

(defun test-nil-tool-call-p (tc)
  "Return non-nil when TC is a nil/null-named tool call."
  (let ((name (plist-get tc :name)))
    (or (null name) (eq name :null) (equal name "null"))))

(defun test-tool-call-fingerprint (tc)
  "Return fingerprint string for tool call TC."
  (let* ((name (or (plist-get tc :name) "nil"))
         (args (plist-get tc :args))
         (args-str (if args (format "%S" args) "nil")))
    (concat name ":" (md5 args-str))))

(defun test-dedup-tools (tools)
  "Deduplicate TOOLS by name, last-wins."
  (let ((seen (make-hash-table :test #'equal)))
    (nreverse
     (cl-loop for tool in (nreverse (copy-sequence tools))
              for name = (plist-get tool :name)
              when (and name (not (gethash name seen)))
              do (puthash name t seen)
              and collect tool))))

(defun test-detect-doom-loop-p (fingerprints threshold)
  "Check if FINGERPRINTS show doom-loop at THRESHOLD."
  (when (>= (length fingerprints) threshold)
    (let* ((fp (car (last fingerprints)))
           (tail (reverse fingerprints))
           (run (length (seq-take-while (lambda (f) (equal f fp)) tail))))
      (>= run threshold))))

;;; ========================================
;;; Tests for my/gptel--nil-tool-call-p
;;; ========================================

(ert-deftest sanitize/nil-tool/nil-name ()
  "Should detect nil name."
  (should (test-nil-tool-call-p '(:name nil))))

(ert-deftest sanitize/nil-tool/null-keyword ()
  "Should detect :null keyword."
  (should (test-nil-tool-call-p '(:name :null))))

(ert-deftest sanitize/nil-tool/null-string ()
  "Should detect 'null' string."
  (should (test-nil-tool-call-p '(:name "null"))))

(ert-deftest sanitize/nil-tool/valid-name ()
  "Should NOT detect valid name."
  (should-not (test-nil-tool-call-p '(:name "Read"))))

(ert-deftest sanitize/nil-tool/empty-string ()
  "Empty string should NOT be nil tool."
  (should-not (test-nil-tool-call-p '(:name ""))))

(ert-deftest sanitize/nil-tool/missing-name-key ()
  "Missing :name key should be nil."
  (should (test-nil-tool-call-p '())))

;;; ========================================
;;; Tests for my/gptel--tool-call-fingerprint
;;; ========================================

(ert-deftest sanitize/fingerprint/with-name-and-args ()
  "Should generate fingerprint with name and args."
  (let ((fp (test-tool-call-fingerprint '(:name "Read" :args (:path "test.el")))))
    (should (string-prefix-p "Read:" fp))
    (should (> (length fp) 10))))

(ert-deftest sanitize/fingerprint/nil-name ()
  "Should use 'nil' for nil name."
  (let ((fp (test-tool-call-fingerprint '(:name nil))))
    (should (string-prefix-p "nil:" fp))))

(ert-deftest sanitize/fingerprint/no-args ()
  "Should handle missing args."
  (let ((fp (test-tool-call-fingerprint '(:name "List"))))
    (should (string-prefix-p "List:" fp))))

(ert-deftest sanitize/fingerprint/same-args-same-fingerprint ()
  "Same args should produce same fingerprint."
  (let ((fp1 (test-tool-call-fingerprint '(:name "Read" :args (:path "test.el"))))
        (fp2 (test-tool-call-fingerprint '(:name "Read" :args (:path "test.el")))))
    (should (equal fp1 fp2))))

(ert-deftest sanitize/fingerprint/different-args-different-fingerprint ()
  "Different args should produce different fingerprint."
  (let ((fp1 (test-tool-call-fingerprint '(:name "Read" :args (:path "a.el"))))
        (fp2 (test-tool-call-fingerprint '(:name "Read" :args (:path "b.el")))))
    (should-not (equal fp1 fp2))))

(ert-deftest sanitize/fingerprint/different-name-different-fingerprint ()
  "Different name should produce different fingerprint."
  (let ((fp1 (test-tool-call-fingerprint '(:name "Read" :args (:path "test.el"))))
        (fp2 (test-tool-call-fingerprint '(:name "Write" :args (:path "test.el")))))
    (should-not (equal fp1 fp2))))

;;; ========================================
;;; Tests for my/gptel--dedup-tools-before-parse
;;; ========================================

(ert-deftest sanitize/dedup/removes-duplicates ()
  "Should remove duplicate tool names."
  (let ((tools (list '(:name "Read" :fn read)
                     '(:name "Edit" :fn edit1)
                     '(:name "Read" :fn read2))))
    (let ((deduped (test-dedup-tools tools)))
      (should (= (length deduped) 2)))))

(ert-deftest sanitize/dedup/last-wins ()
  "Last tool with same name should win."
  (let ((tools (list '(:name "Read" :fn read1)
                     '(:name "Read" :fn read2))))
    (let ((deduped (test-dedup-tools tools)))
      (should (eq (plist-get (car deduped) :fn) 'read2)))))

(ert-deftest sanitize/dedup/no-duplicates ()
  "Should return unchanged if no duplicates."
  (let ((tools (list '(:name "Read") '(:name "Edit"))))
    (let ((deduped (test-dedup-tools tools)))
      (should (= (length deduped) 2)))))

(ert-deftest sanitize/dedup/empty-list ()
  "Should handle empty list."
  (should (null (test-dedup-tools nil))))

(ert-deftest sanitize/dedup/preserves-order ()
  "Should preserve order for first occurrence of each name."
  (let ((tools (list '(:name "A") '(:name "B") '(:name "A"))))
    (let ((deduped (test-dedup-tools tools)))
      (should (equal (mapcar (lambda (tool) (plist-get tool :name)) deduped) '("B" "A"))))))

(ert-deftest sanitize/dedup/triple-duplicate ()
  "Should handle triple duplicates."
  (let ((tools (list '(:name "Read" :v 1)
                     '(:name "Read" :v 2)
                     '(:name "Read" :v 3))))
    (let ((deduped (test-dedup-tools tools)))
      (should (= (length deduped) 1))
      (should (= (plist-get (car deduped) :v) 3)))))

;;; ========================================
;;; Tests for doom-loop detection
;;; ========================================

(ert-deftest sanitize/doom-loop/threshold-default ()
  "Default threshold should be 3."
  (should (= my/gptel-doom-loop-threshold 3)))

(ert-deftest sanitize/doom-loop/not-triggered-under-threshold ()
  "Should not trigger under threshold."
  (let* ((fp (test-tool-call-fingerprint '(:name "Read" :args (:path "test.el"))))
         (fingerprints (list fp fp)))
    (should-not (test-detect-doom-loop-p fingerprints 3))))

(ert-deftest sanitize/doom-loop/triggered-at-threshold ()
  "Should trigger at threshold."
  (let* ((fp (test-tool-call-fingerprint '(:name "Read" :args (:path "test.el"))))
         (fingerprints (list fp fp fp)))
    (should (test-detect-doom-loop-p fingerprints 3))))

(ert-deftest sanitize/doom-loop/triggered-over-threshold ()
  "Should trigger over threshold."
  (let* ((fp (test-tool-call-fingerprint '(:name "Read" :args (:path "test.el"))))
         (fingerprints (list fp fp fp fp)))
    (should (test-detect-doom-loop-p fingerprints 3))))

(ert-deftest sanitize/doom-loop/not-triggered-different-tools ()
  "Should not trigger with different tools."
  (let ((fingerprints (list "Read:abc" "Write:abc" "Read:abc")))
    (should-not (test-detect-doom-loop-p fingerprints 3))))

(ert-deftest sanitize/doom-loop/not-triggered-different-args ()
  "Should not trigger with different args."
  (let ((fingerprints (list "Read:a" "Read:b" "Read:c")))
    (should-not (test-detect-doom-loop-p fingerprints 3))))

(ert-deftest sanitize/doom-loop/custom-threshold ()
  "Should respect custom threshold."
  (let* ((fp (test-tool-call-fingerprint '(:name "Read" :args (:path "test.el"))))
         (fingerprints (list fp fp fp fp fp)))
    (should (test-detect-doom-loop-p fingerprints 5))))

(ert-deftest sanitize/doom-loop/actual-handler-uses-current-run ()
  "Actual doom-loop handler should format messages with CURRENT-RUN."
  (require 'gptel-ext-tool-sanitize)
  (let* ((tc '(:name "Read" :args (:path "test.el")))
         (request-buffer (generate-new-buffer " *doom-loop-abort*"))
         (fp (my/gptel--tool-call-fingerprint tc))
         (info (list :tool-use (list tc)
                     :buffer request-buffer
                     :doom-loop-fingerprints (list fp)
                     :doom-loop-run-counts (list (cons fp 2))))
         (fsm (gptel-make-fsm :info info))
         logged-message
         callback-message
         aborted-buffer
         transition)
    (unwind-protect
        (progn
          (plist-put info :callback
                     (lambda (msg _info)
                        (setq callback-message msg)))
          (cl-letf (((symbol-function 'gptel--fsm-transition)
                     (lambda (_fsm state)
                        (setq transition state)))
                    ((symbol-function 'my/gptel-abort-here)
                     (lambda ()
                       (setq aborted-buffer (current-buffer))))
                    ((symbol-function 'message)
                     (lambda (fmt &rest args)
                        (setq logged-message (apply #'format fmt args)))))
             (my/gptel--detect-doom-loop fsm))
           (should (string-match-p "\"Read\" called 3 times" logged-message))
           (should (string-match-p "\"Read\" called 3 consecutive times" callback-message))
           (should (eq aborted-buffer request-buffer))
            (should (eq transition 'DONE)))
      (when (buffer-live-p request-buffer)
        (kill-buffer request-buffer)))))

(ert-deftest sanitize/doom-loop/actual-handler-counts-same-turn-repeats ()
  "Doom-loop detection should count repeated identical tool calls within one turn."
  (require 'gptel-ext-tool-sanitize)
  (let* ((tc '(:name "Read" :args (:path "test.el")))
         (request-buffer (generate-new-buffer " *doom-loop-same-turn*"))
         (info (list :tool-use (list tc tc tc)
                     :buffer request-buffer))
         (fsm (gptel-make-fsm :info info))
         logged-message
         callback-message
         aborted-buffer
         transition)
    (unwind-protect
        (progn
          (plist-put info :callback
                     (lambda (msg _info)
                       (setq callback-message msg)))
          (cl-letf (((symbol-function 'gptel--fsm-transition)
                     (lambda (_fsm state)
                       (setq transition state)))
                    ((symbol-function 'my/gptel-abort-here)
                     (lambda ()
                       (setq aborted-buffer (current-buffer))))
                    ((symbol-function 'message)
                     (lambda (fmt &rest args)
                       (setq logged-message (apply #'format fmt args)))))
            (my/gptel--detect-doom-loop fsm))
          (should (string-match-p "\"Read\" called 3 times" logged-message))
          (should (string-match-p "\"Read\" called 3 consecutive times" callback-message))
          (should (eq aborted-buffer request-buffer))
          (should (eq transition 'DONE)))
      (when (buffer-live-p request-buffer)
        (kill-buffer request-buffer)))))

(ert-deftest sanitize/inspection-thrash/actual-handler-triggers-on-same-file-streak ()
  "Inspection thrash should abort once same-file read-only exploration crosses threshold."
  (require 'gptel-ext-tool-sanitize)
  (let* ((tc '(:name "Code_Inspect"
               :args (:file_path "/tmp/test.el" :node_name "third-node")))
         (request-buffer (generate-new-buffer " *inspection-thrash-abort*"))
         (info (list :tool-use (list tc)
                     :buffer request-buffer
                     :inspection-thrash-state (list :file "/tmp/test.el" :count 2)))
         (fsm (gptel-make-fsm :info info))
         logged-message
         callback-message
         aborted-buffer
         transition)
    (unwind-protect
        (progn
          (plist-put info :callback
                     (lambda (msg _info)
                       (setq callback-message msg)))
          (let ((my/gptel-inspection-thrash-threshold 3))
            (cl-letf (((symbol-function 'gptel--fsm-transition)
                       (lambda (_fsm state)
                         (setq transition state)))
                      ((symbol-function 'my/gptel-abort-here)
                       (lambda ()
                         (setq aborted-buffer (current-buffer))))
                      ((symbol-function 'message)
                       (lambda (fmt &rest args)
                         (setq logged-message (apply #'format fmt args)))))
              (my/gptel--detect-inspection-thrash fsm)))
          (should (string-match-p "inspection-thrash detected" logged-message))
          (should (string-match-p "/tmp/test\\.el" logged-message))
          (should (string-match-p "3 consecutive read-only inspections" callback-message))
          (should (eq aborted-buffer request-buffer))
          (should (eq transition 'DONE)))
      (when (buffer-live-p request-buffer)
        (kill-buffer request-buffer)))))

(ert-deftest sanitize/inspection-thrash/does-not-trigger-when-file-changes ()
  "Inspection thrash should reset when the model moves to a different file."
  (require 'gptel-ext-tool-sanitize)
  (let* ((tc '(:name "Code_Inspect"
               :args (:file_path "/tmp/other.el" :node_name "fresh-node")))
         (info (list :tool-use (list tc)
                     :inspection-thrash-state (list :file "/tmp/test.el" :count 2)))
         (fsm (gptel-make-fsm :info info))
         transition)
    (let ((my/gptel-inspection-thrash-threshold 3))
      (cl-letf (((symbol-function 'gptel--fsm-transition)
                 (lambda (_fsm state)
                   (setq transition state))))
        (my/gptel--detect-inspection-thrash fsm)))
    (should-not transition)
    (let ((state (plist-get (gptel-fsm-info fsm) :inspection-thrash-state)))
      (should (equal (plist-get state :file) "/tmp/other.el"))
      (should (= (plist-get state :count) 1)))))

(ert-deftest sanitize/inspection-thrash/resets-after-write-tool ()
  "Write-capable tools should reset the same-file inspection streak."
  (require 'gptel-ext-tool-sanitize)
  (let* ((tool-use (list '(:name "ApplyPatch" :args (:patch "*** Begin Patch"))
                         '(:name "Code_Inspect"
                           :args (:file_path "/tmp/test.el" :node_name "fresh-node"))))
         (info (list :tool-use tool-use
                     :inspection-thrash-state (list :file "/tmp/test.el" :count 2)))
         (fsm (gptel-make-fsm :info info))
         transition)
    (let ((my/gptel-inspection-thrash-threshold 3))
      (cl-letf (((symbol-function 'gptel--fsm-transition)
                 (lambda (_fsm state)
                   (setq transition state))))
        (my/gptel--detect-inspection-thrash fsm)))
    (should-not transition)
    (let ((state (plist-get (gptel-fsm-info fsm) :inspection-thrash-state)))
      (should (equal (plist-get state :file) "/tmp/test.el"))
      (should (= (plist-get state :count) 1)))))

(ert-deftest sanitize/inspection-thrash/large-file-gets-extra-headroom ()
  "Large files should receive extra same-file inspection headroom."
  (require 'gptel-ext-tool-sanitize)
  (let ((file (make-temp-file "gptel-inspection-thrash-large" nil ".el")))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert (make-string 4096 ?x)))
          (let ((my/gptel-inspection-thrash-threshold 25)
                (my/gptel-inspection-thrash-bytes-per-extra-step 1024)
                (my/gptel-inspection-thrash-max-extra 10))
             (should (= (my/gptel--inspection-thrash-threshold-for-file file) 29))))
       (when (file-exists-p file)
         (delete-file file)))))

(ert-deftest sanitize/inspection-thrash/default-medium-large-file-gets-more-headroom ()
  "Default sizing should grant extra headroom to medium-large files."
  (require 'gptel-ext-tool-sanitize)
  (let ((file (make-temp-file "gptel-inspection-thrash-default" nil ".el")))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert (make-string 32768 ?x)))
          (should (= my/gptel-inspection-thrash-threshold 40))
          (should (= my/gptel-inspection-thrash-bytes-per-extra-step 8192))
          (should (= my/gptel-inspection-thrash-max-extra 40))
          (should (= (my/gptel--inspection-thrash-threshold-for-file file) 44)))
      (when (file-exists-p file)
        (delete-file file)))))

(ert-deftest sanitize/inspection-thrash/large-file-waits-for-expanded-threshold ()
  "Large files should not abort at the base threshold alone."
  (require 'gptel-ext-tool-sanitize)
  (let* ((file (make-temp-file "gptel-inspection-thrash-large" nil ".el"))
         (tc nil)
         (info nil)
         (fsm nil)
         transition)
    (unwind-protect
        (progn
          (with-temp-file file
            (insert (make-string 4096 ?x)))
          (setq tc `(:name "Code_Inspect"
                           :args (:file_path ,file :node_name "next-node")))
          (setq info (list :tool-use (list tc)
                           :callback (lambda (&rest _args))
                           :inspection-thrash-state (list :file file :count 24)))
          (setq fsm (gptel-make-fsm :info info))
          (let ((my/gptel-inspection-thrash-threshold 25)
                (my/gptel-inspection-thrash-bytes-per-extra-step 1024)
                (my/gptel-inspection-thrash-max-extra 10))
            (cl-letf (((symbol-function 'gptel--fsm-transition)
                       (lambda (_fsm state)
                         (setq transition state))))
              (my/gptel--detect-inspection-thrash fsm)))
          (should-not transition)
          (let ((state (plist-get (gptel-fsm-info fsm) :inspection-thrash-state)))
            (should (equal (plist-get state :file) file))
            (should (= (plist-get state :count) 25))))
      (when (file-exists-p file)
        (delete-file file)))))

(ert-deftest sanitize/inspection-thrash/large-file-triggers-at-expanded-threshold ()
  "Large files should still abort once the expanded threshold is reached."
  (require 'gptel-ext-tool-sanitize)
  (let* ((file (make-temp-file "gptel-inspection-thrash-large" nil ".el"))
         (request-buffer (generate-new-buffer " *inspection-thrash-large*"))
         logged-message
         callback-message
         transition)
    (unwind-protect
        (progn
          (with-temp-file file
            (insert (make-string 4096 ?x)))
          (let* ((tc `(:name "Code_Inspect"
                             :args (:file_path ,file :node_name "next-node")))
                 (info (list :tool-use (list tc)
                             :buffer request-buffer
                             :inspection-thrash-state (list :file file :count 28)))
                 (fsm (gptel-make-fsm :info info)))
            (plist-put info :callback
                       (lambda (msg _info)
                         (setq callback-message msg)))
            (let ((my/gptel-inspection-thrash-threshold 25)
                  (my/gptel-inspection-thrash-bytes-per-extra-step 1024)
                  (my/gptel-inspection-thrash-max-extra 10))
              (cl-letf (((symbol-function 'gptel--fsm-transition)
                         (lambda (_fsm state)
                           (setq transition state)))
                        ((symbol-function 'my/gptel-abort-here)
                         (lambda ()))
                        ((symbol-function 'message)
                         (lambda (fmt &rest args)
                           (setq logged-message (apply #'format fmt args)))))
                (my/gptel--detect-inspection-thrash fsm)))
            (should (eq transition 'DONE))
            (should (string-match-p "29 read-only inspections" logged-message))
            (should (string-match-p "29 consecutive read-only inspections" callback-message))))
      (when (buffer-live-p request-buffer)
        (kill-buffer request-buffer))
      (when (file-exists-p file)
        (delete-file file)))))

;;; ========================================
;;; Tests for sanitize-tool-calls scenarios
;;; ========================================

(ert-deftest sanitize/tool-cases/normal-tool ()
  "Normal tool should pass through."
  (let ((tc '(:name "Read" :args (:path "test.el"))))
    (should-not (test-nil-tool-call-p tc))))

(ert-deftest sanitize/tool-cases/unknown-tool ()
  "Unknown tool should be sanitized."
  (let ((tc '(:name "NonexistentTool")))
    (should-not (test-nil-tool-call-p tc))))

(ert-deftest sanitize/tool-cases/case-mismatch ()
  "Case mismatch should be repairable."
  (let ((tc '(:name "read")))
    (should (stringp (plist-get tc :name)))))

;;; ========================================
;;; Tests for edge cases
;;; ========================================

(ert-deftest sanitize/edge/empty-tool-use ()
  "Empty tool-use list should be handled."
  (should (null '())))

(ert-deftest sanitize/edge/multiple-malformed ()
  "Multiple malformed tools should all be detected."
  (let ((tcs (list '(:name nil) '(:name :null) '(:name "null"))))
    (should (cl-every #'test-nil-tool-call-p tcs))))

(ert-deftest sanitize/edge/fingerprint-consistency ()
  "Fingerprint should be deterministic."
  (let ((tc '(:name "Read" :args (:path "test.el" :limit 100))))
    (should (equal (test-tool-call-fingerprint tc)
                   (test-tool-call-fingerprint tc)))))

;;; ========================================
;;; Tests for fuzzy tool name matching
;;; ========================================

(defun test-normalize-tool-name (name)
  "Normalize tool NAME for fuzzy matching (standalone for testing)."
  (when (stringp name)
    (downcase (replace-regexp-in-string "[-_]" "" name))))

(ert-deftest sanitize/fuzzy/normalize-name ()
  "Test name normalization for fuzzy matching."
  (should (equal (test-normalize-tool-name "Code_Map") "codemap"))
  (should (equal (test-normalize-tool-name "code-map") "codemap"))
  (should (equal (test-normalize-tool-name "CODE-MAP") "codemap"))
  (should (equal (test-normalize-tool-name "CodeMap") "codemap")))

(ert-deftest sanitize/fuzzy/case-insensitive ()
  "Case differences should match."
  (should (equal (test-normalize-tool-name "read") 
                 (test-normalize-tool-name "Read")))
  (should (equal (test-normalize-tool-name "BASH") 
                 (test-normalize-tool-name "bash"))))

(ert-deftest sanitize/fuzzy/underscore-hyphen ()
  "Underscores and hyphens should be treated equally."
  (should (equal (test-normalize-tool-name "Code_Map") 
                 (test-normalize-tool-name "Code-Map")))
  (should (equal (test-normalize-tool-name "find_buffers_and_recent") 
                 (test-normalize-tool-name "find-buffers-and-recent"))))

(ert-deftest sanitize/fuzzy/mixed-case-and-separators ()
  "Mixed case and separators should still match."
  (should (equal (test-normalize-tool-name "CODE_MAP") 
                 (test-normalize-tool-name "code-map")))
  (should (equal (test-normalize-tool-name "Find_Buffers_And_Recent") 
                 (test-normalize-tool-name "find-buffers-and-recent"))))

(ert-deftest sanitize/fuzzy/nil-name ()
  "Nil name should return nil."
  (should-not (test-normalize-tool-name nil)))

(ert-deftest sanitize/fuzzy/empty-name ()
  "Empty name should return empty."
  (should (equal (test-normalize-tool-name "") "")))

(ert-deftest sanitize/fuzzy/embedded-tool-name-recovery ()
  "Embedded tool names inside parser noise should still be recoverable."
  (require 'gptel-ext-tool-sanitize)
  (let* ((todo-tool
          (gptel--make-tool :name "TodoWrite"
                            :function #'ignore
                            :description "todo"
                            :args nil))
         (skill-tool
          (gptel--make-tool :name "create_skill"
                            :function #'ignore
                            :description "skill"
                            :args nil))
         (match
          (my/gptel--find-tool-fuzzy
           "FOCUS\">gptel-agent-loop--handle-aborted-state</parameter>\n<parameter name=\"TodoWrite"
           (list (cons "create_skill" skill-tool)
                 (cons "TodoWrite" todo-tool)))))
    (should (gptel-tool-p match))
    (should (eq match todo-tool))))

(ert-deftest sanitize/tool-calls/repairs-embedded-tool-name-from-global-registry ()
  "Malformed tool names should recover from the global registry without cons-cell crashes."
  (require 'gptel-ext-tool-sanitize)
  (let* ((request-buffer (generate-new-buffer " *sanitize-recover*"))
         (todo-tool
          (gptel--make-tool :name "TodoWrite"
                            :function #'ignore
                            :description "todo"
                            :args nil))
         (edit-tool
          (gptel--make-tool :name "Edit"
                            :function #'ignore
                            :description "edit"
                            :args nil))
         (skill-tool
          (gptel--make-tool :name "create_skill"
                            :function #'ignore
                            :description "skill"
                            :args nil))
         (tool-call
          (list :name "FOCUS\">gptel-agent-loop--handle-aborted-state</parameter>\n<parameter name=\"TodoWrite"
                :args nil))
         (info (list :tool-use (list tool-call)
                     :tools (list edit-tool)
                     :buffer request-buffer))
         (fsm (gptel-make-fsm :info info))
         (gptel--known-tools
          `(("gptel-agent"
             . (("create_skill" . ,skill-tool)
                ("TodoWrite" . ,todo-tool)
                ("Edit" . ,edit-tool))))))
    (unwind-protect
        (progn
          (my/gptel--sanitize-tool-calls fsm)
          (let* ((updated-info (gptel-fsm-info fsm))
                 (updated-tool-use (plist-get updated-info :tool-use))
                 (updated-tools (plist-get updated-info :tools)))
            (should (equal "TodoWrite" (plist-get (car updated-tool-use) :name)))
            (should (memq todo-tool updated-tools))
            (should (cl-every #'gptel-tool-p updated-tools))))
      (when (buffer-live-p request-buffer)
        (kill-buffer request-buffer)))))

(ert-deftest sanitize/tool-dispatch/async-contract-error-becomes-tool-result ()
  "Escaped async dispatch errors should complete the current tool call."
  (require 'gptel-ext-tool-sanitize)
  (let* ((request-buffer (generate-new-buffer " *dispatch-error*"))
         (edit-tool
          (gptel--make-tool :name "Edit"
                            :function #'ignore
                            :description "edit"
                            :args nil
                            :async t))
         (tool-call (list :name "Edit" :args '(:file_path "x.el")))
         (info (list :tool-use (list tool-call)
                     :tools (list edit-tool)
                     :buffer request-buffer))
         (fsm (gptel-make-fsm :info info)))
    (unwind-protect
        (progn
          (cl-letf (((symbol-function 'gptel--fsm-transition)
                     (lambda (&rest _) nil)))
            (my/gptel--handle-tool-use-with-error-result
             (lambda (_fsm)
               (user-error "Tool Contract Violation (Edit): missing or null required argument `new_str`"))
             fsm))
          (should (string-prefix-p "Error: Tool Contract Violation"
                                   (plist-get tool-call :result)))
          (should (string-match-p "new_str" (plist-get tool-call :result))))
      (when (buffer-live-p request-buffer)
        (kill-buffer request-buffer)))))

(provide 'test-gptel-ext-tool-sanitize)
;;; test-gptel-ext-tool-sanitize.el ends here
