#!/usr/bin/env python3
"""OV5 MCP server — exposes emacsclient as MCP tools."""
import json, subprocess, sys

SOCKET = "/run/user/1000/emacs/ov5-auto-workflow"

def emacs(expr):
    r = subprocess.run(["emacsclient", "-s", SOCKET, "-n", "--eval", expr],
                       capture_output=True, text=True, timeout=30)
    return r.stdout.strip()

def tool_status():
    raw = emacs("(gptel-auto-workflow-status)")
    return {"content": [{"type": "text", "text": raw}]}

def tool_run():
    raw = emacs("(gptel-auto-workflow-run-async)")
    return {"content": [{"type": "text", "text": raw}]}

def tool_results():
    raw = emacs("""
(progn
  (setq res (gptel-auto-workflow-status))
  (format "phase=%s total=%d kept=%d run-id=%s"
          (plist-get res :phase) (plist-get res :total)
          (plist-get res :kept) (plist-get res :run-id)))
""")
    return {"content": [{"type": "text", "text": raw}]}

HANDLERS = {
    "ov5_status": tool_status,
    "ov5_run": tool_run,
    "ov5_results": tool_results,
}

if __name__ == "__main__":
    req = json.loads(sys.stdin.read())
    tool = req.get("params", {}).get("name", "")
    result = HANDLERS.get(tool, lambda: {})()
    json.dump({"result": result}, sys.stdout)
