import { useCallback, useEffect, useRef, useState } from "react";
import { getJson } from "../api/client";
import type { Feed, FeedItem, Seals } from "./types";

const PAGE = 50;

/** The feed of decisions: the newest page refreshed every few seconds, and older pages on request. The last known list stays on screen when a refresh fails. */
export function useDecisions(everyMs = 5000) {
  const [items, setItems] = useState<FeedItem[] | null>(null);
  const [more, setMore] = useState(false);
  const [stale, setStale] = useState(false);
  const older = useRef<FeedItem[]>([]);
  const [loadingOlder, setLoadingOlder] = useState(false);

  useEffect(() => {
    let live = true;
    let timer: number | undefined;
    const load = async () => {
      try {
        const feed = await getJson<Feed>(`/readback/api/decisions?limit=${PAGE}`);
        if (live) {
          const ids = new Set(feed.items.map((i) => i.decisionId));
          setItems([...feed.items, ...older.current.filter((i) => !ids.has(i.decisionId))]);
          setMore(older.current.length === 0 ? feed.more : true);
          setStale(false);
        }
      } catch {
        if (live) setStale(true);
      }
      if (live) timer = window.setTimeout(load, everyMs);
    };
    void load();
    return () => {
      live = false;
      if (timer !== undefined) window.clearTimeout(timer);
    };
  }, [everyMs]);

  const loadOlder = useCallback(async () => {
    if (!items || items.length === 0) return;
    setLoadingOlder(true);
    try {
      const last = items[items.length - 1].decisionId;
      const feed = await getJson<Feed>(`/readback/api/decisions?limit=${PAGE}&before=${last}`);
      older.current = [...older.current, ...feed.items];
      setItems((current) => [...(current ?? []), ...feed.items]);
      setMore(feed.more);
    } catch {
      setStale(true);
    } finally {
      setLoadingOlder(false);
    }
  }, [items]);

  return { items, more, stale, loadOlder, loadingOlder };
}

/** The production's state and the mode and model, for the seals at the top. Refreshed every few seconds; null until the first answer. */
export function useSeals(everyMs = 5000): Seals | null {
  const [seals, setSeals] = useState<Seals | null>(null);
  useEffect(() => {
    let live = true;
    let timer: number | undefined;
    const load = async () => {
      try {
        const s = await getJson<{ productionRunning?: boolean; mode?: string; model?: string }>("/readback/api/status");
        if (live) setSeals({ productionRunning: !!s.productionRunning, mode: s.mode === "live" ? "live" : "replay", model: s.model ?? "" });
      } catch {
        if (live) setSeals(null);
      }
      if (live) timer = window.setTimeout(load, everyMs);
    };
    void load();
    return () => {
      live = false;
      if (timer !== undefined) window.clearTimeout(timer);
    };
  }, [everyMs]);
  return seals;
}
