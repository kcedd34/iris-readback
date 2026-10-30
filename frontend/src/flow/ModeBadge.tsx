import type { Mode } from "./types";

/** The product's mode, always in view: a replayed decision must never be taken for a live one. */
export function ModeBadge({ mode }: { mode: Mode }) {
  return mode === "replay" ? (
    <p className="mode mode-replay" role="status">
      <strong>Replay mode.</strong> Decisions come from recorded answers of a real run, not from a live provider.
    </p>
  ) : (
    <p className="mode mode-live" role="status">
      <strong>Live mode.</strong> Decisions come from a live provider call.
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
