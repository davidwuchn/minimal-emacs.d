#!/usr/bin/env python3
"""
Evaluation Runner for Claude Code Skills.

Runs skill evaluations with/without skill access and captures metrics.
"""

import json
import os
import sys
import time
import subprocess
import argparse
from pathlib import Path
from typing import Dict, List, Optional, Any
from dataclasses import dataclass, asdict
from datetime import datetime
import statistics


@dataclass
class TimingMetrics:
    """Metrics captured during eval run."""
    start_time: float
    end_time: float
    duration_ms: int
    total_tokens: int
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "start_time": self.start_time,
            "end_time": self.end_time,
            "duration_ms": self.duration_ms,
            "total_duration_seconds": round(self.duration_ms / 1000, 1),
            "total_tokens": self.total_tokens
        }


@dataclass
class EvalResult:
    """Result of a single eval run."""
    eval_id: int
    eval_name: str
    prompt: str
    skill_path: Optional[str]
    baseline: bool
    outputs_dir: str
    timing: TimingMetrics
    exit_code: int
    success: bool


def run_subagent(
    prompt: str,
    skill_path: Optional[str] = None,
    output_dir: str = "outputs",
    timeout: int = 300
) -> tuple[int, TimingMetrics]:
    """
    Run a subagent with optional skill loaded.
    
    Args:
        prompt: The user prompt to send
        skill_path: Path to skill directory (None for baseline)
        output_dir: Where to save outputs
        timeout: Maximum seconds to wait
        
    Returns:
        (exit_code, timing_metrics)
    """
    start_time = time.time()
    
    # Build command
    cmd = ["claude", "--output-dir", output_dir]
    
    if skill_path:
        cmd.extend(["--skill", skill_path])
    
    cmd.extend(["--prompt", prompt])
    
    # Run subprocess
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout
        )
        
        end_time = time.time()
        duration_ms = int((end_time - start_time) * 1000)
        
        # Parse token count from stderr/output if available
        total_tokens = 0
        # TODO: Parse actual token usage from Claude output
        
        timing = TimingMetrics(
            start_time=start_time,
            end_time=end_time,
            duration_ms=duration_ms,
            total_tokens=total_tokens
        )
        
        return result.returncode, timing
        
    except subprocess.TimeoutExpired:
        end_time = time.time()
        duration_ms = int((end_time - start_time) * 1000)
        
        timing = TimingMetrics(
            start_time=start_time,
            end_time=end_time,
            duration_ms=duration_ms,
            total_tokens=0
        )
        
        return -1, timing


def run_single_eval(
    eval_config: Dict[str, Any],
    skill_path: Optional[str],
    output_base_dir: str,
    iteration: int
) -> EvalResult:
    """
    Run a single eval configuration.
    
    Args:
        eval_config: The eval definition from evals.json
        skill_path: Path to skill (None for baseline)
        output_base_dir: Base directory for all outputs
        iteration: Current iteration number
        
    Returns:
        EvalResult with all metrics
    """
    eval_id = eval_config["id"]
    eval_name = eval_config.get("name", f"eval-{eval_id}")
    prompt = eval_config["prompt"]
    
    # Determine output directory
    config_name = "with_skill" if skill_path else "baseline"
    output_dir = os.path.join(
        output_base_dir,
        f"iteration-{iteration}",
        f"eval-{eval_id}",
        config_name
    )
    
    os.makedirs(output_dir, exist_ok=True)
    
    # Run the eval
    print(f"  Running {eval_name} ({config_name})...", end=" ", flush=True)
    
    exit_code, timing = run_subagent(
        prompt=prompt,
        skill_path=skill_path,
        output_dir=output_dir
    )
    
    success = exit_code == 0
    print(f"{'✓' if success else '✗'} ({timing.duration_ms}ms)")
    
    # Save timing info
    timing_file = os.path.join(output_dir, "timing.json")
    with open(timing_file, 'w') as f:
        json.dump(timing.to_dict(), f, indent=2)
    
    return EvalResult(
        eval_id=eval_id,
        eval_name=eval_name,
        prompt=prompt,
        skill_path=skill_path,
        baseline=skill_path is None,
        outputs_dir=output_dir,
        timing=timing,
        exit_code=exit_code,
        success=success
    )


def run_eval_set(
    evals: List[Dict[str, Any]],
    skill_path: Optional[str],
    output_base_dir: str,
    iteration: int
) -> List[EvalResult]:
    """Run all evals for a given configuration."""
    results = []
    
    for eval_config in evals:
        result = run_single_eval(
            eval_config=eval_config,
            skill_path=skill_path,
            output_base_dir=output_base_dir,
            iteration=iteration
        )
        results.append(result)
    
    return results


def aggregate_results(
    with_skill_results: List[EvalResult],
    baseline_results: List[EvalResult],
    output_dir: str
) -> Dict[str, Any]:
    """
    Aggregate results into benchmark format.
    
    Args:
        with_skill_results: Results with skill loaded
        baseline_results: Results without skill
        output_dir: Where to save benchmark.json
        
    Returns:
        Benchmark data structure
    """
    def compute_stats(results: List[EvalResult]) -> Dict[str, Any]:
        durations = [r.timing.duration_ms for r in results]
        tokens = [r.timing.total_tokens for r in results]
        passed = sum(1 for r in results if r.success)
        
        return {
            "count": len(results),
            "passed": passed,
            "failed": len(results) - passed,
            "pass_rate": round(passed / len(results), 2) if results else 0,
            "duration_ms": {
                "mean": round(statistics.mean(durations), 1) if durations else 0,
                "stddev": round(statistics.stdev(durations), 1) if len(durations) > 1 else 0,
                "min": min(durations) if durations else 0,
                "max": max(durations) if durations else 0
            },
            "tokens": {
                "mean": round(statistics.mean(tokens), 0) if tokens else 0,
                "stddev": round(statistics.stdev(tokens), 0) if len(tokens) > 1 else 0
            }
        }
    
    with_skill_stats = compute_stats(with_skill_results)
    baseline_stats = compute_stats(baseline_results)
    
    # Per-eval breakdown
    evals_breakdown = []
    for ws, bl in zip(with_skill_results, baseline_results):
        evals_breakdown.append({
            "eval_id": ws.eval_id,
            "eval_name": ws.eval_name,
            "with_skill": {
                "passed": ws.success,
                "duration_ms": ws.timing.duration_ms,
                "tokens": ws.timing.total_tokens
            },
            "baseline": {
                "passed": bl.success,
                "duration_ms": bl.timing.duration_ms,
                "tokens": bl.timing.total_tokens
            }
        })
    
    benchmark = {
        "timestamp": datetime.now().isoformat(),
        "summary": {
            "with_skill": with_skill_stats,
            "baseline": baseline_stats,
            "delta": {
                "pass_rate": round(
                    with_skill_stats["pass_rate"] - baseline_stats["pass_rate"], 2
                ),
                "duration_ms_mean": round(
                    with_skill_stats["duration_ms"]["mean"] - baseline_stats["duration_ms"]["mean"], 1
                )
            }
        },
        "evals": evals_breakdown
    }
    
    # Save benchmark
    benchmark_path = os.path.join(output_dir, "benchmark.json")
    with open(benchmark_path, 'w') as f:
        json.dump(benchmark, f, indent=2)
    
    print(f"\nBenchmark saved to: {benchmark_path}")
    print(f"Pass rate: {with_skill_stats['pass_rate']:.0%} (skill) vs {baseline_stats['pass_rate']:.0%} (baseline)")
    print(f"Delta: {benchmark['summary']['delta']['pass_rate']:+.0%}")
    
    return benchmark


def main():
    parser = argparse.ArgumentParser(description="Run skill evaluations")
    parser.add_argument("--skill", "-s", help="Path to skill directory")
    parser.add_argument("--evals", "-e", required=True, help="Path to evals.json")
    parser.add_argument("--output", "-o", default="./eval-results", help="Output directory")
    parser.add_argument("--iteration", "-i", type=int, default=1, help="Iteration number")
    parser.add_argument("--baseline-only", action="store_true", help="Run only baseline")
    parser.add_argument("--skill-only", action="store_true", help="Run only with skill")
    
    args = parser.parse_args()
    
    # Load evals
    with open(args.evals, 'r') as f:
        evals_data = json.load(f)
    
    evals = evals_data.get("evals", [])
    print(f"Loaded {len(evals)} evals from {args.skill or 'template'}")
    
    # Create output directory
    os.makedirs(args.output, exist_ok=True)
    
    # Run evals
    with_skill_results = []
    baseline_results = []
    
    if not args.baseline_only:
        print("\n=== Running WITH skill ===")
        with_skill_results = run_eval_set(
            evals=evals,
            skill_path=args.skill,
            output_base_dir=args.output,
            iteration=args.iteration
        )
    
    if not args.skill_only:
        print("\n=== Running BASELINE (no skill) ===")
        baseline_results = run_eval_set(
            evals=evals,
            skill_path=None,
            output_base_dir=args.output,
            iteration=args.iteration
        )
    
    # Aggregate results
    if with_skill_results and baseline_results:
        print("\n=== Aggregating Results ===")
        aggregate_results(
            with_skill_results=with_skill_results,
            baseline_results=baseline_results,
            output_dir=os.path.join(args.output, f"iteration-{args.iteration}")
        )
    
    print("\nDone!")


if __name__ == "__main__":
    main()
