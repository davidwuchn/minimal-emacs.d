;;; gptel-tools-agent-research.el --- Autonomous research, skill evolution, mementum -*- lexical-binding: t; -*-
;; Part of gptel-tools-agent split

(defun gptel-auto-workflow-update-mutation-skill (mutation-type all-results)
  "Update MUTATION-TYPE skill file with ALL-RESULTS."
  (let* ((skill-file (format "%s/mutations/%s.md"
                             gptel-auto-workflow-skills-dir mutation-type))
         (file (expand-file-name skill-file (gptel-auto-workflow--project-root))))
    (when (file-exists-p file)
      (let* ((content (gptel-auto-workflow--read-file-contents file))
             (relevant (cl-remove-if-not
                        (lambda (r)
                          (let ((hyp (gptel-auto-workflow--plist-get r :hypothesis "")))
                            (eq (gptel-auto-workflow-detect-mutation hyp)
                                (intern mutation-type))))
                        all-results))
             (kept-relevant (cl-remove-if-not (lambda (r) (gptel-auto-workflow--plist-get r :kept nil)) relevant))
             (total (length relevant))
             (kept-count (length kept-relevant))
             (success-rate (if (> total 0) (/ (* 100 kept-count) total) 0))
             (avg-delta (if kept-relevant
                            (/ (apply #'+ (mapcar (lambda (r) (gptel-auto-workflow--plist-get r :delta 0)) kept-relevant))
                               (length kept-relevant))
                          0))
             (history-rows '()))
        (dolist (r kept-relevant)
          (push (list (gptel-auto-workflow--plist-get r :target "")
                      (format-time-string "%Y-%m-%d")
                      (gptel-auto-workflow--plist-get r :hypothesis "")
                      (gptel-auto-workflow--plist-get r :delta 0))
                history-rows))
        (with-temp-buffer
          (insert content)
          (goto-char (point-min))
          (when (re-search-forward "^phi:[[:space:]]*\\([0-9.]+\\)" nil t)
            (replace-match (format "phi: %.2f" (/ success-rate 100.0))))
          (goto-char (point-min))
          (when (re-search-forward "^## Success History" nil t)
            (forward-line 3)
            (dolist (row (nreverse history-rows))
              (insert (format "| %s | %s | %s | %+.2f |\n"
                              (nth 0 row) (nth 1 row)
                              (truncate-string-to-width (or (nth 2 row) "-") 40 nil nil "...")
                              (or (nth 3 row) 0)))))
          (goto-char (point-min))
          (when (re-search-forward "^## Statistics" nil t)
            (forward-line 6)
            (delete-region (point) (line-end-position))
            (insert (format "| Total uses | %d |" total))
            (forward-line 1)
            (delete-region (point) (line-end-position))
            (insert (format "| Success rate | %.0f%% |" success-rate))
            (forward-line 1)
            (delete-region (point) (line-end-position))
            (insert (format "| Avg delta | %+.2f |" avg-delta)))
          (write-region (point-min) (point-max) file))))))

(defun gptel-auto-workflow-metabolize (run-id all-results)
  "Synthesize RUN-ID ALL-RESULTS to mementum + evolve skills."
  (let ((memory-dir (expand-file-name "mementum/memories"
                                      (gptel-auto-workflow--project-root)))
        (by-target (make-hash-table :test 'equal)))
    (make-directory memory-dir t)
    (let ((file (expand-file-name (format "auto-workflow-%s.md" run-id) memory-dir)))
      (with-temp-file file
        (insert (format "---\ntitle: Auto-Workflow %s\ndate: %s\n---\n\n" run-id run-id))
        (insert (format "# Auto-Workflow: %s\n\n" run-id))
        (insert "## Summary\n\n")
        (let ((kept (cl-count-if (lambda (r) (gptel-auto-workflow--plist-get r :kept nil)) all-results))
              (total (length all-results)))
          (insert (format "- Experiments: %d\n" total))
          (insert (format "- Kept: %d\n" kept))
          (insert (format "- Discarded: %d\n\n" (- total kept))))
        (insert "## Key Learnings\n\n")
        (dolist (r (cl-remove-if-not (lambda (r) (gptel-auto-workflow--plist-get r :kept nil)) all-results))
          (insert (format "- **%s**: %s\n"
                          (gptel-auto-workflow--plist-get r :target "")
                          (gptel-auto-workflow--plist-get r :hypothesis "unknown"))))))
    (message "[autonomous] Memory: mementum/memories/auto-workflow-%s.md" run-id)
    (dolist (r all-results)
      (let ((target (gptel-auto-workflow--plist-get r :target "")))
        (puthash target (cons r (gethash target by-target)) by-target)))
    (maphash
     (lambda (target results)
       (gptel-auto-workflow-update-target-skill target results))
     by-target)
    (let ((mutation-types '()))
      (dolist (r all-results)
        (let ((mutation (gptel-auto-workflow-detect-mutation
                         (gptel-auto-workflow--plist-get r :hypothesis ""))))
          (when (not (member mutation mutation-types))
            (push mutation mutation-types))))
      (dolist (mutation-type mutation-types)
        (when (not (equal mutation-type "unknown"))
          (gptel-auto-workflow-update-mutation-skill mutation-type all-results))))
    (message "[autonomous] Skills evolved: %d targets, %d mutation types"
             (hash-table-count by-target)
             (length (cl-remove "unknown" (hash-table-keys by-target))))))

(defun gptel-auto-workflow-run-autonomous ()
  "Run Autonomous Research Agent with program.md + skills + mementum.

Flow:
  1. orient() - load program.md + skills
  2. run experiments with skill guidance
  3. metabolize() - synthesize to mementum

Cron: emacsclient -e '(gptel-auto-workflow-run-autonomous)'
Manual: M-x gptel-auto-workflow-run-autonomous"
  (interactive)
  (gptel-auto-workflow--require-magit-dependencies)
  (let* ((program (gptel-auto-workflow-orient))
         (targets (plist-get program :targets))
         (run-id (format-time-string "%Y-%m-%d"))
         (all-results '())
         (completed-targets 0)
         (total-targets (length targets)))
    (if (null targets)
        (message "[autonomous] No targets in %s" gptel-auto-workflow-program-file)
      (message "[autonomous] Starting %s with %d targets" run-id (length targets))
      (dolist (target targets)
        (gptel-auto-experiment-loop
         target
         (lambda (results)
           (setq all-results (append all-results results))
           (cl-incf completed-targets)
           (when (= completed-targets total-targets)
             (gptel-auto-workflow-metabolize run-id all-results)
             (message "[autonomous] Complete: %d experiments" (length all-results)))))))))

;;; Mementum Optimization

(defvar gptel-mementum-index-file "mementum/.index"
  "Path to recall index file.")

(defun gptel-mementum-build-index ()
  "Build recall index from all knowledge files.
Creates .index file with topic → file mapping for O(1) lookup."
  (let* ((index-file (expand-file-name gptel-mementum-index-file
                                       (gptel-auto-workflow--project-root)))
         (knowledge-dir (expand-file-name "mementum/knowledge"
                                          (gptel-auto-workflow--project-root)))
         (index (make-hash-table :test 'equal)))
    (when (file-exists-p knowledge-dir)
      (dolist (file (directory-files-recursively knowledge-dir "\\.md$"))
        (let ((content (gptel-auto-workflow--read-file-contents file))
              (filename (file-relative-name file knowledge-dir)))
          (dolist (keyword '("caching" "lazy" "simplification" "retry" "context"
                             "code" "nucleus" "learning" "pattern" "evolution"
                             "safety" "upstream" "skill" "benchmark"))
            (when (string-match-p (regexp-quote keyword) content)
              (puthash keyword
                       (cons filename (gethash keyword index))
                       index))))))
    (with-temp-file index-file
      (insert "# Mementum Recall Index\n")
      (insert "# Auto-generated. Do not edit.\n\n")
      (maphash
       (lambda (keyword files)
         (insert (format "%s: %s\n" keyword (string-join (delete-dups files) ", "))))
       index))
    (message "[mementum] Index built: %d keywords" (hash-table-count index))))

(defun gptel-mementum-recall (query)
  "Quick lookup for QUERY in recall index.
Returns list of matching files."
  (let* ((index-file (expand-file-name gptel-mementum-index-file
                                       (gptel-auto-workflow--project-root)))
         (result '()))
    (when (file-exists-p index-file)
      (with-temp-buffer
        (insert-file-contents index-file)
        (goto-char (point-min))
        (when (re-search-forward (format "^%s: " (regexp-quote query)) nil t)
          (let ((line (buffer-substring-no-properties (point) (line-end-position))))
            (setq result (split-string line ",\\s-*"))))))
    (or result
        (progn
          (message "[mementum] Index miss, using git grep for: %s" query)
          (let ((default-directory (gptel-auto-workflow--project-root)))
            ;; SECURITY: Use shell-quote-argument to prevent shell injection
            (split-string
             (shell-command-to-string
              (format "git grep -l %s -- mementum/knowledge/ 2>/dev/null || true"
                      (shell-quote-argument query)))
             "\n" t))))))

(defun gptel-mementum-decay-skills ()
  "Apply decay to skill files not tested in 4+ weeks.
Run weekly via cron."
  (let* ((skills-dir (expand-file-name "mementum/knowledge/optimization-skills"
                                       (gptel-auto-workflow--project-root)))
         (mutations-dir (expand-file-name "mementum/knowledge/mutations"
                                          (gptel-auto-workflow--project-root)))
         (now (float-time))
         (four-weeks (* 4 7 24 60 60))
         (decayed 0)
         (archived 0))
    (dolist (dir (list skills-dir mutations-dir))
      (when (file-exists-p dir)
        (dolist (file (directory-files dir t "\\.md$"))
          (let ((content (gptel-auto-workflow--read-file-contents file)))
            (when (and (stringp content)
                       (string-match "^last-tested:[[:space:]]*\\([0-9-]+\\)" content))
              (let* ((date-str (match-string 1 content))
                     (last-tested (when (>= (length date-str) 10)
                                    (encode-time 0 0 0 (string-to-number (substring date-str 8 10))
                                                 (string-to-number (substring date-str 5 7))
                                                 (string-to-number (substring date-str 0 4)))))
                     (age (when last-tested
                            (- now (float-time last-tested)))))
                (when (and age (> age four-weeks))
                  (let ((new-phi (max 0.3 (- (if (string-match "^phi:[[:space:]]*\\([0-9.]+\\)" content)
                                                 (string-to-number (match-string 1 content))
                                               0.5)
                                             0.02))))
                    (if (< new-phi 0.3)
                        (progn
                          (let ((archive-dir (expand-file-name "archive" dir)))
                            (make-directory archive-dir t)
                            (rename-file file (expand-file-name (file-name-nondirectory file) archive-dir))
                            (cl-incf archived)))
                      (with-temp-buffer
                        (insert content)
                        (goto-char (point-min))
                        (when (re-search-forward "^phi:[[:space:]]*[0-9.]+" nil t)
                          (replace-match (format "phi: %.2f" new-phi)))
                        (write-region (point-min) (point-max) file)
                        (cl-incf decayed)))))))))))
    (message "[mementum] Decay: %d decayed, %d archived" decayed archived)))

(defun gptel-mementum-check-synthesis-candidates ()
  "Check for topics with ≥3 memories and suggest synthesis.
Returns list of synthesis candidates."
  (let* ((memories-dir (expand-file-name "mementum/memories"
                                         (gptel-auto-workflow--project-root)))
         (by-topic (make-hash-table :test 'equal))
         (candidates '()))
    (when (file-exists-p memories-dir)
      (dolist (file (directory-files memories-dir t "\\.md$"))
        (let ((slug (file-name-sans-extension (file-name-nondirectory file))))
          (dolist (topic (split-string slug "[-_]"))
            (when (> (length topic) 3)
              (puthash topic (cons file (gethash topic by-topic)) by-topic)))))
      (maphash
       (lambda (topic files)
         (when (>= (length files) 3)
           (push (list :topic topic :count (length files) :files files) candidates)))
       by-topic))
    (when candidates
      (message "[mementum] Synthesis candidates: %s"
               (mapcar (lambda (c) (plist-get c :topic)) candidates)))
    candidates))

(defvar gptel-mementum--pending-llm-buffers nil
  "Buffers with active direct-LLM mementum synthesis requests.")

(defun gptel-mementum--track-llm-request-buffer (buffer)
  "Remember BUFFER as hosting an active direct-LLM synthesis request."
  (when (buffer-live-p buffer)
    (cl-pushnew buffer gptel-mementum--pending-llm-buffers)))

(defun gptel-mementum--untrack-llm-request-buffer (buffer)
  "Forget BUFFER from active direct-LLM synthesis tracking."
  (setq gptel-mementum--pending-llm-buffers
        (delq buffer gptel-mementum--pending-llm-buffers)))

(defun gptel-mementum--reset-synthesis-state ()
  "Abort and clear tracked direct-LLM synthesis requests."
  (dolist (buffer (delete-dups (delq nil gptel-mementum--pending-llm-buffers)))
    (when (and (buffer-live-p buffer)
               (fboundp 'gptel-abort))
      (ignore-errors (gptel-abort buffer))))
  (setq gptel-mementum--pending-llm-buffers nil))

(defun gptel-mementum--deliver-synthesis-result (project-root headless topic files result
                                                              &optional run-id request-buffer)
  "Handle synthesis RESULT for TOPIC/FILES inside PROJECT-ROOT context.
When RUN-ID is stale, ignore RESULT instead of writing new knowledge pages.
REQUEST-BUFFER is removed from direct-LLM tracking after delivery."
  (unwind-protect
      (if (not (gptel-auto-workflow--run-callback-live-p run-id))
          (message "[mementum] Ignoring stale synthesis for '%s'; run %s is no longer active"
                   topic run-id)
        (let ((default-directory project-root)
              (gptel-auto-workflow--current-project project-root)
              (gptel-auto-workflow--project-root-override project-root)
              (gptel-auto-workflow--run-project-root project-root)
              (gptel-auto-workflow--headless headless))
          (gptel-mementum--handle-synthesis-result topic files result)
          t))
    (when request-buffer
      (gptel-mementum--untrack-llm-request-buffer request-buffer))))

(defun gptel-mementum--synthesis-agent ()
  "Return the preferred agent symbol for mementum synthesis, or nil."
  (when (and (boundp 'gptel-agent--agents)
             gptel-agent--agents)
    (cond
     ((assoc "researcher" gptel-agent--agents) 'researcher)
     ((assoc "executor" gptel-agent--agents) 'executor)
     (t nil))))

(defun gptel-mementum--synthesis-backend ()
  "Return the preferred synthesis backend for mementum, or nil."
  (cond
   ((and (fboundp 'gptel-benchmark-llm-synthesize-knowledge)
         (fboundp 'gptel-request))
    'llm)
   (t
    (gptel-mementum--synthesis-agent))))

(defun gptel-mementum-synthesize-candidate (candidate &optional synchronous synthesis-backend callback-run-id)
  "Synthesize CANDIDATE into knowledge page with human approval.
CANDIDATE is plist with :topic :count :files.
Implements λ termination(x): synthesis ≡ AI | approval ≡ human.
Returns t if synthesis was initiated, nil otherwise.

CALLBACK-RUN-ID freezes the owning workflow identity for stale-callback checks.

Note: Call `gptel-mementum-ensure-agents' first for batch processing."
  (let* ((topic (plist-get candidate :topic))
         (files (plist-get candidate :files))
         (project-root (gptel-auto-workflow--project-root))
         (headless (bound-and-true-p gptel-auto-workflow--headless))
         (memories-content '()))
    (dolist (file files)
      (let ((content (gptel-auto-workflow--read-file-contents file)))
        (when content
          (push content memories-content))))
    (if (< (length memories-content) 3)
        (progn
          (message "[mementum] Skip synthesis: only %d memories for '%s'" (length memories-content) topic)
          nil)
      (let ((synthesis-prompt (gptel-mementum--build-synthesis-prompt topic memories-content)))
        (message "[mementum] Synthesizing %d memories for topic: %s" (length memories-content) topic)
        (let ((backend (or synthesis-backend
                           (gptel-mementum--synthesis-backend)))
              (captured-run-id (or callback-run-id
                                   (and gptel-auto-workflow--running
                                        (gptel-auto-workflow--current-run-id)))))
          (pcase backend
            ('llm
             (let ((request-buffer (current-buffer)))
               (when captured-run-id
                 (gptel-mementum--track-llm-request-buffer request-buffer))
               (if synchronous
                   (gptel-mementum--deliver-synthesis-result
                    project-root headless topic files
                    (gptel-benchmark-llm-synthesize-knowledge-sync
                     topic memories-content 300)
                    captured-run-id request-buffer)
                 (gptel-benchmark-llm-synthesize-knowledge
                  topic memories-content
                  (lambda (result &rest _)
                    (gptel-mementum--deliver-synthesis-result
                     project-root headless topic files result
                     captured-run-id request-buffer))))))
            ((pred symbolp)
             (if (and (fboundp 'gptel-benchmark-call-subagent)
                      (fboundp 'gptel-agent--task))
                 (if (and synchronous
                          (fboundp 'gptel-benchmark-call-subagent-sync))
                     (gptel-mementum--deliver-synthesis-result
                      project-root headless topic files
                      (gptel-benchmark-call-subagent-sync
                       backend
                       (format "Synthesize knowledge: %s" topic)
                       synthesis-prompt
                       300)
                      captured-run-id)
                   (gptel-benchmark-call-subagent
                    backend
                    (format "Synthesize knowledge: %s" topic)
                    synthesis-prompt
                    (lambda (result)
                      (gptel-mementum--deliver-synthesis-result
                       project-root headless topic files result captured-run-id))
                    300))
               (message "[mementum] Skip '%s': no synthesis subagent available" topic)))
            (_
             (message "[mementum] Skip '%s': no synthesis backend available" topic))))
        t))))

(defun gptel-mementum-ensure-agents ()
  "Ensure a synthesis backend is available for mementum.
Returns `llm' when direct `gptel-request' synthesis is available, otherwise a
fallback subagent symbol such as `researcher' or `executor'."
  (let ((base-dir (or (bound-and-true-p user-emacs-directory)
                      (expand-file-name "~/.emacs.d"))))
    ;; Prefer direct, no-tool synthesis first.
    (unless (or (fboundp 'gptel-benchmark-llm-synthesize-knowledge)
                (featurep 'gptel-benchmark-llm))
      (load-file (expand-file-name "lisp/modules/gptel-benchmark-llm.el" base-dir)))
    (or (gptel-mementum--synthesis-backend)
        (progn
          ;; Ensure gptel-agent is loaded for subagent fallback.
          (unless (featurep 'gptel-agent)
            (let* ((elpa-dir (expand-file-name "var/elpa/" base-dir))
                   (yaml-dir (car (directory-files elpa-dir t "\\`yaml-"))))
              (when (and yaml-dir (file-directory-p yaml-dir))
                (add-to-list 'load-path yaml-dir)))
            (require 'gptel-agent nil t))
          (unless (fboundp 'gptel-benchmark-call-subagent)
            (load-file (expand-file-name "lisp/modules/gptel-benchmark-subagent.el" base-dir)))
          (when (fboundp 'gptel-agent--update-agents)
            (unless (and (boundp 'gptel-agent-dirs) gptel-agent-dirs)
              (let ((pkg-agents (expand-file-name "packages/gptel-agent/agents/" base-dir)))
                (setq gptel-agent-dirs
                      (cl-remove-if-not #'file-directory-p (list pkg-agents)))))
            (when (and (boundp 'gptel-agent-dirs) gptel-agent-dirs)
              (or (and (boundp 'gptel-agent--agents) gptel-agent--agents)
                  (gptel-agent--update-agents))))
          (gptel-mementum--synthesis-backend)))))

(defun gptel-mementum-synthesize-all-candidates (&optional candidates synchronous)
  "Synthesize all CANDIDATES (or detect if nil) with human approval.
Ensures agents are loaded once before processing batch."
  (let* ((cands (or candidates (gptel-mementum-check-synthesis-candidates)))
         (synthesized 0)
         (backend (gptel-mementum-ensure-agents))
         (batch-run-id (and gptel-auto-workflow--running
                            (gptel-auto-workflow--current-run-id)))
         (stopped nil))
    ;; Setup agents once for entire batch (not per-candidate)
    (if backend
        (progn
          (message "[mementum] %s available, processing %d candidates"
                   (pcase backend
                     ('llm "Direct LLM")
                     (_ (capitalize (symbol-name backend))))
                   (length cands))
          (dolist (candidate cands)
            (unless stopped
              (if (and batch-run-id
                       (not (gptel-auto-workflow--run-callback-live-p batch-run-id)))
                  (progn
                    (setq stopped t)
                    (message "[mementum] Stopping stale synthesis batch; run %s is no longer active"
                             batch-run-id))
                (when (gptel-mementum-synthesize-candidate
                       candidate synchronous backend batch-run-id)
                  (cl-incf synthesized))))))
      (message "[mementum] No synthesis backend available, skipping synthesis"))
    (message "[mementum] %s %d/%d candidates"
             (if synchronous "Synthesized" "Queued")
             synthesized
             (length cands))
    synthesized))

(defun gptel-mementum--handle-synthesis-result (topic files result)
  "Handle LLM synthesis RESULT for TOPIC from FILES.
Shows preview and asks for human approval before saving."
  (condition-case err
      (let* ((extracted (gptel-mementum--extract-content result))
             (line-count (with-temp-buffer (insert extracted) (count-lines 1 (point-max)))))
        (if (< line-count 50)
            (message "[mementum] Skip '%s': only %d lines (need ≥50)" topic line-count)
          (if (bound-and-true-p gptel-auto-workflow--headless)
              (progn
                (message "[mementum] Auto-saving '%s' in headless mode (%d lines)" topic line-count)
                (gptel-mementum--save-knowledge-page topic files extracted))
            (let ((preview-buffer (get-buffer-create "*Synthesis Preview*")))
              (with-current-buffer preview-buffer
                (erase-buffer)
                (insert (format "# Synthesis Preview: %s\n\n" topic))
                (insert (format "Generated: %d lines\n\n" line-count))
                (insert "## Generated Knowledge Page\n\n")
                (insert extracted)
                (goto-char (point-min)))
              (display-buffer preview-buffer)
              (when (y-or-n-p (format "Create knowledge page for '%s'? (%d lines) " topic line-count))
                (gptel-mementum--save-knowledge-page topic files extracted))))))
    (error
     (message "[mementum] Error handling synthesis for '%s': %s" topic err))))

(defun gptel-mementum--build-synthesis-prompt (topic memories)
  "Build prompt for LLM to synthesize MEMORIES into knowledge page for TOPIC."
  (format "Synthesize the following memories into a knowledge page.

TOPIC: %s

REQUIREMENTS:
1. Minimum 50 lines of actual content
2. Concrete examples (code, tables, commands)
3. Actionable patterns (not just descriptions)
4. Cross-references to related topics
5. Return the full markdown page directly in your final response

IMPORTANT:
- Do not write files or edit the repository
- Do not use tools when the memories below already contain enough context
- Return the complete knowledge page inline, not a summary of what you wrote

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

Generate the complete knowledge page now. Start with the frontmatter and include ALL content. Do not truncate or summarize - provide the full synthesis."
          topic
          (mapconcat #'identity memories "\n\n---\n\n")))

(defun gptel-mementum--extract-content (llm-result)
  "Extract knowledge page content from LLM-RESULT.
Returns the content between the first --- and end, or the whole result."
  (let* ((result (if (stringp llm-result) llm-result (format "%s" llm-result)))
         (start (string-match "---\n" result)))
    (if start
        (substring result start)
      result)))

(defun gptel-mementum--save-knowledge-page (topic files content)
  "Save synthesized CONTENT as knowledge page for TOPIC from FILES."
  (let* ((know-dir (expand-file-name "mementum/knowledge" (gptel-auto-workflow--project-root)))
         (know-file (expand-file-name (format "%s.md" topic) know-dir)))
    (make-directory know-dir t)
    (with-temp-file know-file
      (insert content))
    (message "[mementum] Created knowledge page draft: %s (%d lines)"
             know-file
             (with-temp-buffer (insert content) (count-lines 1 (point-max))))
    (message "[mementum] Review and commit manually: %s"
             (file-relative-name know-file (gptel-auto-workflow--project-root)))
    know-file))



(defun gptel-mementum-weekly-job ()
  "Weekly mementum maintenance: decay + index rebuild + synthesis.
Implements λ synthesize(topic): ≥3 memories → candidate → human approval."
  (interactive)
  (message "[mementum] Starting weekly maintenance...")
  (gptel-mementum-build-index)
  (gptel-mementum-decay-skills)
  (let ((synthesized (gptel-mementum-synthesize-all-candidates nil t)))
    (message "[mementum] Weekly maintenance complete. Synthesized: %d" synthesized)))

(defun gptel-mementum-synthesis-run ()
  "Interactively run synthesis on all candidates.
M-x gptel-mementum-synthesis-run"
  (interactive)
  (gptel-mementum-synthesize-all-candidates))

(provide 'gptel-tools-agent)

;;; gptel-tools-agent.el ends here

(provide 'gptel-tools-agent-research)
;;; gptel-tools-agent-research.el ends here
