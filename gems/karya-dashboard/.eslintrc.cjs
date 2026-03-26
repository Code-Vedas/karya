/*
 * Copyright Codevedas Inc. 2025-present
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

module.exports = {
  root: true,
  env: {
    browser: true,
    es2022: true,
    node: true,
  },
  parser: "@typescript-eslint/parser",
  parserOptions: {
    project: ["./tsconfig.eslint.json"],
    tsconfigRootDir: __dirname,
    ecmaFeatures: {
      jsx: true,
    },
  },
  extends: ["airbnb", "airbnb/hooks", "airbnb-typescript"],
  settings: {
    "import/resolver": {
      typescript: {
        project: ["./tsconfig.eslint.json"],
      },
    },
  },
  rules: {
    "import/extensions": [
      "error",
      "ignorePackages",
      {
        ts: "never",
        tsx: "never",
      },
    ],
    "@typescript-eslint/quotes": ["error", "double"],
    "react/function-component-definition": [
      "error",
      {
        namedComponents: "function-declaration",
        unnamedComponents: "arrow-function",
      },
    ],
    "react/jsx-filename-extension": [
      "error",
      {
        extensions: [".tsx"],
      },
    ],
    "react/jsx-wrap-multilines": "off",
    "react/react-in-jsx-scope": "off",
  },
  overrides: [
    {
      files: ["vite.config.ts", "playwright.config.ts", "tailwind.config.ts"],
      rules: {
        "import/no-extraneous-dependencies": "off",
      },
    },
    {
      files: ["tests/**/*.ts"],
      rules: {
        "import/no-extraneous-dependencies": "off",
      },
    },
  ],
};
