;;; gptel-benchmark-instincts.el --- Pattern instincts with Eight Keys evolution -*- lexical-binding: t; -*-

;; Copyright (C) 2025 David Wu
;; Author: David Wu
;; Version: 1.0.0
;; Keywords: ai, benchmark, instincts, eight-keys, evolution

;;; Commentary:

;; Instinct evolution system for protocol patterns with Eight Keys tracking.
;;
;; An instinct = pattern + φ + Eight Keys + evidence
;;
;; φ (phi) represents the vitality/confidence of a pattern, derived from Eight Keys:
;;   0.9-1.0: Core pattern, almost always applicable
;;   0.7-0.8: Strong preference, well-tested
;;   0.5-0.6: Emerging pattern, needs validation
;;   0.3-0.4: Experimental, low confidence
;;   0.0-0.2: Deprecated, consider removal
;;
;; Eight Keys (equal weights, 12.5% each):
;;   vitality, clarity, purpose, wisdom, synthesis, directness, truth, vigilance
;;
;; Features:
;; - In-memory Eight Keys accumulation
;; - Weekly batch commits to protocol frontmatter
;; - Decay for untested patterns (each key decays independently)
;; - Minimum evidence threshold for confidence
;; - Diagnostic for weak keys
;;
;; Flow:
;;   Benchmark runs → Accumulates Eight Keys → Weekly batch commit → Protocol updated
;;
;; λ instincts(x).
;;   benchmark(x) → eight_keys(x) → φ = mean(eight_keys)
;;   | validated → accumulate(eight_keys, +delta)
;;   | corrected → accumulate(eight_keys, -delta/2)
;;   | untested(weeks > 1) → each_key -= decay_rate
;;   | φ = mean(eight_keys)

;;; Code:

(require 'cl-lib)

(declare-function gptel-mementum-weekly-job "gptel-tools-agent")

;;; Customization

(defgroup gptel-benchmark-instincts nil
  "Instinct evolution for protocol patterns."
  :group 'gptel-benchmark)

(defcustom gptel-benchmark-instincts-delta-positive 0.02
  "Δ increment when pattern validated."
  :type 'number
  :group 'gptel-benchmark-instincts)

(defcustom gptel-benchmark-instincts-delta-negative 0.01
  "Δ decrement when pattern corrected (half of positive)."
  :type 'number
  :group 'gptel-benchmark-instincts)

(defcustom gptel-benchmark-instincts-decay-rate 0.02
  "Decay per week without testing (applied to each key)."
  :type 'number
  :group 'gptel-benchmark-instincts)

(defcustom gptel-benchmark-instincts-phi-minimum 0.3
  "Minimum φ value, don't decay below this."
  :type 'number
  :group 'gptel-benchmark-instincts)

(defcustom gptel-benchmark-instincts-evidence-threshold 5
  "Minimum tests before φ is considered confident.
Patterns with evidence < threshold show as `emerging' in reports."
  :type 'integer
  :group 'gptel-benchmark-instincts)

(defcustom gptel-benchmark-instincts-weak-threshold 0.8
  "Threshold below which a key is considered `weak' in diagnostic."
  :type 'number
  :group 'gptel-benchmark-instincts)

(defcustom gptel-benchmark-instincts-phi-max 1.0
  "Maximum φ value."
  :type 'number
  :group 'gptel-benchmark-instincts)

;;; Eight Keys Definition

(defconst gptel-benchmark-instincts-eight-keys
  '(:vitality :clarity :purpose :wisdom :synthesis :directness :truth :vigilance)
  "List of Eight Keys symbols used for tracking.")

(defconst gptel-benchmark-instincts-key-abbrevs
  '((:vitality . "φ")
    (:clarity . "γ")
    (:purpose . "ε")
    (:wisdom . "τ")
    (:synthesis . "π")
    (:directness . "μ")
    (:truth . "∃")
    (:vigilance . "∀"))
  "Greek symbols for Eight Keys in compact display.")

;;; State

(defvar gptel-benchmark-instincts--accumulator (make-hash-table :test 'equal)
  "Accumulated Eight Keys deltas per (protocol . pattern).
Key: (protocol-file . pattern-name)
Value: (:eight-keys (:vitality 0.0 ...) :count 0 :last-test nil)")

(defvar gptel-benchmark-instincts-timer nil
  "Timer for weekly batch commit.")

;;; φ Computation

(defun gptel-benchmark-instincts-compute-phi (eight-keys)
  "Compute φ as mean of EIGHT-KEYS plist.
EIGHT-KEYS is plist with keys from `gptel-benchmark-instincts-eight-keys'."
  (let ((sum 0.0)
        (count 0))
    (dolist (key gptel-benchmark-instincts-eight-keys)
      (when-let ((val (plist-get eight-keys key)))
        (cl-incf sum val)
        (cl-incf count)))
    (if (> count 0)
        (/ sum count)
      0.5)))

;;; Accumulation

(defun gptel-benchmark-instincts-record (protocol-file pattern-name eight-keys outcome)
  "Record Eight Keys for PATTERN-NAME in PROTOCOL-FILE based on OUTCOME.
OUTCOME is `validated' or `corrected'.
EIGHT-KEYS is plist with all Eight Keys scores from benchmark.
Accumulates in memory for batch commit."
  (let* ((key (cons protocol-file pattern-name))
         (entry (gethash key gptel-benchmark-instincts--accumulator))
         (delta (if (eq outcome 'validated)
                    gptel-benchmark-instincts-delta-positive
                  (- gptel-benchmark-instincts-delta-negative))))
    (let ((new-eight-keys '()))
      (dolist (k gptel-benchmark-instincts-eight-keys)
        (let* ((current (or (plist-get entry k) 0.0))
               (benchmark-val (or (plist-get eight-keys k) 0.5))
               (new-val (+ current (* delta (if (eq outcome 'validated)
                                                benchmark-val
                                              (- 1.0 benchmark-val))))))
          (setq new-eight-keys (plist-put new-eight-keys k new-val))))
      (puthash key
               (list :eight-keys new-eight-keys
                     :count (1+ (or (plist-get entry :count) 0))
                     :last-test (format-time-string "%Y-%m-%d"))
               gptel-benchmark-instincts--accumulator))))

(defun gptel-benchmark-instincts-get-accumulated (protocol-file pattern-name)
  "Get accumulated Eight Keys data for PATTERN-NAME in PROTOCOL-FILE."
  (gethash (cons protocol-file pattern-name) gptel-benchmark-instincts--accumulator))

(defun gptel-benchmark-instincts-clear-accumulator ()
  "Clear all accumulated Eight Keys deltas."
  (clrhash gptel-benchmark-instincts--accumulator))

(defun gptel-benchmark-instincts-accumulator-size ()
  "Return number of pending updates."
  (hash-table-count gptel-benchmark-instincts--accumulator))

;;; Decay

(defun gptel-benchmark-instincts--calculate-decay (last-tested)
  "Calculate decay amount based on LAST-TESTED date string.
Returns decay amount (>= 0)."
  (when last-tested
    (let* ((last (date-to-time last-tested))
           (now (current-time))
           (days-since (/ (float-time (time-subtract now last)) 86400))
           (weeks-since (/ days-since 7)))
      (if (> weeks-since 1)
          (* gptel-benchmark-instincts-decay-rate (floor weeks-since))
        0))))

(defun gptel-benchmark-instincts-apply-decay (eight-keys last-tested)
  "Apply decay to each key in EIGHT-KEYS based on LAST-TESTED.
Returns updated eight-keys plist with all keys decayed."
  (let ((decay (gptel-benchmark-instincts--calculate-decay last-tested)))
    (if (> decay 0)
        (let ((result '()))
          (dolist (key gptel-benchmark-instincts-eight-keys)
            (let* ((old-value (or (plist-get eight-keys key) 0.5))
                   (new-value (max gptel-benchmark-instincts-phi-minimum (- old-value decay))))
              (setq result (plist-put result key new-value))))
          result)
      eight-keys)))

;;; Frontmatter Parsing

(defun gptel-benchmark-instincts--parse-frontmatter (file)
  "Parse YAML frontmatter from FILE.
Returns alist of frontmatter keys/values.
Handles multi-line blocks (e.g., instincts:) by capturing indented content."
  (when (file-exists-p file)
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (when (looking-at "---\\s-*$")
        (forward-line 1)
        (let ((end (save-excursion
                     (when (re-search-forward "^---\\s-*$" nil t)
                       (match-beginning 0))))
              (result '()))
          (when end
            (while (< (point) end)
              (cond
               ((looking-at "^\\([^:]+\\):\\s-*$")
                (let ((key (intern (concat ":" (string-trim (match-string 1))))))
                  (forward-line 1)
                  (let ((block-lines '()))
                    (while (and (< (point) end)
                                (looking-at "^  "))
                      (push (buffer-substring-no-properties (line-beginning-position)
                                                            (line-end-position))
                            block-lines)
                      (forward-line 1))
                    (push (cons key (string-join (nreverse block-lines) "\n")) result))))
               ((looking-at "^\\([^:]+\\):\\s-*\\(.*\\)$")
                (let ((key (intern (concat ":" (string-trim (match-string 1)))))
                      (value (string-trim (match-string 2))))
                  (push (cons key value) result)
                  (forward-line 1)))
               (t
                (forward-line 1))))
            (nreverse result)))))))

(defun gptel-benchmark-instincts--parse-instincts (instincts-string)
  "Parse instincts YAML section into alist.
INSTINCTS-STRING is the raw YAML content."
  (when instincts-string
    (let ((result '())
          (current-pattern nil)
          (current-data '()))
      (dolist (line (split-string instincts-string "\n"))
        (cond
         ;; Pattern name (e.g., "  repl-first:")
         ((string-match "^  \\([a-z-]+\\):\\s-*$" line)
          (when current-pattern
            (push (cons current-pattern current-data) result))
          (setq current-pattern (match-string 1 line)
                current-data '()))
         ;; φ value (e.g., "    φ: 0.83")
         ((string-match "^    φ:\\s-*\\([0-9.]+\\)" line)
          (push (cons :phi (string-to-number (match-string 1 line))) current-data))
         ;; eight-keys section start
         ((string-match "^    eight-keys:" line)
          (push (cons :eight-keys '()) current-data))
         ;; eight-keys value (e.g., "      vitality: 0.85")
         ((string-match "^      \\([a-z]+\\):\\s-*\\([0-9.]+\\)" line)
          (let* ((key (intern (concat ":" (match-string 1 line))))
                 (val (string-to-number (match-string 2 line)))
                 (eight-keys (cdr (assoc :eight-keys current-data))))
            (setcdr (assoc :eight-keys current-data)
                    (plist-put eight-keys key val))))
;; Other values (numeric or string)
          ((string-match "^    \\([a-z-]+\\):\\s-*\\([0-9]+\\.[0-9]+\\)" line)
           (let ((key (intern (concat ":" (match-string 1 line))))
                 (value (string-to-number (match-string 2 line))))
             (push (cons key value) current-data)))
          ((string-match "^    \\([a-z-]+\\):\\s-*\\([0-9]+\\)\\s-*$" line)
           (let ((key (intern (concat ":" (match-string 1 line))))
                 (value (string-to-number (match-string 2 line))))
             (push (cons key value) current-data)))
          ;; String values (dates, etc.)
          ((string-match "^    \\([a-z-]+\\):\\s-*\\([^[:space:]]+\\)" line)
           (let ((key (intern (concat ":" (match-string 1 line))))
                 (value (match-string 2 line)))
             (push (cons key value) current-data)))))
      (when current-pattern
        (push (cons current-pattern current-data) result))
      (nreverse result))))

(defun gptel-benchmark-instincts-get-instinct (protocol-file pattern-name)
  "Get instinct data for PATTERN-NAME from PROTOCOL-FILE.
Returns plist with :phi, :eight-keys, :evidence, :last-tested, :last-updated."
  (when-let ((frontmatter (gptel-benchmark-instincts--parse-frontmatter protocol-file)))
    (let* ((instincts-raw (cdr (assoc :instincts frontmatter)))
           (instincts (gptel-benchmark-instincts--parse-instincts instincts-raw)))
      (cdr (assoc pattern-name instincts)))))

;;; Status Functions

(defun gptel-benchmark-instincts-status (phi evidence)
  "Return status symbol for pattern with PHI and EVIDENCE.
Returns `confident', `emerging', or `deprecated'."
  (cond
   ((< phi gptel-benchmark-instincts-phi-minimum) 'deprecated)
   ((< evidence gptel-benchmark-instincts-evidence-threshold) 'emerging)
   (t 'confident)))

(defun gptel-benchmark-instincts-confident-p (phi evidence)
  "Return non-nil if pattern with PHI and EVIDENCE has enough confidence."
  (eq (gptel-benchmark-instincts-status phi evidence) 'confident))

;;; Format Display

(defun gptel-benchmark-instincts-format-compact (pattern-name data)
  "Format PATTERN-NAME and DATA as compact string.
Returns: repl-first φ=0.83 [v:0.85 c:0.78 p:0.82 w:0.75 s:0.80 d:0.88 t:0.90]
ev=5"
  (let* ((phi (or (cdr (assoc :phi data)) 0.5))
         (eight-keys (cdr (assoc :eight-keys data)))
         (evidence (or (cdr (assoc :evidence data)) 0))
         (keys-str (mapconcat
                    (lambda (key)
                      (format "%s:%.2f"
                              (cdr (assoc key gptel-benchmark-instincts-key-abbrevs))
                              (or (plist-get eight-keys key) 0.5)))
                    gptel-benchmark-instincts-eight-keys
                    " ")))
    (format "%-15s φ=%.2f [%s] ev=%d"
            pattern-name phi keys-str evidence)))

;;; Batch Commit

(defun gptel-benchmark-instincts-commit-batch ()
  "Commit accumulated Eight Keys deltas to protocol files.
Returns number of files updated."
  (cl-block gptel-benchmark-instincts-commit-batch
    (when (= (hash-table-count gptel-benchmark-instincts--accumulator) 0)
      (message "[instincts] No accumulated deltas to commit")
      (cl-return-from gptel-benchmark-instincts-commit-batch 0))

    (let ((updates-by-file (make-hash-table :test 'equal))
          (files-updated 0))
    (maphash
     (lambda (key entry)
       (let ((file (car key))
             (pattern (cdr key)))
         (push (cons pattern entry) (gethash file updates-by-file))))
     gptel-benchmark-instincts--accumulator)

    (maphash
     (lambda (file updates)
       (when (gptel-benchmark-instincts--apply-updates-to-file file updates)
         (cl-incf files-updated)))
     updates-by-file)

    (clrhash gptel-benchmark-instincts--accumulator)

    (message "[instincts] Batch commit complete: %d files updated" files-updated)
    files-updated)))

(defun gptel-benchmark-instincts--apply-updates-to-file (file updates)
  "Apply UPDATES to FILE.
UPDATES is list of (pattern-name . entry) pairs.
Returns t if file was updated."
  (when (file-exists-p file)
    (let* ((existing-instincts (gptel-benchmark-instincts--get-existing-instincts file))
           (updated-instincts (gptel-benchmark-instincts--merge-updates existing-instincts updates)))
      (gptel-benchmark-instincts--write-frontmatter file updated-instincts)
      (message "[instincts] Updated %s with %d patterns"
               (file-name-nondirectory file) (length updates))
      t)))

(defun gptel-benchmark-instincts--get-existing-instincts (file)
  "Get existing instincts from FILE as alist."
  (when-let ((frontmatter (gptel-benchmark-instincts--parse-frontmatter file)))
    (let* ((instincts-raw (cdr (assoc :instincts frontmatter))))
      (when instincts-raw
        (gptel-benchmark-instincts--parse-instincts instincts-raw)))))

(defun gptel-benchmark-instincts--merge-updates (existing-instincts updates)
  "Merge UPDATES into EXISTING-INSTINCTS.
Returns updated instincts alist."
  (let ((result (copy-alist existing-instincts)))
    (dolist (update updates)
      (let* ((pattern (car update))
             (entry (cdr update))
             (existing (assoc pattern result))
             (eight-keys-delta (plist-get entry :eight-keys))
             (count (plist-get entry :count))
             (last-test (plist-get entry :last-test)))
        (if existing
            (let* ((existing-data (cdr existing))
                   (existing-eight-keys (cdr (assoc :eight-keys existing-data)))
                   (existing-evidence (let ((ev (cdr (assoc :evidence existing-data))))
                     (cond ((numberp ev) ev)
                           ((stringp ev) (string-to-number ev))
                           (t 0))))
                   (merged-keys (gptel-benchmark-instincts--merge-eight-keys
                                 existing-eight-keys eight-keys-delta count))
                   (new-phi (gptel-benchmark-instincts-compute-phi merged-keys)))
              (setcdr existing (list (cons :phi new-phi)
                                     (cons :eight-keys merged-keys)
                                     (cons :evidence (+ existing-evidence count))
                                     (cons :last-tested last-test)
                                     (cons :last-updated (format-time-string "%Y-%m-%d")))))
          (push (cons pattern
                      (list (cons :phi (gptel-benchmark-instincts-compute-phi eight-keys-delta))
                            (cons :eight-keys eight-keys-delta)
                            (cons :evidence count)
                            (cons :last-tested last-test)
                            (cons :last-updated (format-time-string "%Y-%m-%d"))))
                result))))
    result))

(defun gptel-benchmark-instincts--merge-eight-keys (existing delta _weight)
  "Merge DELTA into EXISTING eight-keys.
_WEIGHT is reserved for future weighted averaging.
Returns merged eight-keys plist."
  (let ((result '()))
    (dolist (key gptel-benchmark-instincts-eight-keys)
      (let* ((existing-val (or (plist-get existing key) 0.5))
             (delta-val (or (plist-get delta key) 0.0))
             (new-val (min gptel-benchmark-instincts-phi-max
                          (max gptel-benchmark-instincts-phi-minimum
                               (+ existing-val delta-val)))))
        (setq result (plist-put result key new-val))))
    result))

(defun gptel-benchmark-instincts--write-frontmatter (file instincts)
  "Write INSTINCTS to FILE frontmatter."
  (let ((instincts-string (gptel-benchmark-instincts--format-instincts-yaml instincts)))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (when (re-search-forward "^instincts:" nil t)
        (let ((start (line-beginning-position))
              (end (save-excursion
                     (if (re-search-forward "^---" nil t)
                         (match-beginning 0)
                       (point-max)))))
          (delete-region start end)
          (goto-char start)
          (insert instincts-string)))
      (write-file file))))

(defun gptel-benchmark-instincts--format-instincts-yaml (instincts)
  "Format INSTINCTS alist as YAML string."
  (let ((lines '("instincts:")))
    (dolist (instinct instincts)
      (let* ((pattern (car instinct))
             (data (cdr instinct))
             (phi (or (cdr (assoc :phi data)) 0.5))
             (eight-keys (cdr (assoc :eight-keys data)))
             (evidence (or (cdr (assoc :evidence data)) 0))
             (last-tested (or (cdr (assoc :last-tested data)) "never"))
             (last-updated (or (cdr (assoc :last-updated data)) "never")))
        (push (format "  %s:" pattern) lines)
        (push (format "    φ: %.2f" phi) lines)
        (push "    eight-keys:" lines)
        (dolist (key gptel-benchmark-instincts-eight-keys)
          (push (format "      %s: %.2f"
                       (substring (symbol-name key) 1)
                       (or (plist-get eight-keys key) 0.5))
               lines))
        (push (format "    evidence: %d" evidence) lines)
        (push (format "    last-tested: %s" last-tested) lines)
        (push (format "    last-updated: %s" last-updated) lines)))
    (mapconcat #'identity (nreverse lines) "\n")))

;;; Weekly Timer

(defun gptel-benchmark-instincts--seconds-until-sunday ()
  "Calculate seconds until next Sunday 00:00.
Returns the number of seconds from now until the next Sunday at midnight."
  (let* ((now (current-time))
         (decoded (decode-time now))
         ;; decoded-time is (SEC MIN HOUR DAY MON YEAR DOW DST ZONE)
         ;; DOW is 0=Sunday, 1=Monday, ..., 6=Saturday
         (day-of-week (nth 6 decoded))
         (hour (nth 2 decoded))
         (minute (nth 1 decoded))
         (second (nth 0 decoded))
         (today-seconds (+ (* hour 3600) (* minute 60) second))
         ;; Calculate days until Sunday (DOW=0)
         ;; If today is Sunday (DOW=0), days-until = 0 or 7
         (days-until-sunday (mod (- 7 day-of-week) 7)))
    ;; Edge case: exactly Sunday 00:00:00 -> run immediately
    (if (and (= days-until-sunday 0) (= today-seconds 0))
        0
      (progn
        (when (and (= days-until-sunday 0) (> today-seconds 0))
          (setq days-until-sunday 7))
        (+ (* days-until-sunday 86400) (- 86400 today-seconds))))))

(defun gptel-benchmark-instincts-start-weekly-timer ()
  "Start weekly timer for batch commit.
Runs every Sunday at 00:00."
  (when gptel-benchmark-instincts-timer
    (cancel-timer gptel-benchmark-instincts-timer))
  (let ((seconds-until-sunday (gptel-benchmark-instincts--seconds-until-sunday)))
    (setq gptel-benchmark-instincts-timer
          (run-at-time seconds-until-sunday (* 7 24 3600)
                       #'gptel-benchmark-instincts-weekly-job))
    (message "[instincts] Weekly timer set: next run in %.1f days"
             (/ seconds-until-sunday 86400.0))))

(defun gptel-benchmark-instincts-stop-weekly-timer ()
  "Stop weekly timer."
  (when gptel-benchmark-instincts-timer
    (cancel-timer gptel-benchmark-instincts-timer)
    (setq gptel-benchmark-instincts-timer nil)))

(defun gptel-benchmark-instincts-weekly-job ()
  "Weekly job: commit Eight Keys updates, apply decay, run mementum maintenance."
  (message "[instincts] Weekly evolution cycle starting...")

  (gptel-mementum-weekly-job)

  (if (bound-and-true-p gptel-auto-workflow--headless)
      (progn
        (when (> (hash-table-count gptel-benchmark-instincts--accumulator) 0)
          (message "[instincts] Pending batch updates require manual review; skipping headless commit"))
        0)
    (let ((files-updated (gptel-benchmark-instincts-commit-batch)))
      (when (> files-updated 0)
        (let ((default-directory (or (bound-and-true-p mementum-root)
                                     (expand-file-name "~/.emacs.d")))
              (commit-msg (format "instincts evolution: weekly batch update (%s)"
                                  (format-time-string "%Y-%m-%d"))))
          (shell-command "git add mementum/knowledge/*.md")
          (shell-command (concat "git commit -m " (shell-quote-argument commit-msg)))
          (message "[instincts] Weekly evolution cycle complete: %s" commit-msg)))
      files-updated)))

;;; Interactive Commands

(defun gptel-benchmark-instincts-status-report ()
  "Show current instincts status for all protocols."
  (interactive)
  (let* ((knowledge-dir (expand-file-name "mementum/knowledge/"
                                          (or (bound-and-true-p mementum-root)
                                              (expand-file-name "~/.emacs.d"))))
         (protocols (directory-files knowledge-dir t "\\.md$"))
         (report-lines '()))

    (push "Instincts Status" report-lines)
    (push "═══════════════════════════════════════════════════" report-lines)

    (dolist (protocol protocols)
      (let* ((name (file-name-nondirectory protocol))
             (frontmatter (gptel-benchmark-instincts--parse-frontmatter protocol))
             (instincts-raw (cdr (assoc :instincts frontmatter)))
             (instincts (gptel-benchmark-instincts--parse-instincts instincts-raw)))
        (when instincts
          (push (format "\n%s:" name) report-lines)
          (dolist (instinct instincts)
            (let ((pattern (car instinct))
                  (data (cdr instinct)))
              (push (format "  %s" (gptel-benchmark-instincts-format-compact pattern data))
                   report-lines))))))

    (push "\n───────────────────────────────────────────────────" report-lines)
    (push (format "Pending updates: %d patterns"
                 (hash-table-count gptel-benchmark-instincts--accumulator))
         report-lines)

    (message "%s" (mapconcat #'identity (nreverse report-lines) "\n"))))

(defun gptel-benchmark-instincts-diagnostic ()
  "Show weak keys (below threshold) for all patterns."
  (interactive)
  (let* ((knowledge-dir (expand-file-name "mementum/knowledge/"
                                          (or (bound-and-true-p mementum-root)
                                              (expand-file-name "~/.emacs.d"))))
         (protocols (directory-files knowledge-dir t "\\.md$"))
         (weak-found nil)
         (report-lines '()))

    (push (format "Weak Keys (threshold: %.1f)" gptel-benchmark-instincts-weak-threshold)
          report-lines)
    (push "═══════════════════════════════════════════════════" report-lines)

    (dolist (protocol protocols)
      (let* ((frontmatter (gptel-benchmark-instincts--parse-frontmatter protocol))
             (instincts-raw (cdr (assoc :instincts frontmatter)))
             (instincts (gptel-benchmark-instincts--parse-instincts instincts-raw)))
        (dolist (instinct instincts)
          (let* ((pattern (car instinct))
                 (data (cdr instinct))
                 (eight-keys (cdr (assoc :eight-keys data)))
                 (pattern-weak nil))
            (dolist (key gptel-benchmark-instincts-eight-keys)
              (let ((val (or (plist-get eight-keys key) 1.0)))
                (when (< val gptel-benchmark-instincts-weak-threshold)
                  (push (format "  %s: %.2f"
                               (substring (symbol-name key) 1) val)
                       pattern-weak)
                  (setq weak-found t))))
            (when pattern-weak
              (push (format "\n%s:" pattern) report-lines)
              (dolist (line (nreverse pattern-weak))
                (push line report-lines)))))))

    (if weak-found
        (message "%s" (mapconcat #'identity (nreverse report-lines) "\n"))
      (message "No weak keys found (all keys >= %.1f)" gptel-benchmark-instincts-weak-threshold))))

(defun gptel-benchmark-instincts-commit-now ()
  "Force immediate batch commit (bypass weekly timer)."
  (interactive)
  (gptel-benchmark-instincts-weekly-job))

(defun gptel-benchmark-instincts-clear ()
  "Clear all pending updates without committing."
  (interactive)
  (let ((count (hash-table-count gptel-benchmark-instincts--accumulator)))
    (gptel-benchmark-instincts-clear-accumulator)
    (message "[instincts] Cleared %d pending updates" count)))

(defun gptel-benchmark-instincts-show-pending ()
  "Show pending Eight Keys updates."
  (interactive)
  (let ((lines '()))
    (push "Pending Instincts Updates:" lines)
    (push "───────────────────────────────────────────────────" lines)
    (maphash
     (lambda (key entry)
       (let ((file (file-name-nondirectory (car key)))
             (pattern (cdr key)))
         (push (format "  %s / %-15s  count=%d"
                      file pattern
                      (plist-get entry :count))
               lines)))
     gptel-benchmark-instincts--accumulator)
    (if (= (hash-table-count gptel-benchmark-instincts--accumulator) 0)
        (message "No pending instincts updates")
      (message "%s" (mapconcat #'identity (nreverse lines) "\n")))))

;;; Provide

(provide 'gptel-benchmark-instincts)

;;; gptel-benchmark-instincts.el ends here
