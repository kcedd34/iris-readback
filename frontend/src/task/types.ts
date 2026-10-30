// The shape of /readback/api/taskview/:controlId (specs/005-flow-ui/data-model.md).
export interface AgentView {
  decision: string;
  severity: number | string;
  confidence: string;
  rationale: string;
  evidence: string[];
}

export interface TaskView {
  controlId: string;
  decisionId: number;
  patientId: string;
  analyteCode: string;
  analyteName: string;
  valueText: string;
  unit: string;
  convertedValue: string;
  convertedUnit: string;
  reason: string;
  floorNote: string;
  mode: "replay" | "live";
  taskId: string | number;
  assignedTo: string;
  agent?: AgentView;
  agentAbsent?: { failureKind: string; failureReason: string };
  attemptCount: number;
  lastAttempt?: { matched: boolean; attemptedAt: string };
  state: "open" | "completed";
  confirmedBy?: string;
  confirmedAt?: string;
  canConfirm: boolean;
}

export interface DemoAccount {
  user: string;
  password: string;
  canConfirm: boolean;
}

export interface UiConfig {
  publishDemoAccounts: boolean;
  accounts: DemoAccount[];
}
