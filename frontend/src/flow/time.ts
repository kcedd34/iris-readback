/** Seconds since a product timestamp ("2026-10-30 00:49:59.58", UTC), or null when it cannot be read. */
export function secondsSince(since: string | undefined, now: number): number | null {
  if (!since) return null;
  const started = Date.parse(since.replace(" ", "T") + "Z");
  return Number.isNaN(started) ? null : Math.max(0, Math.round((now - started) / 1000));
}

export function formatWait(seconds: number | null): string {
  if (seconds === null) return "just now";
  if (seconds < 60) return `${seconds} s`;
  const minutes = Math.floor(seconds / 60);
  return minutes < 60 ? `${minutes} min ${seconds % 60} s` : `${Math.floor(minutes / 60)} h ${minutes % 60} min`;
}

/** Wall-clock time of a product timestamp, UTC. */
export function clock(at: string): string {
  return at.split(" ")[1]?.slice(0, 8) ?? at;
}

/** Offset of an event from the first one, "+30 s". */
export function offset(at: string, first: string): string {
  const a = Date.parse(at.replace(" ", "T") + "Z");
  const b = Date.parse(first.replace(" ", "T") + "Z");
  if (Number.isNaN(a) || Number.isNaN(b)) return "";
  const s = Math.max(0, Math.round((a - b) / 1000));
  return s < 60 ? `+${s} s` : `+${Math.floor(s / 60)} min ${s % 60} s`;
}
