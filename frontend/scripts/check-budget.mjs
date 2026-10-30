// Fails when what the page loads at startup is above 300 KB gzipped (PRD 11.2). It reads dist/.vite/manifest.json,
// takes the entry chunk, its static imports and its CSS (not the lazy chunks), and gzips each file.
// Usage: node scripts/check-budget.mjs [limitKb]
import { readFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { gzipSync } from "node:zlib";

const here = dirname(fileURLToPath(import.meta.url));
const dist = join(here, "..", "dist");
const manifestPath = join(dist, ".vite", "manifest.json");
const limit = (Number(process.argv[2]) || 300) * 1024;

if (!existsSync(manifestPath)) {
  console.error("FAIL: dist/.vite/manifest.json not found; run npm run build first");
  process.exit(1);
}
const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
const entry = Object.values(manifest).find((chunk) => chunk.isEntry);
if (!entry) {
  console.error("FAIL: no entry chunk in the manifest");
  process.exit(1);
}

const files = new Set();
const seen = new Set();
function visit(key) {
  if (seen.has(key)) return;
  seen.add(key);
  const chunk = manifest[key];
  if (!chunk) return;
  files.add(chunk.file);
  for (const css of chunk.css ?? []) files.add(css);
  for (const imported of chunk.imports ?? []) visit(imported); // static imports only; dynamicImports stay lazy
}
visit(Object.keys(manifest).find((key) => manifest[key] === entry));

let total = 0;
for (const file of files) {
  const size = gzipSync(readFileSync(join(dist, file))).length;
  total += size;
  console.log(`  ${file}: ${(size / 1024).toFixed(1)} KB gzipped`);
}
console.log(`initial load: ${(total / 1024).toFixed(1)} KB gzipped, limit ${(limit / 1024).toFixed(0)} KB`);
if (total > limit) {
  console.error("FAIL: the initial load is above the budget");
  process.exit(1);
}
