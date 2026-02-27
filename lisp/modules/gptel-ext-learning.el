;;; -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'subr-x)
(require 'seq)
(require 'project)
(require 'url)
(require 'url-parse)
(require 'url-util)
(require 'json)
(require 'dom)
(require 'diff)
(require 'gptel)
(eval-when-compile
  (require 'gptel-openai)
  (require 'gptel-gemini)
  (require 'gptel-gh))
(require 'gptel-context)
(require 'gptel-request)
(require 'gptel-gh)
(require 'gptel-gemini)
(require 'gptel-openai)
;; (require 'gptel-openai-extras)

(defun my/learning--update-instinct (path)
  "Update evidence and last-accessed in instinct frontmatter at PATH."
  (when (file-readable-p path)
    (let* ((text (with-temp-buffer
                   (insert-file-contents path)
                   (buffer-string)))
           (case-fold-search nil))
      (when (string-match "\\`---\n\\([\\s\\S]*?\n\\)---\n" text)
        (let* ((front (match-string 1 text))
               (rest (substring text (match-end 0)))
               (date (format-time-string "%Y-%m-%d"))
               (front (if (string-match "^evidence:\\s-*\\([0-9]+\\)" front)
                          (replace-regexp-in-string
                           "^evidence:\\s-*\\([0-9]+\\)"
                           (lambda (_m)
                             (format "evidence: %d"
                                     (1+ (string-to-number (match-string 1 front)))))
                           front)
                        (concat front "evidence: 1\n")))
               (front (if (string-match "^last-accessed:" front)
                          (replace-regexp-in-string
                           "^last-accessed:.*$"
                           (format "last-accessed: %s" date)
                           front)
                        (concat front "last-accessed: " date "\n")))
               (updated (concat "---\n" front "---\n" rest)))
          (with-temp-file path
            (insert updated)))))))

(defun my/learning-auto-evolve-after-commit ()
  "Auto-evolve instincts touched in the latest commit.

If LEARNING.md was updated, increment all instincts referenced via
learning-ref: LEARNING.md#slug.
"
  (let* ((repo (or (and (boundp 'git-commit-repository)
                        git-commit-repository)
                   default-directory))
         (default-directory repo)
         (paths (condition-case nil
                    (process-lines "git" "diff" "--name-only" "HEAD~1")
                  (error nil)))
         (learning-updated (seq-find (lambda (p) (string-match-p "\\`LEARNING.md\\'" p)) paths)))
    (dolist (rel paths)
      (when (string-match-p "\\`instincts/" rel)
        (my/learning--update-instinct (expand-file-name rel repo))))
    (when learning-updated
      (let* ((learning-path (expand-file-name "LEARNING.md" repo))
             (learning-text (when (file-readable-p learning-path)
                              (with-temp-buffer
                                (insert-file-contents learning-path)
                                (buffer-string))))
             (slugs (when learning-text
                      (let ((pos 0)
                            (refs '()))
                        (while (string-match "^### \\(.+\\)$" learning-text pos)
                          (push (format "LEARNING.md#%s" (match-string 1 learning-text)) refs)
                          (setq pos (match-end 0)))
                        refs))))
        (when slugs
          (let* ((instincts-dir (expand-file-name "instincts" repo))
                 (files (when (file-directory-p instincts-dir)
                          (directory-files-recursively instincts-dir "\\.md\\'"))))
            (dolist (file files)
              (when (and (file-readable-p file)
                         (let* ((text (with-temp-buffer
                                        (insert-file-contents file)
                                        (buffer-string))))
                           (seq-some (lambda (ref)
                                       (string-match-p (regexp-quote ref) text))
                                     slugs)))
                (my/learning--update-instinct file)))))))))

(with-eval-after-load 'git-commit
  (add-hook 'git-commit-finish-hook #'my/learning-auto-evolve-after-commit))

(provide 'gptel-ext-learning)
;;; gptel-ext-learning.el ends here
