#!/usr/bin/env python3
"""AutoTTS-style research strategy evolution for minimal-emacs.d

Core idea from AutoTTS: 
- Cache research sessions with outcomes (replay store)
- Evaluate strategies against cached data (offline, no LLM calls)
- Evolve strategies based on measured performance
"""
import csv
import glob
import json
import hashlib
from pathlib import Path
from datetime import datetime

ROOT = Path(__file__).resolve().parents[4]
REPLAY_FILE = ROOT / "var/tmp/research-replay-store.json"
STRATEGY_FILE = ROOT / "var/tmp/researcher-strategy.json"

def load_replay_store():
    if REPLAY_FILE.exists():
        with open(REPLAY_FILE) as f:
            return json.load(f)
    return {"version": "1.0", "sessions": [], "strategies": {}}

def save_replay_store(store):
    REPLAY_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(REPLAY_FILE, 'w') as f:
        json.dump(store, f, indent=2)

def parse_latest_tsv():
    """Parse the most recent experiment TSV for research outcomes."""
    tsv_files = sorted(glob.glob(str(ROOT / "var/tmp/experiments/*/results.tsv")))
    if not tsv_files:
        return None
    
    latest = tsv_files[-1]
    experiments = []
    with open(latest) as f:
        reader = csv.DictReader(f, delimiter='\t')
        for row in reader:
            experiments.append(row)
    return experiments

def extract_research_session(experiments):
    """Extract research session data from experiments."""
    if not experiments:
        return None
    
    # Find research-enabled experiments
    research_exps = [e for e in experiments 
                     if e.get('research_quality') and e['research_quality'] != 'none']
    
    if not research_exps:
        return None
    
    # Get unique research hash
    hashes = set(e.get('research_hash', 'none') for e in research_exps)
    hashes.discard('none')
    
    if not hashes:
        return None
    
    rhash = list(hashes)[0]
    kept = sum(1 for e in research_exps if e.get('decision') == 'kept')
    total = len(research_exps)
    
    # Get strategy used
    strategies = set(e.get('research_strategy', 'none') for e in research_exps)
    strategies.discard('none')
    strategy = list(strategies)[0] if strategies else 'unknown'
    
    return {
        'timestamp': datetime.now().isoformat(),
        'hash': rhash,
        'strategy': strategy,
        'experiments_total': total,
        'experiments_kept': kept,
        'keep_rate': kept / total if total > 0 else 0,
        'targets': [e.get('target', '') for e in research_exps],
    }

def update_strategy_performance(store, session):
    """Update strategy performance metrics."""
    strat = session['strategy']
    if strat not in store['strategies']:
        store['strategies'][strat] = {
            'name': strat,
            'total_experiments': 0,
            'total_kept': 0,
            'sessions': [],
        }
    
    s = store['strategies'][strat]
    s['total_experiments'] += session['experiments_total']
    s['total_kept'] += session['experiments_kept']
    s['keep_rate'] = s['total_kept'] / s['total_experiments'] if s['total_experiments'] > 0 else 0
    s['sessions'].append({
        'timestamp': session['timestamp'],
        'hash': session['hash'],
        'keep_rate': session['keep_rate'],
    })

def generate_strategy_guidance(store):
    """Generate guidance for researcher based on replay store data."""
    if not store['strategies']:
        return "No historical data yet. Use default strategy."
    
    # Sort by keep rate
    sorted_strats = sorted(
        store['strategies'].values(),
        key=lambda x: x.get('keep_rate', 0),
        reverse=True
    )
    
    lines = ["## Strategy Performance (from replay store)", ""]
    for s in sorted_strats[:5]:
        lines.append(f"- **{s['name']}**: {s['keep_rate']:.1%} keep rate ({s['total_kept']}/{s['total_experiments']} experiments)")
    
    best = sorted_strats[0]
    lines.extend([
        "",
        f"## Best Strategy: {best['name']}",
        f"This strategy has the highest keep rate at {best['keep_rate']:.1%}.",
        "PREFER this strategy when similar topics arise.",
        "",
        "## Strategy Evolution Rules",
        "1. If current strategy's keep rate < 10% after 10+ experiments: ABANDON",
        "2. If current strategy's keep rate > 30%: DOUBLE DOWN, use more aggressively",
        "3. If no strategy > 20%: INNOVATE, try completely different approach",
    ])
    
    return "\n".join(lines)

def main():
    store = load_replay_store()
    
    experiments = parse_latest_tsv()
    if experiments:
        session = extract_research_session(experiments)
        if session:
            store['sessions'].append(session)
            update_strategy_performance(store, session)
            save_replay_store(store)
            print(f"Added session: {session['hash'][:8]} - {session['strategy']} - {session['keep_rate']:.1%}")
    
    guidance = generate_strategy_guidance(store)
    
    # Write guidance for researcher
    STRATEGY_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(STRATEGY_FILE, 'w') as f:
        json.dump({
            'guidance': guidance,
            'timestamp': datetime.now().isoformat(),
            'strategies': store['strategies'],
        }, f, indent=2)
    
    print(f"\nStrategy guidance written to {STRATEGY_FILE}")
    print("\n" + guidance)

if __name__ == '__main__':
    main()
