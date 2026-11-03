import { useCallback, useEffect, useRef, useState } from "react";
import { ApiError, getJson, postJson } from "../api/client";
import { signOut } from "../api/session";
import { useSessionUser } from "../api/useSession";
import { SeverityBadge } from "../components/SeverityBadge";
import type { TaskView } from "./types";

type Outcome = { kind: "mismatch"; typed: string } | { kind: "refused" } | { kind: "error"; text: string } | null;

const PLAIN_NUMBER = /^-?\d+(\.\d+)?$/;

/** What the person types is checked here only for shape; whether it matches is decided by the product. */
export function checkEntry(valueText: string, told: string, value: string): string {
  if (!told.trim()) return "Enter whom you told.";
  if (!value.trim()) return "Enter the value you repeated.";
  if (PLAIN_NUMBER.test(valueText.trim()) && !PLAIN_NUMBER.test(value.trim())) {
    return value.includes(",") ? "Use a dot as the decimal separator." : "Enter the value as a number, without a unit.";
  }
  return "";
}

export function TaskScreen({ decisionId, onDone }: { decisionId: number; onDone?: () => void }) {
  const user = useSessionUser();
  const [view, setView] = useState<TaskView | null>(null);
  const [loadError, setLoadError] = useState("");
  const [told, setTold] = useState("");
  const [value, setValue] = useState("");
  const [fieldError, setFieldError] = useState("");
  const [outcome, setOutcome] = useState<Outcome>(null);
  const [busy, setBusy] = useState(false);
  const valueRef = useRef<HTMLInputElement>(null);

  const load = useCallback(async (): Promise<TaskView | null> => {
    try {
      const fresh = await getJson<TaskView>(`/readback/api/taskview/${decisionId}`, { auth: true });
      setView(fresh);
      setLoadError("");
      return fresh;
    } catch (e) {
      setLoadError(e instanceof Error ? e.message : "The task could not be loaded.");
      return null;
    }
  }, [decisionId]);

  useEffect(() => {
    void load();
  }, [load, user]);

  if (loadError && !view) return <p className="error" role="alert">{loadError}</p>;
  if (!view) return <p role="status">Loading the read-back task.</p>;

  const completed = view.state === "completed";
  const otherAssignee = !completed && view.assignedTo && user && view.assignedTo !== user;

  const confirm = async () => {
    const problem = checkEntry(view.valueText, told, value);
    setFieldError(problem);
    if (problem) {
      valueRef.current?.focus();
      return;
    }
    if (!view.assignedTo) {
      setOutcome({ kind: "error", text: "This task is not assigned to anyone yet." });
      return;
    }
    setBusy(true);
    setOutcome(null);
    const before = view.attemptCount;
    const path = `/workflow/rest/task/${encodeURIComponent(`${view.taskId}||${view.assignedTo}`)}`;
    const body = { action: "Communicated", formFields: { ToldWho: told.trim(), ReadbackValue: value.trim() } };
    try {
      await postJson(path, body, { auth: true });
    } catch (e) {
      // The product refuses a confirmation with a 500, never a 404; a 404 here is the platform's occasional wrong
      // answer to a correct request (docs/probes.md, feature 5), so the same request is sent once more.
      if (e instanceof ApiError && e.status === 404) {
        await new Promise((resolve) => setTimeout(resolve, 500));
        try {
          await postJson(path, body, { auth: true });
        } catch {
          /* the outcome is read from what the product recorded, below */
        }
      }
      /* Whatever the answer was, the outcome is read from what the product recorded, below. */
    }
    const after = await load();
    setBusy(false);
    if (!after) return setOutcome({ kind: "error", text: "The result of the confirmation could not be read back from the product." });
    if (after.state === "completed") {
      setOutcome(null);
      onDone?.();
    } else if (after.attemptCount > before) {
      setOutcome({ kind: "mismatch", typed: value.trim() });
    } else {
      setOutcome({ kind: "refused" });
    }
  };

  const converted = view.convertedValue && (view.convertedValue !== view.valueText || view.convertedUnit !== view.unit);

  return (
    <div className="task">
      <div className="task-head">
        <SeverityBadge kind="critical" />
        <span className="num task-case">Case {view.controlId}</span>
        <span>{view.analyteName || view.analyteCode}</span>
      </div>
      <p className="task-patient">Synthetic patient <strong className="num">{view.patientId}</strong></p>
      <div className="task-value" aria-label="Value to read back">
        <span className="task-label">Value to read back</span>
        <span className="task-number num">{view.valueText}</span> <span className="task-unit">{view.unit}</span>
        {converted && <p className="task-converted">In the analyte's reference unit: <span className="num">{view.convertedValue} {view.convertedUnit}</span></p>}
      </div>
      {view.mode === "replay" && <p className="task-replay">Replay mode: the agent's answer below comes from a stored recording.</p>}

      <section aria-labelledby="why-rules">
        <h3 id="why-rules">Why this is critical (from the rules)</h3>
        {view.ruleLines && view.ruleLines.length > 0
          ? <ul className="task-rules">{view.ruleLines.map((line) => <li key={line}>{line}</li>)}</ul>
          : <p>{view.reason || "No reason recorded."}</p>}
        {view.floorNote && !(view.ruleLines && view.ruleLines.length > 0) && <p className="task-meta">{view.floorNote}</p>}
      </section>

      <section aria-labelledby="why-agent">
        <h3 id="why-agent">What the agent said (not a rule)</h3>
        {view.agent ? (
          <>
            <p><strong>{view.agent.decision}</strong>, severity <span className="num">{view.agent.severity}</span>, confidence {view.agent.confidence}</p>
            <p>{view.agent.rationale}</p>
            {view.agent.evidence.length > 0 && (
              <>
                <p className="task-meta">Evidence the agent cited:</p>
                <ul className="task-evidence">
                  {(view.agent.evidenceItems && view.agent.evidenceItems.length > 0 ? view.agent.evidenceItems : view.agent.evidence.map((id) => ({ id, text: "" }))).map((e) => (
                    <li key={e.id}>{e.text ? <>{e.text} <code className="task-evidence-id">{e.id}</code></> : <code className="task-evidence-id">{e.id}</code>}</li>
                  ))}
                </ul>
              </>
            )}
          </>
        ) : (
          <p>There is no agent rationale: {view.agentAbsent ? `${view.agentAbsent.failureKind}${view.agentAbsent.failureReason ? ` (${view.agentAbsent.failureReason})` : ""}` : "the agent gave no usable answer"}. The case is critical by the rules alone.</p>
        )}
      </section>

      {completed ? (
        <section className="task-done" aria-labelledby="done-title" role="status">
          <h3 id="done-title">Read-back confirmed</h3>
          <p>Confirmed by <strong>{view.confirmedBy}</strong> at <span className="num">{view.confirmedAt}</span>. The repeated value matched.</p>
        </section>
      ) : (
        <form className="task-form" onSubmit={(e) => { e.preventDefault(); void confirm(); }} noValidate>
          <h3>Confirm the read-back</h3>
          {otherAssignee && (
            <p className="task-note" role="status">
              This task is assigned to <strong>{view.assignedTo}</strong>. You are signed in as <strong>{user}</strong>.{" "}
              <button type="button" onClick={() => signOut()}>Sign out to switch account</button>
            </p>
          )}
          {!view.assignedTo && <p className="task-note">This task is not assigned to anyone yet.</p>}
          <label htmlFor="told">Who you told</label>
          <input id="told" value={told} onChange={(e) => setTold(e.target.value)} autoComplete="off" aria-describedby="field-error" />
          <label htmlFor="repeated">Value you repeated</label>
          <input id="repeated" ref={valueRef} value={value} onChange={(e) => setValue(e.target.value)} inputMode="decimal" autoComplete="off" aria-describedby="field-error" />
          <p id="field-error" className="error" role="alert">{fieldError}</p>
          <button type="submit" disabled={busy}>{busy ? "Checking" : "Confirm read-back"}</button>
          <p className="task-meta">Attempts so far: <span className="num">{view.attemptCount}</span></p>
          {outcome?.kind === "mismatch" && (
            <div className="task-mismatch" role="alert">
              <p><strong>The value does not match. The task is still open.</strong></p>
              <p>You typed <span className="num task-typed">{outcome.typed}</span>; the value to read back is <span className="num task-expected">{view.valueText}</span>.</p>
            </div>
          )}
          {outcome?.kind === "refused" && <p className="error" role="alert">The product did not accept this: your account is not allowed to confirm this read-back. The task is unchanged.</p>}
          {outcome?.kind === "error" && <p className="error" role="alert">{outcome.text}</p>}
        </form>
      )}
    </div>
  );
}
