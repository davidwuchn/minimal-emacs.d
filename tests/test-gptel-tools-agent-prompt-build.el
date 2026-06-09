;;; test-gptel-tools-agent-prompt-build.el --- Tests for skill loading -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OV5 Self-Improving Architecture

;;; Commentary:

;; Regression tests for gptel-auto-workflow--load-skill.
;; Bug: gptel-auto-workflow--load-skill calls gptel-agent-read-file
;; unconditionally, but gptel-agent-read-file may not be loaded in
;; test environments (or when gptel-agent is unavailable).
;; This caused void-function errors in test runs that combined
;; production-metrics + ontology-predict + monitoring-agent tests.
;;
;; The fix: gptel-auto-workflow--load-skill must guard against
;; missing gptel-agent-read-file, returning a safe empty plist.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gptel-tools-agent-prompt-build)
(require 'gptel-tools-agent-benchmark)  ; for gptel-auto-workflow--project-root

(ert-deftest test-load-skill/handles-missing-gptel-agent-read-file ()
  "load-skill should NOT throw void-function when gptel-agent-read-file is unbound.

Reproduces the production-metrics+ontology-predict+monitoring-agent
test isolation bug: when the skill file IS found but gptel-agent
is not loaded, the call to gptel-agent-read-file fails."
  (let ((test-skill-dir (expand-file-name "test-fixtures/fake-skill"
                                          (file-name-directory
                                           (symbol-file 'gptel-auto-workflow--load-skill)))))
    ;; Ensure test dir exists with a fake SKILL.md
    (make-directory test-skill-dir t)
    (with-temp-file (expand-file-name "SKILL.md" test-skill-dir)
      (insert "---\nsystem: test body\n---\n"))
    (unwind-protect
        (progn
          (cl-letf (((symbol-function 'gptel-auto-workflow--find-skill-file)
                     (lambda (name)
                       (expand-file-name (format "%s/SKILL.md" name) test-skill-dir))))
            ;; Unbind gptel-agent-read-file to simulate test env
            (fmakunbound 'gptel-agent-read-file)
            ;; Should not throw void-function error
            (let ((result (gptel-auto-workflow--load-skill "test-skill")))
              (should (listp result))
              (should (stringp (plist-get result :body))))))
      ;; Cleanup
      (delete-directory test-skill-dir t)
      (ignore-errors (require 'gptel-agent nil t)))))

(ert-deftest test-load-skill-content/handles-missing-gptel-agent ()
  "load-skill-content should not throw when load-skill hits missing gptel-agent."
  (let ((test-skill-dir (expand-file-name "test-fixtures/fake-skill2"
                                          (file-name-directory
                                           (symbol-file 'gptel-auto-workflow--load-skill-content)))))
    (make-directory test-skill-dir t)
    (with-temp-file (expand-file-name "SKILL.md" test-skill-dir)
      (insert "---\nsystem: test body\n---\n"))
    (unwind-protect
        (progn
          (cl-letf (((symbol-function 'gptel-auto-workflow--find-skill-file)
                     (lambda (name)
                       (expand-file-name (format "%s/SKILL.md" name) test-skill-dir))))
            (fmakunbound 'gptel-agent-read-file)
            ;; Should not throw
            (let ((result (gptel-auto-workflow--load-skill-content "test-skill")))
              (should (stringp result)))))
      (delete-directory test-skill-dir t)
      (ignore-errors (require 'gptel-agent nil t)))))

(ert-deftest test-load-skill-content/handles-skill-not-found ()
  "load-skill-content should return empty string when skill file doesn't exist."
  (let ((result (gptel-auto-workflow--load-skill-content "definitely-not-a-real-skill-xyzzy")))
    (should (stringp result))
    (should (equal result ""))))

(ert-deftest test-load-skill-metadata/handles-missing-gptel-agent ()
  "load-skill-metadata should return nil when gptel-agent-read-file is unbound."
  (unwind-protect
      (progn
        (fmakunbound 'gptel-agent-read-file)
        (let ((result (gptel-auto-workflow--load-skill-metadata "test-skill")))
          (should (null result))))
    (ignore-errors (require 'gptel-agent nil t))))

(provide 'test-gptel-tools-agent-prompt-build)
;;; test-gptel-tools-agent-prompt-build.el ends here
