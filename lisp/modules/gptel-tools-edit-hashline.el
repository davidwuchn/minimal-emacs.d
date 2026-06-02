;;; gptel-tools-edit-hashline.el --- Hashline content addressing for Edit tool -*- no-byte-compile: t; lexical-binding: t; -*-

;; Author: David Wu
;; Version: 1.0.0
;;
;; Hashline: stable content-addressed line identifiers for reliable editing.
;; Inspired by https://blog.can.ac/2026/02/12/the-harness-problem/
;;
;; Each line gets a hash tag: "line-num:hash|content"
;; Agent references hashes instead of reproducing text.

(require 'cl-lib)
(require 'subr-x)

(defgroup gptel-tools-edit-hashline nil
  "Hashline content addressing for gptel-agent Edit tool."
  :group 'gptel-tools-edit)

(defcustom gptel-tools-edit-hashline-length 2
  "Length of content hash in characters (1-8).
Shorter = more collisions but less context. Longer = more unique but more tokens.
Default 2 chars = ~256 possible hashes, sufficient for most files <1000 lines."
  :type 'integer
  :group 'gptel-tools-edit-hashline)

(defcustom gptel-tools-edit-hashline-algorithm 'md5
  "Hash algorithm for line content.
Options: md5 (fast, good distribution), sha1 (slower, lower collision)."
  :type '(choice (const md5) (const sha1))
  :group 'gptel-tools-edit-hashline)

;;; Core Functions

(defun gptel-tools-edit-hashline--hash (line-text)
  "Compute short hash for LINE-TEXT.
Returns hash string of length `gptel-tools-edit-hashline-length'."
  (let* ((full-hash (if (eq gptel-tools-edit-hashline-algorithm 'sha1)
                        (sha1 line-text)
                      (md5 line-text)))
         (len (min gptel-tools-edit-hashline-length (length full-hash))))
    (downcase (substring full-hash 0 len))))

(defun gptel-tools-edit-hashline--parse-line (line-text line-num)
  "Parse LINE-TEXT at LINE-NUM into hashline format.
Returns string: \"line-num:hash|content\""
  (format "%d:%s|%s"
          line-num
          (gptel-tools-edit-hashline--hash line-text)
          line-text))

(defun gptel-tools-edit-hashline-format-file (file-path &optional start-line end-line)
  "Format FILE-PATH contents with hashline tags.
Returns string with each line prefixed by hashline tag.
Use this when agent reads a file to provide stable edit anchors.
Optional START-LINE and END-LINE specify line range (1-indexed)."
  (with-temp-buffer
    (insert-file-contents file-path)
    (let* ((all-lines (split-string (buffer-string) "\n" t))
           (total-lines (length all-lines))
           (start (max 1 (or start-line 1)))
           (end (min (or end-line total-lines) total-lines))
           (lines (seq-subseq all-lines (1- start) end))
           (result nil)
           (line-num start))
      (dolist (line lines)
        (push (gptel-tools-edit-hashline--parse-line line line-num) result)
        (setq line-num (1+ line-num)))
      (string-join (nreverse result) "\n"))))

(defun gptel-tools-edit-hashline--parse-tag (tag)
  "Parse hashline TAG string.
TAG format: \"line-num:hash\" or \"line-num:hash|content\" (content ignored).
Returns cons: (line-num . hash) or nil if invalid."
  (when (string-match "^\\([0-9]+\\):\\([a-f0-9]+\\)" tag)
    (cons (string-to-number (match-string 1 tag))
          (downcase (match-string 2 tag)))))

(defun gptel-tools-edit-hashline--verify (file-path line-num expected-hash)
  "Verify that line LINE-NUM in FILE-PATH still has EXPECTED-HASH.
Returns t if match, nil if file changed or line doesn't exist."
  (when (and (file-exists-p file-path)
             (> line-num 0))
    (with-temp-buffer
      (insert-file-contents file-path)
      (goto-char (point-min))
      (when (> (count-lines (point-min) (point-max)) 0)
        (forward-line (1- line-num))
        (let ((line-text (buffer-substring-no-properties
                          (line-beginning-position)
                          (line-end-position))))
          (string= expected-hash
                   (gptel-tools-edit-hashline--hash line-text)))))))

;;; Edit Operations

(defun gptel-tools-edit-hashline-replace (file-path tag new-text)
  "Replace line identified by TAG in FILE-PATH with NEW-TEXT.
TAG is hashline tag: \"line-num:hash\".
Returns success message or error string."
  (let ((parsed (gptel-tools-edit-hashline--parse-tag tag)))
    (if (null parsed)
        (format "Error: Invalid hashline tag '%s'. Expected format: line-num:hash" tag)
      (let ((line-num (car parsed))
            (expected-hash (cdr parsed)))
        (if (not (gptel-tools-edit-hashline--verify file-path line-num expected-hash))
            (format "Error: Hash mismatch for tag '%s'. File may have changed since last read.\nACTION: Re-read the file to get current hashline tags." tag)
          (with-temp-buffer
            (insert-file-contents file-path)
            (goto-char (point-min))
            (forward-line (1- line-num))
            (delete-region (line-beginning-position) (line-end-position))
            (insert new-text)
            (write-region (point-min) (point-max) file-path)
            (format "Successfully replaced line %d (hash %s) in %s"
                    line-num expected-hash file-path)))))))

(defun gptel-tools-edit-hashline-replace-range (file-path start-tag end-tag new-text)
  "Replace lines from START-TAG to END-TAG (inclusive) with NEW-TEXT.
Both tags must verify before replacement.
Returns success message or error string."
  (let ((start (gptel-tools-edit-hashline--parse-tag start-tag))
        (end (gptel-tools-edit-hashline--parse-tag end-tag)))
    (cond
     ((null start)
      (format "Error: Invalid start tag '%s'" start-tag))
     ((null end)
      (format "Error: Invalid end tag '%s'" end-tag))
     ((> (car start) (car end))
      (format "Error: Start line %d > end line %d" (car start) (car end)))
     ((not (gptel-tools-edit-hashline--verify file-path (car start) (cdr start)))
      (format "Error: Hash mismatch for start tag '%s'. File may have changed." start-tag))
     ((not (gptel-tools-edit-hashline--verify file-path (car end) (cdr end)))
      (format "Error: Hash mismatch for end tag '%s'. File may have changed." end-tag))
     (t
      (with-temp-buffer
        (insert-file-contents file-path)
        (goto-char (point-min))
        (forward-line (1- (car start)))
        (let ((beg (line-beginning-position)))
          ;; Move to line after end line
          (forward-line (1+ (- (car end) (car start))))
          (delete-region beg (line-beginning-position))
          (insert new-text)
          (unless (string-suffix-p "\n" new-text)
            (insert "\n")))
        (write-region (point-min) (point-max) file-path)
        (format "Successfully replaced lines %d-%d in %s"
                (car start) (car end) file-path))))))

(defun gptel-tools-edit-hashline-insert-after (file-path tag new-text)
  "Insert NEW-TEXT after line identified by TAG in FILE-PATH.
Returns success message or error string."
  (let ((parsed (gptel-tools-edit-hashline--parse-tag tag)))
    (if (null parsed)
        (format "Error: Invalid hashline tag '%s'" tag)
      (let ((line-num (car parsed))
            (expected-hash (cdr parsed)))
        (if (not (gptel-tools-edit-hashline--verify file-path line-num expected-hash))
            (format "Error: Hash mismatch for tag '%s'. File may have changed." tag)
          (with-temp-buffer
            (insert-file-contents file-path)
            (goto-char (point-min))
            (forward-line line-num)
            (insert new-text)
            (unless (string-suffix-p "\n" new-text)
              (insert "\n"))
            (write-region (point-min) (point-max) file-path)
            (format "Successfully inserted after line %d in %s"
                    line-num file-path)))))))

;;; Tool Registration

(defun gptel-tools-edit-hashline-register ()
  "Register hashline-enhanced Edit tool with gptel."
  (when (fboundp 'gptel-make-tool)
    ;; Register the read helper (not a tool itself, but used by Read)
    ;; Register hashline edit operations as tool variants
    (message "[hashline] Hashline content addressing loaded")))

(provide 'gptel-tools-edit-hashline)
;;; gptel-tools-edit-hashline.el ends here
