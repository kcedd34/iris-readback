// Fails when the built files name an address other than the few that are only strings in a library (XML namespaces,
// error-message links), so nothing in the build can load from outside (PRD 11.2, FR-018). The browser check blocks every
// other address at run time as well. Usage: node scripts/check-external.mjs
import { readdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const dist = join(dirname(fileURLToPath(import.meta.url)), "..", "dist");
const allowed = new Set(["http://www.w3.org", "https://react.dev", "https://reactflow.dev"]);
const files = [...readdirSync(join(dist, "assets")).map((f) => join(dist, "assets", f)), join(dist, "index.html")];
const found = new Map();
for (const file of files) {
  for (const match of readFileSync(file, "utf8").matchAll(/https?:\/\/[A-Za-z0-9.-]+/g)) found.set(match[0], (found.get(match[0]) ?? 0) + 1);
}
let bad = 0;
for (const [host, n] of found) {
  if (!allowed.has(host)) {
    console.error(`FAIL: the build names ${host} (${n} time(s))`);
    bad++;
  }
}
console.log(`external addresses in the build: ${[...found.keys()].join(", ") || "none"}; ${bad} not allowed`);
process.exit(bad ? 1 : 0);
