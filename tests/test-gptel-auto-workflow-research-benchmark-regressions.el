;;; test-gptel-auto-workflow-research-benchmark-regressions.el --- Research benchmark regressions -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)

(load-file (expand-file-name "../lisp/modules/gptel-auto-workflow-research-benchmark.el"
                            (file-name-directory
                             (or load-file-name buffer-file-name default-directory))))

(ert-deftest regression/research-benchmark/controller-design-parses-parenthesized-plist ()
  "Controller agent should accept the exact plist format requested in its prompt."
  (should
   (equal
    (gptel-auto-workflow--parse-controller-design-response
     "(:own-repo-priority 0.85 :external-priority 0.15 :min-confidence-stop 0.72)")
    '(:own-repo-priority 0.85 :external-priority 0.15 :min-confidence-stop 0.72))))

(ert-deftest regression/research-benchmark/controller-design-parses-wrapped-code-fence ()
  "Controller agent should accept analyzer wrappers around a fenced plist."
  (should
   (equal
    (gptel-auto-workflow--parse-controller-design-response
      "Analyzer result for task: Controller Design\n\n```elisp\n(:own-repo-priority 0.88 :external-priority 0.12 :min-confidence-stop 0.72)\n```")
     '(:own-repo-priority 0.88 :external-priority 0.12 :min-confidence-stop 0.72))))

(ert-deftest regression/research-benchmark/controller-design-parses-rule-list ()
  "Controller agent should accept rule-list responses."
  (should
   (equal
    (gptel-auto-workflow--parse-controller-design-rules
     "((:when (> ema-conf 0.7) :then stop) (:when (< ema-conf 0.3) :then branch))")
    '((:when (> ema-conf 0.7) :then stop)
      (:when (< ema-conf 0.3) :then branch)))))

(ert-deftest regression/research-benchmark/controller-design-uses-sync-subagent-result ()
  "Controller design should consume the subagent's returned rule list."
  (cl-letf (((symbol-function 'gptel-benchmark-call-subagent-sync)
              (lambda (&rest _)
                "((:when (> ema-conf 0.7) :then stop))")))
    (should
      (equal (gptel-auto-workflow--call-controller-design-subagent "prompt")
             '((:when (> ema-conf 0.7) :then stop))))))

(ert-deftest regression/research-benchmark/controller-design-async-fallback-is-bounded ()
  "Controller design should not wait forever when async subagent never calls back."
  (let ((times '(0 121))
        (sat nil))
    (cl-letf (((symbol-function 'gptel-benchmark-call-subagent)
               (lambda (&rest _args) nil))
              ((symbol-function 'float-time)
               (lambda ()
                 (prog1 (or (pop times) 121)
                   nil)))
              ((symbol-function 'sit-for)
               (lambda (&rest _args)
                 (setq sat t))))
      (should-not (gptel-auto-workflow--call-controller-design-subagent "prompt"))
      (should-not sat))))

(ert-deftest regression/research-benchmark/controller-design-low-trace-count-returns-nil ()
  "Low trace counts should return nil without invalid `cl-return-from'."
  (cl-letf (((symbol-function 'gptel-auto-workflow--load-research-traces)
             (lambda () nil)))
    (should-not (gptel-auto-workflow--run-controller-design-agent 1))))

(ert-deftest regression/research-benchmark/held-out-validation-does-not-require-training-results ()
  "Held-out validation should not call undefined training-result helpers."
  (let ((result (gptel-auto-workflow--validate-on-held-out
                  '(:min-confidence-stop 0.7)
                  (list '(:output-length 2500 :has-urls t :source "external")
                        '(:output-length 400 :has-urls nil :source "own-repo")))))
    (should (= (plist-get result :test-count) 2))
    (should (numberp (plist-get result :overfit-score)))))

(ert-deftest regression/research-benchmark/trace-analysis-tolerates-missing-source ()
  "Older traces may omit source metadata in controller analysis paths."
  (let ((trace '(:output-length 500
                 :tokens-used 100
                 :confidence 0.2
                 :ema-conf 0.2
                 :ema-delta 0.0
                 :turn-count 1
                 :outcomes ((:kept :json-false)))))
    (should (numberp (plist-get (gptel-auto-workflow--validate-on-held-out
                                 '(:min-confidence-stop 0.7)
                                 (list trace))
                                :overfit-score)))
    (should (plist-get (gptel-auto-workflow--evolve-controller-heuristic (list trace))
                       :external-stats))
    (should (numberp (gptel-auto-workflow--calculate-evolution-objective
                      (list trace)
                      '(:own-repo-priority 0.7 :external-priority 0.15))))
    (should (stringp (gptel-auto-workflow--summarize-traces-for-prompt (list trace))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--load-research-traces)
               (lambda () (list trace))))
      (should (consp (gptel-auto-workflow--offline-benchmark-strategies))))))

(ert-deftest regression/research-benchmark/strategy-text-tolerates-unnamed-phases ()
  "Generated strategy JSON may contain phases without names."
  (let* ((root (make-temp-file "aw-research-benchmark" t))
         (strategy-dir (expand-file-name "assistant/skills/researcher-prompt/strategies" root))
         (strategy-file (expand-file-name "generated.json" strategy-dir)))
    (unwind-protect
        (progn
          (make-directory strategy-dir t)
          (with-temp-file strategy-file
            (insert "{\"name\":\"generated\",\"description\":\"Test strategy\",\"phases\":[{\"query\":\"repo\"},{\"name\":\"fetch\"}]}") )
          (cl-letf (((symbol-function 'gptel-auto-workflow--worktree-base-root)
                     (lambda () root)))
            (let ((text (gptel-auto-workflow--load-strategy-as-text "generated")))
              (should (string-match-p "\\*\\*Strategy\\*\\*: generated" text))
              (should (string-match-p "fetch" text)))))
      (delete-directory root t))))

(ert-deftest regression/research-benchmark/synthesis-tolerates-missing-trace-metadata ()
  "Older traces may omit strategy or source metadata."
  (let* ((root (make-temp-file "aw-research-benchmark" t))
         (data-dir (expand-file-name "assistant/skills/researcher-prompt/data" root)))
    (unwind-protect
        (cl-letf (((symbol-function 'gptel-auto-workflow--worktree-base-root)
                   (lambda () root)))
          (gptel-auto-workflow--synthesize-research-knowledge-from-traces
           (list '(:confidence 0.2
                   :ema-conf 0.1
                   :ema-delta 0.0
                   :output-length 200
                   :outcomes ((:kept :json-false)))))
          (should (file-exists-p (expand-file-name "topic-performance.json" data-dir)))
          (should (file-exists-p (expand-file-name "source-effectiveness.json" data-dir))))
      (delete-directory root t))))

(provide 'test-gptel-auto-workflow-research-benchmark-regressions)

;;; test-gptel-auto-workflow-research-benchmark-regressions.el ends here
