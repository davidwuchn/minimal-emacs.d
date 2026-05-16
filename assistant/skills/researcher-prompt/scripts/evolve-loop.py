#!/usr/bin/env python3
"""AutoTTS-style Strategy Evolution Loop

After each pipeline run:
1. Load latest research trace
2. Evaluate all strategies against it (offline, no LLM calls)
3. Pick best strategy
4. Update researcher prompt
5. Save evolved strategy for next run
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
TRACE_DIR = ROOT / "var/tmp/research-traces"
STRATEGY_DIR = ROOT / "assistant/skills/researcher-prompt/strategies"
RESULTS_FILE = ROOT / "var/tmp/strategy-evaluation-results.json"
GUIDANCE_FILE = ROOT / "var/tmp/researcher-strategy-guidance.json"
SKILL_FILE = ROOT / "assistant/skills/researcher-prompt/SKILL.md"

def run_controller_dsl():
    """Ensure default strategies exist."""
    import subprocess
    script = ROOT / "assistant/skills/researcher-prompt/scripts/controller-dsl.py"
    subprocess.run([sys.executable, str(script)], check=True)

def run_evaluator(session_id=None):
    """Run offline strategy evaluation."""
    import subprocess
    script = ROOT / "assistant/skills/researcher-prompt/scripts/evaluate-strategies.py"
    args = [sys.executable, str(script)]
    if session_id:
        args.append(session_id)
    result = subprocess.run(args, capture_output=True, text=True)
    print(result.stdout)
    if result.stderr:
        print(result.stderr, file=sys.stderr)

def load_evaluation_results():
    """Load strategy evaluation results."""
    if not RESULTS_FILE.exists():
        return None
    with open(RESULTS_FILE) as f:
        return json.load(f)

def pick_best_strategy(results):
    """Pick the best strategy based on evaluation results.
    
    AutoTTS CMC logic: Prefer high success rate, but also consider efficiency.
    """
    if not results or 'strategies' not in results:
        return 'own-repos-first'  # Default
    
    strategies = results['strategies']
    if not strategies:
        return 'own-repos-first'
    
    # Score = success_rate * efficiency
    # This balances "works" with "cheap"
    scored = []
    for name, data in strategies.items():
        score = data['success_rate'] * data['avg_efficiency']
        scored.append((name, score, data))
    
    scored.sort(key=lambda x: x[1], reverse=True)
    return scored[0][0]

def load_strategy(name):
    """Load a strategy definition."""
    strategy_file = STRATEGY_DIR / f"{name}.json"
    if not strategy_file.exists():
        return None
    with open(strategy_file) as f:
        return json.load(f)

def format_strategy_guidance(strategy):
    """Format strategy as guidance text for researcher prompt."""
    lines = [
        f"## Active Strategy: {strategy['name']}",
        f"{strategy['description']}",
        "",
        "### Execution Phases:",
    ]
    
    for i, phase in enumerate(strategy['phases'], 1):
        condition = f" (if: {phase['condition']})" if 'condition' in phase else ""
        stop_if = f" [stop: {phase['stop_if']}]" if 'stop_if' in phase else ""
        lines.append(f"{i}. **{phase['name']}**{condition}{stop_if}")
    
    lines.extend([
        "",
        f"### Budget:",
        f"- Max tokens: {strategy['cost_limit']}",
        f"- Expected: {strategy['expected_tokens']}",
        "",
        "**EXECUTE THESE PHASES IN ORDER. DO NOT SKIP UNLESS CONDITION IS FALSE.**",
    ])
    
    return "\n".join(lines)

def update_researcher_guidance(best_strategy_name, strategy_data):
    """Update the researcher strategy guidance file."""
    guidance = format_strategy_guidance(strategy_data)
    
    GUIDANCE_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(GUIDANCE_FILE, 'w') as f:
        json.dump({
            'best_strategy': best_strategy_name,
            'guidance': guidance,
            'updated_at': json.dumps({}),
        }, f, indent=2)
    
    print(f"[evolve] Updated guidance for strategy: {best_strategy_name}")
    print(f"[evolve] Guidance saved to: {GUIDANCE_FILE}")

def inject_strategy_into_skill():
    """Inject the active strategy into researcher-prompt/SKILL.md.
    
    This replaces the {{strategy-guidance}} placeholder with actual strategy.
    """
    if not GUIDANCE_FILE.exists():
        print("[evolve] No guidance file yet. Run evaluation first.")
        return
    
    with open(GUIDANCE_FILE) as f:
        guidance_data = json.load(f)
    
    guidance = guidance_data.get('guidance', '')
    
    # Read current skill
    with open(SKILL_FILE) as f:
        skill_content = f.read()
    
    # Replace placeholder
    if '{{strategy-guidance}}' in skill_content:
        new_content = skill_content.replace('{{strategy-guidance}}', guidance)
    else:
        # Find the Strategy Guidance section and replace it
        import re
        pattern = r'(## Strategy Guidance \(from Replay Store\)\n\n).*?(\n## |$)'
        replacement = r'\1' + guidance + r'\2'
        new_content = re.sub(pattern, replacement, skill_content, flags=re.DOTALL)
    
    # Write back
    with open(SKILL_FILE, 'w') as f:
        f.write(new_content)
    
    print(f"[evolve] Injected strategy into {SKILL_FILE}")

def main():
    """Run one evolution cycle."""
    print("[evolve] === AutoTTS Strategy Evolution ===\n")
    
    # Step 1: Ensure strategies exist
    print("[evolve] Step 1: Building strategy definitions...")
    run_controller_dsl()
    
    # Step 2: Find latest trace
    traces = sorted(TRACE_DIR.glob("*.json")) if TRACE_DIR.exists() else []
    if traces:
        latest_trace = traces[-1].stem
        print(f"[evolve] Step 2: Evaluating against latest trace: {latest_trace}")
        run_evaluator(latest_trace)
    else:
        print("[evolve] Step 2: No traces yet. Using default strategy.")
        # Still run evaluator to initialize
        run_evaluator()
    
    # Step 3: Load results and pick best
    print("\n[evolve] Step 3: Picking best strategy...")
    results = load_evaluation_results()
    best_strategy = pick_best_strategy(results)
    print(f"[evolve] Best strategy: {best_strategy}")
    
    # Step 4: Load strategy data and update guidance
    print("\n[evolve] Step 4: Updating guidance...")
    strategy_data = load_strategy(best_strategy)
    if strategy_data:
        update_researcher_guidance(best_strategy, strategy_data)
        inject_strategy_into_skill()
    else:
        print(f"[evolve] Warning: Could not load strategy {best_strategy}")
    
    print("\n[evolve] === Evolution Complete ===")

if __name__ == '__main__':
    main()
