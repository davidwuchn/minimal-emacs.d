#!/usr/bin/env python3
"""Evolve eight-keys-grader skill based on experiment results.

Updates scoring weights and signal patterns based on which keys
correlate with experiment success.
"""

import argparse
import json
import re
from pathlib import Path
from datetime import datetime


def analyze_key_performance(analysis):
    """Analyze which Eight Keys correlate with success."""
    key_scores = {}
    
    for stats in analysis.get('target_stats', []):
        for exp in stats.get('experiments', []):
            keys = exp.get('eight_keys', {})
            passed = exp.get('passed', False)
            
            for key, score in keys.items():
                if key not in key_scores:
                    key_scores[key] = {'success': [], 'failure': []}
                
                if passed:
                    key_scores[key]['success'].append(score)
                else:
                    key_scores[key]['failure'].append(score)
    
    # Calculate average scores
    results = {}
    for key, data in key_scores.items():
        success_avg = sum(data['success']) / len(data['success']) if data['success'] else 0
        failure_avg = sum(data['failure']) / len(data['failure']) if data['failure'] else 0
        results[key] = {
            'success_avg': success_avg,
            'failure_avg': failure_avg,
            'discrimination': success_avg - failure_avg,
            'count': len(data['success']) + len(data['failure'])
        }
    
    return results


def generate_weights(key_stats):
    """Generate updated weights based on discrimination power."""
    weights = {}
    
    for key, stats in key_stats.items():
        # Higher discrimination = higher weight
        base_weight = 1.0
        if stats['discrimination'] > 0.3:
            base_weight = 1.5
        elif stats['discrimination'] > 0.1:
            base_weight = 1.2
        elif stats['discrimination'] < -0.1:
            base_weight = 0.8
        
        weights[key] = round(base_weight, 2)
    
    return weights


def update_skill_file(output_dir, key_stats, weights):
    """Update the SKILL.md file with evolved rubric."""
    skill_file = Path(output_dir) / "SKILL.md"
    
    if not skill_file.exists():
        print(f"Skill file not found: {skill_file}")
        return
    
    with open(skill_file, 'r') as f:
        content = f.read()
    
    # Generate weights section
    weights_md = "\n## Evolved Weights\n\n"
    weights_md += "Based on analysis of experiment results.\n\n"
    weights_md += "| Key | Weight | Discrimination | Avg (Success) | Avg (Failure) |\n"
    weights_md += "|-----|--------|----------------|---------------|---------------|\n"
    
    for key in sorted(weights.keys()):
        stats = key_stats[key]
        weights_md += "| {} | {:.2f} | {:+.2f} | {:.2f} | {:.2f} |\n".format(
            key, weights[key], stats['discrimination'],
            stats['success_avg'], stats['failure_avg']
        )
    
    weights_md += "\n"
    
    # Replace or append
    if "## Evolved Weights" in content:
        content = re.sub(
            r"## Evolved Weights.*?(?=\n## |\Z)",
            weights_md.rstrip(),
            content,
            flags=re.DOTALL
        )
    else:
        content = content.rstrip() + "\n\n" + weights_md
    
    # Update timestamp
    now = datetime.now().strftime('%Y-%m-%d %H:%M')
    content = re.sub(
        r'updated: \d{4}-\d{2}-\d{2}( \d{2}:\d{2})?',
        f'updated: {now}',
        content
    )
    
    with open(skill_file, 'w') as f:
        f.write(content)
    
    print(f"Updated {skill_file} with evolved weights for {len(weights)} keys")


def main():
    parser = argparse.ArgumentParser(description='Evolve eight-keys-grader skill')
    parser.add_argument('--analysis', required=True, help='Path to analysis JSON')
    parser.add_argument('--output-dir', required=True, help='Output directory for skill')
    parser.add_argument('--root', default='.', help='Project root')
    args = parser.parse_args()
    
    with open(args.analysis, 'r') as f:
        analysis = json.load(f)
    
    key_stats = analyze_key_performance(analysis)
    weights = generate_weights(key_stats)
    update_skill_file(args.output_dir, key_stats, weights)


if __name__ == '__main__':
    main()
