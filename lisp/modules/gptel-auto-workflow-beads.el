;;; gptel-auto-workflow-beads.el --- Cross-mayor bead protocol -*- lexical-binding: t; -*-

;; Bead Protocol: lightweight cross-mayor communication
;; GTM → PMF: research insights → experiment ideas
;; PMF → GTM: experiment results → validated learnings

(require 'cl-lib)

(defvar gptel-auto-workflow--beads-dir
  (expand-file-name "mementum/beads/")
  "Base directory for cross-mayor beads.")

;;; ─── Bead Schema ───

;; GTM → PMF bead:
;;   id, source, technique, expected-impact, priority, status
;; PMF → GTM bead:
;;   id, experiment, result, score, actual-impact, status

(defun gptel-auto-workflow--bead-dir (direction)
  "Return bead directory for DIRECTION (gtm-to-pmf or pmf-to-gtm)."
  (expand-file-name (symbol-name direction) gptel-auto-workflow--beads-dir))

(defun gptel-auto-workflow--bead-parse (content)
  "Parse bead frontmatter from markdown CONTENT.
Returns plist with :id :source :technique etc."
  (when (stringp content)
    (with-temp-buffer
      (insert content)
      (goto-char (point-min))
      (when (looking-at "---")
        (forward-line 1)
        (let ((end (save-excursion
                     (re-search-forward "^---" nil t)
                     (point)))
              (bead (list)))
          (while (and (< (point) end) (not (eobp)))
            (when (looking-at "\\([a-z-]+\\):\\s-*\\(.*\\)$")
              (let ((key (intern (concat ":" (match-string 1))))
                    (val (string-trim (match-string 2))))
                (setq bead (plist-put bead key val))))
            (forward-line 1))
          bead)))))

(defun gptel-auto-workflow--bead-create (direction &rest properties)
  "Create a bead for DIRECTION with PROPERTIES plist.
Example: \(bead-create \='gtm-to-pmf :source \='github
:technique \='hashline\)"
  (let* ((timestamp (format-time-string "%Y%m%d-%H%M%S"))
         (id (format "%s-%s-%d"
                     (symbol-name direction)
                     timestamp
                     (random 10000)))
         (dir (gptel-auto-workflow--bead-dir direction))
         (file (expand-file-name (format "%s.md" id) dir)))
    (make-directory dir t)
    (with-temp-file file
      (insert "---\n")
      (insert (format "id: %s\n" id))
      (cl-loop for (key val) on properties by #'cddr
               do (insert (format "%s: %s\n"
                                  (substring (symbol-name key) 1)
                                  val)))
      (insert "---\n\n")
      (insert (format "Bead from %s\nGenerated: %s\n"
                      (symbol-name direction)
                      (format-time-string "%Y-%m-%d %H:%M"))))
    (message "[bead] Created %s → %s" id (symbol-name direction))
    id))

(defun gptel-auto-workflow--bead-list (&optional direction status-filter)
  "List beads. Optional DIRECTION and STATUS-FILTER."
  (let ((dirs (if direction
                  (list (gptel-auto-workflow--bead-dir direction))
                (list (gptel-auto-workflow--bead-dir 'gtm-to-pmf)
                      (gptel-auto-workflow--bead-dir 'pmf-to-gtm))))
        beads)
    (dolist (dir dirs)
      (when (file-directory-p dir)
        (dolist (file (directory-files dir t "\\.md$"))
          (let* ((content (with-temp-buffer
                            (insert-file-contents file)
                            (buffer-string)))
                 (bead (gptel-auto-workflow--bead-parse content)))
            (when bead
              (setq bead (plist-put bead :file file))
              (when (or (null status-filter)
                        (string= (plist-get bead :status) status-filter))
                (push bead beads)))))))
    (sort beads (lambda (a b)
                  (string> (or (plist-get a :id) "")
                           (or (plist-get b :id) ""))))))

(defun gptel-auto-workflow--bead-update-status (id new-status)
  "Update bead ID status to NEW-STATUS."
  (let ((beads (gptel-auto-workflow--bead-list)))
    (cl-some (lambda (bead)
               (when (string= (plist-get bead :id) id)
                 (let* ((file (plist-get bead :file))
                        (content (with-temp-buffer
                                   (insert-file-contents file)
                                   (buffer-string))))
                   (setq content (replace-regexp-in-string
                                  "^status:.*$"
                                  (format "status: %s" new-status)
                                  content))
                   (with-temp-file file
                     (insert content))
                   (message "[bead] Updated %s → %s" id new-status)
                   t)))
             beads)))

;;; ─── Auto-Filing from Research (GTM → PMF) ───

(defun gptel-auto-workflow--bead-file-from-research (findings)
  "Parse research FINDINGS and file beads for promising techniques.
Returns list of created bead IDs."
  (let ((ids nil))
    (when (stringp findings)
      ;; Look for technique suggestions in findings
      (with-temp-buffer
        (insert findings)
        (goto-char (point-min))
        ;; Pattern: "Try [technique] to [expected-impact]"
        (while (re-search-forward
                "Try \\([^\n]+\\) to \\([^\n]+\\)"
                nil t)
          (let ((technique (match-string 1))
                (impact (match-string 2)))
            (push (gptel-auto-workflow--bead-create
                   'gtm-to-pmf
                   :source "research-findings"
                   :technique technique
                   :expected-impact impact
                   :priority "medium"
                   :status "pending")
                  ids)))
        ;; Pattern: "Consider [technique] for [reason]"
        (goto-char (point-min))
        (while (re-search-forward
                "Consider \\([^\n]+\\) for \\([^\n]+\\)"
                nil t)
          (let ((technique (match-string 1))
                (reason (match-string 2)))
            (push (gptel-auto-workflow--bead-create
                   'gtm-to-pmf
                   :source "research-findings"
                   :technique technique
                   :expected-impact reason
                   :priority "low"
                   :status "pending")
                  ids)))))
    ids))

;;; ─── Auto-Updating from Experiments (PMF → GTM) ───

(defun gptel-auto-workflow--bead-update-from-experiment (experiment)
  "Create PMF → GTM bead from EXPERIMENT result.
EXPERIMENT is a plist with :target :id :kept :score :hypothesis etc."
  (when (and (plistp experiment)
             (plist-get experiment :target))
    (let* ((target (plist-get experiment :target))
           (exp-id (or (plist-get experiment :id) "unknown"))
           (kept (plist-get experiment :kept))
           (score-before (or (plist-get experiment :score-before) 0))
           (score-after (or (plist-get experiment :score-after) 0))
           (actual-impact (if (> score-after 0)
                             (format "+%.0f%%"
                                     (* 100 (/ (- score-after score-before)
                                               (max score-before 0.001))))
                           "no improvement")))
      (gptel-auto-workflow--bead-create
       'pmf-to-gtm
       :experiment (format "%s-%s" target exp-id)
       :result (if kept "kept" "discarded")
       :score (format "%.2f/9" (or score-after 0))
       :actual-impact actual-impact
       :status (if kept "validated" "failed"))
      ;; Also update any matching GTM → PMF bead
      (let ((beads (gptel-auto-workflow--bead-list 'gtm-to-pmf "running")))
        (dolist (bead beads)
          (when (and (string-match-p (regexp-quote target)
                                     (or (plist-get bead :technique) ""))
                     kept)
            (gptel-auto-workflow--bead-update-status
             (plist-get bead :id)
             "validated")))))))

(provide 'gptel-auto-workflow-beads)
;;; gptel-auto-workflow-beads.el ends here
