import type { FlowItem } from "./types";
import { formatWait, secondsSince } from "./time";

/**
 * The instrument's top readings. "Active escalations" counts open alerts that moved past the first person (the first
 * window ran out); "over target" counts those that reached the last person with nobody left to alert. All come from
 * the product's own alert state, none is computed from a number the interface invented.
 */
export function Indicators({ waiting, total, confirmed, now }: { waiting: FlowItem[]; total: number; confirmed: number | null; now: number }) {
  const over = waiting.filter((i) => i.alertState === "exhausted").length;
  const active = waiting.filter((i) => (i.alertLevel ?? 0) >= 1).length;
  const longest = waiting.reduce<number | null>((max, i) => {
    const s = secondsSince(i.waitingSince, now);
    return s !== null && (max === null || s > max) ? s : max;
  }, null);
  const tiles: Array<{ label: string; value: string; tone?: "critical" | "none" }> = [
    { label: "Awaiting action", value: String(Math.max(total, waiting.length)), tone: waiting.length ? "critical" : "none" },
    { label: "Confirmed", value: confirmed === null ? "–" : String(confirmed) },
    { label: "Over target", value: String(over), tone: over ? "critical" : "none" },
    { label: "Active escalations", value: String(active), tone: active ? "critical" : "none" },
    { label: "Longest wait", value: longest === null ? "–" : formatWait(longest), tone: longest !== null && active ? "critical" : "none" },
  ];
  return (
    <ul className="indicators" aria-label="Readings">
      {tiles.map((t) => (
        <li key={t.label} className={t.tone === "critical" ? "ind-hot" : ""}>
          <span className="ind-value num">{t.value}</span>
          <span className="ind-label">{t.label}</span>
        </li>
      ))}
    </ul>
  );
}
