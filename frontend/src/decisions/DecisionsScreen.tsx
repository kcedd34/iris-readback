import { useEffect, useState, type ReactElement } from "react";
import { getJson } from "../api/client";
import { SeverityBadge, kindOfRoute, type SeverityKind } from "../components/SeverityBadge";
import { CriticalIcon, HeldIcon, NormalIcon, ReviewIcon, ToolIcon } from "../components/icons";
import { toolName } from "../flow/ItemChip";
import { agentText, clip, composition, compositionLine, conversionText, costText, latencyText } from "./format";
import type { FeedItem } from "./types";
import { useDecisions } from "./useDecisions";

const ROUTE_LABEL: Record<string, string> = { readback: "Read-back", review: "Needs review", recollect: "Recollect advised", release: "Released" };
const kindOfSeverity = (s: number): SeverityKind => (s >= 3 ? "critical" : s >= 1 ? "review" : "normal");

interface DetailCall {
  seq: number;
  tool: string;
  status: string;
  arguments: string;
  result: string;
  reason: string;
  durationMs: number;
}
interface DecisionDetail {
  sessionId?: number;
  rationale?: string;
  agentCalled?: boolean;
  rounds?: number;
  toolCalls?: DetailCall[];
  policyRefusal?: string;
  evidenceCheck?: string;
  promptVersion?: string;
  failureKind?: string;
  ruleLines?: string[];
}

const STATUS_WORD: Record<string, string> = { ok: "answered", refused: "refused by the policy", failed: "failed", "unknown-tool": "no such tool" };
const EVIDENCE_WORD: Record<string, string> = { ok: "every cited item was returned by a tool of this investigation", "n/a": "no evidence to check" };

const CELL_ICON: Record<SeverityKind, ReactElement> = { critical: <CriticalIcon />, review: <ReviewIcon />, recollect: <ReviewIcon />, normal: <NormalIcon /> };

/** One number of the composition: severity by icon, number and word, never colour alone. */
function CompCell({ label, value, kind }: { label: string; value: string; kind: SeverityKind }) {
  return (
    <span className={`comp-cell comp-${kind}`}>
      <span className="comp-label">{CELL_ICON[kind]} {label}</span>
      <span className="comp-num num">{value}</span>
    </span>
  );
}

/** The composition of a decision as three numeric cells and a seal: floor, agent, final, and held when the floor refused a lowering. */
export function CompositionLine({ item }: { item: FeedItem }) {
  const c = composition(item);
  const agentKind: SeverityKind = c.agent === "none" ? "review" : kindOfSeverity(Number(c.agent));
  return (
    <p className="comp" aria-label={compositionLine(item)}>
      <CompCell label="floor" value={c.floor} kind={kindOfSeverity(item.floor.severity)} />
      <CompCell label="agent" value={c.agent} kind={agentKind} />
      <CompCell label="final" value={c.final} kind={kindOfSeverity(item.final.severity)} />
      {c.held && (
        <span className="held" title="The floor held back the agent's attempt to lower a critical">
          <HeldIcon /> held
        </span>
      )}
    </p>
  );
}

function Detail({ item }: { item: FeedItem }) {
  const [detail, setDetail] = useState<DecisionDetail | null>(null);
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    let live = true;
    getJson<DecisionDetail>(`/readback/api/decisions/${encodeURIComponent(item.controlId)}`)
      .then((d) => live && setDetail(d))
      .catch(() => live && setFailed(true));
    return () => {
      live = false;
    };
  }, [item.controlId, item.decisionId]);
  if (failed) return <p className="empty">The detail of this decision could not be loaded.</p>;
  if (!detail) return <p className="empty">Loading the detail.</p>;
  const calls = detail.toolCalls ?? [];
  return (
    <div className="dec-detail">
      <section aria-label="What the floor said">
        <h3>Floor</h3>
        {(detail.ruleLines ?? []).length > 0 ? (
          <ul className="dec-rules">{(detail.ruleLines ?? []).map((line) => <li key={line}>{line}</li>)}</ul>
        ) : (
          <p>{item.floor.severity > 0 ? item.floor.note || "Raised by a rule of the table." : item.floor.note || "No rule raised the floor."}</p>
        )}
      </section>
      <section aria-label="Tool calls">
        <h3>What the agent read</h3>
        {calls.length === 0 ? (
          <p className="empty">The agent called no tool for this decision.</p>
        ) : (
          <ol className="dec-calls">
            {calls.map((c) => (
              <li key={c.seq} className={c.status === "ok" ? "" : "dec-call-bad"}>
                <ToolIcon /> <strong>{toolName(c.tool)}</strong>
                <span className="dec-sub"> · {STATUS_WORD[c.status] ?? c.status} · {latencyText(c.durationMs)}</span>
                {c.reason && <span className="dec-reason">{c.reason}</span>}
              </li>
            ))}
          </ol>
        )}
        <p className="dec-sub">{detail.rounds ?? item.rounds} round{(detail.rounds ?? item.rounds) === 1 ? "" : "s"} with the model.</p>
      </section>
      {detail.policyRefusal && (
        <section aria-label="Policy refusal">
          <h3>Refusal</h3>
          <p className="held"><HeldIcon /> {detail.policyRefusal}</p>
        </section>
      )}
      <section aria-label="Evidence check">
        <h3>Evidence check</h3>
        <p>{EVIDENCE_WORD[detail.evidenceCheck ?? ""] ?? (detail.evidenceCheck || "not checked")}</p>
      </section>
      <section aria-label="Visual Trace">
        <h3>Visual Trace</h3>
        <p>
          Session <span className="num">{detail.sessionId ?? "unknown"}</span>. Open it in the production's own Visual Trace (Interoperability, View, Visual Trace). The management portal is not exposed on this page.
        </p>
      </section>
    </div>
  );
}

function Row({ item, open, onToggle }: { item: FeedItem; open: boolean; onToggle: () => void }) {
  const conversion = conversionText(item);
  const rationale = item.agent.rationale ? clip(item.agent.rationale, 220) : "";
  const detailId = `dec-detail-${item.decisionId}`;
  return (
    <li className={`dec-row${open ? " dec-open" : ""}${item.held ? " dec-held" : ""}`}>
      <button type="button" className="dec-main" aria-expanded={open} aria-controls={detailId} onClick={onToggle}>
        <span className="dec-who">
          <span className="dec-value num" aria-label="Value of the result">{item.value.text} <span className="dec-unit">{item.value.unit}</span></span>
          <SeverityBadge kind={kindOfRoute(item.route)} label={ROUTE_LABEL[item.route] ?? item.route} />
          <strong>{item.analyte || "Result"}</strong>
          <span className="num dec-sub">{item.controlId}</span>
          <span className="num dec-sub">{item.decidedAt}</span>
        </span>
        <CompositionLine item={item} />
        <span className="dec-agent">
          <span>{agentText(item)}</span>
          {rationale && <span className="dec-rationale">{rationale}</span>}
          {item.agent.evidence && item.agent.evidence.length > 0 && (
            <span className="tags" aria-label="Evidence">
              {item.agent.evidence.map((e) => (
                <span key={e} className="tag num">{e}</span>
              ))}
            </span>
          )}
        </span>
        <span className="dec-conv num">{conversion}</span>
        <span className="dec-cost num">
          <strong>{costText(item)}</strong>
          <span className="dec-sub">{item.cost.tokens} tokens · {latencyText(item.cost.latencyMs)}</span>
          <span className="dec-sub">{item.cost.model}</span>
        </span>
      </button>
      {open && (
        <div id={detailId}>
          <Detail item={item} />
        </div>
      )}
    </li>
  );
}

/** Every decision the product took, newest first: what the floor, the agent and the final answer said, with the conversion, the cost and what the agent read. */
export function DecisionsScreen() {
  const { items, more, stale, loadOlder, loadingOlder } = useDecisions();
  const [openId, setOpenId] = useState<number | null>(null);
  return (
    <div className="decisions">
      {stale && <p className="stale" role="alert">Connection to the product lost. Showing the last known list.</p>}
      <p className="legend">
        Each line reads <strong>floor</strong> (the deterministic rules), <strong>agent</strong> (the model's answer after the tools it called) and <strong>final</strong> (the higher of the two).
        A <strong>held</strong> seal means the agent tried to lower a critical and the floor did not let it.
      </p>
      {items === null ? (
        <p className="empty">Loading the decisions.</p>
      ) : items.length === 0 ? (
        <p className="empty">No decision has been taken yet. Send a result from the Agent flow screen.</p>
      ) : (
        <ol className="dec-list">
          {items.map((item) => (
            <Row key={item.decisionId} item={item} open={openId === item.decisionId} onToggle={() => setOpenId(openId === item.decisionId ? null : item.decisionId)} />
          ))}
        </ol>
      )}
      {more && (
        <button type="button" className="dec-more" onClick={() => void loadOlder()} disabled={loadingOlder}>
          {loadingOlder ? "Loading" : "Show older decisions"}
        </button>
      )}
    </div>
  );
}
