/*
 * Copyright Codevedas Inc. 2025-present
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import { defineConfig, devices } from "@playwright/test";

const selectedBrowser = process.env.PLAYWRIGHT_BROWSER ?? "firefox";
const isHeadless = process.env.PLAYWRIGHT_HEADLESS !== "false";

if (selectedBrowser !== "firefox") {
  throw new Error(`Unsupported PLAYWRIGHT_BROWSER: ${selectedBrowser}`);
}

export default defineConfig({
  testDir: "./tests/e2e",
  timeout: 30_000,
  fullyParallel: true,
  forbidOnly: Boolean(process.env.CI),
  retries: process.env.CI ? 2 : 0,
  reporter: "list",
  use: {
    baseURL: "http://127.0.0.1:4273",
    headless: isHeadless,
    trace: "on-first-retry",
  },
  webServer: {
    command: "corepack yarn preview",
    port: 4273,
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
  },
  projects: [
    {
      name: selectedBrowser,
      use: { ...devices["Desktop Firefox"] },
    },
  ],
});
