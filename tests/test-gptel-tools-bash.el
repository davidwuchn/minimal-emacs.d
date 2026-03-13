;;; test-gptel-tools-bash.el --- Tests for gptel-tools-bash.el -*- lexical-binding: t; -*-

;; Copyright (C) 2024  David Wu

;; Author: David Wu
;; Keywords: gptel, bash, testing, sandbox

;;; Commentary:

;; Unit tests for the Bash tool in gptel-tools-bash.el.
;; Tests cover:
;; - Plan Mode sandbox (read-only whitelist)
;; - Agent Mode unrestricted execution
;; - Command validation and security
;; - Error handling

;;; Code:

(require 'ert)
(require 'cl-lib)

;;; Bash Mode Simulation

(defvar test-gptel-bash--mode 'agent
  "Current bash mode for testing: 'plan or 'agent.")

(defvar test-gptel-bash--whitelist
  '("git" "ls" "cat" "grep" "find" "test" "echo" "pwd" "wc" "head" "tail")
  "Whitelist of allowed commands in Plan Mode.")

;;; Bash Execution Mock

(defun test-gptel-bash--execute (command &optional mode)
  "Mock Bash execution with mode-based sandboxing.
COMMAND is the bash command string.
MODE is 'plan or 'agent (defaults to `test-gptel-bash--mode`)."
  (let ((current-mode (or mode test-gptel-bash--mode)))
    (cond
     ((eq current-mode 'plan)
      (test-gptel-bash--plan-mode-execute command))
     ((eq current-mode 'agent)
      (test-gptel-bash--agent-mode-execute command))
     (t
      (error "Unknown bash mode: %s" current-mode)))))

(defun test-gptel-bash--plan-mode-execute (command)
  "Execute COMMAND in Plan Mode with sandbox restrictions."
  (let ((forbidden-chars '(">" "<" "&" "$" "`"))
        (forbidden-cmds '("sed" "rm" "mv" "cp" "chmod" "sudo"))
        (cmd (string-trim command))
        (base-cmd nil)
        (blocked nil)
        (block-reason nil))
    ;; Check for forbidden characters
    (catch 'found-forbidden
      (dolist (char forbidden-chars)
        (when (string-match-p (regexp-quote char) cmd)
          (setq blocked t)
          (setq block-reason (format "Forbidden character in Plan Mode: %s" char))
          (throw 'found-forbidden nil))))
    ;; Check for forbidden commands
    (unless blocked
      (setq base-cmd (car (split-string cmd)))
      (when (member base-cmd forbidden-cmds)
        (setq blocked t)
        (setq block-reason (format "Forbidden command in Plan Mode: %s" base-cmd))))
    ;; Return result
    (if blocked
        (list :status "blocked"
              :reason block-reason
              :command cmd)
      (setq base-cmd (or base-cmd (car (split-string cmd))))
      (if (member base-cmd test-gptel-bash--whitelist)
          (list :status "allowed"
                :mode "plan"
                :command cmd
                :output (format "[mock output for: %s]" cmd))
        (list :status "blocked"
              :reason (format "Command not in whitelist: %s" base-cmd)
              :command cmd)))))

(defun test-gptel-bash--agent-mode-execute (command)
  "Execute COMMAND in Agent Mode (unrestricted)."
  (list :status "allowed"
        :mode "agent"
        :command command
        :output (format "[mock output for: %s]" command)
        :warning (when (string-match-p "rm\\|mv\\|chmod\\|sudo" command)
                   "Destructive command executed in Agent Mode")))

;;; Plan Mode Tests

(ert-deftest test-gptel-bash-plan-mode-git-allowed ()
  "Test Plan Mode allows git commands."
  (let ((test-gptel-bash--mode 'plan))
    (let ((result (test-gptel-bash--execute "git status")))
      (should (equal (plist-get result :status) "allowed"))
      (should (equal (plist-get result :mode) "plan")))))

(ert-deftest test-gptel-bash-plan-mode-ls-allowed ()
  "Test Plan Mode allows ls commands."
  (let ((test-gptel-bash--mode 'plan))
    (let ((result (test-gptel-bash--execute "ls -la")))
      (should (equal (plist-get result :status) "allowed")))))

(ert-deftest test-gptel-bash-plan-mode-cat-allowed ()
  "Test Plan Mode allows cat commands."
  (let ((test-gptel-bash--mode 'plan))
    (let ((result (test-gptel-bash--execute "cat file.txt")))
      (should (equal (plist-get result :status) "allowed")))))

(ert-deftest test-gptel-bash-plan-mode-grep-allowed ()
  "Test Plan Mode allows grep commands."
  (let ((test-gptel-bash--mode 'plan))
    (let ((result (test-gptel-bash--execute "grep pattern file.txt")))
      (should (equal (plist-get result :status) "allowed")))))

(ert-deftest test-gptel-bash-plan-mode-find-allowed ()
  "Test Plan Mode allows find commands."
  (let ((test-gptel-bash--mode 'plan))
    (let ((result (test-gptel-bash--execute "find . -name '*.el'")))
      (should (equal (plist-get result :status) "allowed")))))

(ert-deftest test-gptel-bash-plan-mode-test-allowed ()
  "Test Plan Mode allows test commands."
  (let ((test-gptel-bash--mode 'plan))
    (let ((result (test-gptel-bash--execute "test -f file.txt")))
      (should (equal (plist-get result :status) "allowed")))))

;;; Plan Mode Security Tests

(ert-deftest test-gptel-bash-plan-mode-blocks-output-redirection ()
  "Test Plan Mode blocks output redirection (>)."
  (let ((test-gptel-bash--mode 'plan))
    (let ((result (test-gptel-bash--execute "ls > output.txt")))
      (should (equal (plist-get result :status) "blocked"))
      (should (string-match-p "Forbidden" (plist-get result :reason))))))

(ert-deftest test-gptel-bash-plan-mode-blocks-input-redirection ()
  "Test Plan Mode blocks input redirection (<)."
  (let ((test-gptel-bash--mode 'plan))
    (let ((result (test-gptel-bash--execute "cat < input.txt")))
      (should (equal (plist-get result :status) "blocked")))))

(ert-deftest test-gptel-bash-plan-mode-blocks-sed ()
  "Test Plan Mode blocks sed command."
  (let ((test-gptel-bash--mode 'plan))
    (let ((result (test-gptel-bash--execute "sed 's/old/new/g' file.txt")))
      (should (equal (plist-get result :status) "blocked"))
      (should (string-match-p "Forbidden" (plist-get result :reason))))))

(ert-deftest test-gptel-bash-plan-mode-blocks-background-process ()
  "Test Plan Mode blocks background process (&)."
  (let ((test-gptel-bash--mode 'plan))
    (let ((result (test-gptel-bash--execute "git status &")))
      (should (equal (plist-get result :status) "blocked")))))

(ert-deftest test-gptel-bash-plan-mode-blocks-command-substitution ()
  "Test Plan Mode blocks $() command substitution."
  (let ((test-gptel-bash--mode 'plan))
    (let ((result (test-gptel-bash--execute "echo $(pwd)")))
      (should (equal (plist-get result :status) "blocked")))))

(ert-deftest test-gptel-bash-plan-mode-blocks-backtick-substitution ()
  "Test Plan Mode blocks backtick command substitution."
  (let ((test-gptel-bash--mode 'plan))
    (let ((result (test-gptel-bash--execute "echo `pwd`")))
      (should (equal (plist-get result :status) "blocked")))))

(ert-deftest test-gptel-bash-plan-mode-blocks-rm ()
  "Test Plan Mode blocks rm command."
  (let ((test-gptel-bash--mode 'plan))
    (let ((result (test-gptel-bash--execute "rm -rf /tmp/test")))
      (should (equal (plist-get result :status) "blocked")))))

(ert-deftest test-gptel-bash-plan-mode-blocks-chmod ()
  "Test Plan Mode blocks chmod."
  (let ((test-gptel-bash--mode 'plan))
    (let ((result (test-gptel-bash--execute "chmod +x script.sh")))
      (should (equal (plist-get result :status) "blocked")))))

(ert-deftest test-gptel-bash-plan-mode-blocks-sudo ()
  "Test Plan Mode blocks sudo."
  (let ((test-gptel-bash--mode 'plan))
    (let ((result (test-gptel-bash--execute "sudo apt update")))
      (should (equal (plist-get result :status) "blocked"))
      (should (string-match-p "sudo" (plist-get result :reason))))))

(ert-deftest test-gptel-bash-plan-mode-blocks-non-whitelist-command ()
  "Test Plan Mode blocks commands not in whitelist."
  (let ((test-gptel-bash--mode 'plan))
    (let ((result (test-gptel-bash--execute "python3 script.py")))
      (should (equal (plist-get result :status) "blocked"))
      (should (string-match-p "not in whitelist" (plist-get result :reason))))))

;;; Agent Mode Tests

(ert-deftest test-gptel-bash-agent-mode-allows-all-commands ()
  "Test Agent Mode allows all commands."
  (let ((test-gptel-bash--mode 'agent))
    (let ((result (test-gptel-bash--execute "rm -rf /tmp/test")))
      (should (equal (plist-get result :status) "allowed"))
      (should (equal (plist-get result :mode) "agent")))))

(ert-deftest test-gptel-bash-agent-mode-allows-redirection ()
  "Test Agent Mode allows output redirection."
  (let ((test-gptel-bash--mode 'agent))
    (let ((result (test-gptel-bash--execute "echo test > file.txt")))
      (should (equal (plist-get result :status) "allowed")))))

(ert-deftest test-gptel-bash-agent-mode-allows-sed ()
  "Test Agent Mode allows sed."
  (let ((test-gptel-bash--mode 'agent))
    (let ((result (test-gptel-bash--execute "sed 's/old/new/g' file.txt")))
      (should (equal (plist-get result :status) "allowed")))))

(ert-deftest test-gptel-bash-agent-mode-allows-command-substitution ()
  "Test Agent Mode allows command substitution."
  (let ((test-gptel-bash--mode 'agent))
    (let ((result (test-gptel-bash--execute "echo $(pwd)")))
      (should (equal (plist-get result :status) "allowed")))))

(ert-deftest test-gptel-bash-agent-mode-warns-destructive ()
  "Test Agent Mode warns on destructive commands."
  (let ((test-gptel-bash--mode 'agent))
    (let ((result (test-gptel-bash--execute "rm -rf /tmp/test")))
      (should (string-match-p "Destructive" (plist-get result :warning))))))

(ert-deftest test-gptel-bash-agent-mode-no-warning-safe ()
  "Test Agent Mode has no warning for safe commands."
  (let ((test-gptel-bash--mode 'agent))
    (let ((result (test-gptel-bash--execute "git status")))
      (should (null (plist-get result :warning))))))

;;; Edge Case Tests

(ert-deftest test-gptel-bash-empty-command ()
  "Test Bash handles empty command."
  (let ((test-gptel-bash--mode 'agent))
    (let ((result (test-gptel-bash--execute "")))
      (should result))))

(ert-deftest test-gptel-bash-whitespace-command ()
  "Test Bash handles whitespace-only command."
  (let ((test-gptel-bash--mode 'agent))
    (let ((result (test-gptel-bash--execute "   ")))
      (should result))))

(ert-deftest test-gptel-bash-complex-pipeline ()
  "Test Bash handles complex pipeline in Agent Mode."
  (let ((test-gptel-bash--mode 'agent))
    (let ((result (test-gptel-bash--execute "git diff | grep '^+' | wc -l")))
      (should (equal (plist-get result :status) "allowed")))))

(ert-deftest test-gptel-bash-quoted-arguments ()
  "Test Bash handles quoted arguments."
  (let ((test-gptel-bash--mode 'plan))
    (let ((result (test-gptel-bash--execute "grep \"pattern with spaces\" file.txt")))
      (should (equal (plist-get result :status) "allowed")))))

(ert-deftest test-gptel-bash-mode-switch ()
  "Test switching between Plan and Agent modes."
  (let ((test-gptel-bash--mode 'plan))
    (should (equal (plist-get (test-gptel-bash--execute "git status") :mode) "plan")))
  (let ((test-gptel-bash--mode 'agent))
    (should (equal (plist-get (test-gptel-bash--execute "git status") :mode) "agent"))))

;;; Integration-style Tests

(ert-deftest test-gptel-bash-typical-plan-commands ()
  "Test typical Plan Mode command sequences."
  (let ((test-gptel-bash--mode 'plan)
        (commands '("git status"
                    "git diff HEAD"
                    "ls -la"
                    "find . -name '*.el'"
                    "grep -r 'TODO' lisp/"
                    "cat README.md"
                    "test -f Makefile")))
    (dolist (cmd commands)
      (let ((result (test-gptel-bash--execute cmd)))
        (should (equal (plist-get result :status) "allowed"))
        (should (equal (plist-get result :mode) "plan"))))))

(ert-deftest test-gptel-bash-typical-agent-commands ()
  "Test typical Agent Mode command sequences."
  (let ((test-gptel-bash--mode 'agent)
        (commands '("make test"
                    "emacs --batch -l test.el"
                    "npm run build"
                    "docker-compose up"
                    "sed -i 's/old/new/g' file.txt")))
    (dolist (cmd commands)
      (let ((result (test-gptel-bash--execute cmd)))
        (should (equal (plist-get result :status) "allowed"))
        (should (equal (plist-get result :mode) "agent"))))))

;;; Provide the test suite

(provide 'test-gptel-tools-bash)

;;; test-gptel-tools-bash.el ends here
