// The shapes of /readback/api/decisions (specs/007-agentic-tools-governance/contracts/interfaces.md): a closed field list.

export interface FeedAgent {
  decision?: string;
  severity?: number;
  confidence?: string;
  rationale?: string;
  evidence?: string[];
  /** Set instead of the answer when the agent gave none. */
  failureKind?: string;
}

export interface FeedItem {
  decisionId: number;
  controlId: string;
  analyte: string;
  /** The result as it arrived. */
  value: { text: string; unit: string };
  decidedAt: string;
  mode: "live" | "replay";
  route: string;
  floor: { severity: number; ruleId: string; note: string };
  agent: FeedAgent;
  final: { severity: number };
  /** True when the floor held back an attempt of the agent to lower a critical. */
  held: boolean;
  conversion?: { original: string; converted: string; unit: string; standard: string };
  cost: { tokens: number; latencyMs: number; model: string; usd: number | null };
  rounds: number;
  toolCallCount: number;
  toolFailureCount: number;
}

export interface Feed {
  items: FeedItem[];
  more: boolean;
}

/** The production's state and mode, from /readback/api/status. */
export interface Seals {
  productionRunning: boolean;
  mode: "live" | "replay";
  model: string;
}
