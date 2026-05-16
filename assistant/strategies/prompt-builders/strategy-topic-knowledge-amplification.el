;;; strategy-topic-knowledge-amplification.el --- Topic knowledge amplification -*- lexical-binding: t; -*-
;; Hypothesis: Amplifying topic knowledge sections for target domain improves domain-aware improvements.
;; Axis: B

(require 'gptel-tools-agent-prompt-build)

(defun strategy-topic-knowledge-amplification-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with amplified topic knowledge sections."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt target experiment-id max-experiments analysis baseline previous-results))
         (topic-knowledge (gptel-auto-experiment--get-topic-knowledge target))
         (content (if (file-exists-p target) (with-temp-buffer (insert-file-contents target) (buffer-string)) ""))
         (domain-indicators (extract-domain-indicators content))
         (amplified-knowledge (amplify-knowledge topic-knowledge domain-indicators)))
    (concat base-prompt "\n\n" amplified-knowledge)))

(defun extract-domain-indicators (content)
  "Extract domain indicators from CONTENT to determine topic knowledge needs."
  (let ((indicators '()))
    (when (string-match-p "file\\|directory\\|path\\|buffer\\|window\\|frame" content)
      (push "file-operations" indicators))
    (when (string-match-p "network\\|http\\|url\\|request\\|json\\|xml" content)
      (push "network-programming" indicators))
    (when (string-match-p "database\\|sql\\|query\\|insert\\|select" content)
      (push "data-persistence" indicators))
    (when (string-match-p "thread\\|process\\|async\\|concurrency\\|future" content)
      (push "concurrency" indicators))
    (when (string-match-p "regex\\|match\\|search\\|pattern" content)
      (push "text-processing" indicators))
    (if indicators indicators '("general-elisp"))))

(defun amplify-knowledge (topic-knowledge domain-indicators)
  "Amplify TOPIC-KNOWLEDGE for DOMAIN-INDICATORS."
  (format ";; Amplified Topic Knowledge (Domain: %s)
;; Current knowledge: %s
;; Amplification strategy: Expand best practices and common pitfalls for detected domains"
          (string-join domain-indicators ", ")
          (if (and topic-knowledge (> (length topic-knowledge) 0))
              (substring-no-properties topic-knowledge 0 (min 200 (length topic-knowledge)))
            "No pre-existing topic knowledge available")))

(defun strategy-topic-knowledge-amplification-get-metadata ()
  (list :name "topic-knowledge-amplification"
        :version "1.0"
        :hypothesis "Amplifying topic knowledge for detected domains improves domain-specific code improvements."
        :axis "B"
        :components ["domain-detection" "knowledge-amplification"]))

(provide 'strategy-topic-knowledge-amplification)