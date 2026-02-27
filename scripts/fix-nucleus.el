(with-temp-buffer
  (insert-file-contents "lisp/nucleus-config.el")
  (goto-char (point-min))
  (search-forward "(defvar nucleus--gptel-agent-snippet-tools\n  nil")
  (replace-match "(defvar nucleus--gptel-agent-snippet-tools\n  '(\"Bash\" \"Edit\" \"ApplyPatch\" \"preview_file_change\")")
  (write-region (point-min) (point-max) "lisp/nucleus-config.el"))
