;;; gptel-ext-transient.el --- Transient menu fixes and crowdsourced prompts -*- no-byte-compile: t; lexical-binding: t; -*-

;;; Commentary:
;; Fix gptel-system-prompt transient losing the originating buffer.
;; Filter directives based on agent/plan vs regular gptel mode.
;; Replace upstream CSV parser for crowdsourced prompts with RFC-4180 compliant version.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'gptel)

(defvar nucleus-hidden-directives) ; defined in nucleus-presets.el

;; Fix: gptel-system-prompt transient doesn't preserve the originating buffer.
;; When the [Prompt:] header button is clicked, gptel-system-prompt opens a
;; transient.  By the time the suffix fires, current-buffer may be a different
;; window's buffer.  We capture the gptel buffer at click time and pass it
;; explicitly to gptel--edit-directive via :buffer.

(defvar gptel--set-buffer-locally)          ; defined in gptel-transient
(declare-function gptel--set-with-scope "gptel-transient")
(declare-function gptel--edit-directive "gptel-transient")
(declare-function gptel--crowdsourced-prompts "gptel-transient")

(defun my/gptel--suffix-system-message-in-buffer (orig &optional cancel)
  "Around-advice for `gptel--suffix-system-message': use originating gptel buffer.
Also ensures the system message is applied buffer-locally, not globally."
  (if cancel
      (funcall orig cancel)
    (let* ((buf (or (and (boundp 'my/gptel--transient-origin-buffer)
                         (buffer-live-p my/gptel--transient-origin-buffer)
                         my/gptel--transient-origin-buffer)
                    (current-buffer)))
           ;; Force buffer-local scope so C-c C-c writes to buf only,
           ;; not globally (gptel--set-buffer-locally defaults to nil
           ;; when opened from header-line rather than gptel-menu).
           (gptel--set-buffer-locally t))
      (with-current-buffer buf
        (gptel--edit-directive 'gptel--system-message
          :setup #'activate-mark
          :buffer buf
          :callback (lambda (_) (call-interactively #'gptel-menu)))))))

(defvar my/gptel--transient-origin-buffer nil
  "Buffer that opened the gptel-system-prompt transient.")

(defvar my/gptel--transient-origin-preset nil
  "Preset from the buffer that opened the gptel-system-prompt transient.
Used to show different directive menus for gptel-agent vs regular gptel.")

(with-eval-after-load 'gptel-transient
  (advice-add 'gptel--setup-directive-menu
              :around #'my/gptel--filter-directive-menu)
  (advice-add 'gptel-system-prompt :before
              (lambda (&rest _)
                (setq my/gptel--transient-origin-buffer (current-buffer))
                (setq my/gptel--transient-origin-preset
                      (and (boundp 'gptel--preset) gptel--preset))))
  (advice-add 'gptel--suffix-system-message
              :around #'my/gptel--suffix-system-message-in-buffer))

(defvar gptel-directives)

(defun my/gptel--filter-directive-menu (orig sym msg &optional external)
  "Around-advice: filter directives based on whether we're in gptel-agent or regular gptel.
For gptel-agent/gptel-plan buffers: show only nucleus-gptel-agent and nucleus-gptel-plan.
For regular gptel buffers: show all directives except hidden ones."
  (let* ((is-agent-buffer (memq my/gptel--transient-origin-preset '(gptel-plan gptel-agent)))
         (filtered
          (if is-agent-buffer
              (seq-filter (lambda (e) (memq (car e) '(nucleus-gptel-plan nucleus-gptel-agent)))
                          gptel-directives)
            (seq-remove (lambda (e) (memq (car e) (if (boundp 'nucleus-hidden-directives) nucleus-hidden-directives nil)))
                        gptel-directives)))
         (old-directives gptel-directives))
    (unwind-protect
        (progn
          (setq gptel-directives filtered)
          (funcall orig sym msg external))
      (setq gptel-directives old-directives))))


(defun my/gptel--csv-parse-row ()
  "Parse one RFC-4180 CSV row at point, return list of field strings.
Handles quoted fields with embedded newlines and escaped double-quotes.
Advances point to the start of the next row."
  (let (fields)
    (while (not (or (eobp) (and fields (eolp))))
      (let ((field
             (if (eq (char-after) ?\")
                 ;; Quoted field: scan for closing unescaped quote
                 (let ((start (1+ (point))) result)
                   (forward-char 1)           ; skip opening "
                   (while (not result)
                     (if (not (search-forward "\"" nil t))
                         (setq result "")     ; unterminated — give up
                       (if (eq (char-after) ?\")
                           (forward-char 1)   ; "" → escaped quote, continue
                         (setq result         ; found real closing quote
                               (buffer-substring-no-properties
                                start (1- (point)))))))
                   ;; Skip trailing comma if present
                   (when (eq (char-after) ?,) (forward-char 1))
                   (string-replace "\"\"" "\"" result))
               ;; Unquoted field: read until comma or EOL
               (let ((start (point)))
                 (skip-chars-forward "^,\n")
                 (prog1 (buffer-substring-no-properties start (point))
                   (when (eq (char-after) ?,) (forward-char 1)))))))
        (push field fields)))
    ;; Skip EOL
    (when (eolp) (forward-char 1))
    (nreverse fields)))

(with-eval-after-load 'gptel-transient
  ;; Cleaner picker: show only a short single-line preview instead of the
  ;; full multi-line prompt as annotation (which makes selection unusable).
  (defun gptel--read-crowdsourced-prompt ()
    "Pick a crowdsourced system prompt for gptel (clean single-line preview)."
    (interactive)
    (if (not (hash-table-empty-p (gptel--crowdsourced-prompts)))
        (let ((choice
               (completing-read
                "Pick and edit prompt: "
                (lambda (str pred action)
                  (if (eq action 'metadata)
                      `(metadata
                        (affixation-function .
                                             (lambda (cands)
                                               (mapcar
                                                (lambda (c)
                                                  (let* ((full (gethash c gptel--crowdsourced-prompts))
                                                         (preview (truncate-string-to-width
                                                                   (replace-regexp-in-string
                                                                    "[\n\r]+" " " (or full ""))
                                                                   60 nil nil "…")))
                                                    (list c ""
                                                          (concat (propertize " " 'display '(space :align-to 36))
                                                                  (propertize preview 'face 'completions-annotations)))))
                                                cands))))
                    (complete-with-action action gptel--crowdsourced-prompts str pred)))
                nil t)))
          (when-let* ((prompt (gethash choice gptel--crowdsourced-prompts)))
            (gptel--set-with-scope
             'gptel--system-message prompt gptel--set-buffer-locally)
            (gptel--edit-directive 'gptel--system-message
              :callback (lambda (_) (call-interactively #'gptel-menu)))))
      (message "No prompts available.")))

  ;; Replace upstream gptel--crowdsourced-prompts with a version that uses
  ;; a correct RFC-4180 parser.  The upstream gptel--read-csv-column fails on
  ;; multi-line quoted fields (common in awesome-chatgpt-prompts CSV).
  (defun gptel--crowdsourced-prompts ()
    "Acquire and read crowdsourced LLM system prompts (RFC-4180 fix)."
    (when (hash-table-p gptel--crowdsourced-prompts)
      (when (hash-table-empty-p gptel--crowdsourced-prompts)
        (unless gptel-crowdsourced-prompts-file
          (run-at-time 0 nil #'gptel-system-prompt)
          (user-error "No crowdsourced prompts available"))
        (unless (and (file-exists-p gptel-crowdsourced-prompts-file)
                     (time-less-p
                      (time-subtract (current-time) (days-to-time 14))
                      (file-attribute-modification-time
                       (file-attributes gptel-crowdsourced-prompts-file))))
          (when (y-or-n-p
                 (concat "Fetch crowdsourced system prompts from "
                         (propertize "https://github.com/f/awesome-chatgpt-prompts"
                                     'face 'link) "?"))
            (message "Fetching prompts...")
            (let ((dir (file-name-directory gptel-crowdsourced-prompts-file)))
              (unless (file-exists-p dir) (mkdir dir 'create-parents))
              (if (url-copy-file gptel--crowdsourced-prompts-url
                                 gptel-crowdsourced-prompts-file t)
                  (message "Fetching prompts... done.")
                (message "Could not retrieve new prompts.")))))
        (if (not (file-readable-p gptel-crowdsourced-prompts-file))
            (progn (message "No crowdsourced prompts available")
                   (call-interactively #'gptel-system-prompt))
          (with-temp-buffer
            (insert-file-contents gptel-crowdsourced-prompts-file)
            (goto-char (point-min))
            (my/gptel--csv-parse-row)          ; skip header row
            (while (not (eobp))
              (let* ((row (my/gptel--csv-parse-row))
                     (act (car row))
                     (prompt (cadr row)))
                (when (and (stringp act)   (not (string-empty-p act))
                           (stringp prompt)(not (string-empty-p prompt)))
                  (puthash act prompt gptel--crowdsourced-prompts)))))))
      gptel--crowdsourced-prompts)))

(provide 'gptel-ext-transient)
;;; gptel-ext-transient.el ends here
