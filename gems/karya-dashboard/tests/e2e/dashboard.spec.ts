/*
 * Copyright Codevedas Inc. 2025-present
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import { expect, test } from "@playwright/test";

test("renders the dashboard heading in Firefox", async ({ page }) => {
  await page.goto("/");

  await expect(page.getByTestId("dashboard-heading")).toHaveText(
    "Operational clarity for Karya workflows.",
  );
});
