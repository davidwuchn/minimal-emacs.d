#!/usr/bin/env python3
"""Unified Evolution Loop — AutoTTS + Self-Evolution Integration

This is the smooth integration layer:
1. AutoTTS: Evolves the controller (HOW to research)
2. Self-Evolution: Evolves the knowledge (WHAT to research)
3. Together: Controller uses evolved knowledge to make better decisions
"""
import json
import sys
from pathlib import Path
from typing import Dict, List, Optional

ROOT = Path("/home/davidwu/.emacs.d")
CONTROLLER_FILE = ROOT / "var/tmp/researcher-controller.json"
REPLAY_FILE = ROOT / "var/tmp/research-replay-store.json"
GUIDANCE_FILE = ROOT / "var/tmp/researcher-strategy-guidance.json"
SKILL_FILE = ROOT / "assistant/skills/researcher-prompt/SKILL.md"

def load_controller():
    """Load current controller."""
    sys.path.insert(0, str(ROOT / "assistant/skills/researcher-prompt/scripts"))
    from autotts_controller import load_controller as load_ctrl
    return load_ctrl()

def load_replay_store():
    """Load replay store."""
    if REPLAY_FILE.exists():
        with open(REPLAY_FILE) as f:
            return json.load(f)
    return {"version": "1.0", "sessions": [], "strategies": {}}

def evolve_controller_from_traces(controller, traces):
    """Evolve controller parameters based on trace performance.
    
    AutoTTS insight: Adjust controller weights based on what worked.
    """
    if not traces:
        print("[evolve] No traces to learn from")
        return controller
    
    # Analyze trace outcomes
    own_repo_success = 0
    own_repo_total = 0
    external_success = 0
    external_total = 0
    
    for trace in traces:
        # Check if trace mentions own repos
        prompt = trace.get('prompt', '')
        output = trace.get('final_output', '')
        
        if 'davidwuchn' in prompt or 'github.com/davidwuchn' in output:
            own_repo_total += 1
            if len(output) > 1000:  # Good output
                own_repo_success += 1
        else:
            external_total += 1
            if len(output) > 1000:
                external_success += 1
    
    # Update priorities based on success rates
    config = controller.config
    
    if own_repo_total > 0:
        own_rate = own_repo_success / own_repo_total
        config.own_repo_priority = min(0.9, config.own_repo_priority + 0.05 * own_rate)
        print(f"[evolve] Own repo success rate: {own_rate:.1%} → priority: {config.own_repo_priority:.2f}")
    
    if external_total > 0:
        external_rate = external_success / external_total
        config.external_priority = max(0.1, config.external_priority - 0.05 * (1 - external_rate))
        print(f"[evolve] External success rate: {external_rate:.1%} → priority: {config.external_priority:.2f}")
    
    # Adjust confidence thresholds based on average output quality
    avg_output_len = sum(len(t.get('final_output', '')) for t in traces) / len(traces)
    if avg_output_len > 2000:
        config.min_confidence_stop = max(0.5, config.min_confidence_stop - 0.05)
        print(f"[evolve] Good output quality → lower stop threshold: {config.min_confidence_stop:.2f}")
    else:
        config.min_confidence_stop = min(0.8, config.min_confidence_stop + 0.05)
        print(f"[evolve] Poor output quality → raise stop threshold: {config.min_confidence_stop:.2f}")
    
    return controller

def synthesize_knowledge_from_traces(traces):
    """Self-evolution layer: extract knowledge from traces."""
    if not traces:
        return {}
    
    # Extract topics that produced good results
    topic_performance = {}
    source_performance = {}
    
    for trace in traces:
        output = trace.get('final_output', '')
        metadata = trace.get('metadata', {})
        
        # Extract topics mentioned
        topics = metadata.get('topics_covered', [])
        for topic in topics:
            if topic not in topic_performance:
                topic_performance[topic] = {'total': 0, 'good': 0}
            topic_performance[topic]['total'] += 1
            if len(output) > 1000:
                topic_performance[topic]['good'] += 1
        
        # Extract sources
        sources = metadata.get('sources_checked', [])
        for source in sources:
            if source not in source_performance:
                source_performance[source] = {'total': 0, 'good': 0}
            source_performance[source]['total'] += 1
            if len(output) > 1000:
                source_performance[source]['good'] += 1
    
    return {
        'topic_performance': topic_performance,
        'source_performance': source_performance,
    }

def update_skill_with_controller_and_knowledge(controller, knowledge):
    """Update researcher SKILL.md with evolved controller + knowledge.
    
    This is the integration point: controller config + knowledge → prompt.
    """
    config = controller.config
    
    # Build controller guidance section
    controller_lines = [
        "## AutoTTS Controller Configuration (Evolved)",
        "",
        f"**Current Strategy Parameters** (auto-tuned from {len(knowledge.get('topic_performance', {}))} topics):",
        "",
        f"- **Own Repo Priority**: {config.own_repo_priority:.0%} (weight for davidwuchn/* repos)",
        f"- **Fork Priority**: {config.fork_priority:.0%} (weight for forked repos)",
        f"- **External Priority**: {config.external_priority:.0%} (weight for external trending)",
        f"- **Web Priority**: {config.web_priority:.0%} (weight for general web search)",
        "",
        f"- **Stop Threshold**: {config.min_confidence_stop:.0%} confidence (stop early if above)",
        f"- **Budget**: {config.max_tokens_budget} tokens max",
        f"- **Min Insights**: {config.min_insights_for_stop} insights before stopping",
        "",
        "### Controller Decision Rules",
        "",
        "The controller decides research flow based on real-time confidence:",
        "",
        "1. **Confidence > 70% + 2+ insights** → STOP (return findings)",
        "2. **Confidence rising** → Continue current source type",
        "3. **Confidence stagnant** → BRANCH to different source",
        "4. **Confidence < 30%** → Try next source priority",
        "5. **Budget exceeded** → CUT (return what we have)",
        "",
    ]
    
    # Build knowledge section
    knowledge_lines = ["### Evolved Knowledge", ""]
    
    topic_perf = knowledge.get('topic_performance', {})
    if topic_perf:
        knowledge_lines.append("**Topic Performance** (from replay store):")
        for topic, perf in sorted(topic_perf.items(), 
                                  key=lambda x: x[1].get('good', 0) / max(x[1].get('total', 1), 1),
                                  reverse=True)[:5]:
            rate = perf['good'] / perf['total'] if perf['total'] > 0 else 0
            knowledge_lines.append(f"- {topic}: {rate:.0%} success ({perf['good']}/{perf['total']})")
        knowledge_lines.append("")
    
    source_perf = knowledge.get('source_performance', {})
    if source_perf:
        knowledge_lines.append("**Source Performance**:")
        for source, perf in sorted(source_perf.items(),
                                   key=lambda x: x[1].get('good', 0) / max(x[1].get('total', 1), 1),
                                   reverse=True)[:5]:
            rate = perf['good'] / perf['total'] if perf['total'] > 0 else 0
            knowledge_lines.append(f"- {source}: {rate:.0%} success ({perf['good']}/{perf['total']})")
        knowledge_lines.append("")
    
    guidance = "\n".join(controller_lines + knowledge_lines)
    
    # Save to guidance file
    GUIDANCE_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(GUIDANCE_FILE, 'w') as f:
        json.dump({
            'guidance': guidance,
            'controller_config': config.to_dict(),
            'knowledge': knowledge,
        }, f, indent=2)
    
    return guidance

def inject_into_skill(guidance):
    """Inject evolved guidance into researcher SKILL.md."""
    with open(SKILL_FILE) as f:
        content = f.read()
    
    # Replace strategy-guidance placeholder
    if '{{strategy-guidance}}' in content:
        new_content = content.replace('{{strategy-guidance}}', guidance)
    else:
        # Find the section and replace
        import re
        pattern = r'(## Strategy Guidance \(from Replay Store\)\n\n).*?(\n## |$)'
        if re.search(pattern, content, re.DOTALL):
            new_content = re.sub(pattern, r'\1' + guidance + r'\2', content, flags=re.DOTALL)
        else:
            # Insert after AutoTTS section
            insert_after = "## Priority Projects to Monitor"
            new_content = content.replace(
                insert_after,
                guidance + "\n\n" + insert_after
            )
    
    with open(SKILL_FILE, 'w') as f:
        f.write(new_content)
    
    print(f"[evolve] Updated {SKILL_FILE}")

def main():
    """Run unified evolution."""
    print("=" * 60)
    print("UNIFIED EVOLUTION: AutoTTS + Self-Evolution")
    print("=" * 60)
    
    # Step 1: Load current controller
    print("\n[1/4] Loading controller...")
    controller = load_controller()
    print(f"  Current config: stop_threshold={controller.config.min_confidence_stop}, "
          f"own_priority={controller.config.own_repo_priority}")
    
    # Step 2: Load traces
    print("\n[2/4] Loading research traces...")
    traces = []
    if TRACE_DIR.exists():
        for f in TRACE_DIR.glob("*.json"):
            with open(f) as fh:
                traces.append(json.load(fh))
    print(f"  Loaded {len(traces)} traces")
    
    # Step 3: AutoTTS layer — evolve controller
    print("\n[3/4] AutoTTS: Evolving controller...")
    controller = evolve_controller_from_traces(controller, traces)
    
    # Save evolved controller
    sys.path.insert(0, str(ROOT / "assistant/skills/researcher-prompt/scripts"))
    from autotts_controller import save_controller
    save_controller(controller)
    
    # Step 4: Self-Evolution layer — synthesize knowledge
    print("\n[4/4] Self-Evolution: Synthesizing knowledge...")
    knowledge = synthesize_knowledge_from_traces(traces)
    print(f"  Topics: {len(knowledge.get('topic_performance', {}))}")
    print(f"  Sources: {len(knowledge.get('source_performance', {}))}")
    
    # Step 5: Integrate and update skill
    print("\n[5/5] Integrating controller + knowledge into skill...")
    guidance = update_skill_with_controller_and_knowledge(controller, knowledge)
    inject_into_skill(guidance)
    
    print("\n" + "=" * 60)
    print("EVOLUTION COMPLETE")
    print("=" * 60)
    print("\nNext research session will use:")
    print(f"  - Controller with {controller.config.own_repo_priority:.0%} own-repo priority")
    print(f"  - Stop threshold: {controller.config.min_confidence_stop:.0%} confidence")
    print(f"  - Knowledge from {len(traces)} historical traces")

if __name__ == '__main__':
    main()
