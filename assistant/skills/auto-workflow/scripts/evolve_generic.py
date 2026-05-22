#!/usr/bin/env python3
"""Generic self-evolve script for any skill without a custom evolve script.

Reads the skill's experiment performance from results.tsv and appends
a data-driven insight to the SKILL.md footer.  Skills reference this
by setting `evolve-script: evolve_generic.py` in their frontmatter.

The evolve_skills.py runner discovers this script from
assistant/skills/scripts/  (shared scripts directory).
"""

import argparse
import csv
import os
import re
from pathlib import Path
from datetime import datetime


def load_tsv_results(root):
    """Load results.tsv and return list of dicts."""
    tsv_path = Path(root) / "var" / "tmp" / "experiments"
    if not tsv_path.is_dir():
        return []
    # Find the most recent results.tsv
    latest = None
    for d in sorted(tsv_path.iterdir(), reverse=True):
        tsv = d / "results.tsv"
        if tsv.exists():
            latest = tsv
            break
    if not latest:
        return []
    rows = []
    with open(latest) as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            rows.append(row)
    return rows


def skill_performance(skill_name, rows):
    """Compute keep rate and avg score delta for SKILL_NAME."""
    total = 0
    kept = 0
    score_deltas = []
    for r in rows:
        # Match by skill name in strategy or research_strategy field
        strategy = r.get("strategy", "")
        research = r.get("research_strategy", "")
        if skill_name in strategy or skill_name in research:
            total += 1
            if r.get("decision", "").strip() == "kept":
                kept += 1
            try:
                before = float(r.get("score_before", "0.4") or "0.4")
                after = float(r.get("score_after", before) or str(before))
                score_deltas.append(after - before)
            except (ValueError, TypeError):
                pass
    keep_rate = (kept / total) if total > 0 else 0.0
    avg_delta = sum(score_deltas) / len(score_deltas) if score_deltas else 0.0
    return keep_rate, avg_delta, total, kept


def evolve_skill(skill_file, skill_name, rows):
    """Write a performance-driven insight to a SEPARATE evolution file.
    Does NOT modify SKILL.md — avoids perpetual git merge conflicts
    between daemon instances with different experiment data."""
    keep_rate, avg_delta, total, kept = skill_performance(skill_name, rows)

    # Write to var/tmp/skill-evolution/{skill}.md (not SKILL.md)
    root = Path(skill_file).parent.parent.parent.parent  # skill/SKILL.md → repo root
    out_dir = root / "var" / "tmp" / "skill-evolution"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_file = out_dir / f"{skill_name}.md"

    timestamp = datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
    if total == 0:
        insight = f"*Auto-evolved: No experiment data yet ({timestamp}). Collecting baseline.*"
    elif keep_rate >= 0.20:
        insight = (f"*Auto-evolved: Keep rate {keep_rate:.0%} ({kept}/{total}), "
                   f"avg delta {avg_delta:+.3f} ({timestamp}). Reinforcing current approach.*")
    elif keep_rate >= 0.10:
        insight = (f"*Auto-evolved: Keep rate {keep_rate:.0%} ({kept}/{total}), "
                   f"avg delta {avg_delta:+.3f} ({timestamp}). Moderate — consider small adjustments.*")
    else:
        insight = (f"*Auto-evolved: Keep rate {keep_rate:.0%} ({kept}/{total}), "
                   f"avg delta {avg_delta:+.3f} ({timestamp}). Low — the current approach needs revision.*")

    with open(out_file, 'w') as f:
        f.write(f"# {skill_name} Evolution\n\n{insight}\n")

    print(f"    ✓ {skill_name}: keep={keep_rate:.0%} delta={avg_delta:+.3f} ({total} exp) → {out_file}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--skill-file", required=True)
    parser.add_argument("--root", default=".")
    parser.add_argument("--analysis", default=None)
    parser.add_argument("--output-dir", default=None)
    args = parser.parse_args()
    
    skill_file = Path(args.skill_file)
    skill_name = skill_file.parent.name if skill_file.parent else "unknown"
    root = Path(args.root).resolve()
    
    rows = load_tsv_results(root)
    evolve_skill(skill_file, skill_name, rows)


if __name__ == "__main__":
    main()
