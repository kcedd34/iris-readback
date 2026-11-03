import { SimulationIcon } from "../components/icons";
import type { Seals } from "./types";

/** Two seals at the top of every screen: whether the production runs, and the mode and model the decisions come from. No credential is involved. */
export function TopSeals({ seals }: { seals: Seals | null }) {
  if (!seals) {
    return (
      <p className="seals" role="status">
        <span className="seal seal-unknown">Production state unknown</span>
      </p>
    );
  }
  return (
    <p className="seals" role="status">
      <span className={`seal ${seals.productionRunning ? "seal-running" : "seal-stopped"}`}>
        <span className="seal-dot" aria-hidden="true" />
        {seals.productionRunning ? "Production running" : "Production stopped"}
      </span>
      <span className={`seal ${seals.mode === "replay" ? "seal-replay" : "seal-live"}`}>
        <SimulationIcon />
        {seals.mode === "replay" ? "Replay" : "Live"}{seals.model ? ` · ${seals.model}` : ""}
      </span>
    </p>
  );
}
