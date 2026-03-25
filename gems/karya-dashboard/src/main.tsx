/*
 * Copyright Codevedas Inc. 2025-present
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import React from "react";
import ReactDOM from "react-dom/client";
import App from "./app/App";
import "./styles/index.scss";

const rootElement = document.getElementById("root");

if (!rootElement) {
  throw new Error("Karya dashboard could not find the \"#root\" mount element.");
}

ReactDOM.createRoot(rootElement).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
