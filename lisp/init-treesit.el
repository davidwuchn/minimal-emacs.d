;;; init-treesit.el --- Tree-sitter auto configuration -*- lexical-binding: t; -*-

(require 'treesit-auto)

(setq treesit-auto-langs '(python rust clojure elisp emacs-lisp))

;; Custom recipes with ABI14 revisions for Emacs 30 compatibility
(setq my/python-tsauto-config
      (make-treesit-auto-recipe
       :lang 'python
       :ts-mode 'python-ts-mode
       :remap '(python-mode)
       :url "https://github.com/tree-sitter/tree-sitter-python"
       :revision "master"
       :abi14-revision "v0.21.0"
       :ext "\\.py\\'"))

(setq my/rust-tsauto-config
      (make-treesit-auto-recipe
       :lang 'rust
       :ts-mode 'rust-ts-mode
       :remap '(rust-mode)
       :url "https://github.com/tree-sitter/tree-sitter-rust"
       :revision "master"
       :abi14-revision "v0.21.0"
       :ext "\\.rs\\'"))

(setq my/clojure-tsauto-config
      (make-treesit-auto-recipe
       :lang 'clojure
       :ts-mode 'clojure-ts-mode
       :remap '(clojure-mode)
       :url "https://github.com/sogaiu/tree-sitter-clojure"
       :revision "master"
       :ext "\\.clj\\'"))

(setq my/elisp-tsauto-config
      (make-treesit-auto-recipe
       :lang 'elisp
       :ts-mode 'emacs-lisp-ts-mode
       :remap '(emacs-lisp-mode)
       :url "https://github.com/Wilfred/tree-sitter-elisp"
       :revision "master"
       :abi14-revision "1.2"
       :ext "\\.el\\'"))

(add-to-list 'treesit-auto-recipe-list my/python-tsauto-config)
(add-to-list 'treesit-auto-recipe-list my/rust-tsauto-config)
(add-to-list 'treesit-auto-recipe-list my/clojure-tsauto-config)
(add-to-list 'treesit-auto-recipe-list my/elisp-tsauto-config)

(setq treesit-auto-install 'prompt)
(treesit-auto-add-to-auto-mode-alist 'all)
(global-treesit-auto-mode)

(provide 'init-treesit)
