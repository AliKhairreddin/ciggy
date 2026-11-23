import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "e2e",
  use: { baseURL: "http://127.0.0.1:4173", timezoneId: "UTC", locale: "en-US" },
  webServer: {
    command: "npm run dev:ui -- --port 4173 --strictPort",
    url: "http://127.0.0.1:4173",
  },
});
