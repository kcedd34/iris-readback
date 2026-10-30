import { Suspense, lazy, useCallback, useState } from "react";
import { FlowCanvas } from "./flow/FlowCanvas";
import { DemoSequence, useDemoSequence } from "./flow/DemoSequence";
import { ModeBadge, StaleBanner } from "./flow/ModeBadge";
import { ScenarioPicker } from "./flow/ScenarioPicker";
import { StationList } from "./flow/StationList";
import { WaitingList } from "./flow/WaitingList";
import { waitingItems } from "./flow/reducer";
import type { FlowItem } from "./flow/types";
import { useFlow, useNarrow, useNow, usePrefersReducedMotion } from "./flow/useFlow";
import { ThemeSwitch } from "./components/ThemeSwitch";

// The task screen loads on demand, so the panel itself stays light.
const TaskPanel = lazy(() => import("./task/TaskPanel"));

export function App() {
  const { state, dispatch } = useFlow();
  const now = useNow(500);
  const narrow = useNarrow();
  const reducedMotion = usePrefersReducedMotion();
  const [selected, setSelected] = useState<FlowItem | null>(null);
  const onSelect = useCallback((item: FlowItem) => setSelected(item), []);
  const waiting = waitingItems(state);
  const onSubmitted = useCallback((controlIds: string[], analyte: string) => dispatch({ type: "submitted", controlIds, analyte, now: Date.now() }), [dispatch]);
  const demo = useDemoSequence(state, onSubmitted);

  return (
    <div className="app">
      <header className="top">
        <div>
          <h1>Live flow of lab results</h1>
          <p className="lede">A critical value stops at read-back until a person repeats it correctly.</p>
        </div>
        <ThemeSwitch />
      </header>
      <ModeBadge mode={state.mode} />
      <StaleBanner stale={state.stale} />
      <div className="board">
        <div className="board-flow">
          {narrow ? <StationList state={state} onSelect={onSelect} /> : <FlowCanvas state={state} now={now} reducedMotion={reducedMotion} onSelect={onSelect} />}
        </div>
        <div className="board-side">
          <WaitingList items={waiting} total={Math.max(state.waitingTotal, waiting.length)} now={now} onSelect={onSelect} />
          <DemoSequence {...demo} />
          <ScenarioPicker onSubmitted={onSubmitted} />
        </div>
      </div>
      {selected && (
        <Suspense fallback={null}>
          <TaskPanel decisionId={selected.decisionId ?? 0} onClose={() => setSelected(null)} />
        </Suspense>
      )}
    </div>
  );
}
