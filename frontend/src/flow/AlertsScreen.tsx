import { useMemo, useState } from "react";
import type { FlowItem } from "./types";
import { SeverityBadge } from "../components/SeverityBadge";
import { PersonIcon } from "../components/icons";
import { ValueBlock, useCaseDetails, useTimeline, type NotificationEvent } from "./details";
import { clock, formatWait, offset, secondsSince } from "./time";

const EVENT: Record<string, string> = {
  opened: "Alert opened",
  "delivery-attempt": "Pager message sent",
  "delivery-receipt": "Delivery receipt",
  "delivery-failed": "Delivery failed",
  escalated: "Escalated",
  exhausted: "Escalation exhausted",
  confirmed: "Read-back confirmed",
};

/** Most urgent first: the alerts that ran out of people, then the escalated, then the longest wait. */
function byUrgency(now: number) {
  return (a: FlowItem, b: FlowItem) => {
    const rank = (i: FlowItem) => (i.alertState === "exhausted" ? 2 : (i.alertLevel ?? 0) >= 1 ? 1 : 0);
    return rank(b) - rank(a) || (secondsSince(b.waitingSince, now) ?? 0) - (secondsSince(a.waitingSince, now) ?? 0);
  };
}

function stage(item: FlowItem): { label: string; hot: boolean } {
  if (item.alertState === "exhausted") return { label: "Last person reached", hot: true };
  if ((item.alertLevel ?? 0) >= 1) return { label: `Escalated to level ${(item.alertLevel ?? 0) + 1}`, hot: true };
  return { label: "First person", hot: false };
}

function QueueRow({ item, now, selected, onPick, onOpen }: { item: FlowItem; now: number; selected: boolean; onPick: () => void; onOpen: () => void }) {
  const details = useCaseDetails(item.controlId);
  const st = stage(item);
  return (
    <li className={`q-row${selected ? " q-selected" : ""}${st.hot ? " q-hot" : ""}`}>
      <span className="q-band" aria-hidden="true" />
      <div className="q-cell q-sev"><SeverityBadge kind="critical" /></div>
      <div className="q-cell q-exam"><strong>{item.analyte}</strong><span className="num q-id">{item.controlId}</span></div>
      <div className="q-cell q-value"><ValueBlock details={details} large /></div>
      <div className="q-cell q-wait"><span className="q-wait-time num">{formatWait(secondsSince(item.waitingSince, now))}</span><span className="q-sub">waiting</span></div>
      <div className="q-cell q-stage"><span className={`pill${st.hot ? " pill-hot" : ""}`}>{st.label}</span></div>
      <div className="q-cell q-owner"><PersonIcon /> {item.assignedTo || "not assigned yet"}</div>
      <div className="q-cell q-actions">
        <button type="button" onClick={onPick} aria-pressed={selected}>Timeline</button>
        <button type="button" onClick={onOpen}>Open read-back</button>
      </div>
    </li>
  );
}

function Timeline({ item, events }: { item: FlowItem; events: NotificationEvent[] | null }) {
  return (
    <section className="timeline" aria-labelledby="timeline-title">
      <h2 id="timeline-title">Escalation timeline</h2>
      <p className="q-sub"><span className="num">{item.controlId}</span> · {item.analyte}</p>
      {events === null ? (
        <p className="empty">Loading the alert history.</p>
      ) : events.length === 0 ? (
        <p className="empty">No alert event is recorded for this case yet.</p>
      ) : (
        <ol className="tl">
          {events.map((e, i) => (
            <li key={`${e.at}-${i}`} className={`tl-${e.event}`}>
              <span className="tl-time num">{clock(e.at)}<small>{offset(e.at, events[0].at)}</small></span>
              <span className="tl-dot" aria-hidden="true" />
              <span className="tl-body">
                <strong>{EVENT[e.event] ?? e.event}</strong>
                <span>{e.recipient ? `${e.recipient}, level ${e.level + 1}` : `level ${e.level + 1}`}</span>
                {e.detail && <span className="q-sub">{e.detail}</span>}
              </span>
            </li>
          ))}
        </ol>
      )}
    </section>
  );
}

/** The operational screen: the queue of critical results waiting for a person, ordered by urgency, with the alert history of the open one. */
export function AlertsScreen({ items, total, now, onOpen }: { items: FlowItem[]; total: number; now: number; onOpen: (item: FlowItem) => void }) {
  const ordered = useMemo(() => [...items].sort(byUrgency(now)), [items, now]);
  const [pick, setPick] = useState<string | null>(null);
  const current = ordered.find((i) => i.key === pick) ?? ordered[0];
  const events = useTimeline(current?.controlId);
  return (
    <div className="alerts">
      <section className="queue" aria-labelledby="queue-title">
        <h2 id="queue-title">Critical results waiting for a person <span className="num">({Math.max(total, items.length)})</span></h2>
        {ordered.length === 0 ? (
          <p className="empty queue-empty">No critical result is waiting. A critical value stops here until a person repeats it correctly.</p>
        ) : (
          <ol className="q-list">
            <li className="q-head" aria-hidden="true">
              <span /><span>Severity</span><span>Exam</span><span>Value</span><span>Wait</span><span>Escalation</span><span>Owner</span><span>Action</span>
            </li>
            {ordered.map((item) => (
              <QueueRow key={item.key} item={item} now={now} selected={item.key === current?.key} onPick={() => setPick(item.key)} onOpen={() => onOpen(item)} />
            ))}
          </ol>
        )}
        {total > items.length && <p className="empty">Showing {items.length} of {total} waiting cases.</p>}
      </section>
      {current && <Timeline item={current} events={events} />}
    </div>
  );
}
