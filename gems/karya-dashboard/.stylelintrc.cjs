/*
 * Copyright Codevedas Inc. 2025-present
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

module.exports = {
  extends: ["stylelint-config-standard-scss"],
  rules: {
    "alpha-value-notation": null,
    "at-rule-empty-line-before": null,
    "color-function-alias-notation": null,
    "color-function-notation": null,
    "media-feature-range-notation": null,
    "scss/at-rule-no-unknown": [
      true,
      {
        ignoreAtRules: ["tailwind"],
      },
    ],
    "scss/dollar-variable-empty-line-before": null,
    "scss/dollar-variable-pattern": null,
    "selector-class-pattern": null,
    "value-keyword-case": null,
  },
};
