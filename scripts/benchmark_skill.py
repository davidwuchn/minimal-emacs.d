#!/usr/bin/env python3
"""
Skill Benchmark Runner

Benchmarks skills by:
1. Loading skill content
2. Running test prompts through AI
3. Grading outputs against expected behaviors

Usage:
    python scripts/benchmark_skill.py --skill clojure-expert --tests benchmarks/skill-tests/clojure-expert.json
    python scripts/benchmark_skill.py --all-skills
    python scripts/benchmark_skill.py --grade-only --results outputs/benchmark.json
"""

import argparse
import json
import os
import sys
from datetime import datetime
from pathlib import Path
from typing import Any


def load_skill(skill_path: str) -> dict:
    """Load skill file and parse frontmatter."""
    with open(skill_path, "r") as f:
        content = f.read()

    frontmatter = {}
    body = content

    if content.startswith("---"):
        parts = content.split("---", 2)
        if len(parts) >= 3:
            fm_text = parts[1].strip()
            body = parts[2].strip()

            for line in fm_text.split("\n"):
                if ":" in line:
                    key, value = line.split(":", 1)
                    frontmatter[key.strip()] = value.strip()

    return {"frontmatter": frontmatter, "body": body, "raw": content}


def load_tests(tests_path: str) -> dict:
    """Load test cases from JSON file."""
    with open(tests_path, "r") as f:
        return json.load(f)


def check_behavior(output: str, behavior: str) -> bool:
    """Check if output exhibits expected behavior."""
    behavior_lower = behavior.lower()
    output_lower = output.lower()

    prefixes = [
        "mentions ",
        "uses ",
        "shows ",
        "handles ",
        "explains ",
        "suggests ",
        "avoids ",
        "code is ",
    ]

    matched_prefix = None
    for prefix in prefixes:
        if behavior_lower.startswith(prefix):
            matched_prefix = prefix
            keyword = behavior_lower[len(prefix) :]
            break

    if matched_prefix:
        if "e.g." in keyword:
            import re

            match = re.search(r"\(e\.g\.\s*([^)]+)\)", keyword)
            if match:
                examples = match.group(1)
                for ex in examples.split(","):
                    ex = ex.strip()
                    if ex.startswith("or "):
                        ex = ex[3:]
                    if ex in output_lower:
                        return True
                keyword = keyword[: keyword.find("(e.g.")].strip()
                if keyword and keyword in output_lower:
                    return True
                return False

        items = []
        if ", " in keyword or " or " in keyword or "/" in keyword:
            parts = (
                keyword.replace(", or ", ", ")
                .replace(" or ", ", ")
                .replace("/", " or ")
                .split(" or ")
            )
            items = [p.strip("(),.") for p in parts]

        if items:
            for item in items:
                if item in output_lower:
                    return True
            key_terms = [
                t
                for t in keyword.split()
                if len(t) > 3 and t not in ["when", "use", "with"]
            ]
            if any(t in output_lower for t in key_terms):
                return True
            return False

        key_terms = [t for t in keyword.split() if len(t) > 3]
        if key_terms and any(t in output_lower for t in key_terms):
            return True

        return keyword.strip("(),.") in output_lower

    key_terms = [t for t in behavior_lower.split() if len(t) > 3]
    if key_terms and any(t in output_lower for t in key_terms):
        return True

    return behavior_lower in output_lower


def check_forbidden(output: str, forbidden: str) -> bool:
    """Check if output contains forbidden behavior. Returns True if VIOLATED."""
    forbidden_lower = forbidden.lower()
    output_lower = output.lower()

    if "ignores" in forbidden_lower:
        if "violation" in forbidden_lower:
            return False
        if "request" in forbidden_lower:
            return False
        if "potential" in forbidden_lower:
            return False
        if "anti-pattern" in forbidden_lower:
            return False
        if "security implication" in forbidden_lower:
            return False
        if "good practice" in forbidden_lower:
            return False

    if forbidden_lower.startswith("ignores "):
        keyword = forbidden_lower[8:].strip()
        if "nil" in keyword:
            return "nil" not in output_lower
        if "empty" in keyword:
            return "empty" not in output_lower and "[]" not in output_lower
        return keyword not in output_lower

    if forbidden_lower.startswith("writes "):
        return forbidden_lower[7:] in output_lower

    if forbidden_lower.startswith("uses "):
        return forbidden_lower[5:] in output_lower

    if forbidden_lower.startswith("says "):
        phrase = forbidden_lower[5:].strip("'\"")
        return phrase in output_lower

    if forbidden_lower.startswith("adds "):
        return forbidden_lower[5:] in output_lower

    return forbidden_lower in output_lower


def grade_test_case(output: str, test_case: dict) -> dict:
    """Grade a single test case against output."""
    results = {
        "test_id": test_case["id"],
        "test_name": test_case["name"],
        "expected_passed": [],
        "expected_failed": [],
        "forbidden_passed": [],
        "forbidden_violated": [],
        "score": 0,
        "max_score": 0,
        "grade": "F",
    }

    expected = test_case.get("expected_behaviors", [])
    forbidden = test_case.get("forbidden_behaviors", [])

    for behavior in expected:
        results["max_score"] += 10
        if check_behavior(output, behavior):
            results["expected_passed"].append(behavior)
            results["score"] += 10
        else:
            results["expected_failed"].append(behavior)

    for behavior in forbidden:
        results["max_score"] += 10
        if not check_forbidden(output, behavior):
            results["forbidden_passed"].append(behavior)
            results["score"] += 10
        else:
            results["forbidden_violated"].append(behavior)

    if results["max_score"] > 0:
        pct = results["score"] / results["max_score"] * 100
        if pct >= 90:
            results["grade"] = "A"
        elif pct >= 80:
            results["grade"] = "B"
        elif pct >= 70:
            results["grade"] = "C"
        elif pct >= 60:
            results["grade"] = "D"
        else:
            results["grade"] = "F"

    return results


def generate_prompt_for_test(skill: dict, test_case: dict) -> str:
    """Generate the full prompt including skill context."""
    prompt = f"""{skill["raw"]}

---

USER REQUEST: {test_case.get("prompt", test_case.get("input_text", "No prompt"))}

Respond according to your skill instructions above."""
    return prompt


def run_benchmark(
    skill_name: str, tests_path: str, output_dir: str, skill_dir: str | None = None
) -> dict | None:
    """Run benchmark for a single skill."""
    if skill_dir:
        skill_path = Path(skill_dir) / skill_name / "SKILL.md"
    else:
        skill_path = Path("assistant/skills") / skill_name / "SKILL.md"

    if not skill_path.exists():
        print(f"Error: Skill not found at {skill_path}")
        return None

    skill = load_skill(str(skill_path))
    tests = load_tests(tests_path)

    print(f"\n{'=' * 50}")
    print(
        f"Benchmarking: {skill_name} v{skill['frontmatter'].get('version', 'unknown')}"
    )
    print(f"{'=' * 50}")

    results = {
        "skill": skill_name,
        "version": skill["frontmatter"].get("version", "unknown"),
        "timestamp": datetime.now().isoformat(),
        "test_file": tests_path,
        "test_results": [],
        "summary": {
            "total_tests": 0,
            "passed": 0,
            "failed": 0,
            "average_score": 0,
            "overall_grade": "F",
        },
    }

    total_score = 0
    total_max = 0
    grades = []

    for test_case in tests.get("test_cases", []):
        print(f"\nTest: {test_case['id']} - {test_case['name']}")

        prompt = generate_prompt_for_test(skill, test_case)

        prompt_file = Path(output_dir) / f"prompt_{test_case['id']}.txt"
        prompt_file.parent.mkdir(parents=True, exist_ok=True)
        prompt_file.write_text(prompt)

        print(f"  Prompt written to: {prompt_file}")
        print(
            f"  Run this through your AI and save output to: outputs/output_{test_case['id']}.txt"
        )

        output_file = Path(output_dir) / f"output_{test_case['id']}.txt"
        if output_file.exists():
            output = output_file.read_text()
            test_result = grade_test_case(output, test_case)
            results["test_results"].append(test_result)

            total_score += test_result["score"]
            total_max += test_result["max_score"]
            grades.append(test_result["grade"])

            print(
                f"  Grade: {test_result['grade']} ({test_result['score']}/{test_result['max_score']})"
            )
            if test_result["expected_failed"]:
                print(f"  Missing behaviors: {test_result['expected_failed']}")
            if test_result["forbidden_violated"]:
                print(f"  Forbidden behaviors: {test_result['forbidden_violated']}")
        else:
            print(f"  No output file found. Skipping grading.")

    results["summary"]["total_tests"] = len(tests.get("test_cases", []))
    results["summary"]["graded"] = len(results["test_results"])

    if total_max > 0:
        results["summary"]["average_score"] = round(total_score / total_max * 100, 1)

        avg_pct = total_score / total_max * 100
        if avg_pct >= 90:
            results["summary"]["overall_grade"] = "A"
        elif avg_pct >= 80:
            results["summary"]["overall_grade"] = "B"
        elif avg_pct >= 70:
            results["summary"]["overall_grade"] = "C"
        elif avg_pct >= 60:
            results["summary"]["overall_grade"] = "D"
        else:
            results["summary"]["overall_grade"] = "F"

    benchmark_file = Path(output_dir) / "benchmark.json"
    with open(benchmark_file, "w") as f:
        json.dump(results, f, indent=2)

    print(f"\n{'=' * 50}")
    print(f"Overall Grade: {results['summary']['overall_grade']}")
    print(f"Average Score: {results['summary']['average_score']}%")
    print(f"Results saved to: {benchmark_file}")

    return results


def main():
    parser = argparse.ArgumentParser(description="Skill Benchmark Runner")
    parser.add_argument("--skill", help="Skill name to benchmark")
    parser.add_argument("--tests", help="Path to test cases JSON")
    parser.add_argument("--output-dir", default="outputs", help="Output directory")
    parser.add_argument(
        "--skill-dir", help="Skills directory (default: assistant/skills)"
    )
    parser.add_argument("--all-skills", action="store_true", help="Run all skill tests")

    args = parser.parse_args()

    if args.all_skills:
        test_dir = Path("benchmarks/skill-tests")
        if test_dir.exists():
            for test_file in test_dir.glob("*.json"):
                skill_name = test_file.stem
                run_benchmark(
                    skill_name, str(test_file), args.output_dir, args.skill_dir
                )
        else:
            print(f"Test directory not found: {test_dir}")
            sys.exit(1)
    elif args.skill and args.tests:
        run_benchmark(args.skill, args.tests, args.output_dir, args.skill_dir)
    else:
        print("Error: Specify --skill and --tests, or --all-skills")
        sys.exit(1)


if __name__ == "__main__":
    main()
