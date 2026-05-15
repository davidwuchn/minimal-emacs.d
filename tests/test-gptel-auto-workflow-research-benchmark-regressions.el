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

(ert-deftest regression/research-benchmark/controller-design-validates-held-out-rules ()
  "Controller design should bind held-out validation results before reading them."
  (let ((traces (list '(:output-length 1000 :confidence 0.8 :ema-conf 0.8 :ema-delta 0.1
                        :turn-count 1 :source "own-repo" :success-p t)
                      '(:output-length 300 :confidence 0.2 :ema-conf 0.2 :ema-delta -0.1
                        :turn-count 1 :source "external" :success-p nil)
                      '(:output-length 900 :confidence 0.7 :ema-conf 0.7 :ema-delta 0.0
                        :turn-count 1 :source "own-repo" :success-p t)
                      '(:output-length 250 :confidence 0.1 :ema-conf 0.1 :ema-delta -0.2
                        :turn-count 1 :source "external" :success-p nil))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--load-research-traces)
               (lambda () traces))
              ((symbol-function 'gptel-auto-workflow--load-autotts-controller)
               (lambda () '(:min-confidence-stop 0.7 :branch-threshold 0.3)))
              ((symbol-function 'gptel-auto-workflow--call-controller-design-subagent)
               (lambda (_prompt)
                 '((:when (> ema-conf 0.7) :then stop)
                   (:when (< ema-conf 0.3) :then branch)
                   (:when t :then continue))))
              ((symbol-function 'gptel-auto-workflow--save-evolved-controller)
               (lambda (_controller) t))
              ((symbol-function 'gptel-auto-workflow--update-skill-with-controller)
               (lambda (_controller) t)))
      (let ((result (gptel-auto-workflow--run-controller-design-agent 1)))
        (should (plist-get result :best-controller))
        (should (numberp (plist-get result :best-objective)))))))

(ert-deftest regression/research-benchmark/controller-rules-validate-config-signals ()
  "Generated rules should validate when they reference controller config signals."
  (should
   (gptel-auto-workflow--validate-controller-rules
    '((:when (and (> own-repo-priority external-priority)
                  (< turn max-turns)
                  (>= min-confidence-stop stop-threshold)
                  (> token-budget 1000))
       :then continue))
    '(:own-repo-priority 0.85
      :external-priority 0.15
      :stop-threshold 0.65
      :min-confidence-stop 0.7
      :token-budget 8000
      :max-turns 4))))

(ert-deftest regression/research-benchmark/controller-rules-evaluate-config-signals ()
  "Offline rule evaluation should expose the same controller config signals."
  (let ((result (gptel-auto-workflow--evaluate-controller-rules
                 '((:when (> own-repo-priority external-priority) :then stop)
                   (:when t :then continue))
                 (list '(:output-length 1200
                         :confidence 0.8
                         :ema-conf 0.8
                         :ema-delta 0.1
                         :turn-count 1
                         :source "own-repo"
                         :success-p t))
                 '(:own-repo-priority 0.9
                   :external-priority 0.1
                   :token-budget 8000))))
    (should (= (plist-get result :correct) 1))
    (should (= (plist-get result :total) 1))))

(ert-deftest regression/research-benchmark/controller-rules-normalize-generated-aliases ()
  "Generated rules should accept prompt aliases and source comparisons."
  (let ((rules '((:when (and own-priority ext-priority (< ema-conf 0.55))
                  :then continue)
                 (:when (and (= source 'external) (< ema-conf 0.45))
                  :then branch)
                 (:when (and (= source "own-repo") (> ema-conf 0.55))
                  :then stop))))
    (should
     (gptel-auto-workflow--validate-controller-rules
      rules
      '(:own-repo-priority 0.85
        :external-priority 0.15
        :token-budget 8000)))
    (should
     (equal (plist-get (cadr (gptel-auto-workflow--normalize-controller-rules rules))
                       :when)
            '(and (equal source "external") (< ema-conf 0.45))))))

(ert-deftest regression/research-benchmark/controller-rules-evaluate-source-equality ()
  "Offline rule evaluation should not reject numeric source equality variants."
  (let ((result (gptel-auto-workflow--evaluate-controller-rules
                 '((:when (and (= source 'external) (< ema-conf 0.45)) :then branch)
                   (:when t :then continue))
                 (list '(:output-length 1200
                         :confidence 0.3
                         :ema-conf 0.3
                         :ema-delta -0.1
                         :turn-count 1
                         :source "external"
                         :outcomes ((:kept :json-false))
                         :success-p nil))
                 '(:external-priority 0.15
                   :token-budget 8000))))
    (should (= (plist-get result :correct) 1))
    (should (= (plist-get result :total) 1))))

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

(ert-deftest regression/research-benchmark/source-merge-writes-one-sources-key ()
  "Trace source synthesis should not duplicate string and keyword JSON keys."
  (let* ((root (make-temp-file "aw-research-benchmark" t))
         (data-dir (expand-file-name "assistant/skills/researcher-prompt/data" root))
         (source-file (expand-file-name "source-effectiveness.json" data-dir))
         (source-perf (make-hash-table :test 'equal)))
    (unwind-protect
        (progn
          (make-directory data-dir t)
          (with-temp-file source-file
            (insert "{\"version\":\"old\",\"sources\":{\"own-repo\":{\"experiments_kept\":1,\"experiments_enabled\":1}}}"))
          (puthash "external" (list 1 2) source-perf)
          (gptel-auto-workflow--merge-trace-sources-into-data source-perf data-dir)
          (with-temp-buffer
            (insert-file-contents source-file)
            (let ((content (buffer-string))
                  (count 0)
                  (start 0))
              (while (string-match "\"sources\"" content start)
                (setq count (1+ count))
                (setq start (match-end 0)))
              (should (= count 1)))))
      (delete-directory root t))))

(provide 'test-gptel-auto-workflow-research-benchmark-regressions)

;;; test-gptel-auto-workflow-research-benchmark-regressions.el ends here
