import { useCallback, useEffect, useState } from 'react'
import {
  Bar,
  BarChart,
  CartesianGrid,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts'

import {
  ApiError,
  getCourseStats,
  getDailyStats,
  getStampDistribution,
  getStatsOverview,
  listCoupons,
  type CouponSummary,
  type CourseStats,
  type DailyStats,
  type StampDistribution,
  type StatsOverview,
} from '../api'

const PERIODS = [7, 30, 90] as const
type Period = (typeof PERIODS)[number]

type DailyMetric = Exclude<keyof DailyStats, 'date'>
const DAILY_METRICS: { key: DailyMetric; label: string }[] = [
  { key: 'signups', label: '가입' },
  { key: 'views', label: '코스 조회' },
  { key: 'runs', label: '러닝' },
  { key: 'completions', label: '완주' },
  { key: 'favorites', label: '즐겨찾기' },
  { key: 'coupons_issued', label: '쿠폰 발급' },
]

type CourseSortKey = Exclude<keyof CourseStats, 'id' | 'name' | 'address'>
const COURSE_COLUMNS: { key: CourseSortKey; label: string }[] = [
  { key: 'view_count', label: '조회' },
  { key: 'runner_count', label: '이용자' },
  { key: 'run_count', label: '러닝' },
  { key: 'incomplete_run_count', label: '미완주' },
  { key: 'completed_count', label: '완주' },
  { key: 'favorite_count', label: '즐겨찾기' },
]

interface Props {
  onUnauthorized: () => void
}

/** 'YYYY-MM-DD' → 'M/D'. 차트 축 라벨용. */
function shortDate(iso: string): string {
  const [, m, d] = iso.split('-')
  return `${Number(m)}/${Number(d)}`
}

function percent(part: number, whole: number): string {
  if (whole === 0) return '—'
  return `${Math.round((part / whole) * 100)}%`
}

export default function StatsPage({ onUnauthorized }: Props) {
  const [overview, setOverview] = useState<StatsOverview | null>(null)
  const [courses, setCourses] = useState<CourseStats[] | null>(null)
  const [stamps, setStamps] = useState<StampDistribution[] | null>(null)
  const [coupons, setCoupons] = useState<CouponSummary[] | null>(null)
  const [daily, setDaily] = useState<DailyStats[] | null>(null)
  const [error, setError] = useState<string | null>(null)

  const [period, setPeriod] = useState<Period>(30)
  const [metric, setMetric] = useState<DailyMetric>('views')
  const [courseSort, setCourseSort] = useState<CourseSortKey>('view_count')

  const handleError = useCallback(
    (err: unknown) => {
      if (err instanceof ApiError && err.status === 401) {
        onUnauthorized()
        return
      }
      setError(err instanceof ApiError ? err.message : '지표를 불러오지 못했어요.')
    },
    [onUnauthorized],
  )

  // 기간과 무관한 지표는 최초 1회만 읽는다.
  useEffect(() => {
    Promise.all([getStatsOverview(), getCourseStats(), getStampDistribution(), listCoupons()])
      .then(([o, c, s, cp]) => {
        setOverview(o)
        setCourses(c)
        setStamps(s)
        setCoupons(cp)
        setError(null)
      })
      .catch(handleError)
  }, [handleError])

  // 일별 추이는 기간을 바꿀 때마다 다시 읽는다.
  useEffect(() => {
    setDaily(null)
    getDailyStats(period).then(setDaily).catch(handleError)
  }, [period, handleError])

  const sortedCourses = courses
    ? [...courses].sort(
        (a, b) => b[courseSort] - a[courseSort] || a.name.localeCompare(b.name),
      )
    : null

  const periodTotal = daily?.reduce((sum, d) => sum + d[metric], 0) ?? 0
  const metricLabel = DAILY_METRICS.find((m) => m.key === metric)!.label

  return (
    <>
      <div className="page-head">
        <h2>지표</h2>
      </div>
      {error && <div className="error">{error}</div>}

      {overview && (
        <div className="kpi-grid">
          <Kpi label="가입 회원" value={overview.registered_users} hint="탈퇴 제외" />
          <Kpi
            label="실이용자"
            value={overview.active_users}
            hint={`러닝 1회 이상 · ${percent(overview.active_users, overview.registered_users)}`}
          />
          <Kpi label="코스 조회" value={overview.total_views} hint="사람·일 단위 고유" />
          <Kpi label="누적 러닝" value={overview.total_runs} hint={`코스 따라가기 ${overview.course_runs}`} />
          <Kpi
            label="미완주 러닝"
            value={overview.incomplete_runs}
            hint={`따라가기 중 ${percent(overview.incomplete_runs, overview.course_runs)}`}
          />
          <Kpi label="완주(스탬프)" value={overview.total_completions} />
          <Kpi label="즐겨찾기" value={overview.total_favorites} />
          <Kpi
            label="쿠폰 발급"
            value={overview.coupons_issued}
            hint={`사용 ${overview.coupons_used} · ${percent(overview.coupons_used, overview.coupons_issued)}`}
          />
        </div>
      )}

      <section className="card">
        <div className="chart-head">
          <h3>일별 추이</h3>
          <div className="seg">
            {PERIODS.map((p) => (
              <button
                key={p}
                className={p === period ? 'active' : undefined}
                onClick={() => setPeriod(p)}
              >
                {p}일
              </button>
            ))}
          </div>
        </div>
        <div className="seg wrap">
          {DAILY_METRICS.map((m) => (
            <button
              key={m.key}
              className={m.key === metric ? 'active' : undefined}
              onClick={() => setMetric(m.key)}
            >
              {m.label}
            </button>
          ))}
        </div>
        <p className="muted chart-total">
          최근 {period}일 {metricLabel} 합계 <strong>{periodTotal.toLocaleString()}</strong>
        </p>
        {daily == null ? (
          <p className="muted">불러오는 중…</p>
        ) : (
          <ResponsiveContainer width="100%" height={240}>
            <LineChart data={daily} margin={{ top: 8, right: 8, left: -16, bottom: 0 }}>
              <CartesianGrid stroke="#eceef1" vertical={false} />
              <XAxis
                dataKey="date"
                tickFormatter={shortDate}
                tick={{ fontSize: 11 }}
                minTickGap={24}
              />
              <YAxis allowDecimals={false} tick={{ fontSize: 11 }} />
              <Tooltip labelFormatter={(v) => String(v)} formatter={(v) => [v, metricLabel]} />
              <Line
                type="monotone"
                dataKey={metric}
                stroke="#1a1d21"
                strokeWidth={2}
                dot={period === 7}
                isAnimationActive={false}
              />
            </LineChart>
          </ResponsiveContainer>
        )}
      </section>

      <h3>코스별</h3>
      <p className="muted">열 제목을 누르면 그 기준으로 정렬돼요. 미완주 = 러닝 중 검증 미통과.</p>
      {sortedCourses == null && !error && <p className="muted">불러오는 중…</p>}
      {sortedCourses && sortedCourses.length === 0 && (
        <p className="muted">등록된 코스가 없어요.</p>
      )}
      {sortedCourses && sortedCourses.length > 0 && (
        <table className="stats-table">
          <thead>
            <tr>
              <th>코스</th>
              {COURSE_COLUMNS.map((col) => (
                <th
                  key={col.key}
                  className={`sortable${col.key === courseSort ? ' active' : ''}`}
                  onClick={() => setCourseSort(col.key)}
                >
                  {col.label}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {sortedCourses.map((c) => (
              <tr key={c.id}>
                <td>
                  <strong>{c.name}</strong>
                  <div className="muted">{c.address}</div>
                </td>
                {COURSE_COLUMNS.map((col) => (
                  <td key={col.key} className={col.key === courseSort ? 'active' : undefined}>
                    {c[col.key]}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      )}

      <div className="two-col">
        <section className="card">
          <h3>스탬프 보유 분포</h3>
          <p className="muted">스탬프 n개를 가진 회원 수. 0개는 가입 회원 중 미획득.</p>
          {stamps == null ? (
            <p className="muted">불러오는 중…</p>
          ) : (
            <ResponsiveContainer width="100%" height={200}>
              <BarChart data={stamps} margin={{ top: 8, right: 8, left: -16, bottom: 0 }}>
                <CartesianGrid stroke="#eceef1" vertical={false} />
                <XAxis dataKey="stamps" tick={{ fontSize: 11 }} tickFormatter={(v) => `${v}개`} />
                <YAxis allowDecimals={false} tick={{ fontSize: 11 }} />
                <Tooltip labelFormatter={(v) => `스탬프 ${v}개`} formatter={(v) => [v, '회원']} />
                <Bar dataKey="users" fill="#1a1d21" radius={[4, 4, 0, 0]} isAnimationActive={false} />
              </BarChart>
            </ResponsiveContainer>
          )}
        </section>

        <section className="card">
          <h3>쿠폰</h3>
          {coupons == null && <p className="muted">불러오는 중…</p>}
          {coupons && coupons.length === 0 && <p className="muted">만든 쿠폰이 없어요.</p>}
          {coupons && coupons.length > 0 && (
            <table className="stats-table flat">
              <thead>
                <tr>
                  <th>쿠폰</th>
                  <th>발급</th>
                  <th>사용</th>
                </tr>
              </thead>
              <tbody>
                {coupons.map((cp) => (
                  <tr key={cp.id}>
                    <td>
                      <strong>{cp.name}</strong>
                      <div className="muted">{cp.benefit}</div>
                    </td>
                    <td>{cp.issued_count}</td>
                    <td>
                      {cp.used_count}
                      <span className="muted"> ({percent(cp.used_count, cp.issued_count)})</span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </section>
      </div>
    </>
  )
}

function Kpi({ label, value, hint }: { label: string; value: number; hint?: string }) {
  return (
    <div className="kpi">
      <div className="kpi-label">{label}</div>
      <div className="kpi-value">{value.toLocaleString()}</div>
      {hint && <div className="kpi-hint">{hint}</div>}
    </div>
  )
}
