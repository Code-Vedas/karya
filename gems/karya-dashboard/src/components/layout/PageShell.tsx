/*
 * Copyright Codevedas Inc. 2025-present
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import type { PropsWithChildren, ReactNode } from 'react';

type PageShellProps = PropsWithChildren<{
  accent: ReactNode;
  hero: ReactNode;
}>;

export default function PageShell({ accent, children, hero }: PageShellProps) {
  return (
    <main className="page-shell">
      <div className="page-shell__inner">
        <section className="hero-panel">
          <div className="hero-panel__header">
            <div className="hero-panel__copy">{hero}</div>
            {accent}
          </div>
          {children}
        </section>
      </div>
    </main>
  );
}
