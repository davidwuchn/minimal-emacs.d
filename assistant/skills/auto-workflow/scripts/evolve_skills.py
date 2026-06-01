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


def run_pattern_analysis(root_dir, output_dir):
    """Run analyze_patterns.py and return path to output JSON."""
    patterns_path = output_dir / "patterns.json"
    
    script = Path(__file__).parent / "analyze_patterns.py"
    cmd = [
        sys.executable, str(script),
        "--root", root_dir,
        "--output", str(patterns_path)
    ]
    
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Pattern analysis failed: {result.stderr}", file=sys.stderr)
        # Don't exit, just return None - analysis is optional
        return None
    
    return patterns_path


def skill_total_experiments(skill_dir):
    """Return the largest total-experiments value already recorded for SKILL_DIR."""
    skill_file = Path(skill_dir) / "SKILL.md"
    if not skill_file.exists():
        return 0
    try:
        content = skill_file.read_text(encoding="utf-8")
    except OSError:
        return 0
    totals = [int(match.group(1))
              for match in re.finditer(r'total-experiments:\s*(\d+)', content)]
    return max(totals, default=0)


def generate_skill(skill_name, skill_info, analysis_path, root_dir, patterns_path=None):
    """Generate a specific skill from analysis."""
    skills_dir = Path(root_dir) / skill_info['output_dir']
    scripts_dir = Path(root_dir) / "assistant" / "skills" / "auto-workflow" / "scripts"
    
    print(f"\n  Evolving {skill_name}...")
    print(f"    {skill_info['description']}")
    
    if not skill_info['scripts']:
        print(f"    No evolve scripts found, skipping")
        return True

    with open(analysis_path, 'r') as f:
        analysis = json.load(f)
    total_experiments = analysis.get('total_experiments', 0)
    local_total = analysis.get('local_experiments', 0)
    existing_total = skill_total_experiments(skills_dir)
    if existing_total >= total_experiments and local_total == 0:
        print(f"    No new experiments ({existing_total} existing, {local_total} local)")
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
        
        # Build command
        cmd = [
            sys.executable, str(script_path),
            "--analysis", str(analysis_path),
            "--output-dir", str(skills_dir),
            "--root", root_dir
        ]
        
        # Pass skill-file for generic evolve script
        if script_name == 'evolve_generic.py':
            skill_file = skills_dir / "SKILL.md"
            if skill_file.exists():
                cmd.extend(["--skill-file", str(skill_file)])
            else:
                print(f"    No SKILL.md found in {skills_dir}, skipping evolution")
                continue
        
        # Pass patterns if available and script supports it
        if patterns_path and script_name == 'generate_directive.py':
            cmd.extend(["--patterns", str(patterns_path)])
            
        result = subprocess.run(cmd, capture_output=True, text=True)
        
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
        # Skip empty or whitespace-only files — nothing to update
        if not content.strip():
            continue
        # Skip files without frontmatter (no name/description)
        if not content.strip().startswith('---'):
            continue
        content = re.sub(r'^updated:\s*\d{4}-\d{2}-\d{2}( \d{2}:\d{2})?\n', '', content, flags=re.MULTILINE)
        content = re.sub(r'^\s*last-evolution:\s*\d{4}-\d{2}-\d{2}( \d{2}:\d{2})?\n', '', content, flags=re.MULTILINE)
        
        # Add evolution metadata if not present
        if 'evolution-stats:' not in content:
            # Insert metadata inside the existing frontmatter block,
            # BEFORE the closing --- (not creating a new frontmatter).
            # Matches the last --- that closes frontmatter (followed by body text).
            content = re.sub(
                r'\n(---\s*\n(?!#))',
                f'\nmetadata:\n  evolution-stats:\n    total-experiments: {analysis["total_experiments"]}\n\\1',
                content, count=1
            )
        
        # Normalize: collapse 3+ consecutive newlines to max 2
        content = re.sub(r'\n{3,}', '\n\n', content)
        # Ensure exactly one trailing newline
        content = content.rstrip('\n') + '\n'
        
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
    print("\n[1/4] Analyzing experiment results...")
    analysis_path = run_analysis(root_dir, output_dir)
    
    with open(analysis_path, 'r') as f:
        analysis = json.load(f)
    
    print(f"  Total experiments: {analysis['total_experiments']}")
    print(f"  Targets tracked: {len(analysis['target_stats'])}")
    
    # Step 2: Meta-learning pattern analysis
    print("\n[2/4] Meta-learning from mementum + git history...")
    patterns_path = run_pattern_analysis(root_dir, output_dir)
    
    if patterns_path:
        with open(patterns_path, 'r') as f:
            patterns = json.load(f)
        learned = patterns.get('learned_patterns', {})
        print(f"  High-value patterns: {len(learned.get('high_value_patterns', []))}")
        print(f"  Effective techniques: {len(learned.get('effective_techniques', []))}")
        print(f"  Error mitigations: {len(learned.get('error_mitigation', []))}")
    else:
        print("  Pattern analysis skipped or failed")
    
    # Step 3: Evolve each skill
    print("\n[3/4] Evolving skills...")
    evolved = []
    for skill_name in skills_to_evolve:
        skill_info = SKILL_REGISTRY[skill_name]
        if generate_skill(skill_name, skill_info, analysis_path, root_dir, patterns_path):
            evolved.append(skill_name)
    
    # Step 4: Update metadata across all skills
    print("\n[4/4] Updating skill metadata...")
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
