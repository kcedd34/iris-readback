import type { FlowItem } from "./types";
import { SeverityBadge } from "../components/SeverityBadge";
import { PersonIcon } from "../components/icons";
import { ValueBlock, useCaseDetails } from "./details";
import { formatWait, secondsSince } from "./time";

function Row({ item, now, onSelect }: { item: FlowItem; now: number; onSelect?: (item: FlowItem) => void }) {
  const details = useCaseDetails(item.controlId);
  return (
    <li>
      <SeverityBadge kind="critical" />
      <ValueBlock details={details} />
      <span className="num waiting-id">{item.controlId}</span>
      <span>{item.analyte}</span>
      <span className="waiting-meta">waiting <strong className="num wait-time">{formatWait(secondsSince(item.waitingSince, now))}</strong></span>
      <span className="waiting-meta"><PersonIcon /> {item.assignedTo ? `assigned to ${item.assignedTo}` : "not assigned yet"}</span>
      {item.alertState === "exhausted" && <span className="waiting-meta">alert reached the last person</span>}
      {onSelect && <button type="button" onClick={() => onSelect(item)}>Open read-back</button>}
    </li>
  );
}

/** The cases waiting for a person, as text, so the critical state never depends on the canvas alone. */
export function WaitingList({ items, total, now, onSelect }: { items: FlowItem[]; total: number; now: number; onSelect?: (item: FlowItem) => void }) {
  return (
    <section className="waiting" aria-labelledby="waiting-title">
      <h2 id="waiting-title">Waiting for a person <span className="num">({total})</span></h2>
      {items.length === 0 ? (
        <p className="empty">No critical case is waiting.</p>
      ) : (
        <ol className="waiting-list">
          {items.map((item) => (
            <Row key={item.key} item={item} now={now} onSelect={onSelect} />
          ))}
        </ol>
      )}
      {total > items.length && <p className="empty">Showing {items.length} of {total} waiting cases.</p>}
    </section>
  );
}
