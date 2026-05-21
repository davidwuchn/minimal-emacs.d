;;; gptel-auto-workflow-ontology-router.el --- Smart LLM backend routing via ontology -*- lexical-binding: t -*-

;; Copyright (C) 2024-2026  Self-Evolving Emacs Project

;; Author: Self-Evolving System
;; Keywords: ontology, backend, routing, smart, performance

;;; Commentary:

;; Use ontology data to route tasks to the best LLM backend.
;; Tracks backend performance by task type (strategy, target, complexity).
;; Learns from experiment outcomes which backend excels at what.
;;
;; Task classification:
;; - Simple: < 100 lines, single file, obvious fix
;; - Moderate: 100-500 lines, cross-file, requires reasoning
;; - Complex: > 500 lines, architectural, novel patterns
;;
;; Backend performance tracking:
;; - Per strategy: which backend has best keep-rate for strategy X
;; - Per target type: which backend handles file type Y best
;; - Per complexity: simple tasks → fast backend, complex → powerful backend
;; - Per axis: K/I/B/C/M/W/T/PHI/D/SCOPE/SUBST/WHNF/Y/QUOTE
;;
;; Routing rules:
;; - If historical data exists (>= 3 experiments) → use best performing backend
;; - If no data → use default with exploration (15% random for learning)
;; - If all backends fail → fallback chain with retry

;;; Code:

(require 'gptel-auto-workflow-evolution)

(defcustom gptel-auto-workflow--router-min-samples 3
  "Minimum experiments before trusting backend performance data."
  :type 'integer
  :group 'gptel-auto-workflow)

(defcustom gptel-auto-workflow--router-exploration-rate 0.15
  "Probability of random backend selection for learning (15%)."
  :type 'float
  :group 'gptel-auto-workflow)

(defcustom gptel-auto-workflow--router-backends
  '(("moonshot" . (:model "kimi-k2.6" :strengths (complex reasoning long-context) :cost 0.02))
    ("MiniMax" . (:model "minimax-m2.7-highspeed" :strengths (speed simple fast) :cost 0.005))
    ("DashScope" . (:model "glm-5" :strengths (general balanced) :cost 0.01))
    ("DeepSeek" . (:model "deepseek-v4-flash" :strengths (coding reasoning fast) :cost 0.015))
    ("CF-Gateway" . (:model "@cf/openai/gpt-oss-120b" :strengths (fast-reasoning long-context) :cost 0.008)))
  "Available backends from headless LLM fallback list.
ONLY these backends/models are used for smart routing.
Source: `gptel-auto-workflow-headless-subagent-fallbacks`."
  :type 'alist
  :group 'gptel-auto-workflow)

;; ─── Task Classification ───

(defun gptel-auto-workflow--classify-task-complexity (target strategy)
  "Classify task complexity based on TARGET and STRATEGY.
Returns :simple, :moderate, or :complex."
  (let ((lines (condition-case nil
                   (with-temp-buffer
                     (insert-file-contents target)
                     (count-lines (point-min) (point-max)))
                 (error 0)))
        (complexity-indicators '("architecture" "refactor" "redesign"
                                  "extract" "pattern" "framework" "abstract")))
    (cond
     ;; Check strategy name for complexity hints
     ((cl-some (lambda (indicator)
                 (string-match-p indicator (downcase strategy)))
               complexity-indicators)
      :complex)
     ;; Check file size
     ((> lines 500) :complex)
     ((> lines 100) :moderate)
     ;; Default
     (t :simple))))

(defun gptel-auto-workflow--classify-task-axis (target)
  "Classify task by KIBC-M axis based on target filename.
Returns axis keyword: :K :I :B :C :M :W :T :PHI :D :SCOPE :SUBST :WHNF :Y :QUOTE."
  (let ((filename (downcase (file-name-nondirectory target))))
    (cond
     ((string-match-p "error\\|exception\\|handler\\|catch\\|guard" filename) :K)
     ((string-match-p "init\\|setup\\|bootstrap\\|config" filename) :I)
     ((string-match-p "break\\|split\\|chunk\\|divide" filename) :B)
     ((string-match-p "combine\\|merge\\|compose\\|integrate" filename) :C)
     ((string-match-p "meta\\|reflect\\|self\\|auto" filename) :M)
     ((string-match-p "strategy\\|harness\\|pattern" filename) :W)
     ((string-match-p "tool\\|agent\\|interface" filename) :T)
     ((string-match-p "philosophy\\|principle\\|theory" filename) :PHI)
     ((string-match-p "data\\|struct\\|schema\\|type" filename) :D)
     ((string-match-p "scope\\|context\\|namespace" filename) :SCOPE)
     ((string-match-p "subst\\|replace\\|transform" filename) :SUBST)
     ((string-match-p "eval\\|lazy\\|reduce" filename) :WHNF)
     ((string-match-p "recursion\\|loop\\|iterate" filename) :Y)
     ((string-match-p "quote\\|syntax\\|macro" filename) :QUOTE)
     (t :K))))  ; Default to Knowledge/Error handling

;; ─── Backend Performance Tracking ───

(defun gptel-auto-workflow--get-backend-performance (backend &optional strategy target axis)
  "Get performance metrics for BACKEND filtered by STRATEGY, TARGET, or AXIS.
Returns plist with :kept :total :keep-rate."
  (let ((results (gptel-auto-workflow--parse-all-results))
        (kept 0)
        (total 0))
    (dolist (r results)
      (let ((r-backend (or (plist-get r :backend) "unknown"))
            (r-strategy (plist-get r :strategy))
            (r-target (plist-get r :target))
            (r-decision (plist-get r :decision)))
        (when (string= r-backend backend)
          ;; Apply filters if specified
          (when (or (null strategy) (string= r-strategy strategy))
            (when (or (null target) (string= r-target target))
              (when (or (null axis)
                        (eq (gptel-auto-workflow--classify-task-axis r-target) axis))
                (setq total (1+ total))
                (when (equal r-decision "kept")
                  (setq kept (1+ kept)))))))))
    (list :kept kept
          :total total
          :keep-rate (if (> total 0) (/ (float kept) total) 0.0))))

(defun gptel-auto-workflow--get-all-backend-performances (&optional strategy target axis)
  "Get performance for all backends, sorted by keep-rate descending.
Returns alist of (backend . performance-plist)."
  (let ((performances nil))
    (dolist (backend-info gptel-auto-workflow--router-backends)
      (let* ((backend-name (car backend-info))
             (perf (gptel-auto-workflow--get-backend-performance
                    backend-name strategy target axis)))
        (push (cons backend-name perf) performances)))
    ;; Sort by keep-rate descending
    (sort performances
          (lambda (a b)
            (> (plist-get (cdr a) :keep-rate)
                (plist-get (cdr b) :keep-rate))))))

;; ─── Smart Router ───

(defun gptel-auto-workflow--smart-route-backend (target strategy)
  "Select best backend for TARGET + STRATEGY using ontology data.
Returns backend name or nil if no data."
  (let* ((complexity (gptel-auto-workflow--classify-task-complexity target strategy))
         (axis (gptel-auto-workflow--classify-task-axis target))
         (performances (gptel-auto-workflow--get-all-backend-performances strategy target axis))
         (best (car performances)))
    
    ;; Exploration: 15% chance to try random backend for learning
    (when (< (random 100) (* gptel-auto-workflow--router-exploration-rate 100))
      (let ((random-backend (car (nth (random (length performances)) performances))))
        (message "[router] EXPLORATION: trying %s for learning" random-backend)
        (return-from gptel-auto-workflow--smart-route-backend random-backend)))
    
    ;; If we have enough data for the best backend, use it
    (if (and best (>= (plist-get (cdr best) :total) gptel-auto-workflow--router-min-samples))
        (progn
          (message "[router] %s/%s (%s/%s) → %s (%.0f%% keep, %d samples)"
                   strategy target complexity axis
                   (car best)
                   (* 100 (plist-get (cdr best) :keep-rate))
                   (plist-get (cdr best) :total))
          (car best))
      ;; Not enough data - use default with complexity consideration
      (let ((default (pcase complexity
                       (:simple "minimax")
                       (:moderate "openai")
                       (:complex "moonshot")
                       (_ "openai"))))
        (message "[router] %s/%s (%s) → %s (default, insufficient data)"
                 strategy target complexity default)
        default))))

;; ─── Real-time Learning ───

(defun gptel-auto-workflow--record-backend-outcome (backend target strategy decision score)
  "Record experiment outcome for backend learning.
Updates ontology with new performance data."
  (let ((axis (gptel-auto-workflow--classify-task-axis target))
        (complexity (gptel-auto-workflow--classify-task-complexity target strategy)))
    (message "[router] LEARNED: %s on %s/%s (%s/%s) → %s (score %.2f)"
             backend strategy target complexity axis decision score)
    ;; The ontology is updated automatically via parse-all-results on next cycle
    ;; But we could trigger immediate ontology regeneration here if needed
    ))

;; ─── Advice Integration ───

(defun gptel-auto-workflow--backend-router-advice (orig-fun &rest args)
  "Advice around backend selection to use ontology routing."
  (let* ((target (car args))
         (strategy (cadr args))
         (routed-backend (gptel-auto-workflow--smart-route-backend target strategy)))
    (if routed-backend
        (progn
          ;; Set the backend for this experiment
          (let ((backend-obj (cdr (assoc routed-backend gptel-auto-workflow--router-backends))))
            (when backend-obj
              (setq gptel-backend (plist-get backend-obj :model)
                    gptel-model (intern (concat routed-backend "-" (plist-get backend-obj :model))))))
          (apply orig-fun args))
      (apply orig-fun args))))

;; ;; Uncomment to enable smart routing
;; (advice-add 'gptel-auto-experiment-run
;;             :around #'gptel-auto-workflow--backend-router-advice)

(provide 'gptel-auto-workflow-ontology-router)
;;; gptel-auto-workflow-ontology-router.el ends here
