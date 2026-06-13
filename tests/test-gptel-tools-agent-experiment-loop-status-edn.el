;;; test-gptel-tools-agent-experiment-loop-status-edn.el --- EDN status tests -*- lexical-binding: t -*-

(require 'ert)
(require 'cl-lib)
(require 'gptel-tools-agent-base)
(require 'gptel-tools-agent-experiment-loop)

(ert-deftest test-loop-status-edn/persist-and-read-roundtrip ()
  "Persisted status must round-trip through EDN."
  (let* ((root (make-temp-file "ov5-status-" t))
         (status-file (expand-file-name "status.edn" root)))
    (unwind-protect
        (cl-letf (((symbol-function 'gptel-auto-workflow--status-file)
                   (lambda () status-file))
                  ((symbol-function 'gptel-auto-workflow--persist-messages-tail)
                   (lambda () nil))
                  (gptel-auto-workflow--running t)
                  (gptel-auto-workflow--run-id "edn-test-run")
                  (gptel-auto-workflow--stats '(:phase "running" :kept 2 :total 5)))
          (gptel-auto-workflow--persist-status)
          (should (file-exists-p status-file))
          (let ((parsed (gptel-auto-workflow-read-persisted-status)))
            (should (plist-get parsed :running))
            (should (= 2 (plist-get parsed :kept)))
            (should (= 5 (plist-get parsed :total)))
            (should (string= "running" (plist-get parsed :phase)))
            (should (string= "edn-test-run" (plist-get parsed :run-id)))))
      (delete-directory root t))))

(ert-deftest test-loop-status-edn/read-edn-returns-nil-for-missing-file ()
  "EDN reader must return nil for missing files."
  (should-not (gptel-auto-workflow--read-edn "/nonexistent/path/status.edn")))

(ert-deftest test-loop-status-edn/write-and-read-edn ()
  "Generic EDN write/read helper must round-trip."
  (let* ((root (make-temp-file "ov5-edn-" t))
         (file (expand-file-name "data.edn" root))
         (data '(:running true :kept 3 :phase "complete")))
    (unwind-protect
        (progn
          (gptel-auto-workflow--write-edn file data)
          (let ((parsed (gptel-auto-workflow--read-edn file)))
            (should (plist-get parsed :running))
            (should (= 3 (plist-get parsed :kept)))
            (should (string= "complete" (plist-get parsed :phase)))))
      (delete-file file))))

(provide 'test-gptel-tools-agent-experiment-loop-status-edn)
;;; test-gptel-tools-agent-experiment-loop-status-edn.el ends here
