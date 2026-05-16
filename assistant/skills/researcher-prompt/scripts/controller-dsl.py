#!/usr/bin/env python3
"""Research Strategy Controller DSL — AutoTTS-style strategy as code

Strategies are executable definitions, not text descriptions.
Each strategy defines phases with conditions, limits, and stop criteria.
"""
import json
from pathlib import Path
from typing import List, Dict, Optional

ROOT = Path(__file__).resolve().parents[4]
STRATEGY_DIR = ROOT / "assistant/skills/researcher-prompt/strategies"

def ensure_strategy_dir():
    STRATEGY_DIR.mkdir(parents=True, exist_ok=True)

# ─── Strategy Definitions ───

STRATEGIES = {
    'own-repos-first': {
        'name': 'own-repos-first',
        'description': 'Check own repos first, only search externally if needed',
        'phases': [
            {'name': 'search-own', 'tool': 'WebSearch', 'max_calls': 2,
             'query_template': 'site:github.com/davidwuchn {topic}',
             'stop_if': 'found_insights >= 2'},
            {'name': 'search-forks', 'tool': 'WebSearch', 'max_calls': 2,
             'query_template': 'github.com {topic} emacs fork',
             'condition': 'not own_repo_found',
             'stop_if': 'found_insights >= 2'},
            {'name': 'search-external', 'tool': 'WebSearch', 'max_calls': 2,
             'query_template': '{topic} emacs lisp agent pattern',
             'condition': 'not fork_found',
             'stop_if': 'found_insights >= 3'},
            {'name': 'fetch-deep', 'tool': 'WebFetch', 'max_calls': 3,
             'condition': 'has_urls'},
            {'name': 'synthesize', 'tool': 'synthesize', 'min_output_chars': 500},
        ],
        'cost_limit': 8000,
        'expected_tokens': 6000,
    },
    
    'deep-external': {
        'name': 'deep-external',
        'description': 'Deep external research when own repos exhausted',
        'phases': [
            {'name': 'search-blogs', 'tool': 'WebSearch', 'max_calls': 3,
             'query_template': '{topic} emacs lisp best practice 2026'},
            {'name': 'search-github', 'tool': 'WebSearch', 'max_calls': 3,
             'query_template': 'github.com {topic} emacs elisp'},
            {'name': 'fetch-deep', 'tool': 'WebFetch', 'max_calls': 3},
            {'name': 'synthesize', 'tool': 'synthesize', 'min_output_chars': 1000},
        ],
        'cost_limit': 12000,
        'expected_tokens': 10000,
    },
    
    'quick-own-only': {
        'name': 'quick-own-only',
        'description': 'Fast check of own repos only, minimal tokens',
        'phases': [
            {'name': 'search-own', 'tool': 'WebSearch', 'max_calls': 1,
             'query_template': 'site:github.com/davidwuchn {topic}'},
            {'name': 'synthesize', 'tool': 'synthesize', 'min_output_chars': 200},
        ],
        'cost_limit': 2000,
        'expected_tokens': 1500,
    },
    
    'topic-specific': {
        'name': 'topic-specific',
        'description': 'Tailored search based on topic type',
        'phases': [
            {'name': 'classify-topic', 'tool': 'classify'},
            {'name': 'search-topic', 'tool': 'WebSearch', 'max_calls': 3,
             'query_template': '{topic_specific_query}'},
            {'name': 'fetch-deep', 'tool': 'WebFetch', 'max_calls': 2},
            {'name': 'synthesize', 'tool': 'synthesize', 'min_output_chars': 500},
        ],
        'cost_limit': 8000,
        'expected_tokens': 6000,
    },
}

def save_strategy(name: str, strategy: Dict):
    """Save a strategy definition."""
    ensure_strategy_dir()
    strategy_file = STRATEGY_DIR / f"{name}.json"
    with open(strategy_file, 'w') as f:
        json.dump(strategy, f, indent=2)
    print(f"[strategy] Saved: {strategy_file}")

def load_strategy(name: str) -> Optional[Dict]:
    """Load a strategy definition."""
    strategy_file = STRATEGY_DIR / f"{name}.json"
    if not strategy_file.exists():
        return None
    with open(strategy_file) as f:
        return json.load(f)

def list_strategies() -> List[str]:
    """List all available strategies."""
    ensure_strategy_dir()
    return [f.stem for f in STRATEGY_DIR.glob("*.json")]

def get_strategy_for_topic(topic: str, historical_performance: Dict = None) -> Dict:
    """Select best strategy for a topic based on historical performance.
    
    This is the AutoTTS CMC equivalent — pick strategy based on confidence.
    """
    if historical_performance is None:
        historical_performance = {}
    
    # Check if we have performance data for this topic
    topic_perf = historical_performance.get(topic, {})
    best_strategy = topic_perf.get('best_strategy', 'own-repos-first')
    
    # If no data, use default
    if not topic_perf:
        return STRATEGIES['own-repos-first']
    
    # If keep rate is high, use quick strategy (high confidence)
    if topic_perf.get('keep_rate', 0) > 0.3:
        return STRATEGIES.get('quick-own-only', STRATEGIES['own-repos-first'])
    
    # If keep rate is low, use deep strategy (low confidence, explore more)
    if topic_perf.get('keep_rate', 0) < 0.1:
        return STRATEGIES.get('deep-external', STRATEGIES['own-repos-first'])
    
    # Default
    return STRATEGIES.get(best_strategy, STRATEGIES['own-repos-first'])

def format_strategy_as_prompt(strategy: Dict) -> str:
    """Format a strategy as instructions for the researcher subagent."""
    lines = [
        f"## Research Strategy: {strategy['name']}",
        f"{strategy['description']}",
        "",
        "### Phases (execute in order):",
    ]
    
    for i, phase in enumerate(strategy['phases'], 1):
        condition = f" [if: {phase['condition']}]" if 'condition' in phase else ""
        stop_if = f" [stop if: {phase['stop_if']}]" if 'stop_if' in phase else ""
        lines.append(f"{i}. **{phase['name']}**: Use {phase['tool']}{condition}{stop_if}")
        if 'query_template' in phase:
            lines.append(f"   Query: `{phase['query_template']}`")
        if 'max_calls' in phase:
            lines.append(f"   Max calls: {phase['max_calls']}")
    
    lines.extend([
        "",
        f"### Constraints:",
        f"- Cost limit: {strategy['cost_limit']} tokens",
        f"- Expected tokens: {strategy['expected_tokens']}",
        "",
        "Follow these phases EXACTLY. Do not skip phases unless their condition is false.",
    ])
    
    return "\n".join(lines)

def main():
    """Save all default strategies."""
    for name, strategy in STRATEGIES.items():
        save_strategy(name, strategy)
    
    print(f"\nSaved {len(STRATEGIES)} strategies:")
    for name in STRATEGIES:
        print(f"  - {name}")

if __name__ == '__main__':
    main()
