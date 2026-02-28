;;; post-early-init.el --- Post Early Init -*- lexical-binding: t; -*-

;;; Commentary:
;; This file is loaded after early-init.el but before init.el.
;; Use it for early configuration that must be set before packages are loaded.

;;; Code:

;; Set tree-sitter grammar directory early, before any tree-sitter modes are loaded
(setq treesit-extra-load-path
      (list (expand-file-name "var/tree-sitter/" user-emacs-directory)))

(provide 'post-early-init)

;;; post-early-init.el ends here
