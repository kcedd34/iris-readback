import { useState } from "react";
import { ApiError } from "../api/client";
import { submitScenario, useScenarios } from "./useFlow";

/** Submits one of the shipped synthetic scenarios. Never free text: only the id of a scenario the product lists. */
export function ScenarioPicker({ onSubmitted }: { onSubmitted: (controlIds: string[], analyte: string) => void }) {
  const { scenarios, error } = useScenarios();
  const [chosen, setChosen] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const current = scenarios.find((s) => s.id === (chosen || scenarios[0]?.id));

  const submit = async () => {
    if (!current) return;
    setBusy(true);
    setMessage("");
    try {
      const ids = await submitScenario(current.id);
      onSubmitted(ids, current.analyte);
    } catch (e) {
      setMessage(e instanceof ApiError ? e.message : "The result could not be submitted.");
    } finally {
      setBusy(false);
    }
  };

  return (
    <form className="picker" onSubmit={(e) => { e.preventDefault(); void submit(); }}>
      <label htmlFor="scenario">Send a synthetic result into the production</label>
      <div className="picker-row">
        <select id="scenario" value={current?.id ?? ""} onChange={(e) => setChosen(e.target.value)} disabled={!scenarios.length}>
          {scenarios.map((s) => (
            <option key={s.id} value={s.id}>{s.label}</option>
          ))}
        </select>
        <button type="submit" disabled={busy || !current}>{busy ? "Sending" : "Send result"}</button>
      </div>
      {current && <p className="picker-note">The policy expects: <strong>{current.expected.replace("_", " ").toLowerCase()}</strong>. Synthetic data only.</p>}
      {(message || error) && <p className="error" role="alert">{message || error}</p>}
    </form>
  );
}
