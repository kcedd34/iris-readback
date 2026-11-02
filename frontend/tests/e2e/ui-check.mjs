// Browser checks of the flow UI against the running stack (replay mode, no provider key).
//   BASE_URL (default http://127.0.0.1:8080), RUNS (default 5; 20 for the full measure of SC-002 and SC-003),
//   PARTS (comma list of: flow, task, public, a11y; default all), SHOT_DIR (where screenshots go).
// Run it through tests/e2e/ui_check.py, which prepares the stack state and prints the verdict.
import { chromium } from "@playwright/test";
import { mkdirSync } from "node:fs";

const BASE = process.env.BASE_URL || "http://127.0.0.1:8080";
const RUNS = Number(process.env.RUNS || 5);
const PARTS = (process.env.PARTS || "flow,task,public,a11y,demo,alerts,tools").split(",");
const SHOTS = process.env.SHOT_DIR || ".local/ui";
const PASSWORD = process.env.READBACK_DEMO_PASSWORD || "";
const failures = [];
if (PARTS.some((p) => ["task", "public"].includes(p)) && !PASSWORD) {
  console.log("FAIL: READBACK_DEMO_PASSWORD is not set");
  process.exit(1);
}

function check(condition, message) {
  if (!condition) {
    failures.push(message);
    console.log("FAIL:", message);
  }
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function waitFor(fn, ms = 10000, step = 100) {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    const v = await fn();
    if (v) return v;
    await sleep(step);
  }
  return null;
}

async function nodeText(page, station) {
  const node = page.locator(`.node-${station}`);
  return (await node.count()) ? (await node.first().innerText()) : "";
}

async function submit(page, scenarioId) {
  await page.selectOption("#scenario", scenarioId);
  await page.click("button[type=submit]");
}

async function flowPart(browser) {
  const page = await browser.newPage({ viewport: { width: 1360, height: 900 } });
  const errors = [];
  page.on("pageerror", (e) => errors.push(String(e)));
  await page.goto(BASE);
  await page.waitForSelector("select#scenario option", { state: "attached" });
  check((await page.locator(".mode").innerText()).includes("Replay mode"), "the mode badge does not say replay");

  // SC-002 and SC-003: the critical scenario enters, reaches read-back, and is never shown released, reviewed or confirmed.
  let neverWrong = true;
  let reached = 0;
  for (let run = 0; run < RUNS; run++) {
    const before = await page.locator(".waiting-list li").count();
    await sleep(1100); // the product allows one submission per second per account
    await submit(page, "potassium-critical-value");
    const started = Date.now();
    let entered = false;
    const end = Date.now() + 9000;
    while (Date.now() < end) {
      const other = (await nodeText(page, "release")) + (await nodeText(page, "review")) + (await nodeText(page, "confirmed"));
      if (other.includes("RBSAMPLE0001")) neverWrong = false;
      if (!entered && (await page.locator(".chip", { hasText: "RBSAMPLE0001" }).count()) > 0) entered = true;
      if ((await page.locator(".waiting-list li").count()) > before) break;
      await sleep(80);
    }
    const waitingNow = await page.locator(".waiting-list li").count();
    if (waitingNow > before) reached++;
    check(entered, `run ${run + 1}: the submitted case was never shown entering`);
    check(Date.now() - started < 9000, `run ${run + 1}: the case took too long to reach read-back`);
  }
  check(reached === RUNS, `the critical case reached read-back in ${reached} of ${RUNS} runs`);
  check(neverWrong, "a case waiting at read-back was shown as released, reviewed or confirmed");
  await waitFor(async () => (await nodeText(page, "readback")).includes("Critical"), 8000);
  check((await nodeText(page, "readback")).includes("Critical"), "the read-back station does not show the critical marking");
  const waitingText = await page.locator(".waiting").innerText();
  check(waitingText.includes("Critical") && waitingText.includes("RBSAMPLE0001"), "the waiting list does not carry the critical case as text");

  // A normal result leaves through release with the reason the product recorded.
  await sleep(1100);
  await submit(page, "hemoglobin-low-not-critical");
  const released = await waitFor(async () => (await nodeText(page, "release")).includes("RBSAMPLE0002"), 9000);
  check(!!released, "the normal result did not reach the release station");
  const releaseText = await nodeText(page, "release");
  check(releaseText.includes("not critical by rule or by the agent"), "the released case does not show the recorded reason");

  // Reload: the waiting cases are rebuilt from the product's records.
  const waitingBefore = await page.locator(".waiting-list li").count();
  await page.reload();
  await page.waitForSelector(".waiting");
  await waitFor(async () => (await page.locator(".waiting-list li").count()) > 0, 5000);
  const waitingAfter = await page.locator(".waiting-list li").count();
  check(waitingAfter > 0 && waitingAfter >= Math.min(waitingBefore, 200), `after a reload the waiting list has ${waitingAfter} of ${waitingBefore} cases`);
  check((await nodeText(page, "readback")).includes("RBSAMPLE0001"), "after a reload the critical case is not at the read-back station");

  // A lost connection: the banner appears, the waiting cases stay as they were.
  await page.route("**/readback/api/flow?**", (route) => route.abort());
  await page.route("**/readback/api/flow", (route) => route.abort());
  const banner = await waitFor(async () => (await page.locator(".stale").count()) > 0, 6000);
  check(!!banner, "the stale banner did not appear when the connection was lost");
  check((await page.locator(".waiting-list li").count()) === waitingAfter, "a lost connection changed the waiting list");
  await page.unroute("**/readback/api/flow?**");
  await page.unroute("**/readback/api/flow");
  const back = await waitFor(async () => (await page.locator(".stale").count()) === 0, 6000);
  check(!!back, "the stale banner stayed after the connection came back");

  // Several submissions in a row: no waiting case disappears.
  const count = await page.locator(".waiting-list li").count();
  for (const id of ["sodium-critical-value", "hemoglobin-acute-drop", "potassium-dialysis"]) {
    await sleep(1200);
    await submit(page, id);
  }
  await waitFor(async () => (await page.locator(".waiting-list li").count()) >= count + 3, 12000);
  check((await page.locator(".waiting-list li").count()) >= count + 3, "a waiting case disappeared during a series of submissions");

  mkdirSync(SHOTS, { recursive: true });
  await page.screenshot({ path: `${SHOTS}/panel-light.png` });
  check(errors.length === 0, "page errors: " + errors.join(" | "));
  await page.close();
}

async function signInAs(page, user) {
  await page.fill("#signin-user", user);
  await page.fill("#signin-password", PASSWORD);
  await page.click(".signin button[type=submit]");
  try {
    await page.waitForSelector(".task, .task-done, .signin .error", { timeout: 15000 });
  } catch (e) {
    mkdirSync(SHOTS, { recursive: true });
    await page.screenshot({ path: `${SHOTS}/signin-failure.png` });
    throw e;
  }
}

async function openWaiting(page, controlId, assignee) {
  // The newest waiting item of the case (the list is newest first), optionally of one assignee.
  const filter = assignee ? `assigned to ${assignee}` : controlId;
  const row = page.locator(".waiting-list li", { hasText: controlId }).filter({ hasText: filter }).first();
  await row.waitFor({ timeout: 10000 });
  const text = await row.innerText();
  await row.getByRole("button", { name: "Open read-back" }).click();
  await page.waitForSelector("dialog.drawer[open]");
  return text;
}

async function taskPart(browser) {
  const page = await browser.newPage({ viewport: { width: 1360, height: 900 } });
  const posts = [];
  page.on("request", (r) => { if (r.method() === "POST" && r.url().includes("/workflow/rest/")) posts.push(r.url()); });
  await page.goto(BASE);
  await page.waitForSelector("select#scenario option", { state: "attached" });
  await sleep(1100);
  await submit(page, "potassium-critical-value");
  await waitFor(async () => (await page.locator(".waiting-list li", { hasText: "RBSAMPLE0001" }).count()) > 0, 10000);

  // Open the task: sign in first as the person it is assigned to.
  const first = await page.locator(".waiting-list li", { hasText: "RBSAMPLE0001" }).first().innerText();
  const assignee = (first.match(/assigned to (communicator\d)/) || [])[1];
  check(!!assignee, "the waiting case has no assignee shown: " + first);
  const other = assignee === "communicator1" ? "communicator2" : "communicator1";
  await openWaiting(page, "RBSAMPLE0001", assignee);
  check((await page.locator("dialog.drawer .signin").count()) === 1, "the task did not ask for a sign-in");
  await signInAs(page, assignee);
  await page.waitForSelector(".task");
  const text = await page.locator("dialog.drawer").innerText();
  check(text.includes("6.9") && text.includes("mmol/L"), "the task does not show the value and unit");
  check(text.includes("Critical"), "the task does not show the critical state as text");
  check(text.includes("What the agent said (not a rule)") && text.includes("Why this is critical (from the rules)"), "the task does not separate the agent's words from the rules'");
  check(/Synthetic patient\s+SYN\d+/.test(text), "the task does not show the synthetic patient identifier");

  // An empty entry is refused before anything is sent; a wrong value shows both values and leaves the task open.
  const sent = posts.length;
  await page.fill("#told", "Dr X");
  await page.click(".task-form button[type=submit]");
  check((await page.locator("#field-error").innerText()).includes("value you repeated"), "an empty value was not refused with a message");
  check(posts.length === sent, "an empty value was sent to the product");
  await page.fill("#repeated", "6.8");
  await page.click(".task-form button[type=submit]");
  await page.waitForSelector(".task-mismatch");
  check((await page.locator(".task-typed").innerText()) === "6.8" && (await page.locator(".task-expected").innerText()) === "6.9", "the mismatch does not show the typed and the expected value");
  check((await page.locator(".task-form").count()) === 1, "the task closed after a wrong value");

  // The right value completes it and the panel says who confirmed.
  await page.fill("#repeated", "6.9");
  await page.click(".task-form button[type=submit]");
  await page.waitForSelector(".task-done");
  check((await page.locator(".task-done").innerText()).includes(assignee), "the completed task does not name who confirmed");
  await page.keyboard.press("Escape");
  const confirmedChip = await waitFor(async () => (await nodeText(page, "confirmed")).includes("RBSAMPLE0001"), 8000);
  check(!!confirmedChip, "the confirmed case did not move to the confirmed station");
  check((await nodeText(page, "confirmed")).includes(`by ${assignee}`) && (await nodeText(page, "confirmed")).includes("value matched"), "the confirmed station does not say who confirmed and that the value matched");

  // Another account opens the completed task: it is shown completed, with no confirm action.
  await page.locator(".node-confirmed .chip", { hasText: "RBSAMPLE0001" }).first().click();
  await page.waitForSelector("dialog.drawer[open]");
  await page.click("dialog.drawer .drawer-user button");
  await signInAs(page, other);
  await page.waitForSelector(".task-done");
  check((await page.locator(".task-form").count()) === 0, "a completed task offers a confirm action");
  await page.keyboard.press("Escape");

  // The account that cannot confirm sees the content and is refused in plain words; the case is unchanged.
  await sleep(1100);
  await submit(page, "potassium-critical-value");
  await sleep(2500);
  await openWaiting(page, "RBSAMPLE0001");
  await page.click("dialog.drawer .drawer-user button");
  await signInAs(page, "observer");
  await page.waitForSelector(".task");
  check((await page.locator("dialog.drawer").innerText()).includes("6.9"), "the observer does not see the task content");
  await page.fill("#told", "Dr X");
  await page.fill("#repeated", "6.9");
  await page.click(".task-form button[type=submit]");
  await page.waitForSelector(".task-form .error:not(:empty)");
  check((await page.locator(".task-form").innerText()).includes("not allowed to confirm"), "the refusal is not shown in plain words");
  check((await page.locator(".task-done").count()) === 0, "the observer's attempt was shown as a success");
  await page.keyboard.press("Escape");

  // A unit conversion shows both values.
  await page.click(".theme button:has-text('Light')");
  await sleep(1100);
  await submit(page, "glucose-sharp-rise");
  await waitFor(async () => (await page.locator(".waiting-list li", { hasText: "RB42-00002" }).count()) > 0, 10000);
  await openWaiting(page, "RB42-00002");
  await page.click("dialog.drawer .drawer-user button");
  await signInAs(page, assignee);
  await page.waitForSelector(".task");
  const glucose = await page.locator("dialog.drawer").innerText();
  check(glucose.includes("mg/dL") && glucose.includes("reference unit") && glucose.includes("mmol/L"), "the glucose task does not show both units");
  await page.keyboard.press("Escape");
  await page.close();
}

async function publicPart(browser) {
  const expectPublished = process.env.EXPECT_PUBLISHED === "1";
  const page = await browser.newPage({ viewport: { width: 1360, height: 900 } });
  const bodies = [];
  const external = [];
  page.on("request", (r) => { if (!r.url().startsWith(BASE)) external.push(r.url()); });
  page.on("response", async (r) => {
    try {
      const type = r.headers()["content-type"] || "";
      if (type.includes("json") || type.includes("html") || type.includes("javascript") || type.includes("css")) bodies.push({ url: r.url(), text: await r.text(), headers: r.headers() });
    } catch { /* a response that was redirected away has no body */ }
  });
  await page.goto(BASE);
  await page.waitForSelector("select#scenario option", { state: "attached" });
  await sleep(1100);
  await submit(page, "potassium-critical-value");
  await waitFor(async () => (await page.locator(".waiting-list li button").count()) > 0, 10000);
  await page.locator(".waiting-list li button").first().click();
  await page.waitForSelector("dialog.drawer .signin");
  await sleep(500);
  const accountsShown = (await page.locator(".demo-accounts li").count()) === 3;
  check(accountsShown === expectPublished, `the demo accounts are ${accountsShown ? "shown" : "hidden"} but ${expectPublished ? "should be published" : "should not be published"}`);
  if (expectPublished) {
    const text = await page.locator(".demo-accounts").innerText();
    check(text.includes("communicator1") && text.includes("communicator2") && text.includes("observer"), "the three demo accounts are not listed");
    check(text.includes("cannot confirm"), "the account that cannot confirm is not labelled");
    await page.locator(".demo-accounts li", { hasText: "communicator1" }).getByRole("button", { name: "Use" }).click();
  } else {
    await signInAs(page, "communicator1");
  }
  try {
    await page.waitForSelector(".task, .task-done", { timeout: 15000 });
  } catch (e) {
    mkdirSync(SHOTS, { recursive: true });
    await page.screenshot({ path: `${SHOTS}/public-failure.png` });
    throw e;
  }
  await page.keyboard.press("Escape");

  check(external.length === 0, "the page asked for another address: " + external.slice(0, 3).join(", "));
  const secrets = [process.env.OPENAI_API_KEY || ""].filter((v) => v.length > 8);
  const defaults = ["SuperUser", "SYS\"", "\"_SYSTEM\""];
  for (const body of bodies) {
    const isConfig = body.url.endsWith("/ui-config.json");
    for (const secret of secrets) check(!body.text.includes(secret), `the provider key appears in ${body.url}`);
    if (!isConfig && PASSWORD) check(!body.text.includes(PASSWORD), `the demo password appears in ${body.url}`);
    for (const d of defaults) check(!body.text.includes(d), `a default credential string (${d}) appears in ${body.url}`);
    check(!("set-cookie" in body.headers), `a cookie is set by ${body.url}`);
    const own = body.url.includes("/readback/api/taskview/") || body.url.includes("/workflow/rest/");
    if (!own) check(!/SYN\d{7}/.test(body.text), `a patient identifier appears in ${body.url}`);
    check(!/(Apache|InterSystems|ERROR #|SQLCODE)/.test(body.text) || body.url.includes("/assets/"), `platform content appears in ${body.url}`);
  }
  check(bodies.length > 5, "too few responses were scanned");
  await page.close();
}

async function a11yPart(browser) {
  // No request leaves for another address, over a full session.
  const ctx = await browser.newContext({ viewport: { width: 1360, height: 900 } });
  const blocked = [];
  await ctx.route("**/*", (route) => {
    const url = route.request().url();
    if (url.startsWith(BASE) || url.startsWith("data:")) return route.continue();
    blocked.push(url);
    return route.abort();
  });
  const page = await ctx.newPage();
  await page.goto(BASE);
  await page.waitForSelector("select#scenario option", { state: "attached" });
  const known = await page.locator(".waiting-list li", { hasText: "RBSAMPLE0001" }).count();
  await sleep(1100);
  await submit(page, "potassium-critical-value");
  // The newest waiting case is the first of the list: wait for the one just submitted before using the keyboard on it.
  await waitFor(async () => (await page.locator(".waiting-list li", { hasText: "RBSAMPLE0001" }).count()) > known || (known >= 200), 10000);
  await waitFor(async () => (await page.locator(".waiting-list li").first().innerText()).includes("RBSAMPLE0001"), 5000);
  // The task is assigned a moment after the decision; use the keyboard on it only once the list says to whom.
  await waitFor(async () => /assigned to communicator\d/.test(await page.locator(".waiting-list li").first().innerText()), 10000);

  // Severity is never colour alone: every severity element carries an icon and a text.
  const bad = await page.evaluate(() => [...document.querySelectorAll(".sev:not(.sev-pending)")].filter((e) => !e.querySelector("svg") || !e.textContent.trim()).length);
  check(bad === 0, `${bad} severity element(s) lack an icon or a text`);

  // Keyboard only: reach the first "Open read-back" button with Tab, open it, sign in, confirm, close.
  await page.evaluate(() => document.activeElement && document.activeElement.blur());
  // Another submission may be decided a moment later and take the top of the list, so the keyboard goes to the first
  // "Open read-back" of a potassium case that is already assigned, wherever it sits.
  let reached = false;
  for (let i = 0; i < 160 && !reached; i++) {
    await page.keyboard.press("Tab");
    reached = await page.evaluate(() => {
      const el = document.activeElement;
      if (el?.textContent?.trim() !== "Open read-back") return false;
      const row = el.closest("li")?.innerText || "";
      return row.includes("RBSAMPLE0001") && /assigned to communicator\d/.test(row);
    });
  }
  check(reached, "the Open read-back button cannot be reached with the keyboard");
  const outline = await page.evaluate(() => { const s = getComputedStyle(document.activeElement); return { style: s.outlineStyle, width: parseFloat(s.outlineWidth) }; });
  check(outline.style !== "none" && outline.width >= 2, "the focused control shows no focus outline");
  const assignee = (await page.evaluate(() => document.activeElement.closest("li").innerText.match(/assigned to (communicator\d)/)?.[1])) || "communicator1";
  await page.keyboard.press("Enter");
  await page.waitForSelector("dialog.drawer[open]");
  const inside = await page.evaluate(() => document.querySelector("dialog.drawer").contains(document.activeElement));
  check(inside, "the focus did not move into the task panel");
  await page.keyboard.press("Tab");
  // The user name field is reached by Tab (or is already focused); type with the keyboard.
  await page.focus("#signin-user");
  await page.keyboard.type(assignee);
  await page.keyboard.press("Tab");
  await page.keyboard.type(PASSWORD);
  await page.keyboard.press("Enter");
  await page.waitForSelector(".task", { timeout: 15000 });
  await page.focus("#told");
  await page.keyboard.type("Dr Keyboard");
  await page.keyboard.press("Tab");
  await page.keyboard.type("6.9");
  await page.keyboard.press("Enter");
  await page.waitForSelector(".task-done, .task-mismatch, .task-form .error:not(:empty)", { timeout: 15000 });
  const confirmed = (await page.locator(".task-done").count()) > 0;
  if (!confirmed) {
    mkdirSync(SHOTS, { recursive: true });
    await page.screenshot({ path: `${SHOTS}/a11y-failure.png` });
    console.log("keyboard confirm outcome:", (await page.locator("dialog.drawer").innerText()).replace(/\s+/g, " ").slice(0, 700));
  }
  check(confirmed, "confirming the right value with the keyboard did not complete the task");
  await page.keyboard.press("Escape");
  await sleep(300);
  check((await page.locator("dialog.drawer[open]").count()) === 0, "Escape did not close the task panel");

  // Reduced motion: the same information, no moving animation.
  await page.emulateMedia({ reducedMotion: "reduce" });
  await sleep(1100);
  await submit(page, "hemoglobin-low-not-critical");
  await waitFor(async () => (await nodeText(page, "release")).includes("RBSAMPLE0002"), 9000);
  check((await nodeText(page, "release")).includes("RBSAMPLE0002"), "with reduced motion the case did not reach its station");
  const motion = await page.evaluate(() => ({
    animatedEdges: document.querySelectorAll(".react-flow__edge.animated").length,
    chipDuration: parseFloat(getComputedStyle(document.querySelector(".chip")).animationDuration),
  }));
  check(motion.animatedEdges === 0, "with reduced motion edges still animate");
  check(motion.chipDuration < 0.01, `with reduced motion a chip animation lasts ${motion.chipDuration}s`);
  await page.emulateMedia({ reducedMotion: "no-preference" });

  // A small screen: the flow is a list, nothing runs off the page, and the critical state stays in view.
  await page.setViewportSize({ width: 390, height: 800 });
  await sleep(600);
  check((await page.locator(".stations").count()) === 1, "a small screen does not show the list view");
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  check(overflow <= 1, `a small screen scrolls sideways by ${overflow}px`);
  check((await page.locator("body").innerText()).includes("Critical"), "a small screen does not show the critical state");

  // Both themes: the page has a background and ink colour in each, and the switch works.
  await page.setViewportSize({ width: 1360, height: 900 });
  for (const label of ["Dark", "Light"]) {
    await page.click(`.theme button:has-text("${label}")`);
    const colours = await page.evaluate(() => ({ bg: getComputedStyle(document.body).backgroundColor, ink: getComputedStyle(document.body).color, theme: document.documentElement.getAttribute("data-theme") }));
    check(colours.theme === label.toLowerCase() && colours.bg !== colours.ink, `the ${label} theme was not applied`);
  }
  mkdirSync(SHOTS, { recursive: true });
  await page.click('.theme button:has-text("Dark")');
  await page.screenshot({ path: `${SHOTS}/panel-dark.png` });
  check(blocked.length === 0, "the page asked for another address: " + blocked.slice(0, 3).join(", "));
  await ctx.close();
}

// The panel must not open as an empty board: when the product has nothing to show, in replay mode, the short demo sequence
// (a critical stopping at read-back, a borderline going to review) is sent by itself. The first answer of /flow is made empty here.
async function demoPart(browser) {
  const page = await browser.newPage({ viewport: { width: 1360, height: 900 } });
  const posts = [];
  page.on("request", (r) => r.method() === "POST" && r.url().includes("/flow/submit") && posts.push(r.postData()));
  let first = true;
  await page.route(/\/readback\/api\/flow$/, async (route) => {
    if (!first) return route.continue();
    first = false;
    const body = await (await route.fetch()).json();
    return route.fulfill({ json: { ...body, decided: [], inFlight: [], waiting: [], waitingTotal: 0, confirmed: [] } });
  });
  await page.goto(BASE);
  await waitFor(() => posts.length >= 2, 12000);
  check(posts.length === 2 && posts[0].includes("potassium-critical-value") && posts[1].includes("potassium-borderline"), `the demo sequence sent ${JSON.stringify(posts)}`);
  check((await page.locator(".demo-sequence button").count()) === 1, "there is no Run demo sequence button");
  // While a case is at the agent station the hint reads "Deciding now"; wait for the node to be idle again.
  const hinted = await waitFor(async () => (await page.getByText("Rules check first, then the AI agent").count()) === 1, 10000);
  check(hinted, "the agent station hint is not the plain-language one");
  await page.close();
}

// The agent's tool calls shown as sub-steps in the agent node, in order, and what the agent read in the sentence of a raised severity.
// The snapshot is made up (a call the policy refused and one that failed cannot be provoked in replay): the first poll is empty so the
// panel starts clean, the second hands over two decisions, the rest hand over nothing new.
async function toolsPart(browser) {
  const page = await browser.newPage({ viewport: { width: 1360, height: 900 } });
  const entry = (id, controlId, reason, failureKind, toolCalls) => ({ decisionId: id, controlId, analyte: "Hemoglobin", route: "review", finalSeverity: 1, reason, floorNote: "", failureKind, agentCalled: true, mode: "replay", decidedAt: "2026-11-02 10:00:00", toolCalls, rounds: 2, policyRefusal: "" });
  const decided = [
    entry(9001, "TOOLS-OK", "agent raised the severity to 1, not released automatically", "", [
      { seq: 1, tool: "get_patient_history", status: "ok", summary: "2 earlier results" },
      { seq: 2, tool: "get_delta_assessment", status: "ok", summary: "critical by change" },
    ]),
    entry(9002, "TOOLS-BAD", "tool search_policy refused: the tool is not in the tool set", "tool-failure", [
      { seq: 1, tool: "get_patient_history", status: "ok", summary: "no earlier results" },
      { seq: 2, tool: "search_policy", status: "refused", summary: "refused by the policy" },
      { seq: 3, tool: "get_sample_quality", status: "failed", summary: "the tool failed" },
    ]),
  ];
  let polls = 0;
  await page.route(/\/readback\/api\/flow(\?.*)?$/, async (route) => {
    polls += 1;
    const body = await (await route.fetch()).json();
    const base = { ...body, inFlight: [], waiting: [], waitingTotal: 0, confirmed: [] };
    if (polls === 1) return route.fulfill({ json: { ...base, decided: [], cursor: 9000 } });
    if (polls === 2) return route.fulfill({ json: { ...base, decided, cursor: 9002 } });
    return route.fulfill({ json: { ...base, decided: [], cursor: 9002 } });
  });
  await page.goto(BASE);
  const lit = await waitFor(async () => (await page.locator(".node-agent .substeps .substep").count()) >= 1, 15000);
  check(lit, "no tool call is shown as a sub-step in the agent node");
  const refused = await waitFor(async () => (await page.locator(".node-agent .substep-bad").count()) >= 1, 15000);
  check(refused, "a refused or failed call is not marked in the agent node");
  if (refused) {
    const bad = await page.locator(".node-agent .substep-bad").allInnerTexts();
    check(bad.some((t) => t.includes("refused by the policy")), `a refused call does not say so in words: ${JSON.stringify(bad)}`);
    check((await page.locator(".node-agent .substep-bad .substep-mark").count()) >= 1, "a refused call has no icon");
  }
  // Sub-steps appear in the order the agent made them: the history comes before the change.
  const names = await page.locator(".node-agent .substeps").first().locator(".substep-name").allInnerTexts();
  check(names[0] === "Patient history", `the first sub-step is not the first call: ${JSON.stringify(names)}`);
  // Once the case has moved on, the sentence of the raised severity says what the agent read.
  const sentence = await waitFor(async () => (await page.locator(".node-review .chip-reason").allInnerTexts()).some((t) => t.includes("after reading: 2 earlier results (patient history), critical by change (change against history)")), 20000);
  check(sentence, "the raised-severity sentence does not say what the agent read");
  check((await page.locator(".node-agent .substeps").count()) <= 2, "the sub-steps are not limited to the cases at the agent node");
  await page.close();
}

// The second first-class screen: the queue of critical alerts, with the escalation history of the open one. The menu switches
// between it and the agent flow, and the flow stays a canvas (not a summary).
async function alertsPart(browser) {
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  await page.goto(BASE);
  await page.waitForSelector(".canvas .react-flow__node");
  check((await page.locator(".indicators li").count()) === 5, "the readings strip does not show five readings");
  await page.click('.tabs button:has-text("Critical alerts")');
  await page.waitForSelector(".q-row", { timeout: 15000 });
  check((await page.locator(".tabs button[aria-current=page]").innerText()).includes("Critical alerts"), "the menu does not mark the alerts screen");
  const row = page.locator(".q-row").first();
  check(await waitFor(async () => /\d/.test(await row.locator(".value-num").innerText().catch(() => "")), 10000), "the queue row shows no value");
  check((await row.locator(".sev svg").count()) === 1 && (await row.innerText()).includes("Critical"), "the queue row does not show the critical state as icon and text");
  check(/\d+ (s|min)/.test(await row.locator(".q-wait-time").innerText()), "the queue row shows no wait time");
  await row.getByRole("button", { name: "Timeline" }).click();
  check(await waitFor(async () => (await page.locator(".tl li").count()) >= 2, 10000), "the escalation timeline shows no events");
  check((await page.locator(".tl").innerText()).includes("Alert opened"), "the timeline does not start with the alert opening");
  await row.getByRole("button", { name: "Open read-back" }).click();
  await page.waitForSelector("dialog.drawer[open]");
  await page.keyboard.press("Escape");
  await page.click('.tabs button:has-text("Agent flow")');
  await page.waitForSelector(".canvas .react-flow__node");
  check((await page.locator(".canvas").count()) === 1, "the agent flow is not a canvas after switching back");
  await page.close();
}

const browser = await chromium.launch();
try {
  if (PARTS.includes("demo")) await demoPart(browser);
  if (PARTS.includes("alerts")) await alertsPart(browser);
  if (PARTS.includes("tools")) await toolsPart(browser);
  if (PARTS.includes("flow")) await flowPart(browser);
  if (PARTS.includes("task")) await taskPart(browser);
  if (PARTS.includes("public")) await publicPart(browser);
  if (PARTS.includes("a11y")) await a11yPart(browser);
} finally {
  await browser.close();
}
console.log(failures.length ? `FAILED (${failures.length})` : "ui check passed");
process.exit(failures.length ? 1 : 0);
