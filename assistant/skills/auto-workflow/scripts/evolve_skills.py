#!/usr/bin/env python3
"""Master script for unified skill evolution.

Usage:
    python3 evolve_skills.py [--root ROOT] [--skills SKILL1,SKILL2,...]

This is the main entry point for skill self-evolution. It:
1. Auto-discovers skills from assistant/skills/*/SKILL.md
2. Analyzes experiment results
3. Evolves all registered skills based on their domain
4. Supports multiple skill types: auto-workflow, sandbox, grader, validator, etc.

Called by gptel-auto-workflow--evolve-all-skills in Emacs Lisp.
"""

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path


def discover_skills(root_dir):
    """Auto-discover skills from assistant/skills/*/SKILL.md files.
    
    Each skill directory should contain:
    - SKILL.md with frontmatter (name, description, version)
    - Optional scripts/ directory with evolve_*.py scripts
    
    Returns dict mapping skill_name -> skill_info
    """
    skills_root = Path(root_dir) / "assistant" / "skills"
    registry = {}
    
    if not skills_root.exists():
        return registry
    
    for skill_dir in sorted(skills_root.iterdir()):
        if not skill_dir.is_dir() or skill_dir.name.startswith('_'):
            continue
            
        skill_file = skill_dir / "SKILL.md"
        if not skill_file.exists():
            continue
        
        # Parse frontmatter
        with open(skill_file, 'r') as f:
            content = f.read()
        
        name_match = re.search(r'^name:\s*(.+)$', content, re.MULTILINE)
        desc_match = re.search(r'^description:\s*(.+)$', content, re.MULTILINE)
        evolve_match = re.search(r'^evolve-script:\s*(.+)$', content, re.MULTILINE)
        
        skill_name = name_match.group(1).strip() if name_match else skill_dir.name
        description = desc_match.group(1).strip() if desc_match else skill_dir.name
        
        # Find evolve scripts
        scripts = []
        
        # 1. Check if skill declares its own evolve script
        if evolve_match:
            script_name = evolve_match.group(1).strip()
            shared_scripts_dir = Path(root_dir) / "assistant" / "skills" / "auto-workflow" / "scripts"
            script_path = shared_scripts_dir / script_name
            if script_path.exists():
                scripts.append(script_name)
        
        # 2. Check skill-specific scripts directory
        # Skip auto-workflow/scripts since it contains shared scripts
        if skill_dir.name != 'auto-workflow':
            scripts_dir = skill_dir / "scripts"
            if scripts_dir.exists():
                for script in scripts_dir.glob("evolve_*.py"):
                    if script.name not in scripts:
                        scripts.append(script.name)
        
        registry[skill_name] = {
            'scripts': scripts,
            'output_dir': f"assistant/skills/{skill_dir.name}",
            'description': description,
            'dir': skill_dir.name,
        }
    
    return registry


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


def generate_skill(skill_name, skill_info, analysis_path, root_dir):
    """Generate a specific skill from analysis."""
    skills_dir = Path(root_dir) / skill_info['output_dir']
    scripts_dir = Path(root_dir) / "assistant" / "skills" / "auto-workflow" / "scripts"
    
    print(f"\n  Evolving {skill_name}...")
    print(f"    {skill_info['description']}")
    
    if not skill_info['scripts']:
        print(f"    No evolve scripts found, skipping")
        return True
    
    # Run each script for this skill
    for script_name in skill_info['scripts']:
        # Try skill-specific scripts first
        script_path = skills_dir / "scripts" / script_name
        if not script_path.exists():
            # Fall back to shared scripts
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
    from datetime import datetime
    
    now = datetime.now().strftime('%Y-%m-%d %H:%M')
    
    for skill_file in skills_dir.rglob("SKILL.md"):
        with open(skill_file, 'r') as f:
            content = f.read()
        
        # Update updated field
        content = re.sub(
            r'^updated:\s*\d{4}-\d{2}-\d{2}( \d{2}:\d{2})?',
            f'updated: {now}',
            content,
            flags=re.MULTILINE
        )
        
        # Add evolution metadata if not present
        if 'evolution-stats:' not in content:
            content = content.replace(
                '---\n\n#',
                f'---\nmetadata:\n  evolution-stats:\n    total-experiments: {analysis["total_experiments"]}\n    last-evolution: {now}\n\n---\n\n#',
                1
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
    
    # Auto-discover skills
    print("[0/3] Discovering skills...")
    SKILL_REGISTRY = discover_skills(root_dir)
    print(f"  Found {len(SKILL_REGISTRY)} skills:")
    for name, info in SKILL_REGISTRY.items():
        print(f"    - {name}: {info['description']}")
    
    # Determine which skills to evolve
    if args.skills == 'all':
        skills_to_evolve = list(SKILL_REGISTRY.keys())
    else:
        skills_to_evolve = [s.strip() for s in args.skills.split(',')]
        # Validate
        for skill in skills_to_evolve:
            if skill not in SKILL_REGISTRY:
                print(f"Warning: Unknown skill '{skill}', skipping")
        skills_to_evolve = [s for s in skills_to_evolve if s in SKILL_REGISTRY]
    
    # Ensure directories exist
    output_dir = root_path / "var" / "tmp" / "skill-evolution"
    output_dir.mkdir(parents=True, exist_ok=True)
    
    print("\n" + "=" * 60)
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
        skill_info = SKILL_REGISTRY[skill_name]
        if generate_skill(skill_name, skill_info, analysis_path, root_dir):
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
