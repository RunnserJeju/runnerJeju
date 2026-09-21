import { useCallback, useEffect, useState } from 'react'

import {
  ApiError,
  listLogNames,
  listUserLogs,
  type LogNameInfo,
  type UserLogFilter,
  type UserLogRow,
} from '../api'
import Modal from '../components/Modal'

interface Props {
  onUnauthorized: () => void
}

const EMPTY_FILTER: UserLogFilter = {}

/** 원본 행동 로그 열람. 필터를 바꾸면 첫 페이지부터, '더 보기'로 이어서 받는다. */
export default function LogsPage({ onUnauthorized }: Props) {
  /** 입력 중인 값. '조회'를 눌러야 applied로 넘어간다. */
  const [draft, setDraft] = useState<UserLogFilter>(EMPTY_FILTER)
  const [applied, setApplied] = useState<UserLogFilter>(EMPTY_FILTER)
  const [rows, setRows] = useState<UserLogRow[] | null>(null)
  const [logNames, setLogNames] = useState<LogNameInfo[]>([])
  /** detail 팝업에 띄울 행. */
  const [detailRow, setDetailRow] = useState<UserLogRow | null>(null)
  const [cursor, setCursor] = useState<string | null>(null)
  const [loadingMore, setLoadingMore] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const handleError = useCallback(
    (err: unknown) => {
      if (err instanceof ApiError && err.status === 401) {
        onUnauthorized()
        return
      }
      setError(err instanceof ApiError ? err.message : '로그를 불러오지 못했어요.')
    },
    [onUnauthorized],
  )

  useEffect(() => {
    listLogNames().then(setLogNames).catch(handleError)
  }, [handleError])

  useEffect(() => {
    setRows(null)
    setCursor(null)
    listUserLogs(applied)
      .then((page) => {
        setRows(page.items)
        setCursor(page.next_cursor)
        setError(null)
      })
      .catch(handleError)
  }, [applied, handleError])

  const loadMore = () => {
    if (!cursor || loadingMore) return
    setLoadingMore(true)
    listUserLogs(applied, cursor)
      .then((page) => {
        setRows((prev) => [...(prev ?? []), ...page.items])
        setCursor(page.next_cursor)
      })
      .catch(handleError)
      .finally(() => setLoadingMore(false))
  }

  const set = (key: keyof UserLogFilter, value: string) =>
    setDraft((d) => ({ ...d, [key]: value || undefined }))

  /** 표의 회원/세션을 누르면 그 값으로 바로 거른다. */
  const filterBy = (key: 'user_id' | 'session_id', value: string) => {
    const next = { ...applied, [key]: value }
    setDraft(next)
    setApplied(next)
  }

  const logGroups = [...new Set(logNames.map((n) => n.group))]
  const labelOf = (name: string) => logNames.find((n) => n.name === name)?.label

  return (
    <>
      <div className="page-head">
        <h2>로그</h2>
      </div>

      <form
        className="card filter-bar"
        onSubmit={(event) => {
          event.preventDefault()
          setApplied(draft)
        }}
      >
        <div className="row">
          <div className="field">
            <label htmlFor="log-name">로그 이름</label>
            <select
              id="log-name"
              value={draft.log_name ?? ''}
              onChange={(e) => set('log_name', e.target.value)}
            >
              <option value="">전체</option>
              {logGroups.map((group) => (
                <optgroup key={group} label={group}>
                  {logNames
                    .filter((n) => n.group === group)
                    .map((n) => (
                      <option key={n.name} value={n.name}>
                        {n.label} ({n.name})
                      </option>
                    ))}
                </optgroup>
              ))}
            </select>
          </div>
          <div className="field">
            <label htmlFor="log-user">회원 id</label>
            <input
              id="log-user"
              value={draft.user_id ?? ''}
              onChange={(e) => set('user_id', e.target.value)}
            />
          </div>
          <div className="field">
            <label htmlFor="log-session">세션 id</label>
            <input
              id="log-session"
              value={draft.session_id ?? ''}
              onChange={(e) => set('session_id', e.target.value)}
            />
          </div>
        </div>
        <div className="row">
          <div className="field">
            <label htmlFor="log-from">시작일</label>
            <input
              id="log-from"
              type="date"
              value={draft.from ?? ''}
              onChange={(e) => set('from', e.target.value)}
            />
          </div>
          <div className="field">
            <label htmlFor="log-to">종료일</label>
            <input
              id="log-to"
              type="date"
              value={draft.to ?? ''}
              onChange={(e) => set('to', e.target.value)}
            />
          </div>
          <div className="field filter-actions">
            <button type="submit">조회</button>
            <button
              type="button"
              className="secondary"
              onClick={() => {
                setDraft(EMPTY_FILTER)
                setApplied(EMPTY_FILTER)
              }}
            >
              초기화
            </button>
          </div>
        </div>
      </form>

      {error && <div className="error">{error}</div>}
      {rows == null && !error && <p className="muted">불러오는 중…</p>}
      {rows && rows.length === 0 && <p className="muted">조건에 맞는 로그가 없어요.</p>}
      {rows && rows.length > 0 && (
        <table className="logs-table">
          <thead>
            <tr>
              <th>시각</th>
              <th>로그</th>
              <th>회원</th>
              <th>세션</th>
              <th>기기</th>
              <th>detail</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((row) => (
              <tr key={row.id}>
                <td className="nowrap">{formatTime(row.created_at)}</td>
                <td>
                  <code title={labelOf(row.log_name)}>{row.log_name}</code>
                </td>
                <td>
                  {row.user_id ? (
                    <button
                      type="button"
                      className="link"
                      title={row.user_id}
                      onClick={() => filterBy('user_id', row.user_id!)}
                    >
                      {row.nickname ?? row.user_id.slice(0, 8)}
                    </button>
                  ) : (
                    <span className="muted">익명</span>
                  )}
                </td>
                <td>
                  {row.session_id ? (
                    <button
                      type="button"
                      className="link"
                      title={row.session_id}
                      onClick={() => filterBy('session_id', row.session_id!)}
                    >
                      {row.session_id.slice(0, 8)}
                    </button>
                  ) : (
                    <span className="muted">—</span>
                  )}
                </td>
                <td className="muted nowrap">
                  {[row.platform, row.app_version].filter(Boolean).join(' ') || '—'}
                </td>
                <td>
                  {Object.keys(row.detail).length === 0 ? (
                    <span className="muted">—</span>
                  ) : (
                    <button
                      type="button"
                      className="detail-preview"
                      title="자세히 보기"
                      onClick={() => setDetailRow(row)}
                    >
                      {JSON.stringify(row.detail)}
                    </button>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
      {detailRow && (
        <Modal
          title={`${labelOf(detailRow.log_name) ?? detailRow.log_name} · ${formatTime(detailRow.created_at)}`}
          onClose={() => setDetailRow(null)}
        >
          <table className="kv-table">
            <tbody>
              {Object.entries(detailRow.detail).map(([key, value]) => (
                <tr key={key}>
                  <th>{key}</th>
                  <td>{typeof value === 'object' ? JSON.stringify(value, null, 2) : String(value)}</td>
                </tr>
              ))}
            </tbody>
          </table>
          <h3>기록 정보</h3>
          <table className="kv-table">
            <tbody>
              <tr>
                <th>회원</th>
                <td>{detailRow.nickname ?? '익명'}{detailRow.user_id && <span className="muted"> · {detailRow.user_id}</span>}</td>
              </tr>
              <tr>
                <th>세션</th>
                <td>{detailRow.session_id ?? '—'}</td>
              </tr>
              <tr>
                <th>기기</th>
                <td>{[detailRow.platform, detailRow.app_version].filter(Boolean).join(' ') || '—'}</td>
              </tr>
              <tr>
                <th>로그 id</th>
                <td>{detailRow.id}</td>
              </tr>
            </tbody>
          </table>
        </Modal>
      )}

      {cursor && (
        <div className="submit-row">
          <button className="secondary" onClick={loadMore} disabled={loadingMore}>
            {loadingMore ? '불러오는 중…' : '더 보기'}
          </button>
        </div>
      )}
    </>
  )
}

function formatTime(iso: string): string {
  return new Date(iso).toLocaleString('ko-KR', {
    timeZone: 'Asia/Seoul',
    month: 'numeric',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false,
  })
}
