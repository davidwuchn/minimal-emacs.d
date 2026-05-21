;;; test-gptel-auto-workflow-ontology-router.el --- Smart backend routing tests -*- lexical-binding: t; -*-

;;; Commentary:

;; TDD tests for ontology-based backend routing.
;; Verifies task classification, performance tracking, and routing logic.

;;; Code:

(require 'ert)

(load-file (expand-file-name "../lisp/modules/gptel-auto-workflow-ontology-router.el"
                              (file-name-directory
                               (or load-file-name buffer-file-name default-directory))))

;; ─── Task Classification Tests ───

(ert-deftest regression/ontology-router/classify-simple-task ()
  "Small files should be classified as simple."
  (let ((tmpfile (make-temp-file "simple" nil ".el" "(defun foo () 1)\n")))
    (unwind-protect
        (should (eq :simple (gptel-auto-workflow--classify-task-complexity
                             tmpfile "template-default")))
      (delete-file tmpfile))))

(ert-deftest regression/ontology-router/classify-complex-task ()
  "Large files should be classified as complex."
  (let ((tmpfile (make-temp-file "complex" nil ".el")))
    (unwind-protect
        (progn
          (with-temp-file tmpfile
            (dotimes (_ 600)
              (insert "(defun foo () 1)\n")))
          (should (eq :complex (gptel-auto-workflow--classify-task-complexity
                                tmpfile "template-default"))))
      (delete-file tmpfile))))

(ert-deftest regression/ontology-router/classify-by-strategy ()
  "Strategy name can indicate complexity."
  (let ((tmpfile (make-temp-file "foo" nil ".el")))
    (unwind-protect
        (should (eq :complex (gptel-auto-workflow--classify-task-complexity
                              tmpfile "architecture-redesign")))
      (delete-file tmpfile))))

;; ─── Axis Classification Tests ───

(ert-deftest regression/ontology-router/axis-error-handling ()
  "Error-related files should map to :K axis."
  (should (eq :K (gptel-auto-workflow--classify-task-axis "lisp/gptel-error-handler.el"))))

(ert-deftest regression/ontology-router/axis-init ()
  "Init files should map to :I axis."
  (should (eq :I (gptel-auto-workflow--classify-task-axis "lisp/gptel-init.el"))))

(ert-deftest regression/ontology-router/axis-default ()
  "Unknown files should default to :K."
  (should (eq :K (gptel-auto-workflow--classify-task-axis "lisp/foobar.el"))))

;; ─── Backend Performance Tests ───

(ert-deftest regression/ontology-router/backend-performance-kept ()
  "Backend with kept experiments should have positive keep-rate."
  (let ((mock-results
         (list
          (list :backend "moonshot" :strategy "strat" :target "lisp/foo.el"
                :decision "kept"))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda () mock-results)))
      (let ((perf (gptel-auto-workflow--get-backend-performance "moonshot")))
        (should (= 1 (plist-get perf :kept)))
        (should (= 1 (plist-get perf :total)))
        (should (= 1.0 (plist-get perf :keep-rate)))))))

(ert-deftest regression/ontology-router/backend-performance-filtered ()
  "Filtering by strategy should only count matching experiments."
  (let ((mock-results
         (list
          (list :backend "moonshot" :strategy "strat-a" :target "lisp/foo.el"
                :decision "kept")
          (list :backend "moonshot" :strategy "strat-b" :target "lisp/foo.el"
                :decision "discarded"))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda () mock-results)))
      (let ((perf (gptel-auto-workflow--get-backend-performance "moonshot" "strat-a")))
        (should (= 1 (plist-get perf :total)))))))

(ert-deftest regression/ontology-router/all-performances-sorted ()
  "Performances should be sorted by keep-rate descending."
  (let ((mock-results
         (list
          (list :backend "moonshot" :decision "kept")
          (list :backend "moonshot" :decision "kept")
          (list :backend "minimax" :decision "discarded"))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda () mock-results)))
      (let ((perfs (gptel-auto-workflow--get-all-backend-performances)))
        (should (> (plist-get (cdar perfs) :keep-rate)
                     (plist-get (cdadr perfs) :keep-rate)))))))

;; ─── Smart Router Tests ───

(ert-deftest regression/ontology-router/route-with-data ()
  "Router should select best backend when sufficient data exists."
  (let ((mock-results
         (list
          (list :backend "moonshot" :strategy "strat" :target "lisp/foo.el"
                :decision "kept")
          (list :backend "moonshot" :strategy "strat" :target "lisp/foo.el"
                :decision "kept")
          (list :backend "moonshot" :strategy "strat" :target "lisp/foo.el"
                :decision "kept")
          (list :backend "minimax" :strategy "strat" :target "lisp/foo.el"
                :decision "discarded"))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda () mock-results))
              ;; Force no exploration
              ((symbol-function 'random) (lambda (_) 999)))
      (let ((backend (gptel-auto-workflow--smart-route-backend
                      "lisp/foo.el" "strat")))
        (should (string= "moonshot" backend))))))

(ert-deftest regression/ontology-router/route-default-without-data ()
  "Router should use default when no data exists."
  (let ((mock-results nil))
    (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda () mock-results)))
      (let ((backend (gptel-auto-workflow--smart-route-backend
                      "lisp/foo.el" "template-default")))
        (should (stringp backend))))))

(provide 'test-gptel-auto-workflow-ontology-router)
;;; test-gptel-auto-workflow-ontology-router.el ends here
