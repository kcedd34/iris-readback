import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { TaskScreen, checkEntry } from "../src/task/TaskScreen";
import { signIn, signOut } from "../src/api/session";
import type { TaskView } from "../src/task/types";

const open = (extra: Partial<TaskView> = {}): TaskView => ({
  controlId: "C1", decisionId: 1, patientId: "SYN0001", analyteCode: "2823-3", analyteName: "Potassium", valueText: "6.9", unit: "mmol/L",
  convertedValue: "", convertedUnit: "", reason: "critical by rule", floorNote: "within the critical limits", mode: "replay", taskId: "7", assignedTo: "communicator1",
  agent: { decision: "CRITICAL", severity: 3, confidence: "high", rationale: "Potassium above the limit.", evidence: ["current-result", "crit-potassium"] },
  attemptCount: 0, state: "open", canConfirm: true, ...extra,
});

interface Calls { posts: Array<{ url: string; body: unknown }>; views: number }

/** A fake product: each read of the task view returns the next view of the list (the last one repeats); a POST is recorded. */
function product(views: TaskView[], postStatus = 500): Calls {
  const calls: Calls = { posts: [], views: 0 };
  vi.stubGlobal("fetch", vi.fn(async (url: string, init?: RequestInit) => {
    if (init?.method === "POST") {
      calls.posts.push({ url, body: JSON.parse(String(init.body)) });
      return new Response(postStatus === 200 ? "" : JSON.stringify({ error: "the product could not complete the request" }), { status: postStatus });
    }
    const view = views[Math.min(calls.views, views.length - 1)];
    calls.views++;
    return new Response(JSON.stringify(view), { status: 200 });
  }));
  return calls;
}

beforeEach(() => signIn({ user: "communicator1", password: "pw" }));
afterEach(() => {
  cleanup();
  signOut();
  vi.restoreAllMocks();
});

describe("checkEntry", () => {
  it("asks for both fields and a plain number for a numeric value", () => {
    expect(checkEntry("6.9", "", "6.9")).toMatch(/whom you told/);
    expect(checkEntry("6.9", "Dr X", "")).toMatch(/value you repeated/);
    expect(checkEntry("6.9", "Dr X", "6,9")).toMatch(/dot/);
    expect(checkEntry("6.9", "Dr X", "6.9 mmol/L")).toMatch(/number/);
    expect(checkEntry("6.9", "Dr X", "6.9")).toBe("");
    expect(checkEntry("positive", "Dr X", "positive")).toBe("");
  });
});

describe("the task screen", () => {
  it("shows the critical state, the value and the unit as text, and the agent's words marked as the agent's", async () => {
    product([open()]);
    render(<TaskScreen decisionId={1} />);
    expect(await screen.findByText("Critical")).toBeInTheDocument();
    expect(screen.getByLabelText("Value to read back")).toHaveTextContent("6.9 mmol/L");
    expect(screen.getByText(/What the agent said \(not a rule\)/)).toBeInTheDocument();
    expect(screen.getByText("Potassium above the limit.")).toBeInTheDocument();
    expect(screen.getByText("crit-potassium")).toBeInTheDocument();
    expect(screen.getByText("SYN0001")).toBeInTheDocument();
  });

  it("says there is no agent rationale, and why, when the agent step failed", async () => {
    product([open({ agent: undefined, agentAbsent: { failureKind: "timeout", failureReason: "no answer within 30 seconds" } })]);
    render(<TaskScreen decisionId={1} />);
    expect(await screen.findByText(/There is no agent rationale: timeout/)).toBeInTheDocument();
  });

  it("refuses an empty or non-numeric entry before anything is sent", async () => {
    const calls = product([open()]);
    render(<TaskScreen decisionId={1} />);
    await userEvent.click(await screen.findByRole("button", { name: "Confirm read-back" }));
    expect(screen.getByRole("alert", { name: "" })).toHaveTextContent(/whom you told/);
    await userEvent.type(screen.getByLabelText("Who you told"), "Dr X");
    await userEvent.type(screen.getByLabelText("Value you repeated"), "six");
    await userEvent.click(screen.getByRole("button", { name: "Confirm read-back" }));
    expect(screen.getByText(/as a number/)).toBeInTheDocument();
    expect(calls.posts).toHaveLength(0);
  });

  it("shows the typed and the expected value side by side on a mismatch and leaves the task open", async () => {
    const calls = product([open(), open({ attemptCount: 1 })]);
    render(<TaskScreen decisionId={1} />);
    await userEvent.type(await screen.findByLabelText("Who you told"), "Dr X");
    await userEvent.type(screen.getByLabelText("Value you repeated"), "6.8");
    await userEvent.click(screen.getByRole("button", { name: "Confirm read-back" }));
    expect(await screen.findByText(/The value does not match/)).toBeInTheDocument();
    expect(document.querySelector(".task-typed")).toHaveTextContent("6.8");
    expect(document.querySelector(".task-expected")).toHaveTextContent("6.9");
    expect(screen.getByRole("button", { name: "Confirm read-back" })).toBeInTheDocument();
    expect(calls.posts[0].body).toEqual({ action: "Communicated", formFields: { ToldWho: "Dr X", ReadbackValue: "6.8" } });
    expect(decodeURIComponent(calls.posts[0].url)).toBe("/workflow/rest/task/7||communicator1");
  });

  it("shows success only when the re-read task says completed, never from the status of the POST", async () => {
    // The POST answers 200 but the product recorded nothing: the screen must not claim success.
    product([open(), open()], 200);
    render(<TaskScreen decisionId={1} />);
    await userEvent.type(await screen.findByLabelText("Who you told"), "Dr X");
    await userEvent.type(screen.getByLabelText("Value you repeated"), "6.9");
    await userEvent.click(screen.getByRole("button", { name: "Confirm read-back" }));
    expect(await screen.findByText(/did not accept this/)).toBeInTheDocument();
    expect(screen.queryByText("Read-back confirmed")).not.toBeInTheDocument();
    cleanup();
    product([open(), open({ state: "completed", confirmedBy: "communicator1", confirmedAt: "2026-10-29 12:00:00", attemptCount: 1 })], 200);
    render(<TaskScreen decisionId={1} />);
    await userEvent.type(await screen.findByLabelText("Who you told"), "Dr X");
    await userEvent.type(screen.getByLabelText("Value you repeated"), "6.9");
    await userEvent.click(screen.getByRole("button", { name: "Confirm read-back" }));
    expect(await screen.findByText("Read-back confirmed")).toBeInTheDocument();
  });

  it("sends the confirmation once more when the platform answers a correct request with a 404", async () => {
    let posts = 0;
    let reads = 0;
    vi.stubGlobal("fetch", vi.fn(async (_url: string, init?: RequestInit) => {
      if (init?.method === "POST") {
        posts++;
        return posts === 1 ? new Response(JSON.stringify({ error: "not found" }), { status: 404 }) : new Response("", { status: 200 });
      }
      reads++;
      return new Response(JSON.stringify(posts >= 2 ? open({ state: "completed", confirmedBy: "communicator1", confirmedAt: "x", attemptCount: 1 }) : open()), { status: 200 });
    }));
    render(<TaskScreen decisionId={1} />);
    await userEvent.type(await screen.findByLabelText("Who you told"), "Dr X");
    await userEvent.type(screen.getByLabelText("Value you repeated"), "6.9");
    await userEvent.click(screen.getByRole("button", { name: "Confirm read-back" }));
    expect(await screen.findByText("Read-back confirmed")).toBeInTheDocument();
    expect(posts).toBe(2);
    expect(reads).toBeGreaterThan(1);
  });

  it("shows a completed task with who and when, and offers no confirm action", async () => {
    product([open({ state: "completed", confirmedBy: "communicator2", confirmedAt: "2026-10-29 12:00:00" })]);
    render(<TaskScreen decisionId={1} />);
    expect(await screen.findByText("Read-back confirmed")).toBeInTheDocument();
    expect(screen.getByText("communicator2")).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Confirm read-back" })).not.toBeInTheDocument();
  });

  it("says whose the task is when it is assigned to the other account", async () => {
    product([open({ assignedTo: "communicator2", canConfirm: false })]);
    render(<TaskScreen decisionId={1} />);
    await waitFor(() => expect(screen.getByText(/assigned to/)).toBeInTheDocument());
    expect(screen.getByRole("button", { name: /Sign out to switch account/ })).toBeInTheDocument();
  });

  it("shows both values when a unit conversion happened", async () => {
    product([open({ valueText: "90", unit: "mg/dL", convertedValue: "4.99", convertedUnit: "mmol/L" })]);
    render(<TaskScreen decisionId={1} />);
    expect(await screen.findByText(/reference unit/)).toHaveTextContent("4.99 mmol/L");
    expect(screen.getByLabelText("Value to read back")).toHaveTextContent("90 mg/dL");
  });
});
