;;; test-strategic-daemon-functions.el --- Tests for AutoTTS research controller -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for strategic-daemon-functions.el functions.
;; Run with:
;;   emacs --batch -L tests -l test-strategic-daemon-functions.el -f ert-run-tests-batch

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'strategic-daemon-functions)

;;; Root/path tests

(ert-deftest test-daemon/autotts-root-returns-directory ()
  (let ((root (gptel-auto-workflow--autotts-root)))
    (should (stringp root))
    (should (string-suffix-p "/" root))))

(ert-deftest test-daemon/autotts-file-expands-path ()
  (let ((path (gptel-auto-workflow--autotts-file "var/tmp/test.json")))
    (should (stringp path))
    (should (string-match-p "var/tmp/test.json" path))))

;;; Branch pool tests

(ert-deftest test-daemon/branch-pool-init ()
  (gptel-auto-workflow--branch-pool-init)
  (should (= (gptel-auto-workflow--branch-pool-active-count) 0)))

(ert-deftest test-daemon/branch-pool-active-count-zero-initially ()
  (gptel-auto-workflow--branch-pool-init)
  (should (= (gptel-auto-workflow--branch-pool-active-count) 0)))

(ert-deftest test-daemon/branch-pool-add-max-respected ()
  (gptel-auto-workflow--branch-pool-init)
  (let ((gptel-auto-workflow--branch-pool-max 2))
    (gptel-auto-workflow--branch-pool-add "s1" "f1" 100)
    (gptel-auto-workflow--branch-pool-add "s2" "f2" 200)
    (gptel-auto-workflow--branch-pool-add "s3" "f3" 300)
    (should (= (gptel-auto-workflow--branch-pool-active-count) 2))))

(ert-deftest test-daemon/branch-pool-remove ()
  (gptel-auto-workflow--branch-pool-init)
  (let ((b (gptel-auto-workflow--branch-pool-add "s1" "f1" 100)))
    (should (= (gptel-auto-workflow--branch-pool-active-count) 1))
    (gptel-auto-workflow--branch-pool-remove (plist-get b :id))
    (should (= (gptel-auto-workflow--branch-pool-active-count) 0))))

(ert-deftest test-daemon/branch-pool-get-best-prefers-aligned ()
  (gptel-auto-workflow--branch-pool-init)
  (gptel-auto-workflow--branch-pool-add "s1" "longer findings here for higher score" 100)
  (let ((deviant-branch (gptel-auto-workflow--branch-pool-add "s2" "short" 200)))
    (setq gptel-auto-workflow--branch-pool
          (cl-mapcar (lambda (b)
                       (if (= (plist-get b :id) (plist-get deviant-branch :id))
                           (plist-put b :alignment 'deviant)
                         b))
                     gptel-auto-workflow--branch-pool))
    (let ((best (gptel-auto-workflow--branch-pool-get-best)))
      (should (equal (plist-get best :strategy) "s1")))))

;;; EMA tests

(ert-deftest test-daemon/reset-research-ema ()
  (gptel-auto-workflow--reset-research-ema)
  (should (= (gptel-auto-workflow--research-ema-delta) 0.0)))

(ert-deftest test-daemon/ema-update-with-number ()
  (gptel-auto-workflow--reset-research-ema)
  (setq gptel-auto-workflow--research-ema-alpha 0.5)
  (let ((v1 (gptel-auto-workflow--update-research-ema 0.5)))
    (should (<= (abs (- v1 0.25)) 0.001)))
  (let ((v2 (gptel-auto-workflow--update-research-ema 0.7)))
    (should (<= (abs (- v2 0.475)) 0.001))))

(ert-deftest test-daemon/ema-update-with-nil ()
  (gptel-auto-workflow--reset-research-ema)
  (should (= (gptel-auto-workflow--update-research-ema nil) 0.0)))

(ert-deftest test-daemon/ema-update-with-non-number ()
  (gptel-auto-workflow--reset-research-ema)
  (should (= (gptel-auto-workflow--update-research-ema "bad") 0.0)))

(ert-deftest test-daemon/ema-delta-with-history ()
  (gptel-auto-workflow--reset-research-ema)
  (setq gptel-auto-workflow--research-ema-history '(0.8 0.7 0.6 0.5))
  (let ((delta (gptel-auto-workflow--research-ema-delta)))
    (should (<= (abs (- delta 0.3)) 0.001))))

(ert-deftest test-daemon/ema-delta-single-entry ()
  (gptel-auto-workflow--reset-research-ema)
  (setq gptel-auto-workflow--research-ema-history '(0.5))
  (should (= (gptel-auto-workflow--research-ema-delta) 0.0)))

(ert-deftest test-daemon/ema-delta-empty ()
  (gptel-auto-workflow--reset-research-ema)
  (should (= (gptel-auto-workflow--research-ema-delta) 0.0)))

;;; Beta schedule tests

(ert-deftest test-daemon/beta-schedule-is-function ()
  (should (functionp 'gptel-auto-workflow--research-beta-schedule)))

(ert-deftest test-daemon/beta-schedule-0-conservative ()
  (let ((p (gptel-auto-workflow--research-beta-schedule 0.0)))
    (should (= (plist-get p :max-turns) 2))
    (should (= (plist-get p :token-budget) 4000))
    (should (= (plist-get p :beta) 0.0))))

(ert-deftest test-daemon/beta-schedule-1-aggressive ()
  (let ((p (gptel-auto-workflow--research-beta-schedule 1.0)))
    (should (= (plist-get p :max-turns) 8))
    (should (= (plist-get p :token-budget) 12000))
    (should (= (plist-get p :beta) 1.0))))

(ert-deftest test-daemon/beta-schedule-0.5-mid ()
  (let ((p (gptel-auto-workflow--research-beta-schedule 0.5)))
    (should (= (plist-get p :max-turns) 5))
    (should (= (plist-get p :token-budget) 8000))
    (should (= (plist-get p :beta) 0.5))))

(ert-deftest test-daemon/beta-schedule-clamps ()
  (let ((p (gptel-auto-workflow--research-beta-schedule -0.5)))
    (should (= (plist-get p :max-turns) 2)))
  (let ((p (gptel-auto-workflow--research-beta-schedule 2.0)))
    (should (= (plist-get p :max-turns) 8))))

;;; Controller decision tests

(ert-deftest test-daemon/decision-signature-high-rising ()
  (let ((sig (gptel-auto-workflow--controller-decision-signature 'continue 0.85 0.05 "test output")))
    (should (eq (nth 0 sig) 'continue))
    (should (eq (nth 1 sig) 'high))
    (should (eq (nth 2 sig) 'rising))))

(ert-deftest test-daemon/decision-signature-low-falling ()
  (let ((sig (gptel-auto-workflow--controller-decision-signature 'branch 0.2 -0.05 nil)))
    (should (eq (nth 0 sig) 'branch))
    (should (eq (nth 1 sig) 'low))
    (should (eq (nth 2 sig) 'falling))))

(ert-deftest test-daemon/decision-signature-medium-stable ()
  (let ((sig (gptel-auto-workflow--controller-decision-signature 'stop 0.55 0.0 "")))
    (should (eq (nth 0 sig) 'stop))
    (should (eq (nth 1 sig) 'medium))
    (should (eq (nth 2 sig) 'stable))))

(ert-deftest test-daemon/doom-loop-detected-stop ()
  (gptel-auto-workflow--reset-research-ema)
  (setq gptel-auto-workflow--controller-decision-history
        '((stop high rising "a")))
  (setq gptel-auto-workflow--controller-doom-loop-threshold 1)
  (should (eq (gptel-auto-workflow--detect-controller-doom-loop) 'stop)))

(ert-deftest test-daemon/doom-loop-detected-continue ()
  (gptel-auto-workflow--reset-research-ema)
  (setq gptel-auto-workflow--controller-decision-history
        '((continue high rising "a") (continue high rising "a") (continue high rising "a")))
  (setq gptel-auto-workflow--controller-doom-loop-threshold 3)
  (should (eq (gptel-auto-workflow--detect-controller-doom-loop) 'branch)))

(ert-deftest test-daemon/doom-loop-not-detected-continue ()
  (gptel-auto-workflow--reset-research-ema)
  (setq gptel-auto-workflow--controller-decision-history
        '((continue high rising "a") (continue high rising "a")))
  (setq gptel-auto-workflow--controller-doom-loop-threshold 3)
  (should-not (gptel-auto-workflow--detect-controller-doom-loop)))

(ert-deftest test-daemon/doom-loop-not-detected-different ()
  (gptel-auto-workflow--reset-research-ema)
  (setq gptel-auto-workflow--controller-decision-history
        '((stop high rising "a") (continue medium stable "b")))
  (setq gptel-auto-workflow--controller-doom-loop-threshold 2)
  (should-not (gptel-auto-workflow--detect-controller-doom-loop)))

(ert-deftest test-daemon/doom-loop-not-detected-empty ()
  (gptel-auto-workflow--reset-research-ema)
  (setq gptel-auto-workflow--controller-decision-history nil)
  (should-not (gptel-auto-workflow--detect-controller-doom-loop)))

(ert-deftest test-daemon/record-controller-decision ()
  (gptel-auto-workflow--reset-research-ema)
  (setq gptel-auto-workflow--controller-decision-history nil)
  (gptel-auto-workflow--record-controller-decision 'stop 0.7 0.02 "text")
  (should (= (length gptel-auto-workflow--controller-decision-history) 1)))

;;; Category stop threshold tests

(ert-deftest test-daemon/category-stop-threshold-programming ()
  (should (= (gptel-auto-workflow--category-stop-threshold "defun foo bar" 0.65) 0.55)))

(ert-deftest test-daemon/category-stop-threshold-tool-calls ()
  (should (= (gptel-auto-workflow--category-stop-threshold "tool sandbox permit" 0.65) 0.75)))

(ert-deftest test-daemon/category-stop-threshold-agentic ()
  (let ((v (gptel-auto-workflow--category-stop-threshold "agent fsm coordinat" 0.65)))
    (should (<= (abs (- v 0.70)) 0.001))))

(ert-deftest test-daemon/category-stop-threshold-natural ()
  (should (= (gptel-auto-workflow--category-stop-threshold "hello world" 0.65) 0.65)))

;;; Source classification tests

(ert-deftest test-daemon/source-classify-aligned ()
  (let ((findings "## technique\ngptel module"))
    (should (eq (gptel-auto-workflow--classify-source
                 "gptel is a great tool for managing techniques and modules with careful attention to detail and best practices throughout the entire system architecture and design philosophy" 
                 findings) 'aligned))))

(ert-deftest test-daemon/source-classify-deviant-empty ()
  (should (eq (gptel-auto-workflow--classify-source nil "findings") 'deviant)))

(ert-deftest test-daemon/source-classify-deviant-error ()
  (should (eq (gptel-auto-workflow--classify-source "error: timeout" "findings") 'deviant)))

(ert-deftest test-daemon/source-classify-deviant-short ()
  (should (eq (gptel-auto-workflow--classify-source "ab" "findings") 'deviant)))

(ert-deftest test-daemon/source-classify-neutral ()
  (let ((findings "just plain text with nothing special at all really"))
    (should (eq (gptel-auto-workflow--classify-source
                 "something completely different that does not mention any of the techniques or modules or keywords from the findings but is long enough to not be considered deviant by length alone and also this text is now quite a very long string indeed with plenty of padding for good measure"
                 findings) 'neutral))))

;;; Rule evaluation tests

(ert-deftest test-daemon/eval-rule-expr-fallback-number ()
  (should (= (gptel-auto-workflow--eval-rule-expr-fallback 42 nil) 42)))

(ert-deftest test-daemon/eval-rule-expr-fallback-and ()
  (should (gptel-auto-workflow--eval-rule-expr-fallback '(and t t) nil))
  (should-not (gptel-auto-workflow--eval-rule-expr-fallback '(and t nil) nil)))

(ert-deftest test-daemon/eval-rule-expr-fallback-or ()
  (should (gptel-auto-workflow--eval-rule-expr-fallback '(or nil t) nil))
  (should-not (gptel-auto-workflow--eval-rule-expr-fallback '(or nil nil) nil)))

(ert-deftest test-daemon/eval-rule-expr-fallback-not ()
  (should (gptel-auto-workflow--eval-rule-expr-fallback '(not nil) nil))
  (should-not (gptel-auto-workflow--eval-rule-expr-fallback '(not t) nil)))

(ert-deftest test-daemon/eval-rule-expr-fallback-comparison ()
  (should (gptel-auto-workflow--eval-rule-expr-fallback '(> 5 3) nil))
  (should-not (gptel-auto-workflow--eval-rule-expr-fallback '(> 3 5) nil))
  (should (gptel-auto-workflow--eval-rule-expr-fallback '(< 3 5) nil))
  (should (gptel-auto-workflow--eval-rule-expr-fallback '(= 5 5) nil)))

(ert-deftest test-daemon/eval-rule-expr-fallback-arithmetic ()
  (should (= (gptel-auto-workflow--eval-rule-expr-fallback '(+ 1 2 3) nil) 6))
  (should (= (gptel-auto-workflow--eval-rule-expr-fallback '(- 10 3) nil) 7))
  (should (= (gptel-auto-workflow--eval-rule-expr-fallback '(* 3 4) nil) 12))
  (should (= (gptel-auto-workflow--eval-rule-expr-fallback '(/ 12 3) nil) 4)))

(ert-deftest test-daemon/eval-rule-expr-fallback-equal ()
  (should (gptel-auto-workflow--eval-rule-expr-fallback '(equal "a" "a") nil))
  (should-not (gptel-auto-workflow--eval-rule-expr-fallback '(equal "a" "b") nil)))

(ert-deftest test-daemon/eval-rule-expr-fallback-symbol-lookup ()
  (should (= (gptel-auto-workflow--eval-rule-expr-fallback 'x (list (cons 'x 42))) 42)))

;;; Rule expression normalization

(ert-deftest test-daemon/normalize-rule-eq-with-source ()
  (let ((expr (gptel-auto-workflow--normalize-controller-rule-expr
               '(equal source "own-repo"))))
    (should (equal expr '(equal source "own-repo")))))

(ert-deftest test-daemon/normalize-rule-eq-source-reversed ()
  (let ((expr (gptel-auto-workflow--normalize-controller-rule-expr
               '(equal "external" source))))
    (should (equal expr '(equal source "external")))))

;;; Prompt building tests

(ert-deftest test-daemon/build-adaptive-prompt-base-error ()
  (should-error (gptel-auto-workflow--build-adaptive-followup-prompt nil nil nil)))

(ert-deftest test-daemon/build-adaptive-prompt-turn-error ()
  (should-error (gptel-auto-workflow--build-adaptive-followup-prompt "base" nil -1)))

(ert-deftest test-daemon/build-adaptive-prompt-branch-decision ()
  (let ((result (gptel-auto-workflow--build-adaptive-followup-prompt "base prompt" "" 1 'branch)))
    (should (string-match-p "BRANCH" result))))

(ert-deftest test-daemon/build-adaptive-prompt-continue-decision ()
  (let ((result (gptel-auto-workflow--build-adaptive-followup-prompt "base prompt" "" 1 'continue)))
    (should (string-match-p "CONTINUE" result))))

;;; Source literal string tests

(ert-deftest test-daemon/source-literal-string-quoted ()
  (should (equal (gptel-auto-workflow--controller-source-literal-string "value") "value")))

(ert-deftest test-daemon/source-literal-string-escaped ()
  (should (equal (gptel-auto-workflow--controller-source-literal-string "test\\\"value") "test\"value")))

(ert-deftest test-daemon/source-literal-string-symbol ()
  (should (equal (gptel-auto-workflow--controller-source-literal-string 'test-sym) "test-sym")))

;;; Source effectiveness tests

(ert-deftest test-daemon/source-effectiveness-update ()
  (gptel-auto-workflow--update-source-effectiveness "test-source" 'aligned 0.8)
  (let ((stats (gptel-auto-workflow--get-source-effectiveness "test-source")))
    (should (= (plist-get stats :aligned) 1))
    (should (= (plist-get stats :count) 1))))

(ert-deftest test-daemon/source-effectiveness-priority-score-default ()
  (let ((gptel-auto-workflow--source-effectiveness-table (make-hash-table :test 'equal)))
    (should (= (gptel-auto-workflow--source-priority-score "unknown") 0.5))))

;;; Trace recording tests

(ert-deftest test-daemon/record-research-trace ()
  (gptel-auto-workflow--reset-research-ema)
  (setq gptel-auto-workflow--research-trace-log nil)
  (gptel-auto-workflow--record-research-trace 0 '(:decision stop :confidence 0.8 :ema-conf 0.7))
  (should (= (length gptel-auto-workflow--research-trace-log) 1))
  (let ((trace (car gptel-auto-workflow--research-trace-log)))
    (should (eq (plist-get trace :controller-decision) 'stop))))

;;; Controller config signal tests

(ert-deftest test-daemon/controller-config-signals-contain-keys ()
  (let ((sig (gptel-auto-workflow--controller-config-rule-signals
              '(:token-budget 5000 :stop-threshold 0.7))))
    (should (assq 'token-budget sig))
    (should (assq 'stop-threshold sig))
    (should (assq 'beta sig))))

;;; Extension methods (no load errors)

(ert-deftest test-daemon/load-evolved-controller-config ()
  (let ((result (gptel-auto-workflow--load-evolved-controller-config)))
    (if (file-exists-p (gptel-auto-workflow--autotts-file "var/tmp/researcher-controller.json"))
        (should (listp result))
      (should-not result))))

(ert-deftest test-daemon/load-statistical-model-no-config ()
  (should-not (gptel-auto-workflow--load-statistical-model)))

(ert-deftest test-daemon/load-researcher-feedback-no-file ()
  (should-not (gptel-auto-workflow--load-researcher-feedback)))

(ert-deftest test-daemon/active-count-zero-for-empty ()
  (gptel-auto-workflow--branch-pool-init)
  (should (= (gptel-auto-workflow--branch-pool-active-count) 0)))

(ert-deftest test-daemon/branch-pool-add-nil-findings ()
  (gptel-auto-workflow--branch-pool-init)
  (let ((b (gptel-auto-workflow--branch-pool-add nil nil nil)))
    (should b)
    (should (string= (plist-get b :strategy) "default"))
    (should (string= (plist-get b :findings) ""))
    (should (= (plist-get b :tokens) 0))))

(provide 'test-strategic-daemon-functions)
;;; test-strategic-daemon-functions.el ends here
