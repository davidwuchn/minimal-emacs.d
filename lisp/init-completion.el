;;; init-completion.el --- Minibuffer and in-buffer completion -*- lexical-binding: t; -*-

(provide 'init-completion)

(use-package vertico
  :ensure t
  :config
  (vertico-mode))

(use-package orderless
  :ensure t
  :custom
  (completion-styles '(orderless basic))
  (completion-category-defaults nil)
  (completion-category-overrides
   '((file (styles partial-completion))
     (path (styles partial-completion))
     (buffer (styles partial-completion orderless))
     (command (styles orderless))
     (variable (styles orderless))
     (symbol (styles orderless)))))

(use-package marginalia
  :ensure t
  :hook (after-init . marginalia-mode))

(use-package embark
  :ensure t
  :bind
  (("C-." . embark-act)
   ("C-;" . embark-dwim)
   ("C-h B" . embark-bindings)
   ("C-h C" . embark-act))  ; Alternative binding for embark-act
  :init
  (setq prefix-help-command #'embark-prefix-help-command)
  (setq embark-cycle-key (kbd "."))  ; Cycle through candidates with '.'
  :config
  ;; Hide mode line in Embark collect buffers
  (add-to-list 'display-buffer-alist
               '("\\`\\*Embark Collect \\(Live\\|Completions\\)\\*"
                 nil
                 (window-parameters (mode-line-format . none))))
  ;; Make Embark act like a more powerful `M-x`
  (define-key minibuffer-local-map (kbd "C-.") #'embark-act)
  ;; Export Embark keymap to Occur mode
  (add-hook 'occur-mode-hook
            (lambda ()
              (define-key occur-mode-map (kbd "C-.") #'embark-act))))

(use-package embark-consult
  :ensure t
  :hook
  (embark-collect-mode . consult-preview-at-point-mode))

(use-package consult
  :ensure t
  :bind (("C-c M-x" . consult-mode-command)
         ("C-c h" . consult-history)
         ("C-x b" . consult-buffer)
         ("M-y" . consult-yank-pop)
         ("M-g g" . consult-goto-line)
         ("M-g i" . consult-imenu)
         ("M-s d" . consult-find)
         ("M-s r" . consult-ripgrep)
         ("M-s l" . consult-line))
  :hook (completion-list-mode . consult-preview-at-point-mode)
  :init
  (setq xref-show-xrefs-function #'consult-xref
        xref-show-definitions-function #'consult-xref)
  :config
  (consult-customize
   consult-theme :preview-key '(:debounce 0.2 any)
   consult-ripgrep consult-git-grep consult-grep
   consult-bookmark consult-recent-file consult-xref
   consult-source-bookmark consult-source-file-register
   consult-source-recent-file consult-source-project-recent-file
   :preview-key '(:debounce 0.4 any))
  (setq consult-narrow-key "<"))

(use-package corfu
  :ensure t
  :hook ((prog-mode . corfu-mode)
         (text-mode . corfu-mode)
         (shell-mode . corfu-mode)
         (eshell-mode . corfu-mode))
  :custom
  (corfu-auto t)
  (corfu-auto-delay 0.0)
  (corfu-auto-prefix 1)
  (corfu-cycle t)
  (corfu-preselect 'prompt)
  (read-extended-command-predicate #'command-completion-default-include-p)
  (text-mode-ispell-word-completion nil)
  (tab-always-indent 'complete)
  :config
  ;; Magic slash for file paths: insert candidate and trigger completion again
  (defun my/corfu-insert-slash ()
    "Insert a slash or expand the current directory."
    (interactive)
    (let ((cand (and (>= corfu--index 0)
                     (nth corfu--index corfu--candidates))))
      (if (and cand (string-suffix-p "/" cand))
          (progn
            (corfu-insert)
            ;; Re-trigger completion immediately for the next directory level
            (run-at-time 0.0 nil #'completion-at-point))
        (insert "/"))))
  (define-key corfu-map (kbd "/") #'my/corfu-insert-slash))

;; Enable Corfu popup in terminal Emacs (required for Emacs < 31)
(use-package corfu-terminal
  :ensure t
  :unless (display-graphic-p)
  :after corfu
  :config
  (corfu-terminal-mode 1))

(use-package cape
  :ensure t
  :bind ("C-c p" . cape-prefix-map)
  :init
  ;; Add Cape completion backends in order of priority
  (add-hook 'completion-at-point-functions #'cape-dabbrev)
  (add-hook 'completion-at-point-functions #'cape-file)
  (add-hook 'completion-at-point-functions #'cape-elisp-block)
  (add-hook 'completion-at-point-functions #'cape-keyword)
  (add-hook 'completion-at-point-functions #'cape-symbol)
  (add-hook 'completion-at-point-functions #'cape-dict)
  (add-hook 'completion-at-point-functions #'cape-line))

(use-package tempel
  :ensure t
  :bind (("M-+" . tempel-complete) 
         ("M-*" . tempel-insert))
  :init
  (defun tempel-setup-capf ()
    (setq-local completion-at-point-functions
                (cons #'tempel-expand completion-at-point-functions)))
  (add-hook 'prog-mode-hook 'tempel-setup-capf)
  (add-hook 'text-mode-hook 'tempel-setup-capf))
