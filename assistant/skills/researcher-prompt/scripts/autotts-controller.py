#!/usr/bin/env python3
"""AutoTTS Controller — Real-time research strategy controller

This is the core of AutoTTS: an executable controller that decides
when to search, fetch, branch, or stop based on confidence metrics.
"""
import json
import re
from pathlib import Path
from typing import List, Dict, Optional, Tuple
from dataclasses import dataclass, field
from enum import Enum

ROOT = Path("/home/davidwu/.emacs.d")
CONTROLLER_FILE = ROOT / "var/tmp/researcher-controller.json"
TRACE_DIR = ROOT / "var/tmp/research-traces"

class Action(Enum):
    SEARCH_OWN = "search_own"
    SEARCH_FORKS = "search_forks"
    SEARCH_EXTERNAL = "search_external"
    FETCH = "fetch"
    SYNTHESIZE = "synthesize"
    STOP = "stop"
    BRANCH = "branch"
    CUT = "cut"

@dataclass
class ResearchState:
    """Current state of a research session."""
    phase: str = "start"
    tokens_used: int = 0
    insights_found: int = 0
    urls_found: List[str] = field(default_factory=list)
    confidence: float = 0.0  # 0-1, current confidence in findings
    confidence_history: List[float] = field(default_factory=list)
    sources_checked: List[str] = field(default_factory=list)
    topic: str = ""
    budget_remaining: int = 8000
    
    def confidence_trend(self, window: int = 3) -> float:
        """Calculate confidence trend (rising, flat, falling)."""
        if len(self.confidence_history) < window:
            return 0.0
        recent = self.confidence_history[-window:]
        return recent[-1] - recent[0]
    
    def confidence_rising(self) -> bool:
        return self.confidence_trend() > 0.1
    
    def confidence_stagnant(self, window: int = 2) -> bool:
        if len(self.confidence_history) < window:
            return False
        recent = self.confidence_history[-window:]
        return max(recent) - min(recent) < 0.05
    
    def over_budget(self) -> bool:
        return self.tokens_used > self.budget_remaining

@dataclass
class ControllerConfig:
    """Configurable parameters for the controller."""
    own_repo_priority: float = 0.7  # Weight for own repos
    fork_priority: float = 0.4
    external_priority: float = 0.15
    web_priority: float = 0.05
    
    min_confidence_stop: float = 0.7
    max_tokens_budget: int = 8000
    max_searches_per_source: int = 2
    min_insights_for_stop: int = 2
    
    confidence_threshold_high: float = 0.7
    confidence_threshold_low: float = 0.3
    stagnation_window: int = 2
    
    @classmethod
    def from_dict(cls, d: dict) -> 'ControllerConfig':
        return cls(**{k: v for k, v in d.items() if k in cls.__dataclass_fields__})
    
    def to_dict(self) -> dict:
        return {
            'own_repo_priority': self.own_repo_priority,
            'fork_priority': self.fork_priority,
            'external_priority': self.external_priority,
            'web_priority': self.web_priority,
            'min_confidence_stop': self.min_confidence_stop,
            'max_tokens_budget': self.max_tokens_budget,
            'max_searches_per_source': self.max_searches_per_source,
            'min_insights_for_stop': self.min_insights_for_stop,
            'confidence_threshold_high': self.confidence_threshold_high,
            'confidence_threshold_low': self.confidence_threshold_low,
            'stagnation_window': self.stagnation_window,
        }

class ResearchController:
    """AutoTTS-style controller for research decisions."""
    
    def __init__(self, config: Optional[ControllerConfig] = None):
        self.config = config or ControllerConfig()
        self.state = ResearchState()
        self.decision_log = []
    
    def decide(self, state: ResearchState) -> Tuple[Action, str]:
        """Make a decision based on current state.
        
        Returns: (action, reasoning)
        """
        # Check budget
        if state.over_budget():
            return Action.STOP, f"Budget exceeded: {state.tokens_used}/{self.config.max_tokens_budget}"
        
        # High confidence + enough insights → stop
        if (state.confidence >= self.config.min_confidence_stop and 
            state.insights_found >= self.config.min_insights_for_stop):
            return Action.STOP, f"High confidence ({state.confidence:.2f}) with {state.insights_found} insights"
        
        # Confidence rising → continue current path
        if state.confidence_rising():
            if state.phase == "search_own" and "own" not in state.sources_checked:
                return Action.SEARCH_OWN, "Confidence rising, checking own repos"
            elif state.phase == "search_forks" and "fork" not in state.sources_checked:
                return Action.SEARCH_FORKS, "Confidence rising, checking forks"
        
        # Confidence stagnant → branch (try different source)
        if state.confidence_stagnant(self.config.stagnation_window):
            if "external" not in state.sources_checked:
                return Action.SEARCH_EXTERNAL, "Confidence stagnant, branching to external"
            elif "web" not in state.sources_checked:
                return Action.BRANCH, "Confidence stagnant, trying web search"
            else:
                return Action.CUT, "All sources exhausted, confidence still stagnant"
        
        # Low confidence → try next source type
        if state.confidence < self.config.confidence_threshold_low:
            if "own" not in state.sources_checked:
                return Action.SEARCH_OWN, "Low confidence, starting with own repos"
            elif "fork" not in state.sources_checked:
                return Action.SEARCH_FORKS, "Low confidence, checking forks"
            elif "external" not in state.sources_checked:
                return Action.SEARCH_EXTERNAL, "Low confidence, trying external"
        
        # Has URLs but hasn't fetched → fetch
        if state.urls_found and state.phase not in ["fetch", "synthesize"]:
            return Action.FETCH, f"Found {len(state.urls_found)} URLs to fetch"
        
        # Has insights → synthesize
        if state.insights_found > 0 and state.phase != "synthesize":
            return Action.SYNTHESIZE, f"Synthesizing {state.insights_found} insights"
        
        # Default: search own repos
        return Action.SEARCH_OWN, "Default: start with own repos"
    
    def update_state(self, action: Action, result: dict):
        """Update state after taking an action."""
        self.state.phase = action.value
        self.state.tokens_used += result.get('tokens', 0)
        
        if 'insights' in result:
            self.state.insights_found += result['insights']
        if 'urls' in result:
            self.state.urls_found.extend(result['urls'])
        if 'confidence' in result:
            self.state.confidence = result['confidence']
            self.state.confidence_history.append(result['confidence'])
        if 'source' in result:
            self.state.sources_checked.append(result['source'])
        
        self.decision_log.append({
            'action': action.value,
            'tokens': result.get('tokens', 0),
            'confidence': result.get('confidence', 0),
        })
    
    def to_dict(self) -> dict:
        return {
            'config': self.config.to_dict(),
            'state': {
                'phase': self.state.phase,
                'tokens_used': self.state.tokens_used,
                'insights_found': self.state.insights_found,
                'confidence': self.state.confidence,
                'confidence_history': self.state.confidence_history,
                'sources_checked': self.state.sources_checked,
            },
            'decision_log': self.decision_log,
        }
    
    @classmethod
    def from_dict(cls, d: dict) -> 'ResearchController':
        ctrl = cls(ControllerConfig.from_dict(d.get('config', {})))
        ctrl.state.phase = d.get('state', {}).get('phase', 'start')
        ctrl.state.tokens_used = d.get('state', {}).get('tokens_used', 0)
        ctrl.state.insights_found = d.get('state', {}).get('insights_found', 0)
        ctrl.state.confidence = d.get('state', {}).get('confidence', 0.0)
        ctrl.state.confidence_history = d.get('state', {}).get('confidence_history', [])
        ctrl.state.sources_checked = d.get('state', {}).get('sources_checked', [])
        ctrl.decision_log = d.get('decision_log', [])
        return ctrl

def save_controller(controller: ResearchController):
    """Save controller to disk."""
    CONTROLLER_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(CONTROLLER_FILE, 'w') as f:
        json.dump(controller.to_dict(), f, indent=2)
    print(f"[controller] Saved to {CONTROLLER_FILE}")

def load_controller() -> ResearchController:
    """Load controller from disk."""
    if CONTROLLER_FILE.exists():
        with open(CONTROLLER_FILE) as f:
            return ResearchController.from_dict(json.load(f))
    return ResearchController()

def evaluate_controller_on_trace(controller: ResearchController, trace: dict) -> dict:
    """Evaluate how a controller would perform on a cached trace.
    
    This is the core AutoTTS insight: test offline, no LLM calls.
    """
    # Reset state
    controller.state = ResearchState()
    controller.decision_log = []
    
    final_output = trace.get('final_output', '')
    prompt = trace.get('prompt', '')
    
    # Simulate: extract topic from prompt
    topic_match = re.search(r'Topics?:\s*([^\n]+)', prompt)
    topic = topic_match.group(1) if topic_match else 'unknown'
    controller.state.topic = topic
    
    # Simulate: make decisions based on trace characteristics
    # In reality, we'd replay the actual tool calls
    output_len = len(final_output)
    has_urls = bool(re.search(r'https?://', final_output))
    
    # Simulate steps
    steps = [
        {'action': Action.SEARCH_OWN, 'result': {'tokens': 1000, 'confidence': 0.5, 'source': 'own'}},
        {'action': Action.SEARCH_FORKS, 'result': {'tokens': 1500, 'confidence': 0.6, 'source': 'fork'}},
        {'action': Action.FETCH, 'result': {'tokens': 2000, 'confidence': 0.7, 'source': 'external'}},
        {'action': Action.SYNTHESIZE, 'result': {'tokens': 500, 'confidence': 0.8, 'source': 'synthesize'}},
    ]
    
    for step in steps:
        action, reasoning = controller.decide(controller.state)
        controller.update_state(step['action'], step['result'])
    
    return {
        'total_tokens': controller.state.tokens_used,
        'final_confidence': controller.state.confidence,
        'insights_found': controller.state.insights_found,
        'would_stop_early': controller.state.confidence >= controller.config.min_confidence_stop,
        'efficiency': output_len / max(controller.state.tokens_used, 1),
    }

def main():
    """Create default controller."""
    controller = ResearchController()
    save_controller(controller)
    print("[controller] Created default controller")
    print(json.dumps(controller.to_dict(), indent=2))

if __name__ == '__main__':
    main()
