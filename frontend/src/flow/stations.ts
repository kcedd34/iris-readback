import type { Station } from "./types";

export interface StationInfo {
  station: Station;
  title: string;
  hint: string;
  x: number;
  y: number;
}

/** The stations of the flow, left to right, with the layout of the canvas. */
export const STATIONS: StationInfo[] = [
  { station: "intake", title: "Result intake", hint: "HL7 results arrive", x: 0, y: 150 },
  { station: "agent", title: "Agent decision", hint: "Rules check first, then the AI agent", x: 235, y: 150 },
  { station: "readback", title: "Read-back", hint: "Waits for a person", x: 480, y: 0 },
  { station: "confirmed", title: "Read-back confirmed", hint: "Value repeated and matched", x: 715, y: 0 },
  { station: "review", title: "Human review", hint: "Review and recollect advice", x: 480, y: 250 },
  { station: "release", title: "Release", hint: "Not critical by rule or agent", x: 480, y: 430 },
];

export const EDGES: Array<{ id: string; source: Station; target: Station }> = [
  { id: "intake-agent", source: "intake", target: "agent" },
  { id: "agent-readback", source: "agent", target: "readback" },
  { id: "agent-review", source: "agent", target: "review" },
  { id: "agent-release", source: "agent", target: "release" },
  { id: "readback-confirmed", source: "readback", target: "confirmed" },
];
