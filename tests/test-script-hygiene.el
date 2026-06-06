;;; test-script-hygiene.el --- Tests for pipeline script hygiene -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)

(ert-deftest script-hygiene/no-python3-in-scripts ()
  :tags '(script-hygiene)
  "Pipeline scripts must not use python3 (eliminated in prior sessions)."
  (let ((scripts-dir (expand-file-name "../scripts"
                                       (file-name-directory
                                        (or load-file-name buffer-file-name default-directory)))))
    (skip-unless (file-directory-p scripts-dir))
    (dolist (script (directory-files scripts-dir t "\\.sh\\'"))
      (with-temp-buffer
        (insert-file-contents script)
        (goto-char (point-min))
        (when (re-search-forward "python3" nil t)
          (ert-fail (format "%s uses python3" (file-name-nondirectory script))))))))

(ert-deftest script-hygiene/no-hardcoded-experiment-paths ()
  :tags '(script-hygiene)
  "Pipeline scripts must not contain machine-specific experiment paths."
  (let ((scripts-dir (expand-file-name "../scripts"
                                       (file-name-directory
                                        (or load-file-name buffer-file-name default-directory)))))
    (skip-unless (file-directory-p scripts-dir))
    (dolist (script (directory-files scripts-dir t "\\.sh\\'"))
      (with-temp-buffer
        (insert-file-contents script)
        (goto-char (point-min))
        (when (re-search-forward "main-baseline-[0-9]+" nil t)
          (ert-fail (format "%s contains hardcoded experiment path" (file-name-nondirectory script))))))))

(provide 'test-script-hygiene)
;;; test-script-hygiene.el ends here