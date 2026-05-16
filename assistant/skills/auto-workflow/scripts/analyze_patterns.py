#!/usr/bin/env python3
"""Meta-learning pattern analyzer for directive evolution.

Analyzes mementum memories + git history to extract success/failure patterns.
Produces pattern data that generate_directive.py uses to create data-driven directives.

Usage:
    python3 analyze_patterns.py --root ROOT --output OUTPUT_JSON
"""

import argparse
import json
import os
import re
import subprocess
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path


def valid_technique(technique):
    """Return True if TECHNIQUE is an actionable mementum label."""
    if not (15 < len(technique) < 120):
        return False
    if technique.startswith('```') or technique.startswith('**'):
        return False
    if re.match(r'^\d{4}-\d{2}-\d{2}', technique):
        return False
    if re.match(r'^commit\s+`?[0-9a-f]{6,40}', technique, re.IGNORECASE):
        return False
    return True


def parse_mementum_memories(root_dir):
    """Read mementum memories to extract successful patterns."""
    memories_dir = Path(root_dir) / "mementum" / "memories"
    patterns = {
        'success_patterns': Counter(),
        'failure_patterns': Counter(),
        'techniques': Counter(),
        'targets': Counter(),
    }
    
    if not memories_dir.exists():
        return patterns
    
    for mem_file in memories_dir.glob("*.md"):
        if mem_file.name.startswith('_') or mem_file.name == 'README.md':
            continue
            
        with open(mem_file, 'r') as f:
            content = f.read()
        
        # Extract explicit pattern tags without matching quoted commit subjects like "fix: ...".
        tag_re = r'^[ \t]*(?:[-*][ \t]*)?(?:\*\*)?(?:Pattern|Fix|Insight|Technique)(?::\*\*|\*\*:|:)[ \t]*(.+)$'
        for match in re.finditer(tag_re, content, re.IGNORECASE | re.MULTILINE):
            technique = match.group(1).strip().rstrip(':').strip()
            if valid_technique(technique):
                patterns['techniques'][technique] += 1
        
        # Check if memory indicates success or failure
        if re.search(r'(?:success|kept|merged|promoted|fixed)', content, re.IGNORECASE):
            # Extract target file references
            for match in re.finditer(r'`([^`]+\.el)`', content):
                patterns['targets'][match.group(1)] += 1
            
            # Look for pattern descriptions in bold or code
            for match in re.finditer(r'\*\*(.+?)\*\*', content):
                text = match.group(1).strip()
                # Filter out markdown headers and short phrases
                if (len(text) > 10 and len(text) < 100 and 
                    text not in ['Root Cause', 'Verification', 'Before fix', 'After fix', 'Impact', 'Fix'] and
                    not text.endswith(':')):
                    patterns['success_patterns'][text] += 1
        
        elif re.search(r'(?:failure|discarded|error|bug|issue)', content, re.IGNORECASE):
            for match in re.finditer(r'\*\*(.+?)\*\*', content):
                text = match.group(1).strip()
                if (len(text) > 10 and len(text) < 100 and
                    text not in ['Root Cause', 'Verification', 'Before fix', 'After fix'] and
                    not text.endswith(':')):
                    patterns['failure_patterns'][text] += 1
    
    return patterns


def analyze_git_history(root_dir, max_commits=200):
    """Analyze git history to find code patterns in kept experiments."""
    patterns = {
        'code_patterns': Counter(),
        'file_categories': Counter(),
        'change_types': Counter(),
    }
    
    try:
        # Get recent commits with stats
        result = subprocess.run(
            ['git', '-C', root_dir, 'log', f'-{max_commits}', '--format=%H|%s|%b---COMMIT_END---'],
            capture_output=True, text=True, timeout=30
        )
        
        if result.returncode != 0:
            return patterns
        
        commits = result.stdout.split('---COMMIT_END---')
        
        for commit_text in commits:
            if '|' not in commit_text:
                continue
                
            parts = commit_text.split('|', 2)
            if len(parts) < 2:
                continue
                
            commit_hash = parts[0].strip()
            subject = parts[1].strip()
            body = parts[2].strip() if len(parts) > 2 else ''
            
            # Categorize by commit message patterns
            if re.search(r'optimize/', subject):
                # Experiment commit - analyze the diff
                diff_result = subprocess.run(
                    ['git', '-C', root_dir, 'show', '--stat', commit_hash],
                    capture_output=True, text=True, timeout=10
                )
                
                if diff_result.returncode == 0:
                    diff_text = diff_result.stdout
                    
                    # Count file categories
                    for match in re.finditer(r'\blisp/modules/([^/]+)\.el\b', diff_text):
                        patterns['file_categories'][match.group(1)] += 1
                    
                    # Get actual diff content for pattern analysis
                    diff_content = subprocess.run(
                        ['git', '-C', root_dir, 'show', commit_hash],
                        capture_output=True, text=True, timeout=10
                    )
                    
                    if diff_content.returncode == 0:
                        content = diff_content.stdout
                        
                        # Extract code patterns from diff
                        pattern_rules = [
                            (r'\+.*\(defun\s+\S+', 'extract-helper-function'),
                            (r'\+.*when-let\*?', 'nil-guard-pattern'),
                            (r'\+.*unless\s+\(', 'unless-guard'),
                            (r'\+.*condition-case', 'error-handling'),
                            (r'\+.*plist-get\s+\S+\s+nil', 'safe-plist-get'),
                            (r'\+.*bound-and-true-p', 'bound-check'),
                            (r'\+.*require\s+\'', 'add-dependency'),
                            (r'\-.*\(if\s+\S+\s+\S+\s+nil\)', 'simplify-if'),
                            (r'\+.*memoize', 'add-caching'),
                            (r'\+.*defvar\s+\S+', 'add-variable'),
                            (r'\+.*defconst\s+\S+', 'add-constant'),
                        ]
                        
                        for regex, pattern_name in pattern_rules:
                            if re.search(regex, content):
                                patterns['change_types'][pattern_name] += 1
            
            # Also check for non-experiment commits (fixes)
            elif re.search(r'fix:', subject, re.IGNORECASE):
                patterns['change_types']['manual-fix'] += 1
                
                # What was fixed?
                if 'nil' in subject.lower() or 'guard' in subject.lower():
                    patterns['change_types']['nil-guard-pattern'] += 1
                elif 'error' in subject.lower() or 'exception' in subject.lower():
                    patterns['change_types']['error-handling'] += 1
                elif 'cache' in subject.lower():
                    patterns['change_types']['add-caching'] += 1
    
    except (subprocess.TimeoutExpired, subprocess.CalledProcessError) as e:
        print(f"Git analysis warning: {e}", file=os.sys.stderr)
    
    return patterns


def analyze_experiment_results(root_dir):
    """Analyze results.tsv files for correlation patterns.
    
    Scans all experiment directories under var/tmp/experiments/ for results.tsv files.
    """
    experiments_dir = Path(root_dir) / "var" / "tmp" / "experiments"
    
    patterns = {
        'target_success': defaultdict(lambda: {'total': 0, 'kept': 0}),
        'error_patterns': Counter(),
        'score_distribution': [],
    }
    
    if not experiments_dir.exists():
        return patterns
    
    # Scan all experiment directories for results.tsv
    results_files = list(experiments_dir.glob("*/results.tsv"))
    
    if not results_files:
        # Fallback: try legacy location
        legacy_file = experiments_dir / "results.tsv"
        if legacy_file.exists():
            results_files = [legacy_file]
    
    print(f"    Found {len(results_files)} results.tsv files")
    
    for results_file in results_files:
        try:
            with open(results_file, 'r') as f:
                # Skip header
                header = f.readline()
                
                for line in f:
                    parts = line.strip().split('\t')
                    if len(parts) < 10:
                        continue
                    
                    target = parts[1] if len(parts) > 1 else ''
                    status = parts[7] if len(parts) > 7 else ''  # 'decision' column
                    score_str = parts[5] if len(parts) > 5 else '0'  # 'score_after' column
                    error = parts[11] if len(parts) > 11 else ''  # 'grader_reason' column
                    
                    patterns['target_success'][target]['total'] += 1
                    
                    if status == 'kept':
                        patterns['target_success'][target]['kept'] += 1
                        try:
                            patterns['score_distribution'].append(float(score_str))
                        except ValueError:
                            pass
                    
                    # Extract error patterns
                    if error and error != 'nil':
                        # Categorize errors
                        if 'timeout' in error.lower():
                            patterns['error_patterns']['timeout'] += 1
                        elif 'rate' in error.lower() or 'quota' in error.lower():
                            patterns['error_patterns']['api-limit'] += 1
                        elif 'syntax' in error.lower() or 'paren' in error.lower():
                            patterns['error_patterns']['syntax-error'] += 1
                        elif 'test' in error.lower():
                            patterns['error_patterns']['test-failure'] += 1
                        elif 'validation' in error.lower():
                            patterns['error_patterns']['validation-failed'] += 1
                        else:
                            patterns['error_patterns']['other'] += 1
        except Exception as e:
            print(f"    Warning: Could not read {results_file}: {e}", file=os.sys.stderr)
    
    return patterns


def synthesize_learned_patterns(mementum_patterns, git_patterns, experiment_patterns):
    """Synthesize all pattern sources into directive recommendations."""
    
    learned = {
        'high_value_patterns': [],
        'avoid_patterns': [],
        'priority_targets': [],
        'effective_techniques': [],
        'error_mitigation': [],
    }
    
    # 1. High-value patterns (from git + mementum)
    all_success = Counter()
    all_success.update(mementum_patterns['success_patterns'])
    all_success.update(git_patterns['change_types'])
    
    for pattern, count in all_success.most_common(10):
        if count >= 2:  # At least 2 occurrences
            learned['high_value_patterns'].append({
                'pattern': pattern,
                'evidence': count,
                'source': 'git' if pattern in git_patterns['change_types'] else 'mementum'
            })
    
    # 2. Avoid patterns (from failures)
    for pattern, count in mementum_patterns['failure_patterns'].most_common(5):
        if count >= 2:
            learned['avoid_patterns'].append({
                'pattern': pattern,
                'evidence': count,
            })
    
    # 3. Priority targets (from experiment results)
    target_stats = []
    for target, stats in experiment_patterns['target_success'].items():
        if stats['total'] >= 3:  # Need sufficient data
            rate = stats['kept'] / stats['total']
            target_stats.append((target, rate, stats['total'], stats['kept']))
    
    target_stats.sort(key=lambda x: x[1], reverse=True)
    
    for target, rate, total, kept in target_stats[:10]:
        learned['priority_targets'].append({
            'target': target,
            'keep_rate': rate,
            'total': total,
            'kept': kept,
            'recommendation': 'prioritize' if rate > 0.2 else 'avoid' if rate < 0.05 else 'monitor'
        })
    
    # 4. Effective techniques (from mementum insights)
    for technique, count in mementum_patterns['techniques'].most_common(8):
        learned['effective_techniques'].append({
            'technique': technique,
            'frequency': count,
        })
    
    # 5. Error mitigation strategies
    for error_type, count in experiment_patterns['error_patterns'].most_common(5):
        mitigation = {
            'timeout': 'Add smaller batch sizes or chunked processing',
            'api-limit': 'Implement provider fallback or rate limit handling',
            'syntax-error': 'Add pre-flight syntax validation',
            'test-failure': 'Run tests before committing experiments',
            'validation-failed': 'Improve pre-grade validation prompts',
        }.get(error_type, 'Investigate root cause')
        
        learned['error_mitigation'].append({
            'error': error_type,
            'frequency': count,
            'mitigation': mitigation,
        })
    
    return learned


def main():
    parser = argparse.ArgumentParser(description='Analyze patterns for directive evolution')
    parser.add_argument('--root', default='.', help='Project root directory')
    parser.add_argument('--output', '-o', required=True, help='Output JSON path')
    args = parser.parse_args()
    
    root_dir = os.path.expanduser(args.root)
    
    print("[1/4] Parsing mementum memories...")
    mementum_patterns = parse_mementum_memories(root_dir)
    print(f"  Found {len(mementum_patterns['success_patterns'])} success patterns")
    print(f"  Found {len(mementum_patterns['failure_patterns'])} failure patterns")
    
    print("[2/4] Analyzing git history...")
    git_patterns = analyze_git_history(root_dir)
    print(f"  Found {len(git_patterns['change_types'])} change types")
    print(f"  Found {len(git_patterns['file_categories'])} file categories")
    
    print("[3/4] Analyzing experiment results...")
    experiment_patterns = analyze_experiment_results(root_dir)
    print(f"  Analyzed {len(experiment_patterns['target_success'])} targets")
    print(f"  Found {len(experiment_patterns['error_patterns'])} error patterns")
    
    print("[4/4] Synthesizing learned patterns...")
    learned = synthesize_learned_patterns(mementum_patterns, git_patterns, experiment_patterns)
    
    # Build output
    output = {
        'generated_at': datetime.now().isoformat(),
        'sources': {
            'mementum_memories': len(mementum_patterns['success_patterns']),
            'git_commits_analyzed': sum(git_patterns['change_types'].values()),
            'experiment_targets': len(experiment_patterns['target_success']),
        },
        'learned_patterns': learned,
        'raw': {
            'mementum': dict(mementum_patterns),
            'git': dict(git_patterns),
            'experiments': dict(experiment_patterns),
        }
    }
    
    # Write output
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, 'w') as f:
        json.dump(output, f, indent=2, default=lambda x: dict(x) if hasattr(x, 'items') else str(x))
    
    print(f"\n✓ Pattern analysis complete: {output_path}")
    print(f"  High-value patterns: {len(learned['high_value_patterns'])}")
    print(f"  Priority targets: {len(learned['priority_targets'])}")
    print(f"  Error mitigations: {len(learned['error_mitigation'])}")


if __name__ == '__main__':
    main()
