import { useCallback, useEffect, useState, type ReactNode } from 'react'

import {
  ApiError,
  cancelNotificationSend,
  createNotificationSend,
  dispatchNotificationSend,
  getNotificationSend,
  listNotificationDevices,
  listNotificationRecipients,
  listNotificationRecords,
  listNotificationScreens,
  listNotificationSends,
  listNotificationTypes,
  listUsers,
  previewNotificationAudience,
  type NotificationAudience,
  type NotificationDevice,
  type NotificationPermission,
  type NotificationRecord,
  type NotificationScreen,
  type NotificationSend,
  type NotificationType,
  type PushStatus,
  type UserSummary,
} from '../api'
import Modal from '../components/Modal'
import { kstDaysAgo, kstToday } from '../utils/dates'

type Tab = 'compose' | 'sends' | 'records' | 'devices'

const TABS: { key: Tab; label: string }[] = [
  { key: 'compose', label: '발송' },
  { key: 'sends', label: '발송 내역' },
  { key: 'records', label: '알림 기록' },
  { key: 'devices', label: '수신 현황' },
]

const PUSH_LABEL: Record<PushStatus, string> = {
  pending: '대기',
  sending: '발송 중',
  sent: '성공',
  failed: '실패',
  no_permission: '권한 꺼짐',
  no_device: '기기 없음',
  skipped: '건너뜀',
}

const PERMISSION_LABEL: Record<NotificationPermission, string> = {
  authorized: '허용',
  denied: '거부',
  not_determined: '미응답',
  none: '기기 없음',
}

const SEND_STATUS: Record<NotificationSend['status'], { label: string; badge: string }> = {
  scheduled: { label: '예약', badge: 'scheduled' },
  sending: { label: '발송 중', badge: 'popup' },
  done: { label: '완료', badge: 'live' },
  canceled: { label: '취소', badge: 'expired' },
}

const AUDIENCE_LABEL = { all: '전체', authorized: '앱 푸시 허용 회원', users: '직접 선택' }

function formatDateTime(iso: string | null): string {
  if (!iso) return '—'
  return new Date(iso).toLocaleString('ko-KR', {
    timeZone: 'Asia/Seoul',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  })
}

function message(err: unknown, fallback: string): string {
  return err instanceof ApiError ? err.message : fallback
}

function Pager({ page, pageCount, onPage }: { page: number; pageCount: number; onPage: (p: number) => void }) {
  if (pageCount <= 1) return null
  return (
    <div className="pager">
      <button className="secondary small" disabled={page === 0} onClick={() => onPage(page - 1)}>
        이전
      </button>
      <span className="muted">
        {page + 1} / {pageCount}
      </span>
      <button className="secondary small" disabled={page + 1 >= pageCount} onClick={() => onPage(page + 1)}>
        다음
      </button>
    </div>
  )
}

function PushCell({ row }: { row: NotificationRecord }) {
  const label = PUSH_LABEL[row.push_status]
  if (row.push_status === 'sent') return <>{label}</>
  if (row.push_status === 'failed') {
    return (
      <span title={row.push_error ?? undefined} style={{ color: 'var(--danger)' }}>
        {label}
      </span>
    )
  }
  return <span className="muted">{label}</span>
}

function Member({ nickname, email }: { nickname: string | null; email: string | null }) {
  return (
    <>
      <strong>{nickname ?? <span className="muted">(탈퇴/미설정)</span>}</strong>
      {email && <div className="muted">{email}</div>}
    </>
  )
}

/** 남은 대기 건을 묶음 단위로 끝까지 보낸다. 재시도 대기만 남으면(processed 0) 멈춘다. */
async function drain(send: NotificationSend, onProgress: (send: NotificationSend) => void) {
  let current = send
  while (current.status === 'sending' && current.pending_count > 0) {
    const result = await dispatchNotificationSend(current.id)
    current = result.send
    onProgress(current)
    if (result.processed === 0) break
  }
  return current
}

// --- 발송 ---------------------------------------------------------------

const USER_PAGE = 8

function UserPicker({
  selected,
  onChange,
}: {
  selected: Map<string, UserSummary>
  onChange: (next: Map<string, UserSummary>) => void
}) {
  const [draft, setDraft] = useState('')
  const [keyword, setKeyword] = useState('')
  const [page, setPage] = useState(0)
  const [total, setTotal] = useState(0)
  const [users, setUsers] = useState<UserSummary[] | null>(null)

  useEffect(() => {
    let stale = false
    listUsers(keyword, USER_PAGE, page * USER_PAGE).then(
      (result) => {
        if (stale) return
        setUsers(result.items)
        setTotal(result.total)
      },
      () => !stale && setUsers([]),
    )
    return () => {
      stale = true
    }
  }, [keyword, page])

  const toggle = (user: UserSummary) => {
    const next = new Map(selected)
    if (next.has(user.id)) next.delete(user.id)
    else next.set(user.id, user)
    onChange(next)
  }
  const search = () => {
    setKeyword(draft)
    setPage(0)
  }

  return (
    <div className="notif-picker">
      <div className="run-filter">
        <input
          type="search"
          className="name-search"
          placeholder="닉네임/이메일 검색"
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter') {
              e.preventDefault()
              search()
            }
          }}
        />
        <button type="button" className="small" onClick={search}>
          검색
        </button>
        <span className="muted">{selected.size}명 선택</span>
      </div>
      {selected.size > 0 && (
        <div className="notif-chips">
          {[...selected.values()].map((u) => (
            <button type="button" key={u.id} className="secondary small" onClick={() => toggle(u)}>
              {u.nickname ?? u.email ?? u.id.slice(0, 8)} ✕
            </button>
          ))}
        </div>
      )}
      {users && users.length === 0 && <p className="muted">조건에 맞는 회원이 없어요.</p>}
      {users && users.length > 0 && (
        <table className="users-table">
          <tbody>
            {users.map((u) => (
              <tr key={u.id} onClick={() => toggle(u)}>
                <td style={{ width: 28 }}>
                  <input type="checkbox" readOnly checked={selected.has(u.id)} />
                </td>
                <td>
                  <Member nickname={u.nickname} email={u.email} />
                </td>
                <td className="nowrap muted">알림 {PERMISSION_LABEL[u.notification]}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
      <Pager page={page} pageCount={Math.ceil(total / USER_PAGE)} onPage={setPage} />
    </div>
  )
}

function ComposeTab({ onSent }: { onSent: () => void }) {
  const [title, setTitle] = useState('')
  const [body, setBody] = useState('')
  const [screens, setScreens] = useState<NotificationScreen[]>([])
  const [link, setLink] = useState('')
  const [kind, setKind] = useState<NotificationAudience['kind']>('authorized')
  const [selected, setSelected] = useState<Map<string, UserSummary>>(new Map())
  const [when, setWhen] = useState<'now' | 'later'>('now')
  const [scheduledAt, setScheduledAt] = useState('')
  const [count, setCount] = useState<number | null>(null)
  const [busy, setBusy] = useState(false)
  const [progress, setProgress] = useState<NotificationSend | null>(null)
  const [result, setResult] = useState<NotificationSend | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    listNotificationScreens().then((list) => {
      setScreens(list)
      setLink((current) => current || list[0]?.link || '')
    }, () => undefined)
  }, [])

  const audience: NotificationAudience | null =
    kind === 'users' ? (selected.size ? { kind, user_ids: [...selected.keys()] } : null) : { kind }
  const audienceKey = JSON.stringify(audience)

  useEffect(() => {
    if (!audience) {
      setCount(0)
      return
    }
    let stale = false
    setCount(null)
    previewNotificationAudience(audience).then(
      (r) => !stale && setCount(r.count),
      () => !stale && setCount(null),
    )
    return () => {
      stale = true
    }
    // audience는 매 렌더 새 객체라 내용(audienceKey)으로 비교한다.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [audienceKey])

  const ready =
    title.trim() && body.trim() && audience && !!count && (when === 'now' || scheduledAt) && !busy

  const submit = async () => {
    if (!audience || !ready) return
    const target = when === 'now' ? '지금' : `${scheduledAt.replace('T', ' ')}에`
    if (!window.confirm(`${AUDIENCE_LABEL[kind]} ${count}명에게 ${target} 보낼까요?`)) return
    setBusy(true)
    setError(null)
    setResult(null)
    try {
      const created = await createNotificationSend({
        title,
        body,
        link_url: link || null,
        audience,
        scheduled_at: when === 'later' ? new Date(scheduledAt).toISOString() : null,
      })
      setProgress(created)
      setResult(await drain(created, setProgress))
      setTitle('')
      setBody('')
      setLink(screens[0]?.link ?? '')
      setSelected(new Map())
      onSent()
    } catch (err) {
      setError(message(err, '발송하지 못했어요.'))
    } finally {
      setBusy(false)
      setProgress(null)
    }
  }

  return (
    <div className="card notif-form">
      <div className="field">
        <label>
          제목<span className="hint">{title.length}/100</span>
        </label>
        <input value={title} maxLength={100} onChange={(e) => setTitle(e.target.value)} />
      </div>
      <div className="field">
        <label>
          내용<span className="hint">{body.length}/1000 · 알림 배너에는 앞부분만 보여요</span>
        </label>
        <textarea rows={4} value={body} maxLength={1000} onChange={(e) => setBody(e.target.value)} />
      </div>
      <div className="field">
        <label>
          눌렀을 때 열 화면<span className="hint">알림을 누르면 앱의 이 화면이 열려요</span>
        </label>
        <select value={link} onChange={(e) => setLink(e.target.value)}>
          {screens.map((screen) => (
            <option key={screen.link} value={screen.link}>
              {screen.label}
            </option>
          ))}
        </select>
      </div>

      <div className="field">
        <label>받는 사람</label>
        <div className="notif-radios">
          {(['all', 'authorized', 'users'] as const).map((k) => (
            <label key={k}>
              <input type="radio" checked={kind === k} onChange={() => setKind(k)} />
              {AUDIENCE_LABEL[k]}
            </label>
          ))}
        </div>
        {kind === 'all' && (
          <p className="muted section-desc">
            기기가 없거나 알림을 꺼 둔 회원은 푸시는 못 받고 앱 알림함에만 남아요.
          </p>
        )}
        {kind === 'users' && <UserPicker selected={selected} onChange={setSelected} />}
      </div>

      <div className="field">
        <label>발송 시각</label>
        <div className="notif-radios">
          <label>
            <input type="radio" checked={when === 'now'} onChange={() => setWhen('now')} />
            지금
          </label>
          <label>
            <input type="radio" checked={when === 'later'} onChange={() => setWhen('later')} />
            예약
          </label>
          {when === 'later' && (
            <input
              type="datetime-local"
              step={1800}
              style={{ width: 'auto' }}
              value={scheduledAt}
              onChange={(e) => setScheduledAt(e.target.value)}
            />
          )}
        </div>
      </div>

      {error && <div className="error">{error}</div>}
      {result && (
        <div className="notice">
          {result.status === 'scheduled'
            ? `${formatDateTime(result.scheduled_at)} 발송으로 예약했어요.`
            : `${result.target_count}명 중 성공 ${result.sent_count} · 실패 ${result.failed_count} · 권한 꺼짐 ${result.no_permission_count} · 기기 없음 ${result.no_device_count}` +
              (result.pending_count ? ` · 재시도 대기 ${result.pending_count}` : '')}
        </div>
      )}
      <div className="page-head-actions">
        <button onClick={submit} disabled={!ready}>
          {busy ? '보내는 중…' : when === 'now' ? '발송' : '예약'}
        </button>
        <span className="muted">
          {progress && progress.status === 'sending'
            ? `${progress.target_count - progress.pending_count} / ${progress.target_count}`
            : count == null
              ? '대상 확인 중…'
              : `대상 ${count.toLocaleString()}명`}
        </span>
      </div>
    </div>
  )
}

// --- 발송 내역 -----------------------------------------------------------

const SEND_PAGE = 20
const RECIPIENT_PAGE = 50

function SendDetail({ id, onClose, onChanged }: { id: string; onClose: () => void; onChanged: () => void }) {
  const [send, setSend] = useState<NotificationSend | null>(null)
  const [rows, setRows] = useState<NotificationRecord[] | null>(null)
  const [total, setTotal] = useState(0)
  const [status, setStatus] = useState<PushStatus | ''>('')
  const [page, setPage] = useState(0)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [tick, setTick] = useState(0)
  const [screens, setScreens] = useState<NotificationScreen[]>([])
  const screenLabel = (link: string) => screens.find((x) => x.link === link)?.label ?? link

  useEffect(() => {
    listNotificationScreens().then(setScreens, () => undefined)
  }, [])

  useEffect(() => {
    getNotificationSend(id).then(setSend, (err) => setError(message(err, '불러오지 못했어요.')))
  }, [id, tick])

  useEffect(() => {
    let stale = false
    listNotificationRecipients(id, status, RECIPIENT_PAGE, page * RECIPIENT_PAGE).then(
      (r) => {
        if (stale) return
        setRows(r.items)
        setTotal(r.total)
      },
      (err) => !stale && setError(message(err, '명단을 불러오지 못했어요.')),
    )
    return () => {
      stale = true
    }
  }, [id, status, page, tick])

  const run = async (work: () => Promise<unknown>, fallback: string) => {
    setBusy(true)
    setError(null)
    try {
      await work()
      setTick((t) => t + 1)
      onChanged()
    } catch (err) {
      setError(message(err, fallback))
    } finally {
      setBusy(false)
    }
  }

  return (
    <Modal title={send?.title ?? '발송 건'} onClose={onClose} closable={!busy}>
      {error && <div className="error">{error}</div>}
      {send && (
        <>
          <p style={{ whiteSpace: 'pre-wrap' }}>{send.body}</p>
          <p className="muted">
            {AUDIENCE_LABEL[send.audience.kind]} · {send.admin_username ?? '—'} ·{' '}
            {send.status === 'scheduled' || send.status === 'canceled'
              ? `예약 ${formatDateTime(send.scheduled_at)}`
              : `발송 ${formatDateTime(send.scheduled_at ?? send.created_at)}`}
            {send.link_url && <> · 누르면 {screenLabel(send.link_url)}</>}
          </p>
          {send.status !== 'scheduled' && send.status !== 'canceled' && (
            <div className="kpi-grid in-card" style={{ gridTemplateColumns: 'repeat(6, 1fr)' }}>
              {(
                [
                  ['대상', send.target_count],
                  ['성공', send.sent_count],
                  ['실패', send.failed_count],
                  ['권한 꺼짐', send.no_permission_count],
                  ['기기 없음', send.no_device_count],
                  ['읽음', send.read_count ?? 0],
                ] as const
              ).map(([label, value]) => (
                <div className="kpi" key={label}>
                  <div className="kpi-label">{label}</div>
                  <div className="kpi-value">{value.toLocaleString()}</div>
                </div>
              ))}
            </div>
          )}
          <div className="page-head-actions" style={{ margin: '12px 0' }}>
            {send.status === 'scheduled' && (
              <button
                className="secondary small"
                disabled={busy}
                onClick={() =>
                  window.confirm('이 예약을 취소할까요?') &&
                  run(() => cancelNotificationSend(id), '취소하지 못했어요.')
                }
              >
                예약 취소
              </button>
            )}
            {send.status === 'sending' && send.pending_count > 0 && (
              <>
                <button
                  className="small"
                  disabled={busy}
                  onClick={() => run(() => drain(send, setSend), '발송하지 못했어요.')}
                >
                  {busy ? '보내는 중…' : '이어서 발송'}
                </button>
                <span className="muted">
                  남은 {send.pending_count.toLocaleString()}건 · 일시 오류는 다음 차례(30분 간격)에 자동으로 다시
                  보내요
                </span>
              </>
            )}
          </div>
        </>
      )}

      {send && send.status !== 'scheduled' && send.status !== 'canceled' && (
        <>
          <div className="run-filter">
            <label htmlFor="recipient-status">푸시 결과</label>
            <select
              id="recipient-status"
              style={{ width: 'auto' }}
              value={status}
              onChange={(e) => {
                setStatus(e.target.value as PushStatus | '')
                setPage(0)
              }}
            >
              <option value="">전체</option>
              {(['sent', 'failed', 'no_permission', 'no_device', 'pending'] as const).map((s) => (
                <option key={s} value={s}>
                  {PUSH_LABEL[s]}
                </option>
              ))}
            </select>
            <span className="muted">{total.toLocaleString()}명</span>
          </div>
          {rows && rows.length > 0 && (
            <table className="users-table">
              <thead>
                <tr>
                  <th>회원</th>
                  <th>푸시</th>
                  <th>보낸 시각</th>
                  <th>읽음</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r) => (
                  <tr key={r.id}>
                    <td>
                      <Member nickname={r.nickname} email={r.email} />
                    </td>
                    <td className="nowrap">
                      <PushCell row={r} />
                      {r.push_error && <div className="muted">{r.push_error}</div>}
                    </td>
                    <td className="nowrap muted">{formatDateTime(r.pushed_at)}</td>
                    <td className="nowrap muted">{formatDateTime(r.read_at)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
          {rows && rows.length === 0 && <p className="muted">해당하는 회원이 없어요.</p>}
          <Pager page={page} pageCount={Math.ceil(total / RECIPIENT_PAGE)} onPage={setPage} />
        </>
      )}
    </Modal>
  )
}

function SendsTab() {
  const [sends, setSends] = useState<NotificationSend[] | null>(null)
  const [total, setTotal] = useState(0)
  const [page, setPage] = useState(0)
  const [detail, setDetail] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [tick, setTick] = useState(0)

  useEffect(() => {
    let stale = false
    listNotificationSends(SEND_PAGE, page * SEND_PAGE).then(
      (r) => {
        if (stale) return
        setSends(r.items)
        setTotal(r.total)
        setError(null)
      },
      (err) => !stale && setError(message(err, '발송 내역을 불러오지 못했어요.')),
    )
    return () => {
      stale = true
    }
  }, [page, tick])

  const refresh = useCallback(() => setTick((t) => t + 1), [])

  return (
    <>
      <p className="muted page-desc">운영자가 보낸 발송 건이에요. 행을 누르면 받은 사람별 결과가 보여요.</p>
      {error && <div className="error">{error}</div>}
      {sends == null && !error && <p className="muted">불러오는 중…</p>}
      {sends && sends.length === 0 && <p className="muted">아직 보낸 알림이 없어요.</p>}
      {sends && sends.length > 0 && (
        <table className="users-table">
          <thead>
            <tr>
              <th>시각</th>
              <th>제목</th>
              <th>받는 사람</th>
              <th>상태</th>
              <th>대상</th>
              <th>성공</th>
              <th>실패</th>
              <th>권한 꺼짐</th>
              <th>기기 없음</th>
              <th>보낸 사람</th>
            </tr>
          </thead>
          <tbody>
            {sends.map((s) => {
              const waiting = s.status === 'scheduled' || s.status === 'canceled'
              const cell = (value: number): ReactNode => (waiting ? <span className="muted">—</span> : value.toLocaleString())
              return (
                <tr key={s.id} onClick={() => setDetail(s.id)}>
                  <td className="nowrap">{formatDateTime(s.scheduled_at ?? s.created_at)}</td>
                  <td>
                    <strong>{s.title}</strong>
                    <div className="muted notif-clip">{s.body}</div>
                  </td>
                  <td className="nowrap">{AUDIENCE_LABEL[s.audience.kind]}</td>
                  <td className="nowrap">
                    <span className={`badge ${SEND_STATUS[s.status].badge}`}>{SEND_STATUS[s.status].label}</span>
                    {s.status === 'sending' && s.pending_count > 0 && (
                      <div className="muted">남은 {s.pending_count.toLocaleString()}</div>
                    )}
                  </td>
                  <td>{cell(s.target_count)}</td>
                  <td>{cell(s.sent_count)}</td>
                  <td>{cell(s.failed_count)}</td>
                  <td>{cell(s.no_permission_count)}</td>
                  <td>{cell(s.no_device_count)}</td>
                  <td className="nowrap muted">{s.admin_username ?? '—'}</td>
                </tr>
              )
            })}
          </tbody>
        </table>
      )}
      <Pager page={page} pageCount={Math.ceil(total / SEND_PAGE)} onPage={setPage} />
      {detail && <SendDetail id={detail} onClose={() => setDetail(null)} onChanged={refresh} />}
    </>
  )
}

// --- 알림 기록 -----------------------------------------------------------

const RECORD_PAGE = 50

function RecordsTab() {
  const [types, setTypes] = useState<NotificationType[]>([])
  const [draft, setDraft] = useState({ from: kstDaysAgo(7), to: kstToday() })
  const [applied, setApplied] = useState(draft)
  const [type, setType] = useState('')
  const [searchDraft, setSearchDraft] = useState('')
  const [search, setSearch] = useState('')
  const [page, setPage] = useState(0)
  const [total, setTotal] = useState(0)
  const [rows, setRows] = useState<NotificationRecord[] | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    listNotificationTypes().then(setTypes, () => undefined)
  }, [])

  useEffect(() => {
    let stale = false
    setRows(null)
    listNotificationRecords(applied.from, applied.to, type, search, RECORD_PAGE, page * RECORD_PAGE).then(
      (r) => {
        if (stale) return
        setRows(r.items)
        setTotal(r.total)
        setError(null)
      },
      (err) => !stale && setError(message(err, '알림 기록을 불러오지 못했어요.')),
    )
    return () => {
      stale = true
    }
  }, [applied, type, search, page])

  const typeLabel = (key: string) => types.find((t) => t.key === key)?.label ?? key
  const invalid = !draft.from || !draft.to || draft.from > draft.to
  const applySearch = () => {
    setSearch(searchDraft)
    setPage(0)
  }

  return (
    <>
      <p className="muted page-desc">
        회원 한 명이 받은 알림 한 건이 한 행이에요. 운영자 발송과 자동 발송이 함께 보여요.
      </p>
      <form
        className="run-filter"
        onSubmit={(e) => {
          e.preventDefault()
          if (invalid) return
          setApplied(draft)
          setPage(0)
        }}
      >
        <label htmlFor="record-from">기간</label>
        <input
          id="record-from"
          type="date"
          value={draft.from}
          max={draft.to || undefined}
          onChange={(e) => setDraft({ ...draft, from: e.target.value })}
        />
        <span className="muted">~</span>
        <input
          type="date"
          value={draft.to}
          min={draft.from || undefined}
          onChange={(e) => setDraft({ ...draft, to: e.target.value })}
        />
        <button type="submit" className="small" disabled={invalid}>
          조회
        </button>
        <select
          style={{ width: 'auto' }}
          value={type}
          onChange={(e) => {
            setType(e.target.value)
            setPage(0)
          }}
        >
          <option value="">모든 종류</option>
          {types.map((t) => (
            <option key={t.key} value={t.key}>
              {t.label}
              {t.automatic ? ' (자동)' : ''} · {t.count.toLocaleString()}
            </option>
          ))}
        </select>
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
                applySearch()
              }
            }}
          />
          <button type="button" className="small" onClick={applySearch}>
            검색
          </button>
        </span>
      </form>
      <p className="muted run-summary">
        {applied.from} ~ {applied.to} (한국 시간) · {rows ? `${total.toLocaleString()}건` : '불러오는 중…'}
      </p>
      {error && <div className="error">{error}</div>}
      {rows && rows.length === 0 && <p className="muted">조건에 맞는 알림이 없어요.</p>}
      {rows && rows.length > 0 && (
        <table className="users-table">
          <thead>
            <tr>
              <th>시각</th>
              <th>회원</th>
              <th>종류</th>
              <th>내용</th>
              <th>푸시</th>
              <th>읽음</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.id}>
                <td className="nowrap">{formatDateTime(r.created_at)}</td>
                <td>
                  <Member nickname={r.nickname} email={r.email} />
                </td>
                <td className="nowrap">{typeLabel(r.type)}</td>
                <td>
                  <strong>{r.title}</strong>
                  <div className="muted notif-clip">{r.body}</div>
                </td>
                <td className="nowrap">
                  <PushCell row={r} />
                </td>
                <td className="nowrap muted">{formatDateTime(r.read_at)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
      <Pager page={page} pageCount={Math.ceil(total / RECORD_PAGE)} onPage={setPage} />
    </>
  )
}

// --- 수신 현황 -----------------------------------------------------------

const DEVICE_PAGE = 50
const PLATFORM_LABEL: Record<string, string> = { ios: 'iOS', android: 'Android' }

function DevicesTab() {
  const [permission, setPermission] = useState<NotificationPermission | ''>('')
  const [searchDraft, setSearchDraft] = useState('')
  const [search, setSearch] = useState('')
  const [page, setPage] = useState(0)
  const [total, setTotal] = useState(0)
  const [summary, setSummary] = useState<Record<NotificationPermission, number> | null>(null)
  const [rows, setRows] = useState<NotificationDevice[] | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let stale = false
    listNotificationDevices(permission, search, DEVICE_PAGE, page * DEVICE_PAGE).then(
      (r) => {
        if (stale) return
        setRows(r.items)
        setTotal(r.total)
        setSummary(r.summary)
        setError(null)
      },
      (err) => !stale && setError(message(err, '수신 현황을 불러오지 못했어요.')),
    )
    return () => {
      stale = true
    }
  }, [permission, search, page])

  const all = summary ? Object.values(summary).reduce((a, b) => a + b, 0) : 0
  const pick = (next: NotificationPermission | '') => {
    setPermission(next)
    setPage(0)
  }
  const applySearch = () => {
    setSearch(searchDraft)
    setPage(0)
  }

  return (
    <>
      <p className="muted page-desc">
        회원별 알림 권한이에요. 기기가 여러 대면 한 대라도 허용했으면 허용이에요. 기기 없음은 알림을 지원하는
        버전의 앱으로 아직 로그인하지 않은 회원이에요.
      </p>
      {summary && (
        <div className="kpi-grid">
          {(['authorized', 'denied', 'not_determined', 'none'] as const).map((key) => (
            <button
              type="button"
              key={key}
              className={`kpi notif-kpi${permission === key ? ' active' : ''}`}
              onClick={() => pick(permission === key ? '' : key)}
            >
              <div className="kpi-label">{PERMISSION_LABEL[key]}</div>
              <div className="kpi-value">{summary[key].toLocaleString()}</div>
              <div className="kpi-hint">{all ? `${((summary[key] / all) * 100).toFixed(1)}%` : '—'}</div>
            </button>
          ))}
        </div>
      )}
      <div className="run-filter" style={{ marginTop: 16 }}>
        <span className="muted">
          {permission ? `${PERMISSION_LABEL[permission]} ` : '전체 '}
          {total.toLocaleString()}명
        </span>
        <span className="run-search">
          <input
            type="search"
            className="name-search"
            placeholder="닉네임/이메일 검색"
            value={searchDraft}
            onChange={(e) => setSearchDraft(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && applySearch()}
          />
          <button type="button" className="small" onClick={applySearch}>
            검색
          </button>
        </span>
      </div>
      {error && <div className="error">{error}</div>}
      {rows == null && !error && <p className="muted">불러오는 중…</p>}
      {rows && rows.length === 0 && <p className="muted">조건에 맞는 회원이 없어요.</p>}
      {rows && rows.length > 0 && (
        <table className="users-table">
          <thead>
            <tr>
              <th>회원</th>
              <th>알림 권한</th>
              <th>허용한 시각</th>
              <th>기기</th>
              <th>앱 버전</th>
              <th>마지막 확인</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.user_id}>
                <td>
                  <Member nickname={r.nickname} email={r.email} />
                </td>
                <td className="nowrap">
                  {r.permission === 'authorized' ? (
                    PERMISSION_LABEL.authorized
                  ) : (
                    <span className="muted">{PERMISSION_LABEL[r.permission]}</span>
                  )}
                </td>
                <td className="nowrap muted">{formatDateTime(r.authorized_at)}</td>
                <td className="nowrap">
                  {r.platforms.map((p) => PLATFORM_LABEL[p] ?? p).join(', ') || <span className="muted">—</span>}
                  {r.device_count > 1 && <span className="muted"> · {r.device_count}대</span>}
                </td>
                <td className="nowrap muted">{r.app_version ?? '—'}</td>
                <td className="nowrap muted">{formatDateTime(r.updated_at)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
      <Pager page={page} pageCount={Math.ceil(total / DEVICE_PAGE)} onPage={setPage} />
    </>
  )
}

interface Props {
  onUnauthorized: () => void
}

/** 알림: 수동 발송, 발송 내역·명단, 회원별 알림 기록, 알림 권한 현황. 401은 api가 한곳에서 처리한다. */
export default function NotificationsPage(_: Props) {
  const [tab, setTab] = useState<Tab>('compose')

  return (
    <>
      <div className="page-head">
        <h2>알림</h2>
      </div>
      <div className="tabs" style={{ marginTop: 0, marginBottom: 16 }}>
        {TABS.map((t) => (
          <button key={t.key} className={tab === t.key ? 'active' : undefined} onClick={() => setTab(t.key)}>
            {t.label}
          </button>
        ))}
      </div>
      {tab === 'compose' && <ComposeTab onSent={() => undefined} />}
      {tab === 'sends' && <SendsTab />}
      {tab === 'records' && <RecordsTab />}
      {tab === 'devices' && <DevicesTab />}
    </>
  )
}
