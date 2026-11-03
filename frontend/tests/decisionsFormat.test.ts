import { describe, expect, it } from "vitest";
import { agentText, clip, compositionLine, conversionText, costText } from "../src/decisions/format";
import type { FeedItem } from "../src/decisions/types";

const base: FeedItem = {
  decisionId: 1,
  controlId: "RB2026-00001",
  analyte: "Potassium",
  value: { text: "6.9", unit: "mmol/L" },
  decidedAt: "2026-11-02 12:00:00",
  mode: "live",
  route: "readback",
  floor: { severity: 3, ruleId: "crit-potassium", note: "critical by rule" },
  agent: { decision: "CRITICAL", severity: 3, confidence: "high", rationale: "read the history", evidence: ["current-result"] },
  final: { severity: 3 },
  held: false,
  cost: { tokens: 2800, latencyMs: 2400, model: "gpt-5.4-mini", usd: 0.0027 },
  rounds: 2,
  toolCallCount: 4,
  toolFailureCount: 0,
};

describe("the composition line", () => {
  it("states floor, agent and final", () => {
    expect(compositionLine(base)).toBe("floor 3 · agent 3 · final 3");
  });
  it("adds the held seal when the floor held back a lower answer", () => {
    const held = { ...base, agent: { decision: "NON_CRITICAL", severity: 0, confidence: "high" }, held: true };
    expect(compositionLine(held)).toBe("floor 3 · agent 0 · final 3 · held");
  });
  it("says none when the agent gave no answer", () => {
    expect(compositionLine({ ...base, agent: { failureKind: "timeout" }, route: "review" })).toBe("floor 3 · agent none · final 3");
  });
});

describe("the cost cell", () => {
  it("shows dollars for a live decision", () => {
    expect(costText(base)).toBe("$0.00270");
  });
  it("shows replay, never a cost, for a replayed decision", () => {
    expect(costText({ ...base, mode: "replay", cost: { ...base.cost, usd: null } })).toBe("replay");
    expect(costText({ ...base, mode: "replay" })).toBe("replay");
  });
});

describe("the conversion cell", () => {
  it("is empty when nothing was converted", () => {
    expect(conversionText(base)).toBe("");
  });
  it("shows the original and the converted value", () => {
    const converted = { ...base, conversion: { original: "5.1 mmol/L", converted: "91.9", unit: "mg/dL", standard: "reference unit of the analyte" } };
    expect(conversionText(converted)).toBe("5.1 mmol/L → 91.9 mg/dL");
  });
});

describe("the agent cell", () => {
  it("names the answer and the confidence", () => {
    expect(agentText(base)).toBe("CRITICAL, high confidence");
  });
  it("names why there is no answer", () => {
    expect(agentText({ ...base, agent: { failureKind: "provider-error" } })).toBe("no answer (provider-error)");
    expect(agentText({ ...base, agent: { failureKind: "not-called" } })).toBe("not called");
  });
  it("clips a long rationale", () => {
    expect(clip("a".repeat(300), 220).length).toBe(220);
    expect(clip("short", 220)).toBe("short");
  });
});
