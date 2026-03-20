#!/usr/bin/env python3
"""
Check benchmark scores against thresholds for CI integration.

Usage:
    python3 check_benchmark_scores.py --file results.json --min-overall 0.7 --min-per-key 0.6
"""

import argparse
import json
import sys
from pathlib import Path


def load_results(file_path: str) -> list | dict:
    """Load benchmark results from JSON file."""
    with open(file_path) as f:
        return json.load(f)


def extract_eight_keys_scores(results: list | dict) -> dict:
    """Extract Eight Keys scores from results.

    Handles multiple formats:
    - Full results dict with summary.eight-keys-breakdown
    - List of test results with grade.eight-keys (old format)
    - List of test results with string grade (new format - returns empty)
    """
    if isinstance(results, list):
        eight_keys_totals = {}
        count = 0

        for r in results:
            grade = r.get("grade", {})
            if isinstance(grade, dict):
                eight_keys = grade.get("eight-keys", {})
                for key, score in eight_keys.items():
                    if key != "overall" and isinstance(score, (int, float)):
                        eight_keys_totals[key] = eight_keys_totals.get(key, 0) + score
                count += 1

        if count == 0:
            return {}

        return {k: v / count for k, v in eight_keys_totals.items()}

    elif isinstance(results, dict):
        summary = results.get("summary", {})
        return summary.get("eight-keys-breakdown", {})

    return {}


def check_thresholds(
    eight_keys_scores: dict,
    overall_score: float,
    min_overall: float,
    min_per_key: float,
) -> tuple[bool, list[str]]:
    """Check if scores meet thresholds.

    Returns:
        Tuple of (passed, list of failure messages)
    """
    failures = []

    if overall_score < min_overall:
        failures.append(f"Overall score {overall_score:.1%} < {min_overall:.0%}")

    for key, score in eight_keys_scores.items():
        if score < min_per_key:
            failures.append(f"{key} score {score:.1%} < {min_per_key:.0%}")

    return len(failures) == 0, failures


def print_report(
    skill_name: str,
    overall_score: float,
    eight_keys_scores: dict,
    min_overall: float,
    min_per_key: float,
    failures: list[str],
):
    """Print formatted report."""
    print(f"\n## Benchmark Results: {skill_name}\n")
    print(f"### Overall Score: {overall_score:.1%}\n")

    print("### Eight Keys Breakdown:")
    for key in sorted(eight_keys_scores.keys()):
        score = eight_keys_scores[key]
        status = "✅" if score >= min_per_key else "❌"
        # Format key name nicely
        key_name = key.replace("-", " ").title()
        print(f"- {status} {key_name}: {score:.1%}")

    print()

    if failures:
        print("### ❌ Failed Checks:")
        for f in failures:
            print(f"- {f}")
    else:
        print("### ✅ All checks passed!")


def main():
    parser = argparse.ArgumentParser(
        description="Check benchmark scores against thresholds"
    )
    parser.add_argument("--file", required=True, help="Path to benchmark results JSON")
    parser.add_argument(
        "--min-overall",
        type=float,
        default=0.7,
        help="Minimum overall score (default: 0.7)",
    )
    parser.add_argument(
        "--min-per-key",
        type=float,
        default=0.6,
        help="Minimum per-key score (default: 0.6)",
    )
    parser.add_argument("--skill", default="unknown", help="Skill name for reporting")
    parser.add_argument(
        "--json-output", action="store_true", help="Output as JSON for CI"
    )

    args = parser.parse_args()

    # Load results
    try:
        results = load_results(args.file)
    except Exception as e:
        print(f"Error loading results: {e}", file=sys.stderr)
        sys.exit(1)

    # Extract scores
    eight_keys_scores = extract_eight_keys_scores(results)

    # Calculate overall score
    if isinstance(results, list):
        total_tests = len(results)
        passed_tests = sum(
            1 for r in results if r.get("grade", {}).get("passed", False)
        )
        overall_score = passed_tests / total_tests if total_tests > 0 else 0
    else:
        summary = results.get("summary", {})
        raw_score = summary.get("overall-score", summary.get("average_score", 0))
        # Handle both percentage (0-100) and decimal (0-1) formats
        overall_score = raw_score / 100 if raw_score > 1 else raw_score

    # Check thresholds
    passed, failures = check_thresholds(
        eight_keys_scores, overall_score, args.min_overall, args.min_per_key
    )

    # Output
    if args.json_output:
        output = {
            "skill": args.skill,
            "overall_score": overall_score,
            "eight_keys_scores": eight_keys_scores,
            "passed": passed,
            "failures": failures,
        }
        print(json.dumps(output, indent=2))
    else:
        print_report(
            args.skill,
            overall_score,
            eight_keys_scores,
            args.min_overall,
            args.min_per_key,
            failures,
        )

    # Exit with appropriate code
    sys.exit(0 if passed else 1)


if __name__ == "__main__":
    main()
