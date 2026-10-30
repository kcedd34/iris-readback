import type { ReactNode } from "react";
import { CriticalIcon, NormalIcon, RecollectIcon, ReviewIcon } from "./icons";

export type SeverityKind = "critical" | "review" | "recollect" | "normal";

const LABEL: Record<SeverityKind, string> = {
  critical: "Critical",
  review: "Needs review",
  recollect: "Recollect advised",
  normal: "Not critical",
};
const ICON: Record<SeverityKind, ReactNode> = {
  critical: <CriticalIcon />,
  review: <ReviewIcon />,
  recollect: <RecollectIcon />,
  normal: <NormalIcon />,
};

/** The meaning of a route, as a severity kind. Critical is never shown by colour alone: icon and text come with it. */
export function kindOfRoute(route: string | undefined): SeverityKind {
  if (route === "readback") return "critical";
  if (route === "recollect") return "recollect";
  if (route === "release") return "normal";
  return "review";
}

export function SeverityBadge({ kind, label }: { kind: SeverityKind; label?: string }) {
  return (
    <span className={`sev sev-${kind}`}>
      {ICON[kind]}
      <span>{label ?? LABEL[kind]}</span>
    </span>
  );
}
