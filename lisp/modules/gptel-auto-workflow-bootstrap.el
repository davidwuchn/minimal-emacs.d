;;; gptel-auto-workflow-bootstrap.el --- Headless bootstrap for workflow wrapper -*- lexical-binding: t; -*-

;;; Commentary:

;; Keep the cron wrapper's `emacsclient --eval` payload short and stable.  The
;; wrapper only needs to seed repo-local module paths, reload the workflow
;; modules from the requested worktree, and queue the chosen action.

;;; Code:

(require 'subr-x) ;; for proper-list-p

;; Forward declarations for external variables
(defvar package-gnupghome-dir nil)
(defvar package-archives nil)
(defvar package-archive-priorities nil)
(defvar package-archive-contents nil)
(defvar gptel-backend nil)
(defvar gptel-model nil)
(defconst gptel-auto-workflow-bootstrap--package-archives
  '(("melpa"        . "https://melpa.org/packages/")
    ("gnu"          . "https://elpa.gnu.org/packages/")
    ("nongnu"       . "https://elpa.nongnu.org/nongnu/")
    ("melpa-stable" . "https://stable.melpa.org/packages/"))
  "Package archives used by the headless workflow bootstrap.")

(defconst gptel-auto-workflow-bootstrap--package-archive-priorities
  '(("gnu" . 99)
    ("nongnu" . 80)
    ("melpa" . 70)
    ("melpa-stable" . 50))
  "Package archive priorities used by the headless workflow bootstrap.")

(defconst gptel-auto-workflow-bootstrap--required-packages
  '(yaml magit)
  "Runtime packages that a fresh workflow daemon must be able to load.")

(defun gptel-auto-workflow-bootstrap--elpa-dirs (root)
  "Return package directories under ROOT/var/elpa suitable for `load-path'."
  (let* ((elpa-dir (expand-file-name "var/elpa" root))
         (entries (and (file-directory-p elpa-dir)
                       (directory-files elpa-dir t directory-files-no-dot-files-regexp)))
         dirs)
    (dolist (entry entries (nreverse dirs))
      (when (and (file-directory-p entry)
                 (not (member (file-name-nondirectory entry) '("archives" "gnupg"))))
        (push entry dirs)))))

(defun gptel-auto-workflow-bootstrap--configure-package-system (root)
  "Point `package.el' at ROOT's repo-local package cache and activate it."
  (require 'package)
  (let ((gnupg-dir (expand-file-name "var/elpa/gnupg" root)))
    (setq package-user-dir (expand-file-name "var/elpa" root)
          package-quickstart-file (expand-file-name "var/package-quickstart.el" root)
          package-gnupghome-dir (and (file-directory-p gnupg-dir) gnupg-dir)
          package-archives gptel-auto-workflow-bootstrap--package-archives
          package-archive-priorities
          gptel-auto-workflow-bootstrap--package-archive-priorities))
  (package-initialize))

(defun gptel-auto-workflow-bootstrap--load-package-archive-cache (root)
  "Load cached package archive contents from ROOT without refreshing the network."
  (let ((archives-dir (expand-file-name "var/elpa/archives" root))
        (loaded nil))
    (when (file-directory-p archives-dir)
      (dolist (archive-dir (directory-files archives-dir t directory-files-no-dot-files-regexp))
        (let ((cache-file (expand-file-name "archive-contents" archive-dir)))
          (when (file-exists-p cache-file)
            (with-temp-buffer
              (condition-case err
                  (progn
                    (insert-file-contents cache-file)
                    (let ((contents (read (current-buffer))))
                      (when (and (listp contents) (eq (car contents) 1))
                        (dolist (pkg (cdr contents))
                          (when (and (proper-list-p pkg) (symbolp (car pkg)))
                            (let ((pkg-name (car pkg)))
                              (unless (assq pkg-name package-archive-contents)
                                (push pkg package-archive-contents)))))
                        (setq loaded t))))
                (error
                 (message "Bootstrap: failed to load archive cache %s: %S" cache-file err)
                 nil)))))))
    loaded))

(defun gptel-auto-workflow-bootstrap--ensure-package-installed (root package)
  "Ensure PACKAGE can be loaded for the workflow daemon under ROOT."
  (unless (locate-library (symbol-name package))
    (gptel-auto-workflow-bootstrap--load-package-archive-cache root)
    (unless (assq package package-archive-contents)
      (package-refresh-contents))
    (package-install package)
    (package-initialize)))

(defun gptel-auto-workflow-bootstrap--seed-load-path (root)
  "Add repo-local workflow paths under ROOT to `load-path'."
  (dolist (dir (append (list (expand-file-name "lisp" root)
                             (expand-file-name "lisp/modules" root)
                             (expand-file-name "packages/gptel" root)
                             (expand-file-name "packages/gptel-agent" root)
                             (expand-file-name "packages/ai-code" root))
                        (gptel-auto-workflow-bootstrap--elpa-dirs root)))
    (when (file-directory-p dir)
      (add-to-list 'load-path dir))))

(defun gptel-auto-workflow-bootstrap--known-gptel-load-error-p (err)
  "Return non-nil when ERR matches the fresh-daemon Gptel read error."
  (eq (car-safe err) 'invalid-read-syntax))

(defun gptel-auto-workflow-bootstrap--gptel-ready-p ()
  "Return non-nil when the core Gptel entrypoints are available."
  (and (featurep 'gptel)
       (fboundp 'gptel-send)
       (fboundp 'gptel-request)))

(defun gptel-auto-workflow-bootstrap--load-gptel-core (root)
  "Load the core Gptel stack from ROOT in a fresh worker daemon."
  (let ((load-prefer-newer nil))
    (require 'xdg)
    (condition-case err
        (require 'gptel)
      (error
       (condition-case load-err
           (load-file (expand-file-name "packages/gptel/gptel.elc" root))
         (error
          (unless (and (gptel-auto-workflow-bootstrap--known-gptel-load-error-p load-err)
                       (gptel-auto-workflow-bootstrap--gptel-ready-p))
            (signal (car load-err) (cdr load-err)))))
       (unless (gptel-auto-workflow-bootstrap--gptel-ready-p)
         (signal (car err) (cdr err)))))
    (require 'gptel-request)
    (require 'gptel-agent)
    (require 'gptel-agent-tools)))
(declare-function gptel-auto-workflow-queue-all-instincts "gptel-auto-workflow-projects")
(declare-function gptel-auto-workflow-queue-all-mementum "gptel-auto-workflow-projects")
(declare-function gptel-auto-workflow-queue-all-projects "gptel-auto-workflow-projects")
(declare-function gptel-auto-workflow-queue-all-research "gptel-auto-workflow-projects")

(defun gptel-auto-workflow-bootstrap-run (root action)
  "Bootstrap headless workflow execution from ROOT for ACTION."
  (gptel-auto-workflow-bootstrap--configure-package-system root)
  (gptel-auto-workflow-bootstrap--seed-load-path root)
  (dolist (package gptel-auto-workflow-bootstrap--required-packages)
    (gptel-auto-workflow-bootstrap--ensure-package-installed root package))
  (defvar gptel--tool-preview-alist nil)
  (load-file (expand-file-name "lisp/modules/nucleus-tools.el" root))
  (load-file (expand-file-name "lisp/modules/nucleus-prompts.el" root))
  (load-file (expand-file-name "lisp/modules/nucleus-presets.el" root))
  (gptel-auto-workflow-bootstrap--load-gptel-core root)
  (unless (fboundp 'gptel--format-tool-call)
    (defun gptel--format-tool-call (name arg-values)
      (format "(%s %s)\n"
              (propertize (or name "unknown") 'font-lock-face 'font-lock-keyword-face)
              (propertize (format "%s" arg-values) 'font-lock-face 'font-lock-string-face))))
  (load-file (expand-file-name "lisp/modules/gptel-ext-backends.el" root))
  ;; Smart routing: select first available backend for executor tasks via
  ;; the fallback chain.  Skips rate-limited backends automatically.
  ;; Falls through silently if registry/gptel-get-backend not yet loaded.
  (when (fboundp 'gptel-backend-registry-select-for-task)
    (when-let ((selection (gptel-backend-registry-select-for-task 'executor)))
      (setq gptel-backend (car selection)
            gptel-model (cdr selection))))
  ;; Auto-switch back to MiniMax if the stored quota-reset time has elapsed
  (when (fboundp 'gptel-auto-experiment--check-quota-reset-and-switch-back)
    (gptel-auto-experiment--check-quota-reset-and-switch-back))
  (load-file (expand-file-name "lisp/modules/gptel-tools.el" root))
  (when (fboundp 'gptel-tools-setup)
    (gptel-tools-setup))
  (load-file (expand-file-name "lisp/modules/gptel-tools-agent.el" root))
  (if (fboundp 'nucleus-presets-setup-agents)
      (progn
        ;; Reuse the normal preset refresh path so fresh worker daemons have
        ;; live agent dirs, presets, and tool contracts before worktree
        ;; buffers try to apply the agent preset.
        (nucleus-presets-setup-agents)
        (if (fboundp 'nucleus--after-agent-update)
            (nucleus--after-agent-update)
          (when (fboundp 'nucleus--register-gptel-directives)
            (nucleus--register-gptel-directives))
          (when (fboundp 'nucleus--override-gptel-agent-presets)
            (nucleus--override-gptel-agent-presets))))
    (when (fboundp 'nucleus--register-gptel-directives)
      (nucleus--register-gptel-directives))
    (when (fboundp 'nucleus--override-gptel-agent-presets)
      (nucleus--override-gptel-agent-presets)))
  (load-file (expand-file-name "lisp/modules/gptel-auto-workflow-strategic.el" root))
  ;; Phase 5 patch: daemon has persistent loading issue with strategic.el
  ;; where some functions aren't defined after load. Workaround until root
  ;; cause is identified.
  (when (file-exists-p (expand-file-name "lisp/modules/strategic-daemon-functions.el" root))
    (load-file (expand-file-name "lisp/modules/strategic-daemon-functions.el" root)))
  ;; Research trace replay cache for AutoTTS-style offline evaluation
  (when (file-exists-p (expand-file-name "lisp/modules/gptel-auto-workflow-research-cache.el" root))
    (load-file (expand-file-name "lisp/modules/gptel-auto-workflow-research-cache.el" root)))
  (load-file (expand-file-name "lisp/modules/gptel-auto-workflow-projects.el" root))
  (cond
   ((string= action "auto-workflow")
    (gptel-auto-workflow-queue-all-projects))
   ((string= action "research")
    (gptel-auto-workflow-queue-all-research))
   ((string= action "mementum")
    (gptel-auto-workflow-queue-all-mementum))
   ((string= action "instincts")
    (gptel-auto-workflow-queue-all-instincts))
   (t
    (error "Unknown workflow bootstrap action: %s" action))))

(provide 'gptel-auto-workflow-bootstrap)
;;; gptel-auto-workflow-bootstrap.el ends here
