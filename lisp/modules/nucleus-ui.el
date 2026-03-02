;;; nucleus-ui.el --- UI components for nucleus -*- lexical-binding: t; -*-

;; Author: David Wu
;; Version: 1.0.0
;;
;; Header-line and modeline UI components for nucleus.

(require 'subr-x)

;;; Customization

(defgroup nucleus-ui nil
  "UI components for nucleus."
  :group 'nucleus)

;;; Header-line Functions

(defun nucleus--header-line-apply-preset-label (&rest _)
  "Set the gptel header-line to show the active preset with a toggle button.

Only applies when a gptel--preset is active in the current buffer.
Skips special buffers like *Message* that may have gptel-mode enabled."
  (when (and (bound-and-true-p gptel-mode)
             (bound-and-true-p gptel-use-header-line)
             (consp header-line-format)
             (bound-and-true-p gptel--preset)
             (not (string-match-p "^\\*Message" (buffer-name)))
             (not (string-match-p "^ \\*gptel" (buffer-name))))
    (setcar header-line-format
            '(:eval
              (let* ((preset (if (and (boundp 'gptel--preset)
                                     (memq gptel--preset '(gptel-plan gptel-agent)))
                                gptel--preset
                              'gptel-plan))
                     (agent-mode (eq preset 'gptel-agent))
                     (label (if agent-mode "[Agent]" "[Plan]"))
                     (help (if agent-mode
                               "Switch to Plan preset"
                             "Switch to Agent preset"))
                     (face (if agent-mode
                               'font-lock-keyword-face
                             'font-lock-doc-face)))
                (concat
                 (propertize " " 'display '(space :align-to 0))
                 (format "%s"
                         (if (fboundp 'gptel-backend-name)
                             (gptel-backend-name gptel-backend)
                           "gptel"))
                 (propertize
                  (if (fboundp 'buttonize)
                      (buttonize label #'nucleus-header-toggle-preset nil help)
                    label)
                  'face face)))))))

(defun nucleus--agent-around (orig &optional project-dir agent-preset)
  "Around-advice for `gptel-agent': normalize args and fix header.

1. Coerce PROJECT-DIR to an existing directory.
2. Override AGENT-PRESET with `nucleus-agent-default'.
3. After the call, replace gptel-agent's hardcoded header-line closure
   with the preset-aware version."
  (ignore agent-preset)
  (when project-dir
    (setq project-dir
          (let* ((expanded (expand-file-name (or project-dir default-directory)))
                 (dir (if (file-directory-p expanded)
                          expanded
                        (file-name-directory expanded))))
            (file-name-as-directory dir))))
  
  (let* ((existing (mapcar #'buffer-name
                           (seq-filter (lambda (b)
                                        (buffer-local-value 'gptel-mode b))
                                      (buffer-list))))
         (_result (funcall orig project-dir
                          (if (boundp 'nucleus-agent-default)
                              nucleus-agent-default
                            'gptel-plan)))
         (new-buf (seq-find (lambda (b)
                             (and (buffer-local-value 'gptel-mode b)
                                  (not (member (buffer-name b) existing))))
                           (buffer-list))))
    (when (and new-buf (buffer-live-p new-buf))
      (with-current-buffer new-buf
        (nucleus--header-line-apply-preset-label)))))

;;; Integration

(defun nucleus-ui-setup ()
  "Setup nucleus UI components.

Call this after gptel loads to configure header-line."
  ;; Header-line setup is handled by hooks in nucleus-config.el
  ;; This function is provided for future extensions
  )

;;; Footer

(provide 'nucleus-ui)

;;; nucleus-ui.el ends here
