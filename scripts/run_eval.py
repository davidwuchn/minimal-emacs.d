#!/usr/bin/env python3
"""
Skill Evaluation Benchmark Runner

Usage:
    python scripts/run_eval.py --skill <skill-name> --eval <eval-file>
    python scripts/run_eval.py --skill <skill-name> --suite <suite-file>
    python scripts/run_eval.py --skill <skill-name> --baseline <baseline-skill> --eval <eval-file>

Output:
    Creates outputs/ directory with skill outputs
    Creates grading.json with assertion results
    Creates benchmark.json with aggregated statistics
"""

import argparse
import json
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Any


def load_eval(eval_path: str) -> dict:
    """Load eval definition from JSON file."""
    with open(eval_path, "r") as f:
        return json.load(f)


def load_suite(suite_path: str) -> dict:
    """Load suite definition from JSON file."""
    with open(suite_path, "r") as f:
        return json.load(f)


def run_assertion(assertion: dict, output_dir: Path) -> dict:
    """Run a single assertion and return result."""
    result = {
        "name": assertion["name"],
        "type": assertion["type"],
        "passed": False,
        "evidence": "",
    }

    if assertion["type"] == "check":
        # Check if expected strings are in output
        expected = assertion.get("expected", [])
        output_files = list(output_dir.glob("*"))

        if not output_files:
            result["evidence"] = "No output files found"
            return result

        all_content = ""
        for f in output_files:
            if f.is_file():
                all_content += f.read_text(errors="ignore") + "\n"

        missing = [e for e in expected if e not in all_content]
        if not missing:
            result["passed"] = True
            result["evidence"] = f"All expected elements found: {expected}"
        else:
            result["evidence"] = f"Missing elements: {missing}"

    elif assertion["type"] == "script":
        # Run shell command
        command = assertion.get("command", "")
        try:
            proc = subprocess.run(
                command, shell=True, cwd=output_dir, capture_output=True, timeout=60
            )
            result["passed"] = proc.returncode == 0
            result["evidence"] = f"Exit code: {proc.returncode}"
            if proc.stderr:
                result["evidence"] += f", stderr: {proc.stderr.decode()[:200]}"
        except subprocess.TimeoutExpired:
            result["evidence"] = "Command timed out"
        except Exception as e:
            result["evidence"] = f"Error: {str(e)}"

    elif assertion["type"] == "llm":
        # LLM assertions require manual grading or separate agent
        result["evidence"] = "Requires LLM grading via 'grader' agent"

    return result


def run_eval(eval_def: dict, output_dir: Path) -> dict:
    """Run all assertions for an eval."""
    results = []
    for assertion in eval_def.get("assertions", []):
        result = run_assertion(assertion, output_dir)
        results.append(result)

    passed = sum(1 for r in results if r["passed"])
    total = len(results)

    return {
        "eval_id": eval_def.get("id"),
        "eval_name": eval_def.get("name"),
        "results": results,
        "summary": {
            "total": total,
            "passed": passed,
            "failed": total - passed,
            "pass_rate": round(passed / total, 2) if total > 0 else 0,
        },
    }


def main():
    parser = argparse.ArgumentParser(description="Skill Evaluation Benchmark Runner")
    parser.add_argument("--skill", required=True, help="Skill name to evaluate")
    parser.add_argument("--eval", help="Path to eval JSON file")
    parser.add_argument("--suite", help="Path to suite JSON file")
    parser.add_argument("--baseline", help="Baseline skill for comparison")
    parser.add_argument("--output-dir", default="outputs", help="Output directory")
    parser.add_argument(
        "--iterations", type=int, default=1, help="Number of iterations"
    )

    args = parser.parse_args()

    # Determine evals to run
    evals = []
    if args.eval:
        evals.append(load_eval(args.eval))
    elif args.suite:
        suite = load_suite(args.suite)
        suite_dir = Path(args.suite).parent
        for eval_name in suite.get("evals", []):
            eval_path = suite_dir.parent / eval_name
            if eval_path.exists():
                evals.append(load_eval(str(eval_path)))

    if not evals:
        print("Error: No evals to run. Specify --eval or --suite")
        sys.exit(1)

    # Create output directory
    output_base = Path(args.output_dir)
    output_base.mkdir(parents=True, exist_ok=True)

    # Run benchmark
    all_results = []
    for eval_def in evals:
        print(f"Running eval: {eval_def.get('name')}")
        eval_output = output_base / eval_def.get("id", "unknown")
        eval_output.mkdir(parents=True, exist_ok=True)

        result = run_eval(eval_def, eval_output)
        all_results.append(result)

        # Write grading result
        grading_path = eval_output / "grading.json"
        with open(grading_path, "w") as f:
            json.dump(result, f, indent=2)
        print(
            f"  Results: {result['summary']['passed']}/{result['summary']['total']} passed"
        )

    # Write benchmark summary
    benchmark = {
        "skill": args.skill,
        "baseline": args.baseline,
        "timestamp": datetime.now().isoformat(),
        "evals": all_results,
        "aggregate": {
            "total_evals": len(evals),
            "total_assertions": sum(r["summary"]["total"] for r in all_results),
            "total_passed": sum(r["summary"]["passed"] for r in all_results),
            "overall_pass_rate": round(
                sum(r["summary"]["passed"] for r in all_results)
                / max(sum(r["summary"]["total"] for r in all_results), 1),
                2,
            ),
        },
    }

    benchmark_path = output_base / "benchmark.json"
    with open(benchmark_path, "w") as f:
        json.dump(benchmark, f, indent=2)

    print(f"\nBenchmark complete: {benchmark_path}")
    print(f"Overall pass rate: {benchmark['aggregate']['overall_pass_rate']}")


if __name__ == "__main__":
    main()
