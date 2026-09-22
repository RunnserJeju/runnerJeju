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
  getMetric,
  getMetricsBatch,
  listMetrics,
  type MetricInfo,
  type MetricPoint,
} from '../api'
import { downloadCsv } from '../utils/csv'
import { kstDaysAgo, kstToday, shortDate } from '../utils/dates'

/** KPI 카드에 쓰는 지표(누적). 이름은 서버 registry와 같다. */
const KPI_METRICS = [
  'registered_users',
  'active_users',
  'course_detail_open_unique',
  'course_detail_open',
  'runs',
  'course_runs',
  'incomplete_runs',
  'completions',
  'favorites',
  'coupons_issued',
  'coupons_used',
] as const

/** 일별 추이 탭. 값은 서버 registry의 group과 같고, 탭마다 처음 보여줄 지표를 정한다. */
const DAILY_TABS: { group: string; defaultMetric: string }[] = [
  { group: '계정', defaultMetric: 'signups' },
  { group: '러닝', defaultMetric: 'completions' },
  { group: '코스', defaultMetric: 'course_detail_open_unique' },
  { group: '스탬프·쿠폰', defaultMetric: 'coupons_issued' },
  { group: '기타', defaultMetric: 'app_open' },
]

type ChartType = 'line' | 'bar'

interface Props {
  onUnauthorized: () => void
}

function percent(part: number, whole: number): string {
  if (whole === 0) return '—'
  return `${Math.round((part / whole) * 100)}%`
}

/** group_by=none 응답에서 숫자 하나를 꺼낸다. */
function total(points: MetricPoint[] | undefined): number {
  return points?.[0]?.count ?? 0
}

export default function StatsPage({ onUnauthorized }: Props) {
  const [metrics, setMetrics] = useState<MetricInfo[] | null>(null)
  const [kpi, setKpi] = useState<Record<string, MetricPoint[]> | null>(null)
  const [daily, setDaily] = useState<MetricPoint[] | null>(null)
  const [error, setError] = useState<string | null>(null)

  const [tab, setTab] = useState(DAILY_TABS[0])
  const [dailyMetric, setDailyMetric] = useState(DAILY_TABS[0].defaultMetric)
  const [chartType, setChartType] = useState<ChartType>('line')
  const [from, setFrom] = useState(() => kstDaysAgo(7))
  const [to, setTo] = useState(() => kstToday())

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

  // 기간과 무관한 것들은 최초 1회.
  useEffect(() => {
    Promise.all([listMetrics(), getMetricsBatch([...KPI_METRICS])])
      .then(([m, k]) => {
        setMetrics(m)
        setKpi(k)
        setError(null)
      })
      .catch(handleError)
  }, [handleError])

  // 일별 추이는 기간·지표를 바꿀 때마다. 시작이 종료보다 늦으면 요청하지 않는다.
  const rangeValid = Boolean(from && to && from <= to)
  useEffect(() => {
    if (!rangeValid) return
    setDaily(null)
    getMetric(dailyMetric, { from, to, group_by: 'day' })
      .then(setDaily)
      .catch(handleError)
  }, [from, to, rangeValid, dailyMetric, handleError])

  const selectTab = (next: (typeof DAILY_TABS)[number]) => {
    setTab(next)
    setDailyMetric(next.defaultMetric)
  }

  // 현재 탭에서 일별로 볼 수 있는 지표. 서버에 지표가 늘면 자동으로 나타난다.
  const tabMetrics =
    metrics?.filter((m) => m.group === tab.group && m.group_bys.includes('day')) ?? []
  const dailyLabel = metrics?.find((m) => m.name === dailyMetric)?.label ?? dailyMetric
  const periodTotal = daily?.reduce((sum, p) => sum + p.count, 0) ?? 0

  const downloadDaily = () => {
    if (!daily) return
    downloadCsv(
      `${dailyMetric}_${from}_${to}.csv`,
      ['date', dailyMetric],
      daily.map((p) => [p.key, p.count]),
    )
  }

  const k = (name: (typeof KPI_METRICS)[number]) => total(kpi?.[name])

  return (
    <>
      <div className="page-head">
        <h2>대시보드</h2>
      </div>
      {error && <div className="error">{error}</div>}

      {kpi && (
        <div className="kpi-grid">
          <Kpi label="가입 회원" value={k('registered_users')} hint="탈퇴 제외" />
          <Kpi
            label="실이용자"
            value={k('active_users')}
            hint={`러닝 1회 이상 · ${percent(k('active_users'), k('registered_users'))}`}
          />
          <Kpi
            label="코스 조회"
            value={k('course_detail_open_unique')}
            hint={`사람·일 단위 고유 · 클릭 ${k('course_detail_open')}`}
          />
          <Kpi label="누적 러닝" value={k('runs')} hint={`코스 따라가기 ${k('course_runs')}`} />
          <Kpi
            label="미완주 러닝"
            value={k('incomplete_runs')}
            hint={`따라가기 중 ${percent(k('incomplete_runs'), k('course_runs'))}`}
          />
          <Kpi label="완주(스탬프)" value={k('completions')} />
          <Kpi label="즐겨찾기" value={k('favorites')} />
          <Kpi
            label="쿠폰 발급"
            value={k('coupons_issued')}
            hint={`사용 ${k('coupons_used')} · ${percent(k('coupons_used'), k('coupons_issued'))}`}
          />
        </div>
      )}

      <section className="card">
        <div className="chart-head">
          <h3>일별 추이</h3>
          <button className="secondary small" onClick={downloadDaily} disabled={!daily}>
            CSV 다운로드
          </button>
        </div>

        <div className="tabs">
          {DAILY_TABS.map((t) => (
            <button
              key={t.group}
              className={t.group === tab.group ? 'active' : undefined}
              onClick={() => selectTab(t)}
            >
              {t.group}
            </button>
          ))}
        </div>

        <div className="range-row">
          <select
            aria-label="지표"
            value={dailyMetric}
            onChange={(e) => setDailyMetric(e.target.value)}
          >
            {tabMetrics.map((m) => (
              <option key={m.name} value={m.name}>
                {m.label}
              </option>
            ))}
          </select>
          <input
            type="date"
            aria-label="시작일"
            value={from}
            max={to}
            onChange={(e) => setFrom(e.target.value)}
          />
          <span className="muted">~</span>
          <input
            type="date"
            aria-label="종료일"
            value={to}
            min={from}
            max={kstToday()}
            onChange={(e) => setTo(e.target.value)}
          />
          <div className="seg">
            <button
              className={chartType === 'line' ? 'active' : undefined}
              onClick={() => setChartType('line')}
            >
              선
            </button>
            <button
              className={chartType === 'bar' ? 'active' : undefined}
              onClick={() => setChartType('bar')}
            >
              막대
            </button>
          </div>
        </div>

        <p className="muted chart-total">
          {from} ~ {to} {dailyLabel} 합계 <strong>{periodTotal.toLocaleString()}</strong>
        </p>
        {!rangeValid ? (
          <p className="error">시작일이 종료일보다 늦어요.</p>
        ) : daily == null ? (
          <p className="muted">불러오는 중…</p>
        ) : (
          <DailyChart data={daily} type={chartType} label={dailyLabel} />
        )}
      </section>

    </>
  )
}

/** 일별 시계열 하나를 선 또는 막대로 그린다. 두 종류가 축·툴팁 설정을 공유한다. */
function DailyChart({
  data,
  type,
  label,
}: {
  data: MetricPoint[]
  type: ChartType
  label: string
}) {
  const axes = (
    <>
      <CartesianGrid stroke="#eceef1" vertical={false} />
      <XAxis
        dataKey="key"
        tickFormatter={(v) => shortDate(String(v))}
        tick={{ fontSize: 11 }}
        minTickGap={24}
      />
      <YAxis allowDecimals={false} tick={{ fontSize: 11 }} />
      <Tooltip labelFormatter={(v) => String(v)} formatter={(v) => [v, label]} />
    </>
  )
  const margin = { top: 8, right: 8, left: -16, bottom: 0 }

  return (
    <ResponsiveContainer width="100%" height={240}>
      {type === 'line' ? (
        <LineChart data={data} margin={margin}>
          {axes}
          <Line
            type="monotone"
            dataKey="count"
            stroke="#1a1d21"
            strokeWidth={2}
            dot={data.length <= 14}
            isAnimationActive={false}
          />
        </LineChart>
      ) : (
        <BarChart data={data} margin={margin}>
          {axes}
          <Bar dataKey="count" fill="#1a1d21" radius={[4, 4, 0, 0]} isAnimationActive={false} />
        </BarChart>
      )}
    </ResponsiveContainer>
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
