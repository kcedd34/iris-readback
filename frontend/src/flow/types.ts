// The shapes of /readback/api/flow (specs/005-flow-ui/data-model.md) and the panel's own items.
export type Mode = "replay" | "live";

export interface DecidedEntry {
  decisionId: number;
  controlId: string;
  analyte: string;
  route: string; // readback | review | recollect | release
  finalSeverity: number;
  reason: string;
  floorNote: string;
  failureKind: string;
  agentCalled: boolean;
  recordedLatencyMs?: number;
  mode: Mode;
  decidedAt: string;
}

export interface WaitingEntry {
  decisionId: number;
  controlId: string;
  analyte: string;
  since: string;
  taskId: string | number;
  assignedTo: string;
  mode: Mode;
  alertLevel?: number;
  alertState?: string;
}

export interface InFlightEntry {
  controlId: string;
  analyte: string;
  enteredAt: string;
}

export interface ConfirmedEntry {
  decisionId: number;
  controlId: string;
  confirmedBy: string;
  confirmedAt: string;
  readbackMatch: boolean;
}

export interface FlowSnapshot {
  mode: Mode;
  cursor: number;
  decided: DecidedEntry[];
  inFlight: InFlightEntry[];
  waiting: WaitingEntry[];
  waitingTotal: number;
  confirmed: ConfirmedEntry[];
}

/** Where an item is. Recollect advice is shown on review, as the product routes it. */
export type Station = "intake" | "agent" | "readback" | "confirmed" | "review" | "release";

export interface FlowItem {
  key: string;
  controlId: string;
  analyte: string;
  station: Station;
  /** Time the item reached its station (ms, the clock given to the reducer). */
  stationSince: number;
  /** Stations still to pass through, with the replay choreography; empty when the item is where it belongs. */
  path: Station[];
  /** When the next step of the path is due (ms). */
  stepAt: number;
  severity: number | null;
  route?: string;
  reason?: string;
  failureKind?: string;
  /** True when the decision was taken from a recording, so the panel labels it as a replay. */
  replayed: boolean;
  decisionId?: number;
  waitingSince?: string;
  assignedTo?: string;
  alertState?: string;
  confirmedBy?: string;
  readbackMatch?: boolean;
}

export interface FlowState {
  items: Record<string, FlowItem>;
  order: string[];
  cursor: number | null;
  mode: Mode;
  stale: boolean;
  waitingTotal: number;
  inFlightCount: number;
  started: boolean;
}
