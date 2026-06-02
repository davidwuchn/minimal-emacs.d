;;; test-standalone-research.el --- Regressions for standalone research -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)

(load-file (expand-file-name "../lisp/modules/standalone-research.el"
                            (file-name-directory
                             (or load-file-name buffer-file-name default-directory))))

(ert-deftest regression/standalone-research/falls-back-when-multiturn-returns-empty ()
  "Empty multi-turn output should not overwrite findings with a header-only file."
  (let ((fallback-prompt nil)
        (callback-findings nil)
        (saved nil))
    (cl-letf (((symbol-function 'gptel-auto-workflow--research-patterns)
               (lambda (callback &optional _retry-count)
                 (funcall callback "")))
              ((symbol-function 'slr--build-prompt)
               (lambda () "fallback prompt"))
              ((symbol-function 'slr--run-single-turn)
               (lambda (prompt callback)
                 (setq fallback-prompt prompt)
                 (when (functionp callback)
                   (funcall callback "fallback findings"))))
              ((symbol-function 'slr--save-findings)
               (lambda (findings &optional _file-path)
                 (push findings saved))))
      (slr-run-research (lambda (findings)
                          (setq callback-findings findings)))
      (should (equal fallback-prompt "fallback prompt"))
      (should (equal callback-findings "fallback findings"))
      (should-not saved))))

(ert-deftest regression/standalone-research/build-prompt-survives-substitution-error ()
  "Standalone research should use raw prompt if strategic substitution is corrupt."
  (cl-letf (((symbol-function 'slr--load-skill)
             (lambda (_skill-name) "raw researcher prompt"))
            ((symbol-function 'gptel-auto-workflow--substitute-researcher-variables)
             (lambda (_prompt) (error "maphash corruption"))))
    (should (equal (slr--build-prompt) "raw researcher prompt"))))

(ert-deftest regression/standalone-research/single-turn-empty-result-uses-local-fallback ()
  "Async empty single-turn output should fall back to local findings."
  (let ((saved nil)
         (recorded nil)
         (callback-findings nil)
         (defects nil))
    (cl-letf (((symbol-function 'gptel-benchmark-call-subagent)
                (lambda (_type _description _prompt callback &optional _timeout)
                 (funcall callback "")))
              ((symbol-function 'run-with-timer)
               (lambda (_secs _repeat function &rest args)
                 (apply function args)
                 'test-timer))
              ((symbol-function 'slr--record-research-defect)
               (lambda (reason details)
                 (push (list reason details) defects)
                 (list reason details "recorded")))
              ((symbol-function 'slr--local-fallback-findings)
               (lambda (_reason _details)
                 (concat "## Local Research Fallback\n\n"
                         (make-string 200 ?x))))
              ((symbol-function 'slr--record-context)
               (lambda (_prompt findings)
                 (setq recorded findings)))
              ((symbol-function 'slr--save-findings)
               (lambda (findings &optional _file-path)
                 (setq saved findings))))
      (slr--run-single-turn "research prompt"
                            (lambda (findings)
                              (setq callback-findings findings)))
      (sleep-for 0.5)
      (should (slr--usable-findings-p saved))
      (should (equal saved recorded))
      (should (equal saved callback-findings))
      (should (string-match-p "Local Research Fallback" saved))
      (should (equal (length defects) 1))
      (should (eq (caar defects) 'empty-response)))))

(provide 'test-standalone-research)

;;; test-standalone-research.el ends here
