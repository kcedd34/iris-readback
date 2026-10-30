import { createContext, useContext, useEffect, useRef, useState, type ReactNode } from "react";
import { getJson } from "../api/client";
import type { FlowItem } from "./types";

export interface NotificationEvent {
  event: string;
  recipient: string;
  level: number;
  at: string;
  detail: string;
}

/** What the read-only decision view says about a case: its value and unit, and the escalation events of its alert. */
export interface CaseDetails {
  value: string;
  unit: string;
  convertedValue: string;
  convertedUnit: string;
  notifications: NotificationEvent[];
}

interface DecisionView {
  originalValue?: string;
  originalUnit?: string;
  convertedValue?: string;
  convertedUnit?: string;
  notifications?: NotificationEvent[];
}

export async function fetchDetails(controlId: string): Promise<CaseDetails> {
  const view = await getJson<DecisionView>(`/readback/api/decisions/${encodeURIComponent(controlId)}`);
  return {
    value: view.originalValue ?? "",
    unit: view.originalUnit ?? "",
    convertedValue: view.convertedValue ?? "",
    convertedUnit: view.convertedUnit ?? "",
    notifications: view.notifications ?? [],
  };
}

const Details = createContext<Record<string, CaseDetails>>({});
export const useCaseDetails = (controlId: string): CaseDetails | undefined => useContext(Details)[controlId];

const MAX_IDS = 80;

/** Loads the value of each case on screen once, two at a time. A case that cannot be loaded is tried again later. */
export function DetailsProvider({ items, children }: { items: FlowItem[]; children: ReactNode }) {
  const [details, setDetails] = useState<Record<string, CaseDetails>>({});
  const inFlight = useRef(new Set<string>());
  const failedAt = useRef(new Map<string, number>());
  const ids = [...new Set(items.filter((i) => i.route !== undefined).map((i) => i.controlId))].slice(0, MAX_IDS);
  const key = ids.join("|");

  useEffect(() => {
    let live = true;
    const todo = ids.filter((id) => !(id in details) && !inFlight.current.has(id) && Date.now() - (failedAt.current.get(id) ?? 0) > 15000);
    const run = async (id: string) => {
      inFlight.current.add(id);
      try {
        const loaded = await fetchDetails(id);
        if (live) setDetails((d) => ({ ...d, [id]: loaded }));
      } catch {
        failedAt.current.set(id, Date.now());
      } finally {
        inFlight.current.delete(id);
      }
    };
    void (async () => {
      for (let i = 0; i < todo.length && live; i += 2) await Promise.all(todo.slice(i, i + 2).map(run));
    })();
    return () => {
      live = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key]);

  return <Details.Provider value={details}>{children}</Details.Provider>;
}

/** The escalation events of one case, refreshed while it is open on the alerts screen. */
export function useTimeline(controlId: string | undefined, everyMs = 3000): NotificationEvent[] | null {
  const [events, setEvents] = useState<NotificationEvent[] | null>(null);
  useEffect(() => {
    setEvents(null);
    if (!controlId) return;
    let live = true;
    let timer: number | undefined;
    const load = async () => {
      try {
        const d = await fetchDetails(controlId);
        if (live) setEvents(d.notifications);
      } catch {
        /* keep what is shown */
      }
      if (live) timer = window.setTimeout(load, everyMs);
    };
    void load();
    return () => {
      live = false;
      if (timer !== undefined) window.clearTimeout(timer);
    };
  }, [controlId, everyMs]);
  return events;
}

/** The number of read-backs confirmed so far, from the product's own status. */
export function useConfirmedCount(everyMs = 5000): number | null {
  const [count, setCount] = useState<number | null>(null);
  useEffect(() => {
    let live = true;
    let timer: number | undefined;
    const load = async () => {
      try {
        const s = await getJson<{ alerts?: { closed?: number } }>("/readback/api/status");
        if (live && typeof s.alerts?.closed === "number") setCount(s.alerts.closed);
      } catch {
        /* keep the last count */
      }
      if (live) timer = window.setTimeout(load, everyMs);
    };
    void load();
    return () => {
      live = false;
      if (timer !== undefined) window.clearTimeout(timer);
    };
  }, [everyMs]);
  return count;
}

export function ValueBlock({ details, large }: { details: CaseDetails | undefined; large?: boolean }) {
  if (!details || !details.value) return <span className={`value${large ? " value-lg" : ""} value-none`} aria-label="value not loaded yet">–</span>;
  const converted = details.convertedValue && (details.convertedValue !== details.value || details.convertedUnit !== details.unit);
  return (
    <span className={`value${large ? " value-lg" : ""}`}>
      <span className="value-num num">{details.value}</span>
      <span className="value-unit">{details.unit}</span>
      {converted && <span className="value-conv num">= {details.convertedValue} {details.convertedUnit}</span>}
    </span>
  );
}
