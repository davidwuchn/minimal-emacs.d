;;; test-gptel-skill-benchmark.el --- Tests for GPTel Skill Benchmark Engine -*- lexical-binding: t -*-

;;; Commentary:

;; Tests for gptel-skill-benchmark.el

;;; Code:

(require 'ert)
(require 'gptel-benchmark-core)
(require 'gptel-skill-benchmark)

;;; Test Loading

(ert-deftest test-gptel-skill-load-tests ()
  "Test loading test definitions from JSON."
  :tags '(:expensive)
  (let ((tests (gptel-skill-load-tests "planning")))
    (skip-unless (> (length tests) 0))
    (should (listp tests))
    (let ((first-test (car tests)))
      (should (plist-get first-test :id))
      (should (plist-get first-test :prompt)))))

(ert-deftest test-gptel-skill-normalize-test ()
  "Test normalizing test alist to plist."
  (let* ((test-alist '((id . "test-001")
                       (name . "test-name")
                       (prompt . "Test prompt")
                       (expected_behaviors . ["behavior1" "behavior2"])
                       (forbidden_behaviors . ["bad1"])))
         (plist (gptel-skill--normalize-test test-alist)))
    (should (equal (plist-get plist :id) "test-001"))
    (should (equal (plist-get plist :name) "test-name"))
    (should (equal (plist-get plist :prompt) "Test prompt"))))

;;; Summary

(ert-deftest test-gptel-skill-benchmark-summary ()
  "Test generating benchmark summary."
  (let ((test-file (gptel-benchmark-make-temp-file "benchmark" nil ".json")))
    (unwind-protect
        (progn
          (gptel-benchmark-write-json
           (list (list :test-id "test-1"
                       :grade (list :score 8 :total 10 :percentage 80.0))
                 (list :test-id "test-2"
                       :grade (list :score 10 :total 10 :percentage 100.0)))
           test-file)
          (let ((summary (gptel-skill-benchmark-summary test-file)))
            (should (equal (plist-get summary :total-tests) 2))
            (should (equal (plist-get summary :passed-tests) 1))
            (should (> (plist-get summary :overall-score) 80))))
      (delete-file test-file))))

(ert-deftest test-gptel-skill-benchmark-summary-empty ()
  "Test summary with empty results."
  (let ((test-file (gptel-benchmark-make-temp-file "benchmark" nil ".json")))
    (unwind-protect
        (progn
          (gptel-benchmark-write-json nil test-file)
          (let ((summary (gptel-skill-benchmark-summary test-file)))
            (should (equal (plist-get summary :total-tests) 0))
            (should (equal (plist-get summary :overall-score) 0))))
      (delete-file test-file))))

;;; Assertion Checking (Legacy)

(ert-deftest test-gptel-skill-check-assertion ()
  "Test legacy assertion checking."
  (should (gptel-skill-check-assertion "Hello World" "Hello"))
  (should (gptel-skill-check-assertion "Hello World" "World"))
  (should-not (gptel-skill-check-assertion "Hello World" "Goodbye")))

;;; Grade Response Parsing

(ert-deftest test-gptel-skill-parse-grade-response ()
  "Test parsing LLM grade response."
  (let ((response "EXPECTED:\n1. behavior1: PASS - found it\nFORBIDDEN:\n1. bad1: PASS - not present\nSUMMARY: SCORE: 2/2"))
    (let ((grade (gptel-skill--parse-grade-response response)))
      (should (equal (plist-get grade :score) 2))
      (should (equal (plist-get grade :total) 2))
      (should (equal (plist-get grade :percentage) 100.0))
      (should (plist-get grade :passed)))))

(ert-deftest test-gptel-skill-parse-grade-response-partial ()
  "Test parsing partial grade response."
  (let ((response "SUMMARY: SCORE: 1/3"))
    (let ((grade (gptel-skill--parse-grade-response response)))
      (should (equal (plist-get grade :score) 1))
      (should (equal (plist-get grade :total) 3))
      (should (< (plist-get grade :percentage) 50)))))

;;; Average Score

(ert-deftest test-gptel-skill-average-score ()
  "Test calculating average score."
  (let ((results (list (list :grade (list :percentage 80.0))
                       (list :grade (list :percentage 100.0))
                       (list :grade (list :percentage 60.0)))))
    (let ((avg (gptel-skill--average-score results)))
      (should (equal avg 80.0)))))

;;; Grading Prompt

(ert-deftest test-gptel-skill-make-grading-prompt ()
  "Test grading prompt generation."
  (let ((prompt (gptel-skill--make-grading-prompt
                 "test output"
                 '("expected1" "expected2")
                 '("forbidden1"))))
    (should (stringp prompt))
    (should (string-match-p "expected1" prompt))
    (should (string-match-p "forbidden1" prompt))
    (should (string-match-p "SCORE:" prompt))))

;;; Provide

(provide 'test-gptel-skill-benchmark)

;;; test-gptel-skill-benchmark.el ends here