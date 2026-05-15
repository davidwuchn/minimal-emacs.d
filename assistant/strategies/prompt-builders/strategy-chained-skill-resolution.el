;;; strategy-chained-skill-resolution.el --- Sequential skill loading with dependency resolution -*- lexical-binding: t; -*-
;; Hypothesis: Loading skills sequentially where later skills incorporate earlier skill outputs produces coherent guidance
;; Axis: E (Skill loading)
;;
(require 'gptel-tools-agent-prompt-build)

(defun strategy-chained-skill-resolution-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt using chained skill resolution where skills are loaded with context from previous loads."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (skill-chain (strategy-chained-skill-resolution--build-chain))
         (chained-content (strategy-chained-skill-resolution--resolve-chain skill-chain)))
    (concat base-prompt "\n\n" chained-content)))

(defun strategy-chained-skill-resolution--build-chain ()
  "Build ordered list of skills to load in sequence."
  (list '("expertise" . "elisp-expert")
        '("discovery" . "elisp-discover")
        '("refactoring" . "elisp-refactor")
        '("validation" . "elisp-validator")))

(defun strategy-chained-skill-resolution--resolve-chain (skill-chain)
  "Load skills sequentially, building accumulated context.
SKILL-CHAIN is list of (name . skill-id) pairs."
  (let ((accumulated-context "")
        (visited-skills nil))
    (dolist (skill-entry skill-chain)
      (let* ((skill-name (car skill-entry))
             (skill-id (cdr skill-entry))
             (skill-content (condition-case nil
                                (gptel-auto-workflow--load-skill-content skill-id)
                              (error ""))))
        (unless (or (member skill-name visited-skills)
                    (string-empty-p skill-content))
          ;; Annotate skill with accumulated context from previous skills
          (setq accumulated-context
                (format "%s\n\n;; === %s Skill ===\n%s\n;; Prior relevant context from chain: %s"
                        accumulated-context
                        skill-name
                        skill-content
                        (if (string-empty-p accumulated-context)
                            "none"
                          (substring accumulated-context 0 (min 500 (length accumulated-context))))))
          (push skill-name visited-skills))))
    (format "\n;; Chained Skill Resolution\n;; Skills loaded in dependency order:\n%s"
            accumulated-context)))

(defun strategy-chained-skill-resolution-get-metadata ()
  (list :name "chained-skill-resolution"
        :version "1.0"
        :hypothesis "Sequential skill loading with accumulated context produces more coherent and layered guidance"
        :axis "E"
        :components ["skill-chaining" "context-accumulation" "dependency-ordering"]))

(provide 'strategy-chained-skill-resolution)
