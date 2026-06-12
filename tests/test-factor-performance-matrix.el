;;; test-factor-performance-matrix.el --- TDD tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(add-to-list 'load-path (expand-file-name "lisp/modules" default-directory))
(require 'gptel-auto-workflow-evolution)

(defun tdd-factor--make-result (strategy target decision)
  (list :strategy strategy :target target
        :decision (if (eq decision 'kept) "kept" "discarded")
        :score-before 0.4 :score-after 0.5
        :code-quality 0.5 :duration 60
        :timestamp "2026-01-01T00:00:00"))

(ert-deftest tdd/factor/insufficient-data-when-no-results ()
  "Empty result list returns :insufficient-data."
  (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
             (lambda (&optional _) nil))
            ((symbol-function 'gptel-auto-workflow--categorize-experiment-target)
             (lambda (_) :other)))
    (let ((result (gptel-auto-workflow--factor-performance-matrix)))
      (should (eq :insufficient-data (plist-get result :unify-or-diversify)))
      (should (string-match-p "Need >= 9" (plist-get result :reason))))))

(ert-deftest tdd/factor/insufficient-data-when-too-few-results ()
  "Fewer than 9 results returns :insufficient-data."
  (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
             (lambda (&optional _)
               (list
                (tdd-factor--make-result "strat-a" "lisp/modules/foo.el" 'kept)
                (tdd-factor--make-result "strat-b" "lisp/modules/bar.el" 'discarded)
                (tdd-factor--make-result "strat-a" "test/test.el" 'kept))))
            ((symbol-function 'gptel-auto-workflow--categorize-experiment-target)
             (lambda (target)
               (cond ((string-match-p "lisp/modules/" target) :programming)
                     ((string-match-p "test/" target) :testing)
                     (t :other)))))
    (let ((result (gptel-auto-workflow--factor-performance-matrix)))
      (should (eq :insufficient-data (plist-get result :unify-or-diversify)))
      (should (string-match-p "have 3" (plist-get result :reason))))))

(ert-deftest tdd/factor/insufficient-data-when-few-categories ()
  "9+ results but only 1 category → :insufficient-data."
  (let ((results nil))
    (dotimes (i 12)
      (setq results
            (append results
                    (list
                     (tdd-factor--make-result
                      (if (zerop (mod i 2)) "strat-a" "strat-b")
                      "lisp/modules/foo.el" 'kept)))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda (&optional _) results))
              ((symbol-function 'gptel-auto-workflow--categorize-experiment-target)
               (lambda (_) :programming)))
      (let ((result (gptel-auto-workflow--factor-performance-matrix)))
        (should (eq :insufficient-data (plist-get result :unify-or-diversify)))
        (should (string-match-p "1×2" (plist-get result :reason)))))))

(ert-deftest tdd/factor/result-has-computed-at-key ()
  "Result plist always includes :computed-at timestamp."
  (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
             (lambda (&optional _) nil))
            ((symbol-function 'gptel-auto-workflow--categorize-experiment-target)
             (lambda (_) :other)))
    (let ((result (gptel-auto-workflow--factor-performance-matrix)))
      (should (numberp (plist-get result :computed-at))))))

(provide 'test-factor-performance-matrix)
;;; test-factor-performance-matrix.el ends here
