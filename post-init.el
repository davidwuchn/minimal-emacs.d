;;; post-init.el --- User configuration -*- no-byte-compile: t; lexical-binding: t; -*-

;; Add the local lisp directory to Emacs' load path
(add-to-list 'load-path (expand-file-name "lisp" user-emacs-directory))

;; Load the modular configuration files
(require 'init-system)
(require 'init-completion)
(require 'init-evil)
(require 'init-dev)
(require 'init-tools)
