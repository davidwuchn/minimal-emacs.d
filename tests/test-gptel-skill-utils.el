;;; test-gptel-skill-utils.el --- Tests for GPTel Skill Utilities -*- lexical-binding: t -*-

;;; Commentary:

;; Tests for gptel-skill-utils.el

;;; Code:

(require 'ert)
(require 'gptel-skill-utils)

(ert-deftest test-gptel-skill-read-json ()
  "Test reading JSON file."
  (let ((test-file (make-temp-file "skill-test" nil ".json" "{\"key\": \"value\"}")))
    (unwind-protect
        (let ((data (gptel-skill-read-json test-file)))
          (should (equal (cdr (assq 'key data)) "value")))
      (delete-file test-file))))

(ert-deftest test-gptel-skill-write-json ()
  "Test writing JSON file."
  (let ((test-file (make-temp-file "skill-test" nil ".json")))
    (unwind-protect
        (let ((data '((:key . "value") (:number . 42))))
          (gptel-skill-write-json data test-file)
          (should (file-exists-p test-file))
          (let ((read-back (gptel-skill-read-json test-file)))
            (should (equal (cdr (assq 'key read-back)) "value"))
            (should (equal (cdr (assq 'number read-back)) 42))))
      (delete-file test-file))))

(provide 'test-gptel-skill-utils)

;;; test-gptel-skill-utils.el ends here
