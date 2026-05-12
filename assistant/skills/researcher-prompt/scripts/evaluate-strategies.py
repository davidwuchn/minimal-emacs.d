#!/usr/bin/env python3
"""Offline Strategy Evaluator — AutoTTS-style replay-based evaluation

Tests research strategies against cached traces WITHOUT making LLM calls.
This is the core AutoTTS insight: evaluate cheaply offline, then deploy best.
"""
import json
from pathlib import Path
from typing import List, Dict, Optional

ROOT = Path("/home/davidwu/.emacs.d")
TRACE_DIR = ROOT / "var/tmp/research-traces"
STRATEGY_DIR = ROOT / "assistant/skills/researcher-prompt/strategies"
RESULTS_FILE = ROOT / "var/tmp/strategy-evaluation-results.json"

def load_trace(session_id: str) -> Optional[Dict]:
    """Load a research trace."""
    trace_file = TRACE_DIR / f"{session_id}.json"
    if not trace_file.exists():
        return None
    with open(trace_file) as f:
        return json.load(f)

def load_strategy(name: str) -> Optional[Dict]:
    """Load a strategy definition."""
    strategy_file = STRATEGY_DIR / f"{name}.json"
    if not strategy_file.exists():
        return None
    with open(strategy_file) as f:
        return json.load(f)

def evaluate_strategy_against_trace(strategy: Dict, trace: Dict) -> Dict:
    """Evaluate how a strategy would have performed on a cached trace.
    
    This simulates running the strategy without making any LLM calls.
    We replay the trace and check if the strategy's constraints would have
    produced better or worse results.
    """
    tool_calls = trace.get('tool_calls', [])
    final_output = trace.get('final_output', '')
    
    # Simulate strategy execution
    simulated_calls = []
    total_tokens = 0
    phase_idx = 0
    current_phase = strategy['phases'][phase_idx] if strategy['phases'] else None
    
    for call in tool_calls:
        if not current_phase:
            break
        
        # Check if this call matches the current phase
        if call.get('tool') == current_phase.get('tool'):
            simulated_calls.append({
                'phase': current_phase['name'],
                'tool': call['tool'],
                'tokens': call.get('tokens', 0),
            })
            total_tokens += call.get('tokens', 0)
            
            # Check if we should advance to next phase
            if len([c for c in simulated_calls if c['phase'] == current_phase['name']]) >= current_phase.get('max_calls', 999):
                phase_idx += 1
                if phase_idx < len(strategy['phases']):
                    current_phase = strategy['phases'][phase_idx]
                else:
                    current_phase = None
        else:
            # Strategy mismatch — this call wouldn't have happened
            pass
    
    # Evaluate metrics
    cost_limit = strategy.get('cost_limit', 10000)
    expected_tokens = strategy.get('expected_tokens', 8000)
    
    # Would this strategy have stayed within budget?
    within_budget = total_tokens <= cost_limit
    
    # Did we reach the synthesize phase?
    reached_synthesis = any(c['phase'] == 'synthesize' for c in simulated_calls)
    
    # Output quality (based on actual output length)
    output_chars = len(final_output)
    min_output = strategy['phases'][-1].get('min_output_chars', 500) if strategy['phases'] else 500
    sufficient_output = output_chars >= min_output
    
    return {
        'strategy': strategy['name'],
        'session_id': trace['session_id'],
        'simulated_calls': len(simulated_calls),
        'actual_calls': len(tool_calls),
        'total_tokens': total_tokens,
        'within_budget': within_budget,
        'reached_synthesis': reached_synthesis,
        'sufficient_output': sufficient_output,
        'output_chars': output_chars,
        'efficiency_score': output_chars / max(total_tokens, 1),  # chars per token
        'would_succeed': within_budget and reached_synthesis and sufficient_output,
    }

def evaluate_all_strategies(session_id: Optional[str] = None):
    """Evaluate all strategies against traces.
    
    If session_id is provided, evaluate against that trace only.
    Otherwise, evaluate against all traces.
    """
    # Load all strategies
    strategies = []
    for f in STRATEGY_DIR.glob("*.json"):
        with open(f) as fh:
            strategies.append(json.load(fh))
    
    if not strategies:
        print("[eval] No strategies found. Run controller-dsl.py first.")
        return
    
    # Load traces
    if session_id:
        traces = [load_trace(session_id)]
    else:
        traces = []
        for f in TRACE_DIR.glob("*.json"):
            with open(f) as fh:
                traces.append(json.load(fh))
    
    traces = [t for t in traces if t]
    
    if not traces:
        print("[eval] No traces found. Researcher hasn't run yet.")
        return
    
    # Evaluate each strategy against each trace
    results = []
    for strategy in strategies:
        for trace in traces:
            result = evaluate_strategy_against_trace(strategy, trace)
            results.append(result)
    
    # Aggregate by strategy
    strategy_scores = {}
    for r in results:
        name = r['strategy']
        if name not in strategy_scores:
            strategy_scores[name] = {
                'total': 0,
                'would_succeed': 0,
                'avg_efficiency': 0,
                'avg_tokens': 0,
            }
        s = strategy_scores[name]
        s['total'] += 1
        if r['would_succeed']:
            s['would_succeed'] += 1
        s['avg_efficiency'] += r['efficiency_score']
        s['avg_tokens'] += r['total_tokens']
    
    for name in strategy_scores:
        s = strategy_scores[name]
        s['success_rate'] = s['would_succeed'] / s['total']
        s['avg_efficiency'] /= s['total']
        s['avg_tokens'] /= s['total']
    
    # Save results
    RESULTS_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(RESULTS_FILE, 'w') as f:
        json.dump({
            'timestamp': json.dumps({}),
            'strategies': strategy_scores,
            'details': results,
        }, f, indent=2)
    
    # Print summary
    print("\n[eval] Strategy Evaluation Results")
    print("=" * 60)
    sorted_strats = sorted(strategy_scores.items(), 
                          key=lambda x: x[1]['success_rate'], 
                          reverse=True)
    
    for name, scores in sorted_strats:
        print(f"\n{name}:")
        print(f"  Success rate: {scores['success_rate']:.1%} ({scores['would_succeed']}/{scores['total']})")
        print(f"  Avg efficiency: {scores['avg_efficiency']:.2f} chars/token")
        print(f"  Avg tokens: {scores['avg_tokens']:.0f}")
    
    best = sorted_strats[0] if sorted_strats else None
    if best:
        print(f"\n[eval] Best strategy: {best[0]} ({best[1]['success_rate']:.1%} success)")
    
    return strategy_scores

def main():
    import sys
    session_id = sys.argv[1] if len(sys.argv) > 1 else None
    evaluate_all_strategies(session_id)

if __name__ == '__main__':
    main()
