import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";

// The build output goes to dist/ (ignored by the repository allowlist; it is built in the image).
// The manifest lets scripts/check-budget.mjs find what the page loads at startup.
export default defineConfig({
  plugins: [react()],
  build: { outDir: "dist", manifest: true, sourcemap: false },
  server: {
    proxy: {
      "/readback": "http://127.0.0.1:52790",
      "/workflow": "http://127.0.0.1:52790",
    },
  },
  test: { environment: "jsdom", globals: true, setupFiles: ["./tests/setup.ts"], include: ["tests/**/*.test.{ts,tsx}"] },
});
