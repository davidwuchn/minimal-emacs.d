#!/usr/bin/env python3
"""
Package a skill into a .skill file for distribution.

A .skill file is a ZIP archive containing the skill directory contents.
"""

import os
import sys
import json
import zipfile
import argparse
from pathlib import Path
from datetime import datetime


def validate_skill(skill_dir: str) -> tuple[bool, list[str]]:
    """
    Validate skill structure before packaging.
    
    Returns:
        (is_valid, list of issues)
    """
    issues = []
    skill_path = Path(skill_dir)
    
    # Check SKILL.md exists
    skill_md = skill_path / "SKILL.md"
    if not skill_md.exists():
        issues.append("Missing SKILL.md")
    else:
        # Validate frontmatter
        content = skill_md.read_text()
        if "---" not in content:
            issues.append("SKILL.md missing YAML frontmatter")
        elif "name:" not in content or "description:" not in content:
            issues.append("SKILL.md frontmatter missing required fields (name, description)")
    
    # Check for evals
    evals_json = skill_path / "evals" / "evals.json"
    if evals_json.exists():
        try:
            with open(evals_json) as f:
                evals = json.load(f)
            if not evals.get("evals"):
                issues.append("evals.json exists but contains no evals")
        except json.JSONDecodeError:
            issues.append("evals.json is invalid JSON")
    
    # Check for suspicious files
    suspicious = [".env", ".git", "__pycache__", ".DS_Store", "*.pyc"]
    for pattern in suspicious:
        matches = list(skill_path.rglob(pattern))
        if matches:
            issues.append(f"Found suspicious files: {pattern} ({len(matches)} matches)")
    
    return len(issues) == 0, issues


def package_skill(skill_dir: str, output_dir: str = ".") -> str:
    """
    Package skill into .skill file.
    
    Args:
        skill_dir: Path to skill directory
        output_dir: Where to save the .skill file
        
    Returns:
        Path to created .skill file
    """
    skill_path = Path(skill_dir)
    skill_name = skill_path.name
    
    # Determine version
    version = "1.0.0"
    skill_md = skill_path / "SKILL.md"
    if skill_md.exists():
        content = skill_md.read_text()
        if "version:" in content:
            # Extract version from frontmatter
            for line in content.split("\n"):
                if line.strip().startswith("version:"):
                    version = line.split(":", 1)[1].strip()
                    break
    
    # Create output filename
    timestamp = datetime.now().strftime("%Y%m%d")
    output_filename = f"{skill_name}-v{version}-{timestamp}.skill"
    output_path = Path(output_dir) / output_filename
    
    # Create ZIP archive
    with zipfile.ZipFile(output_path, 'w', zipfile.ZIP_DEFLATED) as zf:
        for file_path in skill_path.rglob("*"):
            if file_path.is_file():
                # Skip unwanted files
                if any(part.startswith('.') for part in file_path.relative_to(skill_path).parts):
                    continue
                if file_path.suffix in ['.pyc', '.pyo']:
                    continue
                if '__pycache__' in str(file_path):
                    continue
                
                arcname = file_path.relative_to(skill_path)
                zf.write(file_path, arcname)
                print(f"  Added: {arcname}")
    
    return str(output_path)


def create_metadata(skill_dir: str, output_path: str) -> dict:
    """Create package metadata."""
    skill_path = Path(skill_dir)
    
    # Read skill info
    skill_md = skill_path / "SKILL.md"
    name = skill_path.name
    description = ""
    
    if skill_md.exists():
        content = skill_md.read_text()
        # Extract description from frontmatter
        in_frontmatter = False
        for line in content.split("\n"):
            if line.strip() == "---":
                in_frontmatter = not in_frontmatter
                continue
            if in_frontmatter and line.strip().startswith("description:"):
                description = line.split(":", 1)[1].strip()
                break
    
    # Count files
    file_count = sum(1 for f in skill_path.rglob("*") if f.is_file())
    
    metadata = {
        "name": name,
        "description": description,
        "packaged_at": datetime.now().isoformat(),
        "file_count": file_count,
        "package_size_bytes": Path(output_path).stat().st_size
    }
    
    return metadata


def main():
    parser = argparse.ArgumentParser(description="Package a skill for distribution")
    parser.add_argument("skill_dir", help="Path to skill directory")
    parser.add_argument("-o", "--output", default=".", help="Output directory")
    parser.add_argument("--no-validate", action="store_true", help="Skip validation")
    parser.add_argument("--metadata", action="store_true", help="Create metadata file")
    
    args = parser.parse_args()
    
    # Validate
    if not args.no_validate:
        print(f"Validating {args.skill_dir}...")
        is_valid, issues = validate_skill(args.skill_dir)
        
        if issues:
            print("Issues found:")
            for issue in issues:
                print(f"  ⚠ {issue}")
        
        if not is_valid:
            print("\nValidation failed. Use --no-validate to package anyway.")
            sys.exit(1)
        
        print("✓ Validation passed\n")
    
    # Package
    print(f"Packaging {args.skill_dir}...")
    output_path = package_skill(args.skill_dir, args.output)
    
    print(f"\n✓ Created: {output_path}")
    
    # Create metadata
    if args.metadata:
        metadata = create_metadata(args.skill_dir, output_path)
        metadata_path = Path(output_path).with_suffix('.json')
        with open(metadata_path, 'w') as f:
            json.dump(metadata, f, indent=2)
        print(f"✓ Metadata: {metadata_path}")
    
    # Print summary
    size_kb = Path(output_path).stat().st_size / 1024
    print(f"\nPackage size: {size_kb:.1f} KB")
    print(f"Install with: claude --skill {output_path}")


if __name__ == "__main__":
    main()
