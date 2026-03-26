/*
 * Copyright Codevedas Inc. 2025-present
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

type ReleaseCardProps = {
  detail: string;
  title: string;
};

export default function ReleaseCard({ detail, title }: ReleaseCardProps) {
  return (
    <div className="release-card">
      <h2 className="release-card__title">{title}</h2>
      <p className="release-card__detail">{detail}</p>
    </div>
  );
}
