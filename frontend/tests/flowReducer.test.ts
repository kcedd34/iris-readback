import { describe, expect, it } from "vitest";
import { AGENT_DWELL_MS, TOOL_STEP_MS, agentDwellMs, FINISHED_MS, INTAKE_DWELL_MS, MAX_FINISHED, initialState, itemsAt, reduce, waitingItems } from "../src/flow/reducer";
import type { DecidedEntry, FlowSnapshot, WaitingEntry } from "../src/flow/types";

const decided = (id: number, route: string, extra: Partial<DecidedEntry> = {}): DecidedEntry => ({
  decisionId: id, controlId: `C${id}`, analyte: "Potassium", route, finalSeverity: route === "readback" ? 3 : 0, reason: "r", floorNote: "", failureKind: "",
  agentCalled: true, mode: "replay", decidedAt: "2026-10-29 10:00:00", ...extra,
});
const waiting = (id: number, extra: Partial<WaitingEntry> = {}): WaitingEntry => ({
  decisionId: id, controlId: `C${id}`, analyte: "Potassium", since: "2026-10-29 10:00:00", taskId: id, assignedTo: "communicator1", mode: "replay", ...extra,
});
const snap = (parts: Partial<FlowSnapshot> = {}): FlowSnapshot => ({
  mode: "replay", cursor: 0, decided: [], inFlight: [], waiting: [], waitingTotal: parts.waiting ? parts.waiting.length : 0, confirmed: [], ...parts,
});
const apply = (state = initialState, snapshot: FlowSnapshot, now = 0) => reduce(state, { type: "snapshot", snapshot, now });
const tick = (state: typeof initialState, now: number) => reduce(state, { type: "tick", now });

describe("the replay choreography", () => {
  it("holds a replayed decision at intake and at the agent for a minimum visible time, then moves it to its destination", () => {
    let s = apply(initialState, snap({ cursor: 1, decided: [decided(1, "readback")], waiting: [waiting(1)] }), 1000);
    expect(itemsAt(s, "intake")).toHaveLength(1);
    s = tick(s, 1000 + INTAKE_DWELL_MS - 1);
    expect(itemsAt(s, "intake")).toHaveLength(1);
    s = tick(s, 1000 + INTAKE_DWELL_MS);
    expect(itemsAt(s, "agent")).toHaveLength(1);
    expect(itemsAt(s, "agent")[0].replayed).toBe(true);
    s = tick(s, 1000 + INTAKE_DWELL_MS + AGENT_DWELL_MS - 1);
    expect(itemsAt(s, "agent")).toHaveLength(1);
    s = tick(s, 1000 + INTAKE_DWELL_MS + AGENT_DWELL_MS);
    expect(itemsAt(s, "readback")).toHaveLength(1);
  });

  it("never shows a case that waits at read-back as released, reviewed or confirmed", () => {
    let s = apply(initialState, snap({ cursor: 1, decided: [decided(1, "readback")], waiting: [waiting(1)] }), 0);
    for (let t = 0; t <= 5000; t += 100) {
      s = tick(s, t);
      const item = s.items["d1"];
      expect(["intake", "agent", "readback"]).toContain(item.station);
    }
    expect(itemsAt(s, "release")).toHaveLength(0);
    expect(itemsAt(s, "review")).toHaveLength(0);
    expect(itemsAt(s, "confirmed")).toHaveLength(0);
    expect(waitingItems(s)).toHaveLength(1);
  });

  it("lists the waiting case at once, whatever the animation shows", () => {
    const s = apply(initialState, snap({ cursor: 1, decided: [decided(1, "readback")], waiting: [waiting(1)] }), 0);
    expect(waitingItems(s)).toHaveLength(1);
    expect(s.items["d1"].assignedTo).toBe("communicator1");
  });

  it("sends review, recollect advice and release to their stations, review being shared by the first two", () => {
    let s = apply(initialState, snap({ cursor: 3, decided: [decided(1, "review"), decided(2, "recollect"), decided(3, "release")] }), 0);
    s = tick(tick(s, 600), 600 + AGENT_DWELL_MS);
    expect(itemsAt(s, "review").map((i) => i.controlId).sort()).toEqual(["C1", "C2"]);
    expect(itemsAt(s, "release").map((i) => i.controlId)).toEqual(["C3"]);
  });

  it("does not walk a case whose agent was not called through the agent station", () => {
    let s = apply(initialState, snap({ cursor: 1, decided: [decided(1, "review", { agentCalled: false, failureKind: "budget-reached" })] }), 0);
    s = tick(s, INTAKE_DWELL_MS);
    expect(itemsAt(s, "review")).toHaveLength(1);
    expect(s.items["d1"].failureKind).toBe("budget-reached");
  });

  it("shows a live decision at its destination at once", () => {
    const s = apply(initialState, snap({ mode: "live", cursor: 1, decided: [decided(1, "release", { mode: "live" })] }), 0);
    expect(itemsAt(s, "release")).toHaveLength(1);
    expect(s.items["d1"].replayed).toBe(false);
  });
});

describe("waiting cases", () => {
  it("opens a page late with the waiting cases already at read-back", () => {
    const s = apply(initialState, snap({ cursor: 5, waiting: [waiting(4), waiting(5)] }), 0);
    expect(itemsAt(s, "readback")).toHaveLength(2);
  });

  it("removes a waiting case only when the product no longer lists it, and says who confirmed it", () => {
    let s = apply(initialState, snap({ cursor: 1, waiting: [waiting(1)] }), 0);
    s = apply(s, snap({ cursor: 1, waiting: [waiting(1)] }), 1500);
    expect(itemsAt(s, "readback")).toHaveLength(1);
    s = apply(s, snap({ cursor: 1, waiting: [], confirmed: [{ decisionId: 1, controlId: "C1", confirmedBy: "communicator1", confirmedAt: "x", readbackMatch: true }] }), 3000);
    expect(itemsAt(s, "readback")).toHaveLength(0);
    expect(itemsAt(s, "confirmed")[0].confirmedBy).toBe("communicator1");
    expect(itemsAt(s, "confirmed")[0].readbackMatch).toBe(true);
  });

  it("keeps a waiting case forever while it is listed", () => {
    let s = apply(initialState, snap({ cursor: 1, waiting: [waiting(1)] }), 0);
    for (let t = 1000; t < 10 * FINISHED_MS; t += 5000) {
      s = apply(s, snap({ cursor: 1, waiting: [waiting(1)] }), t);
      s = tick(s, t);
    }
    expect(itemsAt(s, "readback")).toHaveLength(1);
  });

  it("does not mark an old waiting case as left when the product's list is cut", () => {
    let s = apply(initialState, snap({ cursor: 3, waiting: [waiting(1), waiting(2), waiting(3)] }), 0);
    // the product now lists only the newest two of three (cut), so case 1 is unknown, not confirmed
    s = apply(s, snap({ cursor: 3, waiting: [waiting(2), waiting(3)], waitingTotal: 3 }), 1500);
    expect(itemsAt(s, "readback").map((i) => i.controlId).sort()).toEqual(["C1", "C2", "C3"]);
  });

  it("keeps two decisions of the same case id as two events", () => {
    const s = apply(initialState, snap({ cursor: 2, decided: [decided(1, "readback", { controlId: "SAME" }), decided(2, "readback", { controlId: "SAME" })], waiting: [waiting(1, { controlId: "SAME" }), waiting(2, { controlId: "SAME" })] }), 0);
    expect(Object.keys(s.items).sort()).toEqual(["d1", "d2"]);
    expect(waitingItems(s)).toHaveLength(2);
  });
});

describe("bursts and finished items", () => {
  it("keeps every waiting case through a burst of 446 results", () => {
    const decidedAll: DecidedEntry[] = [];
    const waitingAll: WaitingEntry[] = [];
    for (let i = 1; i <= 446; i++) {
      const route = i % 3 === 0 ? "readback" : "release";
      decidedAll.push(decided(i, route));
      if (route === "readback") waitingAll.push(waiting(i));
    }
    let s = apply(initialState, snap({ cursor: 446, decided: decidedAll, waiting: waitingAll }), 0);
    for (let t = 0; t < 30000; t += 1000) s = tick(s, t);
    expect(waitingItems(s)).toHaveLength(waitingAll.length);
    const finished = itemsAt(s, "release").length;
    expect(finished).toBeLessThanOrEqual(MAX_FINISHED);
  });

  it("expires a finished item after a while", () => {
    let s = apply(initialState, snap({ cursor: 1, decided: [decided(1, "release")] }), 0);
    s = tick(tick(s, 600), 600 + AGENT_DWELL_MS);
    expect(itemsAt(s, "release")).toHaveLength(1);
    s = tick(s, 600 + AGENT_DWELL_MS + FINISHED_MS + 1);
    expect(itemsAt(s, "release")).toHaveLength(0);
  });
});

describe("in flight, submitted and stale", () => {
  it("shows a result still being decided at the agent station and replaces it with its decision", () => {
    let s = apply(initialState, snap({ mode: "live", inFlight: [{ controlId: "C1", analyte: "Potassium", enteredAt: "t" }] }), 0);
    expect(itemsAt(s, "agent")).toHaveLength(1);
    s = apply(s, snap({ mode: "live", cursor: 1, decided: [decided(1, "readback", { mode: "live" })], waiting: [waiting(1, { mode: "live" })] }), 1500);
    expect(itemsAt(s, "agent")).toHaveLength(0);
    expect(itemsAt(s, "readback")).toHaveLength(1);
  });

  it("shows a submitted case at intake until the product lists it", () => {
    let s = reduce(initialState, { type: "submitted", controlIds: ["C1"], analyte: "Potassium", now: 0 });
    expect(itemsAt(s, "intake")).toHaveLength(1);
    s = apply(s, snap({ cursor: 0 }), 500);
    expect(itemsAt(s, "intake")).toHaveLength(1);
    s = apply(s, snap({ cursor: 1, decided: [decided(1, "readback")], waiting: [waiting(1)] }), 1000);
    expect(Object.keys(s.items)).toEqual(["d1"]);
  });

  it("marks the state stale without changing any item", () => {
    const s = apply(initialState, snap({ cursor: 1, waiting: [waiting(1)] }), 0);
    const stale = reduce(s, { type: "stale" });
    expect(stale.stale).toBe(true);
    expect(stale.items).toEqual(s.items);
    expect(reduce(stale, { type: "snapshot", snapshot: snap({ cursor: 1, waiting: [waiting(1)] }), now: 10 }).stale).toBe(false);
  });
});

describe("the agent's tool calls", () => {
  const calls = [
    { seq: 1, tool: "get_patient_history", status: "ok" as const, summary: "2 earlier results" },
    { seq: 2, tool: "get_delta_assessment", status: "ok" as const, summary: "critical by change" },
  ];

  it("keeps the calls of a decision in the order the agent made them", () => {
    const s = apply(initialState, snap({ cursor: 1, decided: [decided(1, "readback", { toolCalls: calls })], waiting: [waiting(1)] }), 0);
    expect(s.items["d1"].toolCalls?.map((c) => c.tool)).toEqual(["get_patient_history", "get_delta_assessment"]);
  });

  it("carries no calls for a case where the agent called none", () => {
    const s = apply(initialState, snap({ cursor: 1, decided: [decided(1, "release", { toolCalls: [] })] }), 0);
    expect(s.items["d1"].toolCalls).toBeUndefined();
  });

  it("keeps a replayed decision at the agent for one step per call, and a case without calls for the base time only", () => {
    expect(agentDwellMs(0)).toBe(AGENT_DWELL_MS);
    expect(agentDwellMs(2)).toBe(AGENT_DWELL_MS + 2 * TOOL_STEP_MS);
    let s = apply(initialState, snap({ cursor: 1, decided: [decided(1, "readback", { toolCalls: calls })], waiting: [waiting(1)] }), 0);
    s = tick(s, INTAKE_DWELL_MS);
    expect(itemsAt(s, "agent")).toHaveLength(1);
    s = tick(s, INTAKE_DWELL_MS + agentDwellMs(2) - 1);
    expect(itemsAt(s, "agent")).toHaveLength(1);
    s = tick(s, INTAKE_DWELL_MS + agentDwellMs(2));
    expect(itemsAt(s, "readback")).toHaveLength(1);
  });

  it("keeps the floor policy's refusal on the item", () => {
    const s = apply(initialState, snap({ cursor: 1, decided: [decided(1, "readback", { policyRefusal: "refused: the agent answered NON_CRITICAL" })], waiting: [waiting(1)] }), 0);
    expect(s.items["d1"].policyRefusal).toContain("refused");
  });
});
