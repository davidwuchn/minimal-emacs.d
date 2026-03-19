;;; test-gptel-skill-improve.el --- Tests for GPTel Skill Improvement Workflow -*- lexical-binding: t -*-

;;; Commentary:

;; Tests for gptel-skill-improve.el

;;; Code:

(require 'ert)
(require 'gptel-skill-improve)

(ert-deftest test-gptel-skill-identify-failures ()
  "Test identifying failures from benchmark results."
  (let ((benchmark-results '((( :test-id . "test-1")
                              (:grade (:score . 10) (:total . 10)))
                             (( :test-id . "test-2")
                              (:grade (:score . 7) (:total . 10)))
                             (( :test-id . "test-3")
                              (:grade (:score . 5) (:total . 10))))))
    (let ((failures (gptel-skill-identify-failures benchmark-results)))
      (should (equal (length failures) 2))
      (should (equal (plist-get (car failures) :test-id) "test-3"))
      (should (equal (plist-get (cadr failures) :test-id) "test-2")))))

(ert-deftest test-gptel-skill-create-fix-proposal ()
  "Test creating fix proposal."
  (let ((proposal (gptel-skill-create-fix-proposal "test-skill" "test-1" "Test failed")))
    (should (equal (plist-get proposal :type) "prompt-update"))
    (should (plist-get proposal :content))
    (should (equal (plist-get proposal :test-id) "test-1"))
    (should (equal (plist-get proposal :issue) "Test failed"))))

(ert-deftest test-gptel-skill-is-valid-fix ()
  "Test validating fix proposals."
  (should (gptel-skill-is-valid-fix '(:content . "Valid fix content")))
  (should-not (gptel-skill-is-valid-fix '(:content . "")))
  (should-not (gptel-skill-is-valid-fix '())))

(ert-deftest test-gptel-skill-generate-fixes ()
  "Test generating fixes from failures."
  (let ((failures '((( :test-id . "test-1")
                     (:issue . "Failed assertion"))
                    (( :test-id . "test-2")
                     (:issue . "Timeout error")))))
    (let ((fixes (gptel-skill-generate-fixes "test-skill" failures)))
      (should (equal (length fixes) 2))
      (dolist (fix fixes)
        (should (plist-get fix :type))
        (should (plist-get fix :content))))))

(provide 'test-gptel-skill-improve)

;;; test-gptel-skill-improve.el ends here
