;;; test-gptel-benchmark-core.el --- Benchmark core regressions -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'gptel-benchmark-core)

(ert-deftest benchmark-core/summarize-results/accepts-keyword-alist-scores ()
  "Benchmark summaries should accept keyword-keyed score alists."
  (let ((summary (gptel-benchmark-summarize-results
                  '((run . ((:overall-score . 0.8)
                            (:efficiency-score . 0.7)
                            (:completion-score . 0.9)
                            (:constraint-score . 1.0)))))))
    (should (equal (plist-get summary :total-tests) 1))
    (should (equal (plist-get summary :passed-tests) 1))
    (should (= (plist-get summary :avg-overall) 0.8))))

(provide 'test-gptel-benchmark-core)

;;; test-gptel-benchmark-core.el ends here
