;;; init-treesit.el --- Tree-sitter auto configuration -*- no-byte-compile: t; lexical-binding: t; -*-

(require 'treesit-auto)

;; Languages to enable. This filters treesit-auto-recipe-list.
(setq treesit-auto-langs '(python rust clojure elisp java c cpp lua json javascript go yaml dockerfile bash))

;; Custom recipes with ABI14 revisions for Emacs 30 compatibility where known.
;; Each entry: (lang ts-mode remap-list url ext &optional abi14-revision revision source-dir)
(dolist (spec '((python     python-ts-mode      (python-mode)
                "https://github.com/tree-sitter/tree-sitter-python"
                "\\.py\\'" "v0.21.0")

               (rust       rust-ts-mode         (rust-mode)
                "https://github.com/tree-sitter/tree-sitter-rust"
                "\\.rs\\'" "v0.21.0")

               (clojure    clojure-ts-mode      (clojure-mode)
                "https://github.com/sogaiu/tree-sitter-clojure"
                "\\.clj\\'")

               (elisp      emacs-lisp-ts-mode   (emacs-lisp-mode)
                "https://github.com/Wilfred/tree-sitter-elisp"
                "\\.el\\'" "1.2")

               (java       java-ts-mode         (java-mode)
                "https://github.com/tree-sitter/tree-sitter-java"
                "\\.java\\'")

               (c          c-ts-mode            (c-mode)
                "https://github.com/tree-sitter/tree-sitter-c"
                "\\.c\\'" "v0.21.4")

               (cpp        c++-ts-mode          (c++-mode)
                "https://github.com/tree-sitter/tree-sitter-cpp"
                "\\.cpp\\'" "v0.22.3")

               (lua        lua-ts-mode          (lua-mode)
                "https://github.com/tree-sitter-grammars/tree-sitter-lua"
                "\\.lua\\'" "v0.2.0")

               (json       json-ts-mode         (js-json-mode)
                "https://github.com/tree-sitter/tree-sitter-json"
                "\\.json\\'" "v0.24.8")

               (go         go-ts-mode           (go-mode)
                "https://github.com/tree-sitter/tree-sitter-go"
                "\\.go\\'" "v0.21.0")

               (yaml       yaml-ts-mode         (yaml-mode)
                "https://github.com/ikatyang/tree-sitter-yaml"
                "\\.ya\\?ml\\'")

               (dockerfile dockerfile-ts-mode    (dockerfile-mode)
                "https://github.com/camdencheek/tree-sitter-dockerfile"
                "Dockerfile\\'" "v0.1.2")

               (bash       bash-ts-mode         (sh-mode bash-ts-mode)
                "https://github.com/tree-sitter/tree-sitter-bash"
                "\\.sh\\'\\|\\.bash\\'" "v0.21.0")

               (javascript js-ts-mode           (js-mode javascript-mode js2-mode)
                "https://github.com/tree-sitter/tree-sitter-javascript"
                "\\.js\\'" "v0.21.0" nil "src")))
  (let ((lang           (nth 0 spec))
        (ts-mode        (nth 1 spec))
        (remap          (nth 2 spec))
        (url            (nth 3 spec))
        (ext            (nth 4 spec))
        (abi14-revision (nth 5 spec))
        (revision       (nth 6 spec))
        (source-dir     (nth 7 spec)))
    ;; Remove any existing recipe for this lang to avoid duplicates
    (setq treesit-auto-recipe-list
          (seq-remove (lambda (r) (eq (treesit-auto-recipe-lang r) lang))
                      treesit-auto-recipe-list))
    (add-to-list 'treesit-auto-recipe-list
                 (make-treesit-auto-recipe
                  :lang lang
                  :ts-mode ts-mode
                  :remap remap
                  :url url
                  :ext ext
                  :abi14-revision abi14-revision
                  :revision revision
                  :source-dir source-dir))))

(setq treesit-auto-install 'auto)
(treesit-auto-add-to-auto-mode-alist 'all)
(global-treesit-auto-mode)

(provide 'init-treesit)
