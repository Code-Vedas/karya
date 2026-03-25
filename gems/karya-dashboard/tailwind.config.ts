/*
 * Copyright Codevedas Inc. 2025-present
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import type { Config } from 'tailwindcss';

export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        ink: '#0f172a',
        sand: '#f8f5ef',
        ember: '#f97316',
        tide: '#0f766e',
      },
      fontFamily: {
        display: ['"Space Grotesk"', 'sans-serif'],
        body: ['"Plus Jakarta Sans"', 'sans-serif'],
      },
      boxShadow: {
        panel: '0 20px 50px rgba(15, 23, 42, 0.12)',
      },
    },
  },
  plugins: [],
} satisfies Config;
