#!/usr/bin/env python3
"""Research Trace Logger — AutoTTS-style offline trace collection

Saves complete researcher sessions for offline replay and evaluation.
Each trace includes: prompt, all tool calls, responses, timestamps, tokens.
"""
import json
import hashlib
from pathlib import Path
from datetime import datetime

ROOT = Path(__file__).resolve().parents[4]
TRACE_DIR = ROOT / "var/tmp/research-traces"

def ensure_trace_dir():
    TRACE_DIR.mkdir(parents=True, exist_ok=True)

def save_trace(session_id, prompt, tool_calls, final_output, metadata=None):
    """Save a complete research session trace.
    
    Args:
        session_id: Unique identifier for this research session
        prompt: The full prompt sent to researcher
        tool_calls: List of {tool, args, response, timestamp, tokens}
        final_output: The final research output
        metadata: Extra info (backend, model, strategy used)
    """
    ensure_trace_dir()
    
    trace = {
        'version': '1.0',
        'session_id': session_id,
        'timestamp': datetime.now().isoformat(),
        'prompt': prompt,
        'tool_calls': tool_calls,
        'final_output': final_output,
        'metadata': metadata or {},
        'metrics': {
            'total_tool_calls': len(tool_calls),
            'total_tokens': sum(c.get('tokens', 0) for c in tool_calls),
            'total_chars': len(final_output),
        }
    }
    
    trace_file = TRACE_DIR / f"{session_id}.json"
    with open(trace_file, 'w') as f:
        json.dump(trace, f, indent=2)
    
    print(f"[trace] Saved research trace: {trace_file}")
    print(f"[trace]   Tool calls: {trace['metrics']['total_tool_calls']}")
    print(f"[trace]   Tokens: {trace['metrics']['total_tokens']}")
    print(f"[trace]   Output chars: {trace['metrics']['total_chars']}")
    
    return trace_file

def load_trace(session_id):
    """Load a research trace by session ID."""
    trace_file = TRACE_DIR / f"{session_id}.json"
    if not trace_file.exists():
        return None
    with open(trace_file) as f:
        return json.load(f)

def list_traces():
    """List all available traces."""
    ensure_trace_dir()
    traces = []
    for f in sorted(TRACE_DIR.glob("*.json")):
        with open(f) as fh:
            trace = json.load(fh)
            traces.append({
                'session_id': trace['session_id'],
                'timestamp': trace['timestamp'],
                'tool_calls': trace['metrics']['total_tool_calls'],
                'tokens': trace['metrics']['total_tokens'],
                'chars': trace['metrics']['total_chars'],
            })
    return traces

def build_replay_store():
    """Build replay store from all traces for offline evaluation."""
    traces = list_traces()
    
    store = {
        'version': '1.0',
        'total_traces': len(traces),
        'traces': traces,
    }
    
    store_file = TRACE_DIR / "replay-store.json"
    with open(store_file, 'w') as f:
        json.dump(store, f, indent=2)
    
    print(f"[replay] Built replay store: {len(traces)} traces")
    return store

if __name__ == '__main__':
    import sys
    
    # Called from elisp with: --save ID --prompt-length N --output-length N --strategy S --hash H
    if '--save' in sys.argv:
        try:
            idx = sys.argv.index('--save')
            session_id = sys.argv[idx + 1] if idx + 1 < len(sys.argv) else 'unknown'
            
            prompt_len = 0
            if '--prompt-length' in sys.argv:
                pidx = sys.argv.index('--prompt-length')
                prompt_len = int(sys.argv[pidx + 1]) if pidx + 1 < len(sys.argv) else 0
            
            output_len = 0
            if '--output-length' in sys.argv:
                oidx = sys.argv.index('--output-length')
                output_len = int(sys.argv[oidx + 1]) if oidx + 1 < len(sys.argv) else 0
            
            strategy = 'default'
            if '--strategy' in sys.argv:
                sidx = sys.argv.index('--strategy')
                strategy = sys.argv[sidx + 1] if sidx + 1 < len(sys.argv) else 'default'
            
            rhash = ''
            if '--hash' in sys.argv:
                hidx = sys.argv.index('--hash')
                rhash = sys.argv[hidx + 1] if hidx + 1 < len(sys.argv) else ''
            
            # Create a basic trace (we don't have actual tool calls from elisp yet)
            trace = {
                'version': '1.0',
                'session_id': session_id,
                'timestamp': datetime.now().isoformat(),
                'prompt': f'<prompt {prompt_len} chars>',
                'tool_calls': [],
                'final_output': f'<output {output_len} chars>',
                'metadata': {
                    'strategy': strategy,
                    'hash': rhash,
                },
                'metrics': {
                    'total_tool_calls': 0,
                    'total_tokens': 0,
                    'total_chars': output_len,
                }
            }
            
            ensure_trace_dir()
            trace_file = TRACE_DIR / f"{session_id}.json"
            with open(trace_file, 'w') as f:
                json.dump(trace, f, indent=2)
            
            print(f"[trace] Saved research trace: {trace_file}")
        except Exception as e:
            print(f"[trace] Error saving trace: {e}")
    elif len(sys.argv) > 1 and sys.argv[1] == 'list':
        traces = list_traces()
        print(f"Total traces: {len(traces)}")
        for t in traces:
            print(f"  {t['session_id']}: {t['tool_calls']} calls, {t['tokens']} tokens, {t['chars']} chars")
    else:
        build_replay_store()
