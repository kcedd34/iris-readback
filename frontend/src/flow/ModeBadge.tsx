import type { Mode } from "./types";
import { SimulationIcon } from "../components/icons";

/** The product's mode, always in view: a replayed decision must never be taken for a live one. Amber with an icon in replay. */
export function ModeBadge({ mode }: { mode: Mode }) {
  return mode === "replay" ? (
    <p className="mode mode-replay" role="status">
      <SimulationIcon />
      <span><strong>Simulation. Replay mode.</strong> Synthetic data, not real patients. Decisions come from recorded answers of a real run, not from a live provider.</span>
    </p>
  ) : (
    <p className="mode mode-live" role="status">
      <SimulationIcon />
      <span><strong>Live mode.</strong> Decisions come from a live provider call.</span>
    </p>
  );
}

export function StaleBanner({ stale }: { stale: boolean }) {
  if (!stale) return null;
  return (
    <p className="stale" role="alert">
      Connection to the product lost. Showing the last known state; nothing shown here has changed since.
    </p>
  );
}
