;;; init-dev.el --- Programming, LSP, Clojure, Elisp -*- lexical-binding: t; -*-

;; Add lisp directory to load-path for modular config
(add-to-list 'load-path (file-name-directory load-file-name))

(provide 'init-dev)

;; Markdown
(use-package markdown-mode
  :ensure t
  :commands (markdown-mode gfm-mode)
  :mode (("\\.markdown\\'" . markdown-mode)
         ("\\.md\\'" . markdown-mode)
         ("README\\.md\\'" . gfm-mode)))

(use-package dumb-jump
  :ensure t
  :commands dumb-jump-xref-activate
  :init
  (add-hook 'xref-backend-functions #'dumb-jump-xref-activate 90))

(use-package treesit-local-xref
  :ensure nil
  :commands (treesit-local-xref-backend)
  :init
  (add-hook 'xref-backend-functions #'treesit-local-xref-backend 50))

(use-package treesit-agent-tools
  :ensure nil
  :commands (treesit-agent-get-file-map
             treesit-agent-extract-node
             treesit-agent-replace-node))

;; Tree-sitter auto configuration with custom recipes
(require 'init-treesit)

(use-package apheleia
  :ensure t
  :hook ((prog-mode . apheleia-mode)))

(use-package clojure-mode
  :ensure t
  :mode "\\.clj\\'")

(use-package cider
  :ensure t
  :hook ((clojure-mode . cider-mode)
         (cider-mode . eldoc-mode)
         (cider-repl-mode . eldoc-mode))
  :custom
  (cider-repl-display-help-banner nil)
  (cider-repl-pop-to-buffer-on-connect 'display-only))

(use-package paredit
  :ensure t
  :hook ((emacs-lisp-mode . paredit-mode)
         (eval-expression-minibuffer-setup . paredit-mode)
         (ielm-mode . paredit-mode)
         (lisp-mode . paredit-mode)
         (lisp-interaction-mode . paredit-mode)
         (scheme-mode . paredit-mode)
         (clojure-mode . paredit-mode)
         (cider-repl-mode . paredit-mode)))

(use-package enhanced-evil-paredit
  :ensure t
  :hook (paredit-mode . enhanced-evil-paredit-mode))

;; eglot (LSP)
(use-package eglot
  :ensure nil
  :commands (eglot-ensure eglot-rename eglot-format-buffer)
  :hook ((clojure-mode . eglot-ensure))
  :custom
  (eglot-ignored-server-capabilities '(:documentHighlightProvider)))
