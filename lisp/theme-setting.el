;;; theme-setting.el --- User Visual and Theme Customizations -*- lexical-binding: t; -*-

;;; Fonts

(defvar my/default-font-size 180
  "Default height for the `default' and `fixed-pitch' faces.")

(defvar my/default-variable-font-size 180
  "Default height for the `variable-pitch' face.")

(defvar my/fixed-pitch-font "FiraCode Nerd Font"
  "Font family for `default' and `fixed-pitch' faces.")

(defvar my/variable-pitch-font "Cantarell"
  "Font family for the `variable-pitch' face.")

(when (find-font (font-spec :family my/fixed-pitch-font))
  (set-face-attribute 'default nil
                      :font my/fixed-pitch-font
                      :height my/default-font-size)
  (set-face-attribute 'fixed-pitch nil
                      :font my/fixed-pitch-font
                      :height my/default-font-size))

(when (find-font (font-spec :family my/variable-pitch-font))
  (set-face-attribute 'variable-pitch nil
                      :font my/variable-pitch-font
                      :height my/default-variable-font-size
                      :weight 'regular))

;;; Frame

(defvar my/frame-transparency '(90 . 90)
  "Frame transparency as (ACTIVE . INACTIVE) alpha values.")

(set-frame-parameter (selected-frame) 'alpha my/frame-transparency)
(add-to-list 'default-frame-alist `(alpha . ,my/frame-transparency))
(set-frame-parameter (selected-frame) 'fullscreen 'maximized)
(add-to-list 'default-frame-alist '(fullscreen . maximized))

;;; Line numbers

(defun my/disable-line-numbers ()
  "Disable `display-line-numbers-mode' in the current buffer."
  (display-line-numbers-mode 0))

(dolist (hook '(org-mode-hook
                term-mode-hook
                shell-mode-hook
                treemacs-mode-hook
                eshell-mode-hook))
  (add-hook hook #'my/disable-line-numbers))

;;; Modus Themes (v4.x)

;; Forward declarations (suppress byte-compiler free-variable warnings).
(defvar modus-themes-bold-constructs)
(defvar modus-themes-italic-constructs)
(defvar modus-themes-prompts)
(defvar modus-themes-completions)
(defvar modus-themes-headings)
(defvar modus-themes-common-palette-overrides)

;; Disable any previously enabled themes before loading.
(mapc #'disable-theme custom-enabled-themes)

(require 'modus-themes nil t)

;; Configure before loading — only options valid in Modus Themes 4.x.
(setq modus-themes-bold-constructs t
      modus-themes-italic-constructs t
      modus-themes-prompts '(bold italic)
      modus-themes-completions
      '((matches . (extrabold))
        (selection . (semibold italic)))
      modus-themes-headings
      '((1 . (variable-pitch 1.4))
        (2 . (variable-pitch 1.3))
        (3 . (bold 1.2))
        (t . (semilight 1.1))))

;; Palette overrides: custom background and region colors.
;; This replaces the old with-eval-after-load set-face-background hack.
(setq modus-themes-common-palette-overrides
      '((bg-main "#262626")              ; grey15
        (bg-region "#666666")))

(load-theme 'modus-vivendi t)

;;; Header line (clickable for window dragging)

(defvar my/header-line-map
  (let ((map (make-sparse-keymap)))
    (define-key map [header-line mouse-1] #'ignore)
    (define-key map [header-line mouse-2] #'ignore)
    map)
  "Keymap for header-line mouse clicks.")

(setq-default header-line-format
              '(:eval (propertize " " 'local-map my/header-line-map
                                  'mouse-face 'mode-line-highlight)))

(provide 'theme-setting)
;;; theme-setting.el ends here
