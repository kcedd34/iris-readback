import { STATIONS } from "./stations";
import { itemsAt } from "./reducer";
import { ItemChip } from "./ItemChip";
import type { FlowItem, FlowState } from "./types";

/** The flow as an ordered list, for small screens: every station with its cases, the critical state always visible. */
export function StationList({ state, onSelect }: { state: FlowState; onSelect?: (item: FlowItem) => void }) {
  return (
    <ol className="stations" aria-label="Stations of the flow, in order">
      {STATIONS.map((s) => {
        const items = itemsAt(state, s.station);
        return (
          <li key={s.station} className={`station station-${s.station}`}>
            <h2>{s.title} <span className="num">({items.length})</span></h2>
            <p className="node-hint">{s.hint}</p>
            {items.slice(-8).map((item) => <ItemChip key={item.key} item={item} onSelect={onSelect} />)}
          </li>
        );
      })}
    </ol>
  );
}
