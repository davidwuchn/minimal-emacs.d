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

(ert-deftest tdd/factor/insufficient-data-when-few-cells-after-min-per-cell ()
  "9+ results, 2x2 grid, but only 1 cell has >=3 experiments.
Should return :insufficient-data via the non-zero-cells check (need >=4)."
  (let ((results nil))
    ;; Cell A: strat-a × programming, 3 kept, 3 total
    (dotimes (i 3) (push (tdd-factor--make-result "strat-a" "lisp/modules/foo.el" 'kept) results))
    ;; Cell B: strat-a × testing, 1 kept, 1 total (under min-cell)
    (push (tdd-factor--make-result "strat-a" "test/test.el" 'kept) results)
    ;; Cell C: strat-b × programming, 1 kept, 1 total
    (push (tdd-factor--make-result "strat-b" "lisp/modules/bar.el" 'kept) results)
    ;; Cell D: strat-b × testing, 1 kept, 1 total
    (push (tdd-factor--make-result "strat-b" "test/test2.el" 'kept) results)
    ;; Plus filler to reach 9 results
    (push (tdd-factor--make-result "strat-c" "lisp/modules/baz.el" 'kept) results)
    (push (tdd-factor--make-result "strat-d" "test/test3.el" 'kept) results)
    (push (tdd-factor--make-result "strat-e" "lisp/modules/qux.el" 'kept) results)
    (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda (&optional _) results))
              ((symbol-function 'gptel-auto-workflow--categorize-experiment-target)
               (lambda (target)
                 (cond ((string-match-p "lisp/modules/" target) :programming)
                       ((string-match-p "test/" target) :testing)
                       (t :other)))))
      (let ((result (gptel-auto-workflow--factor-performance-matrix)))
        (should (eq :insufficient-data (plist-get result :unify-or-diversify)))
        (should (string-match-p "Only 1 cells" (plist-get result :reason)))))))

(ert-deftest tdd/factor/unify-when-strategies-perform-similarly ()
  "All strategies keep at same rate across all categories → :unify.
With rank-1 matrix M = [c, c; c, c] (constant), the top singular value
captures all energy → r → 1.0, recommendation :unify.
The matrix has min-per-cell=1 to bypass the 3-experiment default."
  (let ((results nil))
    ;; 4 cells, each with 3 results, all kept → all cells = 1.0
    (dotimes (_ 3)
      (push (tdd-factor--make-result "strat-a" "lisp/modules/foo.el" 'kept) results)
      (push (tdd-factor--make-result "strat-a" "test/test.el" 'kept) results)
      (push (tdd-factor--make-result "strat-b" "lisp/modules/bar.el" 'kept) results)
      (push (tdd-factor--make-result "strat-b" "test/test2.el" 'kept) results))
    (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda (&optional _) results))
              ((symbol-function 'gptel-auto-workflow--categorize-experiment-target)
               (lambda (target)
                 (cond ((string-match-p "lisp/modules/" target) :programming)
                       ((string-match-p "test/" target) :testing)
                       (t :other)))))
      (let ((result (gptel-auto-workflow--factor-performance-matrix 100 1)))
        (should (eq :unify (plist-get result :unify-or-diversify)))
        ;; Reconstruction quality should be near 1.0
        (let ((r (plist-get result :rank1-quality)))
          (should (and (numberp r) (> r 0.85))))))))

(provide 'test-factor-performance-matrix)
;;; test-factor-performance-matrix.el ends here
