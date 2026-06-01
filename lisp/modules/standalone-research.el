;;; standalone-research.el --- Completely standalone research runner -*- lexical-binding: t; -*-
;;; Bypasses all strategic.el functions. Works even when load-file corrupts them.

(require 'json)
(declare-function gptel-benchmark-call-subagent "gptel-benchmark-subagent")
(define-error 'research-pipeline-defect "Research pipeline defect" 'error)
(defvar gptel-auto-workflow--current-research-context)
(defvar gptel-auto-workflow--research-in-progress)
(defvar gptel-auto-workflow--research-findings-cache)

(defun slr--root ()
  "Return the project root for standalone research."
  (file-name-as-directory
   (or (ignore-errors
         (and (boundp 'minimal-emacs-user-directory)
              minimal-emacs-user-directory))
       (getenv "MINIMAL_EMACS_ROOT")
       user-emacs-directory
       default-directory)))

(defun slr--estimate-confidence (findings)
  "Estimate research confidence from FINDINGS without strategic.el helpers."
  (let ((score 0.0)
        (text (or findings "")))
    (when (string-match-p "https?://" text)
      (setq score (+ score 0.3)))
    (when (> (length text) 1000)
      (setq score (+ score 0.2)))
    (when (string-match-p "## \\|### \\|\\*\\*" text)
      (setq score (+ score 0.2)))
    (when (string-match-p "```" text)
      (setq score (+ score 0.1)))
    (min 1.0 score)))

(defun slr--save-trace (prompt findings hash)
  "Save standalone research FINDINGS as an AutoTTS-compatible trace."
  (when (null findings)
    (signal 'wrong-type-argument (list #'stringp findings)))
  (let* ((root (slr--root))
         (trace-dir (expand-file-name "var/tmp/research-traces" root))
         (timestamp (format-time-string "%Y%m%d-%H%M%S"))
         (trace-file (expand-file-name (format "%s-%s.json" timestamp hash)
                                       trace-dir))
         (confidence (slr--estimate-confidence findings))
         (trace-data
          (list :timestamp (format-time-string "%Y-%m-%dT%H:%M:%SZ")
                :strategy "standalone-research"
                :findings-hash hash
                :findings findings
                :output findings
                :prompt prompt
                :prompt-length (length prompt)
                :output-length (length findings)
                :has-urls (if (string-match-p "https?://" findings) t nil)
                :has-code (if (string-match-p "```" findings) t nil)
                :has-structure (if (string-match-p "## .*\n" findings) t nil)
                :source (if (string-match-p "davidwuchn" findings) "own-repo" "external")
                :controller-decision "standalone"
                :confidence confidence
                :ema-conf confidence
                :ema-delta 0.0
                :tokens-used (/ (length findings) 4)
                :steps nil
                :step-count 0
                :turn-count 1
                :trace-log nil
                :metadata (list :tokens-estimate (/ (length findings) 4)
                                :confidence confidence
                                :standalone t))))
    (make-directory trace-dir t)
    (with-temp-file trace-file
      (insert (json-encode trace-data)))
    (when (fboundp 'gptel-auto-workflow--research-cache-index-trace-file)
      (gptel-auto-workflow--research-cache-index-trace-file trace-file))
    trace-file))

(defun slr--record-context (prompt findings)
  "Record standalone FINDINGS in the shared research context and trace store."
  (let* ((findings (or findings ""))
         (hash (sha1 findings))
         (trace-file (slr--save-trace prompt findings hash)))
    (setq gptel-auto-workflow--current-research-context
          (list :strategy "standalone-research"
                :hash hash
                :findings findings
                :digested findings
                :source (if (string-match-p "davidwuchn" findings) "own-repo" "external")
                :trace-file trace-file
                :timestamp (format-time-string "%Y-%m-%dT%H:%M:%SZ")))
    (message "[slr] Recorded AutoTTS context %s (%d chars)"
             (substring hash 0 8)
             (length findings))))

(defun slr--load-skill (skill-name)
  "Load SKILL-NAME SKILL.md content."
  (let* ((root (slr--root))
         (file (expand-file-name (format "assistant/skills/%s/SKILL.md" skill-name) root)))
    (if (file-exists-p file)
        (with-temp-buffer
          (insert-file-contents file)
          (buffer-string))
      "")))

(defun slr--save-findings (findings &optional file-path)
  "Save findings to file."
  (let ((file (or file-path
                  (expand-file-name "var/tmp/research-findings.md"
                                     (slr--root)))))
    (make-directory (file-name-directory file) t)
    (with-temp-file file
      (insert (format "# Research Findings\n\n> Updated: %s\n\n%s"
                      (format-time-string "%Y-%m-%d %H:%M")
                      findings)))
    (message "[slr] Saved %d chars to %s" (length findings) file)))

(defun slr--usable-findings-p (findings)
  "Return non-nil when FINDINGS has enough content for pipeline use."
  (and (stringp findings)
       (> (length findings) 100)
       (string-match-p "\\S-" findings)))

(defun slr--signal-missing-research (reason details)
  "Signal a research pipeline defect for tracking.
REASON is a symbol: daemon-disappeared, timeout, empty-response, or error.
DETAILS is a string with additional context.
Logs to var/tmp/research-defects.jsonl for experiment outcome correlation."
  (let ((defect-data (list :reason reason
                           :details details
                           :timestamp (format-time-string "%Y-%m-%dT%H:%M:%SZ")
                           :pipeline-defect t)))
    ;; Log the defect to var/tmp for correlation with experiment outcomes
    (let ((defect-file (expand-file-name "var/tmp/research-defects.jsonl"
                                          (slr--root))))
      (make-directory (file-name-directory defect-file) t)
      (with-temp-file defect-file
        (insert (json-encode defect-data))
        (insert "\n")))
    (message "[slr] RESEARCH PIPELINE DEFECT: %s — %s" reason details)
    ;; Signal the defect as an error so callers can handle it explicitly
    (signal 'research-pipeline-defect
            (list reason details (format "[slr] Research pipeline defect: %s (%s)" reason details)))))

(defun slr--finish-single-turn (prompt findings completion-callback)
  "Persist FINDINGS for PROMPT and invoke COMPLETION-CALLBACK."
  (unless (slr--usable-findings-p findings)
    (slr--signal-missing-research
     'empty-response
     (format "finish-single-turn received %d chars (need >100 with content)"
             (length (or findings "")))))
  (slr--record-context prompt findings)
  (slr--save-findings findings)
  (when (functionp completion-callback)
    (funcall completion-callback findings)))

(defun slr--run-single-turn (prompt completion-callback)
  "Run a single-turn research subagent call with PROMPT.
Uses run-with-timer 0 to break the call stack and prevent C stack overflow
during deeply nested subagent setup (FSM, 31 tools, preset, context init)."
  (let ((timeout 300))
    (message "[slr] Scheduling subagent with %ds timeout (timer-deferred)..." timeout)
    (run-with-timer
     0 nil
     (lambda ()
       (condition-case err
           (gptel-benchmark-call-subagent
            'researcher "External research" prompt
            (lambda (result)
              (let ((findings (or result "")))
                (message "[slr] Subagent returned %d chars" (length findings))
                (if (slr--usable-findings-p findings)
                    (slr--finish-single-turn prompt findings completion-callback)
                  (slr--signal-missing-research
                   'empty-response
                   (format "Subagent returned %d chars (need >100 with content)"
                           (length findings))))))
            timeout)
         (error
          (message "[slr] Single-turn subagent error (%s)" err)
          (slr--signal-missing-research 'daemon-disappeared (format "%s" err))))))))

(defun slr-run-research (&optional completion-callback)
  "Run external research using subagent and save results.
Tries multi-turn EMA controller first, falls back to single-turn.
COMPLETION-CALLBACK receives the saved findings when provided."
  (interactive)
  ;; Try the full multi-turn research path first (with EMA momentum controller)
  (if (and (fboundp 'gptel-auto-workflow--research-patterns)
           (fboundp 'gptel-auto-workflow--build-research-prompt))
      (condition-case err
          (progn
            (message "[slr] Multi-turn EMA research path available, delegating...")
            ;; Clear stale state before starting new research
            (setq gptel-auto-workflow--research-in-progress nil)
            ;; Ensure nil-safety for findings cache
            (when (null gptel-auto-workflow--research-findings-cache)
              (setq gptel-auto-workflow--research-findings-cache (make-hash-table :test 'equal)))
            (gptel-auto-workflow--research-patterns
             (lambda (findings)
               (condition-case inner-err
                   (if (slr--usable-findings-p findings)
                       (progn
                         (slr--save-findings findings)
                         (when (functionp completion-callback)
                           (funcall completion-callback findings)))
                     (slr--signal-missing-research
                      'empty-response
                      (format "Multi-turn EMA returned %d chars (need >100 with content)"
                              (length (or findings "")))))
               (research-pipeline-defect
                   (message "[slr] Empty research result from EMA, falling back to single-turn...")
                   (slr--run-single-turn (slr--build-prompt) completion-callback))))))
        (error
         (message "[slr] Multi-turn failed (%s)" err)
         (slr--run-single-turn (slr--build-prompt) completion-callback)))
    ;; Fallback: single-turn research (raw SKILL.md, no controller)
    (slr--run-single-turn (slr--build-prompt) completion-callback)))

(defun slr--build-prompt ()
  "Build research prompt with template variable substitution."
  (let ((prompt (slr--load-skill "researcher-prompt")))
    (when (fboundp 'gptel-auto-workflow--substitute-researcher-variables)
      (condition-case err
          (setq prompt (gptel-auto-workflow--substitute-researcher-variables prompt))
        (error
         (message "[slr] Researcher variable substitution failed (%s), using raw prompt" err))))
    (message "[slr] Prompt: %d chars" (length prompt))
    prompt))

(provide 'standalone-research)
;;; standalone-research.el ends here
