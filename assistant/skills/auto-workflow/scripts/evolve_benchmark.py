#!/usr/bin/env python3
"""Evolve benchmark-improver skill based on experiment results.

Adds data-driven suggestions to the benchmark-improver SKILL.md file.
"""

import argparse
import json
import re
from pathlib import Path
from datetime import datetime
from collections import defaultdict, Counter


def analyze_patterns(analysis):
    """Analyze which hypothesis patterns correlate with success."""
    element_keywords = {
        'wood': ['efficient', 'step', 'cache', 'operation', 'speed', 'fast', 'performance', 'optimize', 'reduce', 'simplify'],
        'fire': ['plan', 'principle', 'analysis', 'foresight', 'research', 'investigate', 'explore', 'understand', 'design'],
        'earth': ['constraint', 'timeout', 'limit', 'rigid', 'control', 'check', 'validate', 'verify', 'test', 'guard'],
        'metal': ['flexible', 'tool', 'sequence', 'alternative', 'compose', 'combine', 'merge', 'integrate', 'coordination'],
        'water': ['purpose', 'goal', 'identity', 'clarity', 'meaning', 'intent', 'direction', 'focus', 'aim'],
    }
    
    element_results = defaultdict(lambda: {'total': 0, 'kept': 0, 'improved': 0})
    
    for stats in analysis.get('target_stats', []):
        for exp in stats.get('experiments', []):
            hyp = exp.get('hypothesis', '').lower()
            decision = exp.get('decision', '')
            score_before = exp.get('score_before', 0)
            score_after = exp.get('score_after', 0)
            
            scores = {e: sum(1 for kw in kws if kw in hyp) for e, kws in element_keywords.items()}
            valid = {e: s for e, s in scores.items() if s > 0}
            
            if valid:
                dominant = max(valid, key=valid.get)
                element_results[dominant]['total'] += 1
                if decision == 'kept':
                    element_results[dominant]['kept'] += 1
                if score_after > score_before:
                    element_results[dominant]['improved'] += 1
    
    return element_results


def extract_phrases(analysis):
    """Extract common action phrases from kept experiments."""
    kept = []
    for stats in analysis.get('target_stats', []):
        for exp in stats.get('experiments', []):
            if exp.get('decision') == 'kept':
                kept.append(exp.get('hypothesis', ''))
    
    phrases = Counter()
    for hyp in kept:
        matches = re.findall(r'\b(Add|Fix|Remove|Prevent|Handle|Check|Validate|Ensure|Improve|Optimize|Refactor|Extract|Move|Rename|Update|Implement|Create)\s+([A-Za-z_\-]+)', hyp)
        for verb, noun in matches:
            phrases[f"{verb} {noun}"] += 1
    
    return phrases.most_common(8)


def generate_evolved_md(element_results, phrases):
    """Generate markdown for evolved recommendations."""
    now = datetime.now().strftime('%Y-%m-%d %H:%M')
    
    md = f"\n## Evolved Recommendations (Updated {now})\n\n"
    md += f"Based on analysis of {sum(s['total'] for s in element_results.values())} experiments.\n\n"
    
    element_names = {
        'wood': 'Wood (Operations)',
        'fire': 'Fire (Intelligence)', 
        'earth': 'Earth (Control)',
        'metal': 'Metal (Coordination)',
        'water': 'Water (Identity)',
    }
    
    for element, name in element_names.items():
        stats = element_results.get(element, {'total': 0, 'kept': 0})
        if stats['total'] < 2:
            continue
        
        keep_rate = stats['kept'] / stats['total']
        md += f"### {name}\n\n"
        md += f"- **Success rate:** {keep_rate:.0%} ({stats['kept']}/{stats['total']} experiments)\n"
        
        if keep_rate > 0.15:
            md += "- **Priority:** HIGH - prioritize improvements targeting this element\n"
        elif keep_rate > 0.1:
            md += "- **Priority:** MEDIUM - moderate success with this element\n"
        else:
            md += "- **Priority:** LOW - limited success, reconsider approach\n"
        
        md += "\n"
    
    if phrases:
        md += "### Top Successful Patterns\n\n"
        md += "These action patterns appear most frequently in kept experiments:\n\n"
        for phrase, count in phrases:
            md += f"- {phrase} ({count} times)\n"
        md += "\n"
    
    return md


def update_skill_file(output_dir, evolved_md):
    """Append evolved recommendations to SKILL.md."""
    skill_file = Path(output_dir) / "SKILL.md"
    
    if not skill_file.exists():
        print(f"Skill file not found: {skill_file}")
        return
    
    with open(skill_file, 'r') as f:
        content = f.read()
    
    # Remove old evolved section if present
    content = re.sub(r'\n## Evolved Recommendations.*', '', content, flags=re.DOTALL)
    
    # Append new evolved section
    content = content.rstrip() + evolved_md
    
    # Update timestamp
    now = datetime.now().strftime('%Y-%m-%d %H:%M')
    content = re.sub(
        r'updated: \d{4}-\d{2}-\d{2}( \d{2}:\d{2})?',
        f'updated: {now}',
        content
    )
    
    with open(skill_file, 'w') as f:
        f.write(content)
    
    print(f"Updated {skill_file} with evolved recommendations")


def main():
    parser = argparse.ArgumentParser(description='Evolve benchmark-improver skill')
    parser.add_argument('--analysis', required=True, help='Path to analysis JSON')
    parser.add_argument('--output-dir', required=True, help='Output directory for skill')
    parser.add_argument('--root', default='.', help='Project root')
    args = parser.parse_args()
    
    with open(args.analysis, 'r') as f:
        analysis = json.load(f)
    
    element_results = analyze_patterns(analysis)
    phrases = extract_phrases(analysis)
    evolved_md = generate_evolved_md(element_results, phrases)
    update_skill_file(args.output_dir, evolved_md)


if __name__ == '__main__':
    main()
