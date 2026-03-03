;;; init-treesit.el --- Tree-sitter auto configuration -*- lexical-binding: t; -*-

(require 'treesit-auto)

(setq treesit-auto-langs '(python rust clojure elisp java c cpp))

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

(setq my/java-tsauto-config
      (make-treesit-auto-recipe
       :lang 'java
       :ts-mode 'java-ts-mode
       :remap '(java-mode)
       :url "https://github.com/tree-sitter/tree-sitter-java"
       :revision "master"
       :ext "\\.java\\'"))

(add-to-list 'treesit-auto-recipe-list my/java-tsauto-config)

(setq my/c-tsauto-config
      (make-treesit-auto-recipe
       :lang 'c
       :ts-mode 'c-ts-mode
       :remap '(c-mode)
       :url "https://github.com/tree-sitter/tree-sitter-c"
       :revision "master"
       :abi14-revision "v0.21.4"
       :ext "\\.c\\'"))

(add-to-list 'treesit-auto-recipe-list my/c-tsauto-config)

(setq my/cpp-tsauto-config
      (make-treesit-auto-recipe
       :lang 'cpp
       :ts-mode 'c++-ts-mode
       :remap '(c++-mode)
       :url "https://github.com/tree-sitter/tree-sitter-cpp"
       :revision "master"
       :abi14-revision "v0.22.3"
       :ext "\\.cpp\\'"))

(add-to-list 'treesit-auto-recipe-list my/cpp-tsauto-config)

(setq treesit-auto-install 'auto)
(treesit-auto-add-to-auto-mode-alist 'all)
(global-treesit-auto-mode)

(provide 'init-treesit)
