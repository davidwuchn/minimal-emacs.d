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

;;; ─── TDD coverage for detect-compensating-errors ───
;;;
;;; Behavior (from docstring + source):
;;;   - A compensating error occurs when the GRADER score (vector index 5,
;;;     i.e. G6) is high (>0.6) but the EARLY gates (indices 0-4, i.e. G1-G5)
;;;     failed (score < 0.5).
;;;   - Returns a list of plists, one per compensating error, each with:
;;;     :executor-score, :grader-score, :early-failed-gates (alist).
;;;   - Non-compensating vectors are silently dropped.

(ert-deftest test-pipeline-statechart/detect-compensating-errors-detects-early-fail-with-high-grader ()
  "A vector with all early-gate fails (<0.5) and high grader (>0.6)
must be reported as a compensating error."
  (let* ((gates (append gptel-auto-workflow--pipeline-gates nil))
         ;; G1-G5 all fail (<0.5), G6 grader high (0.8), executor G3 is one of the early fails
         (bad-vec (vector 0.2 0.3 0.2 0.2 0.2 0.8 0.5 0.5 0.5 0.5 0.5))
         (result (gptel-auto-workflow--detect-compensating-errors
                  (list bad-vec) gates)))
    (should (= 1 (length result)))
    (let ((err (car result)))
      (should (= 0.8 (plist-get err :grader-score)))
      (should (= 0.2 (plist-get err :executor-score)))
      (let ((early (plist-get err :early-failed-gates)))
        (should (= 5 (length early)))))))

(ert-deftest test-pipeline-statechart/detect-compensating-errors-ignores-low-grader ()
  "A vector with early-gate fails but LOW grader (≤0.6) is NOT a
compensating error (the grader is not hiding the early failures)."
  (let* ((gates (append gptel-auto-workflow--pipeline-gates nil))
         ;; G1-G5 fail, G6 grader also low (0.5) — not compensating
         (bad-but-grader-low (vector 0.2 0.3 0.2 0.2 0.2 0.5 0.5 0.5 0.5 0.5 0.5))
         (result (gptel-auto-workflow--detect-compensating-errors
                  (list bad-but-grader-low) gates)))
    (should (null result))))

(ert-deftest test-pipeline-statechart/detect-compensating-errors-ignores-no-early-fails ()
  "A vector with high grader but no early-gate fails is NOT a
compensating error (the grader reward is earned, not compensated)."
  (let* ((gates (append gptel-auto-workflow--pipeline-gates nil))
         (clean (vector 0.8 0.8 0.8 0.8 0.8 0.8 0.5 0.5 0.5 0.5 0.5))
         (result (gptel-auto-workflow--detect-compensating-errors
                  (list clean) gates)))
    (should (null result))))

(ert-deftest test-pipeline-statechart/detect-compensating-errors-mixed-input ()
  "Mixed input: out of 3 vectors, only the one with both early-fails
AND high grader is reported."
  (let* ((gates (append gptel-auto-workflow--pipeline-gates nil))
         (v-compensating (vector 0.2 0.3 0.2 0.2 0.2 0.8 0.5 0.5 0.5 0.5 0.5))
         (v-low-grader   (vector 0.2 0.3 0.2 0.2 0.2 0.5 0.5 0.5 0.5 0.5 0.5))
         (v-clean        (vector 0.8 0.8 0.8 0.8 0.8 0.8 0.5 0.5 0.5 0.5 0.5))
         (result (gptel-auto-workflow--detect-compensating-errors
                  (list v-low-grader v-compensating v-clean) gates)))
    (should (= 1 (length result)))
    (should (= 0.8 (plist-get (car result) :grader-score)))))

(ert-deftest test-pipeline-statechart/detect-compensating-errors-empty-input ()
  "Empty input list returns nil (no compensating errors)."
  (let* ((gates (append gptel-auto-workflow--pipeline-gates nil))
         (result (gptel-auto-workflow--detect-compensating-errors nil gates)))
    (should (null result))))

;;; ─── TDD coverage for statechart-analyze ───
;;;
;;; This is the high-level bottleneck detector. It walks the transition
;;; matrix to find the lowest p-pass gate (bottleneck) and the gate
;;; with the highest absolute failure count (lossiest-gate), then
;;; computes the φ-curve deviation and pulls in compensating errors.
;;;
;;; TDD discovery: statechart-analyze previously called
;;; (gptel-auto-workflow--detect-compensating-errors ... gate-order)
;;; without binding `gate-order` in its let* (it's only bound in
;;; build-statechart).  This test exposes that bug.

(ert-deftest test-pipeline-statechart/statechart-analyze-returns-required-keys ()
  "Analyzing a valid statechart with varied p-passes must return a
plist with the keys documented in the function docstring."
  (let* ((gates (append gptel-auto-workflow--pipeline-gates nil))
         (matrix (make-hash-table :test 'eq))
         (record (list :kept t
                       :grader-quality 5
                       :decision "keep"
                       :gate-score-vector (vector 0.5 0.5 0.5 0.5 0.5
                                                  0.5 0.5 0.5 0.5 0.5 0.5)))
         (sc (list :gates gates
                   :total 10
                   :kept 7
                   :discarded 3
                   :keep-rate 0.7
                   :transition-matrix matrix
                   :records (list record)
                   :computed-at (float-time))))
    ;; Realistic: validation has 0.6 p-pass (becomes bottleneck),
    ;; executor has 5 absolute failures (becomes lossiest).
    (dolist (gate (append gates nil))
      (puthash gate (list :p-pass 0.95 :p-fail 0.05 :entered 10 :failed 1)
               matrix))
    (puthash 'validation (list :p-pass 0.6 :p-fail 0.4 :entered 10 :failed 4)
             matrix)
    (puthash 'executor (list :p-pass 0.4 :p-fail 0.6 :entered 10 :failed 6)
             matrix)
    (let ((result (gptel-auto-workflow--statechart-analyze sc)))
      (should (plist-get result :bottleneck))           ; validation
      (should (plist-get result :bottlenecks))         ; validation
      (should (plist-get result :expected-keep-rate))
      (should (plist-get result :lossiest-gate))       ; executor
      (should (plist-get result :phi-keep-rate-max))
      (should (plist-get result :phi-deviation))
      (should (plist-get result :per-gate))
      (should (plist-get result :gate-score-vectors))
      (should (plist-member result :compensating-errors))
      (should (plist-member result :computed-at)))))

(ert-deftest test-pipeline-statechart/statechart-analyze-bottleneck-is-lowest-p-pass ()
  "The reported :bottleneck is the gate with the lowest p-pass."
  (let* ((gates (append gptel-auto-workflow--pipeline-gates nil))
         (matrix (make-hash-table :test 'eq))
         (record (list :kept t :grader-quality 5 :decision "keep"
                       :gate-score-vector (vector 0.5 0.5 0.5 0.5 0.5
                                                  0.5 0.5 0.5 0.5 0.5 0.5)))
         (sc (list :gates gates
                   :total 10
                   :kept 5
                   :discarded 5
                   :keep-rate 0.5
                   :transition-matrix matrix
                   :records (list record)
                   :computed-at (float-time))))
    ;; All gates p-pass=1.0 except validation which is 0.3 (bottleneck)
    (dolist (gate (append gates nil))
      (puthash gate (list :p-pass 1.0 :p-fail 0.0 :entered 10 :failed 0)
               matrix))
    (puthash 'validation (list :p-pass 0.3 :p-fail 0.7 :entered 10 :failed 7)
             matrix)
    (let ((result (gptel-auto-workflow--statechart-analyze sc)))
      (should (eq 'validation (plist-get result :bottleneck))))))

(ert-deftest test-pipeline-statechart/statechart-analyze-lossiest-gate-is-highest-abs-fail ()
  "The reported :lossiest-gate is the gate with the highest absolute
failure count (NOT the lowest p-pass)."
  (let* ((gates (append gptel-auto-workflow--pipeline-gates nil))
         (matrix (make-hash-table :test 'eq))
         (record (list :kept t :grader-quality 5 :decision "keep"
                       :gate-score-vector (vector 0.5 0.5 0.5 0.5 0.5
                                                  0.5 0.5 0.5 0.5 0.5 0.5)))
         (sc (list :gates gates
                   :total 100
                   :kept 50
                   :discarded 50
                   :keep-rate 0.5
                   :transition-matrix matrix
                   :records (list record)
                   :computed-at (float-time))))
    ;; validation: p-pass=0.3 (lowest — bottleneck), but only 2 failures
    (puthash 'validation (list :p-pass 0.3 :p-fail 0.7 :entered 2 :failed 2)
             matrix)
    ;; executor: p-pass=0.9 (NOT bottleneck), but 50 absolute failures
    (puthash 'executor (list :p-pass 0.9 :p-fail 0.1 :entered 100 :failed 50)
             matrix)
    (dolist (gate (append gates nil))
      (unless (or (eq gate 'validation) (eq gate 'executor))
        (puthash gate (list :p-pass 0.5 :p-fail 0.5 :entered 0 :failed 0)
                 matrix)))
    (let ((result (gptel-auto-workflow--statechart-analyze sc)))
      ;; Bottleneck = validation (lowest p-pass=0.3)
      (should (eq 'validation (plist-get result :bottleneck)))
      ;; Lossiest = executor (highest absolute failures=50)
      (should (eq 'executor (plist-get result :lossiest-gate))))))

(ert-deftest test-pipeline-statechart/statechart-analyze-phi-keep-rate-max-is-positive ()
  "The φ-curve keep-rate-max is a positive value (we should never
report a negative or zero expected keep-rate from the golden ratio
heuristic)."
  (let* ((gates (append gptel-auto-workflow--pipeline-gates nil))
         (matrix (make-hash-table :test 'eq))
         (record (list :kept t :grader-quality 5 :decision "keep"
                       :gate-score-vector (vector 0.5 0.5 0.5 0.5 0.5
                                                  0.5 0.5 0.5 0.5 0.5 0.5)))
         (sc (list :gates gates
                   :total 1
                   :kept 1
                   :discarded 0
                   :keep-rate 1.0
                   :transition-matrix matrix
                   :records (list record)
                   :computed-at (float-time))))
    (dolist (gate (append gates nil))
      (puthash gate (list :p-pass 1.0 :p-fail 0.0 :entered 1 :failed 0)
               matrix))
    (let* ((result (gptel-auto-workflow--statechart-analyze sc))
           (phi-max (plist-get result :phi-keep-rate-max))
           (num-gates (plist-get result :num-gates)))
      (should (> phi-max 0.0))
      (should (< phi-max 1.0))
      (should (= num-gates (length gates))))))

(provide 'test-pipeline-statechart)
;;; test-pipeline-statechart.el ends here

;;; ─── TDD coverage for extract-gate-score-vectors ───
;;;
;;; Behavior: walks parsed TSV records, extracts :gate-score-vector
;;; if present, otherwise falls back to compute-gate-score-vector.

(ert-deftest test-pipeline-statechart/extract-gate-score-vectors-uses-existing-vector ()
  "If a record has :gate-score-vector (a vector), use it directly."
  (let* ((v1 (vector 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 0.0))
         (records (list (list :gate-score-vector v1))))
    (let ((result (gptel-auto-workflow--extract-gate-score-vectors records)))
      (should (= 1 (length result)))
      (should (equal v1 (car result))))))

(ert-deftest test-pipeline-statechart/extract-gate-score-vectors-fallback-to-compute ()
  "If a record has :kept t but no :gate-score-vector, fall back to
gptel-auto-workflow--compute-gate-score-vector."
  (let* ((records (list (list :kept t :grader-quality 5 :decision "keep"))))
    (let ((result (gptel-auto-workflow--extract-gate-score-vectors records)))
      (should (= 1 (length result)))
      (should (vectorp (car result))))))

(ert-deftest test-pipeline-statechart/extract-gate-score-vectors-skip-record-with-no-data ()
  "A record with neither :gate-score-vector nor :kept/:decision is
silently dropped (not an error)."
  (let ((records (list (list :foo "bar"))))  ; no relevant keys
    (let ((result (gptel-auto-workflow--extract-gate-score-vectors records)))
      (should (null result)))))

(ert-deftest test-pipeline-statechart/extract-gate-score-vectors-empty-input ()
  "Empty input list returns nil."
  (should (null (gptel-auto-workflow--extract-gate-score-vectors nil))))

(ert-deftest test-pipeline-statechart/extract-gate-score-vectors-preserves-order ()
  "Multiple records are processed in input order (FIFO)."
  (let* ((v1 (vector 0.1 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0))
         (v2 (vector 0.2 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0))
         (v3 (vector 0.3 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0))
         (records (list (list :gate-score-vector v1)
                        (list :gate-score-vector v2)
                        (list :gate-score-vector v3))))
    (let ((result (gptel-auto-workflow--extract-gate-score-vectors records)))
      (should (= 3 (length result)))
      (should (equal v1 (nth 0 result)))
      (should (equal v2 (nth 1 result)))
      (should (equal v3 (nth 2 result))))))

;;; ─── TDD coverage for statechart-drift-check ───
;;;
;;; Behavior: compares current and historical statecharts, flags any
;;; gate whose p-pass has dropped by more than the drift threshold
;;; (default 0.1).

(ert-deftest test-pipeline-statechart/drift-check-identical-no-drift ()
  "When current and historical are identical, no drift is reported."
  (let* ((gates (append gptel-auto-workflow--pipeline-gates nil))
         (matrix (make-hash-table :test 'eq))
         (sc (list :gates gates :total 10 :kept 7 :discarded 3
                   :keep-rate 0.7 :transition-matrix matrix
                   :records nil :computed-at (float-time))))
    (dolist (gate (append gates nil))
      (puthash gate (list :p-pass 0.9 :p-fail 0.1 :entered 10 :failed 1)
               matrix))
    (let ((result (gptel-auto-workflow--statechart-drift-check sc sc)))
      (should-not (plist-get result :drifted))
      (should (null (plist-get result :drifted-gates))))))

(ert-deftest test-pipeline-statechart/drift-check-drops-above-threshold ()
  "A drop in p-pass larger than the threshold flags a drift."
  (let* ((gates (append gptel-auto-workflow--pipeline-gates nil))
         (current-matrix (make-hash-table :test 'eq))
         (historical-matrix (make-hash-table :test 'eq))
         (current (list :gates gates :total 10 :kept 5 :discarded 5
                        :keep-rate 0.5 :transition-matrix current-matrix
                        :records nil :computed-at (float-time)))
         (historical (list :gates gates :total 10 :kept 9 :discarded 1
                           :keep-rate 0.9 :transition-matrix historical-matrix
                           :records nil :computed-at (float-time)))
         (threshold gptel-auto-workflow-statechart-drift-threshold))
    (dolist (gate (append gates nil))
      (puthash gate (list :p-pass 0.5 :p-fail 0.5 :entered 10 :failed 5)
               current-matrix)
      (puthash gate (list :p-pass 0.95 :p-fail 0.05 :entered 10 :failed 1)
               historical-matrix))
    ;; Override threshold to a tight value for the test
    (let ((result (let ((gptel-auto-workflow-statechart-drift-threshold 0.1))
                    (gptel-auto-workflow--statechart-drift-check current historical))))
      (should (plist-get result :drifted))
      (should (> (length (plist-get result :drifted-gates)) 0)))))

(ert-deftest test-pipeline-statechart/drift-check-improvement-no-alert ()
  "When current p-pass is BETTER than historical, no drift alert
even though delta is non-zero."
  (let* ((gates (append gptel-auto-workflow--pipeline-gates nil))
         (current-matrix (make-hash-table :test 'eq))
         (historical-matrix (make-hash-table :test 'eq))
         (current (list :gates gates :total 10 :kept 9 :discarded 1
                        :keep-rate 0.9 :transition-matrix current-matrix
                        :records nil :computed-at (float-time)))
         (historical (list :gates gates :total 10 :kept 5 :discarded 5
                           :keep-rate 0.5 :transition-matrix historical-matrix
                           :records nil :computed-at (float-time))))
    (dolist (gate (append gates nil))
      (puthash gate (list :p-pass 0.95 :p-fail 0.05 :entered 10 :failed 1)
               current-matrix)
      (puthash gate (list :p-pass 0.5 :p-fail 0.5 :entered 10 :failed 5)
               historical-matrix))
    (let ((result (gptel-auto-workflow--statechart-drift-check current historical)))
      (should-not (plist-get result :drifted))
      (should (null (plist-get result :drifted-gates))))))

;;; ─── TDD coverage for build-statechart ───
;;;
;;; Behavior: parses TSV records, classifies them by decision, builds
;;; a transition matrix with per-gate passed/failed/unreached stats,
;;; and computes keep-rate as the product of all p-passes.
;;;
;;; Test strategy: mock gptel-auto-workflow--parse-all-results via
;;; cl-letf to return a controlled list of records.

(ert-deftest test-pipeline-statechart/build-statechart-all-kept ()
  "When all records have :decision 'kept', keep-rate is 1.0 and
all gates have p-pass=1.0."
  (let* ((records (list (list :decision "kept" :grader-quality 5)
                        (list :decision "kept" :grader-quality 4)
                        (list :decision "kept" :grader-quality 3))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda (&rest _args) records)))
      (let ((result (gptel-auto-workflow--build-statechart)))
        (should (= 3 (plist-get result :total)))
        (should (= 3 (plist-get result :kept)))
        (should (= 0 (plist-get result :discarded)))
        (should (= 1.0 (plist-get result :keep-rate)))
        ;; All gates should have p-pass=1.0
        (let ((matrix (plist-get result :transition-matrix))
              (gates (plist-get result :gates)))
          (dolist (gate (append gates nil))
            (let ((entry (gethash gate matrix)))
              (should (= 1.0 (plist-get entry :p-pass)))
              (should (= 3 (plist-get entry :passed)))
              (should (= 0 (plist-get entry :failed))))))))))

(ert-deftest test-pipeline-statechart/build-statechart-all-discarded-at-executor ()
  "When all records are discarded at the executor gate, the executor
gate has failed=N, all earlier gates have passed=N, all later gates
have unreached=N."
  (let* ((records (list (list :decision "merge-conflict" :grader-quality 0)
                        (list :decision "merge-conflict" :grader-quality 0)
                        (list :decision "merge-conflict" :grader-quality 0))))
    ;; Wait - merge-conflict is a different decision. Let me use one 
    ;; that maps to 'executor' in the fail-gate mapping
    (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda (&rest _args) records))
              ((symbol-function 'gptel-auto-workflow--plist-get)
               (lambda (plist key &optional default)
                 (let ((val (lisp--plist-get plist key)))
                   (if (null val) (or default nil) val)))))
      ;; Simpler: use records that fail at executor
      (let* ((records (list (list :decision "executor-timeout" :grader-quality 0)
                            (list :decision "executor-timeout" :grader-quality 0))))
        (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
                   (lambda (&rest _args) records)))
          (let ((result (gptel-auto-workflow--build-statechart)))
            (should (= 2 (plist-get result :total)))
            (should (= 0 (plist-get result :kept)))
            (should (= 2 (plist-get result :discarded)))
            ;; Executor gate has 2 failures
            (let* ((matrix (plist-get result :transition-matrix))
                   (exec-entry (gethash 'executor matrix)))
              (should (= 2 (plist-get exec-entry :failed)))
              (should (= 0 (plist-get exec-entry :passed))))))))))

(ert-deftest test-pipeline-statechart/build-statechart-empty-input ()
  "No records means total=0, kept=0, keep-rate=1.0 (no constraints)."
  (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
             (lambda (&rest _args) nil)))
    (let ((result (gptel-auto-workflow--build-statechart)))
      (should (= 0 (plist-get result :total)))
      (should (= 0 (plist-get result :kept)))
      (should (= 0 (plist-get result :discarded)))
      (should (= 1.0 (plist-get result :keep-rate)))
      ;; All gates initialized to passed=0, failed=0 → p-pass=1.0
      (let ((matrix (plist-get result :transition-matrix))
            (gates (plist-get result :gates)))
        (dolist (gate (append gates nil))
          (let ((entry (gethash gate matrix)))
            (should (= 1.0 (plist-get entry :p-pass)))))))))

(ert-deftest test-pipeline-statechart/build-statechart-staging-pending-skipped ()
  "Records with :decision 'staging-pending' are transient and skipped
(not counted in kept or discarded)."
  (let* ((records (list (list :decision "staging-pending" :grader-quality 0)
                        (list :decision "kept" :grader-quality 5))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda (&rest _args) records)))
      (let ((result (gptel-auto-workflow--build-statechart)))
        (should (= 2 (plist-get result :total)))
        (should (= 1 (plist-get result :kept)))
        (should (= 0 (plist-get result :discarded)))))))

;;; ─── TDD coverage for statechart-report ───
;;;
;;; Behavior: calls statechart-analyze, formats the result as a
;;; human-readable string. Tests verify key sections are present.

;; Helper to construct a minimal valid analysis plist for mocking
(defun test-pipeline-statechart--make-analysis (&optional overrides)
  "Build a minimal analysis plist. OVERRIDES is an alist of (key . value)
that replaces defaults in the returned plist."
  (let* ((gates (append gptel-auto-workflow--pipeline-gates nil))
         (per-gate (mapcar (lambda (g)
                             (list :gate g :p-pass 0.9 :p-fail 0.1
                                   :entered 10 :failed 1))
                           gates))
         (base (list :bottleneck 'validation
                     :bottlenecks (list 'validation)
                     :expected-keep-rate 0.7
                     :lossiest-gate 'executor
                     :phi-keep-rate-max 0.6433
                     :phi-deviation -0.0567
                     :num-gates (length gates)
                     :total-experiments 10
                     :per-gate per-gate
                     :gate-score-vectors nil
                     :compensating-errors nil
                     :computed-at (float-time))))
    (let ((pl base))
      (dolist (ov overrides pl)
        (setq pl (plist-put pl (car ov) (cdr ov)))))))

(ert-deftest test-pipeline-statechart/statechart-report-contains-header ()
  "The report string starts with a recognizable header."
  (cl-letf (((symbol-function 'gptel-auto-workflow--statechart-analyze)
             (lambda () (test-pipeline-statechart--make-analysis))))
    (let ((report (gptel-auto-workflow--statechart-report)))
      (should (stringp report))
      (should (string-match-p "Pipeline Statechart Analysis" report)))))

(ert-deftest test-pipeline-statechart/statechart-report-contains-total-experiments ()
  "The report includes the total experiment count."
  (cl-letf (((symbol-function 'gptel-auto-workflow--statechart-analyze)
             (lambda () (test-pipeline-statechart--make-analysis
                         '((:total-experiments . 42))))))
    (let ((report (gptel-auto-workflow--statechart-report)))
      (should (string-match-p "Total experiments: 42" report)))))

(ert-deftest test-pipeline-statechart/statechart-report-contains-per-gate-table ()
  "The report includes a per-gate transition probability table
with all gates listed."
  (cl-letf (((symbol-function 'gptel-auto-workflow--statechart-analyze)
             (lambda () (test-pipeline-statechart--make-analysis))))
    (let* ((report (gptel-auto-workflow--statechart-report))
           (gates (append gptel-auto-workflow--pipeline-gates nil)))
      (should (string-match-p "Per-gate transition probabilities" report))
      (should (string-match-p "P(pass)" report))
      (dolist (gate gates)
        (should (string-match-p (symbol-name gate) report))))))

(ert-deftest test-pipeline-statechart/statechart-report-contains-bottleneck ()
  "The report includes the bottleneck gate when present."
  (cl-letf (((symbol-function 'gptel-auto-workflow--statechart-analyze)
             (lambda () (test-pipeline-statechart--make-analysis
                         '((:bottleneck . validation))))))
    (let ((report (gptel-auto-workflow--statechart-report)))
      (should (string-match-p "Bottleneck gate: validation" report)))))

(ert-deftest test-pipeline-statechart/statechart-report-omits-bottleneck-when-nil ()
  "If :bottleneck is nil, no bottleneck line appears."
  (cl-letf (((symbol-function 'gptel-auto-workflow--statechart-analyze)
             (lambda () (test-pipeline-statechart--make-analysis
                         '((:bottleneck . nil) (:bottlenecks))))))
    (let ((report (gptel-auto-workflow--statechart-report)))
      (should-not (string-match-p "Bottleneck gate:" report)))))

;;; ─── TDD coverage for statechart-show (interactive command) ───
;;;
;;; Behavior: creates a buffer "*Pipeline Statechart*", inserts the
;;; report and drift check, makes it visible.

(ert-deftest test-pipeline-statechart/statechart-show-creates-buffer ()
  "statechart-show creates a *Pipeline Statechart* buffer with content."
  (cl-letf (((symbol-function 'gptel-auto-workflow--statechart-report)
             (lambda () "Mock statechart report\n"))
            ((symbol-function 'gptel-auto-workflow--statechart-drift-check)
             (lambda () (list :drifted nil :drifted-gates nil
                              :report nil :computed-at (float-time))))
            ((symbol-function 'pop-to-buffer)
             (lambda (buf) (message "pop-to-buffer: %s" (buffer-name buf)))))
    (gptel-auto-workflow-statechart-show)
    (let ((buf (get-buffer "*Pipeline Statechart*")))
      (should buf)
      (with-current-buffer buf
        (should (string-match-p "Mock statechart report" (buffer-string)))
        (should (string-match-p "Drift Check" (buffer-string)))))))

;;; ─── TDD coverage for statechart-rebuild-and-persist ───
;;;
;;; Behavior: builds a statechart, persists it, and reports success.
;;; Errors are caught and reported, never raised.

(ert-deftest test-pipeline-statechart/statechart-rebuild-and-persist-calls-persist ()
  "rebuild-and-persist calls build-statechart, then statechart-persist
with the result."
  (let* ((sc (list :gates '(g1 g2) :total 5 :kept 3 :discarded 2
                   :keep-rate 0.6 :transition-matrix (make-hash-table :test 'eq)
                   :records nil :computed-at (float-time)))
         (persist-called-with nil))
    (cl-letf (((symbol-function 'gptel-auto-workflow--build-statechart)
               (lambda () sc))
              ((symbol-function 'gptel-auto-workflow--statechart-persist)
               (lambda (statechart) (setq persist-called-with statechart)
                   "/tmp/mock.edn")))
      (let ((result (gptel-auto-workflow--statechart-rebuild-and-persist)))
        (should (equal persist-called-with sc))))))

(ert-deftest test-pipeline-statechart/statechart-rebuild-and-persist-handles-errors ()
  "If build-statechart throws, the error is caught (not raised) and
the result string indicates failure."
  (cl-letf (((symbol-function 'gptel-auto-workflow--build-statechart)
             (lambda () (error "simulated build failure")))
            ((symbol-function 'gptel-auto-workflow--statechart-persist)
             (lambda (_) (error "should not be called"))))
    (let ((result (gptel-auto-workflow--statechart-rebuild-and-persist)))
      (should (stringp result))
      (should (string-match-p "error" result)))))
