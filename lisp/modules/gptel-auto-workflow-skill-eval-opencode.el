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

;;; ─── Frontmatter Parser ───

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

(provide 'gptel-auto-workflow-skill-eval-opencode)
;;; gptel-auto-workflow-skill-eval-opencode.el ends here
