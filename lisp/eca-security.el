;;; eca-security.el --- ECA security configuration -*- lexical-binding: t; no-byte-compile: t; -*-

;;; Commentary:
;; Decrypts ~/.authinfo.gpg and sets ECA_NETRC_FILE environment variable.
;; This allows ECA to use stored credentials without exposing the encrypted
;; authinfo file directly.

;;; Code:

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

(provide 'eca-security)

;;; eca-security.el ends here