// Computes the WCAG 2 contrast ratio of every text and indicator pair of src/theme/tokens.css in both themes.
// Fails below 4.5 for text and 3.0 for indicators, borders and focus rings. Usage: node scripts/check-contrast.mjs
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const css = readFileSync(join(here, "..", "src", "theme", "tokens.css"), "utf8");

const tokens = {};
for (const m of css.matchAll(/--([a-z0-9-]+):\s*light-dark\(\s*(#[0-9a-fA-F]{6})\s*,\s*(#[0-9a-fA-F]{6})\s*\)/g)) {
  tokens[m[1]] = { light: m[2], dark: m[3] };
}

const TEXT = 4.5;
const UI = 3.0;
const sevs = ["critical", "recollect", "review", "normal"];
const pairs = [
  ["ink", "bg", TEXT], ["ink", "surface", TEXT], ["ink", "surface-2", TEXT],
  ["ink-2", "bg", TEXT], ["ink-2", "surface", TEXT], ["ink-2", "surface-2", TEXT],
  ["accent", "surface", TEXT], ["accent-ink", "accent", TEXT],
  ["ink", "canvas", TEXT], ["ink-2", "canvas", TEXT], ["line", "canvas", UI],
  ["line", "bg", UI], ["line", "surface", UI], ["focus", "bg", UI], ["focus", "surface", UI],
  ...sevs.flatMap((s) => [[`sev-${s}`, "surface", TEXT], [`sev-${s}`, "bg", TEXT], [`sev-${s}`, `sev-${s}-bg`, TEXT], [`ink`, `sev-${s}-bg`, TEXT]]),
];

function channel(v) {
  const c = v / 255;
  return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
}
function luminance(hex) {
  const n = parseInt(hex.slice(1), 16);
  return 0.2126 * channel((n >> 16) & 255) + 0.7152 * channel((n >> 8) & 255) + 0.0722 * channel(n & 255);
}
function ratio(a, b) {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
}

let failures = 0;
let checked = 0;
for (const theme of ["light", "dark"]) {
  for (const [fg, bg, min] of pairs) {
    if (!tokens[fg] || !tokens[bg]) {
      console.error(`FAIL: token missing for pair ${fg} on ${bg}`);
      failures++;
      continue;
    }
    const r = ratio(tokens[fg][theme], tokens[bg][theme]);
    checked++;
    if (r < min) {
      console.error(`FAIL ${theme}: ${fg} on ${bg} is ${r.toFixed(2)}:1, needs ${min}:1`);
      failures++;
    }
  }
}
// The four severities must stay distinct from one another in each theme (they are never told apart by hue alone,
// but near-identical shades would still be a poor design).
for (const theme of ["light", "dark"]) {
  for (let i = 0; i < sevs.length; i++) {
    for (let j = i + 1; j < sevs.length; j++) {
      const a = tokens[`sev-${sevs[i]}`][theme];
      const b = tokens[`sev-${sevs[j]}`][theme];
      if (a.toLowerCase() === b.toLowerCase()) {
        console.error(`FAIL ${theme}: severities ${sevs[i]} and ${sevs[j]} share the colour ${a}`);
        failures++;
      }
    }
  }
}
console.log(`${checked} contrast pairs checked in two themes, ${failures} failure(s)`);
process.exit(failures ? 1 : 0);
