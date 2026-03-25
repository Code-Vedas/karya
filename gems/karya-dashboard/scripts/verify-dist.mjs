/*
 * Copyright Codevedas Inc. 2025-present
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import { access, readFile, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const baseDir = join(__dirname, "..");

const distIndex = join(baseDir, "dist", "index.html");
const viteManifestPath = join(baseDir, "dist", ".vite", "manifest.json");
const dashboardManifestPath = join(
  baseDir,
  "dist",
  "asset-manifest.json",
);

await access(distIndex);
await access(viteManifestPath);

const viteManifest = JSON.parse(await readFile(viteManifestPath, "utf8"));
const dashboardEntry = viteManifest["index.html"];

if (!dashboardEntry || !dashboardEntry.file) {
  throw new Error("Missing Vite dashboard entry for index.html");
}

const dashboardManifest = {
  version: 1,
  entrypoints: {
    dashboard: {
      source: dashboardEntry.src ?? "src/main.tsx",
      html: "/index.html",
      scripts: [`/${dashboardEntry.file}`],
      styles: (dashboardEntry.css ?? []).map((assetPath) => `/${assetPath}`),
      mount_id: "karya-dashboard-root",
    },
  },
};

await writeFile(
  dashboardManifestPath,
  `${JSON.stringify(dashboardManifest, null, 2)}\n`,
  "utf8",
);

console.log(
  `Verified packaged assets: ${distIndex} and ${dashboardManifestPath}`,
);
