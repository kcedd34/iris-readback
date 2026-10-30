import { useEffect, useReducer, useRef, useState } from "react";
import { getJson, postJson, ApiError } from "../api/client";
import { initialState, reduce } from "./reducer";
import type { FlowSnapshot } from "./types";

export const POLL_MS = 1500;
const TICK_MS = 100;

/** Polls /readback/api/flow, keeps the flow state, and runs the replay choreography clock. */
export function useFlow() {
  const [state, dispatch] = useReducer(reduce, initialState);
  const cursor = useRef<number | null>(null);
  cursor.current = state.cursor;

  useEffect(() => {
    let stopped = false;
    let timer: number | undefined;
    const poll = async () => {
      if (stopped) return;
      if (document.hidden) {
        timer = window.setTimeout(poll, POLL_MS);
        return;
      }
      let again = false;
      try {
        const query = cursor.current === null ? "" : `?after=${cursor.current}`;
        const snapshot = await getJson<FlowSnapshot>(`/readback/api/flow${query}`);
        if (stopped) return;
        dispatch({ type: "snapshot", snapshot, now: Date.now() });
        cursor.current = snapshot.cursor;
        again = snapshot.decided.length >= 200; // a full page: ask again at once
      } catch (error) {
        if (!stopped) dispatch({ type: "stale" });
        if (error instanceof DOMException) return;
      }
      timer = window.setTimeout(poll, again ? 0 : POLL_MS);
    };
    poll();
    return () => {
      stopped = true;
      if (timer !== undefined) window.clearTimeout(timer);
    };
  }, []);

  useEffect(() => {
    const id = window.setInterval(() => dispatch({ type: "tick", now: Date.now() }), TICK_MS);
    return () => window.clearInterval(id);
  }, []);

  return { state, dispatch };
}

export interface Scenario {
  id: string;
  label: string;
  analyte: string;
  expected: string;
  messageCount: number;
}

export function useScenarios() {
  const [scenarios, setScenarios] = useState<Scenario[]>([]);
  const [error, setError] = useState<string>("");
  useEffect(() => {
    let live = true;
    getJson<Scenario[]>("/readback/api/flow/samples")
      .then((list) => live && setScenarios(list))
      .catch((e: unknown) => live && setError(e instanceof ApiError ? e.message : "The scenarios could not be loaded."));
    return () => {
      live = false;
    };
  }, []);
  return { scenarios, error };
}

export async function submitScenario(scenarioId: string): Promise<string[]> {
  const result = await postJson<{ accepted: boolean; controlIds: string[] }>("/readback/api/flow/submit", { scenarioId });
  return result.controlIds;
}

/** A clock that re-renders its user every intervalMs. */
export function useNow(intervalMs: number): number {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const id = window.setInterval(() => setNow(Date.now()), intervalMs);
    return () => window.clearInterval(id);
  }, [intervalMs]);
  return now;
}

export function usePrefersReducedMotion(): boolean {
  const query = "(prefers-reduced-motion: reduce)";
  const [reduced, setReduced] = useState(() => (typeof window.matchMedia === "function" ? window.matchMedia(query).matches : false));
  useEffect(() => {
    if (typeof window.matchMedia !== "function") return;
    const media = window.matchMedia(query);
    const on = () => setReduced(media.matches);
    media.addEventListener("change", on);
    return () => media.removeEventListener("change", on);
  }, []);
  return reduced;
}

export function useNarrow(maxWidth = 720): boolean {
  const query = `(max-width: ${maxWidth}px)`;
  const [narrow, setNarrow] = useState(() => (typeof window.matchMedia === "function" ? window.matchMedia(query).matches : false));
  useEffect(() => {
    if (typeof window.matchMedia !== "function") return;
    const media = window.matchMedia(query);
    const on = () => setNarrow(media.matches);
    media.addEventListener("change", on);
    return () => media.removeEventListener("change", on);
  }, [query]);
  return narrow;
}

