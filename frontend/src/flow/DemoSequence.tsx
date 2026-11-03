import { useCallback, useEffect, useRef, useState } from "react";
import { ApiError } from "../api/client";
import type { FlowState } from "./types";
import { submitScenario } from "./useFlow";

/** Three shipped scenarios, in order: a critical that stops at read-back, one a person reviews, and one in which the agent tries to lower a critical and the floor holds. */
const SEQUENCE = [
  { id: "potassium-critical-value", analyte: "Potassium" },
  { id: "potassium-borderline", analyte: "Potassium" },
  { id: "potassium-agent-tries-to-lower", analyte: "Potassium" },
];
const GAP_MS = 2600;

type Submitted = (controlIds: string[], analyte: string) => void;

/**
 * Sends the short sequence through the same path as the picker, so what the panel shows is the product's own
 * decisions (replayed from recordings, and labeled so). It runs by itself once when the panel opens empty in
 * replay mode, and again on the button. It is never started in live mode, where a submission calls the provider.
 */
export function useDemoSequence(state: FlowState, onSubmitted: Submitted) {
  const [running, setRunning] = useState(false);
  const [message, setMessage] = useState("");
  const started = useRef(false);
  const busy = useRef(false);
  const live = state.mode === "live";

  const run = useCallback(async () => {
    if (busy.current) return;
    busy.current = true;
    setRunning(true);
    setMessage("");
    try {
      for (let i = 0; i < SEQUENCE.length; i++) {
        if (i > 0) await new Promise((resolve) => window.setTimeout(resolve, GAP_MS));
        const step = SEQUENCE[i];
        onSubmitted(await submitScenario(step.id), step.analyte);
      }
    } catch (e) {
      setMessage(e instanceof ApiError ? e.message : "The demo sequence could not be sent.");
    } finally {
      busy.current = false;
      setRunning(false);
    }
  }, [onSubmitted]);

  const empty = state.started && Object.keys(state.items).length === 0 && state.waitingTotal === 0 && state.inFlightCount === 0;
  useEffect(() => {
    if (started.current || !empty || live) return;
    started.current = true;
    void run();
  }, [empty, live, run]);

  return { run, running, message, live };
}

export function DemoSequence({ run, running, message, live }: ReturnType<typeof useDemoSequence>) {
  if (live) return null;
  return (
    <div className="demo-sequence">
      <button type="button" onClick={() => void run()} disabled={running}>{running ? "Running the demo sequence" : "Run demo sequence"}</button>
      <p className="picker-note">A critical potassium stops at read-back; a borderline one goes to a person to review; in the third the agent tries to lower a critical and the floor holds it. Recorded decisions, synthetic data.</p>
      {message && <p className="error" role="alert">{message}</p>}
    </div>
  );
}
