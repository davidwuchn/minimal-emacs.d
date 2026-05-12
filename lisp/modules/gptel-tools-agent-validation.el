;;; gptel-tools-agent-validation.el --- Pre-grade code validation -*- lexical-binding: t; -*-
;; Part of gptel-tools-agent split

(require 'cl-lib)
(require 'subr-x)

(declare-function gptel-auto-workflow--read-file-contents "gptel-tools-agent-base" (filepath))

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
         (or (and (symbolp target)
                  (not (memq target blocks))
                  target)
             (gptel-auto-experiment--invalid-cl-return-target-in-forms
              (nthcdr 2 form) blocks))))
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
      (shell-command-to-string
       (format "git --no-pager diff --no-ext-diff --unified=0 HEAD -- %s 2>/dev/null"
               (shell-quote-argument relative-file))))))

(defconst gptel-auto-experiment--known-call-forms
  '(and catch cond condition-case condition-case-unless-debug defconst defcustom
        defmacro defsubst defun defvar dolist dotimes function if ignore-errors
        interactive lambda let let* or pcase prog1 prog2 progn quote setq
        setq-local throw unless unwind-protect when while)
  "Special forms and defining forms that are valid even when not `fboundp'.")

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
  (let (calls)
    (cl-labels
        ((walk (form)
           (cond
            ((atom form) nil)
            ((not (proper-list-p form)) nil)
            (t
             (let ((head (car form)))
               (when (symbolp head)
                 (push head calls))
               (pcase head
                 ((or 'quote 'function 'backquote 'quasiquote) nil)
                 ((or 'defun 'defmacro 'defsubst 'cl-defun 'cl-defmacro 'cl-defsubst
                      'define-minor-mode 'define-derived-mode 'define-globalized-minor-mode)
                  (mapc #'walk (nthcdr 3 form)))
                 ((or 'lambda 'closure)
                  (mapc #'walk (nthcdr 2 form)))
                 ((or 'let 'let*)
                  (dolist (binding (nth 1 form))
                    (when (consp binding)
                      (mapc #'walk (cdr binding))))
                  (mapc #'walk (nthcdr 2 form)))
                 ((or 'cl-labels 'cl-flet)
                  (dolist (binding (nth 1 form))
                    (when (consp binding)
                      (mapc #'walk (cddr binding))))
                  (mapc #'walk (nthcdr 2 form)))
                 (_
                  (mapc #'walk (cdr form)))))))))
      (mapc #'walk forms))
    (delete-dups calls)))

(defun gptel-auto-experiment--introduced-undefined-call (diff forms)
  "Return the first newly-added function call in DIFF not defined by runtime.

Only added diff lines are inspected to avoid rejecting pre-existing split-module
forward references.  FORMS are the parsed top-level forms from the full file and
are used to recognize local definitions and `declare-function' declarations."
  (let* ((local-defs (gptel-auto-experiment--defined-function-symbols forms))
         (actual-calls (gptel-auto-experiment--call-symbols-in-forms forms))
         (calls nil))
    (dolist (line (gptel-auto-experiment--diff-added-lines diff))
      (setq calls (append (gptel-auto-experiment--call-symbols-in-line line)
                          calls)))
    (cl-find-if
     (lambda (symbol)
       (and (memq symbol actual-calls)
            (not (gptel-auto-experiment--defined-runtime-call-p symbol local-defs))))
     (delete-dups (nreverse calls)))))

(defun gptel-auto-experiment--validate-code (file)
  "Validate code in FILE for syntax and dangerous patterns.
Returns nil if valid, or error message string if invalid."
  (when (and (stringp file) (string-suffix-p ".el" file))
    (if (not (file-exists-p file))
        (format "Missing target file: %s" file)
      (let ((content (gptel-auto-workflow--read-file-contents file))
            forms)
        (or (cond
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
            (let* ((parsed-forms (nreverse forms))
                   (diff (gptel-auto-experiment--diff-against-head file))
                   (undefined-call
                    (gptel-auto-experiment--introduced-undefined-call
                     diff parsed-forms)))
              (or
               (when (gptel-auto-experiment--invalid-cl-return-target-in-forms
                      parsed-forms)
                 (format "Dangerous pattern in %s: cl-return-from without cl-block" file))
               (when undefined-call
                 (format "Undefined function introduced in %s: %S" file undefined-call))
               (when (gptel-auto-experiment--defensive-code-removal-p diff)
                 (format "Defensive code removal detected in %s: removing or/assoc fallbacks without proof" file)))))))))

(provide 'gptel-tools-agent-validation)
;;; gptel-tools-agent-validation.el ends here
