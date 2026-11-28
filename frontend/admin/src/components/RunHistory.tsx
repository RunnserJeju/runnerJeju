import { useCallback, useEffect, useState, type ReactNode } from 'react'

import { ApiError, listAdminRuns, type AdminRun } from '../api'
import { downloadCsv } from '../utils/csv'
import { kstDaysAgo, kstToday } from '../utils/dates'
import Modal from './Modal'

const PAGE_SIZE = 50
/** CSV는 서버 상한(200)씩 끝까지 받아 모은다. */
const CSV_BATCH = 200

/** CSV용 KST 'YYYY-MM-DD HH:mm:ss'. */
function kstStamp(iso: string): string {
  return new Date(iso).toLocaleString('sv-SE', { timeZone: 'Asia/Seoul', hour12: false })
}

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

const COMPLETION: Record<AdminRun['completion'], ReactNode> = {
  completed: <strong>완주</strong>,
  incomplete: <span className="muted">미완주</span>,
  pending: <span className="muted">검증 중</span>,
  none: <span className="muted">-</span>,
}

/** 일치율(0~1)을 소수점 버린 백분율로. 부동소수 오차(0.29*100=28.999…)로 한 칸 내려가지 않게 보정한다. */
function formatMatch(rate: number | null): ReactNode {
  if (rate == null) return <span className="muted">-</span>
  return `경로 ${Math.floor(rate * 100 + 1e-6)}% 일치`
}

/** 기록 한 건을 구간별로. 이어달리기가 없으면 전체가 1회이고, 완주 표시는 마지막 구간에 붙는다. */
function RunDetail({ run, onClose }: { run: AdminRun; onClose: () => void }) {
  const segments = run.segments.length
    ? run.segments
    : [{ started_at: run.started_at, distance_km: run.distance_km, duration_sec: run.duration_sec }]
  return (
    <Modal
      title={
        <>
          {run.nickname ?? '(탈퇴/미설정)'} · {run.course_name ?? '코스 없이 달림'}
        </>
      }
      onClose={onClose}
    >
      <p className="muted">
        총 {segments.length}회 · {run.distance_km.toFixed(2)}km · {formatDuration(run.duration_sec)} ·{' '}
        {formatMatch(run.match_rate)}
      </p>
      <table className="users-table">
        <thead>
          <tr>
            <th>회차</th>
            <th>시작 시각</th>
            <th>거리</th>
            <th>시간</th>
            <th>결과</th>
          </tr>
        </thead>
        <tbody>
          {segments.map((s, i) => {
            const last = i === segments.length - 1
            return (
              <tr key={s.started_at}>
                <td className="nowrap">{i + 1}회</td>
                <td className="nowrap">{formatDateTime(s.started_at)}</td>
                <td className="nowrap">{s.distance_km.toFixed(2)}km</td>
                <td className="nowrap muted">{formatDuration(s.duration_sec)}</td>
                <td className="nowrap">
                  {last ? COMPLETION[run.completion] : <span className="muted">미완주</span>}
                </td>
              </tr>
            )
          })}
        </tbody>
      </table>
    </Modal>
  )
}

interface Props {
  onUnauthorized: () => void
}

/** 코스 지표의 '러닝 기록' 탭. 모든 회원의 러닝을 한 행씩, 기간별·시간순으로 페이지를 넘겨 본다. */
export default function RunHistory({ onUnauthorized }: Props) {
  // 기본은 오늘 하루. draft는 입력 중인 값, applied는 실제로 조회한 값이다.
  const [draft, setDraft] = useState({ from: kstToday(), to: kstToday() })
  const [applied, setApplied] = useState(draft)
  const [searchDraft, setSearchDraft] = useState('')
  const [search, setSearch] = useState('')
  const [order, setOrder] = useState<'asc' | 'desc'>('desc')
  const [page, setPage] = useState(0)
  const [total, setTotal] = useState(0)
  const [runs, setRuns] = useState<AdminRun[] | null>(null)
  /** 행을 눌러 구간별로 펼쳐 보는 기록. */
  const [detail, setDetail] = useState<AdminRun | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [exporting, setExporting] = useState(false)

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
    listAdminRuns(applied.from, applied.to, order, PAGE_SIZE, page * PAGE_SIZE, search)
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
  }, [applied, order, page, search, handleError])

  const apply = (range: { from: string; to: string }) => {
    setDraft(range)
    setApplied(range)
    setPage(0)
  }

  /** 화면의 페이지가 아니라 조회 조건 전체를 받는다. */
  const download = async () => {
    setExporting(true)
    try {
      const all: AdminRun[] = []
      for (let offset = 0; ; offset += CSV_BATCH) {
        const result = await listAdminRuns(applied.from, applied.to, order, CSV_BATCH, offset, search)
        all.push(...result.items)
        if (result.items.length < CSV_BATCH || all.length >= result.total) break
      }
      downloadCsv(
        `runs_${applied.from}_${applied.to}.csv`,
        [
          'run_id', 'started_at_kst', 'ended_at_kst', 'user_id', 'nickname', 'email',
          'course_id', 'course', 'distance_km', 'duration_sec', 'completion', 'match_rate',
          'app_killed', 'segments',
        ],
        all.map((r) => [
          r.id,
          kstStamp(r.started_at),
          kstStamp(r.ended_at),
          r.user_id,
          r.nickname,
          r.email,
          r.course_id,
          r.course_name,
          r.distance_km,
          r.duration_sec,
          r.completion,
          r.match_rate,
          r.app_killed ? 1 : 0,
          Math.max(1, r.segments.length),
        ]),
      )
    } catch (err) {
      handleError(err)
    } finally {
      setExporting(false)
    }
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
        <span className="run-search">
          <input
            type="search"
            className="name-search"
            placeholder="닉네임/이메일 검색"
            value={searchDraft}
            onChange={(e) => setSearchDraft(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') {
                e.preventDefault()
                setSearch(searchDraft)
                setPage(0)
              }
            }}
          />
          <button
            type="button"
            className="small"
            onClick={() => {
              setSearch(searchDraft)
              setPage(0)
            }}
          >
            검색
          </button>
        </span>
        <button
          type="button"
          className="secondary small"
          onClick={download}
          disabled={exporting || !runs?.length}
        >
          {exporting ? '내려받는 중…' : 'CSV 다운로드'}
        </button>
      </form>
      {draft.from > draft.to && draft.to && (
        <div className="error">시작일이 종료일보다 늦을 수 없어요.</div>
      )}

      <p className="muted run-summary">
        {applied.from === applied.to ? applied.from : `${applied.from} ~ ${applied.to}`} (한국 시간) ·{' '}
        {search.trim() && <>“{search.trim()}” 검색 · </>}
        {runs ? `${total.toLocaleString()}건` : '불러오는 중…'}
      </p>

      {error && <div className="error">{error}</div>}
      {runs && runs.length === 0 && <p className="muted">조건에 맞는 러닝 기록이 없어요.</p>}
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
              <th>완주</th>
              <th>경로 일치</th>
            </tr>
          </thead>
          <tbody>
            {runs.map((r) => (
              <tr key={r.id} onClick={() => setDetail(r)}>
                <td className="nowrap">{formatDateTime(r.started_at)}</td>
                <td>
                  <strong>{r.nickname ?? <span className="muted">(탈퇴/미설정)</span>}</strong>
                  {r.email && <div className="muted">{r.email}</div>}
                </td>
                <td>{r.course_name ?? <span className="muted">코스 없이 달림</span>}</td>
                <td className="nowrap">{r.distance_km.toFixed(2)}km</td>
                <td className="nowrap muted">{formatDuration(r.duration_sec)}</td>
                <td className="nowrap">
                  {r.completion === 'incomplete' && r.app_killed ? (
                    <span className="with-corner-tag">
                      {COMPLETION.incomplete}
                      <span className="corner-tag">앱 종료</span>
                    </span>
                  ) : (
                    COMPLETION[r.completion]
                  )}
                  {r.segments.length > 0 && (
                    <div className="muted">이어달리기 {r.segments.length - 1}회</div>
                  )}
                </td>
                <td className="nowrap">{formatMatch(r.match_rate)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      {detail && <RunDetail run={detail} onClose={() => setDetail(null)} />}

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
