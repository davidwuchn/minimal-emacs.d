#!/usr/bin/env python3
"""Evolve sandbox-profiles skill based on experiment results.

Updates tool permission profiles based on which tools correlate with
success vs failure in experiments.
"""

import argparse
import json
import re
from pathlib import Path
from datetime import datetime


def analyze_tool_usage(analysis):
    """Analyze which tool usage patterns correlate with success."""
    tool_stats = {}
    
    for stats in analysis.get('target_stats', []):
        for exp in stats.get('experiments', []):
            tools = exp.get('tools_used', [])
            passed = exp.get('passed', False)
            for tool in tools:
                if tool not in tool_stats:
                    tool_stats[tool] = {'success': 0, 'failure': 0, 'total': 0}
                tool_stats[tool]['total'] += 1
                if passed:
                    tool_stats[tool]['success'] += 1
                else:
                    tool_stats[tool]['failure'] += 1
    
    return tool_stats


def generate_profiles(tool_stats):
    """Generate updated tool permission profiles."""
    profiles = []
    
    for tool, stats in sorted(tool_stats.items()):
        if stats['total'] < 3:
            continue
        
        success_rate = stats['success'] / stats['total']
        
        if success_rate > 0.8:
            level = "allow"
        elif success_rate > 0.5:
            level = "confirm"
        else:
            level = "forbid"
        
        profiles.append({
            'tool': tool,
            'level': level,
            'success_rate': success_rate,
            'total': stats['total']
        })
    
    return profiles


def update_skill_file(output_dir, profiles):
    """Update the SKILL.md file with evolved profiles."""
    skill_file = Path(output_dir) / "SKILL.md"
    
    if not skill_file.exists():
        print(f"Skill file not found: {skill_file}")
        return
    
    with open(skill_file, 'r') as f:
        content = f.read()
    
    # Generate profiles markdown
    profiles_md = "\n## Evolved Tool Profiles\n\n"
    profiles_md += "Based on analysis of {} experiments.\n\n".format(
        sum(p['total'] for p in profiles)
    )
    profiles_md += "| Tool | Level | Success Rate | Experiments |\n"
    profiles_md += "|------|-------|--------------|-------------|\n"
    
    for p in profiles:
        profiles_md += "| {} | {} | {:.0%} | {} |\n".format(
            p['tool'], p['level'], p['success_rate'], p['total']
        )
    
    profiles_md += "\n"
    
    # Replace or append evolved profiles section
    if "## Evolved Tool Profiles" in content:
        content = re.sub(
            r"## Evolved Tool Profiles.*?(?=\n## |\Z)",
            profiles_md.rstrip(),
            content,
            flags=re.DOTALL
        )
    else:
        # Append before the last section or at the end
        content = content.rstrip() + "\n\n" + profiles_md
    
    content = re.sub(r'^updated: \d{4}-\d{2}-\d{2}( \d{2}:\d{2})?\n?', '', content, flags=re.MULTILINE)
    
    with open(skill_file, 'w') as f:
        f.write(content)
    
    print(f"Updated {skill_file} with {len(profiles)} evolved profiles")


def main():
    parser = argparse.ArgumentParser(description='Evolve sandbox-profiles skill')
    parser.add_argument('--analysis', required=True, help='Path to analysis JSON')
    parser.add_argument('--output-dir', required=True, help='Output directory for skill')
    parser.add_argument('--root', default='.', help='Project root')
    args = parser.parse_args()
    
    with open(args.analysis, 'r') as f:
        analysis = json.load(f)
    
    tool_stats = analyze_tool_usage(analysis)
    profiles = generate_profiles(tool_stats)
    update_skill_file(args.output_dir, profiles)


if __name__ == '__main__':
    main()
