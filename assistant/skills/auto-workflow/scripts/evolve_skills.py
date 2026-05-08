#!/usr/bin/env python3
"""Master script for unified skill evolution.

Usage:
    python3 evolve_skills.py [--root ROOT] [--skills SKILL1,SKILL2,...]

This is the main entry point for skill self-evolution. It:
1. Analyzes experiment results
2. Evolves all registered skills based on their domain
3. Supports multiple skill types: auto-workflow, sandbox, grader, validator, etc.

Called by gptel-auto-workflow--evolve-all-skills in Emacs Lisp.
"""

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path


# Registry of all skills that can self-evolve
SKILL_REGISTRY = {
    'auto-workflow': {
        'scripts': ['analyze_results.py', 'generate_directive.py', 'generate_researcher.py'],
        'output_dir': 'assistant/skills/auto-workflow',
        'description': 'Main auto-workflow skills (directive, researcher)',
    },
    'sandbox-profiles': {
        'scripts': ['evolve_profiles.py'],
        'output_dir': 'assistant/skills/sandbox-profiles',
        'description': 'Sandbox tool permission profiles',
    },
    'eight-keys-grader': {
        'scripts': ['evolve_rubric.py'],
        'output_dir': 'assistant/skills/eight-keys-grader',
        'description': 'Eight Keys scoring rubric',
    },
    'elisp-validator': {
        'scripts': ['evolve_rules.py'],
        'output_dir': 'assistant/skills/elisp-validator',
        'description': 'Elisp validation rules',
    },
    'provider-error-analyzer': {
        'scripts': ['evolve_patterns.py'],
        'output_dir': 'assistant/skills/provider-error-analyzer',
        'description': 'Provider error patterns',
    },
    'benchmark-improver': {
        'scripts': ['evolve_benchmark.py'],
        'output_dir': 'assistant/skills/benchmark-improver',
        'description': 'Wu Xing benchmark improvement rules',
    },
}


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


def generate_skill(skill_name, analysis_path, root_dir):
    """Generate a specific skill from analysis."""
    skill_info = SKILL_REGISTRY.get(skill_name)
    if not skill_info:
        print(f"Unknown skill: {skill_name}", file=sys.stderr)
        return False
    
    skills_dir = Path(root_dir) / skill_info['output_dir']
    scripts_dir = Path(__file__).parent
    
    print(f"\n  Evolving {skill_name}...")
    print(f"    {skill_info['description']}")
    
    # Run each script for this skill
    for script_name in skill_info['scripts']:
        script_path = scripts_dir / script_name
        if not script_path.exists():
            print(f"    Script not found: {script_name}")
            continue
            
        result = subprocess.run([
            sys.executable, str(script_path),
            "--analysis", str(analysis_path),
            "--output-dir", str(skills_dir),
            "--root", root_dir
        ], capture_output=True, text=True)
        
        if result.returncode != 0:
            print(f"    Failed: {result.stderr}", file=sys.stderr)
        else:
            print(f"    ✓ {script_name}")
    
    return True


def update_skill_metadata(skills_dir, analysis):
    """Update all SKILL.md files with latest metadata."""
    for skill_file in skills_dir.rglob("SKILL.md"):
        with open(skill_file, 'r') as f:
            content = f.read()
        
        # Update version and timestamp in frontmatter
        import re
        from datetime import datetime
        
        now = datetime.now().strftime('%Y-%m-%d %H:%M')
        
        # Update updated field
        content = re.sub(
            r'updated: \d{4}-\d{2}-\d{2}( \d{2}:\d{2})?',
            f'updated: {now}',
            content
        )
        
        # Add evolution metadata if not present
        if 'evolution-stats:' not in content:
            content = content.replace(
                '---\n\n#',
                f'---\nmetadata:\n  evolution-stats:\n    total-experiments: {analysis["total_experiments"]}\n    last-evolution: {now}\n\n---\n\n#'
            )
        
        with open(skill_file, 'w') as f:
            f.write(content)


def main():
    parser = argparse.ArgumentParser(description='Evolve all skills')
    parser.add_argument('--root', default='.',
                       help='Project root directory')
    parser.add_argument('--skills', default='all',
                       help='Comma-separated list of skills to evolve (default: all)')
    args = parser.parse_args()
    
    root_dir = os.path.expanduser(args.root)
    root_path = Path(root_dir)
    
    # Determine which skills to evolve
    if args.skills == 'all':
        skills_to_evolve = list(SKILL_REGISTRY.keys())
    else:
        skills_to_evolve = [s.strip() for s in args.skills.split(',')]
    
    # Ensure directories exist
    output_dir = root_path / "var" / "tmp" / "skill-evolution"
    output_dir.mkdir(parents=True, exist_ok=True)
    
    print("=" * 60)
    print("Unified Skill Evolution")
    print("=" * 60)
    print(f"\nSkills to evolve: {', '.join(skills_to_evolve)}")
    
    # Step 1: Analyze results (shared across all skills)
    print("\n[1/3] Analyzing experiment results...")
    analysis_path = run_analysis(root_dir, output_dir)
    
    with open(analysis_path, 'r') as f:
        analysis = json.load(f)
    
    print(f"  Total experiments: {analysis['total_experiments']}")
    print(f"  Targets tracked: {len(analysis['target_stats'])}")
    
    # Step 2: Evolve each skill
    print("\n[2/3] Evolving skills...")
    evolved = []
    for skill_name in skills_to_evolve:
        if generate_skill(skill_name, analysis_path, root_dir):
            evolved.append(skill_name)
    
    # Step 3: Update metadata across all skills
    print("\n[3/3] Updating skill metadata...")
    skills_root = root_path / "assistant" / "skills"
    update_skill_metadata(skills_root, analysis)
    
    # Summary
    print("\n" + "=" * 60)
    print("Evolution Complete!")
    print("=" * 60)
    print(f"\nEvolved {len(evolved)} skills:")
    for skill in evolved:
        info = SKILL_REGISTRY[skill]
        print(f"  ✓ {skill}: {info['description']}")
    
    print(f"\nAnalysis cached at: {analysis_path}")
    print(f"\nTop 5 targets:")
    for i, stat in enumerate(analysis['target_stats'][:5], 1):
        print(f"  {i}. {stat['target']}: {stat['keep_rate']*100:.0f}% ({stat['kept']}/{stat['total']})")


if __name__ == '__main__':
    main()
