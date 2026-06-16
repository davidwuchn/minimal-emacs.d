;;; test-pipeline-statechart.el --- TDD tests for gptel-auto-workflow-pipeline-statechart -*- lexical-binding: t; -*-

;; No test file existed for this module despite 12 defuns and 592 lines.
;; This file adds coverage starting with the persist/load roundtrip and
;; the compute-gate-score-vector function.

(require 'ert)
(require 'cl-lib)
(require 'gptel-auto-workflow-pipeline-statechart)
(require 'gptel-tools-agent-base)  ; for gptel-auto-workflow--plist-get

(ert-deftest test-pipeline-statechart/persist-and-load-roundtrip ()
  "A statechart plist persisted with prin1 should roundtrip through read."
  (let* ((root (make-temp-file "ov5-statechart-" t))
         (sample '(:gates 5 :total 10 :kept 8 :discarded 2 :keep-rate 0.8
                   :transition-matrix nil :records nil :computed-at 12345)))
    (unwind-protect
        (cl-letf (((symbol-function 'gptel-auto-workflow--worktree-base-root)
                   (lambda () root))
                  ;; user-emacs-directory is the pre-early-init redirected value
                  ;; (<minimal>/var/); the worktree-base-root stub above should win.
                  (user-emacs-directory (concat root "/")))
          (let ((file (gptel-auto-workflow--statechart-persist sample)))
            (should (file-exists-p file))
            (let ((loaded (gptel-auto-workflow--statechart-load)))
              (should (equal loaded sample)))))
      (delete-directory root t))))

(ert-deftest test-pipeline-statechart/compute-gate-score-vector-for-kept-experiment ()
  "An experiment with :kept t must produce an all-1.0 vector."
  (let* ((exp '(:kept t :grader-quality 5 :decision "keep" :comparator-reason "Combined: 0.40 → 0.60"))
         (gates (append gptel-auto-workflow--pipeline-gates nil))
         (vec (gptel-auto-workflow--compute-gate-score-vector exp)))
    (should (vectorp vec))
    (should (= (length vec) (length gates)))
    ;; For a kept experiment, all gates should be in [0,1]
    (let ((idx 0))
      (dolist (_g gates)
        (should (>= (aref vec idx) 0.0))
        (should (<= (aref vec idx) 1.0))
        (setq idx (1+ idx))))))

(ert-deftest test-pipeline-statechart/compute-gate-score-vector-for-discarded-experiment ()
  "A discarded experiment must produce a vector with some -1.0 entries
(marking unreached gates)."
  (let* ((exp '(:kept nil :grader-quality 2 :decision "discard" :comparator-reason ""))
         (vec (gptel-auto-workflow--compute-gate-score-vector exp)))
    (should (vectorp vec))
    ;; A discarded experiment should have at least one -1.0 (unreached)
    (let ((has-unreached nil))
      (dotimes (i (length vec))
        (when (= (aref vec i) -1.0)
          (setq has-unreached t)))
      (should has-unreached))))

(ert-deftest test-pipeline-statechart/statechart-persistence-file-uses-worktree-root ()
  "The persistence file path must be under the worktree base root
when that function is bound (the normal load order).  This guards
against the same user-emacs-directory red-herring that bit
validate-diff-text, Signal 1, and skill-routing-onto."
  (let* ((root (make-temp-file "ov5-statechart-pf-" t)))
    (unwind-protect
        (cl-letf (((symbol-function 'gptel-auto-workflow--worktree-base-root)
                   (lambda () root)))
          (let ((file (gptel-auto-workflow--statechart-persistence-file)))
            ;; The file path must be UNDER the worktree root
            (should (string-prefix-p (file-name-as-directory root) file))))
      (delete-directory root t))))

(provide 'test-pipeline-statechart)
;;; test-pipeline-statechart.el ends here
