;;; gptel-auto-workflow-research-integration.el --- Research strategy integration -*- lexical-binding: t; -*-

;; Integrates AutoTTS, AutoGo, Ontology, Self-evolve, and Meta-harness
;; into the research strategy pipeline.

;;; Code:

(require 'cl-lib)
(require 'json)

(declare-function gptel-auto-workflow--parse-all-results "gptel-auto-workflow-evolution" ())
(declare-function gptel-auto-workflow--generate-experiment-ontology "gptel-auto-workflow-evolution" ())
(declare-function gptel-auto-workflow--worktree-base-root "gptel-tools-agent" ())
(declare-function gptel-auto-workflow--benchmark-research-strategy "gptel-auto-workflow-research-benchmark" (strategy topic callback))

;; ─── AutoTTS Trace Parsing for Research Sessions ───

(defun gptel-auto-workflow--parse-research-autotts-traces (output)
  "Parse ===RESULT=== JSON blocks from research OUTPUT.
Returns list of trace plists with :phase, :confidence, :tokens, :decision.
AutoTTS: research sessions emit structured trace blocks for token-optimal stopping."
  ;; ASSUMPTION: output is a string; nil/empty means no traces to parse
  ;; EDGE CASE: nil or empty string returns empty list immediately
  (if (string-empty-p (or output ""))
      nil
    (let ((traces nil)
          (pos 0))
      (while (string-match "===RESULT===" output pos)
        ;; Save match-end BEFORE json-read-from-string clobbers it
        (let ((result-end (match-end 0))
              (brace-pos (string-match "{" output (match-end 0))))
          (when brace-pos
            (let* ((json-object-type 'plist)
                   (json-array-type 'list)
                   (json-key-type 'keyword))
              (condition-case nil
                  (let ((trace (json-read-from-string (substring output brace-pos))))
                    (when (plist-get trace :phase)
                      (push trace traces)))
                (error nil))))
          ;; Always advance pos to prevent infinite loop on malformed input
          (setq pos result-end)))
      (nreverse traces))))

(defun gptel-auto-workflow--research-autotts-stop-early-p (traces)
  "Return non-nil if research should STOP early based on TRACE analysis.
AutoTTS: stop when confidence > 0.7 AND 2+ insights found (saves tokens)."
  (when traces
    (let ((latest (car (last traces)))
          (insights (cl-count-if (lambda (t_)
                                   (and (plist-get t_ :insights_count)
                                        (> (plist-get t_ :insights_count) 0)))
                                 traces)))
      (and (> (or (plist-get latest :confidence) 0) 0.7)
           (>= insights 2)))))

;; ─── AutoGo: Category Champions for Research Strategies ───

(defvar gptel-auto-workflow--research-strategy-champions nil
  "Alist of (category . (strategy . keep-rate)) for research strategies.
AutoGo champion league applied to research: best strategy per topic category.")

(defun gptel-auto-workflow--research-category-for-topic (topic)
  "Classify research TOPIC into ontology category.
Returns :programming, :agentic, :tool-calls, or :natural-language."
  ;; ASSUMPTION: topic is a string; nil/non-string defaults to natural-language
  ;; EDGE CASE: nil or non-string topic safely falls through to default category
  (if (stringp topic)
      (cond
       ((string-match-p "\\(?:elisp\\|emacs\\|lisp\\|code\\|function\\|module\\)" topic)
        :programming)
       ((string-match-p "\\(?:agent\\|workflow\\|daemon\\|pipeline\\|orchestrat\\)" topic)
        :agentic)
       ((string-match-p "\\(?:tool\\|backend\\|api\\|provider\\|gateway\\)" topic)
        :tool-calls)
       (t :natural-language))
    :natural-language))

(defun gptel-auto-workflow--update-research-strategy-champion (topic strategy keep-rate)
  "AutoGo: crown research STRATEGY as champion for TOPIC category if it beats baseline.
KEEP-RATE is fraction of experiments kept that used this research strategy."
  (let* ((cat (gptel-auto-workflow--research-category-for-topic topic))
         (baseline 0.15)
         (current (cdr (assq cat gptel-auto-workflow--research-strategy-champions)))
         (current-rate (if current (cdr current) 0.0)))
    (when (and strategy (> keep-rate baseline) (> keep-rate current-rate))
      (setq gptel-auto-workflow--research-strategy-champions
            (cons (cons cat (cons strategy keep-rate))
                  (cl-remove-if (lambda (e) (eq (car e) cat))
                                gptel-auto-workflow--research-strategy-champions)))
      (message "[research-champion] AutoGo: %s champion → '%s' (keep=%.1f%%)"
               cat strategy (* 100 keep-rate)))))

;; ─── Ontology-Driven Research Targeting ───

(defun gptel-auto-workflow--ontology-research-gaps ()
  "Analyze experiment ontology for research gaps.
Returns plist with :gaps (list of gap descriptions) and :priorities (alist topic→priority).
Ontology classes with <3 instances or missing properties become research priorities."
  (let ((gaps nil)
        (priorities nil))
    (when (fboundp 'gptel-auto-workflow--generate-experiment-ontology)
      (let* ((onto (gptel-auto-workflow--generate-experiment-ontology))
             (classes (and (listp onto) (plist-get onto :classes))))
        (when (listp classes)
          (dolist (class classes)
            (let ((name (plist-get class :name))
                  (instances (or (plist-get class :instances) 0))
                  (props (or (plist-get class :properties) nil)))
              (when (< instances 3)
                (push (format "Class '%s' has only %d instances — needs research" name instances)
                      gaps)
                (push (cons name (* 0.5 (- 3 instances))) priorities))
              (when (and props (< (length props) 2))
                (push (format "Class '%s' lacks properties (%d found) — research structure" name (length props))
                      gaps)
                (push (cons name 0.3) priorities))))))
    (list :gaps gaps :priorities (cl-remove-duplicates priorities :key #'car :test #'equal)))))

(defun gptel-auto-workflow--top-research-priority ()
  "Return highest-priority research topic from ontology gaps, or nil.
Uses ontology gap analysis to drive what the researcher should explore next."
  (let ((gaps (gptel-auto-workflow--ontology-research-gaps)))
    (when (and (listp gaps) (plist-get gaps :priorities))
      (let ((priorities (plist-get gaps :priorities)))
        (when (and (listp priorities) priorities)
          (let ((sorted (sort (copy-sequence priorities)
                              (lambda (a b) (> (cdr a) (cdr b))))))
            (when sorted
              (caar sorted))))))))

;; ─── Self-Evolve: Correlate Research Hashes to Experiment Outcomes ───

(defun gptel-auto-workflow--correlate-research-to-outcomes ()
  "Wire self-evolve: compute per-research-source keep-rate from TSV.
Returns alist of (source-name . keep-rate) sorted by performance.
ε Purpose: research scored on downstream experiment success, not volume."
  (when (fboundp 'gptel-auto-workflow--parse-all-results)
    (let ((by-source (make-hash-table :test 'equal))
          (stats nil)
          (all-results (gptel-auto-workflow--parse-all-results)))
      (when (listp all-results)
        (dolist (r all-results)
          (when (listp r)
            (let ((source (or (plist-get r :research-strategy) "none"))
                  (hash (or (plist-get r :research-hash) "none"))
                  (kept (equal (plist-get r :decision) "kept")))
              (unless (or (equal source "none") (equal hash "none"))
                (let ((entry (or (gethash source by-source) (cons 0 0))))
                  (setcar entry (1+ (car entry)))
                  (when kept (setcdr entry (1+ (cdr entry))))
                  (puthash source entry by-source))))))
        (maphash (lambda (source counts)
                   (when (> (car counts) 3)
                     (push (cons source (/ (float (cdr counts)) (car counts))) stats)))
                 by-source)
        (sort stats (lambda (a b) (> (cdr a) (cdr b))))))))

(defun gptel-auto-workflow--research-source-effectiveness-report ()
  "Generate markdown report of research source effectiveness.
Feeds into researcher skill evolution — tells researcher which sources produce kept experiments."
  (let ((stats (gptel-auto-workflow--correlate-research-to-outcomes))
        (lines (list "## Research Source Effectiveness\n")))
    (if stats
        (progn
          (push "| Source | Keep Rate |\n|---:|---:|\n" lines)
          (dolist (s stats)
            (push (format "| %s | %.1f%% |\n"
                          (car s) (* 100 (cdr s))) lines))
          (push "\n**Insight:** Sources with keep-rate >20% are high-signal.\n" lines))
      (push "*No research-experiment correlation data yet.*\n" lines))
    (apply #'concat (nreverse lines))))

;; ─── Meta-Harness: Propose Novel Research Strategies ───

(defvar gptel-auto-workflow--proposed-research-strategies nil
  "List of research strategy names proposed by meta-harness.
Champion league gates them: must beat incumbent before adoption.")

(defvar gptel-auto-workflow--research-strategies
  '("own-repos-first" "deep-external" "quick-own-only" "topic-specific")
  "Available research strategies to benchmark.")

(defun gptel-auto-workflow--propose-research-strategy (name description phases)
  "Meta-harness proposes a new research strategy.
NAME is strategy identifier. DESCRIPTION is human-readable.
PHASES is list of phase plists (:name :prompt :stop-condition).
Strategy is queued for champion league evaluation against existing 4 strategies."
  ;; ASSUMPTION: name is a non-empty string; nil/empty means invalid proposal
  ;; EDGE CASE: nil or empty name is rejected silently, preventing corrupt strategy files
  (if (string-empty-p (or name ""))
      nil
    (unless (member name gptel-auto-workflow--research-strategies)
      (push name gptel-auto-workflow--proposed-research-strategies)
      (message "[meta-harness] Proposed research strategy: %s — queued for champion league"
               name)
      ;; Write strategy definition for later benchmark when running in the full workflow.
      (when (fboundp 'gptel-auto-workflow--worktree-base-root)
        (let ((strategy-file (expand-file-name
                              (format "assistant/skills/researcher-prompt/strategies/%s.json"
                                      name)
                              (gptel-auto-workflow--worktree-base-root))))
          (make-directory (file-name-directory strategy-file) t)
          (with-temp-file strategy-file
            (let ((json-object-type 'hash-table)
                  (json-array-type 'list)
                  (json-key-type 'string))
              (insert (json-encode
                       (let ((h (make-hash-table :test 'equal)))
                         (puthash "name" name h)
                         (puthash "description" description h)
                         (puthash "phases" phases h)
                         (puthash "status" "proposed" h)
                         h)))))))
      name)))

(defun gptel-auto-workflow--run-research-champion-league ()
  "AutoGo: benchmark all proposed strategies against incumbents.
Adopts winners, discards losers. Called from evolution cycle.
∀ Vigilance: a strategy must beat the category baseline (~15%) to be adopted."
  (when gptel-auto-workflow--proposed-research-strategies
    (message "[research-champion] Running champion league for %d proposed strategies"
             (length gptel-auto-workflow--proposed-research-strategies))
    (dolist (proposed (copy-sequence gptel-auto-workflow--proposed-research-strategies))
      (when (fboundp 'gptel-auto-workflow--benchmark-research-strategy)
        (gptel-auto-workflow--benchmark-research-strategy
         proposed "agentic"
         (lambda (result)
           (let ((efficiency (or (plist-get result :efficiency) 0))
                 (baseline 0.15))
             (if (> efficiency baseline)
                 (progn
                   (push proposed gptel-auto-workflow--research-strategies)
                   (message "[research-champion] ADOPTED: %s (efficiency=%.3f > %.3f)"
                            proposed efficiency baseline))
               (message "[research-champion] REJECTED: %s (efficiency=%.3f <= %.3f)"
                        proposed efficiency baseline))
             (setq gptel-auto-workflow--proposed-research-strategies
                   (cl-remove proposed gptel-auto-workflow--proposed-research-strategies
                              :test #'string=)))))))))

(provide 'gptel-auto-workflow-research-integration)
;;; gptel-auto-workflow-research-integration.el ends here
