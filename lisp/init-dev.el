;;; init-dev.el --- Programming, LSP, Clojure, Elisp -*- no-byte-compile: t; lexical-binding: t; -*-

;; Add lisp/ and lisp/modules/ to load-path for both load and byte-compile time.
(eval-and-compile
  (let* ((source-dir (and load-file-name
                          (file-name-directory load-file-name)))
         (base-dir (or (and (boundp 'minimal-emacs-user-directory)
                            minimal-emacs-user-directory)
                       (and source-dir
                            (if (string= (file-name-nondirectory
                                          (directory-file-name source-dir))
                                         "lisp")
                                (file-name-directory
                                 (directory-file-name source-dir))
                              source-dir))
                       default-directory))
         (lisp-dir (expand-file-name "lisp" base-dir))
         (modules-dir (expand-file-name "lisp/modules" base-dir)))
    (add-to-list 'load-path (file-truename lisp-dir))
    (add-to-list 'load-path (file-truename modules-dir))))

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
  :commands (apheleia-mode apheleia-global-mode)
  :hook ((prog-mode . (lambda ()
                        (when (require 'apheleia nil t)
                          (apheleia-mode)))))
  :config
  (apheleia-global-mode +1))

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
         (cider-repl-mode . paredit-mode))
  :init
  ;; Paredit rebinds RET to paredit-RET in paredit-mode-map (a minor-mode map),
  ;; which has higher priority than the buffer-local map.  This breaks M-:
  ;; (eval-expression) by inserting a newline instead of confirming.
  ;; Use minor-mode-overriding-map-alist (checked BEFORE minor-mode-map-alist)
  ;; to restore RET without globally mutating paredit-mode-map.
  ;;
  ;; This MUST be in :init, not :config.  :config runs only after paredit.el
  ;; loads (deferred via :hook), so the add-hook wouldn't execute until the
  ;; first M-: triggers paredit autoload — too late for that minibuffer, and
  ;; depending on hook ordering, possibly never effective.  :init runs at
  ;; init time, ensuring the lambda is on the hook before any M-: invocation.
  (add-hook 'eval-expression-minibuffer-setup-hook
            (lambda ()
              (let ((map (make-sparse-keymap)))
                (define-key map (kbd "RET") #'exit-minibuffer)
                (define-key map (kbd "<return>") #'exit-minibuffer)
                (push (cons 'paredit-mode map)
                      minor-mode-overriding-map-alist)))))

(use-package enhanced-evil-paredit
  :ensure t
  :hook (paredit-mode . enhanced-evil-paredit-mode))

;; eglot (LSP)
(use-package eglot
  :ensure nil
  :commands (eglot-ensure eglot-rename eglot-format-buffer)
  :hook ((clojure-mode . eglot-ensure)
         (java-ts-mode . eglot-ensure)
         (c-ts-mode . eglot-ensure)
         (c++-ts-mode . eglot-ensure)
         (lua-ts-mode . eglot-ensure))
  :custom
  (eglot-ignored-server-capabilities '(:documentHighlightProvider)))

;; Python + ty + ruff via rass
(use-package eglot-python-preset
  :vc (:url "https://github.com/mwolson/eglot-python-preset")
  :custom
  (eglot-python-preset-lsp-server 'rass)
  (eglot-python-preset-rass-tools '(ty ruff)))

;; TypeScript/JS + CSS + frameworks (Astro/Vue/Svelte)
(use-package eglot-typescript-preset
  :vc (:url "https://github.com/mwolson/eglot-typescript-preset"))

(provide 'init-dev)
