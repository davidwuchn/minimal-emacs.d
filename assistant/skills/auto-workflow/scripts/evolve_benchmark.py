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
from collections import defaultdict


def analyze_improvement_effectiveness(analysis):
    """Analyze which improvement types led to score increases."""
    element_results = defaultdict(lambda: {'improved': 0, 'worsened': 0, 'total': 0})
    
    for target, stats in analysis.get('target_stats', {}).items():
        experiments = stats.get('experiments', [])
        for i, exp in enumerate(experiments):
            if i == 0:
                continue
            
            prev = experiments[i - 1]
            prev_score = prev.get('score_after', prev.get('score', 0))
            curr_score = exp.get('score_after', exp.get('score', 0))
            
            # Detect improvement type from hypothesis or tags
            hypothesis = exp.get('hypothesis', '').lower()
            element = None
            
            if any(w in hypothesis for w in ['efficient', 'step', 'cache', 'operation']):
                element = 'wood'
            elif any(w in hypothesis for w in ['plan', 'principle', 'analysis', 'foresight']):
                element = 'fire'
            elif any(w in hypothesis for w in ['constraint', 'timeout', 'limit', 'rigid']):
                element = 'earth'
            elif any(w in hypothesis for w in ['flexible', 'tool', 'sequence', 'alternative']):
                element = 'metal'
            elif any(w in hypothesis for w in ['purpose', 'goal', 'identity', 'clarity']):
                element = 'water'
            
            if element:
                element_results[element]['total'] += 1
                if curr_score > prev_score:
                    element_results[element]['improved'] += 1
                elif curr_score < prev_score:
                    element_results[element]['worsened'] += 1
    
    return element_results


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
        
        improvement_rate = stats['improved'] / stats['total']
        
        if improvement_rate > 0.6:
            effectiveness = 'highly-effective'
        elif improvement_rate > 0.4:
            effectiveness = 'moderately-effective'
        elif improvement_rate > 0.2:
            effectiveness = 'marginally-effective'
        else:
            effectiveness = 'ineffective'
        
        rules.append({
            'element': element,
            'name': element_names.get(element, element),
            'improvement_rate': improvement_rate,
            'effectiveness': effectiveness,
            'total': stats['total'],
            'improved': stats['improved'],
            'worsened': stats['worsened'],
        })
    
    return rules


def update_skill_file(output_dir, rules):
    """Update the SKILL.md file with evolved rules."""
    skill_file = Path(output_dir) / "SKILL.md"
    
    if not skill_file.exists():
        print(f"Skill file not found: {skill_file}")
        return
    
    with open(skill_file, 'r') as f:
        content = f.read()
    
    # Generate effectiveness section
    rules_md = "\n## Evolved Improvement Effectiveness\n\n"
    rules_md += "Based on analysis of which improvement types led to score increases.\n\n"
    rules_md += "| Element | Effectiveness | Improvement Rate | Total | Improved | Worsened |\n"
    rules_md += "|---------|---------------|------------------|-------|----------|----------|\n"
    
    for rule in rules:
        rules_md += "| {} | {} | {:.0%} | {} | {} | {} |\n".format(
            rule['name'], rule['effectiveness'], rule['improvement_rate'],
            rule['total'], rule['improved'], rule['worsened']
        )
    
    rules_md += "\n"
    rules_md += "### Recommendations\n\n"
    
    effective = [r for r in rules if r['effectiveness'] in ('highly-effective', 'moderately-effective')]
    ineffective = [r for r in rules if r['effectiveness'] in ('marginally-effective', 'ineffective')]
    
    if effective:
        rules_md += "**Prioritize these improvement types:**\n"
        for r in effective:
            rules_md += "- {} ({:.0%} success rate)\n".format(r['name'], r['improvement_rate'])
        rules_md += "\n"
    
    if ineffective:
        rules_md += "**Reconsider these improvement types:**\n"
        for r in ineffective:
            rules_md += "- {} ({:.0%} success rate, {} worsened)\n".format(
                r['name'], r['improvement_rate'], r['worsened']
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
    rules = generate_improvement_rules(element_results)
    update_skill_file(args.output_dir, rules)


if __name__ == '__main__':
    main()
