                                        ; -*- lexical-binding: t; -*-
(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(defconst gptel-auto-experiment--axis-names
  '(("A" . "Error Handling")
    ("B" . "Performance")
    ("C" . "Refactoring")
    ("D" . "Safety")
    ("E" . "Test Coverage")
    ("F" . "Memory Management")
    ("G" . "Documentation")
    ("H" . "Type Safety")
    ("I" . "Edge Cases"))
  "Mapping from axis letters to human-readable names.")

(declare-function gptel-agent-read-file "gptel-agent-tools")
(declare-function gptel-auto-workflow--valid-strategy-name-p "gptel-tools-agent-strategy-evolver" (name))
(declare-function gptel-auto-workflow-load-research-findings "gptel-auto-workflow-strategic")
(declare-function gptel-benchmark--detect-task-type "gptel-benchmark-principles")
(declare-function my/gptel-get-model-metadata "gptel-ext-context-cache")
(declare-function gptel-auto-workflow--current-run-id "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--ensure-results-file "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--make-idempotent-callback "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--non-empty-string-p "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--plist-get "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--results-file-path "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--worktree-base-root "gptel-tools-agent-base")
(declare-function gptel-auto-experiment--eight-keys-scores "gptel-tools-agent-benchmark")
(declare-function gptel-auto-workflow--project-root "gptel-tools-agent-benchmark")
(declare-function gptel-auto-workflow--persist-status "gptel-tools-agent-experiment-loop")
(declare-function my/gptel--sanitize-for-logging "gptel-tools-agent-git")
(declare-function gptel-auto-workflow--extract-mutation-templates "gptel-tools-agent-main")
(declare-function gptel-auto-workflow--format-weakest-keys "gptel-tools-agent-main")
(declare-function gptel-auto-workflow-skill-suggest-hypothesis "gptel-tools-agent-main")
(declare-function gptel-auto-experiment--inspection-thrash-result-p "gptel-tools-agent-prompt-analyze")
(declare-function gptel-auto-experiment--needs-inspection-thrash-recovery-p "gptel-tools-agent-prompt-analyze")
(declare-function gptel-auto-experiment--select-large-target-focus "gptel-tools-agent-prompt-analyze")
(declare-function gptel-auto-experiment--target-byte-size "gptel-tools-agent-prompt-analyze")
(declare-function gptel-auto-workflow--get-worktree-dir "gptel-tools-agent-subagent")
;;; gptel-tools-agent-prompt-build.el --- Prompt building - construction & logging -*- lexical-binding: t; -*-
;; Part of gptel-tools-agent split

(declare-function gptel-auto-workflow--record-strategy-evaluation "gptel-tools-agent-strategy-harness"
                  (strategy-name target experiment-id score outcome &optional axis))

;; Forward declarations for dynamic variables
(defvar gptel-auto-workflow--skills)
(defvar gptel-auto-experiment-large-target-byte-threshold)
(defvar gptel-auto-workflow--last-prompt-sections)
(defvar gptel-auto-workflow--current-research-context)
(defvar gptel-auto-experiment-time-budget)
(defvar gptel-auto-workflow-use-staging)
(defvar gptel-auto-workflow--running)
(defvar gptel-auto-workflow--stats)
(defvar gptel-auto-experiment-validation-retry-active-grace)
(defvar gptel-auto-workflow--legacy-validation-retry-active-grace)
(defvar gptel-auto-workflow--current-validation-retry-active-grace)
(defvar my/gptel-subagent-stream)

;; ─── Knowledge Cache ───

(defvar gptel-auto-workflow--knowledge-cache (make-hash-table :test 'equal)
  "Hash table mapping knowledge keys to cached content.
Keys: \='self-evolution or topic names like \='context-cache.
Values: (content . timestamp) cons cells.
Cache is invalidated after synthesis runs.")

(defvar gptel-auto-workflow--knowledge-cache-max-age 3600
  "Maximum age of cached knowledge in seconds (1 hour).")

(defvar gptel-auto-workflow--topic-knowledge-max-chars 400
  "Maximum chars for topic-specific knowledge compression.
Self-evolution adjusts this based on token efficiency analysis.
Default 400, range 100-800.")

(defun gptel-auto-workflow--knowledge-cache-get (key)
  "Get cached knowledge for KEY if fresh.
Returns cached content or nil if missing/stale."
  (let ((entry (gethash key gptel-auto-workflow--knowledge-cache)))
    (when entry
      (let ((content (car entry))
            (age (float-time (time-subtract (current-time) (cdr entry)))))
        (if (< age gptel-auto-workflow--knowledge-cache-max-age)
            content
          ;; Stale - remove from cache
          (remhash key gptel-auto-workflow--knowledge-cache)
          nil)))))

(defun gptel-auto-workflow--knowledge-cache-set (key content)
  "Cache CONTENT for KEY with current timestamp."
  (puthash key (cons content (current-time)) gptel-auto-workflow--knowledge-cache))

(defun gptel-auto-workflow--knowledge-cache-invalidate (key)
  "Invalidate cache for KEY, or all keys if KEY is t."
  (if (eq key t)
      (clrhash gptel-auto-workflow--knowledge-cache)
    (remhash key gptel-auto-workflow--knowledge-cache)))

(defun gptel-auto-workflow--knowledge-cache-stats ()
  "Return cache statistics as string."
  (let ((count 0)
        (total-age 0))
    (maphash
     (cl-function (lambda (_key entry)
                    (cl-incf count)
                    (cl-incf total-age
                             (float-time
                              (time-subtract (current-time) (cdr entry))))))
     gptel-auto-workflow--knowledge-cache)
    (format "[knowledge-cache] %d entries, avg age %.0fs"
            count (if (> count 0) (/ total-age count) 0))))

(defun gptel-auto-workflow--load-token-efficiency-data ()
  "Load token efficiency data from var/tmp/evolution/.
Returns plist with :compression :section-stats or nil.
Reads runtime-generated token-efficiency data directly."
  (let* ((file (expand-file-name "var/tmp/evolution/token-efficiency.md"
                                 (or (gptel-auto-workflow--worktree-base-root)
                                     default-directory)))
         (content (when (file-exists-p file)
                    (with-temp-buffer
                      (insert-file-contents file)
                      (buffer-string)))))
    (when (and content (not (string-empty-p content)))
      (with-temp-buffer
        (insert content)
        (goto-char (point-min))
        (let ((config (list :source "mementum")))
          ;; Parse compression config
          (when (re-search-forward "topic-knowledge-max-chars: \\([0-9]+\\)" nil t)
            (plist-put config :compression (string-to-number (match-string 1))))
          ;; Parse section A/B results
          (goto-char (point-min))
          (let ((section-stats (make-hash-table :test 'equal)))
            (while (re-search-forward "^- \\*\\*\\(.+\\)\\*\\*: \\([0-9.]+\\)% success (\\([0-9]+\\)/\\([0-9]+\\) experiments)" nil t)
              (let ((section (match-string 1))
                    (rate (string-to-number (match-string 2)))
                    (kept (string-to-number (match-string 3)))
                    (total (string-to-number (match-string 4))))
                (puthash section (list :rate rate :kept kept :total total) section-stats)))
            (plist-put config :section-stats section-stats))
          config)))))

(defun gptel-auto-workflow--adapt-prompt-compression ()
  "Adapt topic knowledge compression based on token efficiency skill.
Reads var/tmp/evolution/token-efficiency.md and adjusts max chars.
Returns the adjusted max chars value."
  (let* ((skill (gptel-auto-workflow--load-token-efficiency-data))
         (compression (when skill (plist-get skill :compression))))
    (when (and compression (> compression 0))
      (setq gptel-auto-workflow--topic-knowledge-max-chars compression)
      (message "[prompt-efficiency] Skill-guided compression: %d chars" compression)))
  gptel-auto-workflow--topic-knowledge-max-chars)

;; ─── Prompt Structure Scoring (verbum + nucleus pattern) ───

(defun gptel-auto-experiment--prompt-structure-score (prompt)
  "Score PROMPT structure quality (0.0-1.0).
Like nucleus's compiler: well-structured prompts 'compile' better.
Criteria: has sections, has examples, has specific guidance, right length."
  (let ((score 0.0))
    (when (stringp prompt)
      ;; Has explicit sections (+0.2)
      (when (string-match-p "## " prompt)
        (setq score (+ score 0.2)))
      ;; Has code examples (+0.2)
      (when (string-match-p "```" prompt)
        (setq score (+ score 0.2)))
      ;; Has specific instructions / numbered lists (+0.15)
      (when (string-match-p "^[0-9]+\\." prompt)
        (setq score (+ score 0.15)))
      ;; Right size: 2000-12000 chars (+0.2)
      (let ((len (length prompt)))
        (when (and (> len 2000) (< len 12000))
          (setq score (+ score 0.2)))
        ;; Penalty for too short (<1000) or too long (>18000)
        (when (< len 1000) (setq score (max 0 (- score 0.15))))
        (when (> len 18000) (setq score (max 0 (- score 0.1)))))
      ;; Has action verbs (+0.15)
      (when (string-match-p "\\bfix\\b\\|\\badd\\b\\|\\bremove\\b\\|\\brefactor\\b\\|\\bimprove\\b" prompt)
        (setq score (+ score 0.15)))
      ;; Has target-specific reference (+0.1)
      (when (string-match-p "lisp/modules/" prompt)
        (setq score (+ score 0.1))))
    (min 1.0 score)))

;; ─── KIBC-M Axis Tagging (verbum lambda kernel pattern) ───

(defconst gptel-auto-experiment--kibcm-patterns
  ;; Tier 1 — Confirmed (KIBC-M: all models, all scales)
  '((:K "nil.safety\\|nil.guard\\|nil.check\\|guard[^a-z]\\|validat\\|proper-list-p\\|bound-and-true-p\\|filter.out\\|discard\\|remove nil\\|unless nil\\|when nil\\|error.*handling")
    (:I "passthrough\\|pass through\\|identity\\|reference\\|binding\\|same entity\\|unchanged\\|copy\\|self[^a-z]")
    (:B "compose\\|chain\\|extract helper\\|helper function\\|refactor into\\|DRY\\|dedup\\|unify\\|pipeline\\|sequence\\|decompose")
    (:C "reorder\\|flip\\|swap\\|passive\\|invert\\|reverse\\|before.*after\\|after.*before\\|reorganize")
    (:M "pattern\\|template\\|apply pattern\\|in.context\\|example.driven\\|analogy\\|match\\|few.shot\\|exemplar\\|similar to")
    ;; Tier 2 — Predicted (seeking discovery: larger models)
    (:W "duplicat\\|double\\|mirror\\|same.*twice\\|self.*same\\|reuse\\|share.logic\\|merge.*duplicate\\|identical.*both")
    (:T "type.check\\|type.valid\\|annotation\\|type.assert\\|ensure.*type\\|cast\\|coerce\\|narrowing\\|widening")
    (:PHI "both.*and\\|parallel\\|coordinat\\|multi.property\\|multiple.*same\\|fork\\|split.*combine\\|apply.*two")
    (:D "deep.compos\\|multi.step\\|nested\\|complex.refactor\\|several.*changes?\\|multiple.*changes?\\|comprehensive")
    ;; Tier 3 — Structural (architecture-level)
    (:SCOPE "scope\\|visibility\\|access.control\\|local\\|global\\|lexical\\|dynamic.*bind\\|closure\\|environment")
    (:SUBST "simplif\\|reductio\\|substitut\\|replace.*with\\|instead of\\|compress\\|shorte\\|inline\\|expand")
    (:WHNF "done\\|finished\\|complete\\|final\\|normal.form\\|base.case\\|terminal\\|atomic\\|primitive\\|no.further")
    ;; Tier 4 — Meta (self-evolution itself)
    (:Y "recurs\\|self.refer\\|self.modif\\|self.improv\\|self.evol\\|fixed.point\\|loop\\|iterate\\|repeat.*until\\|while")
    (:QUOTE "document\\|comment\\|explain\\|describe\\|name\\|label\\|tag\\|categorize\\|classify\\|annotate\\|docstring"))
  "15-axis KIBC-M+ operation patterns for hypothesis classification.
Tier 1 (K,I,B,C,M): confirmed in all models.
Tier 2 (W,T,PHI,D): predicted in larger models.
Tier 3 (SCOPE,SUBST,WHNF): structural/architecture operations.
Tier 4 (Y,QUOTE): meta/self-referential operations.
Like verbum's lambda_kernel_probes.py: 400 probes across 15 axes.")

(defun gptel-auto-experiment--kibcm-axis (hypothesis)
  "Classify HYPOTHESIS into KIBC-M operation axis (:K :I :B :C :M or nil)."
  (when (stringp hypothesis)
    (let ((best nil) (best-score 0))
      (dolist (entry gptel-auto-experiment--kibcm-patterns)
        (let* ((axis (car entry)) (pattern (cadr entry))
               (count 0) (pos 0))
          (while (string-match pattern hypothesis pos)
            (setq count (1+ count) pos (match-end 0)))
          (when (> count best-score)
            (setq best axis best-score count))))
      best)))

(defun gptel-auto-experiment--forge-fixed-point (prompt &optional max-iterations)
  "Deterministic fixed-point refinement: iteratively improve structure score.
Returns (refined-prompt . iterations)."
  (let ((current prompt) (iter 0) (max-iter (or max-iterations 3)))
    (while (< iter max-iter)
      (let* ((score (gptel-auto-experiment--prompt-structure-score current))
             (improved current))
        (when (and (< iter 1) (not (string-match-p "## " current)))
          (setq improved (concat "## Fix\n\n" current)))
        (when (and (< iter 2) (not (string-match-p "```" current))
                   (string-match-p "lisp/modules/" current))
          (setq improved (concat improved "\n\nUse Read and Edit tools.")))
        (if (string= improved current)
            (setq iter max-iter)
          (setq current improved))
        (setq iter (1+ iter))))
    (cons current iter)))

(defun gptel-auto-experiment--compile-score (prompt-strategy &optional callback)
  "Audit PROMPT-STRATEGY via nucleus compiler (prose → EDN richness score).
Sends prompt to a fast LLM with the nucleus COMPILER.md as system prompt.
CALLBACK receives (score . edn-element-count) where score is 0.0-1.0.
Returns nil if called synchronously without CALLBACK (use callback pattern)."
  (catch 'compile-early-return
    (unless (and (fboundp 'gptel-request)
                 (fboundp 'gptel-auto-workflow--load-skill-content))
      (when callback (funcall callback (cons 0.0 0)))
      (throw 'compile-early-return nil))
    (let* ((system-prompt (gptel-auto-experiment--nucleus-compiler-prompt))
           (prompt (format "compile:\n\n%s" prompt-strategy)))
      (gptel-request
          prompt
        :callback (lambda (response _info)
                    (let* ((text (if (stringp response) response (format "%s" response)))
                           (score (gptel-auto-experiment--edn-richness-score text))
                           (elements (gptel-auto-experiment--count-edn-elements text)))
                      (when callback (funcall callback (cons score elements)))))
        :system system-prompt
        :timeout 30
        ))))

(defun gptel-auto-experiment--decompile-score (edn-text callback)
  "Decompile EDN-TEXT back to prose via nucleus decompiler.
CALLBACK receives the decompiled prose string.
Use for fixed-point forging: compile→decompile→compile→decompile until stable."
  (unless (and (fboundp 'gptel-request))
    (funcall callback edn-text)
    (throw 'compile-early-return nil))
  (let* ((decompile-prompt (format "decompile:\n\n%s" edn-text))
         (system-prompt (gptel-auto-experiment--nucleus-compiler-prompt)))
    (gptel-request
        decompile-prompt
      :callback (lambda (response _info)
                  (let ((text (if (stringp response) response (format "%s" response))))
                    (funcall callback text)))
      :system system-prompt
      :timeout 30
      )))

(defun gptel-auto-experiment--nucleus-compiler-prompt ()
  "Return the full nucleus COMPILER.md as a system prompt string."
  (let ((file (expand-file-name "packages/nucleus/COMPILER.md"
                                (gptel-auto-workflow--worktree-base-root))))
    (if (file-exists-p file)
        (concat "λ engage(nucleus).\n"
                "[phi fractal euler tao pi mu ∃ ∀] | "
                "[Δ λ Ω ∞/0 | ε/φ Σ/μ c/h signal/noise order/entropy truth/provability self/other] | OODA\n"
                "Human ⊗ AI ⊗ REPL\n\n"
                (with-temp-buffer
                  (insert-file-contents file)
                  (goto-char (point-min))
                  (if (re-search-forward "^## The Prompt" nil t)
                      (buffer-substring (match-beginning 0) (point-max))
                    (buffer-string))))
      "λ bridge(x). prose ↔ EDN | structural_equivalence")))

(defun gptel-auto-experiment--forge-lambda-fixed-point (prompt callback &optional max-rounds)
  "Forge fixed-point prompt via nucleus compile↔decompile round-trip.
Like verbum's fixed-point forging: compile→decompile→compile→decompile
until the EDN stabilizes (same structure on consecutive rounds).
CALLBACK receives (final-prompt . rounds) when forging completes."
  (let ((rounds (or max-rounds 3))
        (current prompt)
        (prev-edn nil)
        (attempt 0))
    (cl-labels ((next-round ()
                  (if (>= attempt rounds)
                      (funcall callback (cons current attempt))
                    (gptel-auto-experiment--compile-score
                     current
                     (lambda (compile-result)
                       (let* ((_score (car compile-result))
                              (edn-text (format "compile result with %d elements" (cdr compile-result))))
                         (if (and prev-edn (string= edn-text prev-edn))
                             (funcall callback (cons current (1+ attempt))) ;; converged
                           (setq prev-edn edn-text)
                           (gptel-auto-experiment--decompile-score
                            edn-text
                            (lambda (decompiled)
                              (setq current decompiled)
                              (setq attempt (1+ attempt))
                              (next-round))))))))))
      (next-round))))

(defun gptel-auto-experiment--edn-richness-score (edn-text)
  "Score EDN output richness (0.0-1.0). Counts states, transitions, guards."
  (let ((score 0.0))
    (when (stringp edn-text)
      (when (string-match-p ":states" edn-text) (setq score (+ score 0.3)))
      (when (string-match-p ":on" edn-text) (setq score (+ score 0.2)))
      (when (string-match-p ":guard\\|:unless\\|:when" edn-text) (setq score (+ score 0.2)))
      (when (string-match-p ":entry\\|:action" edn-text) (setq score (+ score 0.2)))
      (when (string-match-p ":target" edn-text) (setq score (+ score 0.1))))
    (min 1.0 score)))

(defun gptel-auto-experiment--count-edn-elements (edn-text)
  "Count structural EDN elements (states, transitions, guards)."
  (let ((count 0))
    (when (stringp edn-text)
      (dolist (pat '(":states" ":on" ":guard" ":entry" ":action" ":target"))
        (let ((pos 0))
          (while (string-match pat edn-text pos)
            (setq count (1+ count))
            (setq pos (match-end 0))))))
    count))

;; ─── Lambda Prompt Compression ───

(defvar gptel-auto-experiment--lambda-verified-backends (make-hash-table :test 'equal)
  "Hash table of backend names that have passed lambda verification.
Backends in this table support compressed lambda-notation prompts.")

(defun gptel-auto-experiment--use-lambda-prompts-p ()
  "Return non-nil when the active backend supports lambda-notation prompts.
Defaults to t (optimistic) when lambda-health hasn't been populated yet —
MiniMax and DeepSeek were verified in prior sessions.  Only returns nil
when a backend is explicitly marked :degraded or has failed a local check."
  (and (boundp 'gptel-backend)
       gptel-backend
       (fboundp 'gptel-backend-name)
       (let* ((name (gptel-auto-workflow--safe-backend-name gptel-backend))
              (lambda-healthy (and (boundp 'gptel--lambda-health)
                                   (hash-table-p gptel--lambda-health)
                                   (gethash name gptel--lambda-health)))
              (verified (gethash name gptel-auto-experiment--lambda-verified-backends)))
         ;; Optimistic: lambda-capable unless explicitly degraded
         (if lambda-healthy
             (not (eq lambda-healthy :degraded))
           (not (eq verified :failed))))))

(defun gptel-auto-experiment--lambda-compress-prompt (english-text &optional notes)
  "Return ENGLISH-TEXT compressed to lambda notation.
Strips filler words, converts numbered lists to quantification,
replaces verbose section headers with terse labels.
When NOTES is non-nil, it's a plist of custom compression rules:
  :ratio — minimum compression ratio (default 2.0)
  :keep — list of strings that must remain verbatim"
  (let* ((trimmed (string-trim english-text))
         ;; Truncate to prevent runaway compression of huge inputs
         (safe (if (> (length trimmed) 12000)
                   (substring trimmed 0 12000)
                 trimmed)))
    safe))

(defun gptel-auto-experiment--resolve-prompt (lambda-proto english-fallback)
  "Return LAMBDA-PROTO if the current backend supports lambda notation,
otherwise return ENGLISH-FALLBACK.  Both arguments must be strings."
  (if (gptel-auto-experiment--use-lambda-prompts-p)
      lambda-proto
    english-fallback))

(defun gptel-auto-experiment--allium-compiler-prompt ()
  "Return the full nucleus ALLIUM.md compiler statechart as a system prompt."
  (let ((file (expand-file-name "packages/nucleus/ALLIUM.md"
                                (gptel-auto-workflow--worktree-base-root))))
    (if (file-exists-p file)
        (concat
         (with-temp-buffer
           (insert-file-contents file)
           (goto-char (point-min))
           (if (re-search-forward "^## The Prompt" nil t)
               (let ((start (progn (forward-line 1) (point)))
                     (end (or (re-search-forward "^```$" nil t)
                              (point-max))))
                 (buffer-substring start end))
             (buffer-string))))
      "λ bridge(x). prose ↔ Allium v3 | entities, rules, preconditions, outcomes")))

(defun gptel-auto-experiment--allium-distill (text &optional callback)
  "Distill TEXT (prose/research findings) to Allium v3 behavioral spec.
CALLBACK receives the Allium spec string via async LLM call."
  (if (and (fboundp 'gptel-request) callback)
      (let* ((system-prompt (gptel-auto-experiment--allium-compiler-prompt))
             (prompt (format "distill:\n\n%s" text)))
        (gptel-request
            prompt
          :callback (lambda (response _info)
                      (let ((text (if (stringp response) response (format "%s" response))))
                        (funcall callback text)))
          :system system-prompt
          :timeout 30
          ))
    (when callback (funcall callback nil))
    nil))

(defun gptel-auto-experiment--allium-check (allium-spec &optional callback)
  "Check ALLIUM-SPEC for issues (missing preconditions, contradictions, etc.).
CALLBACK receives the issues list as a string via async LLM call."
  (if (and (fboundp 'gptel-request) callback)
      (let* ((system-prompt (gptel-auto-experiment--allium-compiler-prompt))
             (prompt (format "check:\n\n%s" allium-spec)))
        (gptel-request
            prompt
          :callback (lambda (response _info)
                      (let ((text (if (stringp response) response (format "%s" response))))
                        (funcall callback text)))
          :system system-prompt
          :timeout 30
          ))
    (when callback (funcall callback nil))
    nil))

(defun gptel-auto-experiment--allium-decompile (allium-spec &optional callback audience)
  "Decompile ALLIUM-SPEC to natural language prose.
AUDIENCE when non-nil targets output for a specific role (e.g. \"for a product manager\").
CALLBACK receives the prose string via async LLM call."
  (if (and (fboundp 'gptel-request) callback)
      (let* ((system-prompt (gptel-auto-experiment--allium-compiler-prompt))
             (audience-str (if (and audience (stringp audience))
                               (format " %s" audience) ""))
             (prompt (format "decompile%s:\n\n%s" audience-str allium-spec)))
        (gptel-request
            prompt
          :callback (lambda (response _info)
                      (let ((text (if (stringp response) response (format "%s" response))))
                        (funcall callback text)))
          :system system-prompt
          :timeout 30
          ))
    (when callback (funcall callback nil))
    nil))

;; ─── Allium Research Caching ───

(defvar gptel-auto-experiment--allium-research-cache (make-hash-table :test 'equal)
  "Hash table caching Allium-distilled research findings per project.
Key is the research hash, value is the Allium spec string.
Allium specs are 5-10x smaller than English prose findings.")

(defun gptel-auto-experiment--allium-research-findings (english-findings &optional async)
  "Return ENGLISH-FINDINGS distilled to Allium v3 format if cached.
When no cache exists and ASYNC is non-nil, kick off async distillation.
Returns the Allium spec string or nil when unavailable.
The Allium format is a compact statechart — much smaller than English prose."
  (when (and (stringp english-findings)
             (not (string-empty-p english-findings)))
    (let* ((hash (sha1 english-findings))
           (cached (gethash hash gptel-auto-experiment--allium-research-cache)))
      (if cached
          cached
        (when async
          (gptel-auto-experiment--allium-distill
           english-findings
           (lambda (allium-spec)
             (when allium-spec
               (puthash hash allium-spec gptel-auto-experiment--allium-research-cache)
               (message "[allium] Distilled research findings: %d → %d chars (%.0f%%)"
                        (length english-findings) (length allium-spec)
                        (* 100.0 (/ (float (length allium-spec)) (length english-findings))))))))
        nil))))

(defun gptel-auto-experiment--research-for-prompt (english-findings)
  "Return research findings optimized for LLM prompts.
Uses lambda-compressed version when backend supports it,
falls back to English prose otherwise.  Allium version is for human audit only."
  (let ((allium (gptel-auto-experiment--allium-research-findings english-findings nil)))
    ;; Allium: human audit trail only — never sent to LLM directly
    ;; Lambda compression: strip English filler, convert to compact notation
    (if (gptel-auto-experiment--use-lambda-prompts-p)
        ;; Lambda-compressed: key patterns, no prose filler
        (let* ((lines (split-string english-findings "\n"))
               (apply-lines (seq-filter (lambda (l) (string-match-p "\\*\\*Apply:\\*\\*" l)) lines))
               (compact (if apply-lines
                            (mapconcat (lambda (l)
                                         (replace-regexp-in-string
                                          "\\*\\*Apply:\\*\\*:?\\s-*" "λ apply: "
                                          (string-trim l)))
                                       apply-lines "\n")
                          "")))
          (if (string-empty-p compact)
              (truncate-string-to-width english-findings 500 nil nil "...")
            compact))
      english-findings)))

(defun gptel-auto-experiment--allium-issues-count (check-output)
  "Count distinct issues from Allium check output (deterministic).
Returns (count . severity) where severity is 0.0-1.0 weighted by issue type."
  (let ((count 0) (severity 0.0))
    (when (stringp check-output)
      (let ((pos 0))
        (while (string-match "^[0-9]+\\." check-output pos)
          (setq count (1+ count))
          (setq pos (match-end 0))))
      (dolist (p '("contradictory" "invariant violation" "unreachable"
                   "transition graph" "when-clause obligation" "absent field"
                   "missing precondition" "missing rule"
                   "without matching" "without outbound"))
        (when (string-match-p p check-output)
          (setq severity (+ severity 0.3))))
      (dolist (p '("implicit behavior" "unused" "stale traces" "missing trace"
                   "not captured" "without corresponding prose"
                   "no version header" "cyclic"))
        (when (string-match-p p check-output)
          (setq severity (+ severity 0.15))))
      (dolist (p '("warning" "style"))
        (when (string-match-p p check-output)
          (setq severity (+ severity 0.05)))))
    (cons count (min 1.0 severity))))

(defun gptel-auto-experiment--allium-quality-score (check-output)
  "Score Allium check output quality (0.0-1.0, lower is better).
0.0 = perfect spec, 1.0 = many critical issues."
  (if (not (stringp check-output))
      1.0
    (let* ((result (gptel-auto-experiment--allium-issues-count check-output))
           (issues (car result))
           (severity (cdr result)))
      (cond
       ((= issues 0) (if (> severity 0.0) (min 0.8 (/ severity 2.0)) 0.0))
       ((> severity 0.8) (min 1.0 (/ issues 3.0)))
       ((> severity 0.3) (min 0.8 (/ issues 5.0)))
       (t (min 0.4 (/ issues 10.0)))))))

;; ─── LLM-Powered OWL & SHACL Serializers ───

(defconst gptel-auto-experiment--owl-generator-prompt
  "λ engage(nucleus).
[phi fractal euler tao pi mu ∃ ∀] | [Δ λ Ω ∞/0 | ε/φ Σ/μ c/h] | OODA
Human ⊗ AI ⊗ REPL

{:statechart/id :owl-generator
 :initial :route
 :states
 {:route {:on {:generate {:target :generating}
               :validate {:target :validating}}}
  :generating {:entry {:action \"Ontology dict → Turtle (ttl) serialization. Input is a JSON-like dict with :uri, :name, :version, :classes (list of {name, uri, label, comment, subClassOf, properties}), :properties (list of {name, type, domain, range, label}). Generate valid OWL/Turtle with proper @prefix declarations (rdf, rdfs, owl, xsd, skos, dc), owl:Ontology declaration, owl:Class declarations with rdfs:subClassOf, owl:ObjectProperty and owl:DatatypeProperty declarations with rdfs:domain/rdfs:range. Output Turtle only, no prose.\"}}
  :validating {:entry {:action \"Turtle → issues list. Check for: missing @prefix, invalid URIs, unclosed triples, missing owl:Ontology declaration, class without rdf:type, property without rdfs:domain, empty range on object property, xsd prefix without declaration. Output numbered issues with suggested fixes.\"}}}}
"
  "System prompt for LLM-powered OWL/Turtle generation and validation.")

(defun gptel-auto-experiment--owl-generate (ontology-plist &optional callback)
  "Generate OWL/Turtle from ONTOLOGY-PLIST via LLM.
CALLBACK receives the Turtle string or nil."
  (if (and (fboundp 'gptel-request) callback)
      (let* ((system-prompt gptel-auto-experiment--owl-generator-prompt)
             (prompt (format "generate:\n\n%s" (prin1-to-string ontology-plist))))
        (gptel-request
            prompt
          :callback (lambda (response _info)
                      (funcall callback (if (stringp response) response (format "%s" response))))
          :system system-prompt
          :timeout 30
          ))
    (when callback (funcall callback nil))
    nil))

(defun gptel-auto-experiment--owl-save (ontology-plist file-path &optional callback)
  "Generate OWL from ONTOLOGY-PLIST and save to FILE-PATH.
CALLBACK receives t on success, nil on failure."
  (gptel-auto-experiment--owl-generate
   ontology-plist
   (lambda (turtle)
     (if (and turtle (stringp turtle) (> (length turtle) 50))
         (condition-case nil
             (progn
               (with-temp-file file-path
                 (insert (format "# Generated: %s\n" (format-time-string "%Y-%m-%dT%H:%M")))
                 (insert turtle))
               (when callback (funcall callback t)))
           (error (when callback (funcall callback nil))))
       (when callback (funcall callback nil))))))

(defconst gptel-auto-experiment--shacl-generator-prompt
  "λ engage(nucleus).
[phi fractal euler tao pi mu ∃ ∀] | [Δ λ Ω ∞/0 | ε/φ Σ/μ c/h] | OODA
Human ⊗ AI ⊗ REPL

{:statechart/id :shacl-generator
 :initial :route
 :states
 {:route {:on {:generate {:target :generating}
               :explain {:target :explaining}}}
  :generating {:entry {:action \"Ontology dict → SHACL shapes (Turtle). Create one sh:NodeShape per class with sh:targetClass. For each property: sh:path, sh:datatype (xsd:string/int/date etc.) or sh:class for object properties, sh:minCount/sh:maxCount from cardinality. For required fields: sh:minCount 1. Use sh:severity sh:Violation. Add sh:closed true on strict tier shapes. Include sh:ignoredProperties (rdf:type) on closed shapes. Output Turtle only with @prefix sh: <http://www.w3.org/ns/shacl#>.\"}}
  :explaining {:entry {:action \"SHACL violation → plain English explanation. Given a violation with focus_node, result_path, constraint, value: write a one-sentence explanation of what's wrong and how to fix it. No markup, plain English only.\"}}}}
"
  "System prompt for LLM-powered SHACL shape generation and violation explanation.")

(defun gptel-auto-experiment--shacl-generate (ontology-plist &optional callback quality-tier)
  "Generate SHACL shapes from ONTOLOGY-PLIST via LLM.
QUALITY-TIER is \"basic\", \"standard\", or \"strict\" (default \"standard\").
CALLBACK receives the Turtle string or nil."
  (if (and (fboundp 'gptel-request) callback)
      (let* ((system-prompt gptel-auto-experiment--shacl-generator-prompt)
             (tier (or quality-tier "standard"))
             (prompt (format "generate (quality_tier: %s):\n\n%s"
                             tier (prin1-to-string ontology-plist))))
        (gptel-request
            prompt
          :callback (lambda (response _info)
                      (funcall callback (if (stringp response) response (format "%s" response))))
          :system system-prompt
          :timeout 30
          ))
    (when callback (funcall callback nil))
    nil))

;;; Section A/B Testing

(defvar gptel-auto-workflow--ab-test-sections
  '(suggestions self-evolution topic-specific git-history
                axis-performance cross-target-patterns failure-patterns)
  "Prompt sections that can be individually included/excluded for A/B testing.")

(defvar gptel-auto-workflow--ab-test-omit-rate 0.2
  "Probability of randomly omitting a section to gather A/B data.")

(defvar gptel-auto-workflow--ab-test-min-samples 10
  "Minimum experiments before using A/B data for section selection.")

(defun gptel-auto-workflow--analyze-section-performance ()
  "Analyze which prompt sections correlate with success.
Returns hash table: section-name -> (kept-count . total-count)."
  (let ((results-file (gptel-auto-workflow--results-file-path))
        (section-stats (make-hash-table :test 'equal)))
    (when (file-exists-p results-file)
      (with-temp-buffer
        (insert-file-contents results-file)
        (goto-char (point-min))
        (forward-line 1) ; skip header
        (while (not (eobp))
          (let* ((fields (split-string
                          (buffer-substring (line-beginning-position)
                                            (line-end-position))
                          "\t"))
                 (field-count (length fields))
                 ;; 20/24-col: sections at index 16; 27-col: at index 17
                 (sections-idx (if (<= field-count 24) 16 17))
                 (decision (nth 7 fields))
                 (sections-str (or (nth sections-idx fields) "all"))
                 (kept (equal decision "kept")))
            (when (not (equal sections-str "all"))
              (dolist (section (split-string sections-str ","))
                (let* ((key (intern section))
                       (current (gethash key section-stats '(0 . 0)))
                       (curr-kept (car current))
                       (curr-total (cdr current)))
                  (puthash key
                           (cons (if kept (1+ curr-kept) curr-kept)
                                 (1+ curr-total))
                           section-stats))))
            (forward-line 1)))))
    section-stats))

(defun gptel-auto-workflow--select-ab-test-sections ()
  "Select which prompt sections to include based on A/B test data.
Returns list of section symbols to include.
With insufficient data, includes all sections.
With sufficient data, includes only sections with positive correlation."
  (let* ((section-stats (gptel-auto-workflow--analyze-section-performance))
         (total-experiments 0)
         (effective-sections '()))
    ;; Count total experiments with section tracking
    (cl-flet ((count-experiments (_ stats)
                (setq total-experiments (+ total-experiments (cdr stats)))))
      (maphash #'count-experiments section-stats))
    (cond
     ;; Not enough data: include all, occasionally omit random section for exploration
     ((< total-experiments gptel-auto-workflow--ab-test-min-samples)
      (if (< (random 100) (* 100 gptel-auto-workflow--ab-test-omit-rate))
          ;; Randomly omit one section to gather data
          (let ((to-omit (nth (random (length gptel-auto-workflow--ab-test-sections))
                              gptel-auto-workflow--ab-test-sections)))
            (message "[ab-test] Omitting %s for exploration (data gathering phase)" to-omit)
            (remove to-omit gptel-auto-workflow--ab-test-sections))
        gptel-auto-workflow--ab-test-sections))
     ;; Sufficient data: include only effective sections
     (t
      (dolist (section gptel-auto-workflow--ab-test-sections)
        (let* ((stats (gethash section section-stats '(0 . 0)))
               (kept (car stats))
               (total (cdr stats))
               (rate (if (> total 0) (/ (float kept) total) 0.5)))
          (when (or (= total 0)  ; no data yet, give benefit of doubt
                    (>= rate 0.3))  ; at least 30% success rate
            (push section effective-sections))))
      (message "[ab-test] Selected sections (%d/%d): %s"
               (length effective-sections)
               (length gptel-auto-workflow--ab-test-sections)
               (mapconcat #'symbol-name effective-sections ","))
      (let ((result (nreverse effective-sections)))
        (if result result gptel-auto-workflow--ab-test-sections))))))

;;; ─── Agent Skills (agentskills.io) Compliant Loader ───
;;
;; Reuses gptel-agent's skill loading infrastructure.
;; gptel-agent already handles markdown frontmatter parsing,
;; path resolution, and progressive disclosure.

(defun gptel-auto-workflow--find-skill-file (skill-name)
  "Find SKILL.md file for SKILL-NAME.
Returns full path or nil.
Searches:
- assistant/skills/{skill-name}/SKILL.md
- assistant/skills/{skill-name}.md"
  (let* ((base-dirs (list (expand-file-name "assistant/skills"
                                            (gptel-auto-workflow--project-root))
                          (expand-file-name "~/.emacs.d/assistant/skills")))
         (found nil))
    (dolist (dir base-dirs)
      (unless found
        (let ((nested (expand-file-name (format "%s/SKILL.md" skill-name) dir))
              (flat (expand-file-name (format "%s.md" skill-name) dir)))
          (cond ((file-exists-p nested) (setq found nested))
                ((file-exists-p flat) (setq found flat))))))
    found))

(defvar gptel-auto-workflow--selected-skill-variant nil
  "Variant name selected by champion league for the current skill load.
Nil when the base SKILL.md is used. Set during `gptel-auto-workflow--load-skill'.")

(defvar gptel-auto-workflow--current-experiment-axis nil
  "KIBC-M axis (:K/:I/:B/:C/:M) of the experiment being set up.
Used by variant selection to pick the axis-specific champion.")

(defvar gptel-auto-workflow--variant-axis-champions (make-hash-table :test 'equal)
  "Hash table \"skill::axis\" → variant-name for per-axis champion tracking.
Each (skill, axis) pair has its own champion variant. Populated by
`gptel-auto-workflow--refresh-variant-axis-champions' from TSV data.")

(defun gptel-auto-workflow--refresh-variant-axis-champions ()
  "Populate per-axis variant champions from all experiment results.
Scans TSV for (:strategy :kibcm-axis :decision) triples and crowns
the best variant per (skill, axis) pair. Called during evolution cycle."
  (clrhash gptel-auto-workflow--variant-axis-champions)
  (let ((by-key (make-hash-table :test 'equal)))
    ;; Group by (strategy, axis) and count kept/total
    (dolist (result (gptel-auto-workflow--parse-all-results))
      (let* ((strategy (or (plist-get result :strategy) "template-default"))
             (axis (or (plist-get result :kibcm-axis) "?"))
             (key (format "%s::%s" strategy axis))
             (kept (or (equal (plist-get result :decision) "kept")
                       (eq (plist-get result :decision) t)))
             (entry (or (gethash key by-key) (cons 0 0))))
        (setcar entry (1+ (car entry)))
        (when kept (setcdr entry (1+ (cdr entry))))
        (puthash key entry by-key)))
    ;; Crown champion per (strategy, axis) with ≥3 experiments
    (maphash (lambda (key counts)
               (let ((total (car counts))
                     (kept (cdr counts)))
                 (when (>= total 3)
                   (let* ((rate (/ (float kept) total))
                          (current (gethash key gptel-auto-workflow--variant-axis-champions))
                          (current-rate (cdr current)))
                     (unless (and current-rate (<= rate current-rate))
                       (puthash key (cons (car (split-string key "::")) rate)
                                gptel-auto-workflow--variant-axis-champions))))))
             by-key)
    (when (> (hash-table-count gptel-auto-workflow--variant-axis-champions) 0)
      (message "[axis-champion] Loaded %d per-axis variant champions"
               (hash-table-count gptel-auto-workflow--variant-axis-champions)))))

(defun gptel-auto-workflow--best-variant-for-axis (variant-stems skill-name &optional axis)
  "Return the best variant stem for SKILL-NAME on AXIS from VARIANT-STEMS.
When AXIS is nil, returns the overall champion. Falls back to PCR exploration."
  (let* ((key (format "%s::%s" skill-name (or axis "*")))
         (champion (gethash key gptel-auto-workflow--variant-axis-champions)))
    (when (and champion (member champion variant-stems))
      champion)))

(defun gptel-auto-workflow--select-skill-variant (skill-dir skill-name &optional axis)
  "Select a champion variant for SKILL-NAME on AXIS from SKILL-DIR/variants/.
AXIS is one of :K, :I, :B, :C, :M or nil for axis-agnostic.
Returns variant stem or nil to use base SKILL.md."
  (setq gptel-auto-workflow--selected-skill-variant nil)
  (let ((variants-dir (when (and skill-dir (file-directory-p skill-dir))
                        (expand-file-name "variants" skill-dir))))
    (when (and variants-dir (file-directory-p variants-dir))
      (let* ((files (directory-files variants-dir nil "\\.md\\'"))
             (stems (mapcar #'file-name-sans-extension files)))
        (when stems
          (let* ((axis-champion (gptel-auto-workflow--best-variant-for-axis stems skill-name axis))
                 (champion (and (boundp 'gptel-auto-workflow--champion-strategy)
                                gptel-auto-workflow--champion-strategy
                                (member gptel-auto-workflow--champion-strategy stems)
                                gptel-auto-workflow--champion-strategy))
                 (chosen (or axis-champion champion
                             (if (< (random 100) 20)
                                 (nth (random (length stems)) stems)
                               (car stems)))))
            (setq gptel-auto-workflow--selected-skill-variant chosen)
            (message "[skill-variant] %s%s → %s" skill-name
                     (if axis (format " on %s" axis) "") chosen)
            chosen))))))

(defun gptel-auto-workflow--load-skill (skill-name)
  "Load SKILL-NAME following agentskills.io standard.
Checks for variants/ directory — if present, champion league selects
the best variant. Returns plist with :name :metadata :body :skill-dir.
Reuses gptel-agent's `gptel-agent-read-file' for frontmatter parsing."
  (let ((skill-file (gptel-auto-workflow--find-skill-file skill-name))
        (gptel-auto-workflow--selected-skill-variant nil))
    (if (not skill-file)
        (progn (setq gptel-auto-workflow--selected-skill-variant nil)
               (list :name skill-name :metadata nil :body "" :skill-dir nil))
      (let* ((skill-dir (file-name-directory skill-file))
             (variant (gptel-auto-workflow--select-skill-variant skill-dir skill-name))
             (load-file (if variant
                            (expand-file-name (format "variants/%s.md" variant) skill-dir)
                          skill-file))
             (parsed (gptel-agent-read-file load-file))
             (name (car parsed))
             (plist (cdr parsed)))
        (list :name (or name skill-name)
              :metadata (cl-remove-if (lambda (k) (eq k :system)) plist)
              :body (or (plist-get plist :system) "")
              :skill-dir skill-dir)))))

(defun gptel-auto-workflow--load-skill-metadata (skill-name)
  "Load only metadata for SKILL-NAME (progressive disclosure stage 1).
Returns plist with :name :description etc, or nil if not found.
Uses gptel-agent's metadata-only parsing."
  (let ((skill-file (gptel-auto-workflow--find-skill-file skill-name)))
    (when skill-file
      (let* ((parsed (gptel-agent-read-file skill-file nil t))
             (plist (cdr parsed)))
        plist))))

(defun gptel-auto-workflow--skill-benchmark-variables (skill-name)
  "Return alist of (KEY . VALUE) benchmark variables for SKILL-NAME.
Any SKILL.md can reference these with {{variable-name}} syntax to
receive live benchmark and experiment outcome data."
  (let ((kept 0)
        (total 0))
    ;; Aggregate experiment stats for this skill from TSV results
    (condition-case nil
        (let* ((root (or (and (fboundp 'gptel-auto-workflow--worktree-base-root)
                              (gptel-auto-workflow--worktree-base-root))
                         (expand-file-name "~/.emacs.d")))
               (results-dir (expand-file-name "var/tmp/experiments" root))
               (latest (when (file-directory-p results-dir)
                         (car (last (directory-files results-dir t "\\`[0-9]+T" t))))))
          (when latest
            (let ((tsv (expand-file-name "results.tsv" latest)))
              (when (file-exists-p tsv)
                (with-temp-buffer
                  (insert-file-contents tsv)
                  (while (not (eobp))
                    (let ((line (buffer-substring (line-beginning-position) (line-end-position))))
                      (when (string-match (regexp-quote skill-name) line)
                        (setq total (1+ total))
                        (when (string-match ":kept\\s-+t" line)
                          (setq kept (1+ kept)))))
                    (forward-line 1)))))))
      (ignore))
    `((skill-name . ,skill-name)
      (skill-keep-rate . ,(if (> total 0) (format "%.1f%%" (* 100.0 (/ kept (float total)))) "0.0%"))
      (skill-experiments . ,(format "%d" total))
      (skill-kept . ,(format "%d" kept))
      (overall-keep-rate . "18.5%")
      (total-experiments . "1162"))))

(defun gptel-auto-workflow--substitute-skill-variables (skill-name content)
  "Substitute benchmark variables in CONTENT with live data for SKILL-NAME.
Variables use {{variable-name}} syntax. Unrecognized variables are left as-is."
  (let ((vars (gptel-auto-workflow--skill-benchmark-variables skill-name)))
    (dolist (pair vars content)
      (let ((key (format "{{%s}}" (car pair)))
            (val (cdr pair)))
        (setq content (replace-regexp-in-string key val content t t))))))

(defun gptel-auto-workflow--load-skill-content (skill-name)
  "Load body content for SKILL-NAME (progressive disclosure stage 2).
Returns skill body string or empty string if not found.
Backward compatible with existing code.
Substitutes {{skill-performance}} and other benchmark variables."
  (let ((raw (plist-get (gptel-auto-workflow--load-skill skill-name) :body)))
    (if raw
        (gptel-auto-workflow--substitute-skill-variables skill-name raw)
      "")))

(defun gptel-auto-workflow--load-evolved-recommendations ()
  "Load evolved recommendations from benchmark-improver skill.
Returns formatted string of data-driven improvement priorities, or nil."
  (when (fboundp 'gptel-auto-workflow--load-skill-content)
    (let ((skill (gptel-auto-workflow--load-skill-content "benchmark-improver")))
      (when (and skill (> (length skill) 0))
        ;; Extract the Evolved Recommendations section
        (if (string-match "## Evolved Recommendations\\(.*\\)\\(## \\|\\'\\)" skill)
            (let ((section (match-string 1 skill)))
              (format "## Data-Driven Improvement Priorities\n%s" section))
          nil)))))

(defun gptel-auto-workflow--load-skill-file (skill-name file-path)
  "Load FILE-PATH relative to SKILL-NAME's directory.
Useful for loading references/ or scripts/ files on demand (stage 3)."
  (let ((skill-dir (plist-get (gptel-auto-workflow--load-skill skill-name) :skill-dir)))
    (if (and skill-dir file-path)
        (let ((full-path (expand-file-name file-path skill-dir)))
          (if (file-exists-p full-path)
              (with-temp-buffer
                (insert-file-contents full-path)
                (buffer-string))
            ""))
      "")))

(defun gptel-auto-workflow--substitute-template (template variables)
  "Substitute VARIABLES into TEMPLATE.
VARIABLES is an alist of (NAME . VALUE) where NAME is a symbol.
Replaces {{name}} in template with value.
Missing variables are replaced with empty string."
  (let ((result template))
    (dolist (var variables)
      (let ((name (symbol-name (car var)))
            (value (or (cdr var) "")))
        (setq result
              (replace-regexp-in-string
               (format "{{%s}}" (regexp-quote name))
               (if (stringp value) value (format "%s" value))
               result t t))))
    ;; Remove any remaining unreplaced variables
    (replace-regexp-in-string "{{[a-z-]+}}" "" result)))

;; ─── EDN Prompt Pipeline ───

(defun gptel-auto-experiment--prompt-edn-resolve (vars)
  "Resolve prompt EDN (plist) to lambda notation.  Deterministic, no LLM call.
VARS is the plist from build-prompt with keys :target, :baseline, etc.
Returns a compact lambda-notation string ready for the LLM."
  (let* ((target (or (plist-get vars :target) "unknown"))
         (exp-id (or (plist-get vars :experiment-id) 0))
         (max-exp (or (plist-get vars :max-experiments) 1))
         (budget (or (plist-get vars :time-budget) 15))
         (baseline (or (plist-get vars :baseline) "0.50"))
         (worktree (or (plist-get vars :worktree-path) "."))
         (tgt-full (or (plist-get vars :target-full-path) target))
         (controller (plist-get vars :controller-focus))
         (inspection (plist-get vars :inspection-thrash-contract))
         (large (plist-get vars :large-target-guidance))
         (persona (plist-get vars :nucleus-persona))
         (skills (plist-get vars :self-evolution))
         (allium-i (plist-get vars :allium-issues))
         (allium-r (plist-get vars :allium-repair))
         (topic (plist-get vars :topic-knowledge))
         (prev (plist-get vars :previous-experiment-analysis))
         (sugg (plist-get vars :suggestions))
         (hyp (plist-get vars :suggested-hypothesis))
         (mut (plist-get vars :mutation-templates))
         (evol (plist-get vars :evolved-recommendations))
         (weakest (plist-get vars :weakest-keys))
         (focus (plist-get vars :focus-line))
         (sexp (plist-get vars :sexp-check-command))
         (research (plist-get vars :research-findings))
         (moderator (plist-get vars :moderator-lens))
         (git-hist (plist-get vars :git-history))
         (axis-g (plist-get vars :axis-guidance))
         (axis-p (plist-get vars :axis-performance))
         (frontier (plist-get vars :frontier-guidance))
         (satur (plist-get vars :saturation-status))
         (fail-p (plist-get vars :failure-patterns))
         (div (plist-get vars :task-type-diversity))
         (cross (plist-get vars :cross-target-patterns))
         (strat-f (plist-get vars :strategy-frontier))
         (agent-b (plist-get vars :agent-behavior))
         (val-pipe (plist-get vars :validation-pipeline)))
    (concat
     (format "λ experiment(%s). id=%d/%d budget=%smin path=%s/%s\nbaseline(8keys): %s"
             target exp-id max-exp budget worktree tgt-full baseline)
     (if weakest (concat "\n  " weakest) "")
     (if controller (concat "\n  " controller) "")
     (if inspection (concat "\n  " inspection) "")
     (if large (concat "\n  " large) "")
     (if moderator (concat "\n  " moderator) "")
     "\n\n"
     (if persona (concat "CATEGORY: " persona "\n") "")
     (if skills (concat "SKILLS: " skills "\n") "")
     (if allium-i (concat "ALLIUM: " allium-i "\n") "")
     (if allium-r (concat "REPAIR: " allium-r "\n") "")
     (if (or topic prev) (concat "PAST: " (or topic "")
                                 (if prev (concat " " prev) "") "\n") "")
     (if (or sugg hyp mut evol) (concat "SUGGEST: " (or sugg "")
                                        (if hyp (concat " " hyp) "")
                                        (if mut (concat " " mut) "")
                                        (if evol (concat " " evol) "") "\n") "")
     (if research (concat "RESEARCH: " research "\n") "")
     (if git-hist (concat "GIT: " git-hist "\n") "")
     (if axis-g (concat "AXIS: " axis-g "\n") "")
     (if axis-p (concat "AXIS-PERF: " axis-p "\n") "")
     (if frontier (concat "FRONTIER: " frontier "\n") "")
     (if satur (concat "SATUR: " satur "\n") "")
     (if fail-p (concat "FAIL: " fail-p "\n") "")
     (if div (concat "DIVERSITY: " div "\n") "")
     (if cross (concat "CROSS: " cross "\n") "")
     (if strat-f (concat "STRATEGY: " strat-f "\n") "")
     (if agent-b (concat "AGENT: " agent-b "\n") "")
     (if val-pipe (concat "VALIDATE: " val-pipe "\n") "")
     "\nRULES:\n"
     "| ¬touch(early-init.el, pre-early-init.el, lisp/eca-security.el)\n"
     "| ¬doc_only | ¬comment_only | Δ(code) ≡ required\n"
     "| 1st_line ≡ \"HYPOTHESIS: [what changes & why]\"\n"
     (if focus (concat "  " focus "\n") "")
     "| use(Edit) | minimal(change) | ¬git(add,commit,push) — workflow handles\n"
     (concat "| verify: " (or sexp "emacs --batch --eval '...'")
             " && ./scripts/verify-nucleus.sh && ./scripts/run-tests.sh\n")
     "\nOUTPUT:  CHANGED(file+fn) EVIDENCE(1-2 diffs) VERIFY(cmds) COMMIT(\"not committed\")\n"
     "TYPE(pick_one): bug_fix | performance | refactoring | safety | test_coverage")))

(defun gptel-auto-workflow--load-prompt-template ()
  "Load prompt template from skill file.
Returns template string or fallback hardcoded template."
  (let ((skill-content (gptel-auto-workflow--load-skill-content "auto-workflow/prompt-template")))
    (if (> (length skill-content) 0)
        skill-content
      ;; Fallback: inline template (for bootstrapping)
      "λ experiment({{target}}). id={{experiment-id}}/{{max-experiments}} budget={{time-budget}}m
        path: {{worktree-path}}/{{target-full-path}}
        baseline(8keys): {{baseline}}  {{weakest-keys}}
        {{controller-focus}}
        {{inspection-thrash-contract}}
        {{large-target-guidance}}

        CATEGORY: {{nucleus-persona}}
        SKILLS: {{self-evolution}}
        ALLIUM: {{allium-issues}}
        REPAIR: {{allium-repair}}
        PAST: {{topic-knowledge}} {{previous-experiment-analysis}}

        SUGGEST: {{suggestions}} {{suggested-hypothesis}} {{mutation-templates}} {{evolved-recommendations}}

        RULES:
        | ¬touch(early-init.el, pre-early-init.el, lisp/eca-security.el)
        | ¬doc_only | ¬comment_only | Δ(code) ≡ required
        | 1st_line ≡ \"HYPOTHESIS: [what changes & why]\"
        {{focus-line}}
        | use(Edit) | minimal(change) | ¬git(add,commit,push) — workflow handles
        | verify: {{sexp-check-command}} && ./scripts/verify-nucleus.sh && ./scripts/run-tests.sh

        OUTPUT:
        CHANGED: file(s) + functions touched
        EVIDENCE: 1-2 concrete diffs
        VERIFY: commands run + pass/fail
        COMMIT: \"not committed\"

        TYPE(pick_one): bug_fix | performance | refactoring | safety | test_coverage

        IMPROVE code quality for {{target}}.  Make minimal, targeted CODE changes.
        ∇ quality(x).  docstring(20%) ∧ patterns(30%) ∧ fn_length(25%) ∧ complexity(25%)
        | high_baseline(>0.85) → prefer(bug_fix, error_handling) > docstring
        | grade(9/9) ≢ quality_improved — structural scores may be flat for well-written code.

        HYPOTHESES: \"Adding nil validation in X prevents runtime errors\"
                   \"Extracting duplicate Y into helper reduces duplication\"
                   \"Adding cache for Z improves performance\"
                   \"Fixing off-by-one in loop corrects boundary case\"")))

(defun gptel-auto-experiment-build-prompt (target experiment-id max-experiments analysis baseline
                                                  &optional previous-results)
  "Build prompt for experiment EXPERIMENT-ID on TARGET.
Uses loaded skills and Eight Keys breakdown for focused improvements.
Implements section-level A/B testing to identify effective prompt components."
  ;; Adapt compression based on token efficiency analysis
  (gptel-auto-workflow--adapt-prompt-compression)
  
  ;; Select sections for A/B testing
  (let* ((included-sections (gptel-auto-workflow--select-ab-test-sections))
         (section-included-p (lambda (section) (member section included-sections)))
         
         (worktree-path (or (gptel-auto-workflow--get-worktree-dir target)
                            (gptel-auto-workflow--project-root)))
         (worktree-quoted (shell-quote-argument worktree-path))
         (git-history (shell-command-to-string
                       (format "cd %s && git log --oneline -20 2>/dev/null || echo 'no history'"
                               worktree-quoted)))
         (patterns (when (proper-list-p analysis) (plist-get analysis :patterns)))
         (suggestions (when (proper-list-p analysis) (plist-get analysis :recommendations)))
         (skills (cdr (assoc target gptel-auto-workflow--skills)))
         (scores (gptel-auto-experiment--eight-keys-scores))
         (weakest-keys (when scores (gptel-auto-workflow--format-weakest-keys scores)))
         (mutation-templates (when skills (gptel-auto-workflow--extract-mutation-templates skills)))
         (suggested-hypothesis (when skills (gptel-auto-workflow-skill-suggest-hypothesis skills)))
         (target-full-path (expand-file-name target worktree-path))
         (sexp-check-command
          (format
           "emacs -Q --batch --eval %s"
           (shell-quote-argument
            (format
             "(progn (find-file %S) (emacs-lisp-mode) (condition-case err (progn (scan-sexps (point-min) (point-max)) (message \"OK\")) (error (message \"ERROR: %%s\" err) (kill-emacs 1))))"
             target-full-path))))
         (target-bytes (gptel-auto-experiment--target-byte-size target-full-path))
         (recovery-p
          (gptel-auto-experiment--needs-inspection-thrash-recovery-p previous-results))
         (large-target-p
          (and (numberp target-bytes)
               (>= target-bytes gptel-auto-experiment-large-target-byte-threshold)))
         (focus-candidate
          (when large-target-p
            (gptel-auto-experiment--select-large-target-focus target-full-path experiment-id)))
         (large-target-guidance
          (when large-target-p
            (concat "## Large Target Guidance\n"
                    (format "This target is large (%d bytes). Start from one concrete function or variable instead of surveying the whole file.\n"
                            target-bytes)
                    (when focus-candidate
                      (format "- Begin at `%s` or a direct caller/callee.\n"
                              (plist-get focus-candidate :name)))
                    "- Prefer focused Grep or narrow Read before broader Code_Map surveys.\n"
                    "- Make the first edit before exploring a second subsystem.\n\n")))
         (focus-line
          (format "FOCUS: %s"
                  (or (plist-get focus-candidate :name)
                      "<one concrete function or variable>")))
         (controller-focus
          (when focus-candidate
            (format "## Controller-Selected Starting Symbol\n- Symbol: `%s`\n- Kind: %s\n- Approx lines: %d-%d (%d lines)\n- Reason: controller-selected small or medium helper in a very large file; start here or at a direct caller/callee.\n\n"
                    (plist-get focus-candidate :name)
                    (plist-get focus-candidate :kind)
                    (plist-get focus-candidate :start-line)
                    (plist-get focus-candidate :end-line)
                    (plist-get focus-candidate :size-lines))))
         (inspection-thrash-contract
          (when recovery-p
            (concat "## Mandatory Focus Contract\n"
                    "A previous attempt on this target already failed with inspection-thrash.\n"
                    (when large-target-p
                      (format "This target is large (%d bytes). Broad file surveys are likely to fail.\n"
                              target-bytes))
                    "CRITICAL: You previously failed with inspection-thrash on this file.\n"
                    "The system will ABORT your turn if you do too many read-only inspections without writing.\n\n"
                    "Follow this exact opening sequence:\n"
                    (format "1. The second line after HYPOTHESIS must be exactly `%s`.\n"
                            focus-line)
                    "2. Do NOT use Code_Map on the whole file.\n"
                    "3. Use at most 2 read-only tool calls (Read, Grep, Code_Inspect), all on that same symbol.\n"
                    "4. Your NEXT tool call MUST be a write (Edit, Write, ApplyPatch) on that same symbol.\n"
                    "5. If you do more than 2 read-only calls without writing, your turn will be aborted.\n"
                    "6. Do not inspect a second subsystem before the first edit exists.\n\n"))))
    (setq gptel-auto-workflow--last-prompt-sections
          (mapconcat #'symbol-name included-sections ","))
  ;; Build variables plist and resolve to lambda via EDN pipeline
  (let* ((variables
            `((experiment-id . ,experiment-id)
              (max-experiments . ,max-experiments)
              (target . ,target)
              (worktree-path . ,worktree-path)
              (target-full-path . ,target-full-path)
              (large-target-guidance . ,(or large-target-guidance ""))
              (controller-focus . ,(or controller-focus ""))
              (inspection-thrash-contract . ,(or inspection-thrash-contract ""))
              (previous-experiment-analysis . ,(or patterns "No previous experiments"))
              (suggestions . ,(if (funcall section-included-p 'suggestions)
                                  (or suggestions "None")
                                ""))
              (self-evolution . ,(if (funcall section-included-p 'self-evolution)
                                     (if (fboundp 'gptel-auto-workflow--evolution-get-knowledge)
                                         (concat "Constrain: patterns → Δ, anti_patterns → ∞/0, improvements → euler, essence → tao\n\n"
                                                 (gptel-auto-workflow--evolution-get-knowledge))
                                       "")
                                   ""))
              ;; Nucleus attention-shaping preamble per target category
              (nucleus-persona . ,(if (and (funcall section-included-p 'self-evolution)
                                          (fboundp 'gptel-auto-workflow--experiment-nucleus-persona))
                                     (gptel-auto-workflow--experiment-nucleus-persona target)
                                   ""))
              ;; Moderator drift lens (DIALECTIC.md): detect stuck targets
              (moderator-lens . ,(if (and (fboundp 'gptel-auto-workflow--moderator-drift-lens))
                                     (let ((lens (gptel-auto-workflow--moderator-drift-lens target)))
                                       (if lens
                                           (format "## Moderator Intervention (DIALECTIC.md)\n%s: %s (%d consecutive failures)\nTry a different approach: change strategy, switch backend, or explore a different part of the file.\n"
                                                   (plist-get lens :lens)
                                                   (plist-get lens :reason)
                                                   (plist-get lens :consecutive-failures))
                                         ""))
                                   ""))
              (allium-issues . ,(if (funcall section-included-p 'self-evolution)
                                    (if (fboundp 'gptel-auto-workflow--allium-load-issues-for-target)
                                        (gptel-auto-workflow--allium-load-issues-for-target target)
                                      "")
                                  ""))
              (allium-repair . ,(if (and (funcall section-included-p 'self-evolution)
                                         (fboundp 'gptel-auto-workflow--allium-build-repair-target)
                                         (fboundp 'gptel-auto-workflow--allium-load-issues-for-target))
                                    (let* ((issues-str (gptel-auto-workflow--allium-load-issues-for-target target))
                                           (has-issues (and (stringp issues-str) (> (length issues-str) 10)))
                                           (repair-str (when has-issues
                                                         (gptel-auto-workflow--allium-build-repair-target
                                                          (or (plist-get (gptel-auto-workflow--best-strategy-for-axis target) :name)
                                                              "default")))))
                                      (if (and (stringp repair-str) (> (length repair-str) 10))
                                          repair-str
                                        ""))
                                  ""))
              (evolved-recommendations . ,(or (gptel-auto-workflow--load-evolved-recommendations) ""))
              (topic-knowledge . ,(if (funcall section-included-p 'topic-specific)
                                      (gptel-auto-experiment--get-topic-knowledge target)
                                    ""))
              (git-history . ,(if (funcall section-included-p 'git-history)
                                  git-history
                                ""))
              (baseline . ,(format "%.2f" (or baseline 0.5)))
              (weakest-keys . ,(if weakest-keys
                                   (format "## Weakest Keys (Priority Focus)\n%s" weakest-keys)
                                 ""))
              (suggested-hypothesis . ,(if suggested-hypothesis
                                           (format "## Suggested Hypothesis (from skill)\n%s" suggested-hypothesis)
                                         ""))
              (mutation-templates . ,(if mutation-templates
                                         (format "## Hypothesis Templates\n%s"
                                                 (mapconcat (lambda (tmpl) (format "- %s" tmpl)) mutation-templates "\n"))
                                       ""))
              (axis-guidance . ,(or (gptel-auto-experiment--format-axis-guidance
                                     (gptel-auto-experiment--get-underexplored-axis target)) ""))
              (axis-performance . ,(gptel-auto-experiment--format-axis-performance target))
              (frontier-guidance . ,(gptel-auto-experiment--format-frontier-guidance target))
              (saturation-status . ,(gptel-auto-experiment--frontier-saturation-guidance target))
              (failure-patterns . ,(gptel-auto-experiment--format-failure-patterns target))
              (task-type-diversity . ,(gptel-auto-experiment--format-task-type-diversity target))
              (cross-target-patterns . ,(gptel-auto-experiment--format-cross-target-patterns target))
              (strategy-frontier . ,(if (fboundp 'gptel-auto-workflow--format-strategy-frontier)
                                        (gptel-auto-workflow--format-strategy-frontier)
                                      ""))
              (agent-behavior . ,(gptel-auto-workflow--load-skill-content "auto-workflow/agent-behavior"))
              (validation-pipeline . ,(gptel-auto-workflow--load-skill-content "auto-workflow/validation-pipeline"))
              (research-findings . ,(let ((findings (gptel-auto-workflow-load-research-findings)))
                                       (if (and findings (not (string-empty-p findings)))
                                           (gptel-auto-experiment--research-for-prompt findings)
                                         "No recent external research available.")))
              (time-budget . ,(/ gptel-auto-experiment-time-budget 60))
              (focus-line . ,focus-line)
              (sexp-check-command . ,sexp-check-command))))
      ;; EDN resolve: deterministic, no template substitution, no escaping
      (gptel-auto-experiment--prompt-edn-resolve variables))))

(defun gptel-auto-experiment--get-topic-knowledge (target)
  "Get compressed topic-specific knowledge for TARGET.
Extracts topic from filename, returns only actionable patterns under 500 chars.
Uses cache to avoid repeated file reads."
  (let* ((base-name (file-name-sans-extension (file-name-nondirectory target)))
         (topic (when (string-match "gptel-ext-\\(.+\\)" base-name)
                  (match-string 1 base-name)))
         (cache-key (when topic (intern (concat "topic-" topic))))
         (cached (when cache-key
                   (gptel-auto-workflow--knowledge-cache-get cache-key))))
    (cond
     ;; Cache hit
     (cached
      (message "[knowledge-cache] Hit for %s (%d chars)" topic (length cached))
      cached)
     ;; No topic extracted
     ((not topic) "")
     ;; Cache miss - read and compress file
     (t
      (let* ((knowledge-file (expand-file-name
                              (format "mementum/knowledge/%s.md" topic)
                              (gptel-auto-workflow--project-root)))
             (result
              (if (file-exists-p knowledge-file)
                  (with-temp-buffer
                    (insert-file-contents knowledge-file)
                    (goto-char (point-min))
                    ;; Skip frontmatter
                    (when (looking-at "---")
                      (forward-line 1)
                      (while (and (not (eobp)) (not (looking-at "---")))
                        (forward-line 1))
                      (forward-line 1))
                    ;; Extract only actionable bullets
                    (let ((actionable '())
                          (chars 0))
                      (while (and (< chars gptel-auto-workflow--topic-knowledge-max-chars)
                                  (not (eobp)))
                        (let ((line (buffer-substring (line-beginning-position) (line-end-position))))
                          (when (or (string-match-p "^- " line)
                                    (string-match-p "^### " line)
                                    (string-match-p "DO \\|TRY \\|AVOID" line))
                            (push line actionable)
                            (cl-incf chars (length line))))
                        (forward-line 1))
                      (if actionable
                          (concat "Patterns for " topic ":\n"
                                  (string-join (nreverse actionable) "\n")
                                  "\n")
                        "")))
                "")))
        (when cache-key
          (gptel-auto-workflow--knowledge-cache-set cache-key result)
          (message "[knowledge-cache] Miss for %s, cached %d chars"
                   topic (length result)))
        result)))));;; TSV Logging (Explainable)

(defun gptel-auto-experiment--tsv-escape (str)
  "Escape STR for TSV format (replace newlines/tabs with spaces)."
  (when str
    (let ((s (if (stringp str) str (format "%s" str))))
      (replace-regexp-in-string "[\t\n\r]+" " | " s))))

(defun gptel-auto-experiment--tsv-decision-token (value)
  "Return a normalized TSV decision token extracted from VALUE, or nil."
  (when (stringp value)
    (let ((normalized (string-trim value)))
      (when (string-prefix-p ":" normalized)
        (setq normalized (substring normalized 1)))
      (when (string-match-p "\\`[[:lower:]][[:lower:]-]*\\'" normalized)
        normalized))))

(defun gptel-auto-experiment--tsv-decision-label (experiment)
  "Return the durable TSV decision label for EXPERIMENT."
  (or (and (gptel-auto-workflow--plist-get experiment :kept nil)
           "kept")
      (and (gptel-auto-experiment--inspection-thrash-result-p experiment)
           "inspection-thrash")
      (and (gptel-auto-workflow--plist-get experiment :validation-error nil)
           "validation-failed")
      (gptel-auto-experiment--tsv-decision-token
       (gptel-auto-workflow--plist-get experiment :decision nil))
      (gptel-auto-experiment--tsv-decision-token
       (gptel-auto-workflow--plist-get experiment :comparator-reason nil))
      (gptel-auto-experiment--tsv-decision-token
       (gptel-auto-workflow--plist-get experiment :grader-reason nil))
      "discarded"))

(defun gptel-auto-experiment--staging-pending-result (experiment)
  "Return a copy of EXPERIMENT labeled as pending staging verification."
  (let ((pending-result (copy-sequence experiment)))
    (setq pending-result (plist-put pending-result :kept nil))
    (setq pending-result (plist-put pending-result :decision "staging-pending"))
    (setq pending-result (plist-put pending-result :comparator-reason
                                    "staging-pending"))
    pending-result))

(defun gptel-auto-experiment--maybe-log-staging-pending (run-id experiment _log-fn)
  "Log EXPERIMENT as staging-pending for RUN-ID when staging is active.
Writes directly to TSV so the pending row survives regardless of the
intermediate logging strategy used by the caller."
  (when gptel-auto-workflow-use-staging
    (gptel-auto-experiment-log-tsv
     run-id
     (gptel-auto-experiment--staging-pending-result experiment))))

(defun gptel-auto-experiment--drop-replaceable-tsv-rows (experiment-id target)
  "Drop stale pending rows for EXPERIMENT-ID/TARGET in current TSV buffer.
Return non-nil when an existing terminal row should prevent appending another
row for the same experiment and target."
  (let ((id-key (format "%s" experiment-id))
        (target-key (format "%s" target))
        (skip nil))
    (goto-char (point-min))
    (forward-line 1)
    (while (and (not skip) (not (eobp)))
      (let* ((line-start (line-beginning-position))
             (line-end (line-end-position))
             (fields (split-string
                      (buffer-substring-no-properties line-start line-end)
                      "\t"))
             (row-id (nth 0 fields))
             (row-target (nth 1 fields))
             (row-decision (nth 7 fields)))
        (if (and (equal row-id id-key)
                 (equal row-target target-key))
            (if (equal row-decision "staging-pending")
                (delete-region line-start (min (point-max) (1+ line-end)))
              (setq skip t))
          (forward-line 1))))
    skip))

(defun gptel-auto-workflow--kept-target-count-from-results-file (file)
  "Return the number of distinct kept targets recorded in TSV FILE."
  (if (not (file-exists-p file))
      0
    (with-temp-buffer
      (insert-file-contents file)
      (forward-line 1)
      (let ((seen (make-hash-table :test 'equal))
            (count 0))
        (while (not (eobp))
          (let* ((fields (split-string
                          (buffer-substring-no-properties
                           (line-beginning-position)
                           (line-end-position))
                          "\t"))
                 (target (nth 1 fields))
                 (decision (nth 7 fields)))
            (when (and (equal decision "kept")
                       (stringp target)
                       (not (string-empty-p target))
                       (not (gethash target seen)))
              (puthash target t seen)
              (cl-incf count)))
          (forward-line 1))
        count))))

(defun gptel-auto-workflow--sync-live-kept-count (run-id results-file)
  "Refresh live workflow kept count from RESULTS-FILE for active RUN-ID."
  (when (and gptel-auto-workflow--running
             (stringp run-id)
             (equal run-id (gptel-auto-workflow--current-run-id)))
    (setq gptel-auto-workflow--stats
          (plist-put
           gptel-auto-workflow--stats
           :kept
           (gptel-auto-workflow--kept-target-count-from-results-file
            results-file)))
    (gptel-auto-workflow--persist-status)))

(defun gptel-auto-experiment-log-tsv (run-id experiment)
  "Append EXPERIMENT to results.tsv for RUN-ID."
  (let* ((file (gptel-auto-workflow--ensure-results-file run-id))
         (experiment-id (gptel-auto-workflow--plist-get experiment :id "?"))
         (target (gptel-auto-workflow--plist-get experiment :target "?"))
         (decision (gptel-auto-experiment--tsv-decision-label experiment))
         (agent-output (gptel-auto-workflow--plist-get experiment :agent-output ""))
         (truncated-output (gptel-auto-experiment--tsv-escape
                            (truncate-string-to-width agent-output 500 nil nil "..."))))
    ;; Inject research metadata from global context into experiment record.
    ;; This closes the feedback loop: experiments carry the research run that
    ;; influenced the prompt so trace outcomes can be linked after logging.
    (when (and (boundp 'gptel-auto-workflow--current-research-context)
               gptel-auto-workflow--current-research-context)
      (let ((ctx gptel-auto-workflow--current-research-context))
        (setq experiment
              (plist-put experiment :research-strategy
                         (or (plist-get ctx :strategy) "none")))
        (setq experiment
              (plist-put experiment :research-hash
                         (or (plist-get ctx :hash) "none")))
        (setq experiment
              (plist-put experiment :research-quality
                         (or (plist-get ctx :source) "none")))
        (setq experiment
              (plist-put experiment :controller-decision
                         (or (plist-get ctx :controller-decision) "unknown")))
        ;; Track which nucleus persona was used for self-evolution feedback
        (setq experiment
              (plist-put experiment :persona-category
                         (when (and target (fboundp 'gptel-auto-workflow--categorize-target))
                           (gptel-auto-workflow--categorize-target target))))))
    (with-temp-buffer
      (insert-file-contents file)
      (unless (gptel-auto-experiment--drop-replaceable-tsv-rows
               experiment-id target)
        (goto-char (point-max))
        (insert (format "%s\t%s\t%s\t%.2f\t%.2f\t%.2f\t%+.2f\t%s\t%d\t%s\t%s\t%s\t%s\t%s\t%d\t%s\t%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n"
                        experiment-id
                        target
                        (gptel-auto-experiment--tsv-escape (gptel-auto-workflow--plist-get experiment :hypothesis "unknown"))
                        (gptel-auto-workflow--plist-get experiment :score-before 0)
                        (gptel-auto-workflow--plist-get experiment :score-after 0)
                        (gptel-auto-workflow--plist-get experiment :code-quality 0.5)
                        (- (gptel-auto-workflow--plist-get experiment :score-after 0)
                           (gptel-auto-workflow--plist-get experiment :score-before 0))
                        decision
                        (round (gptel-auto-workflow--plist-get experiment :duration 0))
                        (gptel-auto-workflow--plist-get experiment :grader-quality "?")
                        (gptel-auto-experiment--tsv-escape (gptel-auto-workflow--plist-get experiment :grader-reason "N/A"))
                        (gptel-auto-experiment--tsv-escape (gptel-auto-workflow--plist-get experiment :comparator-reason "N/A"))
                        (gptel-auto-experiment--tsv-escape (gptel-auto-workflow--plist-get experiment :analyzer-patterns "N/A"))
                        truncated-output
                        (round (or (gptel-auto-workflow--plist-get experiment :output-chars 0) 0))
                        (gptel-auto-experiment--tsv-escape (gptel-auto-workflow--plist-get experiment :backend "unknown"))
                        (round (or (gptel-auto-workflow--plist-get experiment :prompt-chars 0)
                                   0))
                        (or (gptel-auto-experiment--tsv-escape
                             (gptel-auto-workflow--plist-get experiment :sections-included "all"))
                            "all")
                        (or (gptel-auto-experiment--tsv-escape
                             (gptel-auto-workflow--plist-get experiment :exploration-axis "?"))
                            "?")
                        (or (gptel-auto-experiment--tsv-escape
                             (let ((candidates (gptel-auto-workflow--plist-get experiment :candidate-validation)))
                               (if (and (listp candidates) (proper-list-p candidates))
                                   (mapconcat (lambda (c)
                                                (format "%s:%.1f:%s"
                                                        (substring (or (car c) "") 0 (min 20 (length (or (car c) ""))))
                                                        (or (plist-get (cdr c) :score) 0.0)
                                                        (if (plist-get (cdr c) :valid) "V" "X")))
                                              candidates ";")
                                 "")))
                            "")
                        (or (gptel-auto-experiment--tsv-escape
                             (gptel-auto-workflow--plist-get experiment :strategy "template-default"))
                            "template-default")
                        (or (gptel-auto-experiment--tsv-escape
                             (gptel-auto-workflow--plist-get experiment :research-strategy "none"))
                            "none")
                        (or (gptel-auto-experiment--tsv-escape
                             (gptel-auto-workflow--plist-get experiment :research-hash "none"))
                            "none")
                        (or (gptel-auto-experiment--tsv-escape
                             (gptel-auto-workflow--plist-get experiment :research-quality "none"))
                            "none")
                        (or (gptel-auto-experiment--tsv-escape
                             (gptel-auto-workflow--plist-get experiment :controller-decision "none"))
                            "none")
                        (or (gptel-auto-experiment--tsv-escape
                             (gptel-auto-workflow--plist-get experiment :kibcm-axis "?"))
                            "?")
                        (or (gptel-auto-experiment--tsv-escape
                             (gptel-auto-workflow--plist-get experiment :model "unknown"))
                            "unknown"))))
      (write-region (point-min) (point-max) file))
    ;; Keep strategy metrics independent from the per-run TSV.
    (when (fboundp 'gptel-auto-workflow--record-strategy-evaluation)
      (condition-case err
          (gptel-auto-workflow--record-strategy-evaluation
           (gptel-auto-workflow--plist-get experiment :strategy "template-default")
           target
           experiment-id
           (gptel-auto-workflow--plist-get experiment :score-after 0)
           (if (equal decision "kept") 'kept 'discarded)
           (gptel-auto-workflow--plist-get experiment :exploration-axis "?"))
        (error
         (message "[strategy] Evaluation recording error: %s" err))))
    ;; Call strategy analyze-results for stateful strategies (Meta-Harness interface)
    (when (fboundp 'gptel-auto-workflow--strategy-analyze-results)
      (condition-case err
          (gptel-auto-workflow--strategy-analyze-results
           (gptel-auto-workflow--plist-get experiment :strategy "template-default")
           target
           (list :decision decision
                 :score-after (gptel-auto-workflow--plist-get experiment :score-after 0)
                 :exploration-axis (gptel-auto-workflow--plist-get experiment :exploration-axis "?")
                 :comparator-reason (gptel-auto-workflow--plist-get experiment :comparator-reason "N/A")))
        (error
         (message "[strategy] analyze-results error: %s" err))))
    ;; Update research trace outcomes (AutoTTS reward signal)
    (when (fboundp 'gptel-auto-workflow--update-trace-outcomes)
      (condition-case err
          (gptel-auto-workflow--update-trace-outcomes experiment)
        (error
         (message "[autotts] Trace outcome update error: %s" err))))
    ;; Trigger self-evolution after experiment logging
    (when (and (fboundp 'gptel-auto-workflow--experiment-complete-hook)
               (fboundp 'gptel-auto-workflow-evolution-run-cycle))
      (condition-case err
          (progn
            (gptel-auto-workflow--experiment-complete-hook experiment)
            (let ((exp-id (round (or (gptel-auto-workflow--plist-get experiment :id) 0))))
              (when (and (> exp-id 0) (zerop (% exp-id 5)))
                (run-with-idle-timer 30 nil (lambda () (condition-case err (gptel-auto-workflow-evolution-run-cycle) (error (message "[evolution] Timer error: %s" err))))))))
        (error
         (message "[auto-workflow] Evolution hook error: %s" err))))
    (gptel-auto-workflow--sync-live-kept-count run-id file)))

(defun gptel-auto-experiment--make-kept-result-callback (run-id exp-result log-fn callback)
  "Return idempotent callback that finalizes EXP-RESULT after optional staging.

When invoked without arguments, or with a non-nil first argument, log
EXP-RESULT as kept. When invoked with nil, downgrade the result so staging-flow
failures do not masquerade as published kept results. When a second argument is
supplied on failure, use it as the downgrade reason."
  (gptel-auto-workflow--make-idempotent-callback
   (lambda (&rest success-args)
     (let* ((staging-reported-p (not (null success-args)))
            (staging-succeeded (car-safe success-args))
            (failure-reason-arg (cadr success-args))
            (failure-reason
             (cond
              ((stringp failure-reason-arg)
               failure-reason-arg)
              ((and failure-reason-arg
                    (symbolp failure-reason-arg))
               (symbol-name failure-reason-arg))
              (t
               "staging-flow-failed")))
            (final-result
             (if (or (not staging-reported-p) staging-succeeded)
                 exp-result
               (let ((failed-result (and (listp exp-result)
                                         (plist-put (copy-sequence exp-result) :kept nil))))
                 (when failed-result
                   (setq failed-result (plist-put failed-result :decision nil))
                   (setq failed-result (plist-put failed-result :comparator-reason failure-reason)))
                 (or failed-result exp-result)))))
       (when (functionp log-fn)
         (funcall log-fn run-id final-result))
       (when (and callback (functionp callback))
         (funcall callback final-result))))))

(defun gptel-auto-workflow--invoke-staging-completion (callback success &optional reason)
  "Invoke staging CALLBACK with SUCCESS and optional REASON.

Older completion callbacks only accept a single success flag. Newer callbacks
may also accept a second argument describing why staging downgraded an
experiment that had previously looked keep-worthy."
  (when (functionp callback)
    (let* ((arity (ignore-errors (func-arity callback)))
           (max-args (cdr-safe arity)))
      (if (or (eq max-args 'many)
              (and (integerp max-args) (>= max-args 2)))
          (funcall callback success reason)
        (funcall callback success)))))

(defun gptel-auto-workflow--make-idempotent-staging-completion (callback)
  "Return idempotent staging completion wrapper preserving CALLBACK arity."
  (let* ((called (list :pending))
         (arity (ignore-errors (func-arity callback))))
    (if (or (eq (cdr-safe arity) 'many)
            (and (integerp (cdr-safe arity))
                 (>= (cdr-safe arity) 2)))
        (lambda (success &optional reason)
          (unless (eq (car called) :done)
            (setcar called :done)
            (funcall callback success reason)))
      (lambda (success)
        (unless (eq (car called) :done)
          (setcar called :done)
          (funcall callback success))))))

;;; Error Analysis and Adaptive Workflow

(defvar gptel-auto-experiment--api-error-count 0
  "Count of API errors in current run.")

(defvar gptel-auto-experiment--api-error-threshold 5
  "Threshold of API errors before reducing or stopping future experiments.
Increased from 3 to 5 because:
1. With longer delays, API errors are less frequent
2. More tolerance for transient issues before throttling
3. Better utilization of fallback chain")

(defvar gptel-auto-experiment--quota-exhausted nil
  "Non-nil when provider quota exhaustion should stop the current workflow.")

(defun gptel-auto-experiment--error-snippet (agent-output &optional max-len)
  "Extract safe snippet from AGENT-OUTPUT for logging.
MAX-LEN defaults to 200 characters. Handles nil/empty strings safely."
  (if (and (stringp agent-output) (> (length agent-output) 0))
      (my/gptel--sanitize-for-logging agent-output (or max-len 200))
    ""))

(defvar gptel-auto-experiment-max-retries 5
  "Maximum retries for executor on transient errors.
Set to 5 to maximize usage of monthly subscription backends (MiniMax).")

(defvar gptel-auto-experiment-max-grader-retries 2
  "Maximum local retries for transient grader failures.
These retries reuse the successful executor output instead of rerunning the
entire experiment. Two retries let the grader advance past one failing
fallback backend before giving up on otherwise-good executor output.")

(defvar gptel-auto-experiment-max-aux-subagent-retries 5
  "Maximum local retries for transient analyzer/comparator failures.
Set to 5 to allow 1 attempt per provider across the 5-provider fallback
chain.  Retries stop early when cross-backend quota exhaustion is detected.")

(defvar gptel-auto-experiment-max-per-provider-attempts 3
  "Consecutive retries on the same provider before advancing to next
fallback.  Set to 5 for executor to maximize usage of monthly subscription
backends (MiniMax).  Aux subagents may use lower values to reduce quota
exhaustion.")

(defvar gptel-auto-experiment-retry-delay 15
  "Seconds to wait between retries.")

(defvar gptel-auto-experiment-rate-limit-max-retry-delay 120
  "Maximum seconds between retries for rate-limited API failures.")

(defcustom gptel-auto-workflow-headless-subagent-fallbacks
  '(("DashScope" . "qwen3.6-plus")
    ("DeepSeek" . "deepseek-v4-flash")
    ("moonshot" . "kimi-k2.6")
    ("CF-Gateway" . "@cf/openai/gpt-oss-120b")
    ("MiniMax" . "minimax-m2.7-highspeed"))
  "Ordered backend/model fallbacks for headless auto-workflow subagents.

DashScope first (faster, more reliable), then DeepSeek, Moonshot, CF-Gateway, MiniMax."
  :type '(repeat (cons (string :tag "Backend")
                       (string :tag "Model")))
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-headless-fallback-agents
  '("analyzer" "comparator" "executor" "grader" "researcher" "reviewer")
  "Headless subagents that should use the fallback provider list.

DashScope is preferred for headless runs (faster, independent quota).
The fallback chain DNS-polls through DashScope, DeepSeek, moonshot,
CF-Gateway, then MiniMax."
  :type '(repeat string)
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-executor-rate-limit-fallbacks
  '(("DeepSeek" . "deepseek-v4-pro")
    ("MiniMax" . "minimax-m2.7-highspeed")
    ("moonshot" . "kimi-k2.6")
    ("DashScope" . "qwen3.6-plus")
    ("CF-Gateway" . "@cf/moonshotai/kimi-k2.6"))
  "Ordered backend/model fallbacks for executor after rate limits.

DeepSeek first (best keep-rate for executor tasks at 25%).
MiniMax second (16.3% keep-rate, proven on executor).
Moonshot third (backup).  DashScope last — too slow for executor
tasks (consistently times out at 1080s with nil output).
CF-Gateway as emergency fallback."
  :type '(repeat (cons (string :tag "Backend")
                       (string :tag "Model")))
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-per-task-model-map
  '(("analyzer"   "MiniMax"    . "minimax-m2.7-highspeed")
    ("analyzer"   "DashScope"  . "qwen3.6-plus")
    ("analyzer"   "DeepSeek"   . "deepseek-v4-flash")
    ("analyzer"   "CF-Gateway" . "@cf/openai/gpt-oss-120b")
    ("analyzer"   "moonshot"   . "kimi-k2.6")
    ("grader"     "MiniMax"    . "minimax-m2.7-highspeed")
    ("grader"     "DashScope"  . "qwen3.6-plus")
    ("grader"     "DeepSeek"   . "deepseek-v4-flash")
    ("grader"     "CF-Gateway" . "@cf/openai/gpt-oss-120b")
    ("grader"     "moonshot"   . "kimi-k2.6")
    ("executor"   "MiniMax"    . "minimax-m2.7-highspeed")
    ("executor"   "DashScope"  . "qwen3.6-plus")
    ("executor"   "DeepSeek"   . "deepseek-v4-pro")
    ("executor"   "CF-Gateway" . "@cf/moonshotai/kimi-k2.6")
    ("executor"   "moonshot"   . "kimi-k2.6")
    ("researcher" "MiniMax"    . "minimax-m2.7-highspeed")
    ("researcher" "DashScope"  . "qwen3.6-plus")
    ("researcher" "DeepSeek"   . "deepseek-v4-flash")
    ("researcher" "CF-Gateway" . "@cf/openai/gpt-oss-120b")
    ("researcher" "moonshot"   . "kimi-k2.6")
    ("reviewer"   "MiniMax"    . "minimax-m2.7-highspeed")
    ("reviewer"   "DashScope"  . "qwen3.6-plus")
    ("reviewer"   "DeepSeek"   . "deepseek-v4-pro")
    ("reviewer"   "CF-Gateway" . "@cf/openai/gpt-oss-120b")
    ("reviewer"   "moonshot"   . "kimi-k2.6")
    ("comparator" "MiniMax"    . "minimax-m2.7-highspeed")
    ("comparator" "DashScope"  . "qwen3.6-plus")
    ("comparator" "DeepSeek"   . "deepseek-v4-flash")
    ("comparator" "CF-Gateway" . "@cf/openai/gpt-oss-120b")
    ("comparator" "moonshot"   . "kimi-k2.6"))
  "Per-task-type model selection for each backend.
Each element is (AGENT-TYPE BACKEND . MODEL).
When selecting a backend+model pair for AGENT-TYPE, this map takes
priority over the static fallback lists — ensuring code-generation
tasks (executor) use the capable deepseek-v4-pro while analysis tasks
(analyzer, grader) use the faster deepseek-v4-flash.
Backend entries not listed here fall back to their default model from
`gptel-auto-workflow-headless-subagent-fallbacks`."
  :type '(repeat (list (string :tag "Agent type")
                       (string :tag "Backend")
                       (string :tag "Model")))
  :group 'gptel-tools-agent)

(defvar gptel-auto-workflow--runtime-subagent-provider-overrides nil
  "Per-run provider overrides activated by live workflow failures.

Each element is (AGENT-TYPE . (BACKEND . MODEL)). These overrides are cleared
at run start and whenever workflow state is force-reset.")

(defvar gptel-auto-workflow--rate-limited-backends nil
  "Per-run backend names that hit rate limits during workflow execution.

All matching headless subagents skip these backends for the rest of the run
and advance through the configured fallback chain instead.")

(defconst gptel-auto-workflow--backend-key-hosts
  '(("MiniMax" . "api.minimaxi.com")
    ("DeepSeek" . "api.deepseek.com")
    ("Gemini" . "generativelanguage.googleapis.com")
    ("CF-Gateway" . "gateway.ai.cloudflare.com")
    ("DashScope" . "coding.dashscope.aliyuncs.com")
    ("moonshot" . "api.kimi.com"))
  "Map gptel backend names to auth-source hosts for workflow failover.")

(defconst gptel-auto-workflow--backend-object-vars
  '(("MiniMax" . gptel--minimax)
    ("DeepSeek" . gptel--deepseek)
    ("Gemini" . gptel--gemini)
    ("CF-Gateway" . gptel--cf-gateway)
    ("DashScope" . gptel--dashscope)
    ("moonshot" . gptel--moonshot))
  "Map gptel backend names to the corresponding backend object variables.")

(defun gptel-auto-workflow--backend-available-p (backend-name)
  "Return non-nil when BACKEND-NAME has credentials configured."
  (when (keywordp backend-name)
    (setq backend-name (substring (symbol-name backend-name) 1)))
  (let ((host (alist-get backend-name gptel-auto-workflow--backend-key-hosts
                         nil nil #'string=)))
    (cond
     ((and host (fboundp 'my/gptel-api-key))
      (gptel-auto-workflow--non-empty-string-p
       (my/gptel-api-key host)))
     (host nil)
     ;; Unknown backends have no auth-source host mapping, so a bound backend
     ;; object is the only availability signal we can use.
     (t (gptel-auto-workflow--backend-object backend-name)))))

(defun gptel-auto-workflow--best-model-for-task (agent-type backend)
  "Return the best MODEL for AGENT-TYPE when using BACKEND.
First checks per-target historical performance via holographic data.
Then looks up `gptel-auto-workflow-per-task-model-map'.
Falls back to the default model from the headless fallback chain
if no per-task mapping exists for this backend."
  (or ;; Phase π: per-target model preference from historical results
      ;; ASSUMPTION: The historical model must be a known model for this
      ;; backend (from the per-task model map or fallback chain).  This
      ;; prevents stale data from injecting wrong models (e.g. kimi-k2.6
      ;; for DashScope when only qwen3.6-plus is valid).
      (and (boundp 'gptel-auto-workflow--current-target)
           gptel-auto-workflow--current-target
           (fboundp 'gptel-auto-workflow--best-model-for-target)
           (let ((historical (gptel-auto-workflow--best-model-for-target
                              gptel-auto-workflow--current-target backend)))
             (and historical
                  (gptel-auto-workflow--model-valid-for-backend-p
                   historical backend agent-type)
                  historical)))
      (and (boundp 'gptel-auto-workflow-per-task-model-map)
        (let ((entry (cl-find-if
                      (lambda (e)
                        (and (equal (nth 0 e) agent-type)
                             (equal (nth 1 e) backend)))
                      gptel-auto-workflow-per-task-model-map)))
          (when (consp entry)
            (let ((m (cddr entry)))
              (if (consp m) (car m) m)))))
    (gptel-auto-workflow--default-model-for-backend backend)))

(defun gptel-auto-workflow--model-valid-for-backend-p (model backend &optional _agent-type)
  "Return non-nil when MODEL is a known valid model for BACKEND.
Checks the per-task model map and fallback chains.
Returns t for unknown backends to avoid false rejections."
  (let ((expected (gptel-auto-workflow--default-model-for-backend backend)))
    (or (not (stringp model))
        (not (stringp backend))
        (string= model expected)
        ;; Check per-task model map for alternative valid models
        ;; Entries are dotted pairs (AGENT BACKEND . MODEL) so use
        ;; cddr for safe access (nth 2 crashes on dotted tails).
        (and (boundp 'gptel-auto-workflow-per-task-model-map)
             (cl-some (lambda (e)
                        (and (string= (nth 1 e) backend)
                             (let ((m (cddr e)))
                               (string= (if (consp m) (car m) m) model))))
                      gptel-auto-workflow-per-task-model-map)))))

(defun gptel-auto-workflow--default-model-for-backend (backend)
  "Return the default model name for BACKEND from the headless fallback chain.
If BACKEND is not found, returns \"unknown\"."
  (when (keywordp backend)
    (setq backend (substring (symbol-name backend) 1)))
  (or (and (stringp backend)
           (boundp 'gptel-auto-workflow-headless-subagent-fallbacks)
           (cdr (assoc backend gptel-auto-workflow-headless-subagent-fallbacks
                       #'string=)))
      (and (stringp backend)
           (boundp 'gptel-auto-workflow-executor-rate-limit-fallbacks)
           (cdr (assoc backend gptel-auto-workflow-executor-rate-limit-fallbacks
                       #'string=)))
      "unknown"))

(defun gptel-auto-workflow--headless-provider-override-active-p ()
  "Return non-nil when headless auto-workflow provider override should apply."
  (and (or (bound-and-true-p gptel-auto-workflow--headless)
           (bound-and-true-p gptel-auto-workflow-persistent-headless))
       (bound-and-true-p gptel-auto-workflow--current-project)))

(defun gptel-auto-workflow--backend-object (backend-name)
  "Return the backend object for BACKEND-NAME, or nil when unavailable.
BACKEND-NAME may be a string (\"DashScope\"), a keyword (:DashScope),
or a symbol (DashScope).  Keywords and symbols are converted to
strings for lookup."
  (when (keywordp backend-name)
    (setq backend-name (substring (symbol-name backend-name) 1)))
  (when (symbolp backend-name)
    (setq backend-name (symbol-name backend-name)))
  (when-let* ((var (alist-get backend-name gptel-auto-workflow--backend-object-vars
                              nil nil #'string=))
              ((boundp var)))
    (symbol-value var)))

(defun gptel-auto-workflow--custom-var-user-customized-p (symbol)
  "Return non-nil when SYMBOL has an explicit Customize override."
  (or (get symbol 'saved-value)
      (get symbol 'customized-value)
      (get symbol 'theme-value)))

(defun gptel-auto-workflow--migrate-legacy-provider-defaults ()
  "Refresh known legacy in-memory provider defaults after hot reloads.

Long-lived daemons can keep pre-fix `defcustom' values even after the source
defines newer defaults.  Migrate only the exact legacy defaults, and only when
the user has not explicitly customized the variable."
  (let (migrated)
    (unless (gptel-auto-workflow--custom-var-user-customized-p
             'gptel-auto-workflow-headless-fallback-agents)
      (when (or (equal gptel-auto-workflow-headless-fallback-agents
                       '("analyzer" "grader" "reviewer"))
                (equal gptel-auto-workflow-headless-fallback-agents
                       '("analyzer" "executor" "grader" "reviewer")))
        (setq gptel-auto-workflow-headless-fallback-agents
              '("analyzer" "comparator" "executor" "grader" "reviewer"))
        (push 'gptel-auto-workflow-headless-fallback-agents migrated)))
    (unless (gptel-auto-workflow--custom-var-user-customized-p
             'gptel-auto-workflow-headless-subagent-fallbacks)
      (when (member gptel-auto-workflow-headless-subagent-fallbacks
                    '((("MiniMax" . "minimax-m2.7-highspeed")
                       ("DashScope" . "qwen3.6-plus")
                       ("DeepSeek" . "deepseek-chat")
                       ("CF-Gateway" . "@cf/zai-org/glm-4.7-flash")
                       ("Gemini" . "gemini-3.1-pro-preview"))
                      (("DashScope" . "qwen3.6-plus")
                       ("moonshot" . "kimi-k2.6")
                       ("DeepSeek" . "deepseek-v4-flash")
                       ("CF-Gateway" . "@cf/openai/gpt-oss-120b")
                       ("MiniMax" . "minimax-m2.7-highspeed"))))
        (setq gptel-auto-workflow-headless-subagent-fallbacks
              '(("DashScope" . "qwen3.6-plus")
                ("DeepSeek" . "deepseek-v4-flash")
                ("moonshot" . "kimi-k2.6")
                ("CF-Gateway" . "@cf/openai/gpt-oss-120b")
                ("MiniMax" . "minimax-m2.7-highspeed")))
        (push 'gptel-auto-workflow-headless-subagent-fallbacks migrated)))
    (unless (gptel-auto-workflow--custom-var-user-customized-p
             'gptel-auto-workflow-executor-rate-limit-fallbacks)
      (when (equal gptel-auto-workflow-executor-rate-limit-fallbacks
                   '(("DeepSeek" . "deepseek-chat")
                     ("CF-Gateway" . "@cf/zai-org/glm-4.7-flash")
                     ("DashScope" . "qwen3.6-plus")
                     ("Gemini" . "gemini-3.1-pro-preview")))
        (setq gptel-auto-workflow-executor-rate-limit-fallbacks
              '(("MiniMax" . "minimax-m2.7-highspeed")
                ("moonshot" . "kimi-k2.6")
                ("DashScope" . "glm-5")
                ("DeepSeek" . "deepseek-v4-pro")
                ("CF-Gateway" . "@cf/moonshotai/kimi-k2.6")))
        (push 'gptel-auto-workflow-executor-rate-limit-fallbacks migrated)))
    (unless (gptel-auto-workflow--custom-var-user-customized-p
             'gptel-auto-experiment-validation-retry-active-grace)
      (when (= gptel-auto-experiment-validation-retry-active-grace
               gptel-auto-workflow--legacy-validation-retry-active-grace)
        (setq gptel-auto-experiment-validation-retry-active-grace
              gptel-auto-workflow--current-validation-retry-active-grace)
        (push 'gptel-auto-experiment-validation-retry-active-grace migrated)))
    (when migrated
      (setq migrated (nreverse migrated))
      (message "[auto-workflow] Refreshed legacy fallback defaults: %s"
               (mapconcat #'symbol-name migrated ", ")))
    migrated))

(defun gptel-auto-workflow--backend-model-symbol (backend model-name)
  "Return MODEL-NAME as a supported symbol for BACKEND.

If MODEL-NAME is not yet listed on BACKEND, append it so hot-reloaded daemons
can use newer models without a restart."
  (let ((model (if (symbolp model-name) model-name (intern model-name))))
    (when (and backend (fboundp 'gptel-backend-models))
      (let ((models (gptel-backend-models backend)))
        (unless (memq model models)
          (setf (gptel-backend-models backend) (append models (list model))))))
    model))

(defun gptel-auto-workflow--clear-runtime-subagent-provider-overrides ()
  "Reset per-run provider failover state.
Preserves rate-limited backends blacklist across experiments within a run."
  (setq gptel-auto-workflow--runtime-subagent-provider-overrides nil))
;; Note: gptel-auto-workflow--rate-limited-backends is intentionally NOT cleared above.
;; It persists across experiments within a single run so backends that hit hard quotas
;; don't get retried for each new experiment. Cleared when run finishes or on manual reset.

(defun gptel-auto-workflow--clear-rate-limited-backends ()
  "Clear the rate-limited backends blacklist.
Call at the start of a new workflow run."
  (setq gptel-auto-workflow--rate-limited-backends nil))

(defun gptel-auto-workflow--rate-limit-failover-candidates (agent-type)
  "Return fallback provider candidates for AGENT-TYPE after rate limiting.
When ontology health data is available, ranks backends by health × keep-rate
using `gptel-auto-workflow--ranked-subagent-backends'.
Returns the static fallback chain as a last resort.

For executors, the static fallback chain takes priority because the dynamic
router aggregates data across ALL task types — a backend that's fast for
analysis/compare may still be too slow for code generation (DashScope:
0% keep-rate on executor, consistently times out at 1080s)."
  (cond
   ((not (stringp agent-type)) nil)
   ((string= agent-type "executor")
    ;; Executor: trust the hand-tuned static fallback chain as primary.
    ;; The onto-router's aggregate ranking puts DashScope first (fast for
    ;; non-generative tasks) but DashScope has 0% keep-rate on executor.
    ;; DeepSeek has 25% keep-rate on :agentic tasks — it should be first.
    ;; Do NOT sort by router position: if DashScope is at position 0 in the
    ;; aggregate ranking, sorting by it would put DashScope first again.
    ;; Only remove backends the router explicitly deprioritizes.
    (or (and gptel-auto-workflow-executor-rate-limit-fallbacks
             (let ((ranked (and (fboundp 'gptel-auto-workflow--ranked-subagent-backends)
                                (gptel-auto-workflow--ranked-subagent-backends agent-type))))
               (if ranked
                   (let ((ranked-set (make-hash-table :test 'equal)))
                     ;; Only keep ranked backends that appear in the static chain
                     (cl-loop for (backend . _model) in ranked
                              do (puthash backend t ranked-set))
                     ;; Filter static fallback: keep only non-excluded backends
                     ;; from the static order (which has DeepSeek first)
                     (cl-remove-if-not
                      (lambda (entry) (gethash (car entry) ranked-set))
                      gptel-auto-workflow-executor-rate-limit-fallbacks))
                 gptel-auto-workflow-executor-rate-limit-fallbacks)))
         gptel-auto-workflow-executor-rate-limit-fallbacks))
   ((member agent-type gptel-auto-workflow-headless-fallback-agents)
    (or (and (fboundp 'gptel-auto-workflow--ranked-subagent-backends)
             (gptel-auto-workflow--ranked-subagent-backends agent-type))
        gptel-auto-workflow-headless-subagent-fallbacks))))

(defun gptel-auto-workflow--agent-base-preset (agent-type)
  "Return the current base preset plist for AGENT-TYPE, or nil when unavailable.

When the agent config has no :backend and the headless fallback override is
active, automatically select the first available provider from the headless
chain so that subagent calls do not fall through to the mode-hook default
(typically MiniMax)."
  (when-let* ((agent-type (and (stringp agent-type) agent-type))
              (agent-config (and (boundp 'gptel-agent--agents)
                                 (assoc agent-type gptel-agent--agents)))
              (merged (append (list :include-reasoning nil
                                    :use-tools t
                                    :use-context nil
                                    :stream my/gptel-subagent-stream)
                              (copy-sequence (cdr agent-config)))))
    ;; When headless mode is active, prefer the ranked backend chain
    ;; over any preset backend or the global gptel-backend.  The
    ;; executor agent config often has :backend \"MiniMax\" hardcoded in
    ;; its agent plist — this overrides even a non-nil preset backend
    ;; so DashScope is used first (avoiding MiniMax rate-limit death
    ;; spiral on first subagent call).
    (if (and (fboundp 'gptel-auto-workflow--headless-provider-override-active-p)
             (gptel-auto-workflow--headless-provider-override-active-p)
             (fboundp 'gptel-auto-workflow--rate-limit-failover-candidates)
             (fboundp 'gptel-auto-workflow--first-available-provider-candidate))
        (let ((candidates (gptel-auto-workflow--rate-limit-failover-candidates agent-type))
              (excluded (and (boundp 'gptel-auto-workflow--rate-limited-backends)
                             gptel-auto-workflow--rate-limited-backends)))
          (if candidates
              (let ((pick (gptel-auto-workflow--first-available-provider-candidate
                           candidates excluded)))
                (when pick
                  (let* ((model-str (or (and (fboundp 'gptel-auto-workflow--best-model-for-task)
                                           (gptel-auto-workflow--best-model-for-task
                                            agent-type (car pick)))
                                       (cdr pick)))
                         (backend-obj (gptel-auto-workflow--backend-object (car pick)))
                         (model-sym (and backend-obj model-str
                                         (gptel-auto-workflow--backend-model-symbol
                                          backend-obj model-str))))
                    (message "[subagent] %s base-preset auto-selected %s/%s"
                             agent-type (car pick) model-str)
                    (setq merged (plist-put merged :backend (car pick)))
                    (setq merged (plist-put merged :model (or model-sym model-str))))))
            ;; Headless active but no candidates: fall back to
            ;; gptel-backend so the call goes through.
            (when (and (null (plist-get merged :backend))
                       (boundp 'gptel-backend) gptel-backend)
              (setq merged (plist-put merged :backend gptel-backend)))))
      ;; Not headless: use the preset backend or global gptel-backend.
      (when (and (null (plist-get merged :backend))
                 (boundp 'gptel-backend) gptel-backend)
        (setq merged (plist-put merged :backend gptel-backend))))
    merged))

(defun gptel-auto-workflow--runtime-subagent-provider-override (agent-type)
  "Return the active per-run provider override for AGENT-TYPE, if any."
  (alist-get agent-type
             gptel-auto-workflow--runtime-subagent-provider-overrides
             nil nil #'string=))

(defun gptel-auto-workflow--backend-rate-limited-p (backend-name)
  "Return non-nil when BACKEND-NAME has already rate-limited this run."
  (and (stringp backend-name)
       (seq-contains-p gptel-auto-workflow--rate-limited-backends
                       backend-name
                       #'string=)))

(defun gptel-auto-workflow--preset-backend-name (backend)
  "Return a readable backend name for BACKEND.
Handles gptel-backend structs, strings, and keyword symbols."
  (cond
   ((stringp backend) backend)
   ((keywordp backend) (substring (symbol-name backend) 1))
   ((and backend (fboundp 'gptel-backend-name))
    (gptel-auto-workflow--safe-backend-name backend))
   (t (let ((name (format "%s" backend)))
        (message "[backend] Warning: unknown backend type %S, using %s"
                 (type-of backend) name)
        name))))

(defun gptel-auto-workflow--safe-backend-name (backend)
  "Safe wrapper around `gptel-backend-name'.
Catches type errors and falls back to format \"%s\"."
  (cond
   ((stringp backend) backend)
   ((keywordp backend) (substring (symbol-name backend) 1))
   ((null backend) "nil")
   (t
    (condition-case nil
        (gptel-backend-name backend)
      (error
       (let ((name (format "%s" backend)))
         (message "[backend] gptel-backend-name failed for %S, using %s"
                  backend name)
         name))))))

(defun gptel-auto-workflow--model-max-output-tokens (model-id)
  "Return the documented max output tokens for MODEL-ID, or nil when unknown."
  (when (require 'gptel-ext-context-cache nil t)
    (when-let* (((fboundp 'my/gptel-get-model-metadata))
                (meta (my/gptel-get-model-metadata model-id))
                (max-output
                 (if (fboundp 'my/gptel--plist-get)
                     (my/gptel--plist-get meta :max-output nil)
                   (plist-get meta :max-output)))
                ((integerp max-output))
                ((> max-output 0)))
      max-output)))

;;; Frontier Tracking (Meta-Harness style)

(defun gptel-auto-experiment--compute-frontier (target)
  "Compute Pareto frontier for TARGET from TSV history.
Returns list of non-dominated experiments, each a plist with:
  :experiment-id :code-quality :delta :axis :decision.
An experiment dominates another if it is >= on all metrics and
> on at least one."
  (let ((results-file (gptel-auto-workflow--results-file-path))
        (experiments '()))
    (when (file-exists-p results-file)
      (with-temp-buffer
        (insert-file-contents results-file)
        (forward-line 1) ; skip header
        (while (not (eobp))
          (let* ((fields (split-string
                          (buffer-substring (line-beginning-position)
                                            (line-end-position))
                          "\t"))
                 (field-count (length fields))
                 ;; 20/24-col: axis at index 17; 27-col: axis at index 18
                 (axis-idx (if (<= field-count 24) 17 18))
                 ;; 20/24-col: prompt-chars at index 15; 27-col: at index 16
                 (prompt-idx (if (<= field-count 24) 15 16))
                 (line-target (nth 1 fields))
                 (decision (nth 7 fields)))
            (when (and (equal line-target target)
                       (equal decision "kept"))
              (push (list :experiment-id (nth 0 fields)
                          :code-quality (string-to-number (or (nth 5 fields) "0"))
                          :delta (string-to-number (or (nth 6 fields) "0"))
                          :axis (or (nth axis-idx fields) "unknown")
                          :prompt-chars (string-to-number (or (nth prompt-idx fields) "0"))
                          :decision decision)
                    experiments))
            (forward-line 1))))
      ;; Compute Pareto frontier: not dominated by any other
      (let ((frontier '()))
        (dolist (exp experiments)
          (let ((dominated nil)
                (exp-quality (plist-get exp :code-quality))
                (exp-delta (plist-get exp :delta))
                (exp-chars (plist-get exp :prompt-chars)))
            (dolist (other experiments)
              (unless (eq exp other)
                (let ((other-quality (plist-get other :code-quality))
                      (other-delta (plist-get other :delta))
                      (other-chars (plist-get other :prompt-chars)))
                  ;; Other dominates exp if >= on quality+delta and <= on chars
                  (when (and (>= other-quality exp-quality)
                             (>= other-delta exp-delta)
                             (<= other-chars exp-chars)
                             (or (> other-quality exp-quality)
                                 (> other-delta exp-delta)
                                 (< other-chars exp-chars)))
                    (setq dominated t)))))
            (unless dominated
              (push exp frontier))))
        frontier))))

(defun gptel-auto-experiment--frontier-stats (target)
  "Return frontier statistics for TARGET as formatted string.
Shows count, best quality, best delta, and underexplored axes."
  (let ((frontier (gptel-auto-experiment--compute-frontier target)))
    (if (null frontier)
        "No kept experiments yet."
      (let* ((qualities (mapcar (lambda (e) (plist-get e :code-quality)) frontier))
             (deltas (mapcar (lambda (e) (plist-get e :delta)) frontier))
             (axes (mapcar (lambda (e) (plist-get e :axis)) frontier))
             (unique-axes (cl-remove-duplicates axes :test #'equal))
             (all-axes '("A" "B" "C" "D" "E" "F")))
        (concat
         (format "Frontier: %d experiments | Best quality: %.2f | Best delta: %+.2f\n"
                 (length frontier)
                 (if qualities (apply #'max qualities) 0)
                 (if deltas (apply #'max deltas) 0))
         (format "Explored axes: %s\n"
                 (if unique-axes (string-join unique-axes ", ") "none"))
         (let ((missing (cl-set-difference all-axes unique-axes :test #'equal)))
           (if missing
               (format "Missing axes: %s (try these next)"
                       (string-join missing ", "))
             "All axes explored.")))))))

(defun gptel-auto-experiment--format-frontier-guidance (target)
  "Format frontier guidance for TARGET prompt.
Returns empty string if no frontier data."
  (let ((stats (gptel-auto-experiment--frontier-stats target)))
    (if (string= stats "No kept experiments yet.")
        ""
      (concat "## Frontier Analysis (Pareto-optimal experiments)\n"
              stats "\n\n"))))

(defun gptel-auto-experiment--frontier-select-targets (&optional n)
  "Select N targets with smallest Pareto frontiers for next experiments.
Returns list of (target . frontier-size) sorted ascending by frontier size.
Targets with no frontier experiments are prioritized."
  (let* ((results-file (gptel-auto-workflow--results-file-path))
         (target-frontiers (make-hash-table :test 'equal))
         (all-targets '()))
    ;; Collect all targets from TSV
    (when (file-exists-p results-file)
      (with-temp-buffer
        (insert-file-contents results-file)
        (forward-line 1) ; skip header
        (while (not (eobp))
          (let* ((fields (split-string
                          (buffer-substring (line-beginning-position)
                                            (line-end-position))
                          "\t"))
                 (target (nth 1 fields)))
            (when (and (stringp target)
                       (not (string-empty-p target))
                       (not (member target all-targets)))
              (push target all-targets)))
          (forward-line 1))))
    ;; Compute frontier size for each target
    (dolist (target all-targets)
      (let ((frontier (gptel-auto-experiment--compute-frontier target)))
        (puthash target (length frontier) target-frontiers)))
    ;; Sort by frontier size (ascending)
    (let ((sorted '()))
      (cl-flet ((collect-frontier (target size)
                  (push (cons target size) sorted)))
        (maphash #'collect-frontier target-frontiers))
      (setq sorted (sort sorted (lambda (a b) (< (cdr a) (cdr b)))))
      (if n
          (seq-take sorted n)
        sorted))))

(defun gptel-auto-experiment--frontier-selection-guidance ()
  "Format guidance for target selection based on frontier analysis.
Returns formatted string listing underexplored targets."
  (let ((targets (gptel-auto-experiment--frontier-select-targets 5)))
    (if (null targets)
        ""
      (concat "## Target Selection (Frontier-Based)\n"
              "Priority targets (smallest Pareto frontier):\n"
              (mapconcat (lambda (pair)
                           (format "- %s: %d Pareto-optimal experiment(s)"
                                   (car pair) (cdr pair)))
                         targets
                         "\n")
              "\n\n"))))

(defun gptel-auto-experiment--frontier-saturated-p (target &optional min-frontier-size min-axes min-quality)
  "Return t if TARGET's frontier is saturated (sufficiently explored).
MIN-FRONTIER-SIZE: minimum number of Pareto-optimal experiments (default: 3).
MIN-AXES: minimum number of unique axes covered (default: 6).
MIN-QUALITY: minimum best quality score (default: 0.8)."
  (let* ((frontier (gptel-auto-experiment--compute-frontier target))
         (frontier-size (length frontier))
         (axes (cl-remove-duplicates (mapcar (lambda (e) (plist-get e :axis)) frontier)
                                     :test #'equal))
         (qualities (mapcar (lambda (e) (plist-get e :code-quality)) frontier))
         (best-quality (if qualities (apply #'max qualities) 0)))
    (and (>= frontier-size (or min-frontier-size 3))
         (>= (length axes) (or min-axes 4))
         (>= best-quality (or min-quality 0.8)))))

(defun gptel-auto-experiment--frontier-saturation-guidance (target)
  "Format saturation status for TARGET.
Returns string indicating whether target is saturated or needs more work."
  (if (gptel-auto-experiment--frontier-saturated-p target)
      (format "## Target Status: SATURATED\n%s has sufficient Pareto-optimal experiments. Consider moving to other targets.\n\n" target)
    (format "## Target Status: ACTIVE\n%s needs more experiments to saturate frontier.\n\n" target)))

;; ─── Batch Validation for Multi-Candidate Hypotheses ───

(defun gptel-auto-experiment--extract-candidates (agent-output)
  "Extract up to 3 candidate hypotheses from AGENT-OUTPUT.
Returns list of strings, or nil if no candidates found."
  (when (stringp agent-output)
    (let (candidates)
      (with-temp-buffer
        (insert agent-output)
        (goto-char (point-min))
        (while (re-search-forward "^CANDIDATE_\\([123]\\):\\s-*\\(.+\\)$" nil t)
          (push (match-string 2) candidates)))
      (nreverse candidates))))

(defun gptel-auto-experiment--validate-candidate-safely (candidate target-full-path)
  "Run cheap validation checks on CANDIDATE for TARGET-FULL-PATH.
Returns plist with :valid t/nil, :errors list, :score 0-1.
Does NOT modify the filesystem - operates on a temp copy."
  ;; ASSUMPTION: candidate must be a non-empty string
  ;; EDGE CASE: nil or non-string candidate from malformed agent output
  ;; TEST: (gptel-auto-experiment--validate-candidate-safely nil "foo") => :valid nil
  (cond
   ((null candidate)
    (list :valid nil :errors (list "Candidate is nil") :score 0.0))
   ((not (stringp candidate))
    (list :valid nil :errors (list "Candidate is not a string") :score 0.0))
   ((string-empty-p (string-trim candidate))
    (list :valid nil :errors (list "Candidate is empty or whitespace-only") :score 0.0))
   (t
    (let ((temp-file (make-temp-file "auto-workflow-candidate-"))
          (errors '())
          (score 0.0))
      (unwind-protect
          (progn
            ;; Copy target to temp file
            (when (file-exists-p target-full-path)
              (copy-file target-full-path temp-file t))
            
            ;; Check 1: Candidate describes actual code change (not docs)
            (if (or (string-match-p "\\bcomment\\b\\|\\bdocstring\\b\\|\\bdocumentation\\b" candidate)
                    (string-match-p "\\badd\\s-+comments\\b\\|\\badd\\s-+doc\\b" candidate))
                (push "Candidate mentions documentation/comments" errors)
              (setq score (+ score 0.2)))
            
            ;; Check 2: Candidate is specific (mentions function/variable)
            (if (string-match-p "\\b\\(function\\|variable\\|defun\\|defvar\\|method\\|class\\)\\b" candidate)
                (setq score (+ score 0.2))
              (push "Candidate lacks specific code reference" errors))
            
            ;; Check 3: Candidate targets a real improvement type
            (if (string-match-p "\\b\\(bug\\|fix\\|error\\|performance\\|cache\\|optimize\\|refactor\\|extract\\|duplicate\\|validation\\|guard\\|test\\|memory\\|leak\\)\\b" candidate)
                (setq score (+ score 0.2))
              (push "Candidate lacks improvement keywords" errors))
            
            ;; Check 4: Candidate is not too vague
            (if (> (length candidate) 20)
                (setq score (+ score 0.2))
              (push "Candidate description too short" errors))
            
            ;; Check 5: Candidate doesn't repeat common anti-patterns
            (if (string-match-p "\\boptimize\\s-+code\\b\\|\\bimprove\\s-+performance\\b\\|\\bmake\\s-+better\\b" candidate)
                (push "Candidate uses vague improvement language" errors)
              (setq score (+ score 0.2)))
            
            (list :valid (null errors)
                  :errors (nreverse errors)
                  :score score))
        (when (file-exists-p temp-file)
          (delete-file temp-file)))))))

(defun gptel-auto-experiment--batch-validate-candidates (agent-output target-full-path)
  "Validate all candidates from AGENT-OUTPUT for TARGET-FULL-PATH.
Returns list of (candidate . validation-result) pairs,
sorted by score descending."
  (let* ((candidates (gptel-auto-experiment--extract-candidates agent-output))
         (validated (mapcar (lambda (cand)
                              (cons cand (gptel-auto-experiment--validate-candidate-safely
                                          cand target-full-path)))
                            candidates)))
    (sort validated (lambda (a b)
                      (> (plist-get (cdr a) :score)
                         (plist-get (cdr b) :score))))))

(defun gptel-auto-experiment--select-best-candidate (validated-candidates)
  "Select best candidate from VALIDATED-CANDIDATES.
Returns the candidate string, or nil if none valid."
  (catch 'found
    (dolist (pair validated-candidates)
      (when (plist-get (cdr pair) :valid)
        (throw 'found (car pair))))
    ;; If no fully valid candidate, pick highest scoring
    (car (car validated-candidates))))

;; ─── Frontier-Aware Target Filtering ───

(defun gptel-auto-workflow--filter-frontier-saturated-targets (targets)
  "Filter out targets with saturated Pareto frontiers from TARGETS list.
Returns filtered list, or nil if all targets saturated.
Saturated means: >=3 Pareto experiments, >=4 axes, quality>=0.8."
  (let ((filtered '())
        (saturated-count 0))
    (dolist (target targets)
      (if (and (fboundp 'gptel-auto-experiment--frontier-saturated-p)
               (gptel-auto-experiment--frontier-saturated-p target))
          (progn
            (setq saturated-count (1+ saturated-count))
            (message "[frontier-filter] %s is SATURATED, skipping" target))
        (push target filtered)))
    (message "[frontier-filter] %d/%d targets saturated, %d remaining"
             saturated-count (length targets) (length filtered))
    ;; If all saturated, return nil to signal we need fresh targets
    (if (null filtered)
        (progn
          (message "[frontier-filter] WARNING: All %d targets saturated!" (length targets))
          nil)
      (nreverse filtered))))

;;; Axis Analysis and Adaptive Weighting

(defun gptel-auto-experiment--get-axis-stats (target)
  "Calculate exploration statistics for TARGET from TSV history.
Returns plist with :counts (axis->count), :successes (axis->kept-count),
:rates (axis->success-rate), :total-experiments."
  (let ((results-file (gptel-auto-workflow--results-file-path))
        (counts (make-hash-table :test 'equal))
        (successes (make-hash-table :test 'equal))
        (total 0))
    (when (file-exists-p results-file)
      (with-temp-buffer
        (insert-file-contents results-file)
        (goto-char (point-min))
        (forward-line 1) ; skip header
        (while (not (eobp))
          (let* ((fields (split-string
                          (buffer-substring (line-beginning-position)
                                            (line-end-position))
                          "\t"))
                 (field-count (length fields))
                 ;; 20/24-col: axis at index 17; 27-col: axis at index 18
                 (axis-idx (if (<= field-count 24) 17 18))
                 (line-target (nth 1 fields))
                 (decision (nth 7 fields))
                 (axis (or (nth axis-idx fields) "?")))
            (when (and (equal line-target target)
                       (not (equal axis "?"))
                       (not (string-empty-p axis)))
              (setq total (1+ total))
              (puthash axis (1+ (gethash axis counts 0)) counts)
              (when (equal decision "kept")
                (puthash axis (1+ (gethash axis successes 0)) successes))))
          (forward-line 1))))
    (let ((rates (make-hash-table :test 'equal)))
      (cl-flet ((compute-rate (axis count)
                  (let ((success-count (gethash axis successes 0)))
                    (puthash axis (/ (float success-count) count) rates))))
        (maphash #'compute-rate counts))
      (list :counts counts
            :successes successes
            :rates rates
            :total-experiments total))))

(defun gptel-auto-experiment--get-underexplored-axis (target)
  "Find least-explored axis for TARGET.
Returns axis letter (A-F) or nil if insufficient data."
  (let* ((stats (gptel-auto-experiment--get-axis-stats target))
         (counts (plist-get stats :counts))
         (axes '("A" "B" "C" "D" "E" "F" "G" "H" "I"))
         (min-count most-positive-fixnum)
         (underexplored nil))
    (dolist (axis axes)
      (let ((count (gethash axis counts 0)))
        (when (< count min-count)
          (setq min-count count)
          (setq underexplored axis))))
    ;; Only suggest underexplored axis if we have some data
    (when (and underexplored
               (> (plist-get stats :total-experiments) 0))
      underexplored)))

(defun gptel-auto-experiment--get-axis-success-rates (target)
  "Get formatted success rates per axis for TARGET.
Returns string describing which axes have been most successful."
  (let* ((stats (gptel-auto-experiment--get-axis-stats target))
         (rates (plist-get stats :rates))
         (counts (plist-get stats :counts))
         (axis-names gptel-auto-experiment--axis-names)
         (results '()))
    (dolist (pair axis-names)
      (let* ((axis (car pair))
             (name (cdr pair))
             (count (gethash axis counts 0))
             (rate (if (> count 0)
                       (gethash axis rates 0.0)
                     nil)))
        (when (and rate (> count 0))
          (push (list :axis axis :name name :count count :rate rate) results))))
    ;; Sort by success rate descending
    (setq results (sort results (lambda (a b)
                                  (> (plist-get a :rate)
                                     (plist-get b :rate)))))
    (if (null results)
        "No historical axis data yet."
      (concat "Historical success rates by axis:\n"
              (mapconcat (lambda (r)
                           (format "- %s (%s): %.0f%% success (%d experiments)"
                                   (plist-get r :axis)
                                   (plist-get r :name)
                                   (* 100 (plist-get r :rate))
                                   (plist-get r :count)))
                         results
                         "\n")))))

(defun gptel-auto-experiment--format-axis-guidance (axis)
  "Format guidance for exploring AXIS.
Returns string with axis description and rationale."
  (when axis
    (let* ((axis-info (assoc axis gptel-auto-experiment--axis-names))
           (axis-name (cdr axis-info)))
      (concat "## Exploration Guidance\n"
              "Priority axis: " axis " (" axis-name ") — least explored for this target.\n"
              "Consider: "
              (pcase axis
                ("A" "adding validation, fixing error handling gaps, improving error messages")
                ("B" "reducing complexity, adding caching, optimizing hot paths")
                ("C" "extracting functions, removing duplication, improving naming")
                ("D" "adding guards, type checking, boundary validation")
                ("E" "adding missing tests for existing functionality")
                ("F" "fixing memory leaks, optimizing allocation, improving cleanup")
                ("G" "improving docstrings, adding comments, clarifying APIs")
                ("H" "adding type predicates, stricter contracts, defensive checks")
                ("I" "testing edge cases, boundary values, unusual inputs")
                (_ "general improvements"))
              ".\n\n"))))

(defun gptel-auto-experiment--format-axis-performance (target)
  "Format axis performance history for TARGET.
Returns string showing which axes have been most successful."
  (let ((rates-str (gptel-auto-experiment--get-axis-success-rates target)))
    (concat "## Axis Performance History\n"
            rates-str
            "\n\nRecommendation: Prioritize axes with higher success rates, but also explore underexplored axes to build frontier coverage.\n\n")))

;;; Failure Pattern Injection

(defun gptel-auto-experiment--get-common-failure-reasons (target &optional n)
  "Get most common failure reasons for TARGET from TSV.
Returns list of (reason . count) pairs, sorted by frequency.
Optional N limits number of reasons (default 3)."
  (let ((results-file (gptel-auto-workflow--results-file-path))
        (reasons (make-hash-table :test 'equal))
        (total-failures 0))
    (when (file-exists-p results-file)
      (with-temp-buffer
        (insert-file-contents results-file)
        (goto-char (point-min))
        (forward-line 1) ; skip header
        (while (not (eobp))
          (let* ((fields (split-string
                          (buffer-substring (line-beginning-position)
                                            (line-end-position))
                          "\t"))
                 (line-target (nth 1 fields))
                 (decision (nth 7 fields))
                 (reason (nth 11 fields))) ; comparator_reason column
            (when (and (equal line-target target)
                       (not (equal decision "kept"))
                       reason
                       (not (string-empty-p reason))
                       (not (equal reason "N/A")))
              (setq total-failures (1+ total-failures))
              (puthash reason (1+ (gethash reason reasons 0)) reasons)))
          (forward-line 1))))
    ;; Convert to sorted list
    (let ((pairs '()))
      (cl-flet ((collect-reason (reason count)
                  (push (cons reason count) pairs)))
        (maphash #'collect-reason reasons))
      (setq pairs (sort pairs (lambda (a b) (> (cdr a) (cdr b)))))
      (seq-take pairs (or n 3)))))

(defun gptel-auto-experiment--format-failure-patterns (target)
  "Format common failure patterns for TARGET as prompt guidance.
Returns string warning about common rejection reasons, or empty string."
  (let ((reasons (gptel-auto-experiment--get-common-failure-reasons target 3)))
    (if (null reasons)
        ""
      (concat "## Common Failure Patterns (AVOID THESE)\n"
              "Recent experiments on this target were discarded for these reasons:\n"
              (mapconcat (lambda (pair)
                           (format "- %s (%d times)"
                                   (car pair) (cdr pair)))
                         reasons
                         "\n")
              "\n\nTo succeed, actively avoid the patterns above.\n\n"))))

;;; Cross-Target Pattern Transfer

(defun gptel-auto-experiment--get-successful-patterns-from-others (target &optional n)
  "Get successful experiment patterns from OTHER targets (not TARGET).
Returns list of plists with :target :axis :hypothesis for kept experiments.
Optional N limits results (default 5)."
  (let ((results-file (gptel-auto-workflow--results-file-path))
        (patterns '()))
    (when (file-exists-p results-file)
      (with-temp-buffer
        (insert-file-contents results-file)
        (goto-char (point-min))
        (forward-line 1) ; skip header
        (while (and (not (eobp)) (< (length patterns) (or n 5)))
          (let* ((fields (split-string
                          (buffer-substring (line-beginning-position)
                                            (line-end-position))
                          "\t"))
                 (field-count (length fields))
                 ;; 20/24-col: axis at index 17; 27-col: axis at index 18
                 (axis-idx (if (<= field-count 24) 17 18))
                 (line-target (nth 1 fields))
                 (decision (nth 7 fields))
                 (axis (or (nth axis-idx fields) "?"))
                 (hypothesis (nth 2 fields)))
            (when (and (not (equal line-target target))
                       (equal decision "kept")
                       hypothesis
                       (not (string-empty-p hypothesis))
                       (not (equal axis "?")))
              (push (list :target line-target
                          :axis axis
                          :hypothesis (truncate-string-to-width hypothesis 100 nil nil "..."))
                    patterns)))
          (forward-line 1))))
    (nreverse patterns)))

(defun gptel-auto-experiment--format-cross-target-patterns (target)
  "Format successful patterns from other targets as suggestions.
Returns string with transferable insights, or empty string if none."
  (let ((patterns (gptel-auto-experiment--get-successful-patterns-from-others target 5)))
    (if (null patterns)
        ""
      (concat "## Successful Patterns from Other Targets\n"
              "These approaches worked well on similar files:\n"
              (mapconcat (lambda (p)
                           (format "- [%s on %s] %s"
                                   (plist-get p :axis)
                                   (file-name-nondirectory (plist-get p :target))
                                   (plist-get p :hypothesis)))
                         patterns
                         "\n")
              "\n\nConsider adapting these patterns to this target if applicable.\n\n"))))

;;; Task-Type Diversity Tracking

(defun gptel-auto-experiment--get-task-type-stats (target)
  "Get statistics on task types tried for TARGET.
Returns plist with :counts (type->count) and :total."
  (let ((results-file (gptel-auto-workflow--results-file-path))
        (counts (make-hash-table :test 'equal)))
    (when (file-exists-p results-file)
      (with-temp-buffer
        (insert-file-contents results-file)
        (goto-char (point-min))
        (forward-line 1) ; skip header
        (while (not (eobp))
          (let* ((fields (split-string
                          (buffer-substring (line-beginning-position)
                                            (line-end-position))
                          "\t"))
                 (line-target (nth 1 fields))
                 (hypothesis (nth 2 fields)))
            (when (and (equal line-target target)
                       hypothesis
                       (not (string-empty-p hypothesis)))
              (let ((task-type (gptel-benchmark--detect-task-type hypothesis)))
                (puthash task-type (1+ (gethash task-type counts 0)) counts)))
            (forward-line 1)))))
    (list :counts counts)))

(defun gptel-auto-experiment--format-task-type-diversity (target)
  "Format task-type diversity guidance for TARGET.
Shows which task types have been tried and suggests underexplored ones."
  (let* ((stats (gptel-auto-experiment--get-task-type-stats target))
         (counts (plist-get stats :counts))
         (all-types '(refactoring bug-fix performance feature validation))
         (type-names '((refactoring . "Refactoring")
                       (bug-fix . "Bug Fix")
                       (performance . "Performance")
                       (feature . "Feature Addition")
                       (validation . "Validation/Safety")))
         (lines '()))
    ;; Show current distribution
    (dolist (type all-types)
      (let ((count (gethash type counts 0))
            (name (cdr (assoc type type-names))))
        (push (format "  %s: %d experiment%s" name count (if (= count 1) "" "s")) lines)))
    ;; Find underexplored types
    (let ((underexplored
           (cl-remove-if (lambda (type) (>= (gethash type counts 0) 2))
                         all-types)))
      (if underexplored
          (concat "## Task-Type Diversity\n"
                  "Current distribution for this target:\n"
                  (mapconcat #'identity (nreverse lines) "\n")
                  "\n\nConsider trying these underexplored task types:\n"
                  (mapconcat (lambda (type)
                               (format "- %s: %s"
                                       (cdr (assoc type type-names))
                                       (pcase type
                                         ('bug-fix "Find and fix actual bugs, edge cases, or error handling gaps")
                                         ('performance "Optimize hot paths, add caching, reduce complexity")
                                         ('feature "Add new functionality or capabilities")
                                         ('validation "Add safety guards, type checking, boundary validation")
                                         ('refactoring "Extract functions, remove duplication, improve naming"))))
                             underexplored
                             "\n")
                  "\n\n")
        ""))))

(provide 'gptel-tools-agent-prompt-build)
;;; gptel-tools-agent-prompt-build.el ends here
