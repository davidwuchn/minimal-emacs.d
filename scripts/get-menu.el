(add-to-list 'load-path (expand-file-name "elpa/compat-30.0.1.1/"))
(add-to-list 'load-path (expand-file-name "elpa/seq-2.24/"))
(add-to-list 'load-path (expand-file-name "elpa/cond-let-20260201.1500/"))
(add-to-list 'load-path (expand-file-name "elpa/transient-20260226.1256/"))
(add-to-list 'load-path (expand-file-name "elpa/gptel-20260226.737/"))
(add-to-list 'load-path (expand-file-name "lisp/"))

(require 'transient)
(require 'gptel)
(require 'gptel-transient)

(defun gptel-make-deepseek (&rest args) nil)

;; Set up variables
(setq nucleus-prompts-dir (expand-file-name "assistant/prompts/"))
(setq nucleus-tool-prompts-dir (expand-file-name "assistant/prompts/tools/"))

(load (expand-file-name "lisp/nucleus-config.el") t t)
(load (expand-file-name "lisp/gptel-config.el") t t)

;; Populate directives
(nucleus--register-gptel-directives)

;; Extract from gptel--setup-directive-menu directly
(let ((menu (gptel--setup-directive-menu 'gptel--system-message "Directive" t)))
  (message "Menu items:")
  (dolist (item menu)
    (when (listp item)
      (let ((desc (nth 1 item)))
        (when (stringp desc)
          (message " [%s] %s" (nth 0 item) (substring-no-properties desc)))))))
