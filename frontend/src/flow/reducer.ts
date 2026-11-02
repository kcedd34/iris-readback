import type { ConfirmedEntry, DecidedEntry, FlowItem, FlowSnapshot, FlowState, Station, WaitingEntry } from "./types";

/** Minimum time a replayed decision stays at each station, so a decision that took milliseconds can still be seen. */
export const INTAKE_DWELL_MS = 450;
export const AGENT_DWELL_MS = 700;
/** Each tool call of the investigation lights up for this long inside the agent node, so the order can be followed. */
export const TOOL_STEP_MS = 520;
const MAX_TOOL_STEPS_SHOWN = 6;
/** How long a replayed decision stays at the agent: the base time, and one step for each tool call it made. */
export const agentDwellMs = (calls: number): number => AGENT_DWELL_MS + TOOL_STEP_MS * Math.min(calls, MAX_TOOL_STEPS_SHOWN);
/** How long a finished item (released, reviewed, confirmed) stays on screen. A waiting item never expires. */
export const FINISHED_MS = 20000;
/** At most this many finished items are kept; waiting items are never counted or dropped. */
export const MAX_FINISHED = 60;
/** A submitted placeholder that the product never confirmed is dropped after this long. */
export const PLACEHOLDER_MS = 8000;

export type FlowAction =
  | { type: "snapshot"; snapshot: FlowSnapshot; now: number }
  | { type: "stale" }
  | { type: "tick"; now: number }
  | { type: "submitted"; controlIds: string[]; analyte: string; now: number };

export const initialState: FlowState = {
  items: {},
  order: [],
  cursor: null,
  mode: "replay",
  stale: false,
  waitingTotal: 0,
  inFlightCount: 0,
  started: false,
};

// Keys: "d<decisionId>" for a decided or waiting case, "f:<controlId>:<enteredAt>" for a result still being decided,
// "s:<controlId>:<time>:<n>" for a result the visitor just submitted and the product has not listed yet.
const isPlaceholder = (key: string) => key.startsWith("s:");
const isInFlight = (key: string) => key.startsWith("f:");

export function destinationOf(route: string): Station {
  if (route === "readback") return "readback";
  if (route === "release") return "release";
  return "review"; // review and recollect advice
}

function isFinished(item: FlowItem): boolean {
  return item.path.length === 0 && (item.station === "confirmed" || item.station === "review" || item.station === "release");
}

function withItem(state: FlowState, item: FlowItem): FlowState {
  const known = item.key in state.items;
  return { ...state, items: { ...state.items, [item.key]: item }, order: known ? state.order : [...state.order, item.key] };
}

function without(state: FlowState, key: string): FlowState {
  if (!(key in state.items)) return state;
  const rest = { ...state.items };
  delete rest[key];
  return { ...state, items: rest, order: state.order.filter((k) => k !== key) };
}

function base(key: string, controlId: string, analyte: string, station: Station, replayed: boolean, now: number): FlowItem {
  return { key, controlId, analyte, station, replayed, stationSince: now, path: [], stepAt: now, severity: null };
}

/** A decided entry becomes an item that walks to its destination. In replay it passes intake and the agent first. */
function applyDecided(state: FlowState, entry: DecidedEntry, now: number): FlowState {
  const key = `d${entry.decisionId}`;
  if (key in state.items) return state;
  // A case that was in flight is replaced by its decision.
  const pending = state.order.find((k) => isInFlight(k) && state.items[k].controlId === entry.controlId);
  if (pending) state = without(state, pending);
  const destination = destinationOf(entry.route);
  const replayed = entry.mode === "replay";
  const path: Station[] = replayed ? (entry.agentCalled ? ["agent", destination] : [destination]) : [];
  const item: FlowItem = {
    ...base(key, entry.controlId, entry.analyte, replayed ? "intake" : destination, replayed, now),
    path,
    stepAt: now + (replayed ? INTAKE_DWELL_MS : 0),
    severity: entry.finalSeverity,
    route: entry.route,
    reason: entry.reason || entry.floorNote,
    failureKind: entry.failureKind || undefined,
    decisionId: entry.decisionId,
    toolCalls: entry.toolCalls && entry.toolCalls.length ? entry.toolCalls : undefined,
    policyRefusal: entry.policyRefusal ? entry.policyRefusal : undefined,
  };
  return withItem(state, item);
}

function applyWaiting(state: FlowState, entry: WaitingEntry, now: number): FlowState {
  const key = `d${entry.decisionId}`;
  const existing = state.items[key];
  if (existing) {
    // Already walking or sitting: add what only the waiting list knows and keep the walk as it is.
    return withItem(state, { ...existing, waitingSince: entry.since, assignedTo: entry.assignedTo || undefined, alertState: entry.alertState, alertLevel: entry.alertLevel });
  }
  // Seen only in the waiting list (the page was opened after the decision): it is at read-back, no walk.
  return withItem(state, {
    ...base(key, entry.controlId, entry.analyte, "readback", entry.mode === "replay", now),
    severity: 3,
    route: "readback",
    decisionId: entry.decisionId,
    waitingSince: entry.since,
    assignedTo: entry.assignedTo || undefined,
    alertState: entry.alertState,
    alertLevel: entry.alertLevel,
  });
}

function confirmedById(list: ConfirmedEntry[]): Map<number, ConfirmedEntry> {
  return new Map(list.map((entry) => [entry.decisionId, entry]));
}

export function reduce(state: FlowState, action: FlowAction): FlowState {
  switch (action.type) {
    case "stale":
      // The last known state stays exactly as it was; only the flag changes.
      return state.stale ? state : { ...state, stale: true };

    case "submitted": {
      let next = state;
      action.controlIds.forEach((controlId, index) => {
        const key = `s:${controlId}:${action.now}:${index}`;
        next = withItem(next, base(key, controlId, action.analyte, "intake", false, action.now));
      });
      return next;
    }

    case "snapshot": {
      const { snapshot, now } = action;
      let next: FlowState = { ...state, mode: snapshot.mode, stale: false, started: true, waitingTotal: snapshot.waitingTotal, inFlightCount: snapshot.inFlight.length };

      // Results still being decided: the product's own list, shown at the agent station as it is.
      const inFlight = new Set<string>();
      for (const entry of snapshot.inFlight) {
        const key = `f:${entry.controlId}:${entry.enteredAt}`;
        inFlight.add(key);
        if (!(key in next.items)) next = withItem(next, base(key, entry.controlId, entry.analyte, "agent", false, now));
      }
      for (const key of [...next.order]) if (isInFlight(key) && !inFlight.has(key)) next = without(next, key);

      for (const entry of snapshot.decided) next = applyDecided(next, entry, now);

      const waitingIds = new Set<number>();
      for (const entry of snapshot.waiting) {
        waitingIds.add(entry.decisionId);
        next = applyWaiting(next, entry, now);
      }

      // A case at read-back that the product no longer lists as waiting has left read-back. The list is bounded;
      // when it is cut, an item older than the oldest listed one is left alone because nothing is known about it.
      const complete = snapshot.waitingTotal <= snapshot.waiting.length;
      const oldestListed = snapshot.waiting.length ? Math.min(...snapshot.waiting.map((w) => w.decisionId)) : Infinity;
      const confirmed = confirmedById(snapshot.confirmed);
      for (const key of [...next.order]) {
        const item = next.items[key];
        const waitingHere = item.route === "readback" && item.station === "readback" && item.path.length === 0 && item.decisionId !== undefined;
        if (!waitingHere || waitingIds.has(item.decisionId!)) continue;
        if (!complete && item.decisionId! < oldestListed) continue;
        const done = confirmed.get(item.decisionId!);
        next = withItem(next, { ...item, station: "confirmed", stationSince: now, confirmedBy: done?.confirmedBy, readbackMatch: done?.readbackMatch });
      }

      // A placeholder is replaced once the product lists the case (in flight or decided).
      for (const key of [...next.order]) {
        if (!isPlaceholder(key)) continue;
        const mine = next.items[key];
        const real = next.order.some((k) => !isPlaceholder(k) && next.items[k].controlId === mine.controlId && next.items[k].stationSince >= mine.stationSince);
        if (real) next = without(next, key);
      }
      return { ...next, cursor: snapshot.cursor };
    }

    case "tick": {
      const { now } = action;
      let next = state;
      for (const key of state.order) {
        const item = next.items[key];
        if (item.path.length > 0 && now >= item.stepAt) {
          const [station, ...rest] = item.path;
          next = withItem(next, { ...item, station, path: rest, stationSince: now, stepAt: now + (station === "agent" ? agentDwellMs(item.toolCalls?.length ?? 0) : 0) });
        }
      }
      for (const key of [...next.order]) {
        const item = next.items[key];
        if (isPlaceholder(key) && now - item.stationSince > PLACEHOLDER_MS) next = without(next, key);
        else if (isFinished(item) && now - item.stationSince > FINISHED_MS) next = without(next, key);
      }
      const finished = next.order.filter((key) => isFinished(next.items[key]));
      if (finished.length > MAX_FINISHED) {
        const drop = [...finished].sort((a, b) => next.items[a].stationSince - next.items[b].stationSince).slice(0, finished.length - MAX_FINISHED);
        for (const key of drop) next = without(next, key);
      }
      return next;
    }
  }
}

/** Cases the product routed to read-back and has not confirmed, whatever the animation is showing. */
export function waitingItems(state: FlowState): FlowItem[] {
  return state.order.map((k) => state.items[k]).filter((item) => item.route === "readback" && item.station !== "confirmed");
}

export function itemsAt(state: FlowState, station: Station): FlowItem[] {
  return state.order.map((k) => state.items[k]).filter((item) => item.station === station);
}
