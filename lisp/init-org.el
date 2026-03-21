;;; init-org.el --- Org mode configuration -*- no-byte-compile: t; lexical-binding: t; -*-

;;; Commentary:
;; Comprehensive Org mode configuration including:
;; - Core Org settings (agenda, capture, refile)
;; - Org appearance (org-appear, org-modern)
;; - Org super agenda for better task management
;; - Org roam for networked note-taking
;; - Org pomodoro for time management
;; - Org download for image handling
;; - Export enhancements (ox-gfm, ox-pandoc)
;; - Org query language (org-ql)
;; - Unified folding (kirigami)

;;; Code:

(provide 'init-org)

;; ==============================================================================
;; ORG MODE CORE
;; ==============================================================================

(use-package org
  :ensure nil  ; Built-in
  :hook (org-mode . (lambda () (display-line-numbers-mode -1)))
  :bind (("C-c C-a" . org-agenda)
         ("C-c c" . org-capture)
         ("C-c l" . org-store-link)
         ("C-c o" . org-open-at-point))
  :custom
  ;; Org file locations
  (org-directory "~/org/")
  (org-default-notes-file "~/org/notes.org")
  (org-agenda-files '("~/org/agenda.org"
                      "~/org/projects.org"
                      "~/org/notes.org"))
  
  ;; Todo keywords
  (org-todo-keywords
   '((sequence "TODO(t)" "INPROGRESS(i)" "WAITING(w@/!)" "|" "DONE(d@)" "CANCELLED(c@)")
     (sequence "PROJECT(p)" "|" "COMPLETED(x)")
     (sequence "MEETING(m)" "|" "HELD(h)")))
  
  ;; Todo colors
  (org-todo-keyword-faces
   '(("TODO" . (:foreground "#ff6b6b" :weight bold))
     ("INPROGRESS" . (:foreground "#4ecdc4" :weight bold))
     ("WAITING" . (:foreground "#ffe66d" :weight bold))
     ("DONE" . (:foreground "#95e1d3" :weight bold :strike-through t))
     ("CANCELLED" . (:foreground "#6c757d" :weight bold :strike-through t))
     ("PROJECT" . (:foreground "#a855f7" :weight bold))
     ("MEETING" . (:foreground "#f97316" :weight bold))))
  
  ;; Agenda settings
  (org-agenda-start-with-log-mode t)
  (org-agenda-span 'day)
  (org-agenda-start-day nil)
  (org-agenda-time-grid
   '((daily today require-timed)
     (800 900 1000 1100 1200 1300 1400 1500 1600 1700 1800 1900 2000)))
  
  ;; Capture templates
  (org-capture-templates
   '(("t" "Todo" entry (file+headline "~/org/agenda.org" "Tasks")
      "* TODO %?\n  %U\n  %a\n  :PROPERTIES:\n  :CREATED: %U\n  :END:\n  "
      :empty-lines 1)
     ("n" "Note" entry (file+headline "~/org/notes.org" "Notes")
      "* %?\n  %U\n  %a\n  "
      :empty-lines 1)
     ("j" "Journal" entry (file+datetree "~/org/journal.org")
      "* %?\nEntered on %U\n  %i\n  %a"
      :empty-lines 1)
     ("m" "Meeting" entry (file+headline "~/org/notes.org" "Meetings")
      "* MEETING %?\n  %U\n  Attendees: \n  Agenda:\n  \n  Notes:\n  \n  Action Items:\n  "
      :empty-lines 1)
     ("p" "Project" entry (file+headline "~/org/projects.org" "Projects")
      "* PROJECT %?\n  %U\n  Status: PLANNING\n  Deadline: \n  "
      :empty-lines 1)))
  
  ;; Refile settings
  (org-refile-use-outline-path 'file)
  (org-outline-path-complete-in-steps t)
  (org-refile-allow-creating-parent-nodes 'confirm)
  (org-refile-targets '((org-agenda-files :maxlevel . 3)))
  
  ;; Export settings
  (org-export-with-toc t)
  (org-export-with-section-numbers t)
  (org-export-with-smart-quotes t)
  (org-export-with-drawers nil)
  (org-export-with-sub-superscripts '{}))

;; ==============================================================================
;; ORG BULLETS (Pretty bullets)
;; ==============================================================================

(use-package org-bullets
  :ensure t
  :hook (org-mode . org-bullets-mode))

;; ==============================================================================
;; ORG APPEARANCE (Reveal markup at cursor)
;; ==============================================================================

(use-package org-appear
  :ensure t
  :hook (org-mode . org-appear-mode)
  :config
  (setq org-appear-autoemphasis t)
  (setq org-appear-autolinks t)
  (setq org-appear-autosubmarkers t)
  (setq org-appear-autokeywords t))

;; ==============================================================================
;; ORG SUPER AGENDA (Better agenda grouping)
;; ==============================================================================

(use-package org-super-agenda
  :ensure t
  :after org-agenda
  :init
  (org-super-agenda-mode 1)
  :config
  (setq org-super-agenda-groups
        '((:name "🔴 Today"
           :time-grid t
           :date today
           :scheduled today
           :order 1)
          (:name "🟡 Overdue"
           :deadline past
           :scheduled past
           :order 2)
          (:name "🟢 Next"
           :todo "NEXT"
           :order 3)
          (:name "🔵 In Progress"
           :todo "INPROGRESS"
           :order 4)
          (:name "🟣 High Priority"
           :priority "A"
           :order 5)
          (:name "🟠 Medium Priority"
           :priority "B"
           :order 6)
          (:name "⚪ Low Priority"
           :priority "C"
           :order 7)
          (:name "📋 Projects"
           :todo "PROJECT"
           :order 8)
          (:name "⏳ Waiting"
           :todo "WAITING"
           :order 9)
          (:name "📝 Tasks"
           :todo "TODO"
           :order 10))))

;; ==============================================================================
;; ORG ROAM (Networked note-taking)
;; ==============================================================================

(use-package org-roam
  :ensure t
  :init
  (setq org-roam-v2-ack t)
  :config
  (setq org-roam-directory (file-truename "~/org/roam/"))
  (setq org-roam-dailies-directory "daily/")
  (setq org-roam-completion-everywhere t)
  (setq org-roam-capture-templates
        '(("d" "default" plain
           "%?"
           :if-new (file+head "%<%Y%m%d%H%M%S>-${slug}.org"
                              "#+title: ${title}\n#+date: %U\n#+filetags: \n\n")
           :unnarrowed t)))
  (org-roam-db-autosync-mode 1)
  (org-roam-setup)
  :bind (("C-c n l" . org-roam-buffer-toggle)
         ("C-c n f" . org-roam-node-find)
         ("C-c n g" . org-roam-graph)
         ("C-c n i" . org-roam-node-insert)
         ("C-c n c" . org-roam-capture)
         ("C-c n j" . org-roam-dailies-capture-today)))

;; ==============================================================================
;; ORG POMODORO (Time management)
;; ==============================================================================

(use-package org-pomodoro
  :ensure t
  :after org
  :bind (:map org-mode-map
              ("C-c P" . org-pomodoro)))

;; ==============================================================================
;; ORG DOWNLOAD (Image handling)
;; ==============================================================================

(use-package org-download
  :ensure t
  :hook (org-mode . org-download-enable)
  :config
  (setq org-download-image-dir "~/org/images/")
  (setq org-download-image-org-width 600)
  (setq org-download-screenshot-method "screencapture -i %s"))

;; ==============================================================================
;; ORG ATTACH (File attachments)
;; ==============================================================================

(use-package org-attach
  :ensure nil  ; Built-in with Org
  :after org
  :bind (:map org-mode-map
              ("C-c C-z" . org-attach))  ; Use C-c C-z to avoid conflict with org-agenda
  :config
  (setq org-attach-dir "~/org/attachments/")
  (setq org-attach-id-dir "~/org/attachments/.id/")
  (setq org-attach-auto-tag "ATTACH"))

;; ==============================================================================
;; ORG MODERN (Visual enhancements)
;; ==============================================================================

(use-package org-modern
  :ensure t
  :hook (org-mode . org-modern-mode)
  :config
  (add-hook 'org-agenda-finalize-hook #'org-modern-agenda)
  (setq org-modern-table-vertical 0.2)
  (setq org-modern-table-horizontal 0.2)
  (setq org-modern-priority-default "◎")
  (setq org-modern-priority-low "○")
  (setq org-modern-priority-high "●"))

;; ==============================================================================
;; ORG EXPORT (Reveal.js presentations)
;; ==============================================================================

(use-package ox-reveal
  :ensure t
  :after ox)

;; ==============================================================================
;; ORG EXPORT ENHANCEMENTS (Optional but recommended)
;; ==============================================================================

;; Export to GitHub Flavored Markdown
(use-package ox-gfm
  :ensure t
  :after ox)

;; Export to many formats via Pandoc (PDF, DOCX, ePub, etc.)
(use-package ox-pandoc
  :ensure t
  :after ox)

;; ==============================================================================
;; ORG QUERY LANGUAGE (Better search and filtering)
;; ==============================================================================

;; Powerful query language for Org files (better than built-in search)
(use-package org-ql
  :ensure t
  :after org
  :bind (:map org-agenda-mode-map
              ("s" . org-ql-search)
              ("S" . org-ql-view))
  :config
  ;; Quick access to common queries
  (defun my/org-ql-today ()
    "Show tasks scheduled for today."
    (interactive)
    (org-ql-search (org-agenda-files)
      '(or (scheduled today)
           (deadline today))
      :title "Today")))

;; ==============================================================================
;; KIRIGAMI (Unified folding interface - Recommended in README)
;; ==============================================================================

;; Unified fold/unfold interface across many modes including org-mode
(use-package kirigami
  :ensure t
  :bind
  (:map org-mode-map
        ("C-c f o" . kirigami-open-fold)
        ("C-c f c" . kirigami-close-fold)
        ("C-c f t" . kirigami-toggle-fold)
        ("C-c f O" . kirigami-open-folds)
        ("C-c f C" . kirigami-close-folds)))

;; ==============================================================================
;; ORG TRANSCCLUSION (Optional - Embed content from other files)
;; ==============================================================================

;; Transclude (embed) content from other Org files/buffers
(use-package org-transclusion
  :ensure t
  :after org
  :hook (org-mode . org-transclusion-mode)
  :bind (:map org-mode-map
              ("C-c C-t" . org-transclusion-add)
              ("C-c C-e" . org-transclusion-extract)))

;;; init-org.el ends here
