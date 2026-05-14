;;; standalone-research.el --- Completely standalone research runner -*- lexical-binding: t; -*-
;;; Bypasses all strategic.el functions. Works even when load-file corrupts them.

(require 'json)

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

(defun slr-run-research (&optional completion-callback)
  "Run external research using subagent and save results.
This is a standalone function that does NOT call strategic.el functions.
COMPLETION-CALLBACK receives the saved findings when provided."
  (interactive)
  (let ((prompt (slr--load-skill "researcher-prompt")))
    (message "[slr] Prompt: %d chars, subagents=%s, subagent-fbound=%s"
             (length prompt)
             (and (boundp 'gptel-auto-experiment-use-subagents)
                  gptel-auto-experiment-use-subagents)
             (fboundp 'gptel-benchmark-call-subagent))
    (if (and (boundp 'gptel-auto-experiment-use-subagents)
             gptel-auto-experiment-use-subagents
             (fboundp 'gptel-benchmark-call-subagent))
        (let ((timeout 300))
          (message "[slr] Calling subagent with %ds timeout..." timeout)
          (gptel-benchmark-call-subagent
           'researcher "External research" prompt
           (lambda (result)
             (let ((findings (or result "")))
               (message "[slr] Subagent returned %d chars" (length findings))
               (slr--record-context prompt findings)
               (slr--save-findings findings)
               (when (functionp completion-callback)
                 (funcall completion-callback findings))))
           timeout))
      (message "[slr] Subagents unavailable, saving empty findings")
      (slr--record-context prompt "")
      (slr--save-findings "")
      (when (functionp completion-callback)
        (funcall completion-callback "")))))

(provide 'standalone-research)
