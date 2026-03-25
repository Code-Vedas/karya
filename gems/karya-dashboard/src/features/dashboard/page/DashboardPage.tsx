/*
 * Copyright Codevedas Inc. 2025-present
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import PageShell from '../../../components/layout/PageShell';
import MetricCard from '../../../components/ui/MetricCard';
import ReleaseCard from '../../../components/ui/ReleaseCard';
import {
  dashboardMetrics,
  dashboardReleases,
} from '../data/dashboardContent';

export default function DashboardPage() {
  return (
    <PageShell
      accent={(
        <div className="hero-accent">
          <p className="hero-accent__eyebrow">Current mode</p>
          <p className="hero-accent__title">Build-ready UI package</p>
        </div>
      )}
      hero={(
        <>
          <p className="hero-badge">karya-dashboard</p>
          <h1 className="hero-title" data-testid="dashboard-heading">
            Operational clarity for Karya workflows.
          </h1>
          <p className="hero-summary">
            The UI gem ships a focused control surface for queues, incidents, and
            release readiness without coupling frontend assets to the core gem.
          </p>
        </>
      )}
    >
      <div className="metric-grid">
        {dashboardMetrics.map((metric) => (
          <MetricCard
            key={metric.label}
            label={metric.label}
            trend={metric.trend}
            value={metric.value}
          />
        ))}
      </div>

      <section className="content-grid">
        <article className="release-strip">
          <p className="section-label section-label--muted">Release strip</p>
          <div className="release-strip__stack">
            {dashboardReleases.map((release) => (
              <ReleaseCard
                key={release.title}
                detail={release.detail}
                title={release.title}
              />
            ))}
          </div>
        </article>

        <article className="coverage-panel">
          <p className="section-label section-label--accent">Smoke coverage</p>
          <p className="coverage-panel__title">Firefox E2E wired</p>
          <p className="coverage-panel__body">
            The package builds with Vite, previews the compiled assets, and
            verifies the primary dashboard heading in Playwright.
          </p>
          <div className="coverage-panel__stack">
            <p className="coverage-panel__meta-label">Frontend stack</p>
            <p className="coverage-panel__meta-value">
              React 19, TypeScript, Tailwind CSS, Vite
            </p>
          </div>
        </article>
      </section>
    </PageShell>
  );
}
