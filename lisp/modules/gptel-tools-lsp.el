;;; gptel-tools-lsp.el --- LSP tools for gptel -*- lexical-binding: t; -*-

;; Author: David Wu
;; Version: 1.0.0
;;
;; LSP integration tools for gptel-agent via Eglot and Flymake.

(require 'cl-lib)
(require 'jsonrpc)
(require 'eglot)
(require 'flymake)
(require 'project)
(require 'seq)

;;; Customization

(defgroup gptel-tools-lsp nil
  "LSP tool integrations for gptel-agent."
  :group 'gptel)

;;; Internal Helpers

(defun my/gptel-lsp--get-expected-executables (mode)
  "Get a list of expected executable names for MODE from `eglot-server-programs'."
  (let ((found nil))
    (dolist (entry eglot-server-programs)
      (let ((modes (car entry))
            (server (cdr entry)))
        (when (if (listp modes) (memq mode modes) (eq mode modes))
          (setq found
                (cond
                 ;; ("server" "--arg")
                 ((and (listp server) (stringp (car server)))
                  (list (car server)))
                 ;; "server"
                 ((stringp server)
                  (list server))
                 ;; ((("server" "--arg") ("server2"))) -> ("server" "server2")
                 ((and (listp server) (listp (car server)) (stringp (caar server)))
                  (mapcar #'car server))
                 ;; Dynamic/Byte-code (e.g. python, c++)
                 ((or (byte-code-function-p server) (functionp server))
                  '("<dynamic-resolution>"))
                 (t '("<unknown>")))))))
    found))

(defun my/gptel-lsp--format-missing-server-error (path)
  "Format a detailed error message indicating a missing LSP server for PATH."
  (let* ((buf (or (find-buffer-visiting path)
                  (find-file-noselect path)))
         (mode (and buf (buffer-local-value 'major-mode buf)))
         (execs (and mode (my/gptel-lsp--get-expected-executables mode))))
    (if execs
        (format "Error: No active Eglot server found for %s. The server could not be started automatically. Eglot expects one of the following executables for `%s': %s. Please ensure the appropriate language server is installed and available in your PATH."
                path mode (string-join execs ", "))
      (format "Error: No active Eglot server found for %s. The server could not be started automatically (is the required language server executable installed?)." path))))

(defun my/gptel-lsp--get-server (path &optional auto-start)
  "Get the active Eglot server for PATH, reliably.
If AUTO-START is non-nil and PATH is provided, attempt to start Eglot
automatically in the background if it is not already running."
  (let* ((proj (project-current nil path))
         (servers (and proj (hash-table-values eglot--servers-by-project)))
         (buf (and path (find-buffer-visiting path)))
         (server (if buf
                     (with-current-buffer buf (eglot-current-server))
                   (or (cl-find-if
                        (lambda (s)
                          (let ((s-proj (eglot--project s)))
                            (and s-proj
                                 (equal (project-root s-proj)
                                        (project-root proj)))))
                        servers)
                       (eglot-current-server)))))
    
    (if (and server (jsonrpc-running-p server))
        server
      (if (and auto-start path (file-exists-p path))
          (let* ((new-buf (find-file-noselect path))
                 (new-server (with-current-buffer new-buf
                               (let ((noninteractive t))
                                 (ignore-errors (eglot-ensure)))
                               (eglot-current-server))))
            (if (and new-server (jsonrpc-running-p new-server))
                new-server
              nil))
        nil))))

(defun my/gptel-lsp--path-to-uri (path)
  "Convert PATH to a file URI."
  (concat "file://" (expand-file-name path)))

(defun my/gptel-lsp--uri-to-path (uri)
  "Convert URI to a file path."
  (if (string-prefix-p "file://" uri)
      (substring uri 7)
    uri))

(defun my/gptel-lsp--format-location (loc)
  "Format an LSP Location or LocationLink object LOC into a readable string."
  (let* ((uri (or (plist-get loc :uri)
                  (plist-get loc :targetUri)))
         (range (or (plist-get loc :range)
                    (plist-get loc :targetSelectionRange)))
         (start (plist-get range :start))
         (line (plist-get start :line))
         (char (plist-get start :character))
         (path (my/gptel-lsp--uri-to-path uri)))
    (format "%s:%d:%d" path line char))) ; Keep 0-indexed for agent output

;;; Tool Implementations

(cl-defun my/gptel-lsp-diagnostics (callback)
  "Get project-wide diagnostics from Flymake."
  (unless (fboundp 'flymake--project-diagnostics)
    (funcall callback "Error: flymake--project-diagnostics not available (requires Emacs 29+)")
    (cl-return-from my/gptel-lsp-diagnostics))
  
  (let* ((proj (project-current))
         (servers (and proj (hash-table-values eglot--servers-by-project)))
         (active-server (cl-find-if (lambda (s) (and (equal (project-root (eglot--project s)) (project-root proj))
                                                     (jsonrpc-running-p s)))
                                    servers)))
    (unless active-server
      (funcall callback "Error: No active LSP server found for the current project. Cannot verify diagnostics. Ensure a file is open and the language server is running.")
      (cl-return-from my/gptel-lsp-diagnostics))

    (let ((diags (flymake--project-diagnostics proj)))
      (if (not diags)
          (funcall callback "No diagnostics found for the current project.")
        (let ((formatted
               (mapcar (lambda (d)
                         (let ((buf (flymake-diagnostic-buffer d))
                               (text (flymake-diagnostic-text d))
                               (type (flymake-diagnostic-type d))
                               (beg (flymake-diagnostic-beg d)))
                           (with-current-buffer buf
                             (save-excursion
                               (goto-char beg)
                               (format "%s:%d:%d [%s] %s"
                                       (buffer-file-name buf)
                                       (1- (line-number-at-pos)) ; 0-indexed line
                                       (current-column)          ; 0-indexed char
                                       type text)))))
                       diags)))
          (funcall callback (string-join formatted "\n")))))))

(cl-defun my/gptel-lsp-references (callback file-path line character)
  "Get LSP references for the symbol at FILE-PATH, LINE, CHARACTER (0-indexed)."
  (let ((server (my/gptel-lsp--get-server file-path t)))
    (unless server
      (funcall callback (my/gptel-lsp--format-missing-server-error file-path))
      (cl-return-from my/gptel-lsp-references))
    
    (jsonrpc-async-request
     server
     :textDocument/references
     (list :textDocument (list :uri (my/gptel-lsp--path-to-uri file-path))
           :position (list :line line :character character)
           :context (list :includeDeclaration t))
     :success-fn (lambda (res)
                   (if (not res)
                       (funcall callback "No references found.")
                     (let ((formatted (mapcar #'my/gptel-lsp--format-location res)))
                       (funcall callback (string-join formatted "\n")))))
     :error-fn (lambda (err)
                 (funcall callback (format "LSP Error: %s" (plist-get err :message))))
     :timeout-fn (lambda ()
                   (funcall callback (format "LSP textDocument/references request for '%s' timed out." file-path))))))

(cl-defun my/gptel-lsp-definition (callback file-path line character)
  "Get LSP definition for the symbol at FILE-PATH, LINE, CHARACTER (0-indexed)."
  (let ((server (my/gptel-lsp--get-server file-path t)))
    (unless server
      (funcall callback (my/gptel-lsp--format-missing-server-error file-path))
      (cl-return-from my/gptel-lsp-definition))
    
    (jsonrpc-async-request
     server
     :textDocument/definition
     (list :textDocument (list :uri (my/gptel-lsp--path-to-uri file-path))
           :position (list :line line :character character))
     :success-fn (lambda (res)
                   (if (not res)
                       (funcall callback "No definition found.")
                     (let* ((res-list (if (vectorp res) (append res nil) (list res)))
                            (formatted (mapcar #'my/gptel-lsp--format-location res-list)))
                       (funcall callback (string-join formatted "\n")))))
     :error-fn (lambda (err)
                 (funcall callback (format "LSP Error: %s" (plist-get err :message))))
     :timeout-fn (lambda ()
                   (funcall callback (format "LSP textDocument/definition request for '%s' timed out." file-path))))))

(cl-defun my/gptel-lsp-hover (callback file-path line character)
  "Get LSP hover info for the symbol at FILE-PATH, LINE, CHARACTER (0-indexed)."
  (let ((server (my/gptel-lsp--get-server file-path t)))
    (unless server
      (funcall callback (my/gptel-lsp--format-missing-server-error file-path))
      (cl-return-from my/gptel-lsp-hover))
    
    (jsonrpc-async-request
     server
     :textDocument/hover
     (list :textDocument (list :uri (my/gptel-lsp--path-to-uri file-path))
           :position (list :line line :character character))
     :success-fn (lambda (res)
                   (if (not res)
                       (funcall callback "No hover information found.")
                     (let* ((contents (plist-get res :contents))
                            (val (cond
                                  ((stringp contents) contents)
                                  ((and (listp contents) (plist-get contents :value))
                                   (plist-get contents :value))
                                  ((and (listp contents) (stringp (car contents)))
                                   (string-join contents "\n"))
                                  (t (format "%S" contents)))))
                       (funcall callback val))))
     :error-fn (lambda (err)
                 (funcall callback (format "LSP Error: %s" (plist-get err :message))))
     :timeout-fn (lambda ()
                   (funcall callback (format "LSP textDocument/hover request for '%s' timed out." file-path))))))

(cl-defun my/gptel-lsp-rename (callback file-path line character new-name)
  "Rename symbol at FILE-PATH, LINE, CHARACTER (0-indexed) to NEW-NAME."
  (let ((server (my/gptel-lsp--get-server file-path t)))
    (unless server
      (funcall callback (my/gptel-lsp--format-missing-server-error file-path))
      (cl-return-from my/gptel-lsp-rename))
    
    (jsonrpc-async-request
     server
     :textDocument/rename
     (list :textDocument (list :uri (my/gptel-lsp--path-to-uri file-path))
           :position (list :line line :character character)
           :newName new-name)
     :success-fn (lambda (res)
                   (if (not res)
                       (funcall callback "No rename edits returned by server.")
                     (condition-case err
                         (progn
                           ;; Apply workspace edit without user confirmation for agents
                           (eglot--apply-workspace-edit res nil)
                           (funcall callback (format "Successfully applied rename to '%s'." new-name)))
                       (error
                        (funcall callback (format "Failed to apply rename edit: %s" (error-message-string err)))))))
     :error-fn (lambda (err)
                 (funcall callback (format "LSP Error: %s" (plist-get err :message))))
     :timeout-fn (lambda ()
                   (funcall callback (format "LSP textDocument/rename request for '%s' timed out." file-path))))))

(cl-defun my/gptel-lsp-workspace-symbol (callback query)
  "Query workspace symbols for QUERY."
  (let ((server (my/gptel-lsp--get-server default-directory)))
    (unless server
      (funcall callback "Error: No active Eglot server found for the current project")
      (cl-return-from my/gptel-lsp-workspace-symbol))
    
    (jsonrpc-async-request
     server
     :workspace/symbol
     (list :query query)
     :success-fn (lambda (res)
                   (if (not res)
                       (funcall callback "No symbols found.")
                     (let ((formatted
                            (mapcar (lambda (sym)
                                      (let* ((name (plist-get sym :name))
                                             (kind (plist-get sym :kind))
                                             (loc (plist-get sym :location))
                                             (loc-str (my/gptel-lsp--format-location loc)))
                                        (format "[%s] %s -> %s" kind name loc-str)))
                                    res)))
                       (funcall callback (string-join formatted "\n")))))
     :error-fn (lambda (err)
                 (funcall callback (format "LSP Error: %s" (plist-get err :message))))
     :timeout-fn (lambda ()
                   (funcall callback (format "LSP workspace/symbol request for '%s' timed out." query))))))

;;; Tool Registration

(defun gptel-tools-lsp-register ()
  "Register LSP tools with gptel."
  (when (fboundp 'gptel-make-tool)
    (gptel-make-tool
     :name "lsp_diagnostics"
     :description "Get project-wide diagnostics/errors from the LSP server."
     :function #'my/gptel-lsp-diagnostics
     :args nil
     :category "gptel-agent"
     :async t
     :include t)

    (gptel-make-tool
     :name "lsp_references"
     :description "Find references for a symbol at a specific file, line, and character (0-indexed)."
     :function #'my/gptel-lsp-references
     :args '((:name "file_path" :type string)
             (:name "line" :type integer :description "0-indexed line number")
             (:name "character" :type integer :description "0-indexed character position"))
     :category "gptel-agent"
     :async t
     :include t)

    (gptel-make-tool
     :name "lsp_definition"
     :description "Find the definition of a symbol at a specific file, line, and character (0-indexed)."
     :function #'my/gptel-lsp-definition
     :args '((:name "file_path" :type string)
             (:name "line" :type integer :description "0-indexed line number")
             (:name "character" :type integer :description "0-indexed character position"))
     :category "gptel-agent"
     :async t
     :include t)

    (gptel-make-tool
     :name "lsp_hover"
     :description "Get type information, signature, and documentation for a symbol at a specific file, line, and character (0-indexed)."
     :function #'my/gptel-lsp-hover
     :args '((:name "file_path" :type string)
             (:name "line" :type integer :description "0-indexed line number")
             (:name "character" :type integer :description "0-indexed character position"))
     :category "gptel-agent"
     :async t
     :include t)

    (gptel-make-tool
     :name "lsp_rename"
     :description "Rename a symbol globally across the workspace using the LSP server."
     :function #'my/gptel-lsp-rename
     :args '((:name "file_path" :type string)
             (:name "line" :type integer :description "0-indexed line number")
             (:name "character" :type integer :description "0-indexed character position")
             (:name "new_name" :type string :description "The new name for the symbol"))
     :category "gptel-agent"
     :async t
     :confirm t
     :include t)

    (gptel-make-tool
     :name "lsp_workspace_symbol"
     :description "Search for symbols across the entire workspace/project."
     :function #'my/gptel-lsp-workspace-symbol
     :args '((:name "query" :type string))
     :category "gptel-agent"
     :async t
     :include t)))

(provide 'gptel-tools-lsp)

;;; gptel-tools-lsp.el ends here
