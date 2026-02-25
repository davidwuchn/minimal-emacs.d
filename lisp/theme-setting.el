;;; theme-setting.el --- User Visual and Theme Customizations -*- lexical-binding: t; -*-

(provide 'theme-setting)

;; You will most likely need to adjust this font size for your system!
(defvar efs/default-font-size 180)
(defvar efs/default-variable-font-size 180)

;; Make frame transparency overridable
(defvar efs/frame-transparency '(90 . 90))

(set-face-attribute 'default nil :font "FiraCode Nerd Font" :height efs/default-font-size)

;; Set the fixed pitch face
(set-face-attribute 'fixed-pitch nil :font "FiraCode Nerd Font" :height efs/default-font-size)

;; Set the variable pitch face
(set-face-attribute 'variable-pitch nil :font "Cantarell" :height efs/default-variable-font-size :weight 'regular)

;; Set frame transparency
(set-frame-parameter (selected-frame) 'alpha efs/frame-transparency)
(add-to-list 'default-frame-alist `(alpha . ,efs/frame-transparency))
(set-frame-parameter (selected-frame) 'fullscreen 'maximized)
(add-to-list 'default-frame-alist '(fullscreen . maximized))

;; Disable line numbers for some modes
(dolist (mode '(org-mode-hook
                term-mode-hook
                shell-mode-hook
                treemacs-mode-hook
                eshell-mode-hook))
  (add-hook mode (lambda () (display-line-numbers-mode 0))))

;; Disable built-in themes first
(mapc #'disable-theme custom-enabled-themes)

;; Modus themes ship with recent Emacs versions.
(require 'modus-themes nil t)

;; Add all your customizations prior to loading the themes.
;; Configure the Modus Themes' appearance
(setq modus-themes-mode-line '(accented borderless)
      modus-themes-bold-constructs t
      modus-themes-italic-constructs t
      modus-themes-fringes 'subtle
      modus-themes-tabs-accented t
      modus-themes-paren-match '(bold intense)
      modus-themes-prompts '(bold intense)
      ;; The `modus-themes-completions' is an alist that reads two
      ;; keys: `matches', `selection'.
      modus-themes-completions
      '((matches . (extrabold))
        (selection . (semibold italic text-also)))

      modus-themes-org-blocks 'tinted-background
      modus-themes-scale-headings t
      modus-themes-region '(bg-only)
      modus-themes-headings
      '((1 . (rainbow overline background 1.4))
        (2 . (rainbow background 1.3))
        (3 . (rainbow bold 1.2))
        (t . (semilight 1.1))))

;; Load the theme now that variables are set
(load-theme 'modus-vivendi t)

;; Optional overrides (must be run after theme is loaded)
(with-eval-after-load 'modus-vivendi-theme
  (set-face-background 'default "grey15")
  (set-face-attribute 'region nil :background "#666"))

;; No title bar
(add-to-list 'default-frame-alist '(undecorated . t))
