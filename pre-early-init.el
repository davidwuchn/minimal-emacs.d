;;; pre-early-init.el --- Pre-early init customizations -*- no-byte-compile: t; lexical-binding: t; -*-

;; Enable debug mode (setq to nil to disable)
(setq minimal-emacs-debug t)

;; Disable UI bloat to speed up startup
(setq minimal-emacs-ui-features nil)

;; Reducing clutter in ~/.emacs.d by redirecting files to ~/.emacs.d/var/
;; NOTE: This must be placed in 'pre-early-init.el'.
(setq user-emacs-directory (expand-file-name "var/" minimal-emacs-user-directory))
(setq package-user-dir (expand-file-name "elpa" user-emacs-directory))

;; Add git submodule packages to load-path
;; These are packages from our forks tracked as submodules in packages/
(dolist (pkg-dir '("gptel" "gptel-agent" "ai-code"))
  (let ((path (expand-file-name (concat "packages/" pkg-dir) minimal-emacs-user-directory)))
    (when (file-directory-p path)
      (add-to-list 'load-path path))))

;; Ensure ELPA transient shadows the built-in version.
;; Newer Magit requires `transient--set-layout' which the built-in
;; transient (Emacs < 30) does not provide.  We must add ALL ELPA
;; package dirs to load-path first because transient depends on
;; cond-let, compat, seq, etc.
(let ((elpa-dirs (and (file-directory-p package-user-dir)
                      (directory-files package-user-dir t "^[^.]"))))
  (dolist (dir elpa-dirs)
    (when (file-directory-p dir)
      (add-to-list 'load-path dir)))
  (let ((elpa-transient-dir
         (car (directory-files package-user-dir t "^transient-[0-9]"))))
    (when elpa-transient-dir
      (when (featurep 'transient)
        (unload-feature 'transient t))
      (load "transient" nil 'nomessage))))

;; Prevent package-refresh-contents network hang on startup.
;; Load archive-contents from cache instead of fetching from network.
(defun my/package-load-archive-cache ()
  "Load package archive contents from cached files without network access.
This prevents startup hangs when melpa.org is slow or unreachable.
Returns non-nil if cache was loaded successfully."
  (let ((archives-dir (expand-file-name "archives" package-user-dir))
        (loaded nil))
    (when (file-directory-p archives-dir)
      (dolist (archive-dir (directory-files archives-dir t "^[^.]"))
        (let ((cache-file (expand-file-name "archive-contents" archive-dir)))
          (when (file-exists-p cache-file)
            (with-temp-buffer
              (condition-case nil
                  (progn
                    (insert-file-contents cache-file)
                    (let ((contents (read (current-buffer))))
                      (when (and (listp contents) (eq (car contents) 1))
                        (dolist (pkg (cdr contents))
                          (when (and (listp pkg) (symbolp (car pkg)))
                            (let ((pkg-name (car pkg)))
                              (unless (assq pkg-name package-archive-contents)
                                (push pkg package-archive-contents)))))
                        (setq loaded t))))
                (error nil))))))
      loaded)))

(defun my/package-skip-network-refresh-p (&optional _async)
  "Return non-nil if package-refresh-contents should skip network access.
Uses cached archives if available and less than 24 hours old."
  (when (and (not package-archive-contents)
             (file-exists-p (expand-file-name "archives/melpa/archive-contents"
                                               package-user-dir)))
    (let ((cache-time (file-attribute-modification-time
                       (file-attributes
                        (expand-file-name "archives/melpa/archive-contents"
                                          package-user-dir))))
          (now (current-time)))
      (when (and cache-time
                 (< (time-to-seconds (time-subtract now cache-time)) 86400))
        (my/package-load-archive-cache)
        package-archive-contents))))

(advice-add 'package-refresh-contents :before-until #'my/package-skip-network-refresh-p)
