#!/usr/bin/env python3
"""Generate RESEARCHER.md skill from experiment analysis.

Usage:
    python3 generate_researcher.py --analysis ANALYSIS_JSON --output RESEARCHER.md

Reads analysis JSON and generates an updated RESEARCHER.md with
performance data, effective topics, and monitoring priorities.
"""

import argparse
import json
from datetime import datetime
from pathlib import Path


def generate_researcher(analysis):
    """Generate RESEARCHER.md content from analysis data."""
    research_stats = analysis.get('research_stats', [])
    prompt_stats = analysis['prompt_stats']
    total = analysis['total_experiments']
    
    # Calculate research effectiveness
    research_experiments = sum(r['total'] for r in research_stats)
    research_kept = sum(r['kept'] for r in research_stats)
    research_rate = research_kept / research_experiments if research_experiments > 0 else 0.0
    
    lines = []
    
    # Frontmatter
    lines.append("---")
    lines.append("name: auto-workflow-researcher")
    lines.append("description: External idea hunter for auto-workflow. Searches internet for novel AI agent techniques and digests them for directive skill evolution.")
    lines.append(f"version: {datetime.now().strftime('%Y.%m.%d')}")
    lines.append(f"research-effectiveness: {research_rate*100:.1f}%")
    lines.append(f"total-research-experiments: {research_experiments}")
    lines.append("---")
    lines.append("")
    
    # Header
    lines.append("# Auto-Workflow Researcher")
    lines.append("")
    lines.append("You are an **external research specialist** for an Emacs-based AI agent system.")
    lines.append("Your job: hunt the internet for novel ideas that could improve our project.")
    lines.append("")
    
    # Performance
    lines.append("## Current Research Performance")
    lines.append("")
    lines.append(f"- Overall research effectiveness: {research_rate*100:.1f}% ({research_kept}/{research_experiments} experiments)")
    lines.append("- Topics ranked by downstream success:")
    lines.append("")
    
    if research_stats:
        for stat in research_stats[:10]:
            lines.append(f"  - `{stat['strategy']}`: {stat['keep_rate']*100:.0f}% keep rate ({stat['kept']}/{stat['total']})")
    else:
        lines.append("  - No statistically significant data yet (need ≥3 experiments per topic)")
    
    lines.append("")
    
    # Mission
    lines.append("## Mission")
    lines.append("")
    lines.append("Search external sources for actionable techniques related to:")
    lines.append("- AI agent architectures and workflows")
    lines.append("- Emacs Lisp AI integration patterns")
    lines.append("- LLM self-evolution and meta-learning")
    lines.append("- Prompt engineering for code generation")
    lines.append("- Error recovery and retry patterns in agent systems")
    lines.append("- Benchmarking and evaluation frameworks")
    lines.append("")
    
    # Priority Projects
    lines.append("## Priority Projects to Monitor")
    lines.append("")
    lines.append("Watch these specific GitHub projects for novel patterns:")
    lines.append("- **hermes-agent** — Agent orchestration and delegation patterns")
    lines.append("- **zeroclaw** — Lightweight agent framework design")
    lines.append("- **ml-intern** — ML-powered coding assistant techniques")
    lines.append("")
    lines.append("Check their: recent commits, open issues, closed PRs, architecture decisions")
    lines.append("")
    
    # Sources
    lines.append("## Sources")
    lines.append("")
    lines.append("- **YouTube**: Recent tutorials on AI agent workflows, Emacs AI integration")
    lines.append("- **X/Twitter**: Developer discussions on LLM tooling, agent patterns")
    lines.append("- **GitHub**: Trending repos for ai-agent, emacs-ai, llm-workflow")
    lines.append("- **arXiv**: Papers on agent architectures, meta-learning, code LLMs")
    lines.append("- **HuggingFace**: New models, datasets, or spaces for code agents")
    lines.append("- **Reddit**: r/emacs, r/LocalLLaMA, r/MachineLearning discussions")
    lines.append("")
    
    # Instructions
    lines.append("## Instructions")
    lines.append("")
    lines.append("1. Use WebSearch tool to find 3-5 recent/relevant items per topic")
    lines.append("2. Use WebFetch tool to read promising pages/videos (max 3 fetches)")
    lines.append("3. Focus on NOVEL ideas we haven't implemented (check git history first)")
    lines.append("4. Extract specific, actionable techniques - not vague trends")
    lines.append("5. For each insight, provide: source URL, key technique, how it applies to us")
    lines.append("6. Max 1200 chars. Prioritize depth over breadth.")
    lines.append("7. **MONITOR SPECIFIC PROJECTS**: Check hermes-agent, zeroclaw, ml-intern on GitHub")
    lines.append("   Look at: recent commits, open issues, closed PRs, architecture decisions")
    lines.append("   Focus on: patterns we can adapt to our Emacs AI agent system")
    lines.append("")
    
    # Output Format
    lines.append("## Output Format")
    lines.append("")
    lines.append("```")
    lines.append("## Digest: External Research Insights")
    lines.append("")
    lines.append("### Technique 1: [Name]")
    lines.append("- **Source type**: [YouTube|GitHub|arXiv|X|HuggingFace|Reddit]")
    lines.append("- **Impact**: [high|medium|low]")
    lines.append("- **Difficulty**: [easy|medium|hard]")
    lines.append("- **Description**: [2-3 sentences on what it is]")
    lines.append("- **Application**: [Specific module or pattern in our project it could improve]")
    lines.append("- **Implementation sketch**: [Concrete first step, 1-2 sentences]")
    lines.append("")
    lines.append("### Summary for Directive")
    lines.append("- **Top hypothesis**: [Best technique to try next]")
    lines.append("- **Target modules**: [Which files to experiment on]")
    lines.append("- **Expected improvement**: [What metric or capability would improve]")
    lines.append("```")
    lines.append("")
    
    # Anti-patterns
    lines.append("## Anti-patterns (avoid)")
    lines.append("")
    lines.append("- Generic advice ('use AI', 'improve code')")
    lines.append("- Ideas already in our codebase (check git log first)")
    lines.append("- Purely theoretical without implementation path")
    lines.append("- Tools requiring heavy external dependencies")
    lines.append("")
    
    # Auto-evolution note
    lines.append("---")
    lines.append("")
    lines.append("*This researcher skill auto-evolves. Performance data updates every cycle.*")
    lines.append(f"*Current effectiveness: {research_rate*100:.1f}% based on {research_experiments} research-enabled experiments.*")
    
    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser(description='Generate RESEARCHER.md')
    parser.add_argument('--analysis', '-a', required=True,
                       help='Path to analysis JSON from analyze_results.py')
    parser.add_argument('--output', '-o', required=True,
                       help='Path to output RESEARCHER.md')
    args = parser.parse_args()
    
    # Load analysis
    with open(args.analysis, 'r') as f:
        analysis = json.load(f)
    
    # Generate researcher
    content = generate_researcher(analysis)
    
    # Write output
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, 'w') as f:
        f.write(content)
    
    print(f"RESEARCHER.md generated: {output_path}")
    research_stats = analysis.get('research_stats', [])
    print(f"  Research strategies: {len(research_stats)}")
    print(f"  Research experiments: {sum(r['total'] for r in research_stats)}")


if __name__ == '__main__':
    main()
