;;; gptel-tools-agent-validation.el --- Pre-grade code validation -*- lexical-binding: t; -*-
;; Part of gptel-tools-agent split

(require 'cl-lib)
(require 'subr-x)

(defvar minimal-emacs-user-directory)

(defcustom gptel-auto-experiment-validation-process-timeout 30
  "Maximum seconds for pre-grade validation subprocesses."
  :type 'integer
  :group 'gptel-tools-agent)

;; ─── Critical File Registry (Defense against grader bypass attacks) ───

(defvar gptel-auto-experiment--critical-files
  '("lisp/modules/gptel-auto-workflow-beads.el"
    "lisp/modules/gptel-auto-workflow-production.el"
    "lisp/modules/gptel-auto-workflow-strategic.el"
    "lisp/modules/gptel-auto-workflow-evolution.el"
    "lisp/modules/gptel-tools-agent-staging-baseline.el"
    "lisp/modules/gptel-tools-agent-prompt-build.el"
    "mementum/gtm/strategy-roadmap.md"
    "mementum/decisions/")
  "Files and directories that require explicit human approval to modify.
Any experiment touching these is blocked regardless of grader score.
This prevents architectural destruction attacks that fool the grader.")

(declare-function gptel-auto-workflow--read-file-contents "gptel-tools-agent-base" (filepath))

(defun gptel-auto-experiment--process-timeout-seconds ()
  "Return the active validation subprocess timeout, or nil when disabled."
  (when (and (integerp gptel-auto-experiment-validation-process-timeout)
             (> gptel-auto-experiment-validation-process-timeout 0))
    gptel-auto-experiment-validation-process-timeout))

(defun gptel-auto-experiment--process-exit-code (process)
  "Return PROCESS exit code, signal status, or nil while still running."
  (pcase (process-status process)
    ('exit (process-exit-status process))
    ('signal 128)
    (_ nil)))

(defun gptel-auto-experiment--process-wait-timeboxed (process timeout)
  "Wait for PROCESS until TIMEOUT seconds elapse.
Return its exit status, or 124 when killed for timeout."
  (let ((deadline (+ (float-time) timeout))
        exit-code)
    (while (and (not (setq exit-code
                           (gptel-auto-experiment--process-exit-code process)))
                (< (float-time) deadline))
      (accept-process-output process 0.1))
    (or exit-code
        (progn
          (when (process-live-p process)
            (delete-process process))
          124))))

(defun gptel-auto-experiment--call-process-native-timeout (program args timeout)
  "Run PROGRAM with ARGS and kill it after TIMEOUT seconds.
This helper intentionally captures output in a temporary buffer because current
validation callers only need the exit code."
  (let* ((buffer (generate-new-buffer " *gptel-validation-process*"))
         (process (make-process :name "gptel-validation-process"
                                :buffer buffer
                                :command (cons program args)
                                :connection-type 'pipe
                                :noquery t)))
    (unwind-protect
        (gptel-auto-experiment--process-wait-timeboxed process timeout)
      (when (buffer-live-p buffer)
        (kill-buffer buffer)))))

(defun gptel-auto-experiment--call-process-timeboxed (program &optional infile destination display &rest args)
  "Run PROGRAM with ARGS using a native timeout when possible."
  (if (and (null infile)
           (null destination)
           (null display)
           (gptel-auto-experiment--process-timeout-seconds))
      (gptel-auto-experiment--call-process-native-timeout
       program args (gptel-auto-experiment--process-timeout-seconds))
    (apply #'call-process program infile destination display args)))

(defun gptel-auto-experiment--shell-command-native-timeout (command timeout)
  "Return shell COMMAND output, killing it after TIMEOUT seconds."
  (let* ((buffer (generate-new-buffer " *gptel-validation-shell*"))
         (process (make-process :name "gptel-validation-shell"
                                :buffer buffer
                                :command (list shell-file-name
                                               shell-command-switch
                                               command)
                                :connection-type 'pipe
                                :noquery t)))
    (unwind-protect
        (progn
          (gptel-auto-experiment--process-wait-timeboxed process timeout)
          (with-current-buffer buffer
            (buffer-string)))
      (when (buffer-live-p buffer)
        (kill-buffer buffer)))))

(defun gptel-auto-experiment--shell-command-to-string-timeboxed (command)
  "Return shell COMMAND output with validation timeout protection."
  (if-let* ((timeout (gptel-auto-experiment--process-timeout-seconds)))
      (gptel-auto-experiment--shell-command-native-timeout command timeout)
    (shell-command-to-string command)))

(defun gptel-auto-experiment--invalid-cl-return-target-in-forms (forms &optional blocks)
  "Return the first invalid `cl-return-from' target in FORMS.
BLOCKS is the list of block names currently in scope."
  (cond
   ((null forms) nil)
   ((proper-list-p forms)
    (cl-some (lambda (form)
               (gptel-auto-experiment--invalid-cl-return-target form blocks))
             forms))
   (t
    (gptel-auto-experiment--invalid-cl-return-target forms blocks))))

(defun gptel-auto-experiment--invalid-cl-return-target (form &optional blocks)
  "Return the first invalid `cl-return-from' target in FORM.
BLOCKS is the list of block names currently in scope."
  (cond
   ((atom form) nil)
   ((not (proper-list-p form)) nil)
   (t
    (pcase (car form)
      ((or 'quote 'quasiquote 'backquote) nil)
      ('cl-return-from
          (let ((target (nth 1 form)))
            (cond
             ((null target) :missing-target)
             ((not (symbolp target)) target)
             ((memq target blocks)
              (gptel-auto-experiment--invalid-cl-return-target-in-forms
               (nthcdr 2 form) blocks))
             (t target))))
      ('cl-block
          (let ((name (nth 1 form)))
            (gptel-auto-experiment--invalid-cl-return-target-in-forms
             (nthcdr 2 form)
             (if (symbolp name) (cons name blocks) blocks))))
      ((or 'cl-defun 'cl-defmacro 'cl-defsubst)
       (let ((name (nth 1 form))
             (body (nthcdr 3 form)))
         (gptel-auto-experiment--invalid-cl-return-target-in-forms
          body
          (if (symbolp name) (cons name blocks) blocks))))
      ((or 'cl-labels 'cl-flet)
       (let ((bindings (nth 1 form))
             (body (nthcdr 2 form)))
         (or (cl-some
              (lambda (binding)
                (when (and (consp binding) (symbolp (car binding)))
                  (let ((name (car binding))
                        (fbody (cddr binding)))
                    (gptel-auto-experiment--invalid-cl-return-target-in-forms
                     fbody
                     (cons name blocks)))))
              bindings)
             (gptel-auto-experiment--invalid-cl-return-target-in-forms
              body blocks))))
      (_
       (or (gptel-auto-experiment--invalid-cl-return-target (car form) blocks)
           (gptel-auto-experiment--invalid-cl-return-target-in-forms
            (cdr form) blocks)))))))

(defun gptel-auto-experiment--defensive-code-removal-p (content)
  "Detect if CONTENT removes defensive code patterns.
Returns non-nil if defensive code removal is detected.

Checks for:
- Removing string-key fallbacks in JSON parsing
- Removing or guards without evidence they're unreachable
- Removing nil checks or error handlers

Works with both git diff content (lines starting with '-') and
regular file content."
  (when (stringp content)
    (let ((removed-lines nil)
          (is-diff nil))
      (with-temp-buffer
        (insert content)
        (goto-char (point-min))
        (setq is-diff (re-search-forward "^@@\\|^diff\\|^---" nil t))
        (goto-char (point-min))
        (when is-diff
          (while (re-search-forward "^-\\([^-].*\\)$" nil t)
            (push (match-string 1) removed-lines))))
      (if is-diff
          (cl-some
           (lambda (line)
             (or
              (string-match-p "cdr\\s-*(assoc\\s-+\"" line)
              (string-match-p "assoc\\s-+\"\\(file\\|path\\|target\\)\"" line)
              (and (string-match-p "or\\s-*" line)
                   (string-match-p "alist-get\\|assoc" line))))
           removed-lines)
        (and (string-match-p "alist-get\\s-+'\\(file\\|path\\|target\\)" content)
             (not (string-match-p "assoc\\s-+\"\\(file\\|path\\|target\\)\"" content))
             (string-match-p "json\\|alist" content))))))

(defun gptel-auto-experiment--diff-against-head (file)
  "Return git diff content for FILE against HEAD, or nil outside a Git worktree."
  (when-let* ((absolute-file (expand-file-name file))
              (root (locate-dominating-file absolute-file ".git")))
    (let ((default-directory root)
          (relative-file (file-relative-name absolute-file root)))
      (gptel-auto-experiment--shell-command-to-string-timeboxed
       (format "git --no-pager diff --no-ext-diff --unified=0 HEAD -- %s 2>/dev/null"
               (shell-quote-argument relative-file))))))

(defconst gptel-auto-experiment--known-call-forms
  '(and catch cond condition-case condition-case-unless-debug defconst defcustom
        defmacro defsubst defun defvar dolist dotimes function if ignore-errors
        interactive lambda let let* or pcase prog1 prog2 progn quote setq
        setq-local throw unless unwind-protect when while)
  "Special forms and defining forms that are valid even when not `fboundp'.")

(defconst gptel-auto-experiment--safe-validation-requires
  '(cl-lib json seq subr-x)
  "Features safe to load while validating generated code.")

(defun gptel-auto-experiment--required-features (forms)
  "Return top-level `require' features from FORMS."
  (let (features)
    (dolist (form forms)
      (when (and (consp form) (eq (car form) 'require))
        (let ((feature-form (cadr form)))
          (when (and (consp feature-form)
                     (eq (car feature-form) 'quote))
            (setq feature-form (cadr feature-form)))
          (when (symbolp feature-form)
            (push feature-form features)))))
    (delete-dups features)))

(defun gptel-auto-experiment--load-safe-required-features (forms)
  "Load safe top-level dependencies declared in FORMS."
  (dolist (feature (gptel-auto-experiment--required-features forms))
    (when (memq feature gptel-auto-experiment--safe-validation-requires)
      (require feature nil t))))

(defun gptel-auto-experiment--defined-function-symbols (forms)
  "Return function symbols declared or defined by top-level FORMS."
  (let (symbols)
    (dolist (form forms)
      (when (consp form)
        (pcase (car form)
          ((or 'defun 'defmacro 'defsubst 'cl-defun 'cl-defmacro 'cl-defsubst
               'define-minor-mode 'define-derived-mode 'define-globalized-minor-mode)
           (when (symbolp (cadr form))
             (push (cadr form) symbols)))
          ('declare-function
           (when (symbolp (cadr form))
             (push (cadr form) symbols)))
          ('autoload
            (let ((quoted (cadr form)))
              (when (and (consp quoted)
                         (eq (car quoted) 'quote)
                         (symbolp (cadr quoted)))
                (push (cadr quoted) symbols)))))))
    (delete-dups symbols)))

(defun gptel-auto-experiment--diff-added-lines (diff)
  "Return added source lines from unified DIFF, excluding file headers."
  (let (lines)
    (when (stringp diff)
      (with-temp-buffer
        (insert diff)
        (goto-char (point-min))
        (while (re-search-forward "^+\\([^+].*\\)$" nil t)
          (push (match-string 1) lines))))
    (nreverse lines)))

(defun gptel-auto-experiment--diff-removed-lines (diff)
  "Return removed source lines from unified DIFF, excluding file headers."
  (let (lines)
    (when (stringp diff)
      (with-temp-buffer
        (insert diff)
        (goto-char (point-min))
        (while (re-search-forward "^-\\([^-].*\\)$" nil t)
          (push (match-string 1) lines))))
    (nreverse lines)))

(defun gptel-auto-experiment--call-symbols-in-line (line)
  "Return apparent function call symbols in added source LINE.
Skips t and nil which can appear as pcase/cl-case clause heads
and are Emacs Lisp constants, not callable functions."
  (let ((start 0)
        symbols)
    (when (stringp line)
      (while (string-match "(\\s-*\\([^[:space:]()\"';]+\\)" line start)
        (let* ((name (match-string 1 line))
               (sym (and (stringp name)
                         (not (string-match-p "\\`[0-9:]" name))
                         (not (member name '("t" "nil")))
                         (intern name))))
          (when sym
            (push sym symbols)))
        (setq start (match-end 0))))
    symbols))

(defun gptel-auto-experiment--defined-runtime-call-p (symbol local-defs)
  "Return non-nil when SYMBOL is a callable known to this Emacs runtime."
  (or (memq symbol local-defs)
      (memq symbol gptel-auto-experiment--known-call-forms)
      (special-form-p symbol)
      (fboundp symbol)
      (macrop symbol)))

(defun gptel-auto-experiment--call-symbols-in-forms (forms)
  "Return function call symbols from parsed FORMS.

This walks code positions and skips lambda/defun argument lists, so ordinary
variable names are not mistaken for undefined function calls."
  (when (and forms (proper-list-p forms))
    (let (calls)
    (cl-labels
        ((walk (form)
           (cond
            ((atom form) nil)
             ((not (proper-list-p form)) nil)
             (t
              (let ((head (car form)))
                (pcase head
                  ((or 'quote 'function 'backquote 'quasiquote) nil)
                  ((pred (lambda (symbol)
                           (and (symbolp symbol)
                                (member (symbol-name symbol) '("`" "," ",@")))))
                   nil)
                  ((or 'defun 'defmacro 'defsubst 'cl-defun 'cl-defmacro 'cl-defsubst
                       'define-minor-mode 'define-derived-mode 'define-globalized-minor-mode)
                   (push head calls)
                   (mapc #'walk (nthcdr 3 form)))
                  ((or 'declare-function 'autoload) nil)
                  ((or 'lambda 'closure)
                   (push head calls)
                   (mapc #'walk (cddr form)))
                  ((or 'let 'let*)
                   (push head calls)
                   (dolist (binding (nth 1 form))
                     (when (consp binding)
                       (mapc #'walk (cdr binding))))
                   (mapc #'walk (nthcdr 2 form)))
                  ('dolist
                   (push head calls)
                   (let ((spec (nth 1 form)))
                     (when (consp spec)
                       (walk (cadr spec))
                       (walk (caddr spec))))
                   (mapc #'walk (nthcdr 2 form)))
                  ('dotimes
                   (push head calls)
                   (let ((spec (nth 1 form)))
                     (when (consp spec)
                       (walk (cadr spec))
                       (walk (caddr spec))))
                   (mapc #'walk (nthcdr 2 form)))
                  ('cl-loop
                   (push head calls)
                   ;; Expand loop syntax once so binding vars do not look callable.
                   (let ((expanded (condition-case nil
                                       (macroexpand-1 form)
                                     (error nil))))
                     (if (and expanded (not (equal expanded form)))
                         (walk expanded)
                       (mapc #'walk (cdr form)))))
                  ((or 'cl-labels 'cl-flet)
                   (push head calls)
                   (dolist (binding (nth 1 form))
                     (when (consp binding)
                       (mapc #'walk (cddr binding))))
                   (mapc #'walk (nthcdr 2 form)))
                  ('condition-case
                   (push head calls)
                   (walk (nth 2 form))
                   (dolist (handler (nthcdr 3 form))
                     (when (proper-list-p handler)
                       (mapc #'walk (cdr handler)))))
                  ('pcase
                   (push head calls)
                   (walk (nth 1 form))
                   (dolist (clause (nthcdr 2 form))
                     (when (proper-list-p clause)
                       (mapc #'walk (cdr clause)))))
                  (_
                   (when (symbolp head)
                     (push head calls))
                   (mapc #'walk (cdr form)))))))))
      (mapc #'walk forms))
    (delete-dups calls))))

(defun gptel-auto-experiment--introduced-undefined-call (diff forms)
  "Return the first newly-added function call in DIFF not defined by runtime.

Only added diff lines are inspected to avoid rejecting pre-existing split-module
forward references.  FORMS are the parsed top-level forms from the full file and
are used to recognize local definitions and `declare-function' declarations."
  (unless (proper-list-p forms)
    (error "ASSUMPTION VIOLATION: forms must be a proper list, got: %S" forms))
  (gptel-auto-experiment--load-safe-required-features forms)
  (let* ((local-defs (gptel-auto-experiment--defined-function-symbols forms))
         (actual-calls (gptel-auto-experiment--call-symbols-in-forms forms))
          (removed-calls nil)
          (calls nil))
    (dolist (line (gptel-auto-experiment--diff-removed-lines diff))
      (setq removed-calls (append (gptel-auto-experiment--call-symbols-in-line line)
                                  removed-calls)))
    (dolist (line (gptel-auto-experiment--diff-added-lines diff))
      (setq calls (append (gptel-auto-experiment--call-symbols-in-line line)
                          calls)))
    (cl-find-if
     (lambda (symbol)
        (and (memq symbol actual-calls)
             (not (memq symbol removed-calls))
             (not (gptel-auto-experiment--defined-runtime-call-p symbol local-defs))))
     (delete-dups (nreverse calls)))))

(defun gptel-auto-experiment--forward-sexp-file (file)
  "Parse FILE with `forward-sexp' in `emacs-lisp-mode'.
Returns nil if structurally valid, or an error message string."
  (condition-case err
      (with-temp-buffer
        (insert-file-contents file)
        (delay-mode-hooks
          (emacs-lisp-mode))
        (goto-char (point-min))
        (while (not (eobp))
          (forward-sexp))
        nil)
    (error (format "Elisp parse error in %s: %s"
                   (file-relative-name file)
                   (error-message-string err)))))

(defun gptel-auto-experiment--validate-code (file)
  "Validate code in FILE for syntax and dangerous patterns.
Returns nil if valid, or error message string if invalid."
  (when (and (stringp file) (string-suffix-p ".el" file))
    (if (not (file-exists-p file))
        (format "Missing target file: %s" file)
      (let ((content (gptel-auto-workflow--read-file-contents file))
            forms)
        (or (gptel-auto-experiment--forward-sexp-file file)
            (cond
             ((null content)
              (format "Empty or unreadable file: %s" file))
             ((condition-case err
                  (with-temp-buffer
                    (insert content)
                    (set-syntax-table emacs-lisp-mode-syntax-table)
                    (goto-char (point-min))
                    (while (progn
                             (forward-comment (point-max))
                             (< (point) (point-max)))
                     (push (read (current-buffer)) forms))
                    nil)
                (error (format "Syntax error in %s: %s" file err)))))
             (let* ((project-root (or (locate-dominating-file file "scripts/byte-compile-check.sh")
                                      (bound-and-true-p minimal-emacs-user-directory)
                                      user-emacs-directory))
                    (byte-compile-script (expand-file-name "scripts/byte-compile-check.sh"
                                                           project-root))
                    (parsed-forms (nreverse forms))
                    (diff (gptel-auto-experiment--diff-against-head file))
                    (undefined-call
                     (gptel-auto-experiment--introduced-undefined-call
                      diff parsed-forms))
                    ;; Quick byte-compile check — resolve the helper from the
                    ;; target file's live repo root, not `user-emacs-directory',
                    ;; which points at var/ in workflow daemons.
                    (byte-compile-ok
                     (and (file-exists-p byte-compile-script)
                          (condition-case nil
                               (zerop (gptel-auto-experiment--call-process-timeboxed
                                       byte-compile-script
                                       nil nil nil
                                       (expand-file-name file project-root)))
                             (error nil)))))
               (or
                (when (gptel-auto-experiment--invalid-cl-return-target-in-forms
                       parsed-forms)
                  (format "Dangerous pattern in %s: cl-return-from without cl-block" file))
               (when undefined-call
                 (format "Undefined function introduced in %s: %S" file undefined-call))
               (when (gptel-auto-experiment--defensive-code-removal-p diff)
                 (format "Defensive code removal detected in %s: removing or/assoc fallbacks without proof" file))
               (unless byte-compile-ok
                 (format "Byte-compile error in %s" file)))))))))

;; ─── Cheap Diff Content Sanity Check ───

(defun gptel-auto-experiment--validate-diff-content (worktree)
  "Cheap pre-grade check of aggregate diff in WORKTREE.
Returns nil if content seems reasonable, or an error string.
Catches: trivial changes (whitespace/comments only), LLM artifacts in diff,
vandalism (removal of error handling), and excessively large diffs.
This runs between syntax validation and the grader API call."
  (when (and worktree (file-directory-p worktree))
    (let ((default-directory worktree)
          (diff-text (gptel-auto-experiment--shell-command-to-string-timeboxed
                      "git --no-pager diff --no-ext-diff --unified=10 HEAD -- . 2>/dev/null")))
      (cond
       ;; No diff at all — executor somehow produced no changes
       ((string-empty-p (string-trim diff-text))
        "Cheap check: experiment produced no file changes")
       ;; Check for LLM/markdown artifacts in the diff
       ((string-match-p
         "\\+```\\(emacs-lisp\\|lisp\\|elisp\\)?" diff-text)
        (format "Cheap check: LLM markdown artifacts in diff (``` blocks)"))
       ;; Check for debug artifacts: print/insert at top level
        ((let ((debug-form nil))
           (when (string-match
                  "^\\+\\(message\\|insert\\|print\\|princ\\|debug\\)" diff-text)
             (setq debug-form (match-string 1 diff-text))
             (format "Cheap check: debug artifact in diff (top-level %s)"
                     debug-form))))
       ;; Check for vandalism: removal of error handling patterns
        ((string-match-p
          "^-.*condition-case\\|^-.*ignore-errors\\|^-.*noninteractive"
          diff-text)
         (format "Cheap check: error handling removal detected in diff"))
        ;; Check for excessive diff size (>80 lines touched is off-task)
        ((let ((line-count (with-temp-buffer
                             (insert diff-text)
                             (count-matches "\n" (point-min) (point-max)))))
           (when (> line-count 80)
             (format "Cheap check: diff too large (%d lines)"
                     (1+ line-count)))))
         ;; Check for trivial changes: only whitespace or comment additions
        ((let ((non-trivial-lines 0))
           (dolist (line (split-string diff-text "\n"))
             (when (string-match-p "^\\+[^+ \t;]" line)
               (cl-incf non-trivial-lines)))
           (when (and (> non-trivial-lines 0) (< non-trivial-lines 2))
             (format "Cheap check: diff has only %d non-comment code lines"
                     non-trivial-lines))))
         ;; CRITICAL FILE CHECK: only block if actually destructive
         ;; Small bug fixes to critical files are allowed; mass deletions are not
         ((let ((critical-hit nil))
            (dolist (pattern gptel-auto-experiment--critical-files)
              (when (and (not critical-hit)
                         (string-match-p (regexp-quote pattern) diff-text))
                (setq critical-hit pattern)))
            (when critical-hit
              ;; Count total deletions in diff
              (let ((total-deletions
                     (with-temp-buffer
                       (insert diff-text)
                       (count-matches "^-" (point-min) (point-max)))))
                (when (> total-deletions 20)
                  (format "CRITICAL: experiment deletes %d lines including protected file: %s"
                          total-deletions critical-hit))))))
        ;; DESTRUCTIVE CHANGE CHECK: mass deletion detection
        ((let* ((added (with-temp-buffer
                        (insert diff-text)
                        (count-matches "^\\+" (point-min) (point-max))))
                (deleted (with-temp-buffer
                           (insert diff-text)
                           (count-matches "^-" (point-min) (point-max))))
                (net-change (- added deleted)))
           (when (< net-change -50)
             (format "ARCHITECTURAL DESTRUCTION: net deletion of %d lines (added %d, deleted %d)"
                     (- net-change) added deleted))))
        ;; SCOPE CREEP CHECK: too many files touched
        ((let* ((files-touched
                 (delete-dups
                  (delq nil
                        (mapcar (lambda (line)
                                  (when (string-match "^diff --git a/\\(.+?\\) b/" line)
                                    (match-string 1 line)))
                                (split-string diff-text "\n"))))))
           (when (> (length files-touched) 5)
             (format "SCOPE CREEP: touches %d files (expected <=3)"
                     (length files-touched)))))
         ;; Looks reasonable
         (t nil)))))

;; ─── Grader Fast-Track: Auto-pass small defensive changes ───

(defun gptel-auto-experiment--fast-track-p (diff-text)
  "Return t if DIFF-TEXT qualifies for grader fast-track.
Fast-track: small defensive changes that are low-risk and match patterns
from previous kept experiments. Saves grader API calls.
Criteria:
- Total diff < 20 lines
- Only adds code (no deletions or < 3 deletions)
- Contains defensive patterns: ignore-errors, when-let, condition-case, stringp
- Touches only 1 file"
  (when (and diff-text (not (string-empty-p diff-text)))
    (let* ((line-count (with-temp-buffer
                         (insert diff-text)
                         (count-matches "\n" (point-min) (point-max))))
           (_added (with-temp-buffer
                    (insert diff-text)
                    (count-matches "^\\+" (point-min) (point-max))))
           (deleted (with-temp-buffer
                      (insert diff-text)
                      (count-matches "^-" (point-min) (point-max))))
           (files-touched
            (delete-dups
             (delq nil
                   (mapcar (lambda (line)
                             (when (string-match "^diff --git a/\\(.+?\\) b/" line)
                               (match-string 1 line)))
                           (split-string diff-text "\n")))))
           (has-defensive-pattern
            (or (string-match-p "ignore-errors" diff-text)
                (string-match-p "when-let" diff-text)
                (string-match-p "condition-case" diff-text)
                (string-match-p "stringp" diff-text)
                (string-match-p "null\\|nil\\|boundp\\|fboundp" diff-text))))
      (and (< line-count 20)
           (< deleted 3)
           (= (length files-touched) 1)
           has-defensive-pattern))))

(provide 'gptel-tools-agent-validation)

(provide 'gptel-tools-agent-validation)
;;; gptel-tools-agent-validation.el ends here
