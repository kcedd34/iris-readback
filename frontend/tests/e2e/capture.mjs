// Writes the first-impression screenshots (SC-001): the panel with a critical case waiting, a released one and a review one.
import { chromium } from "@playwright/test";
import { mkdirSync } from "node:fs";

const BASE = process.env.BASE_URL || "http://127.0.0.1:8080";
const OUT = process.env.SHOT_DIR || ".local/ui";
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
mkdirSync(OUT, { recursive: true });
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1360, height: 900 } });
await page.goto(BASE);
await page.waitForSelector("select#scenario option", { state: "attached" });
for (const id of ["hemoglobin-low-not-critical", "potassium-borderline", "potassium-recollect", "hemoglobin-acute-drop"]) {
  await sleep(1200);
  await page.selectOption("#scenario", id);
  await page.click("button[type=submit]");
}
await sleep(4500);
for (const theme of ["Light", "Dark"]) {
  await page.click(`.theme button:has-text("${theme}")`);
  await sleep(400);
  await page.screenshot({ path: `${OUT}/first-impression-${theme.toLowerCase()}.png` });
}
await page.setViewportSize({ width: 390, height: 900 });
await page.click('.theme button:has-text("Light")');
await sleep(600);
await page.screenshot({ path: `${OUT}/first-impression-phone.png`, fullPage: true });
await browser.close();
console.log("captured in " + OUT);
