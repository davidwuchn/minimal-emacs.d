;;; gptel-auto-workflow-skill-eval-opencode.el --- Skill evaluation assertion engine for OpenCode -*- lexical-binding: t; -*-

;; Parses YAML task definitions and grades agent transcripts against
;; expected/forbidden behavior assertions.

(require 'cl-lib)

(defcustom gptel-auto-workflow-skill-eval-task-dir
  (expand-file-name "assistant/skills/_eval-tasks/"
                    (or (and (fboundp 'gptel-auto-workflow--worktree-base-root)
                             (gptel-auto-workflow--worktree-base-root))
                        user-emacs-directory))
  "Directory containing skill evaluation task YAML files.
Tasks live alongside the skills they test in assistant/skills/_eval-tasks/."
  :type 'directory
  :group 'gptel-auto-workflow)

(defcustom gptel-auto-workflow-skill-eval-opencode-bin "opencode"
  "Path to the opencode binary."
  :type 'string
  :group 'gptel-auto-workflow)

(defcustom gptel-auto-workflow-skill-eval-timeout 300
  "Timeout in seconds for a single opencode eval run."
  :type 'integer
  :group 'gptel-auto-workflow)

(defcustom gptel-auto-workflow-skill-eval-results-dir
  (expand-file-name "var/tmp/skill-eval-opencode/results/"
                    (or (and (fboundp 'gptel-auto-workflow--worktree-base-root)
                             (gptel-auto-workflow--worktree-base-root))
                        user-emacs-directory))
  "Directory for persisting skill eval results."
  :type 'directory
  :group 'gptel-auto-workflow)

(defcustom gptel-auto-workflow-skill-eval-ab-threshold 0.05
  "Minimum difference in success rate to recommend promote/reject."
  :type 'float
  :group 'gptel-auto-workflow)

;;; ─── Transcript Parser ───

(defun gptel-auto-workflow-skill-eval--parse-transcript-json (json-string)
  "Parse opencode JSON output, return a flat transcript string.
JSON-STRING is newline-delimited JSON from `opencode run --format json'.
Extract text parts and tool calls.  Return a string for assertion
checking."
  (let ((lines (split-string json-string "\n"))
        (parts nil))
    (dolist (line lines)
      (let ((trimmed (string-trim line)))
        (when (string-match-p "^{" trimmed)
          (let* ((parsed
                  (condition-case nil
                      (if (fboundp 'json-parse-string)
                          (json-parse-string trimmed
                                             :object-type 'plist
                                             :null-object nil
                                             :false-object nil)
                        (gptel-auto-workflow-skill-eval--parse-json-regex trimmed))
                    (error nil)))
                 (ptype (when parsed (plist-get parsed :type))))
            (when ptype
              (cond
               ((string= ptype "text")
                (let ((text (plist-get parsed :text)))
                  (when (and text (stringp text)
                             (not (string-empty-p (string-trim text))))
                    (push (string-trim text) parts))))
               ((string= ptype "tool")
                (let* ((tool-name (or (plist-get parsed :tool) "unknown"))
                       (state (plist-get parsed :state))
                       (output (when state (plist-get state :output)))
                       (output-str (if (and output (stringp output))
                                       (substring output 0 (min (length output) 200))
                                     "")))
                  (push (format "TOOL: %s OUTPUT: %s" tool-name output-str)
                        parts)))))))))
    (string-join (nreverse parts) "\n")))

(defun gptel-auto-workflow-skill-eval--parse-json-regex (json-line)
  "Fallback regex-based JSON parser for a single-line JSON object.
Extracts :type, :text, :tool, and :state subkeys into a plist.
Used when `json-parse-string' is unavailable."
  (let ((result nil))
    (when (string-match "\"type\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\"" json-line)
      (setq result (plist-put result :type (match-string 1 json-line))))
    (when (string-match "\"text\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\"" json-line)
      (setq result (plist-put result :text (match-string 1 json-line))))
    (when (string-match "\"tool\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\"" json-line)
      (setq result (plist-put result :tool (match-string 1 json-line))))
    (when (string-match "\"output\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\"" json-line)
      (let ((output (match-string 1 json-line)))
        (setq result (plist-put result :state (list :output output)))))
    result))

;;; ─── Opencode Executor ───

(defun gptel-auto-workflow-skill-eval-run (task skill-variant-file)
  "Run a single opencode eval with TASK and SKILL-VARIANT-FILE.
TASK is a parsed task plist from `gptel-auto-workflow-skill-eval-parse-task'.
SKILL-VARIANT-FILE is the path to the SKILL.md variant to test.
Temporarily replaces the .opencode/skills/<skill> symlink to inject variant.
Returns plist (:transcript STR :grade PLIST :duration FLOAT :exit-code INT)."
  (let* ((skill-name (plist-get task :skill))
         (prompt (plist-get task :prompt))
         (project-root (or (and (fboundp 'gptel-auto-workflow--worktree-base-root)
                                (gptel-auto-workflow--worktree-base-root))
                           default-directory))
         (symlink-path (expand-file-name (format ".opencode/skills/%s" skill-name)
                                         project-root))
         (original-target nil)
         (temp-skill-dir nil)
         (start-time (float-time))
         (output-buf (generate-new-buffer " *opencode-eval*"))
         exit-code
         stdout-str)
    (unwind-protect
        (progn
          ;; 1. Save original symlink target
          (when (file-symlink-p symlink-path)
            (setq original-target (file-symlink-p symlink-path)))
          ;; 2. Create temp dir with SKILL.md -> variant
          (setq temp-skill-dir (make-temp-file "opencode-skill-eval-" t))
          (make-symbolic-link (expand-file-name skill-variant-file)
                              (expand-file-name "SKILL.md" temp-skill-dir)
                              t)
          ;; 3. Replace symlink
          (when (file-exists-p symlink-path)
            (delete-file symlink-path))
          (make-symbolic-link temp-skill-dir symlink-path t)
          ;; 4. Run opencode
          (let ((default-directory project-root))
            (setq exit-code
                  (call-process gptel-auto-workflow-skill-eval-opencode-bin
                                nil output-buf nil
                                "run" "--format" "json"
                                "--dir" project-root
                                prompt))
            (setq stdout-str
                  (with-current-buffer output-buf
                    (buffer-string)))))
      ;; Cleanup: restore original symlink
      (when symlink-path
        (when (file-exists-p symlink-path)
          (delete-file symlink-path))
        (when original-target
          (make-symbolic-link original-target symlink-path t)))
      (when (and temp-skill-dir (file-exists-p temp-skill-dir))
        (delete-directory temp-skill-dir t))
      (when (buffer-live-p output-buf)
        (kill-buffer output-buf)))
    (let* ((transcript (gptel-auto-workflow-skill-eval--parse-transcript-json
                        (or stdout-str "")))
           (grade (gptel-auto-workflow-skill-eval-grade task transcript))
           (duration (- (float-time) start-time)))
      (list :transcript transcript
            :grade grade
            :duration duration
            :exit-code exit-code))))

;;; ─── A/B Runner ───

(defun gptel-auto-workflow-skill-eval--locate-treatment-variant (skill-name)
  "Locate the treatment variant SKILL.md for SKILL-NAME.
Checks `assistant/skills/_eval-tasks/{skill}-candidate.md' first,
then `var/tmp/skill-eval-opencode/variants/{skill}-candidate.md'.
Returns the file path if found, nil otherwise."
  (let* ((root (or (and (fboundp 'gptel-auto-workflow--worktree-base-root)
                        (gptel-auto-workflow--worktree-base-root))
                   default-directory))
         (candidates
          (list (expand-file-name (format "assistant/skills/_eval-tasks/%s-candidate.md"
                                          skill-name)
                                  root)
                (expand-file-name (format "var/tmp/skill-eval-opencode/variants/%s-candidate.md"
                                          skill-name)
                                  root))))
    (cl-find-if #'file-exists-p candidates)))

(defun gptel-auto-workflow-skill-eval--compute-success-rate (run-results)
  "Compute the overall success rate from RUN-RESULTS plists.
Returns a float 0.0-1.0."
  (if (null run-results)
      0.0
    (let ((total-pass 0)
          (total-assertions 0))
      (dolist (r run-results)
        (let ((grade (plist-get r :grade)))
          (when grade
            (cl-incf total-pass (or (plist-get grade :pass-count) 0))
            (cl-incf total-assertions (or (plist-get grade :total) 0)))))
      (if (> total-assertions 0)
          (/ (float total-pass) total-assertions)
        0.0))))

(defun gptel-auto-workflow-skill-eval-ab (skill-name task &optional n-runs)
  "Run A/B comparison for SKILL-NAME on TASK, N-RUNS per arm (default 3).
Baseline uses `assistant/skills/{skill}/SKILL.md'.
Treatment is found via `--locate-treatment-variant'.
Return plist with :baseline-rate, :treatment-rate, :recommendation."
  (or n-runs (setq n-runs 3))
  (let* ((root (or (and (fboundp 'gptel-auto-workflow--worktree-base-root)
                        (gptel-auto-workflow--worktree-base-root))
                   default-directory))
         (baseline-file (expand-file-name
                         (format "assistant/skills/%s/SKILL.md" skill-name) root))
         (treatment-file (gptel-auto-workflow-skill-eval--locate-treatment-variant
                          skill-name))
         baseline-results treatment-results)
    ;; Run baseline
    (dotimes (_ n-runs)
      (push (gptel-auto-workflow-skill-eval-run task baseline-file)
            baseline-results))
    (setq baseline-results (nreverse baseline-results))
    ;; Run treatment (if available)
    (when treatment-file
      (dotimes (_ n-runs)
        (push (gptel-auto-workflow-skill-eval-run task treatment-file)
              treatment-results))
      (setq treatment-results (nreverse treatment-results)))
    ;; Compute rates and recommendation
    (let* ((baseline-rate
            (gptel-auto-workflow-skill-eval--compute-success-rate baseline-results))
           (treatment-rate
            (if treatment-results
                (gptel-auto-workflow-skill-eval--compute-success-rate treatment-results)
              0.0))
           (delta (- treatment-rate baseline-rate))
           (recommendation
            (cond
             ((not treatment-file) "no-variant")
             ((>= delta gptel-auto-workflow-skill-eval-ab-threshold) "promote")
             ((<= delta (- gptel-auto-workflow-skill-eval-ab-threshold)) "reject")
             (t "indeterminate"))))
      (list :skill skill-name
            :task (plist-get task :name)
            :baseline-results baseline-results
            :treatment-results treatment-results
            :baseline-rate baseline-rate
            :treatment-rate treatment-rate
            :recommendation recommendation))))

;;; ─── Result Persistence ───

(defun gptel-auto-workflow-skill-eval-save-result (result)
  "Save RESULT plist to a JSON file in the results directory.
Returns the file path of the saved result."
  (let* ((dir (expand-file-name gptel-auto-workflow-skill-eval-results-dir))
         (skill (plist-get result :skill))
         (variant (or (plist-get result :variant) "unknown"))
         (ts (format-time-string "%Y%m%dT%H%M%S"))
         (filename (format "%s-%s-%s.json" skill variant ts))
         (filepath (expand-file-name filename dir))
         (transcript (plist-get result :transcript))
         (excerpt (if transcript
                      (let ((s (string-trim transcript)))
                        (if (> (length s) 500)
                            (concat (substring s 0 500) "...")
                          s))
                    ""))
         (grade (plist-get result :grade))
         (duration (plist-get result :duration))
         (data `(:skill ,skill :task ,(plist-get result :task)
                   :timestamp ,ts :variant ,variant :duration ,duration
                   :grade (:pass-count ,(plist-get grade :pass-count)
                           :fail-count ,(plist-get grade :fail-count)
                           :total ,(plist-get grade :total))
                   :transcript-excerpt ,excerpt)))
    (unless (file-exists-p dir)
      (make-directory dir t))
    (with-temp-file filepath
      (insert (if (fboundp 'json-serialize)
                  (json-serialize data)
                (format "%S" data))))
    filepath))

(defun gptel-auto-workflow-skill-eval--parse-frontmatter (text)
  "Parse YAML-like frontmatter TEXT and return a plist.
Handles:
  - Simple key: value pairs
  - prompt: | block scalar (multiline)
  - expected_behaviors / forbidden_behaviors list sections"
  (let* ((lines (split-string text "\n"))
         (result nil)
         (in-prompt nil)
         (prompt-lines nil)
         (list-key nil)       ;; :expected or :forbidden
         (items nil)
         (current-item nil)
         (i 0)
         (n (length lines)))
    (while (< i n)
      (let ((line (nth i lines)))
        (cond
         ;; Skip empty lines (but not inside prompt block)
         ((and (not in-prompt) (string-match-p "^[ \t]*$" line))
          (setq i (1+ i)))

         ;; Inside prompt multiline block
         (in-prompt
          (if (string-match-p "^[ \t]" line)
              ;; Still in prompt block - collect indented line
              (progn
                (push (string-trim-left line) prompt-lines)
                (setq i (1+ i)))
            ;; Non-indented line ends prompt block; flush and reprocess
            (push :prompt result)
            (push (string-join (nreverse prompt-lines) "\n") result)
            (setq in-prompt nil prompt-lines nil)
            ;; do NOT increment i — reprocess this line as a new key
            ))

         ;; prompt: | starts multiline block
         ((string-match-p "^prompt:[ \t]*|[ \t]*$" line)
          (setq in-prompt t prompt-lines nil)
          (setq i (1+ i)))

         ;; Start of behaviors list section
         ((string-match "^\\(expected_behaviors\\|forbidden_behaviors\\):[ \t]*$" line)
          ;; Flush previous list section before starting a new one
          (when list-key
            (when current-item
              (push current-item items)
              (setq current-item nil))
            (push list-key result)
            (push (nreverse items) result))
          (setq list-key (if (string-match "expected" line) :expected :forbidden))
          (setq items nil current-item nil)
          (setq i (1+ i)))

         ;; List item: "  - key: value"
         ((and list-key
               (string-match "^[ \t]*-[ \t]+\\([a-z_]+\\):[ \t]+\"?\\([^\"]*\\)\"?[ \t]*$" line))
          (when current-item
            (push current-item items))
          (let ((key (intern (concat ":" (match-string 1 line))))
                (val (string-trim (match-string 2 line) "\"" "\"")))
            (setq current-item (list key val)))
          (setq i (1+ i)))

         ;; Nested key:value in current list item (more indented)
         ((and list-key current-item
               (string-match "^[ \t]+\\([a-z_]+\\):[ \t]+\"?\\([^\"]*\\)\"?[ \t]*$" line))
          (let ((key (intern (concat ":" (match-string 1 line))))
                (val (string-trim (match-string 2 line) "\"" "\"")))
            (push val current-item)
            (push key current-item))
          (setq i (1+ i)))

         ;; Top-level simple key: value (no leading whitespace)
         ((string-match "^\\([a-z_]+\\):[ \t]+\"?\\([^\"]*\\)\"?[ \t]*$" line)
          (let ((key (intern (concat ":" (match-string 1 line))))
                (val (string-trim (match-string 2 line) "\"" "\"")))
            (push key result)
            (push val result))
          (setq i (1+ i)))

         ;; Fallback — skip unrecognized line
         (t (setq i (1+ i))))))

    ;; Flush remaining state after loop
    (when in-prompt
      (push :prompt result)
      (push (string-join (nreverse prompt-lines) "\n") result))
    (when current-item
      (push current-item items))
    (when list-key
      (push list-key result)
      (push (nreverse items) result))

    (nreverse result)))

;;; ─── Task Loader ───

(defun gptel-auto-workflow-skill-eval-parse-task (filepath)
  "Parse a task YAML FILEPATH and return a property list.
Extracts frontmatter between the first two `---` markers, then parses
keys, multiline prompt, and expected/forbidden behavior assertions.

Returns plist with keys:
  :name, :skill, :description, :prompt,
  :expected ((:type ... :tool ... :description ...) ...),
  :forbidden ((:type ... :pattern ... :description ...) ...)"
  (with-temp-buffer
    (insert-file-contents filepath)
    (goto-char (point-min))
    (if (re-search-forward "^---$" nil t)
        (let ((start (point)))
          (forward-line 1)
          (if (re-search-forward "^---$" nil t)
              (let* ((end (match-beginning 0))
                     (fm-text (buffer-substring-no-properties start end)))
                (gptel-auto-workflow-skill-eval--parse-frontmatter fm-text))
            ;; Only one --- marker found — parse to end of buffer
            (let ((fm-text (buffer-substring-no-properties start (point-max))))
              (gptel-auto-workflow-skill-eval--parse-frontmatter fm-text))))
      ;; No --- markers — parse entire file
      (gptel-auto-workflow-skill-eval--parse-frontmatter
       (buffer-substring-no-properties (point-min) (point-max))))))

;;; ─── Assertion Checker ───

(defun gptel-auto-workflow-skill-eval-check-assertion (assertion transcript)
  "Check a single ASSERTION against the agent TRANSCRIPT.
ASSERTION is a plist with at least :type and :description.
TRANSCRIPT is a string of the agent's tool call output.

Supported assertion types and their plist keys:
  :tool-used       — (:tool \"emacsclient\")
  :pattern-present — (:pattern \"regex\")
  :pattern-absent  — (:pattern \"regex\")
  :output-contains — (:text \"literal\")

Returns a plist: (:pass t|nil :description \"...\")"
  (let* ((atype (plist-get assertion :type))
         (desc (plist-get assertion :description)))
    (cond
     ((string= atype "tool-used")
      (let* ((tool (plist-get assertion :tool))
             (found (when tool
                      (string-match-p (regexp-quote (downcase tool))
                                       (downcase transcript)))))
        (list :pass (and found t) :description desc)))

     ((string= atype "pattern-present")
      (let* ((pattern (plist-get assertion :pattern))
             (found (when pattern
                      (condition-case nil
                          (string-match-p pattern transcript)
                        (error nil)))))
        (list :pass (and found t) :description desc)))

     ((string= atype "pattern-absent")
      (let* ((pattern (plist-get assertion :pattern))
             (found (when pattern
                      (condition-case nil
                          (string-match-p pattern transcript)
                        (error nil)))))
        (list :pass (not found) :description desc)))

     ((string= atype "output-contains")
      (let* ((text (plist-get assertion :text))
             (found (when text
                      (string-match-p (regexp-quote text) transcript))))
        (list :pass (and found t) :description desc)))

     (t
      (list :pass nil :description (format "Unknown assertion type: %s" atype))))))

;;; ─── Grader ───

(defun gptel-auto-workflow-skill-eval-grade (task transcript)
  "Grade a TRANSCRIPT against all assertions in TASK.
TASK is a plist with :expected and :forbidden assertion lists.
TRANSCRIPT is a string.

Returns a plist:
  (:pass-count N :fail-count N :total N
   :results ((:pass t|nil :type \"tool-used\" :description \"...\") ...))"
  (let ((results nil)
        (pass-count 0)
        (fail-count 0))
    ;; Check expected behaviors
    (dolist (assertion (plist-get task :expected))
      (let ((res (gptel-auto-workflow-skill-eval-check-assertion assertion transcript)))
        (push (plist-put res :type (plist-get assertion :type)) results)
        (if (plist-get res :pass)
            (setq pass-count (1+ pass-count))
          (setq fail-count (1+ fail-count)))))
    ;; Check forbidden behaviors
    (dolist (assertion (plist-get task :forbidden))
      (let ((res (gptel-auto-workflow-skill-eval-check-assertion assertion transcript)))
        (push (plist-put res :type (plist-get assertion :type)) results)
        (if (plist-get res :pass)
            (setq pass-count (1+ pass-count))
          (setq fail-count (1+ fail-count)))))
    (list :pass-count pass-count
          :fail-count fail-count
          :total (+ pass-count fail-count)
          :results (nreverse results))))

;;; ─── Batch Loader ───

(defun gptel-auto-workflow-skill-eval-load-tasks (directory)
  "Load all .yaml task files from DIRECTORY.
Returns a list of task plists (as produced by
`gptel-auto-workflow-skill-eval-parse-task')."
  (let ((files (directory-files directory t "\\.yaml\\'" t))
        (tasks nil))
    (dolist (file files)
      (let ((task (condition-case err
                      (gptel-auto-workflow-skill-eval-parse-task file)
                    (error
                     (message "Error parsing %s: %s" file (error-message-string err))
                     nil))))
        (when task
          (push task tasks))))
    (nreverse tasks)))

;;; ─── Variant Generator ───

(defcustom gptel-auto-workflow-skill-eval-variants-dir
  (expand-file-name "var/tmp/skill-eval-opencode/variants/"
                    (or (and (fboundp 'gptel-auto-workflow--worktree-base-root)
                             (gptel-auto-workflow--worktree-base-root))
                        user-emacs-directory))
  "Directory for skill variant candidate files."
  :type 'directory
  :group 'gptel-auto-workflow)

(defun gptel-auto-workflow-skill-eval-generate-variant (skill-name)
  "Generate a skill variant for SKILL-NAME using LLM.
Reads the current SKILL.md and recent eval results, then
prompts the LLM to produce an improved variant.
Writes candidate to the variants directory.
Returns the candidate file path, or nil on failure."
  (let* ((root (or (and (fboundp 'gptel-auto-workflow--worktree-base-root)
                        (gptel-auto-workflow--worktree-base-root))
                   default-directory))
         (current-skill (expand-file-name
                         (format "assistant/skills/%s/SKILL.md" skill-name) root))
         (candidate-file (expand-file-name
                          (format "%s-candidate.md" skill-name)
                          gptel-auto-workflow-skill-eval-variants-dir))
         (current-content (when (file-exists-p current-skill)
                            (with-temp-buffer
                              (insert-file-contents current-skill)
                              (buffer-string))))
         (recent-results (gptel-auto-workflow-skill-eval--recent-results
                          skill-name 5))
         (improvement-hints
          (gptel-auto-workflow-skill-eval--extract-improvement-hints
           recent-results)))
    (if (not current-content)
        (progn
          (message "[skill-eval] Current skill not found: %s" current-skill)
          nil)
      (let* ((prompt (gptel-auto-workflow-skill-eval--make-variant-prompt
                      skill-name current-content improvement-hints))
             (variant-content
              (gptel-auto-workflow-skill-eval--llm-synchronous prompt)))
        (when (and variant-content (stringp variant-content)
                   (> (length (string-trim variant-content)) 50))
          (unless (file-exists-p gptel-auto-workflow-skill-eval-variants-dir)
            (make-directory gptel-auto-workflow-skill-eval-variants-dir t))
          (with-temp-file candidate-file
            (insert variant-content))
          (message "[skill-eval] Variant written: %s" candidate-file)
          candidate-file)))))

(defun gptel-auto-workflow-skill-eval--make-variant-prompt
  (skill-name current-content hints)
  "Build the LLM prompt for generating a SKILL-NAME variant.
CURRENT-CONTENT is the current SKILL.md text.
HINTS is a string of improvement suggestions from eval results."
  (format
   "You are a prompt engineer. Improve the following opencode SKILL.md.

SKILL NAME: %s

CURRENT SKILL.md:
```
%s
```

RECENT EVAL RESULTS (what to improve):
%s

RULES:
1. Keep the YAML frontmatter structure (--- delimited)
2. Keep the same skill name and triggers
3. Focus on the improvement areas identified in eval results
4. Make instructions more specific and actionable
5. Keep the total length under 300 lines
6. Output ONLY the improved SKILL.md content, no commentary

Improved SKILL.md:"
   skill-name
   (if (> (length current-content) 3000)
       (concat (substring current-content 0 3000) "\n... (truncated)")
     current-content)
   (or hints "No specific improvements identified. General refinement.")))

(defun gptel-auto-workflow-skill-eval--extract-improvement-hints (results)
  "Extract improvement hints from RESULTS list.
Each result is a plist from a completed eval run.
Returns a human-readable string of improvement suggestions."
  (if (null results)
      ""
    (let ((hints nil)
          (fail-patterns nil))
      (dolist (r results)
        (let ((grade (plist-get r :grade)))
          (when grade
            (let ((fail-count (or (plist-get grade :fail-count) 0)))
              (when (> fail-count 0)
                (push (format "Run had %d/%d failures"
                              fail-count (or (plist-get grade :total) 0))
                      fail-patterns))))))
      (when fail-patterns
        (push (format "Common failures (%d runs): %s"
                      (length fail-patterns)
                      (string-join fail-patterns "; "))
              hints))
      (string-join hints "\n"))))

(defun gptel-auto-workflow-skill-eval--recent-results (skill-name limit)
  "Load the LIMIT most recent eval results for SKILL-NAME.
Returns a list of result plists."
  (let* ((dir (expand-file-name gptel-auto-workflow-skill-eval-results-dir))
         (results nil))
    (when (file-exists-p dir)
      (let ((files (sort (directory-files dir t "\\.json\\'" t)
                         (lambda (a b)
                           (time-less-p
                            (nth 5 (file-attributes b))
                            (nth 5 (file-attributes a)))))))
        (dolist (f files)
          (when (< (length results) limit)
            (condition-case nil
                (with-temp-buffer
                  (insert-file-contents f)
                  (let ((data (json-parse-string (buffer-string)
                                                 :object-type 'plist
                                                 :null-object nil
                                                 :false-object nil)))
                    (when (and data
                               (string= (plist-get data :skill) skill-name))
                      (push (plist-get data :grade) results)
                      ;; Also attach transcript-excerpt for hint extraction
                      (setcar results
                              (list :grade (car results)
                                    :transcript (plist-get data
                                                           :transcript-excerpt))))))
              (error nil))))))
    (nreverse results)))

(defun gptel-auto-workflow-skill-eval--llm-synchronous (prompt)
  "Call LLM synchronously with PROMPT and return the response text.
Uses `gptel-request' if available, otherwise returns nil."
  (when (fboundp 'gptel-request)
    (let ((result nil)
          (done nil))
      (gptel-request prompt
        :callback (lambda (response &rest _)
                    (setq result response
                          done t)))
      ;; Wait up to 60 seconds
      (let ((waited 0))
        (while (and (not done) (< waited 60))
          (sleep-for 0.5)
          (cl-incf waited 0.5)))
      result)))

;;; ─── Promotion Pipeline ───

(defun gptel-auto-workflow-skill-eval-promote (skill-name ab-result)
  "Promote a winning skill variant to the canonical location.
SKILL-NAME is the skill being evolved.
AB-RESULT is the plist from `gptel-auto-workflow-skill-eval-ab'.
Enqueues to the human approval queue if `recommendation' is \"promote\".
Does nothing if recommendation is not \"promote\".
Returns the queue entry if enqueued, nil otherwise."
  (let ((recommendation (plist-get ab-result :recommendation))
        (treatment-rate (plist-get ab-result :treatment-rate))
        (baseline-rate (plist-get ab-result :baseline-rate)))
    (when (not (string= recommendation "promote"))
      (message "[skill-eval] Not promoting %s: recommendation=%s"
               skill-name recommendation)
      (cl-return-from gptel-auto-workflow-skill-eval-promote nil))
    (let* ((root (or (and (fboundp 'gptel-auto-workflow--worktree-base-root)
                          (gptel-auto-workflow--worktree-base-root))
                     default-directory))
           (candidate (gptel-auto-workflow-skill-eval--locate-treatment-variant
                       skill-name))
           (canonical (expand-file-name
                       (format "assistant/skills/%s/SKILL.md" skill-name) root))
           (delta (- treatment-rate baseline-rate)))
      (when (not candidate)
        (message "[skill-eval] No candidate variant for %s" skill-name)
        (cl-return-from gptel-auto-workflow-skill-eval-promote nil))
      ;; Enqueue for human approval
      (when (fboundp 'gptel-auto-workflow-approval-queue-enqueue)
        (let* ((rollback-tag (format "skill-%s-before-promote-%s"
                                     skill-name
                                     (format-time-string "%Y%m%d-%H%M%S")))
               (proposal
                (list :type "skill-promotion"
                      :component (format "skill/%s" skill-name)
                      :pattern-target (format "assistant/skills/%s/SKILL.md"
                                              skill-name)
                      :risk "medium"
                      :source "skill-eval-opencode"
                      :description (format
                                    "Promote %s skill variant (treatment=%.2f baseline=%.2f delta=%.2f)"
                                    skill-name treatment-rate baseline-rate delta)
                      :action (list 'skill-promote
                                    :skill skill-name
                                    :candidate candidate
                                    :canonical canonical)))
               (entry
                (gptel-auto-workflow-approval-queue-enqueue
                 proposal rollback-tag)))
          (when entry
            (message "[skill-eval] Enqueued promotion for %s (id=%s)"
                     skill-name (plist-get entry :id)))
          entry)))))

(defun gptel-auto-workflow-skill-eval-execute-promotion (skill-name
                                                          candidate-file
                                                          canonical-file)
  "Execute the promotion: copy CANDIDATE-FILE to CANONICAL-FILE.
SKILL-NAME is used for logging and git commit message.
This function is called by the approval queue executor after
human approval.  Returns t on success, nil on failure."
  (ignore-errors
    (copy-file candidate-file canonical-file t)
    (delete-file candidate-file)
    (message "[skill-eval] Promoted %s: %s -> %s"
             skill-name candidate-file canonical-file)
    t))

(provide 'gptel-auto-workflow-skill-eval-opencode)
;;; gptel-auto-workflow-skill-eval-opencode.el ends here
