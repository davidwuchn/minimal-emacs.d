;;; gptel-tools.el --- Tool registry for gptel -*- no-byte-compile: t; lexical-binding: t; -*-

;; Author: David Wu
;; Version: 1.1.0
;;
;; Main tool registry that loads and registers all gptel tools.

(require 'cl-lib)
(require 'subr-x)
(require 'seq)

(declare-function gptel--file-binary-p "gptel-request")

;;; Hooks

(defvar gptel-tools-after-register-hook nil
  "Hook run after `gptel-tools-register-all' completes.
Use this to refresh presets or update buffers that depend on tool availability.")

;; Load individual tool modules
;; Load gptel-tools-code BEFORE gptel-tools-agent because the latter
;; triggers gptel-agent loading via eval-and-compile, which runs the
;; with-eval-after-load callbacks that need gptel-tools-code-register.
(require 'gptel-tools-bash)
(require 'gptel-tools-grep)
(require 'gptel-tools-glob)
(require 'gptel-tools-edit)
(require 'gptel-tools-apply)
(require 'gptel-tools-preview)
(require 'gptel-tools-programmatic)
(require 'gptel-tools-introspection)
(require 'gptel-tools-code)
(require 'gptel-tools-agent)
;; (require 'gptel-tools-lsp)  ; Deprecated, functionality merged into gptel-tools-code
;; (require 'gptel-tools-ast)  ; Deprecated, functionality merged into gptel-tools-code

;;; Customization

(defgroup gptel-tools nil
  "Tool registry and management for gptel-agent."
  :group 'gptel)

(defun gptel-tools--eval-expression (expression)
  "Evaluate Elisp EXPRESSION and return result plus any captured stdout."
  (let ((standard-output (generate-new-buffer " *gptel-eval*"))
        (safe-default-directory
         (or (and (stringp default-directory)
                  default-directory)
             (and (stringp temporary-file-directory)
                  temporary-file-directory)
             user-emacs-directory))
        (result nil)
        (output nil))
    (unwind-protect
        (condition-case err
            (let ((default-directory safe-default-directory))
              (setq result (eval (read expression) t))
              (when (> (buffer-size standard-output) 0)
                (setq output (with-current-buffer standard-output (buffer-string))))
              (concat (format "Result:\n%S" result)
                      (and output (format "\n\nSTDOUT:\n%s" output))))
          ((error user-error)
           (concat (format "Error: %S: %S" (car err) (cdr err))
                   (and output (format "\n\nSTDOUT:\n%s" output)))))
      (kill-buffer standard-output))))

(defun gptel-tools-register-all ()
  "Register all gptel tools.

Call this after gptel-agent-tools loads."
  ;; Register individual tool modules
  (gptel-tools-bash-register)
  (gptel-tools-grep-register)
  (gptel-tools-glob-register)
  (gptel-tools-edit-register)
  (gptel-tools-apply-register)
  (gptel-tools-preview-register)
  (gptel-tools-programmatic-register)
  (gptel-tools-introspection-register)
  (gptel-tools-code-register)
  ;; (gptel-tools-lsp-register)  ; Deprecated by gptel-tools-code
  ;; (gptel-tools-ast-register)  ; Deprecated by gptel-tools-code
  (gptel-tools-agent-register)

  ;; Register standard gptel-agent tools
  (when (fboundp 'gptel-make-tool)
    ;; Invalid tool - catches malformed tool calls from models
    (gptel-make-tool
     :name "invalid"
     :function (lambda (tool error)
                 "Handle invalid/malformed tool calls from the model."
                 (format "Error: Invalid tool call. Tool: %s. Error: %s" tool error))
     :description "Internal tool for handling malformed tool calls. Do not call directly."
     :args '((:name "tool" :type string)
             (:name "error" :type string))
     :category "gptel-agent"
     :include nil)

    ;; Write tool
    (gptel-make-tool
     :name "Write"
     :category "gptel-agent"
     :function (lambda (path filename content)
                 "Create a new file safely. Refuses to overwrite existing files."
                 (let ((filepath (expand-file-name filename path)))
                   (if (file-exists-p filepath)
                       (error "File already exists: %s. Use Edit or Insert instead." filepath)
                     (with-temp-file filepath (insert content)))
                   (format "Created new file: %s" filepath)))
     :description "Create a new file with the specified content. SAFETY: refuses to overwrite existing files."
     :args '((:name "path" :type string :description "Directory path")
             (:name "filename" :type string :description "File name")
             (:name "content" :type string :description "Content"))
     :confirm t
     :include t)

    ;; Read tool (supports PDF extraction via pdftotext)
    (gptel-make-tool
     :name "Read"
     :function #'my/gptel--read-file-safe
     :description "Read file contents by line range. PDF files are extracted as text. Other binary files (images, archives) are rejected."
     :args '((:name "file_path" :type string)
             (:name "start_line" :type integer :optional t)
             (:name "end_line" :type integer :optional t))
     :category "gptel-agent"
     :include t)

    ;; Insert tool
    (gptel-make-tool
     :name "Insert"
     :function #'gptel-agent--insert-in-file
     :description "Insert text at a line number in a file."
     :args '((:name "file_path" :type string :description "Path to the file")
             (:name "line_number" :type integer)
             (:name "new_str" :type string))
     :category "gptel-agent"
     :confirm t
     :include t)

    ;; Mkdir tool
    (gptel-make-tool
     :name "Mkdir"
     :function #'gptel-agent--make-directory
     :description "Create a directory under a parent directory."
     :args '((:name "parent" :type string)
             (:name "name" :type string))
     :category "gptel-agent"
     :confirm t
     :include t)

    ;; Move tool
    (gptel-make-tool
     :name "Move"
     :function (lambda (source dest)
                 (let ((src (expand-file-name source))
                       (dst (expand-file-name dest)))
                   (if (not (file-exists-p src))
                       (error "Source file does not exist: %s" src)
                     (rename-file src dst t)
                     (format "Moved %s to %s" src dst))))
     :description "Move or rename a file safely."
     :args '((:name "source" :type string :description "Source file path")
             (:name "dest" :type string :description "Destination file path"))
     :category "gptel-agent"
     :confirm t
     :include t)

    ;; Eval tool
    (gptel-make-tool
     :name "Eval"
     :function #'gptel-tools--eval-expression
     :description "Evaluate a single Elisp expression."
     :args '((:name "expression" :type string))
     :category "gptel-agent"
     :confirm t
     :include t)

    ;; WebSearch tool (with error handling)
    (gptel-make-tool
     :name "WebSearch"
     :function #'my/gptel-web-search-safe
     :description "Search the web (returns top results)."
     :args '((:name "query" :type string)
             (:name "count" :type integer :optional t))
     :include t
     :async t
     :category "gptel-agent")

    ;; WebFetch tool (with error handling)
    (gptel-make-tool
     :name "WebFetch"
     :function #'my/gptel-web-fetch-safe
     :description "Fetch and read the text of a URL."
     :args '((:name "url" :type string))
     :async t
     :include t
     :category "gptel-agent")

    ;; YouTube tool
    (gptel-make-tool
     :name "YouTube"
     :function #'gptel-agent--yt-read-url
     :description "Fetch YouTube description and transcript."
     :args '((:name "url" :type string))
     :category "gptel-agent"
     :async t
     :include t)

    ;; TodoWrite tool
    (gptel-make-tool
     :name "TodoWrite"
     :function #'gptel-agent--write-todo
     :description "Update a session todo list. IMPORTANT: This is a tracking tool only. After calling TodoWrite, immediately continue executing the tasks. Do not stop or wait for user input after creating a todo list."
     :args '((:name "todos"
                    :type array
                    :items (:type object
                                  :properties (:content (:type string :minLength 1)
                                                        :status (:type string :enum ["pending" "in_progress" "completed"])
                                                        :activeForm (:type string :minLength 1 :optional t)))))
     :category "gptel-agent"
     :include nil)

    ;; Skill creation tool (gptel-agent provides Skill tool for loading)
    (gptel-make-tool
     :name "create_skill"
     :function (lambda (skill-name user-prompt &optional dir)
                 (let* ((dir (or dir (expand-file-name "assistant/skills/" user-emacs-directory)))
                        (skill-dir (expand-file-name skill-name dir)))
                   (unless (file-directory-p dir)
                     (make-directory dir t))
                   (unless (file-directory-p skill-dir)
                     (make-directory skill-dir t))
                   (with-temp-file (expand-file-name "SKILL.md" skill-dir)
                     (insert (format "# Skill: %s\n\n%s\n" skill-name user-prompt)))
                   (format "Created skill: %s" skill-dir)))
     :description "Create a new skill with the given name and prompt."
     :args '((:name "skillName" :type string)
             (:name "userPrompt" :type string)
             (:name "dir" :type string :optional t))
     :category "gptel-agent"
     :confirm t))

  ;; Default toolset is set by nucleus-sync-tool-profile in gptel-mode-hook.
  ;; Use (nucleus-get-tools :readonly) or (nucleus-get-tools :nucleus) directly.
  )

;;; Utility Functions

(defun my/gptel--read-file-safe (file-path &optional start-line end-line)
  "Read FILE-PATH safely, extracting text from PDFs, rejecting other binary files.
START-LINE and END-LINE specify the line range to read.
PDF files are extracted using pdftotext if available."
  (let ((path (expand-file-name file-path)))
    (cond
     ((not (file-readable-p path))
      (error "Error: File %s is not readable" path))
     ((file-directory-p path)
      (error "Error: Cannot read directory %s as file" path))
     ((string-match-p "\\.pdf\\'" path)
      (my/gptel--extract-pdf-text path start-line end-line))
     ((or (string-match-p "\\.\\(jpe?g\\|png\\|gif\\|webp\\|zip\\|tar\\|gz\\|exe\\|dll\\|so\\|dylib\\)\\'" path)
          (and (fboundp 'gptel--file-binary-p) (gptel--file-binary-p path)))
      (format "Error: Binary file detected (%s). Use appropriate tools for binary files."
              (or (file-name-extension path) "unknown type")))
     (t
      (gptel-agent--read-file-lines path start-line end-line)))))

(defun my/gptel--extract-pdf-text (path &optional start-line end-line)
  "Extract text from PDF at PATH using pdftotext.
START-LINE and END-LINE specify the line range to return."
  (let ((pdftotext (executable-find "pdftotext")))
    (if (not pdftotext)
        (format "Error: pdftotext not found. Install with: brew install poppler")
      (let ((text (with-temp-buffer
                    (call-process pdftotext nil t nil "-layout" path "-")
                    (buffer-string))))
        (if (string-empty-p (string-trim text))
            (format "Error: Could not extract text from PDF: %s" (file-name-nondirectory path))
           (let* ((lines (split-string text "\n"))
                  (total-lines (length lines))
                  (start (or start-line 1))
                  (end (min (or end-line total-lines) total-lines)))
             (cond
              ((< start 1)
               (format "Error: start-line %d is invalid (must be >= 1)" start-line))
              ((> start total-lines)
               (format "Error: start-line %d exceeds total lines (%d)" start-line total-lines))
              ((> (or end-line 0) total-lines)
               (format "Error: end-line %d exceeds total lines (%d)" end-line total-lines))
              ((> start end)
               (format "Error: start-line (%d) exceeds end-line (%d)" start-line end-line))
              (t
               (let ((page-count (max 1 (1+ (cl-count ?\f text)))))
                 (format "PDF: %s (%d pages, %d lines)\n\n%s"
                         (file-name-nondirectory path)
                         page-count
                         total-lines
                         (string-join (seq-subseq lines (1- start) end) "\n")))))))))))

(defun my/gptel-web-search-safe (tool-cb query &optional count)
  "Web search with error handling.
Wraps `gptel-agent--web-search-eww' with better error recovery."
  (condition-case err
      (gptel-agent--web-search-eww
       (lambda (result)
         (cond
          ((null result)
           (funcall tool-cb "WebSearch returned no results."))
          ((and (stringp result) (string-match-p "^Error:" result))
           (funcall tool-cb result))
          ((stringp result)
           (funcall tool-cb result))
          (t
           (funcall tool-cb (format "WebSearch: unexpected result type: %s" (type-of result))))))
       query count)
    (error
     (funcall tool-cb (format "WebSearch error: %s" (error-message-string err))))))

(defun my/gptel-web-fetch-safe (tool-cb url)
  "Web fetch with error handling.
Wraps `gptel-agent--read-url' with better error recovery."
  (condition-case err
      (gptel-agent--read-url
       (lambda (result)
         (cond
          ((null result)
           (funcall tool-cb "WebFetch returned no content."))
          ((and (stringp result) (string-match-p "^Error:" result))
           (funcall tool-cb result))
          ((stringp result)
           (funcall tool-cb result))
          (t
           (funcall tool-cb (format "WebFetch: unexpected result type: %s" (type-of result))))))
       url)
    (error
     (funcall tool-cb (format "WebFetch error: %s" (error-message-string err))))))

;;; Advice for gptel-agent web search callback

(defun my/gptel--around-web-search-eww-callback (orig-fn cb)
  "Advice around `gptel-agent--web-search-eww-callback' with error handling."
  (condition-case err
      (if (and (boundp 'url-http-end-of-headers)
               url-http-end-of-headers)
          (funcall orig-fn cb)
        (funcall cb "Error: HTTP response headers not found. The search may have failed or been blocked."))
    (error
     (funcall cb (format "Error parsing search results: %s" (error-message-string err))))))

;;; Integration

(defun gptel-tools-setup ()
  "Setup gptel tools.

Call this after gptel-agent-tools loads.
Runs `gptel-tools-after-register-hook' after registration."
  ;; Add error handling advice to web search callback
  (advice-add 'gptel-agent--web-search-eww-callback :around
              #'my/gptel--around-web-search-eww-callback)
  (gptel-tools-register-all)
  (run-hooks 'gptel-tools-after-register-hook))

;;; Footer

(provide 'gptel-tools)

;;; Auto-initialization

(with-eval-after-load 'gptel-agent-tools
  (gptel-tools-setup))

;;; gptel-tools.el ends here
