;;; test-heartbeat-daemon-init-strong.el --- Stronger test for heartbeat-at-init -*- lexical-binding: t; -*-

(defvar test-heartbeat-daemon-init--repo-root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name default-directory)))))

(ert-deftest test-heartbeat-daemon-init/function-is-inside-daemonp-block ()
  "The gptel-auto-workflow--start-heartbeat-timer call must be inside
the (when (daemonp) ...) block in post-init.el."
  (let ((f (expand-file-name "post-init.el" test-heartbeat-daemon-init--repo-root)))
    (skip-unless (file-exists-p f))
    (with-temp-buffer
      (insert-file-contents f)
      (let ((content (buffer-string)))
        ;; The daemonp-block + heartbeat-function must be present
        (should (string-match-p "(when (daemonp)" content))
        (should (string-match-p "gptel-auto-workflow--start-heartbeat-timer" content))
        ;; Eager require must be used (the fix for the lazy-load race)
        (let ((lazy-form (string-match-p
                          "with-eval-after-load 'gptel-tools-agent-experiment-loop"
                          content)))
          (should (not lazy-form)))
        ;; The heartbeat call must come AFTER the (when (daemonp)
        ;; start, not before — i.e., the function is INSIDE the block.
        (let ((daemonp-start (string-match "(when (daemonp)" content))
              (heartbeat-pos (string-match
                              "gptel-auto-workflow--start-heartbeat-timer"
                              content)))
          (should (> heartbeat-pos daemonp-start)))))))
