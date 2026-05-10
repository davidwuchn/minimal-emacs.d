#!/usr/bin/env python3
"""Evolve provider-error-analyzer skill based on experiment results.

Updates error patterns based on observed provider errors in experiments.
"""

import argparse
import json
import re
from pathlib import Path
from datetime import datetime
from collections import Counter


def analyze_error_patterns(analysis):
    """Extract common error patterns from experiments."""
    patterns = Counter()
    
    for stats in analysis.get('target_stats', []):
        for exp in stats.get('experiments', []):
            error = exp.get('error', '') or ''
            grader_reason = exp.get('grader_reason', '') or ''
            combined = error + ' ' + grader_reason
            
            # Categorize errors
            if 'quota' in combined.lower() or 'insufficient_quota' in combined.lower():
                patterns['quota-exhausted'] += 1
            if 'rate_limit' in combined.lower() or '429' in combined.lower():
                patterns['rate-limited'] += 1
            if 'timeout' in combined.lower() or 'timed out' in combined.lower():
                patterns['timeout'] += 1
            if 'auth' in combined.lower() or 'unauthorized' in combined.lower() or '401' in combined.lower():
                patterns['auth-failure'] += 1
            if 'server_error' in combined.lower() or '529' in combined.lower():
                patterns['server-error'] += 1
            if 'invalid_parameter' in combined.lower() or 'json' in combined.lower():
                patterns['invalid-parameter'] += 1
            if 'curl' in combined.lower() and 'failed' in combined.lower():
                patterns['network-error'] += 1
    
    return patterns


def generate_patterns(error_patterns):
    """Generate regex patterns from observed errors."""
    patterns = []
    
    pattern_map = {
        'quota-exhausted': {
            'regex': r'allocated quota exceeded|insufficient_quota|insufficient balance|billing_hard_limit_reached|hard limit reached',
            'category': 'hard-quota',
            'action': 'failover-to-backup-provider',
        },
        'rate-limited': {
            'regex': r'rate_limit_error|throttling|rate\.limit|429|overloaded_error|cluster overloaded|529|负载较高',
            'category': 'rate-limit',
            'action': 'exponential-backoff-retry',
        },
        'timeout': {
            'regex': r'timeout|timed out|curl failed with exit code 28|curl failed with exit code 56|operation timed out',
            'category': 'timeout',
            'action': 'retry-with-longer-timeout',
        },
        'auth-failure': {
            'regex': r'authorized_error|token is unusable|invalid[_ ]api[_ ]key|unauthorized|http_code "401"',
            'category': 'auth',
            'action': 'check-credentials-and-retry',
        },
        'server-error': {
            'regex': r'server_error|WebClientRequestException|Malformed JSON',
            'category': 'server',
            'action': 'retry-after-delay',
        },
        'invalid-parameter': {
            'regex': r'invalid_parameter_error|InvalidParameter|JSON format|Malformed JSON',
            'category': 'parameter',
            'action': 'fix-payload-and-retry',
        },
        'network-error': {
            'regex': r'curl failed with exit code 28|curl failed with exit code 56|operation timed out',
            'category': 'network',
            'action': 'retry-with-backoff',
        },
    }
    
    for pattern_name, count in error_patterns.most_common(10):
        if pattern_name in pattern_map:
            template = pattern_map[pattern_name]
            patterns.append({
                'name': pattern_name,
                'pattern': template['regex'],
                'category': template['category'],
                'action': template['action'],
                'frequency': count,
            })
    
    return patterns


def update_skill_file(output_dir, patterns):
    """Update the SKILL.md file with evolved patterns."""
    skill_file = Path(output_dir) / "SKILL.md"
    
    if not skill_file.exists():
        print(f"Skill file not found: {skill_file}")
        return
    
    with open(skill_file, 'r') as f:
        content = f.read()
    
    # Generate patterns section
    patterns_md = "\n## Evolved Error Patterns\n\n"
    patterns_md += "Based on analysis of experiment errors.\n\n"
    patterns_md += "| Pattern | Category | Action | Frequency | Regex |\n"
    patterns_md += "|---------|----------|--------|-----------|-------|\n"
    
    for p in patterns:
        patterns_md += "| {} | {} | {} | {} | `{}` |\n".format(
            p['name'], p['category'], p['action'], p['frequency'], p['pattern']
        )
    
    patterns_md += "\n"
    
    # Replace or append
    if "## Evolved Error Patterns" in content:
        content = re.sub(
            r"## Evolved Error Patterns.*?(?=\n## |\Z)",
            patterns_md.rstrip(),
            content,
            flags=re.DOTALL
        )
    else:
        content = content.rstrip() + "\n\n" + patterns_md
    
    content = re.sub(r'^updated: \d{4}-\d{2}-\d{2}( \d{2}:\d{2})?\n?', '', content, flags=re.MULTILINE)
    
    with open(skill_file, 'w') as f:
        f.write(content)
    
    print(f"Updated {skill_file} with {len(patterns)} evolved patterns")


def main():
    parser = argparse.ArgumentParser(description='Evolve provider-error-analyzer skill')
    parser.add_argument('--analysis', required=True, help='Path to analysis JSON')
    parser.add_argument('--output-dir', required=True, help='Output directory for skill')
    parser.add_argument('--root', default='.', help='Project root')
    args = parser.parse_args()
    
    with open(args.analysis, 'r') as f:
        analysis = json.load(f)
    
    error_patterns = analyze_error_patterns(analysis)
    patterns = generate_patterns(error_patterns)
    update_skill_file(args.output_dir, patterns)


if __name__ == '__main__':
    main()
