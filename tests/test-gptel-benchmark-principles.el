;;; test-gptel-benchmark-principles.el --- Tests for Eight Keys and Wu Xing -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for gptel-benchmark-principles.el functions.
;; Run with:
;;   emacs --batch -L tests -l test-gptel-benchmark-principles.el -f ert-run-tests-batch

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gptel-benchmark-principles)

;;; Eight Keys definitions tests

(ert-deftest test-principles/eight-keys-defined ()
  "Eight keys definitions should exist."
  (should (listp gptel-benchmark-eight-keys-definitions)))

(ert-deftest test-principles/eight-keys-has-8-keys ()
  "Eight keys should have 8 keys."
  (should (= (length gptel-benchmark-eight-keys-definitions) 8)))

;;; Weight tests

(ert-deftest test-principles/weights-defined ()
  "Eight keys weights should be defined."
  (should (listp gptel-benchmark-eight-keys-weights)))

(ert-deftest test-principles/weights-all-positive ()
  "All weights should be positive."
  (dolist (weight gptel-benchmark-eight-keys-weights)
    (should (> (cdr weight) 0))))

;;; Wu Xing tests

(ert-deftest test-principles/wu-xing-report-exists ()
  "Wu Xing report function should exist."
  (should (fboundp 'gptel-benchmark-wu-xing-report)))

;; ─── TDD: Subsystem profiles ───

(ert-deftest tdd/profiles/all-five-defined ()
  "All five subsystem profiles must be defined."
  (let ((profiles gptel-benchmark-eight-keys-subsystem-profiles))
    (should (listp profiles))
    (should (= 5 (length profiles)))))

(ert-deftest tdd/profiles/each-has-8-keys ()
  "Each subsystem profile must have all 8 key weights."
  (dolist (profile gptel-benchmark-eight-keys-subsystem-profiles)
    (let* ((tag (car profile))
           (weights (plist-get profile :weights)))
      (should (= 8 (length weights)))
      (dolist (key '(phi-vitality fractal-clarity epsilon-purpose
                     tau-wisdom pi-synthesis mu-directness
                     exists-truth forall-vigilance))
        (should (alist-get key weights))))))

(ert-deftest tdd/profiles/each-has-description ()
  "Each subsystem profile must have a non-empty description."
  (dolist (profile gptel-benchmark-eight-keys-subsystem-profiles)
    (let ((desc (plist-get profile :description)))
      (should (stringp desc))
      (should (> (length desc) 10)))))

(ert-deftest tdd/profiles/weights-are-positive ()
  "All subsystem profile weights must be positive."
  (dolist (profile gptel-benchmark-eight-keys-subsystem-profiles)
    (let ((weights (plist-get (cdr profile) :weights)))
      (dolist (w weights)
        (should (> (cdr w) 0))))))

(ert-deftest tdd/profiles/autotts-emphasizes-wisdom-and-truth ()
  "AutoTTS profile must have Wisdom and Truth as the highest weights."
  (let ((weights (gptel-benchmark-get-subsystem-weights :autotts)))
    (should (> (alist-get 'tau-wisdom weights) (alist-get 'phi-vitality weights)))
    (should (> (alist-get 'tau-wisdom weights) (alist-get 'fractal-clarity weights)))
    (should (> (alist-get 'exists-truth weights) (alist-get 'mu-directness weights)))))

(ert-deftest tdd/profiles/autogo-emphasizes-vitality-and-vigilance ()
  "AutoGo profile must have Vitality and Vigilance as the highest weights."
  (let ((weights (gptel-benchmark-get-subsystem-weights :autogo)))
    (should (> (alist-get 'phi-vitality weights) (alist-get 'tau-wisdom weights)))
    (should (> (alist-get 'forall-vigilance weights) (alist-get 'pi-synthesis weights)))))

(ert-deftest tdd/profiles/get-subsystem-weights-fallback ()
  "get-subsystem-weights returns default weights for unknown subsystems."
  (let ((weights (gptel-benchmark-get-subsystem-weights :unknown)))
    (should weights)
    (should (= 8 (length weights)))))

;; ─── TDD: Subsystem-aware scoring ───

(ert-deftest tdd/score-for/different-profiles-produce-different-scores ()
  "score-for with different subsystems produces different overall scores
when the output has asymmetric signal/anti-pattern distributions."
  (let* ((wisdom-text "planning before execution error prevention foresight proactive measures risks identified")
         (scores-autotts (gptel-benchmark-eight-keys-score-for wisdom-text :autotts))
         (scores-default (gptel-benchmark-eight-keys-score wisdom-text))
         (overall-autotts (alist-get 'overall scores-autotts))
         (overall-default (alist-get 'overall scores-default)))
    ;; AutoTTS amplifies Wisdom (τ 1.5), default uses 1.0 — should differ
    (should (not (equal overall-autotts overall-default)))))

(ert-deftest tdd/score-for/vitality-heavy-output-favors-autogo ()
  "AutoGo with Vitality (φ 1.5) should score vitality output higher than Meta-harness."
  (let* ((vitality-text "builds on discoveries adapts to new information progressive improvement non-repetitive evolves approach learns from feedback")
         (scores-autogo (gptel-benchmark-eight-keys-score-for vitality-text :autogo))
         (scores-meta (gptel-benchmark-eight-keys-score-for vitality-text :meta-harness)))
    (should (> (alist-get 'overall scores-autogo) (alist-get 'overall scores-meta)))))

(ert-deftest tdd/score-for/returns-same-keys-as-score ()
  "score-for returns the same key structure as score (all 8 keys + overall)."
  (let* ((scores (gptel-benchmark-eight-keys-score-for "test output" :autotts)))
    (should (alist-get 'phi-vitality scores))
    (should (alist-get 'fractal-clarity scores))
    (should (alist-get 'epsilon-purpose scores))
    (should (alist-get 'tau-wisdom scores))
    (should (alist-get 'pi-synthesis scores))
    (should (alist-get 'mu-directness scores))
    (should (alist-get 'exists-truth scores))
    (should (alist-get 'forall-vigilance scores))
    (should (alist-get 'overall scores))))

;; ─── TDD: Dynamic variable override ───

(ert-deftest tdd/dynamic-var/binding-changes-weights ()
  "Binding gptel-benchmark--active-subsystem changes weights used.
When the active subsystem is set, the score differs from the default."
  (let* ((wisdom-text "planning before execution foresight proactive")
         (default-scores (gptel-benchmark-eight-keys-score wisdom-text))
         (default-overall (alist-get 'overall default-scores))
         (gptel-benchmark--active-subsystem :autotts)
         (autotts-scores (gptel-benchmark-eight-keys-score wisdom-text))
         (autotts-overall (alist-get 'overall autotts-scores)))
    ;; AutoTTS amplifies Wisdom (τ 1.5 > 1.0) — overall score should differ
    (should (not (equal default-overall autotts-overall)))))

(ert-deftest tdd/dynamic-var/nil-binding-uses-default ()
  "When gptel-benchmark--active-subsystem is nil, default weights are used."
  (let* ((gptel-benchmark--active-subsystem nil)
         (scores (gptel-benchmark-eight-keys-score "test"))
         (weights-scores (gptel-benchmark--eight-keys-score-with-weights
                          "test" nil gptel-benchmark-eight-keys-weights))
         (overall-var (alist-get 'overall scores))
         (overall-default (alist-get 'overall weights-scores)))
    (should (equal overall-var overall-default))))

(ert-deftest tdd/dynamic-var/score-function-respects-binding ()
  "gptel-benchmark-eight-keys-score respects the dynamic variable binding.
Setting :meta-harness (Clarity 1.5) changes the score."
  (let* ((no-bind (gptel-benchmark-eight-keys-score "test"))
         (gptel-benchmark--active-subsystem :meta-harness)
         (with-bind (gptel-benchmark-eight-keys-score "test explicit assumptions testable definitions clear structure")))
    (should (not (equal (alist-get 'overall no-bind)
                        (alist-get 'overall with-bind))))))

(provide 'test-gptel-benchmark-principles)
;;; test-gptel-benchmark-principles.el ends here