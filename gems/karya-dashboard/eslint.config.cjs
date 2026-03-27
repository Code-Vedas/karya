const js = require("@eslint/js");
const globals = require("globals");
const simpleImportSort = require("eslint-plugin-simple-import-sort");
const tseslint = require("typescript-eslint");

module.exports = [
  {
    ignores: [
      "**/coverage",
      "**/dist",
      "**/node_modules",
      "**/playwright-report",
      "**/test-results",
      "**/*.d.ts",
      "**/*.js",
      "**/*.tsbuildinfo",
      "**/.yarn",
    ],
  },
  js.configs.recommended,
  ...tseslint.configs.recommendedTypeChecked,
  {
    files: [
      "src/**/*.{ts,tsx}",
      "tests/**/*.ts",
      "vite.config.ts",
      "playwright.config.ts",
      "tailwind.config.ts",
    ],
    languageOptions: {
      parser: tseslint.parser,
      globals: {
        ...globals.browser,
        ...globals.node,
      },
      parserOptions: {
        project: ["./tsconfig.eslint.json"],
        tsconfigRootDir: __dirname,
        ecmaFeatures: {
          jsx: true,
        },
      },
    },
    plugins: {
      "simple-import-sort": simpleImportSort,
    },
    rules: {
      "@typescript-eslint/consistent-type-imports": "error",
      quotes: [
        "error",
        "double",
        {
          avoidEscape: true,
        },
      ],
      "simple-import-sort/exports": "error",
      "simple-import-sort/imports": "error",
    },
  },
];
