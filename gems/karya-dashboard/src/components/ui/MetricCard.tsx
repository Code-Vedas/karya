/*
 * Copyright Codevedas Inc. 2025-present
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

type MetricCardProps = {
  label: string;
  trend: string;
  value: string;
};

export default function MetricCard({ label, trend, value }: MetricCardProps) {
  return (
    <article className="metric-card">
      <p className="metric-card__label">{label}</p>
      <div className="metric-card__value-row">
        <p className="metric-card__value">{value}</p>
        <p className="metric-card__trend">{trend}</p>
      </div>
    </article>
  );
}
