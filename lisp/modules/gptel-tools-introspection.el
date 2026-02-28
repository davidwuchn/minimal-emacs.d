;;; gptel-tools-introspection.el --- Introspection tools for gptel -*- lexical-binding: t; -*-

;; Author: David Wu
;; Version: 1.0.0
;;
;; Emacs introspection tools for gptel-agent.

(require 'cl-lib)
(require 'subr-x)
(require 'find-func)

;;; Customization

(defgroup gptel-tools-introspection nil
  "Introspection tools for gptel-agent."
  :group 'gptel)

;;; Helper Functions

(defun my/gptel--describe-symbol (name)
  "Return the documentation and current value for the given symbol NAME."
  (let* ((sym (intern-soft name))
         (out ""))
    (unless sym
      (error "Symbol not found: %s" name))
    (when (fboundp sym)
      (setq out (concat out (format "Function: %s\n%s\n\n" sym (or (documentation sym t) "No documentation.")))))
    (when (boundp sym)
      (setq out (concat out (format "Variable: %s\nValue: %S\n%s\n\n"
                                    sym (symbol-value sym)
                                    (or (documentation-property sym 'variable-documentation t)
                                        "No documentation.")))))
    (when (featurep sym)
      (setq out (concat out (format "Feature: %s is loaded.\n\n" sym))))
    (when (facep sym)
      (setq out (concat out (format "Face: %s\n%s\n\n" sym (or (face-documentation sym) "No documentation.")))))
    (if (string-empty-p out)
        (format "Symbol %s exists but is not bound to a function, variable, feature, or face." sym)
      (string-trim out))))

(defun my/gptel--get-symbol-source (name)
  "Return the source code for the given symbol NAME."
  (let* ((sym (intern-soft name))
         (result nil))
    (unless sym
      (error "Symbol not found: %s" name))
    (condition-case err
        (let* ((loc (or (ignore-errors (find-function-search-for-symbol sym nil (symbol-file sym 'defun)))
                        (ignore-errors (find-function-search-for-symbol sym 'defvar (symbol-file sym 'defvar)))))
               (buf (car loc))
               (pos (cdr loc)))
          (if (and buf pos)
              (with-current-buffer buf
                (save-excursion
                  (goto-char pos)
                  (let ((start (point))
                        (end (progn (forward-sexp 1) (point))))
                    (setq result (buffer-substring-no-properties start end)))))
            (error "Source not found for %s" name)))
      (error (setq result (format "Error retrieving source: %s" (error-message-string err)))))
    result))

(defun my/gptel--find-buffers-and-recent (pattern)
  "Find open buffers and recently opened files matching PATTERN."
  (let* ((pattern (if (string-empty-p pattern) "." pattern))
         (bufs (delq nil (mapcar (lambda (b)
                                   (let ((name (buffer-name b)) (file (buffer-file-name b)))
                                     (when (and (not (string-prefix-p " " name))
                                                (or (string-match-p pattern name)
                                                    (and file (string-match-p pattern file))))
                                       (format "  %s%s (%s)" name (if (buffer-modified-p b) "*" "") (or file "")))))
                                 (buffer-list))))
         (recs (progn (recentf-mode 1)
                      (seq-filter (lambda (f) (string-match-p pattern (file-name-nondirectory f))) recentf-list))))
    (concat (when bufs (format "Open Buffers:\n%s\n\n" (string-join bufs "\n")))
            (when recs (format "Recent Files:\n%s" (string-join (mapcar (lambda (f) (format "  %s" f)) recs) "\n"))))))

;;; Tool Registration

(defun gptel-tools-introspection-register ()
  "Register introspection tools with gptel."
  (when (fboundp 'gptel-make-tool)
    ;; describe_symbol
    (gptel-make-tool
     :name "describe_symbol"
     :description "Get the documentation string and current value of an Emacs symbol (function, variable, face, or feature)."
     :function #'my/gptel--describe-symbol
     :args '((:name "name" :type string :description "The exact name of the symbol to look up"))
     :category "gptel-agent"
     :confirm nil
     :include t)

    ;; get_symbol_source
    (gptel-make-tool
     :name "get_symbol_source"
     :description "Get the actual elisp source code definition of a function or variable."
     :function #'my/gptel--get-symbol-source
     :args '((:name "name" :type string :description "The exact name of the symbol"))
     :category "gptel-agent"
     :confirm nil
     :include t)

    ;; find_buffers_and_recent
    (gptel-make-tool
     :name "find_buffers_and_recent"
     :description "List currently open buffers and recently accessed file paths matching a pattern."
     :function #'my/gptel--find-buffers-and-recent
     :args (list '(:name "pattern" :type string :description "Regex pattern to match against buffer/file names"))
     :category "gptel-agent"
     :confirm nil
     :include t)))

;;; Footer

(provide 'gptel-tools-introspection)

;;; gptel-tools-introspection.el ends here
