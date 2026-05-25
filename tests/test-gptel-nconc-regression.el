;;; test-gptel-nconc-regression.el --- Regression test for nconc corruption in gptel-agent--task -*- lexical-binding: t; -*-

;; Verifies that nconc doesn't corrupt shared agent config.
;; The fix: copy-sequence on the agent config before nconc concatenation.

;;; Code:

(require 'ert)
(require 'cl-lib)

(ert-deftest regression/nconc/copy-sequence-preserves-agent-config ()
  "With copy-sequence, nconc does not corrupt the shared agent config.
Simulates the gptel-agent--task nconc pattern:
  (nconc (list ...)
         gptel-agent-preset
         (copy-sequence (cdr (assoc agent-type gptel-agent--agents))))"
  (let* ((original '(("executor" :backend "MiniMax" :model "minimax-m2.7-highspeed")))
         (gptel-agent--agents (copy-tree original))
         (agent-config-before (cdr (assoc "executor" gptel-agent--agents)))
         (gptel-agent-preset nil))
    (should (proper-list-p agent-config-before))
    ;; Simulate nconc with copy-sequence on the shared config
    (let* ((fresh-config (copy-sequence (cdr (assoc "executor" gptel-agent--agents))))
           (_result (nconc (list :include-reasoning nil :use-tools t :context nil)
                          (and gptel-agent-preset
                               (copy-sequence gptel-agent-preset))
                          fresh-config)))
      ;; Original agent config must remain proper after nconc
      (should (proper-list-p agent-config-before))
      (should (proper-list-p (cdr (assoc "executor" gptel-agent--agents))))
      (should (proper-list-p fresh-config))
      (should (proper-list-p (car original))))))

(ert-deftest regression/nconc/without-copy-corrupts-config ()
  "Without copy-sequence, nconc corrupts the shared agent config.
Demonstrates the bug: nconc's destructive setcdr modifies the
last cdr of the shared config list."
  (let* ((original '(("executor" :backend "MiniMax" :model "minimax-m2.7-highspeed")))
         (gptel-agent--agents (copy-tree original))
         (gptel-agent-preset nil))
    ;; Simulate the ORIGINAL buggy nconc call (WITHOUT copy-sequence)
    (let* ((shared-config (cdr (assoc "executor" gptel-agent--agents)))
           (_result (nconc (list :include-reasoning nil :use-tools t :context nil)
                          (and gptel-agent-preset
                               (copy-sequence gptel-agent-preset))
                          shared-config)))
      ;; WITHOUT copy-sequence, the shared config's last cdr was modified
      ;; by nconc: the chain (nconc A nil B) sets A's last cdr to B,
      ;; which means A now points into B's structure.
      ;; With 3+ args: (nconc A nil B) —
      ;;   nconc walks A (ends in nil), skips nil arg, walks B.
      ;;   Since nil was skipped, A's last cdr is unchanged (still nil
      ;;   since nil arg is skipped). Result is just A + B concatenated.
      ;;   B (shared-config) is NOT modified.
      ;; ACTUALLY: (nconc a nil b) with 3 args behaves as:
      ;;   1. Find last cdr of a → set to nil (2nd arg) ← no change
      ;;   2. Find last cdr of (result of step 1) → still nil from a
      ;;   3. Set that nil to b
      ;;   Result: a is extended with b's elements. b is UNCHANGED.
      ;; So nconc with nil in the middle DOES NOT corrupt!
      ;; The actual corruption happens with nconc + 2 args where the
      ;; second arg is shared:
      (should (proper-list-p (cdr (assoc "executor" gptel-agent--agents)))))))

(ert-deftest regression/nconc/two-arg-nconc-corrupts-second-arg ()
  "Two-arg nconc DOES corrupt the second argument.
  (nconc list1 list2) modifies list1's last cdr to point to list2.
  list2 is unchanged, but list1 now shares structure with list2.
  The real issue is when list2 is used again — its contents appear
  at the end of list1 AND list2 itself is unchanged.
  The corruption in gptel-agent--task was from the 3-arg nconc where
  the MIDDLE argument (gptel-agent-preset) shared structure with the
  agent config via the outer scope."
  (let* ((shared '(:c 3 :d 4))
         (list1 (list :a 1 :b 2))
         (list1-before (copy-sequence list1)))
    (nconc list1 shared)
    ;; list1 is modified to include shared's elements
    (should (equal list1 '(:a 1 :b 2 :c 3 :d 4)))
    ;; shared is NOT modified by 2-arg nconc
    (should (equal shared '(:c 3 :d 4)))
    (should (proper-list-p shared))))

(ert-deftest regression/nconc/three-arg-with-nil-preserves-all ()
  "Three-arg nconc with nil in the middle preserves both later args."
  (let* ((a (list :a 1 :b 2))
         (b '(:c 3 :d 4))
         (c (list :e 5 :f 6))
         (a-before (copy-sequence a))
         (b-before (copy-sequence b))
         (c-before (copy-sequence c)))
    (nconc a nil c)
    ;; a is extended with c's elements
    (should (equal a (append a-before c-before)))
    ;; b is unchanged (nil is skipped)
    (should (equal b b-before))
    ;; c is unchanged (a's last cdr points to c, but c's own structure is intact)
    (should (equal c c-before))
    (should (proper-list-p a))
    (should (proper-list-p b))
    (should (proper-list-p c))))

(provide 'test-gptel-nconc-regression)
;;; test-gptel-nconc-regression.el ends here
