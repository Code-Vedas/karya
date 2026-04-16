/*
 * Copyright Codevedas Inc. 2025-present
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import "./styles/index.scss";

import { StrictMode } from "react";
import { createRoot } from "react-dom/client";

import App from "./app/App";

const dashboardMountId = "karya-dashboard-root";
const rootElement = document.getElementById(dashboardMountId);

if (rootElement === null) {
  throw new Error(`Dashboard root element #${dashboardMountId} was not found.`);
}

createRoot(rootElement).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
