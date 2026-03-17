;;; Directory Local Variables
;;; For more information see (info "(emacs) Directory Variables")

((emacs-lisp-mode
  . ((indent-tabs-mode . nil)
     (fill-column . 100)
     (sentence-end-double-space . t)
     (emacs-lisp-docstring-fill-column . fill-column)
     (checkdoc-force-docstrings-flag . nil)
     (byte-compile-warnings . (not free-vars unresolved noruntime lexical make-local))
     (flymake-mode . t)
     (eval . (add-hook 'before-save-hook #'copyright-update nil t)))))

;;; .dir-locals.el ends here