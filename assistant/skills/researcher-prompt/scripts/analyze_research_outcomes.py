#!/usr/bin/env python3
"""Analyze research outcomes from experiment history.

Correlates research topics with experiment success to produce
meta-learning data for the researcher skill.

Usage:
    python analyze_research_outcomes.py --experiments-dir var/tmp/experiments \
        --output-dir assistant/skills/researcher-prompt/data
"""

import argparse
import csv
import json
import re
import subprocess
from collections import defaultdict, Counter
from datetime import datetime, timedelta
from pathlib import Path


# Keywords that indicate research-inspired hypotheses
RESEARCH_KEYWORDS = {
    'validation-guard': ['guard', 'validate', 'check', 'ensure', 'prevent', 'boundp', 'null'],
    'nil-safety': ['nil guard', 'nil check', 'null guard', 'null check', 'nil safety'],
    'type-validation': ['proper-list-p', 'listp', 'consp', 'functionp', 'stringp', 'integerp'],
    'error-handling': ['error', 'exception', 'catch', 'condition-case', 'signal'],
    'helper-extraction': ['extract helper', 'extract function', 'helper function', 'refactor into'],
    'performance': ['optimize', 'performance', 'cache', 'memoize', 'speed', 'efficient', 'O(n)'],
    'clarity': ['clarity', 'explicit', 'self-documenting', 'readable', 'clear'],
    'cleanup': ['cleanup', 'remove', 'delete', 'orphaned', 'stale', 'leak'],
    'async': ['async', 'callback', 'promise', 'deferred', 'timer', 'process'],
    'buffer': ['buffer', 'overlay', 'window', 'frame'],
}

# Source patterns in mementum memories
SOURCE_PATTERNS = {
    'github': r'github\.com/([^/\s]+/[^/\s]+)',
    'youtube': r'youtube\.com|youtu\.be',
    'arxiv': r'arxiv\.org',
    'reddit': r'reddit\.com/r/(\w+)',
    'twitter': r'twitter\.com|x\.com',
    'huggingface': r'huggingface\.co',
}


def parse_results_tsv(tsv_path):
    """Parse a single results.tsv file into experiment records."""
    experiments = []
    try:
        with open(tsv_path, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f, delimiter='\t')
            for row in reader:
                # Skip non-experiment rows
                if not row.get('experiment_id') or row.get('experiment_id') == 'experiment_id':
                    continue
                try:
                    exp = {
                        'id': row.get('experiment_id', '').strip(),
                        'target': row.get('target', '').strip(),
                        'hypothesis': row.get('hypothesis', '').strip(),
                        'score_before': float(row.get('score_before', 0) or 0),
                        'score_after': float(row.get('score_after', 0) or 0),
                        'code_quality': float(row.get('code_quality', 0) or 0),
                        'delta': row.get('delta', '0').strip(),
                        'decision': row.get('decision', '').strip().lower(),
                        'duration': int(row.get('duration', 0) or 0),
                        'grader_quality': int(row.get('grader_quality', 0) or 0),
                        'grader_reason': row.get('grader_reason', '').strip(),
                        'comparator_reason': row.get('comparator_reason', '').strip(),
                        'analyzer_patterns': row.get('analyzer_patterns', '').strip(),
                    }
                    if exp['id'] and exp['target']:
                        experiments.append(exp)
                except (ValueError, TypeError):
                    continue
    except Exception as e:
        print(f"Warning: Could not parse {tsv_path}: {e}")
    return experiments


def extract_topics_from_hypothesis(hypothesis):
    """Extract research topics from a hypothesis string."""
    hyp_lower = hypothesis.lower()
    topics = []
    
    for topic, keywords in RESEARCH_KEYWORDS.items():
        if any(kw in hyp_lower for kw in keywords):
            topics.append(topic)
    
    # Also extract action+target patterns
    actions = re.findall(r'\b(add|fix|remove|prevent|handle|check|validate|ensure|improve|optimize|refactor|extract|move|rename|update|implement|create)\s+([a-z_\-]+)', hyp_lower)
    for verb, noun in actions:
        technique = f"{verb.lower()}-{noun.lower()}"
        topics.append(technique)
    
    return [t for t in list(set(topics)) if _valid_topic_name(t)]


def _valid_topic_name(name):
    """Reject topic names that are log messages or contain brackets/special chars."""
    if not name or not isinstance(name, str):
        return False
    if '[' in name or ']' in name or "'" in name or '"' in name:
        return False
    if name in ('rejected', 'accepted'):
        return False
    if not re.match(r'^[a-z][a-z0-9-]+$', name):
        return False
    return True


def analyze_topic_performance(experiments, lookback_days=30):
    """Analyze which topics correlate with experiment success."""
    cutoff = datetime.now() - timedelta(days=lookback_days)
    
    # Group experiments by topic
    topic_stats = defaultdict(lambda: {
        'total': 0, 'kept': 0, 'discarded': 0,
        'quality_deltas': [], 'score_improvements': [],
        'targets': Counter(), 'sources': Counter(),
        'first_seen': None, 'last_seen': None,
        'experiments': []
    })
    
    for exp in experiments:
        exp_date = None
        try:
            date_str = exp['id'].split('T')[0] if 'T' in exp['id'] else None
            if date_str:
                exp_date = datetime.strptime(date_str, '%Y-%m-%d')
        except (ValueError, KeyError, TypeError):
            pass
        
        if exp_date and exp_date < cutoff:
            continue
        
        topics = extract_topics_from_hypothesis(exp['hypothesis'])
        
        for topic in topics:
            stats = topic_stats[topic]
            stats['total'] += 1
            
            if exp['decision'] == 'kept':
                stats['kept'] += 1
            else:
                stats['discarded'] += 1
            
            stats['quality_deltas'].append(exp['code_quality'])
            stats['score_improvements'].append(exp['score_after'] - exp['score_before'])
            stats['targets'][exp['target']] += 1
            
            if exp_date:
                if stats['first_seen'] is None or exp_date < stats['first_seen']:
                    stats['first_seen'] = exp_date
                if stats['last_seen'] is None or exp_date > stats['last_seen']:
                    stats['last_seen'] = exp_date
            
            stats['experiments'].append({'id': exp['id'], 'decision': exp['decision']})
    
    # Calculate derived metrics
    result = {}
    for topic, stats in topic_stats.items():
        if stats['total'] < 2:  # Need at least 2 experiments for significance
            continue
        
        success_rate = stats['kept'] / stats['total']
        avg_quality = sum(stats['quality_deltas']) / len(stats['quality_deltas']) if stats['quality_deltas'] else 0
        avg_score_imp = sum(stats['score_improvements']) / len(stats['score_improvements']) if stats['score_improvements'] else 0
        
        # Detect trend
        trend = 'stable'
        if stats['first_seen'] and stats['last_seen']:
            days_span = (stats['last_seen'] - stats['first_seen']).days
            if days_span > 7:
                # Simple trend: compare first half vs second half
                mid = stats['total'] // 2
                first_half_kept = sum(1 for e in stats['experiments'][:mid]
                                     if e['decision'] == 'kept') if mid > 0 else 0
                second_half_kept = sum(1 for e in stats['experiments'][mid:]
                                      if e['decision'] == 'kept') if (stats['total'] - mid) > 0 else 0
                first_rate = first_half_kept / mid if mid > 0 else 0
                second_rate = second_half_kept / (stats['total'] - mid) if (stats['total'] - mid) > 0 else 0
                
                if second_rate > first_rate * 1.2:
                    trend = 'improving'
                elif second_rate < first_rate * 0.8:
                    trend = 'declining'
        
        result[topic] = {
            'total_experiments': stats['total'],
            'kept': stats['kept'],
            'discarded': stats['discarded'],
            'success_rate': round(success_rate, 3),
            'avg_quality_score': round(avg_quality, 3),
            'avg_score_improvement': round(avg_score_imp, 3),
            'trend': trend,
            'top_targets': [t[0] for t in stats['targets'].most_common(3)],
            'first_seen': stats['first_seen'].isoformat() if stats['first_seen'] else None,
            'last_seen': stats['last_seen'].isoformat() if stats['last_seen'] else None,
        }
    
    return result


def analyze_source_effectiveness(memories_dir, experiments):
    """Analyze which external sources produce actionable insights."""
    sources = defaultdict(lambda: {
        'mentions': 0, 'experiments_enabled': 0, 'experiments_kept': 0,
        'techniques': Counter(), 'last_seen': None
    })
    
    # Scan mementum memories for research references
    memories_path = Path(memories_dir)
    if not memories_path.exists():
        return {}
    
    for mem_file in memories_path.glob('*.md'):
        try:
            content = mem_file.read_text()
            mem_date = None
            
            # Try to extract date from filename or content
            date_match = re.search(r'(\d{4}-\d{2}-\d{2})', mem_file.name)
            if date_match:
                mem_date = datetime.strptime(date_match.group(1), '%Y-%m-%d')
            
            for source_type, pattern in SOURCE_PATTERNS.items():
                matches = re.finditer(pattern, content, re.IGNORECASE)
                for match in matches:
                    source_id = f"{source_type}:{match.group(1) if match.groups() else source_type}"
                    sources[source_id]['mentions'] += 1
                    
                    # Extract techniques mentioned near the source
                    context_start = max(0, match.start() - 200)
                    context_end = min(len(content), match.end() + 200)
                    context = content[context_start:context_end].lower()
                    
                    for topic, keywords in RESEARCH_KEYWORDS.items():
                        if any(kw in context for kw in keywords):
                            sources[source_id]['techniques'][topic] += 1
                    
                    if mem_date:
                        if sources[source_id]['last_seen'] is None or mem_date > sources[source_id]['last_seen']:
                            sources[source_id]['last_seen'] = mem_date
        except Exception as e:
            print(f"Warning: Could not parse {mem_file}: {e}")
    
    # Try to correlate sources with experiments
    # This is heuristic: if experiment hypothesis contains techniques from a source
    for exp in experiments:
        exp_topics = extract_topics_from_hypothesis(exp['hypothesis'])
        for source_id, stats in sources.items():
            if any(topic in stats['techniques'] for topic in exp_topics):
                stats['experiments_enabled'] += 1
                if exp['decision'] == 'kept':
                    stats['experiments_kept'] += 1
    
    # Format results
    result = {}
    for source_id, stats in sources.items():
        if stats['mentions'] < 1:
            continue
        
        success_rate = stats['experiments_kept'] / stats['experiments_enabled'] if stats['experiments_enabled'] > 0 else 0
        
        result[source_id] = {
            'source_type': source_id.split(':')[0],
            'identifier': source_id.split(':', 1)[1] if ':' in source_id else source_id,
            'mentions': stats['mentions'],
            'techniques_suggested': list(stats['techniques'].keys())[:5],
            'experiments_enabled': stats['experiments_enabled'],
            'experiments_kept': stats['experiments_kept'],
            'success_rate': round(success_rate, 3),
            'last_seen': stats['last_seen'].isoformat() if stats['last_seen'] else None,
        }
    
    return result


def detect_temporal_patterns(topic_performance):
    """Classify topics by their temporal status."""
    emerging = []
    mature = []
    declining = []
    unexplored = []
    
    for topic, stats in topic_performance.items():
        success_rate = stats['success_rate']
        trend = stats['trend']
        total = stats['total_experiments']
        
        if total < 5:
            if success_rate > 0.3:
                emerging.append(topic)
            else:
                unexplored.append(topic)
        elif trend == 'improving':
            emerging.append(topic)
        elif trend == 'declining':
            declining.append(topic)
        else:
            mature.append(topic)
    
    return {
        'emerging': sorted(emerging, key=lambda t: topic_performance[t]['success_rate'], reverse=True)[:5],
        'mature': sorted(mature, key=lambda t: topic_performance[t]['success_rate'], reverse=True)[:5],
        'declining': sorted(declining, key=lambda t: topic_performance[t]['success_rate'])[:5],
        'unexplored': sorted(unexplored, key=lambda t: topic_performance[t]['success_rate'], reverse=True)[:5],
    }


def load_all_experiments(experiments_dir):
    """Load all experiments from results.tsv files."""
    all_experiments = []
    experiments_path = Path(experiments_dir)
    
    if not experiments_path.exists():
        print(f"Experiments directory not found: {experiments_dir}")
        return all_experiments
    
    for tsv_file in experiments_path.rglob('results.tsv'):
        experiments = parse_results_tsv(tsv_file)
        all_experiments.extend(experiments)
        print(f"Loaded {len(experiments)} experiments from {tsv_file}")
    
    print(f"Total experiments loaded: {len(all_experiments)}")
    return all_experiments


def main():
    parser = argparse.ArgumentParser(description='Analyze research outcomes from experiments')
    parser.add_argument('--experiments-dir', default='var/tmp/experiments',
                        help='Directory containing experiment results.tsv files')
    parser.add_argument('--memories-dir', default='mementum/memories',
                        help='Directory containing mementum memories')
    parser.add_argument('--output-dir', default='assistant/skills/researcher-prompt/data',
                        help='Output directory for analysis JSON files')
    parser.add_argument('--lookback-days', type=int, default=30,
                        help='Days to look back for analysis')
    args = parser.parse_args()
    
    # Load data
    experiments = load_all_experiments(args.experiments_dir)
    
    if not experiments:
        print("No experiments found. Exiting.")
        return
    
    # Analyze
    print("\nAnalyzing topic performance...")
    topic_performance = analyze_topic_performance(experiments, args.lookback_days)
    print(f"Found {len(topic_performance)} topics with ≥2 experiments")
    
    print("\nAnalyzing source effectiveness...")
    source_effectiveness = analyze_source_effectiveness(args.memories_dir, experiments)
    print(f"Found {len(source_effectiveness)} sources")
    
    print("\nDetecting temporal patterns...")
    temporal_patterns = detect_temporal_patterns(topic_performance)
    print(f"Emerging: {len(temporal_patterns['emerging'])}, Mature: {len(temporal_patterns['mature'])}, "
          f"Declining: {len(temporal_patterns['declining'])}, Unexplored: {len(temporal_patterns['unexplored'])}")
    
    # Ensure output directory exists
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    
    # Write results
    now = datetime.now().isoformat()
    
    topic_file = output_dir / 'topic-performance.json'
    with open(topic_file, 'w') as f:
        json.dump({
            'version': now,
            'lookback_days': args.lookback_days,
            'total_experiments': len(experiments),
            'topics': topic_performance
        }, f, indent=2)
    print(f"\nWrote {topic_file}")
    
    source_file = output_dir / 'source-effectiveness.json'
    with open(source_file, 'w') as f:
        json.dump({
            'version': now,
            'sources': source_effectiveness
        }, f, indent=2)
    print(f"Wrote {source_file}")
    
    temporal_file = output_dir / 'temporal-patterns.json'
    with open(temporal_file, 'w') as f:
        json.dump({
            'version': now,
            'patterns': temporal_patterns
        }, f, indent=2)
    print(f"Wrote {temporal_file}")
    
    # Print summary
    print("\n" + "="*60)
    print("TOP 5 TOPICS BY SUCCESS RATE:")
    sorted_topics = sorted(topic_performance.items(), key=lambda x: x[1]['success_rate'], reverse=True)
    for topic, stats in sorted_topics[:5]:
        print(f"  {topic:30s} {stats['success_rate']:.1%} ({stats['kept']}/{stats['total_experiments']}) "
              f"trend: {stats['trend']}")
    
    print("\nTOP 5 SOURCES BY SUCCESS RATE:")
    sorted_sources = sorted(source_effectiveness.items(), key=lambda x: x[1]['success_rate'], reverse=True)
    for source, stats in sorted_sources[:5]:
        print(f"  {source:40s} {stats['success_rate']:.1%} ({stats['experiments_kept']}/{stats['experiments_enabled']})")
    
    print("\n" + "="*60)


if __name__ == '__main__':
    main()
