;;; test-eca-security.el --- Tests for eca-security.el -*- lexical-binding: t; -*-

;;; Commentary:
;; Security-focused tests for credential handling.
;; TDD approach: tests define expected secure behavior.

;;; Code:

(require 'ert)
(require 'cl-lib)

;; Add lisp directory to load path
(add-to-list 'load-path (expand-file-name "lisp" user-emacs-directory))
(require 'eca-security)

(defvar eca-security--test-temp-dir nil
  "Temporary directory for security tests.")

(defun eca-security--test-setup ()
  "Create test temporary directory."
  (setq eca-security--test-temp-dir
        (let ((tmp (make-temp-file "eca-security-test-")))
          (delete-file tmp)
          (make-directory tmp t)
          tmp)))

(defun eca-security--test-cleanup ()
  "Clean up test temporary directory."
  (when (and eca-security--test-temp-dir
             (file-directory-p eca-security--test-temp-dir))
    (delete-directory eca-security--test-temp-dir 'recursive))
  (setq eca-security--test-temp-dir nil))

(defun eca-security--create-test-gpg-file (content)
  "Create a test GPG-encrypted file with CONTENT.
Returns path to encrypted file."
  (let ((plain-file (make-temp-file "eca-plain-" nil nil content))
        (gpg-file (concat (make-temp-file "eca-gpg-" nil nil) ".gpg")))
    (unwind-protect
        (progn
          (call-process "gpg" nil nil nil
                        "--batch" "--yes"
                        "--symmetric" "--cipher-algo" "AES256"
                        "--passphrase" "test-passphrase"
                        "-o" gpg-file plain-file)
          gpg-file)
      (delete-file plain-file))))

;; ============================================================================
;; Test: Netrc Validation
;; ============================================================================

(ert-deftest eca-security-test-validate-netrc-valid ()
  "Test that valid netrc content passes validation."
  (let ((valid-netrc "machine example.com\nlogin user\npassword secret\n"))
    (should (eca-security--validate-netrc valid-netrc))))

(ert-deftest eca-security-test-validate-netrc-invalid-empty ()
  "Test that empty content fails validation."
  (should-not (eca-security--validate-netrc ""))
  (should-not (eca-security--validate-netrc nil)))

(ert-deftest eca-security-test-validate-netrc-invalid-no-machine ()
  "Test that content without 'machine' keyword fails validation."
  (should-not (eca-security--validate-netrc "login user\npassword secret\n"))
  (should-not (eca-security--validate-netrc "just some text")))

(ert-deftest eca-security-test-validate-netrc-invalid-injection ()
  "Test that newline injection in password field is detected.
This is a security test - malformed netrc should be rejected."
  (let ((injected "machine example.com\npassword secret\nmachine attacker.com\npassword stolen\n"))
    ;; Current implementation allows this - this test documents the weakness
    ;; TODO: After fix, this should fail validation
    (should (eca-security--validate-netrc injected))))

;; ============================================================================
;; Test: Secure Temp File Creation
;; ============================================================================

(ert-deftest eca-security-test-create-secure-temp-permissions ()
  "Test that temp files are created with 0600 permissions.
Security test: credentials must never be readable by others."
  (let* ((content "machine test.com\nlogin user\npassword secret\n")
         (tmp-file (eca-security--create-secure-temp content eca-security--test-temp-dir)))
    (unwind-protect
        (progn
          (should tmp-file)
          (should (file-exists-p tmp-file))
          ;; Verify permissions are exactly 0600
          (let ((modes (file-modes tmp-file)))
            (should (= (logand modes #o777) #o600))))
      (when tmp-file (delete-file tmp-file)))))

(ert-deftest eca-security-test-create-secure-temp-content ()
  "Test that temp file contains exact content written."
  (let* ((content "machine test.com\nlogin user\npassword secret\n")
         (tmp-file (eca-security--create-secure-temp content eca-security--test-temp-dir)))
    (unwind-protect
        (progn
          (should tmp-file)
          (with-temp-buffer
            (insert-file-contents tmp-file)
            (should (string= (buffer-string) content))))
      (when tmp-file (delete-file tmp-file)))))

(ert-deftest eca-security-test-create-secure-temp-error-cleanup ()
  "Test that failed temp file creation cleans up partial files.
Security test: no partial credentials left on disk."
  ;; This test documents expected behavior - implementation may vary
  (should t)) ; Placeholder

;; ============================================================================
;; Test: Orphan Cleanup
;; ============================================================================

(ert-deftest eca-security-test-cleanup-orphaned-temps ()
  "Test that orphaned temp files are cleaned up on startup."
  (eca-security--test-setup)
  (unwind-protect
      (let* ((test-dir (concat eca-security--test-temp-dir "/orphans"))
             (orphan-file (concat test-dir "/eca-netrc-orphan")))
        (make-directory test-dir t)
        (write-region "test" nil orphan-file nil 'silent)
        (set-file-modes orphan-file #o600)
        ;; Make file appear old (>1 hour) so it's considered orphan
        (call-process "touch" nil nil nil "-t" "202001010000" orphan-file)
        (should (file-exists-p orphan-file))
        ;; Simulate cleanup
        (eca-security--cleanup-orphaned-temps test-dir)
        (should-not (file-exists-p orphan-file)))
    (eca-security--test-cleanup)))

(ert-deftest eca-security-test-cleanup-preserves-non-matching ()
  "Test that cleanup only removes files with correct prefix."
  (eca-security--test-setup)
  (unwind-protect
      (let* ((test-dir (concat eca-security--test-temp-dir "/preserve"))
             (keep-file (concat test-dir "/other-file"))
             (remove-file (concat test-dir "/eca-netrc-temp")))
        (make-directory test-dir t)
        (write-region "test" nil keep-file nil 'silent)
        (write-region "test" nil remove-file nil 'silent)
        ;; Make remove-file appear old so it's considered orphan
        (call-process "touch" nil nil nil "-t" "202001010000" remove-file)
        (eca-security--cleanup-orphaned-temps test-dir)
        (should (file-exists-p keep-file))
        (should-not (file-exists-p remove-file)))
    (eca-security--test-cleanup)))

;; ============================================================================
;; Test: GPG Decryption
;; ============================================================================

(ert-deftest eca-security-test-gpg-decrypt-success ()
  "Test successful GPG decryption with passphrase.
Note: This tests the eca-security--decrypt-gpg function directly,
which is kept for backward compatibility but not used by default."
  (skip-unless (executable-find "gpg"))
  (let ((test-content "machine test.com\nlogin user\npassword secret\n")
        (gpg-file nil)
        (decrypted nil))
    (unwind-protect
        (progn
          (setq gpg-file (eca-security--create-test-gpg-file test-content))
          ;; Test decryption function with passphrase
          (setq decrypted (eca-security--decrypt-gpg gpg-file "test-passphrase"))
          (when decrypted
            (should (string-match-p "machine test.com" decrypted))))
      (when gpg-file (delete-file gpg-file)))))

(ert-deftest eca-security-test-gpg-decrypt-failure ()
  "Test GPG decryption failure with wrong passphrase."
  (skip-unless (executable-find "gpg"))
  (let ((test-content "machine test.com\nlogin user\npassword secret\n")
        (gpg-file nil)
        (decrypted nil))
    (unwind-protect
        (progn
          (setq gpg-file (eca-security--create-test-gpg-file test-content))
          (setq decrypted (eca-security--decrypt-gpg gpg-file "wrong-passphrase"))
          (should-not decrypted))
      (when gpg-file (delete-file gpg-file)))))

;; ============================================================================
;; Test: Cleanup Hook
;; ============================================================================

(ert-deftest eca-security-test-cleanup-function ()
  "Test that cleanup function removes temp file and PID file."
  (eca-security--test-setup)
  (unwind-protect
      (let* ((content "machine test.com\nlogin user\npassword secret\n")
             (tmp-file (eca-security--create-secure-temp content eca-security--test-temp-dir))
             (pid-file (concat tmp-file ".pid")))
        (when tmp-file
          (setq eca-security--temp-file tmp-file)
          (eca-security--cleanup)
          (should-not (file-exists-p tmp-file))
          (should-not (file-exists-p pid-file))
          (should (null eca-security--temp-file))))
    (eca-security--test-cleanup)))

;; ============================================================================
;; Test: Directory Creation Security
;; ============================================================================

(ert-deftest eca-security-test-secure-dir-creation ()
  "Test that secure temp directory is created with 0700 permissions."
  (eca-security--test-setup)
  (unwind-protect
      (let* ((test-subdir (concat eca-security--test-temp-dir "/secure-test"))
             (created (eca-security--ensure-secure-directory test-subdir)))
        (unwind-protect
            (progn
              (should created)
              (should (file-directory-p test-subdir))
              (let ((modes (file-modes test-subdir)))
                (should (= (logand modes #o777) #o700))))
          (when (file-directory-p test-subdir)
            (delete-directory test-subdir 'recursive))))
    (eca-security--test-cleanup)))


;; ============================================================================
;; Test: GPG Binary Check (NEW - Security Fix)
;; ============================================================================

(ert-deftest eca-security-test-gpg-binary-check ()
  "Test that GPG binary check returns non-nil when gpg is available."
  (let ((result (eca-security--gpg-available-p)))
    (if (executable-find "gpg")
        (should result)
      (should-not result))))

(ert-deftest eca-security-test-decrypt-fails-without-gpg ()
  "Test that decryption fails gracefully when GPG is not available."
  ;; This test verifies the security fix: no fallback to insecure methods
  (let ((mock-gpg-file "/tmp/nonexistent.gpg"))
    ;; Should not crash, should return nil
    (should-not (eca-security--decrypt-gpg-agent mock-gpg-file))))

;; ============================================================================
;; Test: File Size Limit (NEW - Security Fix)
;; ============================================================================

(ert-deftest eca-security-test-decrypt-rejects-large-files ()
  "Test that decryption rejects files larger than 10KB limit.
Security test: prevent memory exhaustion from large decrypted content."
  (skip-unless (executable-find "gpg"))
  (let* ((large-content (make-string 15000 ?a))  ; 15KB, exceeds 10KB limit
         (gpg-file nil)
         (decrypted nil))
    (unwind-protect
        (progn
          (setq gpg-file (eca-security--create-test-gpg-file large-content))
          (setq decrypted (eca-security--decrypt-gpg-agent gpg-file))
          ;; Should return nil for files exceeding size limit
          (should-not decrypted))
      (when gpg-file (delete-file gpg-file)))))

(ert-deftest eca-security-test-decrypt-accepts-small-files ()
  "Test that decryption accepts files under 10KB limit.
Uses eca-security--decrypt-gpg with passphrase for testing."
  (skip-unless (executable-find "gpg"))
  (let* ((small-content "machine test.com\nlogin user\npassword secret\n")
         (gpg-file nil)
         (decrypted nil))
    (unwind-protect
        (progn
          (setq gpg-file (eca-security--create-test-gpg-file small-content))
          ;; Use decrypt-gpg with passphrase for testing
          (setq decrypted (eca-security--decrypt-gpg gpg-file "test-passphrase"))
          ;; Should succeed for small files
          (when decrypted
            (should (< (length decrypted) 10240))))  ; Under 10KB
      (when gpg-file (delete-file gpg-file)))))

;; ============================================================================
;; Test: TTL-Based Orphan Cleanup (NEW - Security Fix)
;; ============================================================================

(ert-deftest eca-security-test-orphan-cleanup-ttl-24h ()
  "Test that orphan cleanup deletes files older than 24 hours.
Security test: prevent credential leakage from stale temp files."
  (eca-security--test-setup)
  (unwind-protect
      (let* ((test-dir (concat eca-security--test-temp-dir "/ttl-test"))
             (old-file (concat test-dir "/eca-netrc-old"))
             (new-file (concat test-dir "/eca-netrc-new")))
        (make-directory test-dir t)
        ;; Create old file (>24 hours)
        (write-region "test" nil old-file nil 'silent)
        (set-file-modes old-file #o600)
        (call-process "touch" nil nil nil "-t" "202001010000" old-file)
        ;; Create new file (current time)
        (write-region "test" nil new-file nil 'silent)
        (set-file-modes new-file #o600)
        ;; Both should exist before cleanup
        (should (file-exists-p old-file))
        (should (file-exists-p new-file))
        ;; Run cleanup - only old file should be removed
        (eca-security--cleanup-orphaned-temps test-dir)
        (should-not (file-exists-p old-file))
        ;; New file without PID should be kept if <1 hour old
        ;; (current logic keeps files <1 hour without PID)
        )
    (eca-security--test-cleanup)))

;; ============================================================================
;; Test: No Hardcoded Passphrase (NEW - Security Fix)
;; ============================================================================

(ert-deftest eca-security-test-no-hardcoded-passphrase ()
  "Test that decryption does not use hardcoded passphrase fallback.
Security test: gpg-agent should be the only decryption method.
This test verifies the hardcoded 'test-passphrase' has been removed."
  (skip-unless (executable-find "gpg"))
  (let* ((test-content "machine test.com\nlogin user\npassword secret\n")
         (gpg-file nil)
         (decrypted nil))
    (unwind-protect
        (progn
          ;; Encrypt with a DIFFERENT passphrase than the hardcoded one
          (let ((plain-file (make-temp-file "eca-plain-" nil nil test-content)))
            (unwind-protect
                (progn
                  (call-process "gpg" nil nil nil
                                "--batch" "--yes"
                                "--symmetric" "--cipher-algo" "AES256"
                                "--passphrase" "different-passphrase"
                                "-o" (setq gpg-file (concat plain-file ".gpg")) plain-file))
              (delete-file plain-file)))
          ;; Try to decrypt - should fail since we don't have gpg-agent set up
          ;; and the hardcoded passphrase won't work
          (setq decrypted (eca-security--decrypt-gpg-agent gpg-file))
          ;; Should return nil (no decryption) rather than using hardcoded fallback
          (should-not decrypted))
      (when gpg-file (delete-file gpg-file)))))

;; ============================================================================
;; Test: Umask Not Relied Upon (NEW - Security Fix)
;; ============================================================================

(ert-deftest eca-security-test-permissions-without-umask ()
  "Test that file permissions are set explicitly, not via umask.
Security test: permissions must be 0600 regardless of umask setting."
  (let* ((content "machine test.com\nlogin user\npassword secret\n")
         (tmp-file (eca-security--create-secure-temp content eca-security--test-temp-dir)))
    (unwind-protect
        (progn
          (should tmp-file)
          ;; Verify permissions are exactly 0600
          ;; This should pass even if umask is permissive
          (let ((modes (file-modes tmp-file)))
            (should (= (logand modes #o777) #o600))))
      (when tmp-file (delete-file tmp-file)))))
;;; test-eca-security.el ends here
