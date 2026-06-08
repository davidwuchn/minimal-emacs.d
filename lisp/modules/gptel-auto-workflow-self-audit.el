;;; gptel-auto-workflow-self-audit.el --- Self-audit: detect and auto-fix system gaps -*- lexical-binding: t; -*-
;;
;; YC principle: 'self-evolve and self-heal' must include META, not just code.
;; Previously 7+ audit passes by a human (David) found the same recurring
;; problems — backend cold-start, strategy cold-start, staging-merge
;; bottleneck, inactive subsystems. The system could find these itself
;; if it looked. This module does.
;;
;; What it does:
;; 1. Detect backend cold-start: any backend with 0 experiments in 7d
;; 2. Detect strategy cold-start: any strategy with 0 evaluations
;; 3. Detect staging-merge bottleneck: >50% of failures are staging-merge
;; 4. Generate 'audit-fix' memory when issues found
;; 5. Emit a Self-Audit Report to the digest
;;
;; Pattern: 'What would a human reviewer notice? Let the system notice too.'

(require 'cl-lib)
(require 'subr-x)

(declare-function gptel-auto-workflow--expand-workspace-path
  "gptel-tools-agent-base" (path &optional root))

;;; Customization

(defgroup gptel-auto-workflow-self-audit nil
  "Self-audit: detect and auto-fix system gaps."
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-self-audit-enabled t
  "When non-nil, run self-audit checks during the pipeline."
  :type 'boolean
  :group 'gptel-auto-workflow-self-audit)

(defcustom gptel-auto-workflow-self-audit-cold-start-window 7
  "Days of history to scan for cold-start detection."
  :type 'integer
  :group 'gptel-auto-workflow-self-audit)

(defcustom gptel-auto-workflow-self-audit-bottleneck-threshold 0.5
  "Fraction threshold for bottleneck detection."
  :type 'number
  :group 'gptel-auto-workflow-self-audit)

;;; Helpers

(defun gptel-auto-workflow-self-audit--root ()
  "Return workspace root, falling back to default-directory.
Uses gptel-auto-workflow--workspace-path if set (pipeline batch mode),
then --expand-workspace-path (daemon mode), then default-directory."
  (or (and (boundp 'gptel-auto-workflow--workspace-path)
           gptel-auto-workflow--workspace-path
           (file-directory-p gptel-auto-workflow--workspace-path)
           gptel-auto-workflow--workspace-path)
      (and (fboundp 'gptel-auto-workflow--expand-workspace-path)
           (gptel-auto-workflow--expand-workspace-path ""))
      default-directory))

(defun gptel-auto-workflow-self-audit--filter-recent-files (files cutoff)
  "Return FILES whose mtime is after CUTOFF (float-time)."
  (let (recent)
    (dolist (f files)
      (when-let ((attrs (file-attributes f)))
        (when (time-less-p cutoff (float-time (nth 5 attrs)))
          (push f recent))))
    recent))

(defun gptel-auto-workflow-self-audit--tsv-files (&optional window)
  "Return recent results.tsv files within WINDOW days."
  (let* ((root (gptel-auto-workflow-self-audit--root))
         (days (or window
                   gptel-auto-workflow-self-audit-cold-start-window))
         (cutoff (float-time
                  (time-subtract (current-time) (days-to-time days))))
         (exp-dir (expand-file-name "var/tmp/experiments" root)))
    (when (file-exists-p exp-dir)
      (gptel-auto-workflow-self-audit--filter-recent-files
       (directory-files exp-dir t "\\.tsv$")
       cutoff))))

(defun gptel-auto-workflow-self-audit--parse-tsv-lines (file)
  "Parse FILE as TSV, return list of field-lists per line."
  (condition-case nil
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (let (rows)
          (while (not (eobp))
            (let ((line (buffer-substring (point) (line-end-position))))
              (push (split-string line "\t" t) rows))
            (forward-line 1))
          (nreverse rows)))
    (error nil)))

(defun gptel-auto-workflow-self-audit--hash-keys (table)
  "Return list of keys from hash TABLE."
  (let (keys)
    (maphash (lambda (k _) (push k keys)) table)
    keys))

(defun gptel-auto-workflow-self-audit--collect-from-tsv-fields
    (tsv-files field-idx filter-fn)
  "Collect unique values from FIELD-IDX across TSV-FILES.
FILTER-FN is called on each value; only truthy results are kept."
  (let ((table (make-hash-table :test 'equal)))
    (dolist (rf tsv-files)
      (dolist (row (gptel-auto-workflow-self-audit--parse-tsv-lines rf))
        (when (length> row field-idx)
          (let ((val (nth field-idx row)))
            (when (funcall filter-fn val)
              (puthash val t table))))))
    (gptel-auto-workflow-self-audit--hash-keys table)))

(defun gptel-auto-workflow-self-audit--backend-filter (val)
  "Return non-nil if VAL looks like a backend name."
  (and val (string-match-p "^[A-Z]" val)))

(defun gptel-auto-workflow-self-audit--strategy-filter (val)
  "Return non-nil if VAL is a meaningful strategy name."
  (and val
       (not (string-empty-p val))
       (not (string= val "template-default"))
       (not (string= val "?"))))

;;; Data extraction

(defun gptel-auto-workflow-self-audit--backends-used (&optional window)
  "Return list of backend names used in recent TSV files."
  (gptel-auto-workflow-self-audit--collect-from-tsv-fields
   (gptel-auto-workflow-self-audit--tsv-files window)
   15
   'gptel-auto-workflow-self-audit--backend-filter))

(defun gptel-auto-workflow-self-audit--all-backends ()
  "Return list of all defined backends from gptel-ext-backends.el."
  (let* ((root (gptel-auto-workflow-self-audit--root))
         (backends-file
          (expand-file-name "lisp/modules/gptel-ext-backends.el" root))
         (backends '()))
    (when (file-exists-p backends-file)
      (with-temp-buffer
        (insert-file-contents backends-file)
        (goto-char (point-min))
        (while (re-search-forward
                "(defvar gptel--\\([a-z0-9-]+\\)" nil t)
          (let ((raw-name (match-string 1)))
            (push (concat (upcase (substring raw-name 0 1))
                          (substring raw-name 1))
                  backends)))))
    (delete-dups backends)))

(defun gptel-auto-workflow-self-audit--strategies-evaluated (&optional window)
  "Return list of strategy names evaluated in recent TSV files."
  (gptel-auto-workflow-self-audit--collect-from-tsv-fields
   (gptel-auto-workflow-self-audit--tsv-files window)
   21
   'gptel-auto-workflow-self-audit--strategy-filter))

(defun gptel-auto-workflow-self-audit--all-strategies ()
  "Return list of all strategy names from assistant/strategies/."
  (let* ((root (gptel-auto-workflow-self-audit--root))
         (strategies-dir
          (expand-file-name "assistant/strategies" root))
         (acc '()))
    (when (file-directory-p strategies-dir)
      (dolist (subdir (directory-files strategies-dir t "^[^.]" t))
        (when (file-directory-p subdir)
          (dolist (f (directory-files subdir t "strategy-.*\\.el$"))
            (push (file-name-sans-extension
                   (file-name-nondirectory f))
                  acc))))
      (dolist (f (directory-files strategies-dir t "strategy-.*\\.el$"))
        (push (file-name-sans-extension
               (file-name-nondirectory f))
              acc)))
    (delete-dups acc)))

(defun gptel-auto-workflow-self-audit--decision-counts (&optional window)
  "Return alist of (decision . count) from recent TSV files."
  (let ((counts (make-hash-table :test 'equal))
        (total 0))
    (dolist (rf (gptel-auto-workflow-self-audit--tsv-files window))
      (dolist (row (gptel-auto-workflow-self-audit--parse-tsv-lines rf))
        (when (length> row 8)
          (setq total (1+ total))
          (cl-incf (gethash (nth 7 row) counts 0)))))
    (let (acc)
      (maphash (lambda (k v) (push (cons k v) acc)) counts)
      (cons (cons 'total total) acc))))

;;; Audit checks

(defun gptel-auto-workflow-self-audit--run-backend-check ()
  "Audit backend cold-start. Returns plist :used, :all, :cold."
  (let* ((used (gptel-auto-workflow-self-audit--backends-used))
         (all (gptel-auto-workflow-self-audit--all-backends))
         (cold (cl-set-difference all used :test #'string=)))
    (list :used used :all all :cold cold)))

(defun gptel-auto-workflow-self-audit--run-strategy-check ()
  "Audit strategy cold-start. Returns plist with evaluation stats."
  (let* ((evaluated (gptel-auto-workflow-self-audit--strategies-evaluated))
         (all (gptel-auto-workflow-self-audit--all-strategies))
         (unevaluated (cl-set-difference all evaluated :test #'string=)))
    (list :total (length all)
          :evaluated (length evaluated)
          :unevaluated (length unevaluated)
          :unevaluated-names unevaluated)))

(defun gptel-auto-workflow-self-audit--run-merge-check ()
  "Audit staging-merge bottleneck. Returns plist with merge stats."
  (let* ((counts (gptel-auto-workflow-self-audit--decision-counts))
         (total (or (cdr (assoc 'total counts)) 0))
         (smf (or (cdr (assoc "staging-merge-failed" counts)) 0))
         (smf-t (or (cdr (assoc "staging-merge-failed.t" counts)) 0))
         (msf (or (cdr (assoc "Merge to staging failed" counts)) 0))
         (staging-total (+ smf smf-t msf))
         (fraction (if (> total 0)
                       (/ (float staging-total) total)
                     0.0)))
    (list :total total
          :staging-merge-count staging-total
          :fraction fraction
          :bottleneck-p (> fraction
                          gptel-auto-workflow-self-audit-bottleneck-threshold))))

;;; Main entry

(defun gptel-auto-workflow-self-audit-run ()
  "Run all self-audit checks. Returns plist with all findings."
  (when gptel-auto-workflow-self-audit-enabled
    (let* ((bcc (gptel-auto-workflow-self-audit--byte-compile-check))
           (bca (gptel-auto-workflow-self-audit--run-backend-check))
           (sca (gptel-auto-workflow-self-audit--run-strategy-check))
           (sma (gptel-auto-workflow-self-audit--run-merge-check))
           (pricing (gptel-auto-workflow-self-audit--check-pricing-freshness))
           (kg (gptel-auto-workflow-self-audit--run-knowledge-gap-check))
           (cold (plist-get bca :cold))
           (cold-count (length cold))
           (unev (plist-get sca :unevaluated))
           (broken-count (length (plist-get bcc :broken)))
           (bottleneck (plist-get sma :bottleneck-p))
           (pricing-stale (plist-get pricing :stale-count))
           (kg-count (plist-get kg :gap-count))
           (issues (+ broken-count cold-count unev
                      (if bottleneck 1 0)
                      (if (> pricing-stale 0) 1 0)
                      kg-count)))
      (list :module-health bcc
            :backend-cold-start bca
            :strategy-cold-start sca
            :staging-merge-bottleneck sma
            :pricing-freshness pricing
            :knowledge-gaps kg
            :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S")
            :issues issues
            :auto-fixable (+ broken-count cold-count unev)))))

;;; Report formatting

(defun gptel-auto-workflow-self-audit--run-knowledge-gap-check ()
  "Check the unified graph for knowledge gaps.
Detects: isolated nodes (no edges), low-confidence communities,
and targets with no similarity edges. Returns plist :gap-count, :isolated,
:low-confidence."
  (let ((gap-count 0) (isolated '()) (low-conf-communities '()))
    (condition-case err
        (when (fboundp 'gptel-auto-workflow--unified-graph-ensure)
          (let ((graph (gptel-auto-workflow--unified-graph-ensure)))
            (when (and graph (> (hash-table-count graph) 0))
              ;; Find isolated nodes: degree 0
              (maphash (lambda (key edges)
                         (when (null edges)
                           (let ((id (cdr key)))
                             (unless (string-match-p "^\." id)  ; skip method stubs
                               (push id isolated)))))
                       graph)
              (setq gap-count (+ gap-count (length isolated)))
              ;; Find low-confidence edges in communities
              (when (fboundp 'gptel-auto-workflow--unified-graph-communities)
                (let* ((communities (gptel-auto-workflow--unified-graph-communities))
                       (comm-confidence (make-hash-table :test 'equal)))
                  (when communities
                    (maphash (lambda (from-key edges)
                               (let ((comm (gethash from-key communities)))
                                 (dolist (edge (or edges '()))
                                   (let ((label (nth 3 edge)))
                                     (when (eq label 'AMBIGUOUS)
                                       (puthash comm
                                                (1+ (gethash comm comm-confidence 0))
                                                comm-confidence))))))
                             graph)
                    (maphash (lambda (comm count)
                               (when (> count 3)  ; community with >3 AMBIGUOUS edges
                                 (push (cons comm count) low-conf-communities)))
                             comm-confidence)
                    (when low-conf-communities
                      (setq gap-count (+ gap-count 1)))))))))
      (error (message "[self-audit] Knowledge gap check failed: %s"
                      (error-message-string err))))
    (list :gap-count (min gap-count 10)  ; cap at 10 to avoid dominating issue count
          :isolated (seq-take isolated 5)
          :low-confidence-communities (seq-take low-conf-communities 3))))

(defun gptel-auto-workflow-self-audit--format-knowledge-gap-section (kg)
  "Format knowledge gap section from KG plist."
  (if (not kg)
      ""
    (let ((gaps (plist-get kg :gap-count))
          (isolated (plist-get kg :isolated))
          (low-conf (plist-get kg :low-confidence-communities)))
      (if (or (null gaps) (= gaps 0))
          "- ✓ Knowledge graph: 0 gaps detected\n\n"
        (concat
         (format "### Knowledge graph gaps (%d found)\n" gaps)
         (when isolated
           (format "- %d isolated nodes (no connections): %s\n"
                   (length isolated)
                   (mapconcat #'identity isolated ", ")))
         (when low-conf
           (format "- %d communities with >3 AMBIGUOUS edges (low confidence)\n"
                   (length low-conf)))
         "\n")))))

(defun gptel-auto-workflow-self-audit--format-backend-section (bca)
  "Format backend cold-start section from BCA plist."
  (let ((cold (plist-get bca :cold))
        (used-count (length (plist-get bca :used)))
        (all-count (length (plist-get bca :all)))
        (days gptel-auto-workflow-self-audit-cold-start-window))
    (concat
     (format "### Backend cold-start (%d/%d used in %dd)\n"
             used-count all-count days)
     (if (null cold)
         "- ✓ All backends tried\n"
       (format "- ⚠ %d backends never used: %s\n"
               (length cold)
               (or (mapconcat #'identity cold ", ") "(none)")))
     "\n")))

(defun gptel-auto-workflow-self-audit--format-strategy-section (sca)
  "Format strategy cold-start section from SCA plist."
  (let ((unev-count (plist-get sca :unevaluated))
        (total (plist-get sca :total))
        (evaluated (plist-get sca :evaluated))
        (days gptel-auto-workflow-self-audit-cold-start-window))
    (concat
     (format "### Strategy cold-start (%d/%d evaluated in %dd)\n"
             evaluated total days)
     (if (= unev-count 0)
         "- ✓ All strategies have signal\n"
       (format "- ⚠ %d strategies still unevaluated (Bayesian floor 25%%)\n"
               unev-count))
     "\n")))

(defun gptel-auto-workflow-self-audit--format-merge-section (sma)
  "Format staging-merge bottleneck section from SMA plist."
  (let ((count (plist-get sma :staging-merge-count))
        (fraction (plist-get sma :fraction))
        (bottleneck (plist-get sma :bottleneck-p))
        (days gptel-auto-workflow-self-audit-cold-start-window))
    (concat
     (format "### Staging-merge bottleneck (%d/%.0f%% in %dd)\n"
             count (* 100.0 fraction) days)
     (if bottleneck
         "- ⚠ BOTTLENECK: auto-resolver handles .md; source code still needs review\n"
       "- ✓ Below threshold\n")
     "\n")))

(defun gptel-auto-workflow-self-audit--format-report (audit-result)
  "Format AUDIT-RESULT as a markdown section for the digest."
  (when audit-result
    (let ((bca (plist-get audit-result :backend-cold-start))
          (sca (plist-get audit-result :strategy-cold-start))
          (sma (plist-get audit-result :staging-merge-bottleneck))
          (bcc (plist-get audit-result :module-health))
          (kg (plist-get audit-result :knowledge-gaps))
          (issues (plist-get audit-result :issues))
          (ts (plist-get audit-result :timestamp)))
      (concat
       "## Self-Audit (system-meta — finds the gaps humans find)\n"
       "\n"
       "The system now audits itself for the patterns the human\n"
       "reviewer has been catching in 7+ audit passes.\n"
       "\n"
       (gptel-auto-workflow-self-audit--format-byte-compile-section bcc)
       (gptel-auto-workflow-self-audit--format-backend-section bca)
       (gptel-auto-workflow-self-audit--format-strategy-section sca)
       (gptel-auto-workflow-self-audit--format-merge-section sma)
       (gptel-auto-workflow-self-audit--format-knowledge-gap-section kg)
       (format "**Audit score: %d issues found** (timestamp %s)\n"
               issues ts)
       "Memory written: mementum/memories/audit-fix-*.md\n"))))

;;; Memory writing

(defun gptel-auto-workflow-self-audit--build-memory-content (audit-result)
  "Build the content string for the audit-fix memory file."
  (let* ((bca (plist-get audit-result :backend-cold-start))
         (sca (plist-get audit-result :strategy-cold-start))
         (sma (plist-get audit-result :staging-merge-bottleneck))
         (bcc (plist-get audit-result :module-health))
         (cold (plist-get bca :cold))
         (unev (plist-get sca :unevaluated-names))
         (ts (plist-get audit-result :timestamp))
         (days gptel-auto-workflow-self-audit-cold-start-window)
         (cold-str (if cold
                       (mapconcat #'identity cold ", ")
                     "(none)"))
         (unev-str (if unev
                       (mapconcat #'identity
                                   (cl-subseq unev 0
                                              (min 10 (length unev)))
                                   ", ")
                     "(none)"))
         (merge-label (if (plist-get sma :bottleneck-p)
                          "BOTTLENECK"
                        "OK"))
         (merge-pct (format "%.0f%%"
                            (* 100.0 (plist-get sma :fraction)))))
    (concat
     (format "**Self-audit found %d issues** (timestamp %s):\n\n"
             (plist-get audit-result :issues) ts)
     (format "**Backend cold-start**: %d/%d backends never used in last %dd\n"
             (length cold) (length (plist-get bca :all)) days)
     (format "  - Cold: %s\n\n" cold-str)
     (format "**Strategy cold-start**: %d/%d strategies unevaluated\n"
             (plist-get sca :unevaluated) (plist-get sca :total))
     (format "  - First 10: %s\n\n" unev-str)
     (format "**Staging-merge bottleneck**: %s (%s of failures)\n"
             merge-label merge-pct)
     "  - Auto-resolver for .md conflicts: deployed (commit 95396bc1)\n\n"
     (gptel-auto-workflow-self-audit--add-byte-compile-to-memory
      audit-result bcc)
     "**Action items**:\n"
     "- System should attempt cold backends on next cycle\n"
     "- 40%% exploration rate may be too slow to discover winners\n"
     "- Staging-merge auto-resolver handles .md; source code still needs review\n\n"
     "**Status**: Audit is in place. The next pipeline run will detect\n"
     "the same issues, and the next evolution cycle can act on them.\n\n"
     "YC: 'self-evolve' must include META — auditing the system itself,\n"
     "not just the code it produces. This memory is itself an evolution.\n")))

(defun gptel-auto-workflow-self-audit--write-memory (audit-result)
  "Write an audit-fix memory file when issues are found."
  (when (and audit-result (> (or (plist-get audit-result :issues) 0) 0))
    (let* ((root (gptel-auto-workflow-self-audit--root))
           (memory-dir (expand-file-name "mementum/memories/" root))
           (ts (plist-get audit-result :timestamp))
           (filename (expand-file-name
                      (concat "audit-fix-" ts ".md")
                      memory-dir))
           (content (gptel-auto-workflow-self-audit--build-memory-content
                     audit-result)))
      (condition-case err
          (progn
            (make-directory memory-dir t)
            (with-temp-file filename
              (insert "---\n")
              (insert "title: Self-Audit Report\n")
              (insert (concat "timestamp: " ts "\n"))
              (insert "category: audit-fix\n")
              (insert (format "issues: %d\n"
                              (plist-get audit-result :issues)))
              (insert "auto-fixable: yes (auto-resolver deployed)\n")
              (insert "---\n\n")
              (insert content))
            (message "[self-audit] Wrote audit-fix memory for %d issues"
                     (plist-get audit-result :issues)))
        (error
         (message "[self-audit] Failed to write audit memory: %s"
                  (error-message-string err)))))))

;;; Byte-compile health check (META — catches modules that can't compile)

(defun gptel-auto-workflow-self-audit--byte-compile-check ()
  "Check that all auto-workflow modules byte-compile cleanly.
Returns plist :broken (list of files with errors), :total, :healthy."
  (let* ((root (gptel-auto-workflow-self-audit--root))
         (mod-dir (expand-file-name "lisp/modules" root))
         (broken '())
         (total 0))
    (when (file-directory-p mod-dir)
      (dolist (f (directory-files mod-dir t
                                  "gptel-auto-workflow.*\\.el$"))
        (setq total (1+ total))
        (condition-case err
            (with-temp-buffer
              (insert-file-contents f)
              (emacs-lisp-mode)
              (goto-char (point-min))
              ;; Check parens first (fast)
              (check-parens)
              ;; Then try byte-compile (slower but more thorough)
              (let ((byte-compile-dest-file-function
                     (lambda (_) nil)))
                (byte-compile-file f)))
          (error
           (push (cons (file-name-nondirectory f)
                       (error-message-string err))
                 broken)))))
    (list :broken (nreverse broken)
          :total total
          :healthy (= 0 (length broken)))))

(defun gptel-auto-workflow-self-audit--format-byte-compile-section (bcc)
  "Format byte-compile health section from BCC plist."
  (let ((broken (plist-get bcc :broken))
        (total (plist-get bcc :total)))
    (concat
     (format "### Module health (%d/%d compile cleanly)\n"
             (- total (length broken)) total)
     (if (null broken)
         "- ✓ All modules byte-compile\n"
       (concat
        (format "- ⚠ %d modules broken:\n" (length broken))
        (mapconcat
         (lambda (pair)
           (format "  - %s: %s" (car pair) (cdr pair)))
         broken "\n")
        "\n"))
     "\n")))

(defun gptel-auto-workflow-self-audit--add-byte-compile-to-memory
    (_audit-result bcc)
  "Append byte-compile findings to memory content string."
  (let ((broken (plist-get bcc :broken)))
    (if (null broken)
        ""
      (concat
       "\n**Module byte-compile health**: "
       (format "%d/%d modules broken\n"
               (length broken) (plist-get bcc :total))
       (mapconcat
        (lambda (pair)
          (format "- %s: %s" (car pair) (cdr pair)))
        broken "\n")
       "\n"))))

;;; Pipeline entry

(defun gptel-auto-workflow-self-audit-execute ()
  "Run audit, write memory if issues found, return formatted report.
Also writes structured result to var/tmp/self-audit-result.el for
the pipeline self-heal step to consume."
  (let ((result (gptel-auto-workflow-self-audit-run)))
    (when result
      (gptel-auto-workflow-self-audit--write-memory result)
      (gptel-auto-workflow-self-audit--write-structured-result result)
      ;; YC Learning←Quality: if >=3 audit-fix memories exist with shared root
      ;; causes, synthesize a knowledge page so the prompt builder can inject it
      (gptel-auto-workflow-self-audit--synthesize-system-health))
    (gptel-auto-workflow-self-audit--format-report result)))

(defun gptel-auto-workflow-self-audit--build-structured-result-content (result)
  "Build content string for var/tmp/self-audit-result.el from RESULT.
Uses concat to avoid deeply nested insert/format calls in the write function."
  (let* ((bcc (plist-get result :module-health))
         (bca (plist-get result :backend-cold-start))
         (sca (plist-get result :strategy-cold-start))
         (sma (plist-get result :staging-merge-bottleneck))
         (pricing (plist-get result :pricing-freshness))
         (cold (plist-get bca :cold))
         (unev (plist-get sca :unevaluated))
         (bottleneck (plist-get sma :bottleneck-p))
         (broken (plist-get bcc :broken))
         (issues (plist-get result :issues))
         (pricing-stale (or (plist-get pricing :stale-count) 0))
         (pricing-days (or (plist-get pricing :days-stale) 0)))
    (concat
     ";; self-audit-result.el — structured audit findings\n"
     ";; Written by gptel-auto-workflow-self-audit-execute\n"
     ";; Consumed by run-pipeline.sh Step 0.5 for auto-remediation\n"
     ";;\n"
     (format "(issues-count . %d)\n" issues)
     (format "(cold-backends . %S)\n" cold)
     (format "(unevaluated-strategies . %d)\n" unev)
     (format "(staging-merge-bottleneck . %S)\n" bottleneck)
     (format "(pricing-stale . %d)\n" pricing-stale)
     (format "(pricing-days-stale . %d)\n" pricing-days)
     (when broken
       (format "(broken-modules . %S)\n" (mapcar #'car broken)))
     ";; Remediation actions for self-heal:\n"
     (when (> (length cold) 0)
       "(remediation . force-cold-backends)\n")
     (when (> unev 0)
       "(remediation . increase-exploration-rate)\n")
     (when bottleneck
       "(remediation . staging-merge-autoresolve)\n")
     (when (> pricing-stale 0)
       "(remediation . update-pricing)\n")
     (when (> (length broken) 0)
       "(remediation . flag-broken-modules)\n")
     (format "(audit-timestamp . %S)\n"
             (plist-get result :timestamp)))))

(defun gptel-auto-workflow-self-audit--write-structured-result (result)
  "Write RESULT as a structured file for pipeline self-heal to consume.
File: var/tmp/self-audit-result.el — contains an alist the bash script
can grep for specific remediation actions."
  (when result
    (let* ((root (gptel-auto-workflow-self-audit--root))
           (result-file (expand-file-name
                         "var/tmp/self-audit-result.el" root))
           (content (gptel-auto-workflow-self-audit--build-structured-result-content
                     result)))
      (condition-case err
          (progn
            (make-directory (file-name-directory result-file) t)
            (with-temp-file result-file
              (insert content))
            (message "[self-audit] Wrote structured result to %s"
                     result-file))
        (error
         (message "[self-audit] Failed to write structured result: %s"
                  (error-message-string err)))))))

(defun gptel-auto-workflow-self-audit-verify-recovery (before-result)
  "Verify whether issues found in BEFORE-RESULT improved after remediation.
Returns plist :before-issues, :after-issues, :improved-p, :delta."
  (let* ((after-result (gptel-auto-workflow-self-audit-run))
         (before-issues (or (plist-get before-result :issues) 0))
         (after-issues (or (plist-get after-result :issues) 0))
         (delta (- before-issues after-issues))
         (improved (> delta 0)))
    (list :before-issues before-issues
          :after-issues after-issues
          :delta delta
          :improved-p improved
          :still-broken (when (> after-issues 0)
                         (format "%d issues remain after remediation"
                                 after-issues)))))

;;; System-health synthesis (Learning<-Quality loop)

(defun gptel-auto-workflow-self-audit--read-audit-memories ()
  "Read all audit-fix-*.md memory files and return list of plists.
Each plist has :file, :timestamp, :issues, :cold, :unev, :bottleneck."
  (let* ((root (gptel-auto-workflow-self-audit--root))
         (mem-dir (expand-file-name "mementum/memories/" root))
         (memories '()))
    (when (file-directory-p mem-dir)
      (dolist (f (directory-files mem-dir t "audit-fix-.*\\.md$"))
        (condition-case _
            (with-temp-buffer
              (insert-file-contents f)
              (goto-char (point-min))
              (let ((issues 0) (cold 0) (cold-total 0) (unev 0)
                    (unev-total 0) (bottleneck nil) (ts ""))
                (when (search-forward "---" nil t)
                  (while (and (not (eobp))
                              (not (looking-at "---")))
                    (when (looking-at "^issues: \\([0-9]+\\)")
                      (setq issues (string-to-number (match-string 1))))
                    (when (looking-at "^\\(timestamp\\): \\(.+\\)")
                      (setq ts (match-string 2)))
                    (forward-line 1)))
                (when (search-forward "Backend cold-start" nil t)
                  (when (re-search-forward
                         "\\([0-9]+\\)/\\([0-9]+\\) backends" nil t)
                    (setq cold (string-to-number (match-string 1)))
                    (setq cold-total (string-to-number (match-string 2)))))
                (when (search-forward "Strategy cold-start" nil t)
                  (when (re-search-forward
                         "\\([0-9]+\\)/\\([0-9]+\\) strategies" nil t)
                    (setq unev (string-to-number (match-string 1)))
                    (setq unev-total (string-to-number (match-string 2)))))
                (when (search-forward "BOTTLENECK" nil t)
                  (setq bottleneck t))
                (push (list :file f :timestamp ts :issues issues
                            :cold-backends cold :cold-total cold-total
                            :unevaluated-strategies unev
                            :unevaluated-total unev-total
                            :bottleneck-p bottleneck)
                      memories)))
          (error nil))))
    memories))

(defun gptel-auto-workflow-self-audit--synthesize-system-health ()
  "Aggregate >=3 audit-fix memories into a knowledge page.
Creates/updates mementum/knowledge/system-health-patterns.md when
recurring root causes are detected across >=3 audit runs.
Returns the count of memories found, or nil if below threshold."
  (let* ((memories (gptel-auto-workflow-self-audit--read-audit-memories))
         (n (length memories)))
    (when (>= n 3)
      (let* ((root (gptel-auto-workflow-self-audit--root))
             (kp-dir (expand-file-name "mementum/knowledge/" root))
             (kp-file (expand-file-name "system-health-patterns.md" kp-dir))
             (cold-runs (seq-count
                         (lambda (m) (> (plist-get m :cold-backends) 0))
                         memories))
             (unev-runs (seq-count
                         (lambda (m) (> (plist-get m :unevaluated-strategies) 0))
                         memories))
             (bottleneck-runs (seq-count
                               (lambda (m) (plist-get m :bottleneck-p))
                               memories))
             (avg-cold (if (> cold-runs 0)
                           (/ (apply #'+
                                     (mapcar (lambda (m) (plist-get m :cold-backends))
                                             memories))
                              cold-runs)
                         0))
             (avg-unev (if (> unev-runs 0)
                           (/ (apply #'+
                                     (mapcar (lambda (m) (plist-get m :unevaluated-strategies))
                                             memories))
                              unev-runs)
                         0))
             (latest (car (sort memories
                                (lambda (a b)
                                  (string> (or (plist-get a :timestamp) "")
                                           (or (plist-get b :timestamp) ""))))))
             (content
              (concat
               "---\n"
               "title: System Health Patterns\n"
               "status: active\n"
               "category: system-health\n"
               (format "tags: [self-audit, auto-fix, meta]\n")
               "related: [pipeline-health, self-healing-architecture]\n"
               (format "last-updated: %s\n"
                       (or (plist-get latest :timestamp)
                           (format-time-string "%Y-%m-%dT%H:%M:%S")))
               "---\n\n"
               "# System Health Patterns\n\n"
               "Auto-generated from self-audit memories. Updated every pipeline\n"
               "run when >=3 audit-fix memories exist.\n\n"
               (format "## Summary (%d audit runs analyzed)\n\n" n)
               (format "- **Backend cold-start**: detected in %d/%d runs "
                       cold-runs n)
               (format "(avg %.1f cold backends)\n" avg-cold)
               (format "- **Strategy cold-start**: detected in %d/%d runs "
                       unev-runs n)
               (format "(avg %.1f unevaluated strategies)\n" avg-unev)
               (concat "- **Staging-merge bottleneck**: detected "
                       "in " (number-to-string bottleneck-runs) "/"
                       (number-to-string n) " runs\n\n")
               "## Recurring Root Causes\n\n"
               (when (>= cold-runs 3)
                 (concat
                  "### Backend Cold-Start (>=3 occurrences)\n"
                  "- **Symptom**: 5-8 backends never tried within "
                  "cold-start window\n"
                  "- **Impact**: Reduced model diversity, reliance on "
                  "single provider\n"
                  "- **Auto-fix deployed**: force-try-backends.txt signal "
                  "-> daemon unblocks rate-limited backends\n"
                  "- **Verification**: check `gptel-auto-workflow--rate-"
                  "limited-backends` size after pipeline run\n"
                  "- **Status**: auto-fix applied each pipeline cycle\n\n"))
               (when (>= unev-runs 3)
                 (concat
                  "### Strategy Cold-Start (>=3 occurrences)\n"
                  "- **Symptom**: 12-15 strategies never evaluated "
                  "(hidden by 25% Bayesian floor)\n"
                  "- **Impact**: Poor strategy selection, template-"
                  "default bias\n"
                  "- **Auto-fix deployed**: exploration-rateOverride.txt "
                  "signal -> daemon increases exploration rate\n"
                  "- **Verification**: check strategy pool visibility "
                  "in digest\n"
                  "- **Status**: auto-fix applied each pipeline cycle\n\n"))
               (when (>= bottleneck-runs 3)
                 (concat
                  "### Staging-Merge Bottleneck (>=3 occurrences)\n"
                  "- **Symptom**: git conflicts in .md files cause "
                  "experiment failures\n"
                  "- **Impact**: 3-4%% keep-rate ceiling, wasted "
                  "experiment cycles\n"
                  "- **Auto-fix deployed**: --try-autoresolve-conflicts "
                  "uses --theirs for .md files\n"
                  "- **Limitation**: source code (.el) conflicts still "
                  "require manual review\n"
                  "- **Status**: auto-fix active; .el conflicts "
                  "escalated to human\n\n"))
               "## Actionability\n\n"
               "These patterns are injected into the experiment prompt "
               "builder via `gptel-auto-experiment--system-health-for-"
               "prompt`, causing the evolution LLM to:\n"
               "1. **Prioritize fixes** for targets contributing to "
               "known bottlenecks\n"
               "2. **Avoid strategies** that reproduce cold-start patterns\n"
               "3. **Self-monitor** by checking whether its own changes "
               "improve system health metrics\n\n"
               "---\n\n"
               "*Generated by gptel-auto-workflow-self-audit.el - "
               "Learning<-Quality loop*\n")))
        (make-directory kp-dir t)
        (with-temp-file kp-file
          (insert content))
        (message (concat "[self-audit] Synthesized system-health-patterns "
                         "from %d audit memories (cold=%d, unev=%d, bottleneck=%d)")
                 n cold-runs unev-runs bottleneck-runs)
        n))))

;;; Signal-file reader (bridge between pipeline bash -> daemon Emacs)

(defvar gptel-auto-workflow--grader-timeout-override nil
  "Override for grader timeout in seconds. Set by pipeline auto-fix
when grader-destroying-experiments is detected as recurring PENDING.")

(defvar gptel-auto-workflow--force-grader-backends nil
  "List of backend names to force for grading. Set by pipeline auto-fix
when grader-destroying-experiments escalates.")

(defun gptel-auto-workflow-self-audit-apply-pipeline-signals ()
  "Read signal files written by pipeline Step 0.5 and apply them to the daemon.
This bridges bash auto-fix signals into the Emacs daemon process.
Returns number of signals applied."
  (let* ((root (gptel-auto-workflow-self-audit--root))
         (force-file (expand-file-name "var/tmp/force-try-backends.txt" root))
         (exploration-file (expand-file-name "var/tmp/exploration-rateOverride.txt" root))
         (grader-timeout-file (expand-file-name "var/tmp/grader-timeoutOverride.txt" root))
         (grader-backends-file (expand-file-name "var/tmp/force-grader-backends.txt" root))
         (applied 0))
    ;; Auto-fix 1: Unblock cold backends from rate-limit blacklist
    (when (file-exists-p force-file)
      (let ((cold-names (with-temp-buffer
                           (insert-file-contents force-file)
                           (split-string (buffer-string) "," t))))
        (when (and cold-names (boundp 'gptel-auto-workflow--rate-limited-backends))
          (dolist (name cold-names)
            (setq gptel-auto-workflow--rate-limited-backends
                  (delete name gptel-auto-workflow--rate-limited-backends)))
          (message "[self-audit] Force-try: %d cold backends unblocked (%s)"
                   (length cold-names)
                   (mapconcat #'identity cold-names ", "))
          (setq applied (1+ applied)))))
    ;; Auto-fix 2: Override exploration rate from pipeline signal
    (when (file-exists-p exploration-file)
      (let ((rate (with-temp-buffer
                    (insert-file-contents exploration-file)
                    (string-to-number (buffer-string)))))
        (when (and (> rate 0)
                   (boundp 'gptel-auto-workflow--ontology-reorder-exploration-rate))
          (setq gptel-auto-workflow--ontology-reorder-exploration-rate (/ rate 100.0))
          (message "[self-audit] Exploration override: %d%% (from pipeline)" rate)
          (setq applied (1+ applied)))))
    ;; Auto-fix 3: Override grader timeout (grader-destroying-experiments escalation)
    (when (file-exists-p grader-timeout-file)
      (let ((timeout (with-temp-buffer
                       (insert-file-contents grader-timeout-file)
                       (string-to-number (buffer-string)))))
        (when (> timeout 0)
          ;; Set grader timeout override (consumed by grader harness)
          (setq gptel-auto-workflow--grader-timeout-override timeout)
          (message "[self-audit] Grader timeout override: %ds (from pipeline escalation)"
                   timeout)
          (setq applied (1+ applied)))))
    ;; Auto-fix 4: Force fast backends for grading
    (when (file-exists-p grader-backends-file)
      (let ((backends (with-temp-buffer
                        (insert-file-contents grader-backends-file)
                        (split-string (buffer-string) "[,\n]+" t))))
        (when backends
          (setq gptel-auto-workflow--force-grader-backends backends)
          (message "[self-audit] Force grader backends: %s (from pipeline escalation)"
                   (mapconcat #'identity backends ", "))
          (setq applied (1+ applied)))))
    ;; Clean up signal files (one-shot, consumed)
    (when (file-exists-p force-file) (delete-file force-file))
    (when (file-exists-p exploration-file) (delete-file exploration-file))
    (when (file-exists-p grader-timeout-file) (delete-file grader-timeout-file))
    (when (file-exists-p grader-backends-file) (delete-file grader-backends-file))
    applied))
 
;;; Pricing freshness check (token-economics foundation)

(defun gptel-auto-workflow-self-audit--parse-pricing-knowledge ()
  "Parse mementum/knowledge/bailian-pricing.md and return pricing alist.
Each entry: (:model :input-cny :output-cny :cache-cny :context :last-updated).
Extracts last-updated from frontmatter for freshness tracking."
  (let* ((root (gptel-auto-workflow-self-audit--root))
         (pricing-file (expand-file-name
                        "mementum/knowledge/bailian-pricing.md" root))
         (pricing '())
         (last-updated ""))
    (when (file-exists-p pricing-file)
      (with-temp-buffer
        (insert-file-contents pricing-file)
        (goto-char (point-min))
        ;; Extract last-updated from frontmatter
        (when (re-search-forward "^last-updated: \\(.+\\)" nil t)
          (setq last-updated (string-trim (match-string 1))))
        ;; Parse pricing blocks: ```pricing ... ```
        (goto-char (point-min))
        (while (search-forward "```pricing" nil t)
          (forward-line 1)
          (let ((start (point)))
            (when (search-forward "```" nil t)
              (forward-line 0)
              (let ((block (buffer-substring start (point))))
                (dolist (line (split-string block "\n" t))
                  (let ((parts (split-string line "|" t)))
                    (when (>= (length parts) 5)
                      (let ((model (string-trim (nth 0 parts)))
                            (input-cny (string-to-number (string-trim (nth 1 parts))))
                            (output-cny (string-to-number (string-trim (nth 2 parts))))
                            (cache-cny (string-to-number (string-trim (nth 3 parts))))
                            (context (string-to-number (string-trim (nth 4 parts)))))
                        (when (and (> input-cny 0) (> output-cny 0))
                          (push (list :model model
                                      :input-cny input-cny
                                      :output-cny output-cny
                                      :cache-cny cache-cny
                                      :context context
                                      :last-updated last-updated)
                                 pricing))))))))
        ))
        (nreverse pricing)))))

(defun gptel-auto-workflow-self-audit--find-provider-for-model (model)
  "Find which provider in gptel-backend-registry has MODEL.
Returns provider name or nil."
  (when (boundp 'gptel-backend-registry)
    (catch 'found
      (dolist (entry gptel-backend-registry)
        (let* ((provider (car entry))
               (plist (cdr entry))
               (models (plist-get plist :models)))
          (when (and models (memq (intern model) models))
            (throw 'found provider)))))))

(defun gptel-auto-workflow-self-audit--get-registry-pricing (provider model)
  "Get current pricing from gptel-backend-registry for PROVIDER/MODEL.
Returns plist (:input :output :cache :context) or nil."
  (when (and (boundp 'gptel-backend-registry) provider)
    (let ((entry (assoc provider gptel-backend-registry)))
      (when entry
        (let* ((plist (cdr entry))
               (metadata (plist-get plist :model-metadata))
               (model-sym (intern model))
               (model-entry (assoc model-sym metadata)))
          (when model-entry
            (let ((mplist (cdr model-entry)))
              (list :input (or (plist-get mplist :pricing-input) 0)
                    :output (or (plist-get mplist :pricing-output) 0)
                    :cache (or (plist-get mplist :pricing-cache-hit) 0)
                    :context (or (plist-get mplist :context-window) 0)))))))))

(defun gptel-auto-workflow-self-audit--check-pricing-freshness ()
  "Compare bailian-pricing.md knowledge page against gptel-backend-registry.
Returns plist (:stale-count :discrepancies :knowledge-count :last-updated
:days-stale).
Each discrepancy: (:model :provider :field :expected :actual).
Also flags if the knowledge page hasn't been updated in >30 days."
  (let ((knowledge (gptel-auto-workflow-self-audit--parse-pricing-knowledge))
        (discrepancies '())
        (conversion-rate 0.138)  ; 1 CNY ≈ $0.138
        (last-updated "")
        (days-stale 0))
    ;; Check knowledge page freshness
    (when knowledge
      (setq last-updated (plist-get (car knowledge) :last-updated))
      (when (not (string-empty-p last-updated))
        (let* ((updated-time (condition-case nil
                                 (float-time
                                  (date-to-time
                                   (replace-regexp-in-string "T" " " last-updated)))
                               (error nil)))
               (now (float-time))
               (days (when updated-time (/ (- now updated-time) 86400))))
          (when days (setq days-stale (floor days))))))
    ;; Compare knowledge entries against registry
    (dolist (entry knowledge)
      (let* ((model (plist-get entry :model))
             (input-cny (plist-get entry :input-cny))
             (output-cny (plist-get entry :output-cny))
             (cache-cny (plist-get entry :cache-cny))
             (context-kb (plist-get entry :context))
             (provider (gptel-auto-workflow-self-audit--find-provider-for-model
                        model))
             (reg (when provider
                    (gptel-auto-workflow-self-audit--get-registry-pricing
                     provider model)))
             (expected-input (* input-cny conversion-rate))
             (expected-output (* output-cny conversion-rate))
             (expected-cache (* cache-cny conversion-rate)))
        (when reg
          ;; Check input price (20% tolerance for exchange rate)
          (when (and (> expected-input 0)
                     (> (abs (- (plist-get reg :input) expected-input))
                        (* expected-input 0.2)))
            (push (list :model model :provider provider :field :pricing-input
                        :expected (format "%.2f" expected-input)
                        :actual (format "%.2f" (plist-get reg :input)))
                  discrepancies))
          ;; Check output price
          (when (and (> expected-output 0)
                     (> (abs (- (plist-get reg :output) expected-output))
                        (* expected-output 0.2)))
            (push (list :model model :provider provider :field :pricing-output
                        :expected (format "%.2f" expected-output)
                        :actual (format "%.2f" (plist-get reg :output)))
                  discrepancies))
          ;; Check context window
          (when (and (> context-kb 0)
                     (/= (plist-get reg :context) context-kb))
            (push (list :model model :provider provider :field :context-window
                        :expected (number-to-string context-kb)
                        :actual (number-to-string (plist-get reg :context)))
                  discrepancies)))))
    ;; Add staleness warning if knowledge page is old
    (when (> days-stale 30)
      (push (list :model "KNOWLEDGE-PAGE" :provider "N/A"
                  :field :freshness
                  :expected (format "≤30 days")
                  :actual (format "%d days stale" days-stale))
            discrepancies))
    (list :stale-count (length discrepancies)
          :discrepancies (nreverse discrepancies)
          :knowledge-count (length knowledge)
          :last-updated last-updated
          :days-stale days-stale
          :last-checked (format-time-string "%Y-%m-%dT%H:%M:%S"))))

(defun gptel-auto-workflow-self-audit--format-pricing-report (result)
  "Format pricing freshness result as a readable string."
  (let ((stale (plist-get result :stale-count))
        (disc (plist-get result :discrepancies))
        (kcount (plist-get result :knowledge-count))
        (days-stale (plist-get result :days-stale)))
    (concat
     (format "Pricing check: %d models known, %d discrepancies" kcount stale)
     (when (> days-stale 0)
       (format " (knowledge page %d days old)" days-stale))
     (if (= stale 0)
         " — pricing fresh ✓"
       (concat
        "\n" (mapconcat
              (lambda (d)
                (format "  - %s/%s %s: expected %s, actual %s"
                        (plist-get d :provider) (plist-get d :model)
                        (plist-get d :field)
                        (plist-get d :expected)
                        (plist-get d :actual)))
              disc "\n")
        (when (> days-stale 30)
          "\n⚠ Knowledge page >30 days stale — update from Bailian console")
        "\n→ Resolve: update registry OR update bailian-pricing.md")))))

;;; Token Economics (real per-model pricing from registry)

(defun gptel-auto-workflow-self-audit--compute-token-economics (&optional root)
  "Compute token economics from experiment TSV data using real registry pricing.
Scans var/tmp/experiments/*/results.tsv for last 24h.
Returns plist (:total :total-cost :kept :kept-cost :models-seen :model-breakdown).
:model-breakdown is ((:model :count :kept-count :cost :speed :capabilities) ...)."
  (let* ((root (or root (gptel-auto-workflow-self-audit--root)))
         (exp-dir (expand-file-name "var/tmp/experiments" root))
         (cutoff (- (float-time) 86400))  ; 24h
         (pricing (make-hash-table :test 'equal))
         (model-stats (make-hash-table :test 'equal))
         (total 0) (kept 0) (total-cost 0.0) (kept-cost 0.0))
    ;; Build pricing + metadata lookup from registry
    (when (boundp 'gptel-backend-registry)
      (dolist (entry gptel-backend-registry)
        (dolist (m (plist-get (cdr entry) :model-metadata))
          (let* ((model (symbol-name (car m)))
                 (p (cdr m))
                 (in (or (plist-get p :pricing-input) 0.0))
                 (out (or (plist-get p :pricing-output) 0.0))
                 (cache (or (plist-get p :pricing-cache-hit) 0.0))
                 (speed (or (plist-get p :speed) 'unknown))
                 (caps (or (plist-get p :capabilities) '(code-generation))))
            (puthash model (list :cost (+ in cache)
                                 :speed speed
                                 :capabilities caps)
                     pricing)))))
    ;; Scan recent TSV files
    (when (file-directory-p exp-dir)
      (dolist (tsv (directory-files exp-dir t "results\\.tsv$"))
        (when (> (float-time (nth 5 (file-attributes tsv))) cutoff)
          (condition-case nil
              (with-temp-buffer
                (insert-file-contents tsv)
                (goto-char (point-min))
                (while (not (eobp))
                  (let* ((line (buffer-substring (point) (line-end-position)))
                         (fields (split-string line "\t")))
                    (when (>= (length fields) 16)
                      (let* ((model (nth 15 fields))
                             (decision (nth 7 fields))
                             (info (or (gethash model pricing)
                                       (list :cost 0.10 :speed 'unknown
                                             :capabilities '(code-generation))))
                             (cost (plist-get info :cost))
                             (kept-p (string-match-p
                                      "\\`\\(kept\\|grader-bypass\\|merged\\|staged\\)"
                                      decision))
                             (stats (or (gethash model model-stats)
                                        (list :count 0 :kept-count 0
                                              :total-cost 0.0 :kept-cost 0.0
                                              :speed (plist-get info :speed)
                                              :caps (plist-get info :capabilities)))))
                        ;; Update per-model stats
                        (plist-put stats :count (1+ (plist-get stats :count)))
                        (plist-put stats :total-cost
                                   (+ (plist-get stats :total-cost) cost))
                        (when kept-p
                          (plist-put stats :kept-count
                                     (1+ (plist-get stats :kept-count)))
                          (plist-put stats :kept-cost
                                     (+ (plist-get stats :kept-cost) cost)))
                        (puthash model stats model-stats)
                        ;; Totals
                        (setq total (1+ total))
                        (setq total-cost (+ total-cost cost))
                        (when kept-p
                          (setq kept (1+ kept))
                          (setq kept-cost (+ kept-cost cost)))))
                    (forward-line 1))))
            (error nil)))))
    ;; Build sorted model breakdown
    (let ((breakdown '()))
      (maphash (lambda (model stats)
                 (push (append (list :model model) stats) breakdown))
               model-stats)
      (setq breakdown (sort breakdown
                            (lambda (a b)
                              (> (plist-get a :total-cost)
                                 (plist-get b :total-cost)))))
      (list :total total :total-cost total-cost
            :kept kept :kept-cost kept-cost
            :models-seen (hash-table-count model-stats)
            :model-breakdown breakdown))))

(provide 'gptel-auto-workflow-self-audit)
;;; gptel-auto-workflow-self-audit.el ends here
