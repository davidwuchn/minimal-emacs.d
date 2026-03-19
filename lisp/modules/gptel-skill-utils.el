;;; gptel-skill-utils.el --- GPTel Skill Utility Functions -*- lexical-binding: t -*-

;; Copyright (C) 2024 David Wu

;; Author: David Wu <davidwu@example.com>
;; Keywords: ai, benchmark, utilities

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Shared utility functions for GPTel skill modules.
;; This module centralizes common operations to avoid code duplication.

;;; Code:

(require 'json)

(defun gptel-skill-read-json (file)
  "Read and parse JSON from FILE.
Returns the parsed JSON structure as Elisp objects."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (json-read)))

(defun gptel-skill-write-json (data file)
  "Write DATA as JSON to FILE.
DATA should be an Elisp object that can be serialized to JSON."
  (with-temp-buffer
    (insert (json-encode data))
    (write-region (point-min) (point-max) file)))

(provide 'gptel-skill-utils)

;;; gptel-skill-utils.el ends here
