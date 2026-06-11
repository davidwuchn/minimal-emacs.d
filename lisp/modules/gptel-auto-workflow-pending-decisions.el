;;; gptel-auto-workflow-pending-decisions.el -*- lexical-binding: t; -*-
(defun gptel-auto-workflow--pending-decisions-p ()
  "Return non-nil if there are pending human decisions blocking PMF."
  (when (bound-and-true-p gptel-auto-workflow-human-decision-gate)
    (let ((dir (if (fboundp 'gptel-auto-workflow--decisions-dir)
                   (gptel-auto-workflow--decisions-dir)
                 (expand-file-name "mementum/decisions/" default-directory)))
          (pending nil))
      (when (file-directory-p dir)
        (dolist (file (directory-files dir t "\.md$"))
          (let* ((content (condition-case nil
                            (with-temp-buffer
                              (insert-file-contents file)
                              (buffer-string))
                          (error nil)))
                 (status (when (and content (string-match "^status:\s-*(.+)$" content))
                           (match-string 1 content))))
            (when (and status (string= (string-trim status) "proposed"))
              (setq pending t)))))
      pending)))

(provide 'gptel-auto-workflow-pending-decisions)
