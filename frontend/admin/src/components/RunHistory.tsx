import { useCallback, useEffect, useState } from 'react'

import { ApiError, listAdminRuns, type AdminRun } from '../api'
import { kstDaysAgo, kstToday } from '../utils/dates'

const PAGE_SIZE = 50

function formatDateTime(iso: string): string {
  return new Date(iso).toLocaleString('ko-KR', {
    timeZone: 'Asia/Seoul',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false,
  })
}

function formatDuration(sec: number): string {
  const h = Math.floor(sec / 3600)
  const m = Math.floor((sec % 3600) / 60)
  const s = sec % 60
  const pad = (n: number) => String(n).padStart(2, '0')
  return h > 0 ? `${h}:${pad(m)}:${pad(s)}` : `${m}:${pad(s)}`
}

interface Props {
  onUnauthorized: () => void
}

/** 코스 지표의 '러닝 기록' 탭. 모든 회원의 러닝을 한 행씩, 기간별·시간순으로 페이지를 넘겨 본다. */
export default function RunHistory({ onUnauthorized }: Props) {
  // 기본은 오늘 하루. draft는 입력 중인 값, applied는 실제로 조회한 값이다.
  const [draft, setDraft] = useState({ from: kstToday(), to: kstToday() })
  const [applied, setApplied] = useState(draft)
  const [order, setOrder] = useState<'asc' | 'desc'>('desc')
  const [page, setPage] = useState(0)
  const [total, setTotal] = useState(0)
  const [runs, setRuns] = useState<AdminRun[] | null>(null)
  const [error, setError] = useState<string | null>(null)

  const handleError = useCallback(
    (err: unknown) => {
      if (err instanceof ApiError && err.status === 401) {
        onUnauthorized()
        return
      }
      setError(err instanceof ApiError ? err.message : '러닝 기록을 불러오지 못했어요.')
    },
    [onUnauthorized],
  )

  useEffect(() => {
    // 기간·페이지를 연달아 바꾸면 늦게 온 옛 응답이 새 목록을 덮을 수 있어 버린다.
    let stale = false
    setRuns(null)
    listAdminRuns(applied.from, applied.to, order, PAGE_SIZE, page * PAGE_SIZE)
      .then((result) => {
        if (stale) return
        setRuns(result.items)
        setTotal(result.total)
        setError(null)
      })
      .catch((err) => {
        if (!stale) handleError(err)
      })
    return () => {
      stale = true
    }
  }, [applied, order, page, handleError])

  const apply = (range: { from: string; to: string }) => {
    setDraft(range)
    setApplied(range)
    setPage(0)
  }

  const invalid = !draft.from || !draft.to || draft.from > draft.to
  const pageCount = Math.max(1, Math.ceil(total / PAGE_SIZE))

  return (
    <>
      <form
        className="run-filter"
        onSubmit={(event) => {
          event.preventDefault()
          if (!invalid) apply(draft)
        }}
      >
        <label htmlFor="run-from">조회 기간</label>
        <input
          id="run-from"
          type="date"
          value={draft.from}
          max={draft.to || undefined}
          onChange={(e) => setDraft({ ...draft, from: e.target.value })}
        />
        <span className="muted">~</span>
        <input
          id="run-to"
          type="date"
          value={draft.to}
          min={draft.from || undefined}
          onChange={(e) => setDraft({ ...draft, to: e.target.value })}
        />
        <button type="submit" className="small" disabled={invalid}>
          조회
        </button>
        <button
          type="button"
          className="secondary small"
          onClick={() => apply({ from: kstToday(), to: kstToday() })}
        >
          오늘
        </button>
        <button
          type="button"
          className="secondary small"
          onClick={() => apply({ from: kstDaysAgo(7), to: kstToday() })}
        >
          최근 7일
        </button>
      </form>
      {draft.from > draft.to && draft.to && (
        <div className="error">시작일이 종료일보다 늦을 수 없어요.</div>
      )}

      <p className="muted run-summary">
        {applied.from === applied.to ? applied.from : `${applied.from} ~ ${applied.to}`} (한국 시간) ·{' '}
        {runs ? `${total.toLocaleString()}건` : '불러오는 중…'}
      </p>

      {error && <div className="error">{error}</div>}
      {runs && runs.length === 0 && <p className="muted">이 기간에 러닝 기록이 없어요.</p>}
      {runs && runs.length > 0 && (
        <table className="users-table">
          <thead>
            <tr>
              <th
                className="sortable active"
                onClick={() => {
                  setOrder(order === 'asc' ? 'desc' : 'asc')
                  setPage(0)
                }}
              >
                시작 시각
                <span className="sort-mark">{order === 'asc' ? '▲' : '▼'}</span>
              </th>
              <th>회원</th>
              <th>코스</th>
              <th>거리</th>
              <th>시간</th>
            </tr>
          </thead>
          <tbody>
            {runs.map((r) => (
              <tr key={r.id}>
                <td className="nowrap">{formatDateTime(r.started_at)}</td>
                <td>
                  <strong>{r.nickname ?? <span className="muted">(탈퇴/미설정)</span>}</strong>
                  {r.email && <div className="muted">{r.email}</div>}
                </td>
                <td>{r.course_name ?? <span className="muted">코스 없이 달림</span>}</td>
                <td className="nowrap">{r.distance_km.toFixed(2)}km</td>
                <td className="nowrap muted">{formatDuration(r.duration_sec)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      {pageCount > 1 && (
        <div className="pager">
          <button className="secondary small" disabled={page === 0} onClick={() => setPage(page - 1)}>
            이전
          </button>
          <span className="muted">
            {page + 1} / {pageCount}
          </span>
          <button
            className="secondary small"
            disabled={page + 1 >= pageCount}
            onClick={() => setPage(page + 1)}
          >
            다음
          </button>
        </div>
      )}
    </>
  )
}
