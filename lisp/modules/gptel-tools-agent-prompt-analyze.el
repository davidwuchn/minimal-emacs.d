; -*- lexical-binding: t; -*-
(declare-function gptel-auto-experiment--call-aux-subagent-with-retry "gptel-tools-agent-benchmark")
(declare-function gptel-auto-experiment--decision-gate "gptel-tools-agent-benchmark")
(declare-function gptel-auto-workflow--plist-get "gptel-tools-agent-base")
(declare-function gptel-auto-experiment--expected-comparator-winner "gptel-tools-agent-benchmark")
(declare-function gptel-auto-experiment--parse-comparator-winner "gptel-tools-agent-benchmark")
(declare-function my/gptel--invoke-callback-safely "gptel-tools-agent-subagent")
(defvar gptel-auto-experiment-use-subagents)
(require 'cl-lib)
;;; gptel-tools-agent-prompt-analyze.el --- Prompt building - analysis & selection -*- lexical-binding: t; -*-
;; Part of gptel-tools-agent split

(defun gptel-auto-experiment-decide (before after callback)
  "Compare BEFORE vs AFTER using LLM comparator.
CALLBACK receives keep/discard decision with reasoning.  LLM decides
when available; local fallback for tests.  The comparator subagent
overlay will appear in the current buffer at time of call."
  ;; Capture the current buffer to ensure comparator overlay appears in right place
  (let* ((decide-buffer (current-buffer))
         (score-before (gptel-auto-workflow--plist-get before :score 0))
         (score-after (gptel-auto-workflow--plist-get after :score 0))
         (quality-before (gptel-auto-workflow--plist-get before :code-quality 0.5))
         (quality-after (gptel-auto-workflow--plist-get after :code-quality 0.5))
         (combined-before (+ (* 0.6 score-before) (* 0.4 quality-before)))
         (combined-after (+ (* 0.6 score-after) (* 0.4 quality-after)))
         (decision-threshold 0.005)
         (numeric-winner
          (gptel-auto-experiment--expected-comparator-winner
           combined-before combined-after decision-threshold))
         (gated-decision
          (gptel-auto-experiment--decision-gate
           numeric-winner
           score-before score-after
           quality-before quality-after
           combined-before combined-after
           decision-threshold))
         (expected-winner (plist-get gated-decision :winner))
         (gate-note (plist-get gated-decision :note)))
    (if (and gptel-auto-experiment-use-subagents
             (fboundp 'gptel-benchmark-call-subagent))
        (let ((compare-prompt (format "λ compare(A,B). combined = 0.6·eightKeys + 0.4·quality (ε=%.3f)
A:  S=%.3f  Q=%.3f  C=%.3f
B:  S=%.3f  Q=%.3f  C=%.3f
| C(B) > C(A) + ε → B | C(A) > C(B) + ε → A | else → tie
OUTPUT: line1=\"A\"|\"B\"|\"tie\" line2=reason(1 sentence)"
                                      decision-threshold
                                      score-before quality-before combined-before
                                      score-after quality-after combined-after)))
          (with-current-buffer decide-buffer
            (gptel-auto-experiment--call-aux-subagent-with-retry
             "comparator"
             (lambda (cb)
               (gptel-benchmark-call-subagent
                'comparator
                "Compare experiment results"
                compare-prompt
                cb))
             (lambda (result)
               (let* ((response (if (stringp result) result (format "%S" result)))
                       (reported-winner (or (gptel-auto-experiment--parse-comparator-winner response)
                                            "unparsed"))
                        (override (not (string= reported-winner expected-winner)))
                        (gate-rejects-clearly (and gate-note
                                                   (string-match-p "\\`Rejected:" gate-note)))
                        (winner (if (and override (string= reported-winner "B") (not gate-rejects-clearly))
                                    "B"
                                  expected-winner))
                        (keep (string= winner "B")))
                 (my/gptel--invoke-callback-safely
                  callback
                  (list :keep keep
                        :reasoning (format "%sWinner: %s | Score: %.2f → %.2f, Quality: %.2f → %.2f, Combined: %.2f →
%.2f%s"
                                           (if override
                                               (format "Comparator override: %s -> %s | "
                                                       reported-winner winner)
                                             "")
                                           winner score-before score-after
                                           quality-before quality-after
                                           combined-before combined-after
                                           (if gate-note
                                               (format " | %s" gate-note)
                                             ""))
                        :improvement (list :score (- score-after score-before)
                                           :quality (- quality-after quality-before)
                                           :combined (- combined-after combined-before)))))))))
      (let ((winner expected-winner)
            (keep (string= expected-winner "B")))
        (my/gptel--invoke-callback-safely
         callback
         (list :keep keep
               :reasoning (format "Local: Winner: %s | Score: %.2f → %.2f, Quality: %.2f → %.2f, Combined: %.2f → %.2f%s"
                                  winner
                                  score-before score-after
                                  quality-before quality-after
                                  combined-before combined-after
                                  (if gate-note
                                      (format " | %s" gate-note)
                                    ""))
               :improvement (list :score (- score-after score-before)
                                  :quality (- quality-after quality-before)
                                  :combined (- combined-after combined-before))))))))

(defun gptel-auto-experiment--strong-grade-pass-p (grade-score grade-total)
  "Return non-nil when GRADE-SCORE reflects a strong pass (>= 70%).
GRADE-TOTAL can be nil when the grader omits an explicit denominator.
Lowered from 85% to 70% to match the grader's pass threshold — the
structural eight-keys scorer often returns 0.0 for valid changes,
so we trust the grader more aggressively."
  (let ((score (if (numberp grade-score) grade-score 0)))
    (if (and (numberp grade-total) (> grade-total 0))
        (>= (/ (float score) grade-total) 0.70)
      (>= score 7))))

(defun gptel-auto-experiment--speculative-correctness-language-p (text)
  "Return non-nil when TEXT describes a speculative or clarity-only fix."
  (when (stringp text)
    (string-match-p
     (rx (or "potential "
             "possible "
             "hypothetical"
             "defensive hardening"
             "improves robustness"
             "enhances robustness"
             "without changing behavior"
             "without altering behavior"
             "improves clarity"
             "improves testability"
             "improve clarity"
             "improve testability"
             "clarity by "
             "making the control flow explicit"
             "consistent with "
             "reducing code duplication"
             "avoid unnecessary"
             "avoids unnecessary"
             "unnecessary timer cancellation"
             "unnecessary stop/start operations"
             "wasteful operations"
             "redundant timer cancellation"
             "edge case"
             "edge cases"
             "could "
             "might "
             "may "))
     text)))

(defun gptel-auto-experiment--grade-explanation-text (grade-details)
  "Return explanation-only text extracted from GRADE-DETAILS.
When the grader emits rubric bullets like `PASS - ...', ignore the rubric
labels
and preserve only the explanatory text to avoid matching static prompt
wording."
  (when (stringp grade-details)
    (let ((start 0)
          explanations)
      (while (string-match
              (rx (or "PASS - " "FAIL - ")
                  (group (*? (not (any "|")))))
              grade-details
              start)
        (let ((segment (string-trim (match-string 1 grade-details))))
          (unless (string-empty-p segment)
            (push segment explanations)))
        (setq start (match-end 0)))
      (if explanations
          (string-join (nreverse explanations) "\n")
        grade-details))))

(defun gptel-auto-experiment--grader-indicates-correctness-fix-p (grade-details)
  "Return non-nil when GRADE-DETAILS describes a real correctness fix.
Speculative or purely defensive hardening language does not count."
  (let ((grade-signals
         (gptel-auto-experiment--grade-explanation-text grade-details)))
    (when (stringp grade-signals)
      (let ((case-fold-search t))
         (and
          (string-match-p
           (rx (or (seq (or "fixes"
                            "fixed"
                            "resolves"
                            "resolved"
                            "corrects"
                            "corrected"
                            "eliminates"
                            "eliminated"
                            "addresses"
                            "addressed"
                            "prevents"
                            "prevented")
                        (* (not (any ".\n")))
                        (or "bug"
                            "bugs"
                            "runtime error"
                            "runtime errors"
                            "crash"
                            "crashes"
                            "security hole"
                            "security issue"
                            "state corruption"
                            "logic failure"
                            "correctness bug"
                            "correctness bugs"
                            "functional regression"
                            "functional regressions"))
                   "genuine bug"
                   "genuine bugs"
                   "actual functional bug"
                   "actual functional bugs"
                   "demonstrably buggy"))
          grade-signals)
         (not
          (gptel-auto-experiment--speculative-correctness-language-p
           grade-signals)))))))

(defun gptel-auto-experiment--normal-grade-details-p (grade-details)
  "Return non-nil when GRADE-DETAILS is a normal rubric result."
  (and (stringp grade-details)
       (string-match-p "Grader result for task:[[:space:]]*Grade output" grade-details)
       (string-match-p "SUMMARY:[[:space:]]*SCORE:" grade-details)))

(defun gptel-auto-experiment--promote-correctness-fix-decision
    (decision tests-passed grade-score grade-total grade-details &optional hypothesis)
  "Return DECISION or a promoted keep decision for high-confidence ties.
Promotion is allowed for non-regressing ties with passing tests, some
positive quality/combined improvement, strong grader evidence of a real
correctness fix.

Additionally, when the gate rejects a confirmed bug fix because code quality
drops slightly (guard code adds necessary complexity), the correctness bypass
overrides the rejection.  A bug fix that the grader scores 8+/9 should not be
rejected solely because nil guards or validation checks increase complexity.

Grade bypass: when the grader strongly confirms (8+/9) that a change is a
genuine improvement but the structural scoring formula rejects it (because
guard code penalizes length/complexity metrics), trust the grader over the
formula.  This handles guard additions, validation, error handling, and
documentation improvements that the structural model can't evaluate."
  (let* ((improvement (and (listp decision) (plist-get decision :improvement)))
         (decision-threshold 0.005)
         (score-delta (if (listp improvement)
                          (or (plist-get improvement :score) 0)
                        0))
         (quality-delta (if (listp improvement)
                            (or (plist-get improvement :quality) 0)
                          0))
         (combined-delta (if (listp improvement)
                             (or (plist-get improvement :combined) 0)
                           0))
         (reasoning (and (listp decision) (plist-get decision :reasoning)))
         (gate-rejected-p
          (and (stringp reasoning)
               (string-match-p (rx "Rejected:") reasoning)))
         (correctness-fix-p
          (gptel-auto-experiment--grader-indicates-correctness-fix-p
           grade-details))
         (speculative-hypothesis-p
          (gptel-auto-experiment--speculative-correctness-language-p
           hypothesis))
         (strong-grade-p
          (gptel-auto-experiment--strong-grade-pass-p
           grade-score grade-total))
         (score-acceptable-p
          (> score-delta (- decision-threshold)))
         ;; Grader bypass: when the grader strongly confirms a genuine quality
         ;; improvement (8+/9) but the structural formula rejects it, trust the
         ;; grader.  Guard code, validation, error handling, and documentation
         ;; additions all penalize the length/complexity quality metrics but are
         ;; genuine improvements.  The quality-delta floor prevents bypassing
         ;; for changes that actively damage the codebase.
         (grade-confirms-quality-p
          (and strong-grade-p
               (not speculative-hypothesis-p)
               (>= quality-delta -0.12)
               (>= score-delta -0.01)
               (>= combined-delta -0.05)))
         (grade-bypass-p
          (and (listp decision)
               (not (plist-get decision :keep))
               grade-confirms-quality-p))
         (correctness-bypass-p
          (and (listp decision)
               (not (plist-get decision :keep))
               correctness-fix-p
               (not speculative-hypothesis-p)
               strong-grade-p
               score-acceptable-p))
         (override-note
          (cond
           (grade-bypass-p
            (format "Grader-confirmed quality: %d/%d bypasses structural regression (quality Δ%.3f combined Δ%.3f)"
                    grade-score (or grade-total 9) quality-delta combined-delta))
           (correctness-bypass-p
            (format "Correctness fix: grader %d/%d confirms real bug fix keeping despite quality delta %.3f"
                    grade-score (or grade-total 9) quality-delta))
           (t
            "Override: keep non-regressing high-confidence tie with passing tests"))))
    ;; Grade bypass: grader strongly confirms improvement, trust it.
    (if grade-bypass-p
        (let ((promoted (copy-sequence decision)))
          (setq promoted (plist-put promoted :keep t))
          (plist-put
           promoted
           :reasoning
           (if (and (stringp reasoning)
                    (not (string-match-p (regexp-quote override-note) reasoning)))
               (format "%s | %s" override-note reasoning)
             override-note)))
      ;; Correctness bypass: promote genuine bug fixes that the grader strongly confirms.
      (if correctness-bypass-p
          (let ((promoted (copy-sequence decision)))
            (setq promoted (plist-put promoted :keep t))
            (plist-put
             promoted
             :reasoning
             (if (and (stringp reasoning)
                      (not (string-match-p (regexp-quote override-note) reasoning)))
                 (format "%s | %s" override-note reasoning)
               override-note)))
        ;; Standard promotion: only for non-rejecting score-ties with positive quality.
        (if (or (not (listp decision))
                (plist-get decision :keep)
                (not tests-passed)
                (<= score-delta (- decision-threshold))
                (<= quality-delta 0)
                (<= combined-delta 0)
                gate-rejected-p
                (not correctness-fix-p)
                speculative-hypothesis-p
                (not strong-grade-p))
            decision
          (let ((promoted (copy-sequence decision)))
            (setq promoted (plist-put promoted :keep t))
            (plist-put
             promoted
             :reasoning
             (if (and (stringp reasoning)
                      (not (string-match-p (regexp-quote override-note) reasoning)))
                 (format "%s | %s" override-note reasoning)
               override-note))))))))

;;; Prompt Building

(defconst gptel-auto-experiment-large-target-byte-threshold 60000
  "Byte size above which experiment prompts enable the focus contract.")

(defconst gptel-auto-experiment-large-target-focus-token-weights
  '(("callback" . 6.0)
    ("timer" . 5.0)
    ("safe" . 5.0)
    ("validate" . 4.0)
    ("check" . 4.0)
    ("status" . 4.0)
    ("build" . 3.0)
    ("prompt" . 3.0)
    ("state" . 3.0)
    ("retry" . 3.0)
    ("sync" . 2.0)
    ("select" . 2.0)
    ("focus" . 2.0)
    ("buffer" . 2.0)
    ("worktree" . 1.0)
    ("stage" . 1.0))
  "Name-token weights for controller-selected large-target focus symbols.")

(defconst gptel-auto-experiment-large-target-focus-max-candidates 8
  "Maximum ranked large-target focus candidates to rotate across experiments.")

(defun gptel-auto-experiment--target-byte-size (target-full-path)
  "Return the byte size for TARGET-FULL-PATH, or nil when unavailable."
  (let ((attrs (and (stringp target-full-path)
                    (ignore-errors (file-attributes target-full-path)))))
    (when attrs
      (file-attribute-size attrs))))

(defun gptel-auto-experiment--collect-top-level-definitions (target-full-path)
  "Return top-level definitions from TARGET-FULL-PATH as plists."
  (when (and (stringp target-full-path)
             (file-readable-p target-full-path))
    (with-temp-buffer
      (insert-file-contents target-full-path)
      (let ((definition-rx
             "









^(\\(\\(?:cl-defun\\|defun\\|defsubst\\|defmacro\\|cl-defmethod\\|defvar\\|defconst\\|defcustom\\)\\)\\s-+\\([^()\n\t
]+\\)")
            definitions
            total-lines)
        (goto-char (point-min))
        (while (re-search-forward definition-rx nil t)
          (push (list :kind (match-string 1)
                      :name (match-string 2)
                      :start-line (line-number-at-pos (match-beginning 0)))
                definitions))
        (setq definitions (nreverse definitions)
              total-lines (line-number-at-pos (point-max)))
        (cl-loop for current in definitions
                 for next = (cadr (memq current definitions))
                 collect
                 (let* ((start-line (plist-get current :start-line))
                        (end-line (if next
                                      (1- (plist-get next :start-line))
                                    total-lines))
                        (size-lines (1+ (- end-line start-line)))
                        (candidate (copy-sequence current)))
                   (setq candidate (plist-put candidate :end-line end-line))
                   (plist-put candidate :size-lines size-lines)))))))

(defun gptel-auto-experiment--large-target-focus-score (candidate)
  "Return a deterministic focus score for large-target CANDIDATE."
  (let* ((name (downcase (or (plist-get candidate :name) "")))
         (size (or (plist-get candidate :size-lines) 0))
         (score 0.0))
    (dolist (entry gptel-auto-experiment-large-target-focus-token-weights)
      (when (string-match-p (car entry) name)
        (setq score (+ score (cdr entry)))))
    (setq score (+ score (max 0.0 (- 8.0 (/ (abs (- size 24)) 4.0)))))
    (when (string-prefix-p "my/" name)
      (setq score (+ score 1.5)))
    (when (string-match-p "--" name)
      (setq score (+ score 0.5)))
    score))

(defun gptel-auto-experiment--select-large-target-focus (target-full-path experiment-id)
  "Return a controller-selected focus candidate for TARGET-FULL-PATH.
Rotates across the top-ranked candidates using EXPERIMENT-ID."
  (let* ((candidates
          (cl-loop for candidate in (gptel-auto-experiment--collect-top-level-definitions
                                     target-full-path)
                   when (and (member (plist-get candidate :kind)
                                     '("defun" "cl-defun" "defsubst"))
                             (<= 8 (or (plist-get candidate :size-lines) 0) 120))
                   collect (plist-put (copy-sequence candidate)
                                      :score
                                      (gptel-auto-experiment--large-target-focus-score
                                       candidate))))
         (ranked (sort candidates
                       (lambda (a b)
                         (let ((score-a (or (plist-get a :score) 0.0))
                               (score-b (or (plist-get b :score) 0.0)))
                           (if (= score-a score-b)
                               (< (or (plist-get a :start-line) most-positive-fixnum)
                                  (or (plist-get b :start-line) most-positive-fixnum))
                             (> score-a score-b))))))
         (shortlist (seq-take ranked gptel-auto-experiment-large-target-focus-max-candidates)))
    (when shortlist
      (nth (mod (max 0 (1- (or experiment-id 1)))
                (length shortlist))
           shortlist))))

(defun gptel-auto-experiment--inspection-thrash-result-p (result)
  "Return non-nil when RESULT records an inspection-thrash failure."
  (when (proper-list-p result)
    (cl-some
     (lambda (text)
       (and (stringp text)
            (string-match-p "inspection-thrash aborted" text)))
     (list (plist-get result :error)
           (plist-get result :agent-output)
           (plist-get result :grader-reason)
           (plist-get result :comparator-reason)))))

(defun gptel-auto-experiment--needs-inspection-thrash-recovery-p (previous-results)
  "Return non-nil when PREVIOUS-RESULTS include inspection-thrash failures."
  (cl-some #'gptel-auto-experiment--inspection-thrash-result-p previous-results))

(defun gptel-auto-experiment--retry-history (previous-results result)
  "Return retry history from PREVIOUS-RESULTS plus any durable guidance in
RESULT.
Retries should learn from inspection-thrash failures immediately so the next
prompt activates the focused recovery contract."
  (if (and result
           (gptel-auto-experiment--inspection-thrash-result-p result))
      (append previous-results (list result))
    previous-results))

(provide 'gptel-tools-agent-prompt-analyze)
;;; gptel-tools-agent-prompt-analyze.el ends here
