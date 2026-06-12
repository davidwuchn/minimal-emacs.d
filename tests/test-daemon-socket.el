;;; test-daemon-socket.el --- Test daemon socket creation -*- lexical-binding: t -*-

(require 'ert)

(ert-deftest test-daemon-socket-variables-bound ()
  "Server variables should be bound in daemon mode."
  (skip-unless (daemonp))
  (should (boundp 'server-name))
  (should (boundp 'server-socket-dir))
  (should (stringp server-name))
  (should (stringp server-socket-dir)))

(ert-deftest test-daemon-socket-file-exists ()
  "Server socket file should exist in daemon mode."
  (skip-unless (daemonp))
  (skip-unless (and (boundp 'server-name) (boundp 'server-socket-dir)))
  (let ((sock (expand-file-name server-name server-socket-dir)))
    (should (file-exists-p sock))))

(ert-deftest test-daemon-server-process-live ()
  "Server process should be live in daemon mode."
  (skip-unless (daemonp))
  (should (boundp 'server-process))
  (should server-process)
  (should (process-live-p server-process)))

(provide 'test-daemon-socket)
;;; test-daemon-socket.el ends here
