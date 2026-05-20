;;; test-per-axis-controller-regressions.el --- Per-axis AutoTTS controller TDD -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for the per-axis AutoTTS controller guidance: loading and saving
;; axis-specific strategy-guidance-{AXIS}.json files with fallback to
;; global strategy-guidance.json.
;;
;; Run:
;;   emacs --batch -L tests -L lisp/modules \
;;         -l test-per-axis-controller-regressions.el \
;;         -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gptel-auto-workflow-strategic)
(require 'gptel-auto-workflow-research-benchmark)

;; ─── Loading axis-specific guidance (TDD tests) ───

(ert-deftest test-per-axis/load-global-no-axis ()
  "Without axis, load strategy-guidance.json."
  (let* ((tmpdir (make-temp-file "tdd-pa-" t))
         (file (expand-file-name "assistant/skills/researcher-prompt/data/strategy-guidance.json" tmpdir)))
    (make-directory (file-name-directory file) t)
    (with-temp-file file (insert "{\"beta\":0.5,\"own-priority\":80}"))
    (let ((gptel-auto-workflow--project-root-override tmpdir))
      (let ((r (gptel-auto-workflow--load-strategy-guidance-json)))
        (should (= (plist-get r :beta) 0.5))
        (should (= (plist-get r :own-priority) 80))))))

(ert-deftest test-per-axis/load-axis-specific ()
  "With axis :K, load strategy-guidance-K.json."
  (let* ((tmpdir (make-temp-file "tdd-pa-" t))
         (file (expand-file-name "assistant/skills/researcher-prompt/data/strategy-guidance-K.json" tmpdir)))
    (make-directory (file-name-directory file) t)
    (with-temp-file file (insert "{\"beta\":0.75,\"own-priority\":60}"))
    (let ((gptel-auto-workflow--project-root-override tmpdir)
          (gptel-auto-workflow--current-experiment-axis :K))
      (let ((r (gptel-auto-workflow--load-strategy-guidance-json)))
        (should (= (plist-get r :beta) 0.75))
        (should (= (plist-get r :own-priority) 60))))))

(ert-deftest test-per-axis/load-axis-fallback ()
  "With axis :K but no axis file, fall back to global."
  (let* ((tmpdir (make-temp-file "tdd-pa-" t))
         (file (expand-file-name "assistant/skills/researcher-prompt/data/strategy-guidance.json" tmpdir)))
    (make-directory (file-name-directory file) t)
    (with-temp-file file (insert "{\"beta\":0.5,\"own-priority\":80}"))
    (let ((gptel-auto-workflow--project-root-override tmpdir)
          (gptel-auto-workflow--current-experiment-axis :K))
      (let ((r (gptel-auto-workflow--load-strategy-guidance-json)))
        (should (= (plist-get r :beta) 0.5))
        (should (= (plist-get r :own-priority) 80))))))

(ert-deftest test-per-axis/load-no-file ()
  "Without any file, return nil."
  (let* ((tmpdir (make-temp-file "tdd-pa-" t)))
    (let ((gptel-auto-workflow--project-root-override tmpdir))
      (should (null (gptel-auto-workflow--load-strategy-guidance-json))))))

(ert-deftest test-per-axis/load-malformed ()
  "Malformed JSON returns nil."
  (let* ((tmpdir (make-temp-file "tdd-pa-" t))
         (file (expand-file-name "assistant/skills/researcher-prompt/data/strategy-guidance.json" tmpdir)))
    (make-directory (file-name-directory file) t)
    (with-temp-file file (insert "not valid {{"))
    (let ((gptel-auto-workflow--project-root-override tmpdir))
      (should (null (gptel-auto-workflow--load-strategy-guidance-json))))))

;; ─── Saving axis-specific guidance ───

(ert-deftest test-per-axis/save-global-no-axis ()
  "Without axis, save to strategy-guidance.json."
  (let* ((tmpdir (make-temp-file "tdd-pa-" t))
         (data-dir (expand-file-name "assistant/skills/researcher-prompt/data" tmpdir))
         (global (expand-file-name "strategy-guidance.json" data-dir))
         (c '(:own-repo-priority 0.8 :external-priority 0.15 :beta 0.5)))
    (make-directory data-dir t)
    (cl-letf (((symbol-function 'gptel-auto-workflow--worktree-base-root)
               (lambda () tmpdir)))
      (gptel-auto-workflow--update-skill-with-controller c)
      (should (file-exists-p global))
      (should-not (file-exists-p (expand-file-name "strategy-guidance-K.json" data-dir))))))

(ert-deftest test-per-axis/save-axis-specific ()
  "With axis :K, save to strategy-guidance-K.json."
  (let* ((tmpdir (make-temp-file "tdd-pa-" t))
         (data-dir (expand-file-name "assistant/skills/researcher-prompt/data" tmpdir))
         (axis (expand-file-name "strategy-guidance-K.json" data-dir))
         (global (expand-file-name "strategy-guidance.json" data-dir))
         (c '(:own-repo-priority 0.8 :external-priority 0.15 :beta 0.5)))
    (make-directory data-dir t)
    (cl-letf (((symbol-function 'gptel-auto-workflow--worktree-base-root)
               (lambda () tmpdir)))
      (let ((gptel-auto-workflow--current-experiment-axis :K))
        (gptel-auto-workflow--update-skill-with-controller c)
        (should (file-exists-p axis))
        (should-not (file-exists-p global))))))

(ert-deftest test-per-axis/save-axis-json ()
  "Axis file content is valid JSON with expected keys."
  (let* ((tmpdir (make-temp-file "tdd-pa-" t))
         (data-dir (expand-file-name "assistant/skills/researcher-prompt/data" tmpdir))
         (axis (expand-file-name "strategy-guidance-K.json" data-dir))
         (c '(:own-repo-priority 0.8 :external-priority 0.15 :beta 0.5)))
    (make-directory data-dir t)
    (cl-letf (((symbol-function 'gptel-auto-workflow--worktree-base-root)
               (lambda () tmpdir)))
      (let ((gptel-auto-workflow--current-experiment-axis :K))
        (gptel-auto-workflow--update-skill-with-controller c)
        (let ((d (with-temp-buffer
                   (insert-file-contents axis)
                   (let ((json-object-type 'plist) (json-key-type 'keyword)) (json-read)))))
          (should (numberp (plist-get d :beta)))
          (should (numberp (plist-get d :own-priority)))
          (should (numberp (plist-get d :ext-priority))))))))

(provide 'test-per-axis-controller-regressions)
;;; test-per-axis-controller-regressions.el ends here
