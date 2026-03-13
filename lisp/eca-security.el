;;; eca-security.el --- ECA security config -*- lexical-binding: t; -*-

;; This file is written to work in both Doom Emacs and vanilla Emacs.
;; In vanilla Emacs, Doom macros like `use-package!' and `add-hook!' are undefined.

(with-eval-after-load 'eca
  ;; Decrypt ~/.authinfo.gpg to a temporary file and set ECA_NETRC_FILE
  ;; (mimics the eca-secure wrapper script behavior)
  (let* ((authinfo-gpg (expand-file-name "~/.authinfo.gpg"))
         (decrypted (with-temp-buffer
                      (if (and (file-exists-p authinfo-gpg)
                               (zerop (call-process "gpg" nil t nil
                                                    "-q" "--batch" "-d" authinfo-gpg)))
                          (buffer-string)
                        nil))))
    (if (and decrypted (not (string-empty-p decrypted)))
        (let ((tmp-file (make-temp-file "netrc-")))
          (write-region decrypted nil tmp-file nil 'silent)
          (set-file-modes tmp-file #o600)
          (setenv "ECA_NETRC_FILE" tmp-file)
          ;; Clean up temp file on Emacs exit
          (add-hook 'kill-emacs-hook
                    (lambda () (when (file-exists-p tmp-file)
                                (delete-file tmp-file)))))
      (message "[eca-security] Warning: Failed to decrypt %s" authinfo-gpg))))

;;; Fast download overrides for eca-process
;; These run after eca-process is loaded (which happens when eca loads).
;; No elpa files are modified.

(with-eval-after-load 'eca-process
  ;; Force ECA to install binaries in ~/.emacs.d/eca instead of ~/.emacs.d/var/eca
  (setopt eca-server-install-path (expand-file-name (if (eq system-type 'windows-nt) "eca/eca.exe" "eca/eca")
                                                    (if (boundp 'minimal-emacs-user-directory) minimal-emacs-user-directory user-emacs-directory))
          eca-server-version-file-path (expand-file-name "eca/eca-version" (if (boundp 'minimal-emacs-user-directory) minimal-emacs-user-directory user-emacs-directory)))

  ;; 1. Write missing version file & pre-seed version cache
  ;; Prevents string-version-lessp(nil, latest)=t triggering a re-download
  ;; on every startup when the system eca binary is absent.
  ;;
  ;; The tag_name from GitHub has no "v" prefix (e.g. "0.106.0"); we normalise
  ;; everything to "X.Y.Z" to match the format expected by the version file.
  ;;
  ;; Version resolution order (stops at first success):
  ;;   a) Installed binary  (`eca --version` → "eca X.Y.Z")
  ;;   b) GitHub tags API   (api.github.com/repos/.../releases/latest → tag_name)
  ;;   c) Package version   (from eca-pkg.el if installed via package.el)
  ;;   d) Pinned fallback   (updated manually when above sources fail)
  ;;
  (defvar my/eca--pinned-version "0.106.0"
    "Pinned fallback version when binary and GitHub API are unavailable.
Update this when ECA releases change format or GitHub API is unreachable.")

  (defun my/eca--resolve-version ()
    "Return the current eca version string as \"X.Y.Z\".
Tries the installed binary, then the GitHub releases/latest API, then
package.el version, then falls back to a pinned constant."
    (cl-flet ((parse-semver (raw)
                (and (stringp raw)
                     (string-match "\\([0-9]+\\.[0-9]+\\.[0-9]+\\)" raw)
                     (match-string 1 raw))))
      (or
       ;; (a) installed binary
       (when-let* ((bin (executable-find "eca"))
                   (raw (string-trim
                         (shell-command-to-string
                          (concat (shell-quote-argument bin) " --version")))))
         (parse-semver raw))
       ;; (b) GitHub releases/latest API (tiny JSON, no auth required)
       (when-let* ((curl (or (executable-find "curl") (executable-find "curl.exe")))
                   (raw  (string-trim
                          (shell-command-to-string
                           (format "%s -s -f --max-time 5 %s"
                                   (shell-quote-argument curl)
                                   "https://api.github.com/repos/editor-code-assistant/eca/releases/latest"))))
                   ((not (string-blank-p raw)))
                   ;; tag_name field: "0.106.0" (no v prefix on this repo)
                   ((string-match "\"tag_name\"\\s-*:\\s-*\"\\([^\"]+\\)\"" raw)))
         (parse-semver (match-string 1 raw)))
       ;; (c) package.el version (if installed via package.el)
       (when (featurep 'package)
         (when-let* ((pkg-desc (assq 'eca package-alist))
                     (ver-list (package-desc-version (cadr pkg-desc))))
           (package-version-join ver-list)))
       ;; (d) pinned fallback — update when the above sources change format
       my/eca--pinned-version)))

  (let* ((vfile (or (bound-and-true-p eca-server-version-file-path)
                    (expand-file-name "eca/eca-version" (if (boundp 'minimal-emacs-user-directory) minimal-emacs-user-directory user-emacs-directory))))
         (version (my/eca--resolve-version)))
    ;; Write version file if missing so the 'already-installed branch fires.
    (unless (file-exists-p vfile)
      (make-directory (file-name-directory vfile) t)
      (write-region version nil vfile nil 'silent))
    ;; Pre-populate the in-memory cache -> skips the blocking GitHub API call.
    (setq eca-process--latest-server-version version))

  ;; 2. Use /releases/latest (tiny JSON) instead of /releases (full list)
  (defun my/eca--curl-download-string (url)
    "Like `eca--curl-download-string' but rewrites the releases list URL
to the /releases/latest endpoint (much smaller payload, ~10x faster)."
    (let* ((fast-url (replace-regexp-in-string
                      "/repos/\\([^/]+/[^/]+\\)/releases$"
                      "/repos/\\1/releases/latest"
                      url))
           (curl-cmd (or (executable-find "curl")
                         (executable-find "curl.exe"))))
      (unless curl-cmd
        (error "Curl not found"))
      (let ((output (shell-command-to-string
                     (format "%s -L -s -S -f --compressed %s"
                             (shell-quote-argument curl-cmd)
                             (shell-quote-argument fast-url)))))
        (when (string-blank-p output)
          (error "Curl failed to download from %s" fast-url))
        ;; /releases/latest returns a single object; wrap it so callers
        ;; that do (elt result 0) still work.
        (if (string-match-p "^\\s-*\\[" output)
            output
          (concat "[" output "]")))))

  (advice-add 'eca--curl-download-string :override #'my/eca--curl-download-string)

  ;; 3. Replace blocking curl download with async aria2c
  ;; Mirrors fast-download.clj: -c (resume) -x16 -s16 -k1M --file-allocation=none
  ;; Falls back to wget -c, then curl -C - (both with resume).
  (setopt eca-server-download-method 'curl)

  (cl-defun my/eca--curl-download-file (&key url path on-done)
    "Async binary download replacing `eca--curl-download-file'.
Uses aria2c with 16 parallel connections and resume support (mirrors
fast-download.clj).  Falls back to wget then curl when aria2c is absent."
    (let* ((aria2 (executable-find "aria2c"))
           (wget  (executable-find "wget"))
           (curl  (or (executable-find "curl") (executable-find "curl.exe")))
           (cmd   (cond
                   (aria2 (list aria2
                                "-c"                     ; resume
                                "-x" "16"                ; max connections/server
                                "-s" "16"                ; splits
                                "-k" "1M"                ; min split size
                                "--file-allocation=none" ; faster start
                                "--summary-interval=0"   ; quiet
                                "--auto-file-renaming=false"
                                "-d" (file-name-directory path)
                                "-o" (file-name-nondirectory path)
                                url))
                   (wget  (list wget "-c" "-O" path url))
                   (curl  (list curl "-C" "-" "-L" "-f" "-o" path url))
                   (t (error "No downloader found (aria2c/wget/curl)")))))
      (eca-info "Fast-downloading %s -> %s [%s]"
                url path (file-name-nondirectory (car cmd)))
      (make-process
       :name     "eca-download"
       :command  cmd
       :noquery  t
       :sentinel (lambda (proc _event)
                   (unless (process-live-p proc)
                     (if (= 0 (process-exit-status proc))
                         (progn
                           (eca-info "Download complete: %s" path)
                           (funcall on-done))
                       (message "eca download failed (exit %d): %s"
                                (process-exit-status proc) path)))))))

  (advice-add 'eca--curl-download-file :override #'my/eca--curl-download-file)

  ;; 4. Interactive update command & buffer
  ;; Checks GitHub releases/latest, compares with installed version,
  ;; downloads + verifies + installs the new binary synchronously.
  (defun my/eca-update (&optional silent)
    "Check for a newer eca binary and update if available.

Compares the installed version against the latest GitHub release.
If an update is available, downloads the platform-appropriate zip,
verifies SHA256 (warns but continues when unavailable), installs the
new binary into `eca-server-install-path', and updates the version file.

Progress is shown live in the *eca-update* buffer.
With prefix arg or when SILent is non-nil, suppress the buffer."
    (interactive "P")
    (let* ((buf (and (not silent) (get-buffer-create "*eca-update*")))
           (log (lambda (fmt &rest args)
                  (when buf
                    (with-current-buffer buf
                      (goto-char (point-max))
                      (insert (apply #'format fmt args) "\n")
                      (when-let* ((win (get-buffer-window buf t)))
                        (set-window-point win (point-max)))))
                  ;; Also echo brief status
                  (apply #'message fmt args))))
      (when buf
        (with-current-buffer buf
          (erase-buffer)
          (insert "=== eca update ===\n\n"))
        (display-buffer buf))
      (let ((curl (or (executable-find "curl") (executable-find "curl.exe"))))
        (unless curl (user-error "my/eca-update: curl not found"))

        ;; 1. Fetch latest version from GitHub API
        (funcall log "Checking latest version from GitHub...")
        (let* ((api-url "https://api.github.com/repos/editor-code-assistant/eca/releases/latest")
               (raw (string-trim
                     (shell-command-to-string
                      (format "%s -s -f --max-time 10 %s"
                              (shell-quote-argument curl)
                              (shell-quote-argument api-url)))))
               (_ (when (string-blank-p raw)
                    (user-error "my/eca-update: failed to reach GitHub API")))
               (_ (unless (string-match "\"tag_name\"\\s-*:\\s-*\"\\([^\"]+\\)\"" raw)
                    (user-error "my/eca-update: could not parse tag_name")))
               (latest (match-string 1 raw))   ; "0.105.0" — no v prefix on this repo

               ;; 2. Installed version
               (installed (my/eca--resolve-version))           ; "vX.Y.Z"
               (installed-bare (if (string-match "^v?\\(.*\\)" installed)
                                   (match-string 1 installed)
                                 installed)))

          (funcall log "Latest:    %s" latest)
          (funcall log "Installed: %s" installed-bare)

          (if (not (string-version-lessp installed-bare latest))
              (funcall log "\nAlready up to date.")

            ;; 3. Derive paths
            (let* ((zip-url   (eca-process--download-url latest))
                   (store-path eca-server-install-path)
                   (zip-path  (concat store-path ".zip"))
                   (sha-url   (concat zip-url ".sha256"))
                   (sha-path  (concat zip-path ".sha256"))
                   (old-path  (concat store-path ".old"))
                   (temp-dir  (concat (file-name-directory store-path) "eca-update-temp")))

              ;; 4. Download zip synchronously
              (funcall log "\nDownloading %s ..." zip-url)
              (make-directory (file-name-directory store-path) t)
              (let ((exit (call-process curl nil buf t
                                        "-L" "-f" "--progress-bar"
                                        "-o" zip-path zip-url)))
                (unless (= exit 0)
                  (user-error "my/eca-update: download failed (curl exit %d)" exit)))
              (funcall log "Download complete.")

              ;; 5. SHA256 verification (warn only, never abort)
              (funcall log "\nVerifying SHA256...")
              (call-process curl nil nil nil
                            "-s" "-f" "--max-time" "5" "-o" sha-path sha-url)
              (let* ((sha-available (and (file-exists-p sha-path)
                                         (> (file-attribute-size
                                             (file-attributes sha-path)) 0)))
                     (shasum-cmd
                      (cond
                       ((executable-find "sha256sum") "sha256sum")
                       ((executable-find "shasum")    "shasum -a 256")
                       (t nil))))
                (cond
                 ((not sha-available)
                  (funcall log "Warning: SHA256 asset not available for this platform — skipping verification."))
                 ((not shasum-cmd)
                  (funcall log "Warning: sha256sum/shasum not found — skipping verification."))
                 (t
                  (let* ((expected (car (split-string
                                         (with-temp-buffer
                                           (insert-file-contents sha-path)
                                           (buffer-string)))))
                         (actual (car (split-string
                                       (shell-command-to-string
                                        (format "%s %s"
                                                shasum-cmd
                                                (shell-quote-argument zip-path)))))))
                    (if (string= expected actual)
                        (funcall log "SHA256 OK (%s)." actual)
                      (funcall log "Warning: SHA256 mismatch — expected %s, got %s. Installing anyway."
                               expected actual))))))

              ;; 6. Unzip to temp dir
              (funcall log "\nExtracting...")
              (when (file-exists-p temp-dir)
                (delete-directory temp-dir t))
              (make-directory temp-dir t)
              (let ((exit (call-process "unzip" nil buf t
                                        "-o" zip-path "-d" temp-dir)))
                (unless (= exit 0)
                  (user-error "my/eca-update: unzip failed (exit %d)" exit)))

              ;; 7. Move binary into place
              (let ((new-bin (expand-file-name
                              (file-name-nondirectory store-path) temp-dir)))
                (unless (file-exists-p new-bin)
                  (user-error "my/eca-update: expected binary not found after extraction: %s" new-bin))
                (when (file-exists-p old-path)
                  (ignore-errors (delete-file old-path)))
                (when (file-exists-p store-path)
                  (rename-file store-path old-path))
                (rename-file new-bin store-path)
                (set-file-modes store-path #o0700))

              ;; 8. Clean up temp files
              (ignore-errors (delete-directory temp-dir t))
              (ignore-errors (delete-file zip-path))
              (ignore-errors (delete-file sha-path))
              (ignore-errors (delete-file old-path))

              ;; 9. Update version tracking
              ;; Store bare semver (no "v" prefix) to match my/eca--resolve-version output
                (write-region latest nil
                              eca-server-version-file-path nil 'silent)
                (setq eca-process--latest-server-version latest)

                (funcall log "\neca updated to v%s. Done." latest)))))))

)

;; 5. Daily auto-update check
;; Runs once per Emacs session, after 30 s of idle, at most once per day.
;; Uses a timestamp file so repeated restarts don't re-check until tomorrow.
(defcustom my/eca-auto-update-enabled nil
  "When non-nil, check for eca updates once per day at idle."
  :type 'boolean
  :group 'eca)

(defcustom my/eca-auto-update-idle-seconds 30
  "Seconds of idle time before the daily eca update check runs."
  :type 'integer
  :group 'eca)

(defvar my/eca--last-check-file
  (expand-file-name "eca/eca-update-check" (if (boundp 'minimal-emacs-user-directory) minimal-emacs-user-directory user-emacs-directory))
  "Timestamp file recording when the last auto-update check ran.")

(defun my/eca--update-check-due-p ()
  "Return non-nil when more than 24 h have passed since the last check."
  (not (and (file-exists-p my/eca--last-check-file)
            (let* ((attrs (file-attributes my/eca--last-check-file))
                   (mtime (file-attribute-modification-time attrs))
                   (age   (float-time (time-subtract (current-time) mtime))))
              (< age 86400)))))

(defun my/eca--auto-update-maybe ()
  "Run `my/eca-update' silently if a day has passed since the last check."
  (when (and my/eca-auto-update-enabled
             (featurep 'eca-process)
             (my/eca--update-check-due-p))
    ;; Touch the timestamp file immediately so concurrent/rapid restarts skip.
    (make-directory (file-name-directory my/eca--last-check-file) t)
    (write-region "" nil my/eca--last-check-file nil 'silent)
    ;; Suppress the progress buffer for auto-runs; errors go to *Messages*.
    (condition-case err
        (let ((display-buffer-alist
               (cons '("\\*eca-update\\*" (display-buffer-no-window))
                     display-buffer-alist)))
          (my/eca-update))
      (error (message "eca auto-update check failed: %s"
                      (error-message-string err))))))

(defun my/eca-update-show ()
  "Show eca update status and offer manual update.
Pops up a buffer with current version info and buttons to check/update."
  (interactive)
  (let* ((installed (my/eca--resolve-version))
         (buf (get-buffer-create "*eca-update*")))
    (with-current-buffer buf
      (erase-buffer)
      (insert "=== eca Update ===\n\n")
      (insert (format "Installed version: %s\n\n" installed))
      (insert "Actions:\n")
      (insert-text-button "Check for updates"
                          'action (lambda (_)
                                    (call-interactively #'my/eca-update))
                          'follow-link t
                          'help-echo "Click to check and update eca")
      (insert "\n")
      (insert-text-button "Force re-download"
                          'action (lambda (_)
                                    (when (yes-or-no-p "Re-download even if up to date? ")
                                      (call-interactively #'my/eca-update)))
                          'follow-link t
                          'help-echo "Force re-download and reinstall")
      (insert "\n\n")
      (insert "Auto-update is currently: ")
      (insert-text-button (if my/eca-auto-update-enabled "ENABLED" "DISABLED")
                          'action (lambda (_)
                                    (customize-set-variable 'my/eca-auto-update-enabled
                                                            (not my/eca-auto-update-enabled))
                                    (my/eca-update-show))
                          'follow-link t
                          'help-echo "Click to toggle auto-update")
      (insert "\n")
      (goto-char (point-min)))
    (display-buffer buf '(display-buffer-same-window))))

(with-eval-after-load 'eca-process
  (run-with-idle-timer my/eca-auto-update-idle-seconds nil
                       #'my/eca--auto-update-maybe))

(provide 'eca-security)
