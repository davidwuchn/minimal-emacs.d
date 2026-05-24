;;; gptel-auto-workflow-cq-evolution.el --- CQ-to-skill evolution wiring -*- lexical-binding: t -*-

;; Copyright (C) 2024-2026  Self-Evolving Emacs Project

;; Author: Self-Evolving System
;; Keywords: ontology, competency-questions, skill-evolution

;;; Commentary:

;; Wire competency question answerability into targeted skill evolution.
;; When the ontology cannot answer a question, trigger evolution for
;; the skill responsible for that domain.

;;; Code:

(require 'cl-lib)
(declare-function gptel-auto-workflow--run-evolution-script "gptel-auto-workflow-evolution" (script-name &rest args))

(defconst gptel-auto-workflow--cq-to-skills
  '(("Which strategies are effective?" . ("strategy-proposer" "strategy-harness"))
    ("What targets need optimization?" . ("experiment-core" "benchmark"))
    ("Which backends perform best?" . ("backend-fallback" "retry"))
    ("Are research findings coherent?" . ("researcher-prompt"))
    ("What caused an experiment to fail?" . ("error-handling" "experiment-loop"))
    ("How do strategies relate to knowledge?" . ("knowledge-management" "mementum")))
  "Map competency questions to skills that should evolve when unanswerable.")

(defun gptel-auto-workflow--evolve-skills-from-unanswerable-cqs (cq-results)
  "Trigger targeted skill evolution for unanswerable competency questions.
CQ-RESULTS is alist of (question . answerable) from
`gptel-auto-workflow--check-competency-questions'.
Returns list of skills triggered for evolution."
  (let ((evolved nil))
    (dolist (r cq-results)
      (unless (cdr r)  ; unanswerable
        (let* ((question (car r))
               (skills (cdr (assoc question gptel-auto-workflow--cq-to-skills))))
          (when skills
            (dolist (skill skills)
              (message "[cq-evolution] Triggering %s evolution (unanswerable: %s)"
                       skill question)
              (condition-case err
                  (progn
                    (gptel-auto-workflow--run-evolution-script
                     "evolve_skills.py" "--skills" skill "--root" ".")
                    (push skill evolved))
                (error (message "[cq-evolution] Failed to evolve %s: %s"
                                skill (error-message-string err)))))))))
    (delete-dups evolved)))

;; Wire into evolution cycle via advice
(defun gptel-auto-workflow--cq-evolution-advice (orig-fun &rest args)
  "Advice around `gptel-auto-workflow--check-competency-questions'.
Triggers skill evolution for unanswerable questions."
  (let ((results (apply orig-fun args)))
    (let ((total (length results))
          (answerable (cl-count-if #'cdr results)))
      (when (and (fboundp 'gptel-auto-workflow--evolve-skills-from-unanswerable-cqs)
                 (< answerable total))
        (let ((evolved (gptel-auto-workflow--evolve-skills-from-unanswerable-cqs
                        results)))
          (when evolved
            (message "[cq] Triggered evolution for %d skill(s): %s"
                     (length evolved) (string-join evolved ", "))))))
    results))

(advice-add 'gptel-auto-workflow--check-competency-questions
            :around #'gptel-auto-workflow--cq-evolution-advice)

(provide 'gptel-auto-workflow-cq-evolution)
;;; gptel-auto-workflow-cq-evolution.el ends here
