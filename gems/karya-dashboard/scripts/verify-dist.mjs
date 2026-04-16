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
const dashboardManifestPath = join(baseDir, "dist", "asset-manifest.json");
const dashboardMountId = "karya-dashboard-root";

await access(distIndex);
await access(viteManifestPath);

const distIndexHtml = await readFile(distIndex, "utf8");

if (!distIndexHtml.includes(`id="${dashboardMountId}"`)) {
  throw new Error(`Missing dashboard mount element #${dashboardMountId}`);
}

const viteManifest = JSON.parse(await readFile(viteManifestPath, "utf8"));
const dashboardEntry = viteManifest["index.html"];

if (!dashboardEntry?.file) {
  throw new Error("Missing Vite dashboard entry for index.html");
}

const collectEntryAssets = (entryName, seen = new Set()) => {
  if (seen.has(entryName)) {
    return { scripts: [], styles: [] };
  }

  const entry = viteManifest[entryName];

  if (!entry?.file) {
    throw new Error(`Missing Vite manifest entry for ${entryName}`);
  }

  seen.add(entryName);

  const scripts = [entry.file];
  const styles = [...(entry.css ?? [])];

  for (const importedEntryName of entry.imports ?? []) {
    const importedAssets = collectEntryAssets(importedEntryName, seen);
    scripts.push(...importedAssets.scripts);
    styles.push(...importedAssets.styles);
  }

  return {
    scripts: [...new Set(scripts)],
    styles: [...new Set(styles)],
  };
};

const dashboardAssets = collectEntryAssets("index.html");

const dashboardManifest = {
  version: 1,
  entrypoints: {
    dashboard: {
      source: dashboardEntry.src ?? "src/main.tsx",
      html: "/index.html",
      scripts: dashboardAssets.scripts.map((assetPath) => `/${assetPath}`),
      styles: dashboardAssets.styles.map((assetPath) => `/${assetPath}`),
      mount_id: dashboardMountId,
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
