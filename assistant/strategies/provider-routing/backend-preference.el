;; -*- lexical-binding: t; -*-
;; Auto-evolved per-axis backend preference
;; Updated: 2026-06-15 — remaining backends; DeepSeek primary
(defvar gptel-auto-workflow--task-backend-preference nil)
(setq gptel-auto-workflow--task-backend-preference
      '(("analyzer" "DeepSeek" . 0.30)
        ("executor" "DeepSeek" . 0.30)
        ("grader" "DeepSeek" . 0.30)
        ("researcher" "DeepSeek" . 0.30)
        ("reviewer" "DeepSeek" . 0.30)
        ("comparator" "DeepSeek" . 0.30)
        ("analyzer" "MiniMax" . 0.20)
        ("executor" "MiniMax" . 0.20)
        ("grader" "MiniMax" . 0.20)
        ("researcher" "MiniMax" . 0.20)
        ("reviewer" "MiniMax" . 0.20)
        ("comparator" "MiniMax" . 0.20)
        ("analyzer" "moonshot" . 0.10)
        ("executor" "moonshot" . 0.10)
        ("grader" "moonshot" . 0.10)
        ("researcher" "moonshot" . 0.10)
        ("reviewer" "moonshot" . 0.10)
        ("comparator" "moonshot" . 0.10)))
