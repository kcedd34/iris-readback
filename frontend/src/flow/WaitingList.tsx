import type { FlowItem } from "./types";
import { SeverityBadge } from "../components/SeverityBadge";
import { PersonIcon } from "../components/icons";

function waited(since: string | undefined, now: number): string {
  if (!since) return "";
  const started = Date.parse(since.replace(" ", "T") + "Z");
  if (Number.isNaN(started)) return "";
  const seconds = Math.max(0, Math.round((now - started) / 1000));
  if (seconds < 60) return `${seconds} s`;
  const minutes = Math.floor(seconds / 60);
  return minutes < 60 ? `${minutes} min ${seconds % 60} s` : `${Math.floor(minutes / 60)} h ${minutes % 60} min`;
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
            <li key={item.key}>
              <SeverityBadge kind="critical" />
              <span className="num waiting-id">{item.controlId}</span>
              <span>{item.analyte}</span>
              <span className="waiting-meta">waiting {waited(item.waitingSince, now) || "just now"}</span>
              <span className="waiting-meta"><PersonIcon /> {item.assignedTo ? `assigned to ${item.assignedTo}` : "not assigned yet"}</span>
              {item.alertState === "exhausted" && <span className="waiting-meta">alert reached the last person</span>}
              {onSelect && <button type="button" onClick={() => onSelect(item)}>Open read-back</button>}
            </li>
          ))}
        </ol>
      )}
      {total > items.length && <p className="empty">Showing {items.length} of {total} waiting cases.</p>}
    </section>
  );
}
