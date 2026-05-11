#!/usr/bin/env python3
"""Analyze experiment results and generate statistics for skill evolution.

Usage:
    python3 analyze_results.py [--root ROOT] [--output OUTPUT]

Reads all results.tsv files from var/tmp/experiments/ and produces
a JSON summary of target statistics, patterns, and performance metrics.
"""

import argparse
import csv
import json
import os
import re
import sys
from collections import defaultdict
from datetime import datetime
from pathlib import Path


def parse_results(root_dir):
    """Parse all results.tsv files under var/tmp/experiments/."""
    results_dir = Path(root_dir) / "var" / "tmp" / "experiments"
    records = []
    
    if not results_dir.exists():
        return records
    
    for run_dir in sorted(results_dir.iterdir()):
        if not run_dir.is_dir() or not run_dir.name.startswith("202"):
            continue
            
        tsv_file = run_dir / "results.tsv"
        if not tsv_file.exists():
            continue
            
        with open(tsv_file, 'r', newline='') as f:
            reader = csv.DictReader(f, delimiter='\t')
            for row in reader:
                if not row.get('target'):
                    continue
                records.append({
                    'target': row['target'],
                    'hypothesis': row.get('hypothesis', ''),
                    'score_before': float(row.get('score_before', 0) or 0),
                    'score_after': float(row.get('score_after', 0) or 0),
                    'code_quality': float(row.get('code_quality', 0) or 0),
                    'delta': row.get('delta', '0'),
                    'decision': row.get('decision', 'unknown'),
                    'grader_quality': float(row.get('grader_quality', 0) or 0),
                    'prompt_chars': int(row.get('prompt_chars', 0) or 0),
                    'research_strategy': row.get('research_strategy', 'none'),
                    'research_hash': row.get('research_hash', 'none'),
                    'timestamp': row.get('timestamp', ''),
                })
    
    return records


def compute_target_stats(records):
    """Compute statistics per target."""
    by_target = defaultdict(list)
    for r in records:
        by_target[r['target']].append(r)
    
    stats = []
    for target, target_records in by_target.items():
        total = len(target_records)
        kept = sum(1 for r in target_records if r['decision'] == 'kept')
        failed = sum(1 for r in target_records if r['decision'] == 'validation-failed')
        keep_rate = kept / total if total > 0 else 0.0
        
        stats.append({
            'target': target,
            'keep_rate': keep_rate,
            'total': total,
            'kept': kept,
            'failed': failed,
            'avg_score_before': sum(r['score_before'] for r in target_records) / total,
            'avg_score_after': sum(r['score_after'] for r in target_records) / total,
            'avg_quality': sum(r['code_quality'] for r in target_records) / total,
            'experiments': target_records,
        })
    
    # Sort by keep rate descending
    stats.sort(key=lambda x: x['keep_rate'], reverse=True)
    return stats


def compute_research_stats(records):
    """Compute statistics per research strategy."""
    by_strategy = defaultdict(list)
    for r in records:
        if r['research_strategy'] and r['research_strategy'] != 'none':
            by_strategy[r['research_strategy']].append(r)
    
    stats = []
    for strategy, strategy_records in by_strategy.items():
        total = len(strategy_records)
        kept = sum(1 for r in strategy_records if r['decision'] == 'kept')
        keep_rate = kept / total if total > 0 else 0.0
        
        stats.append({
            'strategy': strategy,
            'keep_rate': keep_rate,
            'total': total,
            'kept': kept,
        })
    
    stats.sort(key=lambda x: x['keep_rate'], reverse=True)
    return stats


def compute_prompt_stats(records):
    """Compute prompt size vs success correlation."""
    kept = [r for r in records if r['decision'] == 'kept']
    discarded = [r for r in records if r['decision'] == 'discarded']
    
    return {
        'avg_kept_prompt': sum(r['prompt_chars'] for r in kept) / len(kept) if kept else 0,
        'avg_discarded_prompt': sum(r['prompt_chars'] for r in discarded) / len(discarded) if discarded else 0,
        'total_experiments': len(records),
        'total_kept': len(kept),
        'total_discarded': len(discarded),
    }


def read_existing_total_experiments(root_dir):
    """Return the largest tracked total-experiments value in skill files."""
    skills_dir = Path(root_dir) / "assistant" / "skills"
    totals = []

    if not skills_dir.exists():
        return 0

    for skill_file in skills_dir.rglob("SKILL.md"):
        try:
            text = skill_file.read_text(encoding="utf-8")
        except OSError:
            continue
        for match in re.finditer(r'total-experiments:\s*(\d+)', text):
            totals.append(int(match.group(1)))

    return max(totals, default=0)


def main():
    parser = argparse.ArgumentParser(description='Analyze experiment results')
    parser.add_argument('--root', default='.', help='Project root directory')
    parser.add_argument('--output', '-o', default='-', 
                       help='Output file (default: stdout)')
    args = parser.parse_args()
    
    root_dir = os.path.expanduser(args.root)
    
    # Parse all results
    records = parse_results(root_dir)
    
    if not records:
        print("No experiment records found.", file=sys.stderr)
        sys.exit(1)
    
    # Compute statistics
    target_stats = compute_target_stats(records)
    research_stats = compute_research_stats(records)
    prompt_stats = compute_prompt_stats(records)
    
    existing_total = read_existing_total_experiments(root_dir)
    total_experiments = max(len(records), existing_total)

    # Build output
    output = {
        'generated_at': datetime.now().isoformat(),
        'total_experiments': total_experiments,
        'local_experiments': len(records),
        'existing_total_experiments': existing_total,
        'target_stats': target_stats,
        'research_stats': research_stats,
        'prompt_stats': prompt_stats,
    }
    
    # Write output
    json_str = json.dumps(output, indent=2)
    
    if args.output == '-':
        print(json_str)
    else:
        output_path = Path(args.output)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        with open(output_path, 'w') as f:
            f.write(json_str)
        print(f"Analysis written to {output_path}", file=sys.stderr)


if __name__ == '__main__':
    main()
