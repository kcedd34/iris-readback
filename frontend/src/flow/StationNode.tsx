import { Handle, Position, type NodeProps } from "@xyflow/react";
import type { ReactElement } from "react";
import type { FlowItem, Station } from "./types";
import { ItemChip } from "./ItemChip";
import { AgentIcon, ConfirmedIcon, CriticalIcon, InboxIcon, NormalIcon, ReviewIcon } from "../components/icons";

export interface StationNodeData extends Record<string, unknown> {
  station: Station;
  title: string;
  hint: string;
  items: FlowItem[];
  active: boolean;
  onSelect?: (item: FlowItem) => void;
}

const ICONS: Record<Station, ReactElement> = {
  intake: <InboxIcon />,
  agent: <AgentIcon />,
  readback: <CriticalIcon />,
  confirmed: <ConfirmedIcon />,
  review: <ReviewIcon />,
  release: <NormalIcon />,
};

const SHOWN = 4; // chips shown at a station other than read-back; read-back shows every waiting case

export function StationNode({ data }: NodeProps) {
  const d = data as StationNodeData;
  const all = d.items;
  const limit = d.station === "readback" ? 12 : SHOWN;
  const shown = all.slice(-limit);
  return (
    <section className={`node node-${d.station}${d.active ? " node-active" : ""}`} aria-label={`${d.title}: ${all.length} case${all.length === 1 ? "" : "s"}`}>
      <Handle type="target" position={Position.Left} isConnectable={false} />
      <header className="node-head">
        <span className="node-icon">{ICONS[d.station]}</span>
        <h2>{d.title}</h2>
        <span className="node-count num">{all.length}</span>
      </header>
      <p className="node-hint">{d.active && d.station === "agent" ? "Deciding now" : d.hint}</p>
      <div className="node-items nodrag nopan nowheel">
        {shown.map((item) => (
          <ItemChip key={item.key} item={item} onSelect={d.onSelect} />
        ))}
        {all.length > shown.length && <p className="node-more num">{all.length - shown.length} more</p>}
      </div>
      <Handle type="source" position={Position.Right} isConnectable={false} />
    </section>
  );
}
