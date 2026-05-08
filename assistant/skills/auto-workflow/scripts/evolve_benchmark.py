#!/usr/bin/env python3
"""Evolve benchmark-improver skill based on experiment results.

Updates Wu Xing improvement rules based on which improvements
actually led to better benchmark scores.
"""

import argparse
import json
import re
from pathlib import Path
from datetime import datetime
from collections import defaultdict, Counter


def analyze_improvement_effectiveness(analysis):
    """Analyze which improvement patterns correlate with success."""
    element_results = defaultdict(lambda: {'improved': 0, 'worsened': 0, 'total': 0, 'kept': 0})
    
    # Map hypothesis keywords to Wu Xing elements
    element_keywords = {
        'wood': ['efficient', 'step', 'cache', 'operation', 'speed', 'fast', 'performance', 'optimize', 'reduce', 'simplify', 'remove', 'clean'],
        'fire': ['plan', 'principle', 'analysis', 'foresight', 'research', 'investigate', 'explore', 'understand', 'design', 'architect'],
        'earth': ['constraint', 'timeout', 'limit', 'rigid', 'control', 'check', 'validate', 'verify', 'test', 'guard', 'safe'],
        'metal': ['flexible', 'tool', 'sequence', 'alternative', 'compose', 'combine', 'merge', 'integrate', 'coordination', 'pattern'],
        'water': ['purpose', 'goal', 'identity', 'clarity', 'meaning', 'intent', 'direction', 'focus', 'aim', 'objective'],
    }
    
    for stats in analysis.get('target_stats', []):
        for exp in stats.get('experiments', []):
            hypothesis = exp.get('hypothesis', '').lower()
            score_before = exp.get('score_before', 0)
            score_after = exp.get('score_after', 0)
            decision = exp.get('decision', '')
            
            # Determine which element this hypothesis targets
            element_scores = {}
            for element, keywords in element_keywords.items():
                score = sum(1 for kw in keywords if kw in hypothesis)
                if score > 0:
                    element_scores[element] = score
            
            if not element_scores:
                continue
            
            # Pick the dominant element
            dominant = max(element_scores, key=element_scores.get)
            
            element_results[dominant]['total'] += 1
            if decision == 'kept':
                element_results[dominant]['kept'] += 1
            if score_after > score_before:
                element_results[dominant]['improved'] += 1
            elif score_after < score_before:
                element_results[dominant]['worsened'] += 1
    
    return element_results


def analyze_hypothesis_patterns(analysis):
    """Extract common words/phrases from successful hypotheses."""
    kept_hypotheses = []
    discarded_hypotheses = []
    
    for stats in analysis.get('target_stats', []):
        for exp in stats.get('experiments', []):
            hyp = exp.get('hypothesis', '')
            if exp.get('decision') == 'kept':
                kept_hypotheses.append(hyp)
            else:
                discarded_hypotheses.append(hyp)
    
    # Extract action words (verbs) from kept hypotheses
    kept_words = Counter()
    for hyp in kept_hypotheses:
        words = re.findall(r'\b[A-Za-z]{4,}\b', hyp.lower())
        for w in words:
            if w not in ('function', 'defun', 'variable', 'module', 'lisp', 'emacs', 'gptel', 'workflow', 'target', 'experiment'):
                kept_words[w] += 1
    
    return {
        'kept_count': len(kept_hypotheses),
        'discarded_count': len(discarded_hypotheses),
        'top_words': kept_words.most_common(15),
    }


def generate_improvement_rules(element_results):
    """Generate updated improvement rules based on effectiveness."""
    rules = []
    
    element_names = {
        'wood': 'Operations (Wood)',
        'fire': 'Intelligence (Fire)',
        'earth': 'Control (Earth)',
        'metal': 'Coordination (Metal)',
        'water': 'Identity (Water)',
    }
    
    for element, stats in sorted(element_results.items()):
        if stats['total'] < 2:
            continue
        
        keep_rate = stats['kept'] / stats['total']
        improvement_rate = stats['improved'] / stats['total']
        
        if keep_rate > 0.2:
            effectiveness = 'highly-effective'
        elif keep_rate > 0.1:
            effectiveness = 'moderately-effective'
        elif keep_rate > 0.05:
            effectiveness = 'marginally-effective'
        else:
            effectiveness = 'ineffective'
        
        rules.append({
            'element': element,
            'name': element_names.get(element, element),
            'keep_rate': keep_rate,
            'improvement_rate': improvement_rate,
            'effectiveness': effectiveness,
            'total': stats['total'],
            'kept': stats['kept'],
            'improved': stats['improved'],
            'worsened': stats['worsened'],
        })
    
    return rules


def update_skill_file(output_dir, rules, patterns):
    """Update the SKILL.md file with evolved rules."""
    skill_file = Path(output_dir) / "SKILL.md"
    
    if not skill_file.exists():
        print(f"Skill file not found: {skill_file}")
        return
    
    with open(skill_file, 'r') as f:
        content = f.read()
    
    # Generate effectiveness section
    rules_md = "\n## Evolved Improvement Effectiveness\n\n"
    rules_md += f"Based on analysis of {patterns['kept_count']} kept and {patterns['discarded_count']} discarded experiments.\n\n"
    rules_md += "| Element | Effectiveness | Keep Rate | Improvement Rate | Total | Kept |\n"
    rules_md += "|---------|---------------|-----------|------------------|-------|------|\n"
    
    for rule in rules:
        rules_md += "| {} | {} | {:.0%} | {:.0%} | {} | {} |\n".format(
            rule['name'], rule['effectiveness'], rule['keep_rate'],
            rule['improvement_rate'], rule['total'], rule['kept']
        )
    
    rules_md += "\n"
    
    # Add top words from successful hypotheses
    if patterns['top_words']:
        rules_md += "### Top Words in Successful Hypotheses\n\n"
        rules_md += "These words appear most frequently in hypotheses that were kept:\n\n"
        for word, count in patterns['top_words'][:10]:
            rules_md += f"- **{word}**: {count} times\n"
        rules_md += "\n"
    
    # Add recommendations
    effective = [r for r in rules if r['effectiveness'] in ('highly-effective', 'moderately-effective')]
    ineffective = [r for r in rules if r['effectiveness'] in ('marginally-effective', 'ineffective')]
    
    if effective:
        rules_md += "### Prioritize These Improvement Types\n\n"
        for r in effective:
            rules_md += "- {} ({:.0%} keep rate, {} kept out of {})\n".format(
                r['name'], r['keep_rate'], r['kept'], r['total']
            )
        rules_md += "\n"
    
    if ineffective:
        rules_md += "### Reconsider These Improvement Types\n\n"
        for r in ineffective:
            rules_md += "- {} ({:.0%} keep rate, {} total attempts)\n".format(
                r['name'], r['keep_rate'], r['total']
            )
        rules_md += "\n"
    
    # Replace or append
    if "## Evolved Improvement Effectiveness" in content:
        content = re.sub(
            r"## Evolved Improvement Effectiveness.*?(?=\n## |\Z)",
            rules_md.rstrip(),
            content,
            flags=re.DOTALL
        )
    else:
        content = content.rstrip() + "\n\n" + rules_md
    
    # Update timestamp
    now = datetime.now().strftime('%Y-%m-%d %H:%M')
    content = re.sub(
        r'updated: \d{4}-\d{2}-\d{2}( \d{2}:\d{2})?',
        f'updated: {now}',
        content
    )
    
    with open(skill_file, 'w') as f:
        f.write(content)
    
    print(f"Updated {skill_file} with effectiveness data for {len(rules)} elements")


def main():
    parser = argparse.ArgumentParser(description='Evolve benchmark-improver skill')
    parser.add_argument('--analysis', required=True, help='Path to analysis JSON')
    parser.add_argument('--output-dir', required=True, help='Output directory for skill')
    parser.add_argument('--root', default='.', help='Project root')
    args = parser.parse_args()
    
    with open(args.analysis, 'r') as f:
        analysis = json.load(f)
    
    element_results = analyze_improvement_effectiveness(analysis)
    patterns = analyze_hypothesis_patterns(analysis)
    rules = generate_improvement_rules(element_results)
    update_skill_file(args.output_dir, rules, patterns)


if __name__ == '__main__':
    main()
