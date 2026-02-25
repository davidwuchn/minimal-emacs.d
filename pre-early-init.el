;;; pre-early-init.el --- Pre-early init customizations -*- no-byte-compile: t; lexical-binding: t; -*-

;; Disable UI bloat to speed up startup
(setq minimal-emacs-ui-features nil)

;; Reducing clutter in ~/.emacs.d by redirecting files to ~/.emacs.d/var/
;; NOTE: This must be placed in 'pre-early-init.el'.
(setq user-emacs-directory (expand-file-name "var/" minimal-emacs-user-directory))
(setq package-user-dir (expand-file-name "elpa" user-emacs-directory))
