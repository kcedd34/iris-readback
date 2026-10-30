import { Suspense, lazy, useCallback, useEffect, useState } from "react";
import { AlertsScreen } from "./flow/AlertsScreen";
import { DemoSequence, useDemoSequence } from "./flow/DemoSequence";
import { DetailsProvider, useConfirmedCount } from "./flow/details";
import { FlowCanvas } from "./flow/FlowCanvas";
import { Indicators } from "./flow/Indicators";
import { ModeBadge, StaleBanner } from "./flow/ModeBadge";
import { NowContext } from "./flow/now";
import { ScenarioPicker } from "./flow/ScenarioPicker";
import { StationList } from "./flow/StationList";
import { WaitingList } from "./flow/WaitingList";
import { waitingItems } from "./flow/reducer";
import type { FlowItem } from "./flow/types";
import { useFlow, useNarrow, useNow, usePrefersReducedMotion } from "./flow/useFlow";
import { Brand } from "./components/Brand";
import { ThemeSwitch } from "./components/ThemeSwitch";

// The task screen loads on demand, so the panel itself stays light.
const TaskPanel = lazy(() => import("./task/TaskPanel"));

type Screen = "flow" | "alerts";
const screenOfHash = (): Screen => (window.location.hash === "#/alerts" ? "alerts" : "flow");

export function App() {
  const { state, dispatch } = useFlow();
  const now = useNow(500);
  const narrow = useNarrow();
  const reducedMotion = usePrefersReducedMotion();
  const confirmed = useConfirmedCount();
  const [screen, setScreen] = useState<Screen>(screenOfHash);
  const [selected, setSelected] = useState<FlowItem | null>(null);
  const onSelect = useCallback((item: FlowItem) => setSelected(item), []);
  const waiting = waitingItems(state);
  const total = Math.max(state.waitingTotal, waiting.length);
  const onSubmitted = useCallback((controlIds: string[], analyte: string) => dispatch({ type: "submitted", controlIds, analyte, now: Date.now() }), [dispatch]);
  const demo = useDemoSequence(state, onSubmitted);

  useEffect(() => {
    const on = () => setScreen(screenOfHash());
    window.addEventListener("hashchange", on);
    return () => window.removeEventListener("hashchange", on);
  }, []);
  const go = (next: Screen) => {
    window.location.hash = next === "alerts" ? "#/alerts" : "#/flow";
    setScreen(next);
  };

  return (
    <NowContext.Provider value={now}>
      <DetailsProvider items={Object.values(state.items)}>
        <div className="app">
          <header className="top">
            <Brand />
            <nav className="tabs" aria-label="Screens">
              <button type="button" className={screen === "flow" ? "on" : ""} aria-current={screen === "flow" ? "page" : undefined} onClick={() => go("flow")}>Agent flow</button>
              <button type="button" className={screen === "alerts" ? "on" : ""} aria-current={screen === "alerts" ? "page" : undefined} onClick={() => go("alerts")}>
                Critical alerts <span className="tab-count num">{total}</span>
              </button>
            </nav>
            <ThemeSwitch />
          </header>
          <ModeBadge mode={state.mode} />
          <StaleBanner stale={state.stale} />
          <Indicators waiting={waiting} total={total} confirmed={confirmed} now={now} />
          {screen === "flow" ? (
            <main className="screen">
              <div className="screen-head">
                <h1>Live flow of lab results</h1>
                <p className="lede">A critical value stops at read-back until a person repeats it correctly. The agent can raise a severity, never lower a critical.</p>
              </div>
              <div className="board">
                <div className="board-flow">
                  {narrow ? <StationList state={state} onSelect={onSelect} /> : <FlowCanvas state={state} now={now} reducedMotion={reducedMotion} onSelect={onSelect} />}
                </div>
                <div className="board-side">
                  <WaitingList items={waiting} total={total} now={now} onSelect={onSelect} />
                  <section className="demo" aria-labelledby="demo-title">
                    <h2 id="demo-title">Demonstration</h2>
                    <p className="picker-note">Synthetic results sent into the production for the demo. Not part of operation.</p>
                    <DemoSequence {...demo} />
                    <ScenarioPicker onSubmitted={onSubmitted} />
                  </section>
                </div>
              </div>
            </main>
          ) : (
            <main className="screen">
              <div className="screen-head">
                <h1>Critical alerts</h1>
                <p className="lede">Results waiting for a person, most urgent first. Open one to see who was alerted and when the alert moved on.</p>
              </div>
              <AlertsScreen items={waiting} total={total} now={now} onOpen={onSelect} />
            </main>
          )}
          {selected && (
            <Suspense fallback={null}>
              <TaskPanel decisionId={selected.decisionId ?? 0} onClose={() => setSelected(null)} />
            </Suspense>
          )}
        </div>
      </DetailsProvider>
    </NowContext.Provider>
  );
}
