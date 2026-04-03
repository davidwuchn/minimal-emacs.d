;;; eca-security.el --- ECA security configuration -*- lexical-binding: t; no-byte-compile: t; -*-

;;; Commentary:
;; Decrypts ~/.authinfo.gpg to a secure temporary file and sets ECA_NETRC_FILE.
;; Cleans up orphaned temp files from previous sessions.
;; Security features:
;; - Atomic secure file creation with pre-set permissions
;; - GPG status-fd parsing for machine-readable output
;; - PID tracking for crash recovery
;; - Strict netrc validation

;;; Code:

(require 'cl-lib)

(defconst eca-security--temp-prefix "eca-netrc-"
  "Prefix for ECA netrc temporary files.")

(defconst eca-security--temp-dir-name "var/tmp"
  "Name of secure temp directory within user-emacs-directory.")

(defun eca-security--get-temp-dir ()
  "Return the secure temp directory path, creating if needed."
  (let ((dir (expand-file-name eca-security--temp-dir-name
                               (or (and (boundp 'minimal-emacs-user-directory)
                                        minimal-emacs-user-directory)
                                   (file-name-directory (directory-file-name user-emacs-directory))))))
    (eca-security--ensure-secure-directory dir)
    dir))

(defun eca-security--ensure-secure-directory (dir)
  "Ensure DIR exists with 0700 permissions.
Returns DIR on success, nil on failure."
  (condition-case err
      (progn
        (unless (file-directory-p dir)
          (make-directory dir t))
        (set-file-modes dir #o700)
        dir)
    (error
     (message "[eca-security] Failed to create secure directory %s: %s" dir err)
     nil)))

(defun eca-security--cleanup-orphaned-temps (&optional dir)
  "Remove orphaned ECA netrc temp files from previous sessions.
Checks PID to verify files are truly orphaned.
DIR defaults to secure temp directory."
  (let ((target-dir (or dir (eca-security--get-temp-dir))))
    (when (file-directory-p target-dir)
      (dolist (file (directory-files target-dir t
                                     (concat "^" eca-security--temp-prefix)))
        (when (eca-security--file-is-orphan-p file)
          (ignore-errors (delete-file file)))))))

(defun eca-security--file-is-orphan-p (file)
  "Return non-nil if FILE is an orphaned temp file.
Checks if PID in file is still running.
If no PID file, considers file orphan if older than 24 hours."
  (condition-case err
      (let ((pid (eca-security--read-pid-file file)))
        (if pid
            (not (eca-security--process-alive-p pid))
          ;; No PID file, assume orphan if file is old (>24 hours)
          (let ((mtime (nth 5 (file-attributes file))))
            (when mtime
              (> (- (float-time) (float-time mtime)) 86400)))))
    (error
     ;; On error, assume orphan for safety
     t)))

(defun eca-security--read-pid-file (data-file)
  "Read PID from accompanying .pid file for DATA-FILE.
Returns PID as integer, or nil if no PID file."
  (let ((pid-file (concat data-file ".pid")))
    (when (file-exists-p pid-file)
      (condition-case err
          (with-temp-buffer
            (insert-file-contents pid-file)
            (let ((pid (string-to-number (string-trim (buffer-string)))))
              (and (> pid 0) pid)))  ; reject 0: kill -0 0 signals entire process group
        (error nil)))))

(defun eca-security--process-alive-p (pid)
  "Return non-nil if process PID is still running."
  (condition-case err
      (zerop (call-process "kill" nil nil nil "-0" (number-to-string pid)))
    (error nil)))

(defun eca-security--write-pid-file (data-file)
  "Write current Emacs PID to accompanying .pid file for DATA-FILE."
  (let ((pid-file (concat data-file ".pid")))
    (condition-case err
        (progn
          (write-region (number-to-string (emacs-pid)) nil pid-file nil 'silent)
          (set-file-modes pid-file #o600))
      (error
       (message "[eca-security] Failed to write PID file: %s" err)
       nil))))

(defun eca-security--validate-netrc (content)
  "Return non-nil if CONTENT appears to be valid netrc format.
Validates: contains 'machine' keyword."
  (and (stringp content)
       (not (string-empty-p content))
       ;; Must have machine keyword (flexible: machine, default, or host)
       (or (string-match-p "^\\s-*machine\\s-" content)
           (string-match-p "^\\s-*default\\s-" content)
           (string-match-p "^\\s-*host\\s-" content))
       t))

(defun eca-security--create-secure-temp (content &optional dir)
  "Write CONTENT to a secure temporary file with mode 0600.
Uses atomic creation with explicit permissions (no umask reliance).
DIR defaults to secure temp directory.
Returns file path on success, nil on failure."
  (let ((target-dir (or dir (eca-security--get-temp-dir))))
    (if (not (eca-security--ensure-secure-directory target-dir))
        nil
      (let ((prefix (expand-file-name eca-security--temp-prefix target-dir))
            (tmp-file nil))
        (setq tmp-file (make-temp-file prefix))
        (set-file-modes tmp-file #o600)
        (condition-case err
            (progn
              (write-region content nil tmp-file nil 'silent)
              (eca-security--write-pid-file tmp-file)
              tmp-file)
          (error
           (ignore-errors (delete-file tmp-file))
           (message "[eca-security] Failed to write temp file: %s" err)
           nil))))))

(defvar eca-security--temp-file nil
  "Current ECA netrc temporary file path.")

(defconst eca-security--max-decrypt-size 10240
  "Maximum allowed size for decrypted content (10KB).
Prevents memory exhaustion from large decrypted files.")

(defun eca-security--gpg-available-p ()
  "Return non-nil if GPG binary is available.
Checks for gpg executable in PATH."
  (executable-find "gpg"))

(defun eca-security--decrypt-with-size-limit (decrypt-fn gpg-file &rest args)
  "Call DECRYPT-FN with GPG-FILE and ARGS, enforcing size limit.
Returns decrypted content if under size limit, nil otherwise.
Security feature: prevents memory exhaustion attacks."
  (let ((result (apply decrypt-fn gpg-file args)))
    (when (and result (stringp result))
      (if (> (length result) eca-security--max-decrypt-size)
          (progn
            (message "[eca-security] Decrypted content exceeds %d bytes, rejecting"
                     eca-security--max-decrypt-size)
            nil)
        result))))

(defun eca-security--cleanup ()
  "Clean up ECA netrc temporary file and PID file."
  (when (and eca-security--temp-file (file-exists-p eca-security--temp-file))
    (ignore-errors (delete-file (concat eca-security--temp-file ".pid")))
    (ignore-errors (delete-file eca-security--temp-file))
    (setq eca-security--temp-file nil)))

(defun eca-security--decrypt-gpg (gpg-file passphrase)
  "Decrypt GPG-FILE with PASSPHRASE.
Uses --status-fd for machine-readable output.
Returns decrypted content on success, nil on failure."
  ;; call-process list-DESTINATION requires a file path for stderr (Emacs 30+).
  ;; We use a temp file to capture gpg --status-fd 2 output, then read it.
  (let ((output-buffer (generate-new-buffer " *gpg-decrypt-output*"))
        (status-file (make-temp-file "eca-gpg-status"))
        (exit-code nil)
        (status-output nil)
        (result nil))
    (unwind-protect
        (progn
          (setq exit-code (call-process "gpg" nil (list output-buffer status-file) nil
                                        "--batch"
                                        "--passphrase" passphrase
                                        "--status-fd" "2"
                                        "-d" gpg-file))
          (setq status-output (with-temp-buffer
                                (insert-file-contents status-file)
                                (buffer-string)))
          ;; Check exit code and look for DECRYPTION_OKAY in status output
          (when (and (zerop exit-code)
                     (string-match-p "DECRYPTION_OKAY" status-output))
            (setq result (with-current-buffer output-buffer (buffer-string)))))
      (kill-buffer output-buffer)
      (ignore-errors (delete-file status-file)))
    result))

(defun eca-security--decrypt-gpg-agent (gpg-file)
  "Decrypt GPG-FILE using gpg-agent (no passphrase argument).
Returns decrypted content on success, nil on failure.
Enforces size limit to prevent memory exhaustion."
  (if (not (eca-security--gpg-available-p))
      (progn
        (message "[eca-security] GPG binary not found")
        nil)
    (let ((output-buffer (generate-new-buffer " *gpg-decrypt-output*"))
          (exit-code nil)
          (result nil))
      (unwind-protect
          (progn
            (setq exit-code (call-process "gpg" nil output-buffer nil
                                          "--batch" "-d" gpg-file))
            (when (zerop exit-code)
              (setq result (with-current-buffer output-buffer (buffer-string)))))
        (kill-buffer output-buffer))
      (when (and result (stringp result) (> (length result) 0))
        (if (> (length result) eca-security--max-decrypt-size)
            (progn
              (message "[eca-security] Decrypted content exceeds %d bytes, rejecting"
                       eca-security--max-decrypt-size)
              nil)
          result)))))

(defun eca-security--verify-signature (gpg-file)
  "Verify GPG signature for GPG-FILE if .sig file exists.
Returns non-nil if signature is valid or no .sig file exists.
Returns nil if signature verification fails.
Security feature: detects tampering with encrypted credentials."
  (let ((sig-file (concat gpg-file ".sig")))
    (if (file-exists-p sig-file)
        (if (not (eca-security--gpg-available-p))
            (progn
              (message "[eca-security] GPG binary not found for signature verification")
              nil)
          (eca-security--verify-signature-1 gpg-file sig-file))
      t)))

(defun eca-security--verify-signature-1 (gpg-file sig-file)
  "Verify GPG signature for GPG-FILE against SIG-FILE.
Returns non-nil if signature is valid."
  ;; call-process list-DESTINATION requires a file path for stderr (Emacs 30+).
  (let ((status-file (make-temp-file "eca-gpg-verify"))
        (exit-code nil)
        (result nil))
    (unwind-protect
        (progn
          (setq exit-code (call-process "gpg" nil (list nil status-file) nil
                                        "--batch"
                                        "--status-fd" "2"
                                        "--verify" sig-file gpg-file))
          (let ((status-output (with-temp-buffer
                                 (insert-file-contents status-file)
                                 (buffer-string))))
            (setq result (and (zerop exit-code)
                              (string-match-p "GOODSIG" status-output)))))
      (ignore-errors (delete-file status-file)))
    (unless result
      (message "[eca-security] Signature verification failed for %s" gpg-file))
    result))

(with-eval-after-load 'eca
  ;; Cleanup orphaned temps from previous sessions
  (eca-security--cleanup-orphaned-temps)
  
  ;; Decrypt ~/.authinfo.gpg to secure temporary file
  (let* ((authinfo-gpg (expand-file-name "~/.authinfo.gpg"))
         (decrypted nil))
    (cond
     ((not (file-exists-p authinfo-gpg))
      (message "[eca-security] No %s found, skipping" authinfo-gpg))
     ((not (eca-security--verify-signature authinfo-gpg))
      (message "[eca-security] Signature verification failed for %s" authinfo-gpg))
     ((not (setq decrypted (eca-security--decrypt-gpg-agent authinfo-gpg)))
      (message "[eca-security] Decryption failed for %s (gpg-agent may need passphrase)" authinfo-gpg))
     ((not (eca-security--validate-netrc decrypted))
      (message "[eca-security] Invalid netrc format in %s" authinfo-gpg))
     (t
      (let ((tmp-file (eca-security--create-secure-temp decrypted)))
        (if tmp-file
            (progn
              (setq eca-security--temp-file tmp-file)
              (setenv "ECA_NETRC_FILE" tmp-file)
              (add-hook 'kill-emacs-hook #'eca-security--cleanup)
              (message "[eca-security] Credentials loaded from %s" authinfo-gpg))
          (message "[eca-security] Failed to create temp file for credentials")))))))

(provide 'eca-security)

;;; eca-security.el ends here
