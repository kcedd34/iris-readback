import type { FlowItem } from "./types";
import { SeverityBadge, kindOfRoute } from "../components/SeverityBadge";
import { ValueBlock, useCaseDetails } from "./details";
import { useClock } from "./now";
import { formatWait, secondsSince } from "./time";

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
      {item.reason && item.station !== "intake" && item.station !== "agent" && item.station !== "confirmed" && <span className="chip-meta chip-reason">{item.reason}</span>}
      {item.failureKind && <span className="chip-meta">agent step: {item.failureKind}</span>}
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
