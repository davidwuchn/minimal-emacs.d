;;; gptel-benchmark-llm.el --- LLM-powered improvement suggestions -*- lexical-binding: t; -*-

;; Copyright (C) 2025 David Wu
;; Author: David Wu
;; Version: 1.0.0
;; Keywords: ai, benchmark, llm, improvement

;;; Commentary:

;; LLM integration for generating improvement suggestions.
;; Uses gptel to analyze benchmark results and generate specific,
;; actionable improvements for skills and workflows.

;;; Code:

(require 'cl-lib)
(require 'gptel-benchmark-principles)
(require 'gptel-benchmark-core)
(require 'gptel-benchmark-memory)

(declare-function gptel-request "gptel")
(declare-function gptel-abort "gptel" (buffer))
(defvar gptel-model)

;;; Customization

(defgroup gptel-benchmark-llm nil
  "LLM integration for benchmark improvements."
  :group 'gptel-benchmark)

(defcustom gptel-benchmark-llm-enabled t
  "Whether to use LLM for improvement suggestions."
  :type 'boolean
  :group 'gptel-benchmark-llm)

(defcustom gptel-benchmark-llm-model nil
  "Model to use for LLM suggestions. nil means default."
  :type '(choice (const :tag "Default" nil)
                 (string :tag "Model name"))
  :group 'gptel-benchmark-llm)

;;; Main Entry Points

(defun gptel-benchmark-llm-suggest-improvements (name type anti-patterns &optional callback)
  "Use LLM to generate improvement suggestions.
NAME is skill/workflow name, TYPE is 'skill or 'workflow.
ANTI-PATTERNS is list of detected anti-patterns.
CALLBACK receives suggestions when complete (async)."
  (if (and gptel-benchmark-llm-enabled (fboundp 'gptel-request))
      (gptel-benchmark--llm-request-suggestions name type anti-patterns callback)
    (gptel-benchmark--fallback-suggestions name type anti-patterns callback)))

(defun gptel-benchmark-llm-analyze-results (name type results &optional callback)
  "Use LLM to analyze benchmark RESULTS.
Returns insights about performance patterns."
  (if (and gptel-benchmark-llm-enabled (fboundp 'gptel-request))
      (gptel-benchmark--llm-request-analysis name type results callback)
    (gptel-benchmark--fallback-analysis results callback)))

(defun gptel-benchmark-llm-synthesize-knowledge (topic memories &optional callback)
  "Use LLM to synthesize MEMORIES about TOPIC into knowledge.
CALLBACK receives synthesized content."
  (if (and gptel-benchmark-llm-enabled (fboundp 'gptel-request))
      (gptel-benchmark--llm-request-synthesis topic memories callback)
    (gptel-benchmark--fallback-synthesis topic memories callback)))

;;; LLM Request Functions

(defun gptel-benchmark--call-llm-request (prompt callback)
  "Call `gptel-request' with PROMPT and CALLBACK.
When `gptel-benchmark-llm-model' is non-nil, bind `gptel-model' dynamically
instead of passing an unsupported `:model' keyword."
  (let ((gptel-model (or gptel-benchmark-llm-model
                         (and (boundp 'gptel-model) gptel-model))))
    (gptel-request prompt
      :callback callback)))

(defun gptel-benchmark--llm-request-suggestions (name type anti-patterns callback)
  "Send LLM request for improvement suggestions."
  (let* ((prompt (gptel-benchmark--make-improvement-prompt name type anti-patterns))
         (default-callback (lambda (response &rest _)
                              (gptel-benchmark--parse-suggestions response))))
    (condition-case err
        (gptel-benchmark--call-llm-request prompt (or callback default-callback))
      (error
       (message "[llm] Error requesting suggestions: %s" err)
       (gptel-benchmark--fallback-suggestions name type anti-patterns callback)))))

(defun gptel-benchmark--llm-request-analysis (name type results callback)
  "Send LLM request for results analysis."
  (let* ((prompt (gptel-benchmark--make-analysis-prompt name type results))
         (default-callback (lambda (response &rest _)
                              (gptel-benchmark--parse-analysis response))))
    (condition-case err
        (gptel-benchmark--call-llm-request prompt (or callback default-callback))
      (error
       (message "[llm] Error requesting analysis: %s" err)
       (gptel-benchmark--fallback-analysis results callback)))))

(defun gptel-benchmark--llm-request-synthesis (topic memories callback)
  "Send LLM request for knowledge synthesis."
  (let* ((prompt (gptel-benchmark--make-synthesis-prompt topic memories))
         (default-callback (lambda (response &rest _)
                              (gptel-benchmark--parse-synthesis response))))
    (condition-case err
        (gptel-benchmark--call-llm-request prompt (or callback default-callback))
      (error
       (message "[llm] Error requesting synthesis: %s" err)
       (gptel-benchmark--fallback-synthesis topic memories callback)))))

;;; Prompt Generation

(defun gptel-benchmark--make-improvement-prompt (name type anti-patterns)
  "Create prompt for improvement suggestions."
  (format "You are an AI benchmark improvement system using Wu Xing principles.

Analyze the following anti-patterns detected in %s %s and suggest specific improvements.

## Anti-Patterns (相克)
%s

## Wu Xing Framework
- Wood (Operations): Action, execution
- Fire (Intelligence): Learning, adaptation  
- Earth (Control): Constraints, resources
- Metal (Coordination): Structure, protocols
- Water (Identity): Purpose, direction

For each anti-pattern:
1. Identify the affected element
2. Apply the controlling element (相克 remedy)
3. Suggest a specific, actionable improvement

Format your response as JSON:
```json
{
  \"improvements\": [
    {\"element\": \"wood\", \"action\": \"specific action\", \"rationale\": \"why this helps\"}
  ]
}
```"
          type name
          (mapconcat (lambda (ap)
                       (format "- %s (%s): %s"
                               (plist-get ap :pattern)
                               (plist-get ap :element)
                               (plist-get ap :symptom)))
                     anti-patterns "\n")))

(defun gptel-benchmark--make-analysis-prompt (name type results)
  "Create prompt for results analysis."
  (format "Analyze these benchmark results for %s %s:

%s

Provide:
1. Overall assessment
2. Key strengths
3. Areas for improvement
4. Recommended focus areas

Be concise and specific." type name
          (if (listp results)
              (format "Overall score: %.1f%%" 
                      (* 100 (or (plist-get results :overall-score) 0)))
            (format "%S" results))))

(defun gptel-benchmark--make-synthesis-prompt (topic memories)
  "Create prompt for knowledge synthesis."
  (format "Synthesize the following memories into a knowledge page.

TOPIC: %s

REQUIREMENTS:
1. Minimum 50 lines of actual content
2. Concrete examples (code, tables, commands)
3. Actionable patterns (not just descriptions)
4. Cross-references to related topics
5. Return the full markdown page directly in your final response

IMPORTANT:
- Return the complete knowledge page inline, not a summary
- Do not describe what you would write; write the page itself
- Start with frontmatter and include the full document body

OUTPUT FORMAT:
---
title: [Title]
status: active
category: knowledge
tags: [tag1, tag2]
---

# [Title]

## [Section 1]

[Content with examples]

## [Section 2]

[Content with patterns]

## Related

- [Related topics]

---

MEMORIES TO SYNTHESIZE:

%s

---

Generate the complete knowledge page now. Start with the frontmatter and include ALL content. Do not truncate or summarize."
          topic
          (mapconcat #'identity memories "\n\n---\n\n")))

;;; Response Parsing

(defun gptel-benchmark--parse-suggestions (response)
  "Parse LLM response into suggestions list."
  (condition-case nil
      (let* ((json-string (gptel-benchmark--extract-json response))
             (data (json-read-from-string json-string))
             (improvements (cdr (assq 'improvements data))))
        (mapcar (lambda (imp)
                  (list :element (intern (or (cdr (assq 'element imp)) "unknown"))
                        :action (or (cdr (assq 'action imp)) "No action specified")
                        :rationale (or (cdr (assq 'rationale imp)) "No rationale")))
                (if (vectorp improvements) (append improvements nil) improvements)))
    (error
     (message "[llm] Failed to parse suggestions, using fallback")
     nil)))

(defun gptel-benchmark--parse-analysis (response)
  "Parse LLM analysis response."
  (list :analysis response
        :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S")))

(defun gptel-benchmark--parse-synthesis (response)
  "Parse LLM synthesis response into knowledge content."
  response)

(defun gptel-benchmark--extract-json (text)
  "Extract JSON from TEXT that may contain markdown code blocks."
  (if (string-match "```json\\s-*\\(\\(?:.\\|\n\\)*?\\)\\s-*```" text)
      (match-string 1 text)
    text))

;;; Fallback Functions (no LLM)

(defun gptel-benchmark--fallback-suggestions (name type anti-patterns callback)
  "Generate fallback suggestions without LLM."
  (let ((suggestions (mapcar
                      (lambda (ap)
                        (let ((element (plist-get ap :element)))
                          (list :element element
                                :action (pcase element
                                          ('wood "Reduce step count, simplify operations")
                                          ('fire "Focus on one task at a time")
                                          ('earth "Relax constraints, allow flexibility")
                                          ('metal "Adapt protocols to context")
                                          ('water "Clarify purpose and direction"))
                                :rationale (format "Addresses %s anti-pattern" (plist-get ap :pattern)))))
                      anti-patterns)))
    (if callback (funcall callback suggestions) suggestions)))

(defun gptel-benchmark--fallback-analysis (results callback)
  "Generate fallback analysis without LLM."
  (let ((analysis (list :overall-score (plist-get results :overall-score)
                        :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S"))))
    (if callback (funcall callback analysis) analysis)))

(defun gptel-benchmark--fallback-synthesis (topic memories callback)
  "Generate fallback synthesis without LLM."
  (let ((content (format "---\ntitle: %s\nstatus: open\n---\n\nSynthesized from %d memories.\n\n%s"
                         topic (length memories)
                         (mapconcat #'identity memories "\n\n"))))
    (if callback (funcall callback content) content)))

;;; Synchronous Wrappers

(defun gptel-benchmark-llm-suggest-improvements-sync (name type anti-patterns)
  "Synchronous version of suggest-improvements.
Returns suggestions directly, blocking until complete."
  (let ((result nil)
        (done nil)
        (timeout-count 0))
    (gptel-benchmark-llm-suggest-improvements
     name type anti-patterns
     (lambda (suggestions &rest _)
       (setq result suggestions done t)))
    (while (and (not done) (< timeout-count 600)) ; max 60s at 0.1s intervals
      (sit-for 0.1)
      (cl-incf timeout-count))
     (unless done
       (message "[llm] Timeout waiting for suggestions after 60s"))
     result))

(defun gptel-benchmark-llm-synthesize-knowledge-sync (topic memories &optional timeout-seconds)
  "Synchronous version of `gptel-benchmark-llm-synthesize-knowledge'.
Returns synthesized knowledge content directly. TIMEOUT-SECONDS defaults to 300."
  (let ((result nil)
         (done nil)
         (timeout-count 0)
         (limit (* 10 (or timeout-seconds 300)))
         (request-buffer (current-buffer)))
    (gptel-benchmark-llm-synthesize-knowledge
     topic memories
      (lambda (content &rest _)
        (setq result content
              done t)))
    (while (and (not done) (< timeout-count limit))
      (sit-for 0.1)
      (cl-incf timeout-count))
    (unless done
      (message "[llm] Timeout waiting for synthesis after %ss" (or timeout-seconds 300))
      (when (and (buffer-live-p request-buffer)
                 (fboundp 'gptel-abort))
        (ignore-errors (gptel-abort request-buffer))))
    result))

;;; Provide

(provide 'gptel-benchmark-llm)

;;; gptel-benchmark-llm.el ends here
