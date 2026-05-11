#!/usr/bin/env python3
"""Generate DIRECTIVE.md skill from experiment analysis.

Usage:
    python3 generate_directive.py --analysis ANALYSIS_JSON --output DIRECTIVE.md

Reads analysis JSON from analyze_results.py and generates an updated
DIRECTIVE.md with current target rankings, patterns, and hypotheses.
"""

import argparse
import json
import os
from datetime import datetime
from pathlib import Path


def generate_directive(analysis, skill_dir, patterns=None):
    """Generate DIRECTIVE.md content from analysis data.
    
    Args:
        analysis: Results analysis JSON from analyze_results.py
        skill_dir: Path to skill directory
        patterns: Optional pattern analysis from analyze_patterns.py
    """
    total = analysis.get('total_experiments', 0)
    local_total = analysis.get('local_experiments', total)
    kept = analysis['prompt_stats']['total_kept']
    target_stats = analysis['target_stats']
    
    # Extract learned patterns if available
    learned = patterns.get('learned_patterns', {}) if patterns else {}
    
    lines = []
    
    # Frontmatter
    lines.append("---")
    lines.append("name: auto-workflow-directive")
    lines.append("description: Evolving program definition for auto-workflow")
    lines.append(f"version: {datetime.now().strftime('%Y.%m.%d')}")
    lines.append(f"total-experiments: {total}")
    lines.append(f"total-kept: {kept}")
    lines.append("---")
    lines.append("")
    
    # Header
    lines.append("# Auto-Workflow Program")
    lines.append("")
    lines.append("> LLM decides targets and strategies. We gather context and execute.")
    lines.append("> This directive is AUTO-EVOLVED from experiment results.")
    lines.append("> Philosophy: Learn from every experiment. Adapt the program.")
    lines.append("")
    
    # Active Targets
    lines.append("## Active Targets")
    lines.append("")
    lines.append("<!-- AUTO-UPDATED: Targets ranked by recent keep rate -->")
    lines.append("| Target | Keep Rate | Total | Kept | Status |")
    lines.append("|--------|-----------|-------|------|--------|")
    
    for stat in target_stats[:10]:
        rate = stat['keep_rate']
        status = "✅ High yield" if rate >= 0.3 else "🟡 Active" if rate >= 0.1 else "❌ Plateaued" if stat['total'] > 5 else "⏳ Insufficient data"
        lines.append(f"| `{stat['target']}` | {rate*100:.0f}% | {stat['total']} | {stat['kept']} | {status} |")
    
    lines.append("")
    
    # Meta-Learned Patterns (NEW)
    if learned.get('high_value_patterns'):
        lines.append("## 🧬 Meta-Learned Patterns")
        lines.append("")
        lines.append("<!-- AUTO-UPDATED: From git history + mementum analysis -->")
        lines.append("*These patterns were automatically extracted from successful experiments.*")
        lines.append("")
        
        for pattern_data in learned['high_value_patterns'][:8]:
            pattern = pattern_data['pattern']
            evidence = pattern_data['evidence']
            source = pattern_data.get('source', 'analysis')
            lines.append(f"- **{pattern}** ({evidence}× from {source})")
        
        lines.append("")
    
    # Effective Techniques (NEW)
    if learned.get('effective_techniques'):
        lines.append("## 🛠️ Effective Techniques")
        lines.append("")
        lines.append("<!-- AUTO-UPDATED: From mementum insights -->")
        lines.append("")
        
        for tech_data in learned['effective_techniques'][:6]:
            technique = tech_data['technique']
            freq = tech_data['frequency']
            lines.append(f"- {technique} (seen {freq}×)")
        
        lines.append("")
    
    # Error Mitigation (NEW)
    if learned.get('error_mitigation'):
        lines.append("## 🛡️ Error Mitigation")
        lines.append("")
        lines.append("<!-- AUTO-UPDATED: From experiment error analysis -->")
        lines.append("")
        
        for err_data in learned['error_mitigation'][:5]:
            error = err_data['error']
            freq = err_data['frequency']
            mitigation = err_data['mitigation']
            lines.append(f"- **{error}** ({freq}×): {mitigation}")
        
        lines.append("")
    
    # Success Patterns (legacy, for backward compatibility)
    lines.append("## Success Patterns")
    lines.append("")
    lines.append("<!-- AUTO-UPDATED: From mementum knowledge -->")
    
    # Extract patterns from successful targets
    success_patterns = set()
    for stat in target_stats[:5]:
        target = stat['target']
        if 'sanitize' in target:
            success_patterns.add("Add input validation and sanitization guards")
        elif 'error' in target or 'retry' in target:
            success_patterns.add("Improve error handling and recovery mechanisms")
        elif 'cache' in target:
            success_patterns.add("Add caching with proper invalidation")
        elif 'guard' in target or 'validate' in target:
            success_patterns.add("Add nil guards and boundary checks")
        else:
            success_patterns.add("Extract helper functions for repeated logic")
    
    if not success_patterns:
        success_patterns = {
            "Extract constants into named variables",
            "Add nil guards on plist/assoc lookups",
            "Extract helper functions for repeated logic",
        }
    
    for pattern in sorted(success_patterns):
        lines.append(f"- {pattern}")
    lines.append("")
    
    # Failed Patterns
    lines.append("## Failed Patterns")
    lines.append("")
    lines.append("<!-- AUTO-UPDATED: From mementum knowledge -->")
    
    # Add learned failure patterns if available
    if learned.get('avoid_patterns'):
        for pattern_data in learned['avoid_patterns'][:5]:
            pattern = pattern_data['pattern']
            lines.append(f"- {pattern}")
    else:
        lines.append("- TODO-only targets (no actionable bugs)")
        lines.append("- Pure refactoring without bug fix")
        lines.append("- Common Lisp symbols not in Emacs Lisp")
    
    lines.append("")
    
    # Next Hypotheses
    lines.append("## Next Hypotheses")
    lines.append("")
    lines.append("<!-- AUTO-UPDATED: From experiment insights -->")
    
    # Generate hypotheses using learned patterns
    hypothesis_count = 0
    
    # First, try to use meta-learned patterns to generate better hypotheses
    if learned.get('priority_targets'):
        for target_data in learned['priority_targets']:
            if target_data['recommendation'] == 'prioritize' and hypothesis_count < 3:
                target = target_data['target']
                # Pick a relevant technique
                technique = 'nil guards and validation'
                if learned.get('effective_techniques'):
                    technique = learned['effective_techniques'][0]['technique']
                lines.append(f"- **{target}**: Apply {technique} (keep rate: {target_data['keep_rate']*100:.0f}%)")
                hypothesis_count += 1
    
    # Fallback to old logic
    for stat in target_stats:
        if stat['keep_rate'] < 0.2 and stat['total'] >= 3 and hypothesis_count < 5:
            lines.append(f"- **{stat['target']}**: Try validation guards or error handling improvements (previous experiments discarded)")
            hypothesis_count += 1
    
    if hypothesis_count == 0:
        lines.append("- Continue with current targets based on research findings")
    
    lines.append("")
    
    # Immutable Files
    lines.append("## Immutable Files")
    lines.append("")
    lines.append("```")
    lines.append("early-init.el")
    lines.append("pre-early-init.el")
    lines.append("lisp/eca-security.el")
    lines.append("lisp/modules/gptel-ext-security.el")
    lines.append("lisp/modules/gptel-ext-tool-confirm.el")
    lines.append("lisp/modules/gptel-ext-tool-permits.el")
    lines.append("eca/**")
    lines.append("mementum/**")
    lines.append("var/elpa/**")
    lines.append("```")
    lines.append("")
    
    # Constraints
    lines.append("## Constraints")
    lines.append("")
    lines.append("| Setting | Value |")
    lines.append("|---------|-------|")
    lines.append("| Per experiment | 15 minutes |")
    lines.append("| Max per target | 10 experiments |")
    lines.append("| Stop if no improvement | 3 consecutive |")
    lines.append("")
    
    # Footer
    lines.append("---")
    lines.append("")
    lines.append(f"*This directive was auto-generated from {total} experiments ({kept} kept locally across {local_total} local records). It evolves every self-evolution cycle.*")
    
    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser(description='Generate DIRECTIVE.md')
    parser.add_argument('--analysis', '-a', required=True,
                       help='Path to analysis JSON from analyze_results.py')
    parser.add_argument('--patterns', '-p', default=None,
                       help='Path to pattern analysis JSON from analyze_patterns.py')
    parser.add_argument('--output', '-o', required=True,
                       help='Path to output DIRECTIVE.md')
    args = parser.parse_args()
    
    # Load analysis
    with open(args.analysis, 'r') as f:
        analysis = json.load(f)
    
    # Load patterns if provided
    patterns = None
    if args.patterns and Path(args.patterns).exists():
        with open(args.patterns, 'r') as f:
            patterns = json.load(f)
        print(f"Loaded pattern analysis: {args.patterns}")
    
    # Generate directive
    skill_dir = Path(args.output).parent
    content = generate_directive(analysis, skill_dir, patterns)
    
    # Write output
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, 'w') as f:
        f.write(content)
    
    print(f"DIRECTIVE.md generated: {output_path}")
    print(f"  Total experiments: {analysis['total_experiments']}")
    print(f"  Targets tracked: {len(analysis['target_stats'])}")
    if patterns:
        learned = patterns.get('learned_patterns', {})
        print(f"  Meta-learned patterns: {len(learned.get('high_value_patterns', []))}")
        print(f"  Effective techniques: {len(learned.get('effective_techniques', []))}")
        print(f"  Error mitigations: {len(learned.get('error_mitigation', []))}")


if __name__ == '__main__':
    main()
