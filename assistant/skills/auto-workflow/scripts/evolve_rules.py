#!/usr/bin/env python3
"""Evolve elisp-validator skill based on experiment results.

Updates validation rules based on common failure patterns in
experiment outputs.
"""

import argparse
import json
import re
from pathlib import Path
from datetime import datetime
from collections import Counter


def analyze_failure_patterns(analysis):
    """Extract common patterns from failed experiments."""
    patterns = Counter()
    
    for stats in analysis.get('target_stats', []):
        for exp in stats.get('experiments', []):
            if not exp.get('passed', False):
                error = exp.get('error', '') or exp.get('grader_reason', '')
                # Extract common error patterns
                if 'unbound' in error.lower() or 'void-variable' in error.lower():
                    patterns['unbound-variable'] += 1
                if 'wrong-number-of-arguments' in error.lower():
                    patterns['wrong-arity'] += 1
                if 'invalid-function' in error.lower():
                    patterns['invalid-function'] += 1
                if 'scan-error' in error.lower() or 'unbalanced' in error.lower():
                    patterns['paren-imbalance'] += 1
                if 'end-of-file' in error.lower():
                    patterns['premature-eof'] += 1
    
    return patterns


def generate_rules(patterns):
    """Generate validation rules from observed patterns."""
    rules = []
    
    rule_templates = {
        'unbound-variable': {
            'check': 'Verify all variables are bound or declared with defvar',
            'severity': 'error',
            'pattern': r'\b\w+\b(?=.*not.*defined)',
        },
        'wrong-arity': {
            'check': 'Verify function call argument counts match definitions',
            'severity': 'error',
            'pattern': r'wrong-number-of-arguments',
        },
        'invalid-function': {
            'check': 'Verify function references are valid symbols',
            'severity': 'error',
            'pattern': r'invalid-function',
        },
        'paren-imbalance': {
            'check': 'Verify all parentheses are balanced',
            'severity': 'error',
            'pattern': r'unbalanced|scan-error',
        },
        'premature-eof': {
            'check': 'Verify no truncated forms or missing closing delimiters',
            'severity': 'error',
            'pattern': r'end of file during parsing',
        },
    }
    
    for pattern_name, count in patterns.most_common(10):
        if pattern_name in rule_templates:
            template = rule_templates[pattern_name]
            rules.append({
                'name': pattern_name,
                'check': template['check'],
                'severity': template['severity'],
                'frequency': count,
                'pattern': template['pattern'],
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
    
    # Generate rules section
    rules_md = "\n## Evolved Validation Rules\n\n"
    rules_md += "Based on analysis of failed experiments.\n\n"
    rules_md += "| Rule | Severity | Frequency | Check |\n"
    rules_md += "|------|----------|-----------|-------|\n"
    
    for rule in rules:
        rules_md += "| {} | {} | {} | {} |\n".format(
            rule['name'], rule['severity'], rule['frequency'], rule['check']
        )
    
    rules_md += "\n"
    
    # Replace or append
    if "## Evolved Validation Rules" in content:
        content = re.sub(
            r"## Evolved Validation Rules.*?(?=\n## |\Z)",
            rules_md.rstrip(),
            content,
            flags=re.DOTALL
        )
    else:
        content = content.rstrip() + "\n\n" + rules_md
    
    content = re.sub(r'^updated: \d{4}-\d{2}-\d{2}( \d{2}:\d{2})?\n?', '', content, flags=re.MULTILINE)
    
    with open(skill_file, 'w') as f:
        f.write(content)
    
    print(f"Updated {skill_file} with {len(rules)} evolved rules")


def main():
    parser = argparse.ArgumentParser(description='Evolve elisp-validator skill')
    parser.add_argument('--analysis', required=True, help='Path to analysis JSON')
    parser.add_argument('--output-dir', required=True, help='Output directory for skill')
    parser.add_argument('--root', default='.', help='Project root')
    args = parser.parse_args()
    
    with open(args.analysis, 'r') as f:
        analysis = json.load(f)
    
    patterns = analyze_failure_patterns(analysis)
    rules = generate_rules(patterns)
    update_skill_file(args.output_dir, rules)


if __name__ == '__main__':
    main()
