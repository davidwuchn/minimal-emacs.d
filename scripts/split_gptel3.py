import os

with open("lisp/gptel-config.el.bak", "r") as f:
    text = f.read()


def extract_section(start_marker, end_marker=None):
    start = text.find(start_marker)
    if start == -1:
        print(f"WARNING: start_marker not found: {start_marker}")
        return ""
    if end_marker:
        end = text.find(end_marker, start)
        if end == -1:
            print(f"WARNING: end_marker not found: {end_marker}")
            return text[start:]
        return text[start:end]
    return text[start:]


base_reqs = """;;; -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'subr-x)
(require 'seq)
(require 'project)
(require 'url)
(require 'url-parse)
(require 'url-util)
(require 'json)
(require 'dom)
(require 'diff)
(require 'gptel)
(eval-when-compile
  (require 'gptel-openai)
  (require 'gptel-gemini)
  (require 'gptel-gh))
(require 'gptel-context)
(require 'gptel-request)
(require 'gptel-gh)
(require 'gptel-gemini)
(require 'gptel-openai)
;; (require 'gptel-openai-extras)
"""


def write_module(filename, content):
    filepath = os.path.join("lisp/modules", filename)
    with open(filepath, "w") as f:
        f.write(
            base_reqs
            + "\n"
            + content.strip()
            + f"\n\n(provide '{filename[:-3]})\n;;; {filename} ends here\n"
        )
    print(f"Wrote {filename}")


header_end = text.find(";; --- Markdown Face Compatibility ---")
header_text = text[:header_end]
lines = header_text.split("\n")
new_header_lines = []
in_toc = False
for line in lines:
    if line.startswith(";;; Table of Contents"):
        in_toc = True
    elif in_toc and line.startswith(";;   L"):
        continue
    elif in_toc and not line.strip():
        in_toc = False
    elif not in_toc and not line.startswith(";;; gptel-config"):
        new_header_lines.append(line)
header_code = "\n".join(new_header_lines).strip()

# 1. Core
core_start = ";; --- Markdown Face Compatibility ---"
core_end = ";; --- Interruptible Grep Tool Override ---"
core_content = header_code + "\n\n" + extract_section(core_start, core_end)

fsm_start = ";; --- FSM Error Recovery ---"
fsm_end = ";; --- Provider Backends ---"
core_content += "\n\n" + extract_section(fsm_start, fsm_end)
write_module("gptel-core.el", core_content)

# 2. Tools
tools_part1 = extract_section(";; --- Interruptible Grep Tool Override ---", fsm_start)
tools_part2 = extract_section(
    "(defun my/find-buffers-and-recent (pattern)",
    "(defun my/gptel--extract-patch (text)",
)

tools_part3_start = "(defgroup my/gptel-subagent nil"
tools_part3_end = ";; --- Step-through preview infrastructure ---"
tools_part3 = extract_section(tools_part3_start, tools_part3_end)

tools_part4_start = (
    ";; Build tool lists after gptel-agent-tools has registered all upstream tools."
)
tools_part4_end = ";; --- Configuration Defaults ---"
tools_part4 = extract_section(tools_part4_start, tools_part4_end)

tools_content = (
    tools_part1 + "\n\n" + tools_part2 + "\n\n" + tools_part3 + "\n\n" + tools_part4
)
write_module("gptel-tools.el", tools_content)

# 3. Backends
backends_start = ";; --- Provider Backends ---"
backends_end = "(defgroup my/gptel-auto-compact nil"
write_module("gptel-backends.el", extract_section(backends_start, backends_end))

# 4. Context
context_start = "(defgroup my/gptel-auto-compact nil"
context_end = "(defun my/learning--update-instinct (path)"
write_module("gptel-context.el", extract_section(context_start, context_end))

# 5. Learning
learning_start = "(defun my/learning--update-instinct (path)"
learning_end = "(defun my/find-buffers-and-recent (pattern)"
write_module("gptel-learning.el", extract_section(learning_start, learning_end))

# 6. Patch
patch_part1_start = "(defun my/gptel--extract-patch (text)"
patch_part1_end = "(defgroup my/gptel-subagent nil"
patch_part1 = extract_section(patch_part1_start, patch_part1_end)

patch_part2_start = ";; --- Step-through preview infrastructure ---"
patch_part2_end = (
    ";; Build tool lists after gptel-agent-tools has registered all upstream tools."
)
patch_part2 = extract_section(patch_part2_start, patch_part2_end)

patch_content = patch_part1 + "\n\n" + patch_part2
write_module("gptel-patch.el", patch_content)

# 7. Security
security_start = ";; ==============================================================================\n;; TOOL SECURITY & ROUTING (NUCLEUS HYBRID SANDBOX)"
write_module("gptel-security.el", extract_section(security_start, None))

# 8. Main Config
config_defaults_start = ";; --- Configuration Defaults ---"
config_defaults_end = (
    ";; =============================================================================="
)
config_defaults_content = extract_section(config_defaults_start, config_defaults_end)

new_config = (
    """;;; gptel-config.el --- Clean, modular gptel configuration -*- lexical-binding: t; -*-

(add-to-list 'load-path
             (expand-file-name "modules"
                               (file-name-directory (or load-file-name
                                                        buffer-file-name
                                                        (locate-library "gptel-config")
                                                        (expand-file-name "lisp/gptel-config.el" user-emacs-directory)))))

(require 'gptel-core)
(require 'gptel-backends)
(require 'gptel-context)
(require 'gptel-learning)
(require 'gptel-patch)
(require 'gptel-tools)
(require 'gptel-security)

"""
    + config_defaults_content.strip()
    + "\n\n(provide 'gptel-config)\n;;; gptel-config.el ends here\n"
)

with open("lisp/gptel-config.el", "w") as f:
    f.write(new_config)

print("Split completed successfully with final mappings.")
