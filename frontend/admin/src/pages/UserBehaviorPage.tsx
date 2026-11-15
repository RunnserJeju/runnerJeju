import { useCallback, useEffect, useState } from 'react'
import { Bar, BarChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts'

import { ApiError, getScreenStats, type ScreenStat } from '../api'
import { downloadCsv } from '../utils/csv'
import { kstDaysAgo, kstToday } from '../utils/dates'

/** 앱이 보내는 화면 이름(탭·라우트 이름) → 표시명. 없는 이름은 그대로 보여준다. */
const SCREEN_LABELS: Record<string, string> = {
  home: '홈',
  community: '커뮤니티',
  running: '러닝(지도)',
  stamp: '스탬프',
  profile: '마이페이지',
  run: '러닝 중',
  run_result: '러닝 결과',
  run_share: '러닝 공유',
  run_detail: '러닝 기록 상세',
  notification: '알림',
  event_detail: '이벤트 상세',
  running_week: '러닝위크',
  participation_form: '러닝위크 참가 신청',
  incomplete_runs: '이어 달리기 목록',
  member_info: '회원 정보',
  completed_courses: '완주 코스',
  favorite_courses: '찜한 코스',
  coupon_list: '내 쿠폰',
  coupon_use: '쿠폰 사용',
  reward_claim: '경품 수령',
  login: '로그인',
  nickname_setup: '닉네임 설정',
}

const COLUMNS: { key: keyof ScreenStat; label: string }[] = [
  { key: 'views', label: 'PV' },
  { key: 'users', label: '사용자' },
  { key: 'avg_sec', label: '평균 체류' },
  { key: 'median_sec', label: '중앙값' },
  { key: 'total_sec', label: '총 체류' },
]

const CHARTS: { key: 'views' | 'avg_sec'; label: string }[] = [
  { key: 'views', label: 'PV' },
  { key: 'avg_sec', label: '평균 체류시간' },
]

const labelOf = (screen: string) => SCREEN_LABELS[screen] ?? screen

/** 초 → '1시간 2분' / '3분 20초' / '45초'. */
function formatDwell(sec: number | null): string {
  if (sec == null) return '—'
  const s = Math.round(sec)
  if (s >= 3600) return `${Math.floor(s / 3600)}시간 ${Math.floor((s % 3600) / 60)}분`
  if (s >= 60) return `${Math.floor(s / 60)}분 ${s % 60}초`
  return `${s}초`
}

function formatCell(row: ScreenStat, key: keyof ScreenStat): string {
  const value = row[key]
  if (key === 'views' || key === 'users') return Number(value).toLocaleString()
  return formatDwell(value as number | null)
}

interface Props {
  onUnauthorized: () => void
}

/** 화면별 PV와 체류시간. 앱의 screen_view·app_background 로그로 계산한다. */
export default function UserBehaviorPage({ onUnauthorized }: Props) {
  const [from, setFrom] = useState(() => kstDaysAgo(7))
  const [to, setTo] = useState(() => kstToday())
  const [rows, setRows] = useState<ScreenStat[] | null>(null)
  const [sort, setSort] = useState<keyof ScreenStat>('views')
  const [chart, setChart] = useState(CHARTS[0])
  const [error, setError] = useState<string | null>(null)

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

  const rangeValid = Boolean(from && to && from <= to)
  useEffect(() => {
    if (!rangeValid) return
    // 기간을 연달아 바꾸면 늦게 온 옛 응답이 새 기간을 덮을 수 있어 버린다.
    let stale = false
    setRows(null)
    getScreenStats(from, to)
      .then((result) => {
        if (stale) return
        setRows(result)
        setError(null)
      })
      .catch((err) => {
        if (!stale) handleError(err)
      })
    return () => {
      stale = true
    }
  }, [from, to, rangeValid, handleError])

  const sorted = rows
    ? [...rows].sort(
        (a, b) => Number(b[sort] ?? -1) - Number(a[sort] ?? -1) || a.screen.localeCompare(b.screen),
      )
    : null
  const chartData = rows
    ? [...rows]
        .sort((a, b) => (b[chart.key] ?? 0) - (a[chart.key] ?? 0))
        .map((r) => ({ name: labelOf(r.screen), value: r[chart.key] ?? 0 }))
    : []
  const totalViews = rows?.reduce((sum, r) => sum + r.views, 0) ?? 0

  const download = () => {
    if (!sorted) return
    downloadCsv(
      `screens_${from}_${to}.csv`,
      ['screen', 'label', ...COLUMNS.map((c) => c.key)],
      sorted.map((r) => [r.screen, labelOf(r.screen), ...COLUMNS.map((c) => r[c.key] ?? '')]),
    )
  }

  return (
    <>
      <div className="page-head">
        <h2>유저 행동</h2>
        <button className="secondary small" onClick={download} disabled={!sorted?.length}>
          CSV 다운로드
        </button>
      </div>
      <p className="muted page-desc">
        화면별 조회 수(PV)와 체류시간이에요. 체류시간은 화면에 들어온 뒤 다른 화면으로 가거나 앱을
        내릴 때까지예요.
      </p>
      {error && <div className="error">{error}</div>}

      <section className="card">
        <div className="chart-head">
          <h3>화면별 {chart.label}</h3>
        </div>
        <div className="range-row">
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
            {CHARTS.map((c) => (
              <button
                key={c.key}
                className={c.key === chart.key ? 'active' : undefined}
                onClick={() => setChart(c)}
              >
                {c.label}
              </button>
            ))}
          </div>
        </div>
        <p className="muted chart-total">
          {from} ~ {to} 전체 PV <strong>{totalViews.toLocaleString()}</strong>
        </p>
        {!rangeValid ? (
          <p className="error">
            {!from || !to ? '시작일과 종료일을 모두 골라 주세요.' : '시작일이 종료일보다 늦어요.'}
          </p>
        ) : rows == null ? (
          <p className="muted">불러오는 중…</p>
        ) : rows.length === 0 ? (
          <p className="muted">이 기간에는 화면 조회 로그가 없어요.</p>
        ) : (
          <ResponsiveContainer width="100%" height={Math.max(160, chartData.length * 30)}>
            <BarChart data={chartData} layout="vertical" margin={{ top: 4, right: 16, left: 8, bottom: 0 }}>
              <CartesianGrid stroke="#eceef1" horizontal={false} />
              <XAxis
                type="number"
                allowDecimals={false}
                tick={{ fontSize: 11 }}
                tickFormatter={(v) => (chart.key === 'avg_sec' ? formatDwell(Number(v)) : String(v))}
              />
              <YAxis type="category" dataKey="name" width={120} tick={{ fontSize: 12 }} />
              <Tooltip
                formatter={(v) => [
                  chart.key === 'avg_sec' ? formatDwell(Number(v)) : Number(v).toLocaleString(),
                  chart.label,
                ]}
              />
              <Bar dataKey="value" fill="#1a1d21" radius={[0, 4, 4, 0]} isAnimationActive={false} />
            </BarChart>
          </ResponsiveContainer>
        )}
      </section>

      {sorted && sorted.length > 0 && (
        <table className="stats-table">
          <thead>
            <tr>
              <th>화면</th>
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
            {sorted.map((r) => (
              <tr key={r.screen}>
                <td>
                  <strong>{labelOf(r.screen)}</strong> <span className="muted">{r.screen}</span>
                </td>
                {COLUMNS.map((col) => (
                  <td key={col.key} className={col.key === sort ? 'active' : undefined}>
                    {formatCell(r, col.key)}
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
