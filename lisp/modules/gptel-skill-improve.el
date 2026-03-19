;;; gptel-skill-improve.el --- GPTel Skill Improvement Workflow -*- lexical-binding: t -*-

;; Copyright (C) 2024 David Wu

;; Author: David Wu <davidwu@example.com>
;; Keywords: ai, improvement, optimization

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Implements workflow for improving GPTel skills based on benchmark results.

;;; Code:

(require 'json)
(require 'cl-lib)
(require 'gptel-skill-benchmark)
(require 'gptel-skill-utils)

(defun gptel-skill-improve (skill-name &optional _target-tests)
  "Improve SKILL-NAME based on benchmark results.
Optional TARGET-TESTS parameter is reserved for future selective targeting."
  (let* ((benchmark-file (format "./benchmarks/%s-benchmark.json" skill-name))
         (benchmark-results (gptel-skill-read-json benchmark-file))
         (failures (gptel-skill-identify-failures benchmark-results))
         (fix-proposals (gptel-skill-generate-fixes skill-name failures)))
    (let ((reviewed-fixes (gptel-skill-review-fixes skill-name fix-proposals)))
      (gptel-skill-apply-fixes skill-name reviewed-fixes)
      (gptel-skill-verify-improvement skill-name benchmark-results))))

(defun gptel-skill-generate-fixes (skill failures)
  "Generate potential fixes for SKILL based on FAILURES."
  (let ((fix-proposals '()))
    (dolist (failure failures)
      (let* ((test-id (plist-get failure :test-id))
             (issue (plist-get failure :issue))
             (proposal (gptel-skill-create-fix-proposal skill test-id issue)))
        (push proposal fix-proposals)))
    fix-proposals))

(defun gptel-skill-review-fixes (_skill fix-proposals)
  "Review FIX-PROPOSALS for SKILL and return approved ones.
Note: SKILL parameter reserved for future context-aware review."
  (let ((approved-fixes '()))
    (dolist (proposal fix-proposals)
      (when (gptel-skill-is-valid-fix proposal)
        (push proposal approved-fixes)))
    approved-fixes))

(defun gptel-skill-apply-fixes (skill fix-proposals &optional _feedback)
  "Apply FIX-PROPOSALS to SKILL.
Optional FEEDBACK parameter is reserved for future use."
  (dolist (proposal fix-proposals)
    (let ((fix-type (plist-get proposal :type))
          (fix-content (plist-get proposal :content)))
      (cond
       ((string= fix-type "prompt-update")
        (gptel-skill-update-prompt skill fix-content))
       ((string= fix-type "logic-change")
        (gptel-skill-modify-logic skill fix-content))
       ((string= fix-type "assertion-adjustment")
        (gptel-skill-adjust-assertions skill fix-content))))))

(defun gptel-skill-verify-improvement (skill old-version &optional _new-version)
  "Verify IMPROVEMENT of SKILL from OLD-VERSION.
Optional NEW-VERSION parameter is reserved for future version tracking."
  (let* ((new-benchmark (gptel-skill-benchmark-run skill))
         (old-summary (gptel-skill-benchmark-summary old-version))
         (new-summary (gptel-skill-benchmark-summary new-benchmark))
         (old-score (plist-get old-summary :overall-score))
         (new-score (plist-get new-summary :overall-score)))
    (list :improved (> new-score old-score)
          :old-score old-score
          :new-score new-score
          :difference (- new-score old-score))))

(defun gptel-skill-identify-failures (benchmark-results)
  "Identify failures in BENCHMARK-RESULTS."
  (let ((failures '()))
    (dolist (result benchmark-results)
      (let* ((test-id (plist-get result :test-id))
             (grade (plist-get result :grade))
             (score (plist-get grade :score))
             (total (plist-get grade :total)))
        (when (< score total)
          (push (list :test-id test-id
                     :issue (format "Test failed with score %d/%d" score total))
                failures))))
    failures))

(defun gptel-skill-create-fix-proposal (skill test-id issue)
  "Create a fix proposal for ISSUE in TEST-ID of SKILL."
  (let ((proposal-type "prompt-update")  ; Default type
        (proposal-content (format "Update skill %s to handle test %s better: %s" skill test-id issue)))
    (list :type proposal-type
          :content proposal-content
          :test-id test-id
          :issue issue)))

(defun gptel-skill-is-valid-fix (proposal)
  "Check if PROPOSAL is a valid fix."
  (let ((content (plist-get proposal :content)))
    (and content
         (> (length content) 0))))

(defun gptel-skill-update-prompt (skill _new-prompt)
  "Update the prompt for SKILL with NEW-PROMPT.
Note: Placeholder - depends on how skills store their prompts."
  ;; TODO: Implement actual file editing to update skill prompt
  (message "Updating prompt for skill %s" skill))

(defun gptel-skill-modify-logic (skill _logic-changes)
  "Modify the logic of SKILL based on LOGIC-CHANGES.
Note: Placeholder - depends on how skills are structured."
  ;; TODO: Implement logic to modify skill implementation
  (message "Modifying logic for skill %s" skill))

(defun gptel-skill-adjust-assertions (skill _assertion-changes)
  "Adjust test assertions for SKILL based on ASSERTION-CHANGES.
Note: Placeholder - depends on how assertions are stored."
  ;; TODO: Implement assertion file updates
  (message "Adjusting assertions for skill %s" skill))

(provide 'gptel-skill-improve)

;;; gptel-skill-improve.el ends here
