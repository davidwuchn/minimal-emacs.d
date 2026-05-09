#!/usr/bin/env python3
"""Evolve evolution-patterns skill based on experiment results.

Updates hypothesis categories and score predictor based on observed outcomes.
"""

import argparse
import json
import re
from pathlib import Path
from datetime import datetime
from collections import defaultdict


def analyze_hypothesis_patterns(analysis):
    """Analyze which hypothesis patterns predict success."""
    category_stats = defaultdict(lambda: {'total': 0, 'kept': 0})
    keyword_stats = defaultdict(lambda: {'total': 0, 'kept': 0})
    
    for stats_item in analysis.get('target_stats', []):
        for exp in stats_item.get('experiments', []):
            hypothesis = exp.get('hypothesis', '') or ''
            decision = exp.get('decision', '') or ''
            
            # Extract keywords
            keywords = set(hypothesis.lower().split())
            
            for kw in keywords:
                keyword_stats[kw]['total'] += 1
                if decision == 'kept':
                    keyword_stats[kw]['kept'] += 1
    
    # Find high-signal keywords
    high_signal = {}
    for kw, data in keyword_stats.items():
        if data['total'] >= 5:  # Minimum sample size
            rate = data['kept'] / data['total']
            if rate > 0.3 or rate < 0.1:  # Strong signal
                high_signal[kw] = {
                    'rate': rate,
                    'total': data['total'],
                    'kept': data['kept']
                }
    
    return high_signal


def update_skill(skill_path, patterns):
    """Update skill file with evolved patterns."""
    with open(skill_path, 'r') as f:
        content = f.read()
    
    now = datetime.now().strftime('%Y-%m-%d %H:%M')
    
    evolution_section = f"""\n\n## Evolved Patterns\n\nUpdated: {now}\n\n### High-Signal Keywords\n\n"""
    
    # Sort by success rate
    sorted_patterns = sorted(patterns.items(), key=lambda x: x[1]['rate'], reverse=True)
    
    for kw, data in sorted_patterns[:20]:  # Top 20
        evolution_section += f"- `{kw}`: {data['rate']:.0%} ({data['kept']}/{data['total']})\n"
    
    if '## Evolved Patterns' not in content:
        content = content.rstrip() + evolution_section
    else:
        content = re.sub(
            r'## Evolved Patterns.*?(?=\n## |\Z)',
            evolution_section.strip(),
            content,
            flags=re.DOTALL
        )
    
    with open(skill_path, 'w') as f:
        f.write(content)


def main():
    parser = argparse.ArgumentParser(description='Evolve experiment patterns')
    parser.add_argument('--analysis', help='Path to analysis results JSON')
    parser.add_argument('--output-dir', help='Output directory')
    parser.add_argument('--root', help='Project root')
    parser.add_argument('analysis_json', nargs='?', help='Path to analysis results JSON (legacy)')
    parser.add_argument('--skill', default='SKILL.md', help='Path to skill file')
    args = parser.parse_args()
    
    # Determine analysis path
    analysis_path = args.analysis or args.analysis_json
    if not analysis_path:
        parser.error("--analysis or analysis_json required")
    
    # Determine skill path
    skill_path = args.skill
    if args.output_dir:
        skill_path = Path(args.output_dir) / 'SKILL.md'
    
    with open(analysis_path) as f:
        analysis = json.load(f)
    
    patterns = analyze_hypothesis_patterns(analysis)
    update_skill(skill_path, patterns)
    print(f"[evolve] Updated evolution-patterns skill with {len(patterns)} patterns")


if __name__ == '__main__':
    main()
