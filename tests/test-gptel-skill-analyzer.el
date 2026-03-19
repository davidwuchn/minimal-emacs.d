;;; test-gptel-skill-analyzer.el --- Tests for GPTel Skill Analyzer -*- lexical-binding: t -*-

;;; Commentary:

;; Tests for gptel-skill-analyzer.el

;;; Code:

(require 'ert)
(require 'gptel-skill-analyzer)

(ert-deftest test-gptel-skill-is-flaky-test ()
  "Test flaky test detection."
  (let ((test-data '((( :test-id . "flaky-test")
                      (:grade (:passed . t)))
                     (( :test-id . "flaky-test")
                      (:grade (:passed . nil)))
                     (( :test-id . "stable-test")
                      (:grade (:passed . t)))
                     (( :test-id . "stable-test")
                      (:grade (:passed . t))))))
    (let ((test-file (make-temp-file "analyzer" nil ".json")))
      (unwind-protect
          (progn
            (gptel-skill-write-json test-data test-file)
            (should (gptel-skill-is-flaky-test "flaky-test" test-file))
            (should-not (gptel-skill-is-flaky-test "stable-test" test-file)))
        (delete-file test-file)))))

(ert-deftest test-gptel-skill-is-non-discriminating-test ()
  "Test non-discriminating test detection."
  (let ((test-data '((( :test-id . "all-pass")
                      (:grade (:passed . t)))
                     (( :test-id . "all-pass")
                      (:grade (:passed . t)))
                     (( :test-id . "all-fail")
                      (:grade (:passed . nil)))
                     (( :test-id . "all-fail")
                      (:grade (:passed . nil))))))
    (let ((test-file (make-temp-file "analyzer" nil ".json")))
      (unwind-protect
          (progn
            (gptel-skill-write-json test-data test-file)
            (should (gptel-skill-is-non-discriminating-test "all-pass" test-file))
            (should (gptel-skill-is-non-discriminating-test "all-fail" test-file)))
        (delete-file test-file)))))

(ert-deftest test-gptel-skill-is-systematic-failure ()
  "Test systematic failure detection."
  (let ((test-data '((( :test-id . "systematic-fail")
                      (:grade (:passed . nil)))
                     (( :test-id . "systematic-fail")
                      (:grade (:passed . nil)))
                     (( :test-id . "systematic-fail")
                      (:grade (:passed . nil)))
                     (( :test-id . "systematic-fail")
                      (:grade (:passed . nil)))
                     (( :test-id . "systematic-fail")
                      (:grade (:passed . t))))))
    (let ((test-file (make-temp-file "analyzer" nil ".json")))
      (unwind-protect
          (progn
            (gptel-skill-write-json test-data test-file)
            (should (gptel-skill-is-systematic-failure "systematic-fail" test-file)))
        (delete-file test-file)))))

(ert-deftest test-gptel-skill-generate-summary ()
  "Test summary generation."
  (let ((test-data '((( :test-id . "test-1")
                      (:grade (:score . 8) (:total . 10) (:percentage . 80.0)))
                     (( :test-id . "test-2")
                      (:grade (:score . 9) (:total . 10) (:percentage . 90.0))))))
    (let ((summary (gptel-skill-generate-summary test-data)))
      (should (equal (plist-get summary :total-tests) 2))
      (should (equal (plist-get summary :average-score) 85.0)))))

(provide 'test-gptel-skill-analyzer)

;;; test-gptel-skill-analyzer.el ends here
