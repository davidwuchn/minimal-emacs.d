#!/usr/bin/env python3
"""Evolve researcher-prompt skill based on experiment outcomes.

Reads analysis JSON files and updates the SKILL.md template with
dynamic topic priorities, source rankings, and anti-patterns.

Usage:
    python evolve_researcher.py \
        --data-dir assistant/skills/researcher-prompt/data \
        --skill assistant/skills/researcher-prompt/SKILL.md
"""

import argparse
import json
import re
from pathlib import Path
from datetime import datetime


def load_json_safe(path):
    """Load JSON file, return empty dict on error."""
    try:
        with open(path, 'r') as f:
            return json.load(f)
    except Exception as e:
        print(f"Warning: Could not load {path}: {e}")
        return {}


def format_topic_performance(topic_data, max_topics=10):
    """Format topic performance data as markdown table."""
    if not topic_data:
        return "*No topic data available yet.*"
    
    topics = topic_data.get('topics', {})
    if not topics:
        return "*No topics with sufficient data (minimum 2 experiments).*\n\nRun more experiments to populate topic analysis."
    
    # Sort by composite score: success_rate * avg_quality_score
    scored_topics = []
    for topic, stats in topics.items():
        composite = stats['success_rate'] * stats.get('avg_quality_score', 0.5)
        scored_topics.append((topic, stats, composite))
    
    scored_topics.sort(key=lambda x: x[2], reverse=True)
    
    lines = [
        "| Rank | Topic | Success Rate | Experiments | Trend | Top Targets |",
        "|------|-------|--------------|-------------|-------|-------------|",
    ]
    
    for rank, (topic, stats, _) in enumerate(scored_topics[:max_topics], 1):
        success_pct = f"{stats['success_rate']:.1%}"
        count = f"{stats['kept']}/{stats['total_experiments']}"
        trend_emoji = {'improving': '📈', 'declining': '📉', 'stable': '➡️'}.get(stats['trend'], '➡️')
        targets = ', '.join(stats.get('top_targets', [])[:2])
        lines.append(f"| {rank} | {topic} | {success_pct} | {count} | {trend_emoji} {stats['trend']} | {targets} |")
    
    return '\n'.join(lines)


def format_priority_topics(topic_data, temporal_data, max_topics=6):
    """Generate the Mission section with prioritized topics."""
    if not topic_data or not temporal_data:
        return """Search external sources for actionable techniques related to:
- AI agent architectures and workflows
- Emacs Lisp AI integration patterns
- LLM self-evolution and meta-learning
- Prompt engineering for code generation
- Error recovery and retry patterns in agent systems
- Benchmarking and evaluation frameworks"""
    
    topics = topic_data.get('topics', {})
    patterns = temporal_data.get('patterns', {})
    
    # Select topics: top mature + emerging + one unexplored
    selected = []
    
    # Add top mature topics (proven success)
    mature = patterns.get('mature', [])
    for topic in mature[:2]:
        if topic in topics and topic not in selected:
            selected.append(topic)
    
    # Add emerging topics (improving success)
    emerging = patterns.get('emerging', [])
    for topic in emerging[:2]:
        if topic in topics and topic not in selected:
            selected.append(topic)
    
    # Add unexplored topics (high potential)
    unexplored = patterns.get('unexplored', [])
    for topic in unexplored[:1]:
        if topic in topics and topic not in selected:
            selected.append(topic)
    
    # Fill remaining slots with top overall
    all_sorted = sorted(topics.items(), key=lambda x: x[1]['success_rate'], reverse=True)
    for topic, _ in all_sorted:
        if topic not in selected:
            selected.append(topic)
        if len(selected) >= max_topics:
            break
    
    lines = ["Search external sources for actionable techniques related to:"]
    
    for topic in selected[:max_topics]:
        if topic in topics:
            stats = topics[topic]
            description = {
                'validation-guard': 'Defensive validation and guard patterns',
                'nil-safety': 'Nil safety and null pointer prevention',
                'type-validation': 'Type validation and predicate patterns',
                'error-handling': 'Error handling and recovery patterns',
                'helper-extraction': 'Helper function extraction and DRY',
                'performance': 'Performance optimization and caching',
                'clarity': 'Code clarity and self-documenting patterns',
                'cleanup': 'Resource cleanup and memory management',
                'async': 'Async programming and callback patterns',
                'buffer': 'Buffer and overlay management',
            }.get(topic, topic.replace('-', ' ').title())
            
            lines.append(f"- **{description}** (success: {stats['success_rate']:.0%}) — {topic}")
    
    return '\n'.join(lines)


def format_project_priorities(source_data):
    """Format project monitoring priorities based on source effectiveness."""
    if not source_data or not source_data.get('sources'):
        return "_No source effectiveness data yet. See repo list below._"
    
    sources = source_data.get('sources', {})
    
    # Group by source type
    github_sources = []
    other_sources = []
    
    for source_id, stats in sources.items():
        if stats.get('source_type') == 'github':
            github_sources.append((source_id, stats))
        else:
            other_sources.append((source_id, stats))
    
    # Sort by success rate
    github_sources.sort(key=lambda x: x[1]['success_rate'], reverse=True)
    other_sources.sort(key=lambda x: x[1]['success_rate'], reverse=True)
    
    lines = ["### External Projects (Ranked by Downstream Success)\n"]
    
    for source_id, stats in github_sources[:10]:
        repo = stats.get('identifier', source_id)
        success = stats['success_rate']
        techniques = ', '.join(stats.get('techniques_suggested', [])[:3])
        lines.append(f"- **{repo}** — Success: {success:.0%} ({stats['experiments_kept']}/{stats['experiments_enabled']}) "
                    f"Techniques: {techniques or 'various'}")
    
    if other_sources:
        lines.append("\n### Other Sources\n")
        for source_id, stats in other_sources[:5]:
            source_type = stats.get('source_type', 'unknown')
            lines.append(f"- **{source_type}** — Success: {stats['success_rate']:.0%}")
    
    return '\n'.join(lines)


def format_anti_patterns(topic_data):
    """Extract anti-patterns from low-success topics."""
    if not topic_data:
        return """- Generic advice ('use AI', 'improve code')
- Ideas already in our codebase (check git log first)
- Purely theoretical without implementation path
- Tools requiring heavy external dependencies"""
    
    topics = topic_data.get('topics', {})
    
    # Find topics with low success rate but high attempt count
    anti_patterns = []
    for topic, stats in topics.items():
        if stats['total_experiments'] >= 5 and stats['success_rate'] < 0.1:
            anti_patterns.append((topic, stats))
    
    if not anti_patterns:
        return """- Generic advice ('use AI', 'improve code')
- Ideas already in our codebase (check git log first)
- Purely theoretical without implementation path
- Tools requiring heavy external dependencies
- Topics with <10% historical success (see data)"""
    
    lines = ["- Generic advice ('use AI', 'improve code')", "- Ideas already in our codebase"]
    
    for topic, stats in sorted(anti_patterns, key=lambda x: x[1]['success_rate']):
        description = topic.replace('-', ' ').title()
        lines.append(f"- **{description}** — Only {stats['success_rate']:.0%} success ({stats['kept']}/{stats['total_experiments']} experiments kept)")
    
    lines.append("- Tools requiring heavy external dependencies")
    return '\n'.join(lines)


def generate_evolved_skill(skill_path, data_dir):
    """Generate updated SKILL.md with dynamic content."""
    
    # Load analysis data
    topic_data = load_json_safe(data_dir / 'topic-performance.json')
    source_data = load_json_safe(data_dir / 'source-effectiveness.json')
    temporal_data = load_json_safe(data_dir / 'temporal-patterns.json')
    
    # Preserve frontmatter fields from existing SKILL.md
    existing_level = "molecule"
    existing_atoms = "atoms: [agent-prompts]"
    existing_molecules = ""
    if skill_path.exists():
        try:
            existing = skill_path.read_text(encoding="utf-8")
            for line in existing.split("\n"):
                if line.startswith("level:"):
                    existing_level = line.split(":", 1)[1].strip()
                elif line.startswith("atoms:"):
                    existing_atoms = line.strip()
                elif line.startswith("molecules:"):
                    existing_molecules = line.strip()
        except Exception:
            pass
    
    # Build extra frontmatter lines
    extra_frontmatter = []
    if existing_level:
        extra_frontmatter.append(f"level: {existing_level}")
    if existing_atoms:
        extra_frontmatter.append(existing_atoms)
    if existing_molecules:
        extra_frontmatter.append(existing_molecules)
    extra_fm = "\n".join(extra_frontmatter)
    
    # Load static repo list (survives auto-evolution)
    repos_md = ""
    repos_file = skill_path.parent / "REPOS.md"
    if repos_file.exists():
        repos_md = repos_file.read_text(encoding="utf-8").strip()
    
    # Calculate overall effectiveness (used by Elisp substitution, not inline)
    topics = (topic_data or {}).get("topics", {})
    total_kept = sum((s or {}).get('kept', 0) for s in topics.values())
    total_exp = sum((s or {}).get('total_experiments', 0) for s in topics.values())
    
    # Generate sections (still used in Mission and other sections)
    priority_topics_md = format_priority_topics(topic_data, temporal_data)
    project_priorities_md = format_project_priorities(source_data)
    anti_patterns_md = format_anti_patterns(topic_data)
    
    # Build the evolved skill content
    evolved_content = f"""---
name: researcher-prompt
description: Prompt template for external research specialist subagent. Auto-evolves based on experiment outcomes.
version: 2.0
evolve-script: evolve_researcher.py
{extra_fm}
---
metadata:
  evolution-stats:
    total-experiments: {topic_data.get('total_experiments', 870)}

---

# Auto-Workflow Researcher Prompt

## Role

You are an **external research specialist** for an Emacs-based AI agent system.
Your job: hunt the internet for novel ideas that could improve our project.

## Current Research Performance

- Overall research effectiveness: {{research-effectiveness}}.0% ({{kept-research}}/{{total-research}} research-correlated experiments kept)
- Analysis window: last {topic_data.get('lookback_days', 30)} days
- Topics ranked by downstream success:

{{topic-performance}}

{{research-champion}}

{{ontology-gaps}}

{{current-bottlenecks}}

## Mission

{priority_topics_md}

## Priority Projects to Monitor

{project_priorities_md}

---

{repos_md}

---

Check their: recent commits, open issues, closed PRs, architecture decisions
Focus on: patterns we can adapt to our Emacs AI agent system

## Anti-patterns (avoid)

{anti_patterns_md}

## Dynamic Updates

This skill auto-evolves every {topic_data.get('lookback_days', 30)} days based on:
1. Correlation between research topics and experiment keep rates
2. Source effectiveness tracking (which external projects produce actionable insights)
3. Temporal pattern detection (emerging vs declining topics)

## Sources

- **YouTube**: Recent tutorials on AI agent workflows, Emacs AI integration
- **X/Twitter**: Developer discussions on LLM tooling, agent patterns
- **GitHub**: Trending repos for ai-agent, emacs-ai, llm-workflow
- **arXiv**: Papers on agent architectures, meta-learning, code LLMs
- **HuggingFace**: New models, datasets, or spaces for code agents
- **Reddit**: r/emacs, r/LocalLLaMA, r/MachineLearning discussions

## Output Format

Return a compact structured digest. End with JSON metadata so AutoTTS can replay decisions offline:

```json
{{
  "strategy_used": "own-repos-first",
  "sources_checked": ["davidwuchn/gptel"],
  "topics_covered": ["nil-safety"],
  "confidence_final": 0.75,
  "insights_count": 2,
  "tokens_estimate": 2500
}}
```

{{{{strategy-guidance}}}}

## Instructions

1. Use WebSearch tool to find 3-5 recent/relevant items per topic
2. Use WebFetch tool to read promising pages/videos (max 3 fetches)
3. Focus on NOVEL ideas we haven't implemented (check git history first)
4. Extract specific, actionable techniques - not vague trends
5. For each insight, provide: source URL, key technique, how it applies to us
6. Max 1200 chars. Prioritize depth over breadth.
7. **MONITOR SPECIFIC PROJECTS**: Check ranked projects above for novel patterns
8. **PRIORITIZE HIGH-SUCCESS TOPICS**: Focus on topics with >30% keep rate

---

*This researcher skill auto-evolves. Performance data updates every cycle.*

## Variables

The following are substituted at prompt-build time from live data:
- `strategy-guidance`: AutoTTS controller guidance (source priority, stop threshold, beta)
- `topic-performance`: Formatted list of topics ranked by keep rate
- `research-effectiveness`, `kept-research`, `total-research`: Experiment outcome statistics
"""
    
    return evolved_content


def main():
    parser = argparse.ArgumentParser(description='Evolve researcher prompt based on outcomes')
    parser.add_argument('--analysis', help='Path to analysis JSON (from analyze_results.py)')
    parser.add_argument('--output-dir', help='Directory for output')
    parser.add_argument('--root', help='Project root directory')
    # Legacy arguments for direct invocation
    parser.add_argument('--data-dir', help='Directory containing analysis JSON files')
    parser.add_argument('--skill', help='Path to SKILL.md file to update')
    parser.add_argument('--dry-run', action='store_true', help='Print to stdout instead of writing')
    args = parser.parse_args()
    
    # Determine paths from standard evolve_skills.py arguments or legacy args
    if args.data_dir and args.skill:
        data_dir = Path(args.data_dir)
        skill_path = Path(args.skill)
    elif args.root:
        root = Path(args.root)
        data_dir = Path(args.analysis) if args.analysis else root / "assistant" / "skills" / "researcher-prompt" / "data"
        skill_path = Path(args.output_dir) / "SKILL.md" if args.output_dir else root / "assistant" / "skills" / "researcher-prompt" / "SKILL.md"
    else:
        parser.error("Either --data-dir + --skill or --root is required")
    
    print(f"Loading analysis data from {data_dir}")
    print(f"Updating skill at {skill_path}")
    
    evolved_content = generate_evolved_skill(skill_path, data_dir)
    
    if args.dry_run:
        print("\n" + "="*60)
        print("EVOLVED SKILL CONTENT:")
        print("="*60)
        print(evolved_content)
    else:
        # Write new skill
        skill_path.parent.mkdir(parents=True, exist_ok=True)
        with open(skill_path, 'w') as f:
            f.write(evolved_content)
        
        print(f"Updated {skill_path}")
        print(f"Skill size: {len(evolved_content)} chars")


if __name__ == '__main__':
    main()
