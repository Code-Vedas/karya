/*
 * Copyright Codevedas Inc. 2025-present
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */
var __assign = (this && this.__assign) || function () {
    __assign = Object.assign || function(t) {
        for (var s, i = 1, n = arguments.length; i < n; i++) {
            s = arguments[i];
            for (var p in s) if (Object.prototype.hasOwnProperty.call(s, p))
                t[p] = s[p];
        }
        return t;
    };
    return __assign.apply(this, arguments);
};
import { defineConfig, devices } from '@playwright/test';
export default defineConfig({
    testDir: './tests/e2e',
    timeout: 30000,
    fullyParallel: true,
    forbidOnly: Boolean(process.env.CI),
    retries: process.env.CI ? 2 : 0,
    reporter: 'list',
    use: {
        baseURL: 'http://127.0.0.1:4273',
        trace: 'on-first-retry',
    },
    webServer: {
        command: 'corepack yarn preview',
        port: 4273,
        reuseExistingServer: !process.env.CI,
        timeout: 120000,
    },
    projects: [
        {
            name: 'firefox',
            use: __assign({}, devices['Desktop Firefox']),
        },
    ],
});
