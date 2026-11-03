import type { FeedItem } from "./types";

/** The composition of one decision as the screen states it: what the floor, the agent and the final answer said, and whether the floor held back the agent. */
export interface Composition {
  floor: string;
  agent: string;
  final: string;
  held: boolean;
}

export function composition(item: FeedItem): Composition {
  const agent = item.agent.failureKind !== undefined ? "none" : String(item.agent.severity ?? 0);
  return { floor: String(item.floor.severity), agent, final: String(item.final.severity), held: item.held };
}

/** The line itself, for a screen reader and for the tests: `floor 3 · agent 0 · final 3 · held`. */
export function compositionLine(item: FeedItem): string {
  const c = composition(item);
  return `floor ${c.floor} · agent ${c.agent} · final ${c.final}${c.held ? " · held" : ""}`;
}

/** The cost of a decision: the estimate in dollars for a live one, the word `replay` for a replayed one, which has no cost of its own. */
export function costText(item: FeedItem): string {
  if (item.mode === "replay" || item.cost.usd === null) return "replay";
  return item.cost.usd < 0.01 ? `$${item.cost.usd.toFixed(5)}` : `$${item.cost.usd.toFixed(4)}`;
}

export function latencyText(ms: number): string {
  return ms >= 1000 ? `${(ms / 1000).toFixed(1)} s` : `${ms} ms`;
}

/** The conversion, when the value was converted to the reference unit: `5.1 mmol/L → 91.9 mg/dL`. Empty when it was not. */
export function conversionText(item: FeedItem): string {
  const c = item.conversion;
  return c ? `${c.original} → ${c.converted} ${c.unit}` : "";
}

/** What the agent said, short: its decision and confidence, or why it gave no answer. */
export function agentText(item: FeedItem): string {
  const a = item.agent;
  if (a.failureKind !== undefined) return a.failureKind === "not-called" ? "not called" : `no answer (${a.failureKind})`;
  return `${a.decision ?? ""}${a.confidence ? `, ${a.confidence} confidence` : ""}`;
}

export function clip(text: string, max: number): string {
  return text.length <= max ? text : `${text.slice(0, max - 1).trimEnd()}…`;
}
