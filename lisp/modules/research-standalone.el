;;; research-standalone.el --- Minimal researcher that works in daemon context -*- lexical-binding: t; -*-
;; Loads researcher prompt and calls subagent directly.
;; Bypasses all the complex functions that get corrupted by load-file.

;; Redefine format-topic-performance using defalias to avoid load-file corruption
(defalias 'gptel-auto-workflow--format-topic-performance
  (lambda (topics)
    (if (or (null topics)
            (not (hash-table-p topics))
            (zerop (hash-table-count topics)))
        "*No topic performance data available.*"
      (let ((topic-list nil))
        (maphash (lambda (topic stats)
                   (let ((success-rate (gethash "success_rate" stats 0))
                         (total (gethash "total_experiments" stats 0))
                         (kept (gethash "kept" stats 0))
                         (trend (gethash "trend" stats "stable")))
                     (push (list topic success-rate total kept trend) topic-list))
                 topics))
        (setq topic-list (sort topic-list (lambda (a b) (> (nth 1 a) (nth 1 b)))))
        (concat "| Topic | Success Rate | Kept/Total | Trend |\n"
                "|-------|--------------|------------|-------|\n"
                (mapconcat
                 (lambda (item)
                   (format "| %s | %.0f%% | %d/%d | %s |"
                           (nth 0 item) (* 100 (nth 1 item))
                           (nth 3 item) (nth 2 item)
                           (nth 4 item)))
                 (seq-take topic-list 10)
                 "\n"))))
    "Format TOPICS hash-table as markdown table."))

;; Redefine substitute-researcher-variables in a simpler way
(defalias 'gptel-auto-workflow--substitute-researcher-variables
  (lambda (skill-content)
    (if (null skill-content)
        skill-content
      (let* ((meta-data (gptel-auto-workflow--load-researcher-meta-learning))
             (effectiveness (or (plist-get meta-data :effectiveness) 16))
             (kept (or (plist-get meta-data :kept) 0))
             (total (or (plist-get meta-data :total) 870))
             (topics (plist-get meta-data :topics)))
        (setq skill-content
              (replace-regexp-in-string
               "{{research-effectiveness}}" (number-to-string effectiveness)
               skill-content t t))
        (setq skill-content
              (replace-regexp-in-string
               "{{kept-research}}" (number-to-string kept)
               skill-content t t))
        (setq skill-content
              (replace-regexp-in-string
               "{{total-research}}" (number-to-string total)
               skill-content t t))
        (if topics
            (let ((topic-md (gptel-auto-workflow--format-topic-performance topics)))
              (setq skill-content
                    (replace-regexp-in-string
                     "{{topic-performance}}" topic-md
                     skill-content t t)))
          (setq skill-content
                (replace-regexp-in-string
                 "{{topic-performance}}" "*No topic data available yet.*"
                 skill-content t t)))
        skill-content))
    "Substitute template variables in SKILL-CONTENT with meta-learning data."))

(provide 'research-standalone)
;;; research-standalone.el ends here
