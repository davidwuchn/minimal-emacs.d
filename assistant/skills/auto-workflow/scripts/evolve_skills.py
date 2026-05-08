#!/usr/bin/env python3
"""Master script for auto-workflow skill evolution.

Usage:
    python3 evolve_skills.py [--root ROOT]

This is the main entry point for skill self-evolution. It:
1. Analyzes experiment results
2. Generates DIRECTIVE.md with updated target rankings
3. Generates RESEARCHER.md with current performance data
4. Optionally generates RESEARCH.md with strategy summaries

Called by gptel-auto-workflow--evolve-all-skills in Emacs Lisp.
"""

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path


def run_analysis(root_dir, output_dir):
    """Run analyze_results.py and return path to output JSON."""
    analysis_path = output_dir / "analysis.json"
    
    script = Path(__file__).parent / "analyze_results.py"
    cmd = [
        sys.executable, str(script),
        "--root", root_dir,
        "--output", str(analysis_path)
    ]
    
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Analysis failed: {result.stderr}", file=sys.stderr)
        sys.exit(1)
    
    return analysis_path


def generate_skills(analysis_path, skills_dir):
    """Generate all skill files from analysis."""
    scripts_dir = Path(__file__).parent
    
    # Generate DIRECTIVE.md
    directive_script = scripts_dir / "generate_directive.py"
    directive_output = skills_dir / "DIRECTIVE.md"
    
    result = subprocess.run([
        sys.executable, str(directive_script),
        "--analysis", str(analysis_path),
        "--output", str(directive_output)
    ], capture_output=True, text=True)
    
    if result.returncode != 0:
        print(f"Directive generation failed: {result.stderr}", file=sys.stderr)
    else:
        print(result.stdout)
    
    # Generate RESEARCHER.md
    researcher_script = scripts_dir / "generate_researcher.py"
    researcher_output = skills_dir / "RESEARCHER.md"
    
    result = subprocess.run([
        sys.executable, str(researcher_script),
        "--analysis", str(analysis_path),
        "--output", str(researcher_output)
    ], capture_output=True, text=True)
    
    if result.returncode != 0:
        print(f"Researcher generation failed: {result.stderr}", file=sys.stderr)
    else:
        print(result.stdout)


def main():
    parser = argparse.ArgumentParser(description='Evolve all auto-workflow skills')
    parser.add_argument('--root', default='.',
                       help='Project root directory')
    args = parser.parse_args()
    
    root_dir = os.path.expanduser(args.root)
    root_path = Path(root_dir)
    
    # Ensure directories exist
    skills_dir = root_path / "assistant" / "skills" / "auto-workflow"
    output_dir = root_path / "var" / "tmp" / "skill-evolution"
    
    skills_dir.mkdir(parents=True, exist_ok=True)
    output_dir.mkdir(parents=True, exist_ok=True)
    
    print("=" * 60)
    print("Auto-Workflow Skill Evolution")
    print("=" * 60)
    
    # Step 1: Analyze results
    print("\n[1/3] Analyzing experiment results...")
    analysis_path = run_analysis(root_dir, output_dir)
    
    # Load analysis for summary
    with open(analysis_path, 'r') as f:
        analysis = json.load(f)
    
    print(f"  Total experiments: {analysis['total_experiments']}")
    print(f"  Targets tracked: {len(analysis['target_stats'])}")
    print(f"  Research strategies: {len(analysis.get('research_stats', []))}")
    
    # Step 2: Generate skills
    print("\n[2/3] Generating skill files...")
    generate_skills(analysis_path, skills_dir)
    
    # Step 3: Summary
    print("\n[3/3] Evolution complete!")
    print(f"\nGenerated skills:")
    print(f"  - {skills_dir / 'DIRECTIVE.md'}")
    print(f"  - {skills_dir / 'RESEARCHER.md'}")
    print(f"\nAnalysis cached at: {analysis_path}")
    
    # Show top targets
    print(f"\nTop 5 targets by keep rate:")
    for i, stat in enumerate(analysis['target_stats'][:5], 1):
        print(f"  {i}. {stat['target']}: {stat['keep_rate']*100:.0f}% ({stat['kept']}/{stat['total']})")


if __name__ == '__main__':
    main()
