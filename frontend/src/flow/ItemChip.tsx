import type { FlowItem } from "./types";
import { SeverityBadge, kindOfRoute } from "../components/SeverityBadge";
import { ValueBlock, useCaseDetails } from "./details";
import { useClock } from "./now";
import { formatWait, secondsSince } from "./time";
import { TOOL_STEP_MS } from "./reducer";
import type { ToolCallEntry } from "./types";

const TOOL_NAMES: Record<string, string> = {
  get_patient_history: "Patient history",
  get_delta_assessment: "Change against history",
  search_policy: "Laboratory policy",
  get_sample_quality: "Sample quality",
};
export const toolName = (tool: string): string => TOOL_NAMES[tool] ?? tool;
const STATUS_TEXT: Record<string, string> = { ok: "", refused: "refused by the policy", failed: "failed", "unknown-tool": "no such tool" };

/** The tool calls inside the agent node: lit one after the other, in the order the agent made them. A refused or failed call is
 * marked by an icon and a word, not by colour alone, and looks different from a call that answered. */
export function ToolSteps({ calls, since, animate }: { calls: ToolCallEntry[]; since: number; animate: boolean }) {
  const now = useClock();
  const lit = animate ? Math.min(calls.length, Math.max(1, Math.floor((now - since) / TOOL_STEP_MS) + 1)) : calls.length;
  return (
    <ol className="substeps" aria-label="What the agent looked up">
      {calls.slice(0, lit).map((c) => (
        <li key={c.seq} className={`substep substep-${c.status === "ok" ? "ok" : "bad"}`}>
          <span className="substep-mark" aria-hidden="true">{c.status === "ok" ? "\u2192" : "\u2715"}</span>
          <span className="substep-name">{toolName(c.tool)}</span>
          <span className="substep-what">{c.status === "ok" ? c.summary : STATUS_TEXT[c.status] ?? c.status}</span>
        </li>
      ))}
    </ol>
  );
}

/** What the agent read that led to its answer, in a short phrase, or "" when it read nothing that answered. */
export function readPhrase(calls: ToolCallEntry[] | undefined): string {
  const ok = (calls ?? []).filter((c) => c.status === "ok" && c.summary);
  if (!ok.length) return "";
  return "after reading: " + ok.map((c) => `${c.summary} (${toolName(c.tool).toLowerCase()})`).join(", ");
}

/** One case at a station: severity (colour, icon and text), the value as the main figure, case id and analyte. Never a patient identifier. */
export function ItemChip({ item, onSelect }: { item: FlowItem; onSelect?: (item: FlowItem) => void }) {
  const kind = kindOfRoute(item.route);
  const pending = item.route === undefined;
  const details = useCaseDetails(item.controlId);
  const now = useClock();
  const waiting = item.station === "readback" && item.path.length === 0;
  const openable = onSelect && item.route === "readback" && item.station !== "intake" && item.station !== "agent";
  const body = (
    <>
      <span className="chip-top">
        {pending ? <span className="sev sev-pending"><span>Deciding</span></span> : <SeverityBadge kind={item.station === "confirmed" ? "normal" : kind} label={item.station === "confirmed" ? "Confirmed" : undefined} />}
        {waiting && <span className="chip-wait num">{formatWait(secondsSince(item.waitingSince, now))}</span>}
      </span>
      {!pending && <ValueBlock details={details} />}
      <span className="chip-line"><span className="chip-id num">{item.controlId}</span> <span className="chip-meta">{item.analyte}</span></span>
      {item.station === "confirmed" && <span className="chip-meta">{item.confirmedBy ? `by ${item.confirmedBy}, ${item.readbackMatch ? "value matched" : "value did not match"}` : "left read-back"}</span>}
      {item.station === "agent" && item.toolCalls && item.toolCalls.length > 0 && <ToolSteps calls={item.toolCalls} since={item.stationSince} animate={item.replayed} />}
      {item.reason && item.station !== "intake" && item.station !== "agent" && item.station !== "confirmed" && <span className="chip-meta chip-reason">{item.reason}{readPhrase(item.toolCalls) && /^agent raised/.test(item.reason) ? `, ${readPhrase(item.toolCalls)}` : ""}</span>}
      {item.policyRefusal && item.station !== "intake" && item.station !== "agent" && <span className="chip-meta chip-held">The floor held back the agent's lower answer</span>}
      {item.failureKind && item.failureKind !== "floor-policy-refusal" && <span className="chip-meta">agent step: {item.failureKind}</span>}
      {item.replayed && item.station === "agent" && <span className="chip-meta">replay of a recorded decision</span>}
      {item.station === "readback" && item.assignedTo && <span className="chip-meta">assigned to {item.assignedTo}</span>}
    </>
  );
  const cls = `chip chip-${item.station === "confirmed" ? "normal" : pending ? "pending" : kind}`;
  if (openable) {
    return (
      <button type="button" className={`${cls} chip-open`} onClick={() => onSelect(item)} aria-label={`Open the read-back task of case ${item.controlId}`}>
        {body}
      </button>
    );
  }
  return <div className={cls}>{body}</div>;
}
