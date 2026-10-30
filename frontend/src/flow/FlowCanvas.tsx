import { useMemo } from "react";
import { Background, ReactFlow, type Edge, type Node } from "@xyflow/react";
import "@xyflow/react/dist/style.css";
import { EDGES, STATIONS } from "./stations";
import { StationNode, type StationNodeData } from "./StationNode";
import { itemsAt } from "./reducer";
import type { FlowItem, FlowState } from "./types";

/** Two invisible corner points that fix the framing of the whole layout, so the view does not jump as cases arrive. */
const Anchor = () => <span aria-hidden="true" />;
const nodeTypes = { station: StationNode, anchor: Anchor };
const ANCHORS: Node[] = [
  { id: "anchor-start", type: "anchor", position: { x: 0, y: 0 }, data: {}, style: { width: 1, height: 1, opacity: 0, pointerEvents: "none" }, draggable: false, selectable: false, focusable: false },
  { id: "anchor-end", type: "anchor", position: { x: 1170, y: 720 }, data: {}, style: { width: 1, height: 1, opacity: 0, pointerEvents: "none" }, draggable: false, selectable: false, focusable: false },
];
/** An edge moves for this long after something arrived at the station it leads to. */
const RECENT_MS = 2000;

export function FlowCanvas({ state, now, reducedMotion, onSelect }: { state: FlowState; now: number; reducedMotion: boolean; onSelect?: (item: FlowItem) => void }) {
  const nodes = useMemo<Node[]>(
    () => [
      ...ANCHORS,
      ...STATIONS.map((s) => {
        const items = itemsAt(state, s.station);
        const data: StationNodeData = { station: s.station, title: s.title, hint: s.hint, items, active: s.station === "agent" && items.length > 0, onSelect };
        return { id: s.station, type: "station", position: { x: s.x, y: s.y }, data, draggable: false, selectable: false, connectable: false, focusable: false };
      }),
    ],
    [state, onSelect],
  );
  const edges = useMemo<Edge[]>(
    () =>
      EDGES.map((e) => {
        const recent = !reducedMotion && itemsAt(state, e.target).some((item) => now - item.stationSince < RECENT_MS);
        return { id: e.id, source: e.source, target: e.target, animated: recent, style: { stroke: recent ? "var(--accent)" : "var(--line)", strokeWidth: 2 }, focusable: false };
      }),
    [state, now, reducedMotion],
  );
  return (
    <div className="canvas" role="group" aria-label="Live flow of results through the production">
      <ReactFlow
        nodes={nodes}
        edges={edges}
        nodeTypes={nodeTypes}
        fitView
        fitViewOptions={{ padding: 0.04 }}
        nodesDraggable={false}
        nodesConnectable={false}
        elementsSelectable={false}
        nodesFocusable={false}
        edgesFocusable={false}
        panOnDrag={false}
        panOnScroll={false}
        zoomOnScroll={false}
        zoomOnPinch={false}
        zoomOnDoubleClick={false}
        preventScrolling={false}
        minZoom={0.3}
        maxZoom={1.2}
      >
        <Background gap={24} />
      </ReactFlow>
    </div>
  );
}
