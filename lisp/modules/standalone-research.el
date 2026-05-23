;;; standalone-research.el --- Completely standalone research runner -*- lexical-binding: t; -*-
;;; Bypasses all strategic.el functions. Works even when load-file corrupts them.

(require 'json)
(declare-function gptel-benchmark-call-subagent "gptel-benchmark-subagent")
(defvar gptel-auto-workflow--current-research-context)
(defvar gptel-auto-workflow--research-in-progress)

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
    (when (string-match-p "## \|### \|\\*\\*" text)
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

(defun slr--local-fallback-findings (&optional reason)
  "Return local fallback findings when external research fails for REASON."
  (format "## Local Research Fallback

Research subagent did not return usable external findings%s.

Use this local context for the pipeline instead of treating research as absent:

- Prioritize daemon-loading safety: avoid `load-file` paths that can corrupt nested `lambda` or `maphash` forms in the workflow daemon.
- Prefer nil-safety and proper-list guards around warm daemon state, cache lookups, and parsed subagent output.
- Keep analyzer/controller outputs machine-parseable; when wrappers or code fences appear, scan for the first valid plist instead of parsing the whole response.
- Treat timeout-sized or header-only research output as failed and fall back to local repository patterns.

This fallback is intentionally local-only and should be replaced by fresh external research when the provider is healthy."
          (if (and (stringp reason) (string-match-p "\\S-" reason))
              (format " (%s)" (truncate-string-to-width reason 120 nil nil "..."))
            "")))

(defun slr--finish-single-turn (prompt findings completion-callback)
  "Persist FINDINGS for PROMPT and invoke COMPLETION-CALLBACK."
  (let ((final-findings
         (if (slr--usable-findings-p findings)
             findings
           (message "[slr] Single-turn returned unusable findings (%d chars), using local fallback"
                    (length (or findings "")))
           (slr--local-fallback-findings findings))))
    (slr--record-context prompt final-findings)
    (slr--save-findings final-findings)
    (when (functionp completion-callback)
      (funcall completion-callback final-findings))))

(defun slr--run-single-turn (prompt completion-callback)
  "Run a single-turn research subagent call with PROMPT.
Bypasses gptel-benchmark-call-subagent and calls gptel-agent--task directly
with DeepSeek backend to avoid the MiniMax fallthrough."
  (let ((timeout 300))
    (message "[slr] Calling subagent directly with DeepSeek backend...")
    (run-with-timer
     0 nil
     (lambda ()
       (let ((gptel-backend (or (and (boundp 'gptel--deepseek) gptel--deepseek)
                                gptel-backend))
             (gptel-model (when (boundp 'my/gptel-plain-model)
                            my/gptel-plain-model))
             (gptel-agent-preset nil))
         (condition-case err
             (if (fboundp 'gptel-agent--task)
                 (gptel-agent--task
                  (lambda (result)
                    (let ((findings (or result "")))
                      (message "[slr] Direct subagent returned %d chars" (length findings))
                      (slr--finish-single-turn prompt findings completion-callback)))
                  "researcher" "External research" prompt)
               (message "[slr] gptel-agent--task not available, using fallback")
               (slr--finish-single-turn prompt "" completion-callback))
           (error
            (message "[slr] Direct subagent failed (%s), using local fallback" err)
            (slr--finish-single-turn prompt (format "%s" err) completion-callback))))))))

(defun slr-run-research (&optional completion-callback)
  "Run external research using subagent and save results.
Uses direct gptel-agent--task call (via slr--run-single-turn) to bypass
the MiniMax fallthrough in gptel-benchmark-call-subagent.
COMPLETION-CALLBACK receives the saved findings when provided."
  (interactive)
  ;; Skip the multi-turn path entirely — its gptel-benchmark-call-subagent
  ;; path always falls through to MiniMax regardless of global backend
  ;; settings.  The single-turn path calls gptel-agent--task directly with
  ;; DeepSeek bound dynamically.
  (slr--run-single-turn (slr--build-prompt) completion-callback))

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
