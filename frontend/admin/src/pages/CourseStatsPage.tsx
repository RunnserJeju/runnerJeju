import { useCallback, useEffect, useState } from 'react'

import { ApiError, getMetricsBatch, type MetricPoint } from '../api'
import { downloadCsv } from '../utils/csv'
import { kstToday } from '../utils/dates'

/** 표의 열. 순서대로 표시되고, 이름은 서버 registry의 지표 이름이다. */
const COLUMNS: { key: string; label: string }[] = [
  { key: 'course_detail_open_unique', label: '조회' },
  { key: 'runners', label: '이용자' },
  { key: 'course_runs', label: '러닝' },
  { key: 'incomplete_runs', label: '미완주' },
  { key: 'completions', label: '완주' },
  { key: 'favorites', label: '즐겨찾기' },
]

interface CourseRow {
  id: string
  name: string
  counts: Record<string, number>
}

interface Props {
  onUnauthorized: () => void
}

/** group_by=course 응답 여러 개를 코스 id 기준 한 표로 합친다. */
function mergeByCourse(batch: Record<string, MetricPoint[]>): CourseRow[] {
  const rows = new Map<string, CourseRow>()
  for (const [metric, points] of Object.entries(batch)) {
    for (const p of points) {
      if (!p.key) continue
      const row = rows.get(p.key) ?? { id: p.key, name: p.name ?? '(삭제된 코스)', counts: {} }
      row.counts[metric] = p.count
      rows.set(p.key, row)
    }
  }
  return [...rows.values()]
}

/** 코스별 누적 지표 표. 열 제목으로 정렬하고 CSV로 내려받는다. */
export default function CourseStatsPage({ onUnauthorized }: Props) {
  const [courses, setCourses] = useState<CourseRow[] | null>(null)
  const [sort, setSort] = useState(COLUMNS[0].key)
  const [error, setError] = useState<string | null>(null)

  const handleError = useCallback(
    (err: unknown) => {
      if (err instanceof ApiError && err.status === 401) {
        onUnauthorized()
        return
      }
      setError(err instanceof ApiError ? err.message : '코스 지표를 불러오지 못했어요.')
    },
    [onUnauthorized],
  )

  useEffect(() => {
    getMetricsBatch(
      COLUMNS.map((c) => c.key),
      { group_by: 'course' },
    )
      .then((batch) => {
        setCourses(mergeByCourse(batch))
        setError(null)
      })
      .catch(handleError)
  }, [handleError])

  const sorted = courses
    ? [...courses].sort(
        (a, b) => (b.counts[sort] ?? 0) - (a.counts[sort] ?? 0) || a.name.localeCompare(b.name),
      )
    : null

  const download = () => {
    if (!sorted) return
    downloadCsv(
      `courses_${kstToday()}.csv`,
      ['course_id', 'course', ...COLUMNS.map((c) => c.key)],
      sorted.map((c) => [c.id, c.name, ...COLUMNS.map((col) => c.counts[col.key] ?? 0)]),
    )
  }

  return (
    <>
      <div className="page-head">
        <h2>코스</h2>
        <button className="secondary small" onClick={download} disabled={!sorted?.length}>
          CSV 다운로드
        </button>
      </div>
      <p className="muted">
        누적 기준이에요. 열 제목을 누르면 그 기준으로 정렬돼요. 미완주 = 코스 러닝 중 검증 미통과.
      </p>
      {error && <div className="error">{error}</div>}
      {sorted == null && !error && <p className="muted">불러오는 중…</p>}
      {sorted && sorted.length === 0 && <p className="muted">아직 코스 활동이 없어요.</p>}
      {sorted && sorted.length > 0 && (
        <table className="stats-table">
          <thead>
            <tr>
              <th>코스</th>
              {COLUMNS.map((col) => (
                <th
                  key={col.key}
                  className={`sortable${col.key === sort ? ' active' : ''}`}
                  onClick={() => setSort(col.key)}
                >
                  {col.label}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {sorted.map((c) => (
              <tr key={c.id}>
                <td>
                  <strong>{c.name}</strong>
                </td>
                {COLUMNS.map((col) => (
                  <td key={col.key} className={col.key === sort ? 'active' : undefined}>
                    {c.counts[col.key] ?? 0}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </>
  )
}
