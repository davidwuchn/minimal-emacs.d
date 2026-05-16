#!/usr/bin/env python3
"""learn_controller.py - Statistical controller learning from trace outcomes.

Simple correlation-based learning that works with small datasets.
Called from Elisp when sufficient traces with outcomes are available.

Usage: python3 learn_controller.py [trace_dir] [output_json]
"""

import json
import sys
import math
from pathlib import Path

def sigmoid(x):
    return 1 / (1 + math.exp(-max(-10, min(10, x))))

def load_traces(trace_dir):
    """Load all traces with outcomes."""
    traces = []
    trace_path = Path(trace_dir)
    if not trace_path.exists():
        return traces
    
    for f in trace_path.glob("*.json"):
        try:
            with open(f) as fh:
                trace = json.load(fh)
            # Only include traces with outcomes
            if trace.get("outcomes"):
                traces.append(trace)
        except Exception:
            pass
    return traces

def extract_features(trace):
    """Extract feature vector from trace."""
    return {
        "output_length": trace.get("output-length", 0),
        "has_urls": 1 if trace.get("has-urls") else 0,
        "has_structure": 1 if trace.get("has-structure") else 0,
        "has_code": 1 if trace.get("has-code") else 0,
        "source_own": 1 if trace.get("source") == "own-repo" else 0,
        "confidence": trace.get("confidence", 0),
        "tokens_used": trace.get("tokens-used", 0),
        "step_count": trace.get("step-count", 0),
    }

def get_outcome(trace):
    """Binary outcome: 1 if any experiment kept, 0 otherwise."""
    outcomes = trace.get("outcomes", [])
    if not outcomes:
        return None
    return 1 if any(o.get("kept") for o in outcomes) else 0

def extract_topic(trace):
    """Extract topic from trace.
    Looks for topic in outcomes or strategy name."""
    # Check outcomes for topic hints
    outcomes = trace.get("outcomes", [])
    if outcomes:
        target = outcomes[0].get("target", "")
        # Extract topic from filename patterns
        if "loop" in target or "retry" in target:
            return "async"
        elif "sandbox" in target or "security" in target:
            return "nil-safety"
        elif "cache" in target or "context" in target:
            return "performance"
        elif "error" in target or "guard" in target:
            return "error-handling"
    
    # Check strategy for topic hints
    strategy = trace.get("strategy", "")
    if strategy == "own-repos-first":
        return "nil-safety"
    elif strategy == "deep-external":
        return "performance"
    
    return "general"

def learn_topic_specific(traces, topic):
    """Learn topic-specific controller from traces.
    Returns model for this topic, or None if insufficient data."""
    topic_traces = [t for t in traces if extract_topic(t) == topic]
    return learn_controller_simple(topic_traces, topic)

def learn_controller_simple(traces, topic_name="general"):
    """Learn controller parameters from traces with outcomes.
    
    Uses simple correlation-based approach:
    1. Calculate mean feature values for kept vs discarded
    2. Use difference as feature weight
    3. Fit intercept so P(kept) ≈ base rate
    """
    if len(traces) < 3:
        return None  # Insufficient data
    
    # Extract features and outcomes
    data = []
    for trace in traces:
        outcome = get_outcome(trace)
        if outcome is not None:
            data.append((extract_features(trace), outcome))
    
    if len(data) < 3:
        return None
    
    n = len(data)
    n_kept = sum(1 for _, y in data if y == 1)
    base_rate = n_kept / n
    
    # Calculate means for kept vs discarded
    features = ["output_length", "has_urls", "has_structure", "has_code", 
                "source_own", "confidence", "tokens_used", "step_count"]
    
    kept_means = {f: 0.0 for f in features}
    disc_means = {f: 0.0 for f in features}
    kept_count = disc_count = 0
    
    for feats, outcome in data:
        if outcome == 1:
            for f in features:
                kept_means[f] += feats[f]
            kept_count += 1
        else:
            for f in features:
                disc_means[f] += feats[f]
            disc_count += 1
    
    if kept_count == 0 or disc_count == 0:
        return None
    
    for f in features:
        kept_means[f] /= kept_count
        disc_means[f] /= disc_count
    
    # Calculate weights as difference in means (normalized)
    weights = {}
    for f in features:
        diff = kept_means[f] - disc_means[f]
        # Normalize by pooled std (approximate)
        pooled_std = max(0.01, (kept_means[f] + disc_means[f]) / 2)
        weights[f] = diff / pooled_std
    
    # Calculate intercept for logistic regression
    # We want: when all features at their mean, P(kept) = base_rate
    mean_score = sum(weights[f] * (kept_means[f] + disc_means[f]) / 2 for f in features)
    intercept = math.log(base_rate / (1 - base_rate)) - mean_score
    
    # Calculate decision thresholds from data
    kept_scores = []
    disc_scores = []
    for feats, outcome in data:
        score = intercept + sum(weights[f] * feats[f] for f in features)
        prob = sigmoid(score)
        if outcome == 1:
            kept_scores.append(prob)
        else:
            disc_scores.append(prob)
    
    # STOP threshold: mean of kept scores
    stop_threshold = sum(kept_scores) / len(kept_scores) if kept_scores else 0.7
    
    # BRANCH threshold: mean of discarded scores  
    branch_threshold = sum(disc_scores) / len(disc_scores) if disc_scores else 0.3
    
    return {
        "topic": topic_name,
        "model": {
            "intercept": intercept,
            "weights": weights,
            "features": features,
            "n_traces": n,
            "n_kept": n_kept,
            "base_rate": base_rate,
        },
        "thresholds": {
            "stop": min(0.9, max(0.5, stop_threshold)),
            "branch": max(0.1, min(0.5, branch_threshold)),
            "cut_tokens": 8000,
        },
        "stats": {
            "kept_means": {k: round(v, 3) for k, v in kept_means.items()},
            "discarded_means": {k: round(v, 3) for k, v in disc_means.items()},
        }
    }

def learn_controller(traces):
    """Learn controller parameters from traces with outcomes.
    
    Learns both global model and topic-specific models.
    Topic models allow different strategies for different research topics.
    """
    if len(traces) < 5:
        return None  # Insufficient data
    
    # Global model (all traces)
    global_model = learn_controller_simple(traces, "global")
    if not global_model:
        return None
    
    # Topic-specific models
    topics = {}
    topic_names = set(extract_topic(t) for t in traces)
    
    for topic in topic_names:
        topic_model = learn_topic_specific(traces, topic)
        if topic_model:
            topics[topic] = topic_model
    
    # Merge into single result
    result = global_model.copy()
    result["topics"] = topics
    result["topic_count"] = len(topics)
    
    return result

def main():
    if len(sys.argv) < 2:
        trace_dir = str(Path(__file__).resolve().parents[4] / "var" / "tmp" / "research-traces")
    else:
        trace_dir = sys.argv[1]
    
    traces = load_traces(trace_dir)
    print(f"Loaded {len(traces)} traces with outcomes", file=sys.stderr)
    
    result = learn_controller(traces)
    if result:
        print(json.dumps(result))
    else:
        print(json.dumps({"error": "insufficient_data", "n_traces": len(traces)}))

if __name__ == "__main__":
    main()
