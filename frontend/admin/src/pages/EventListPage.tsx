import { useCallback, useEffect, useState } from 'react'

import {
  ApiError,
  createEvent,
  deleteEvent,
  deleteEventImage,
  listEvents,
  setEventImage,
  updateEvent,
  type CommunityEvent,
  type CommunityEventPayload,
} from '../api'
import Modal from '../components/Modal'

interface Props {
  /** 목록 로딩이 401이면(세션 만료 등) 인증 화면으로 되돌린다. */
  onUnauthorized: () => void
}

type Visibility = 'hidden' | 'scheduled' | 'live' | 'expired'

/** 서버 routers/events.is_visible과 같은 규칙. */
function visibilityOf(event: CommunityEvent, now: Date): Visibility {
  if (!event.is_active) return 'hidden'
  if (event.starts_at && new Date(event.starts_at) > now) return 'scheduled'
  if (event.ends_at && new Date(event.ends_at) < now) return 'expired'
  return 'live'
}

const VISIBILITY_LABEL: Record<Visibility, string> = {
  hidden: '숨김',
  scheduled: '예약',
  live: '노출 중',
  expired: '만료',
}

function formatDateTime(iso: string | null): string {
  if (!iso) return '—'
  const d = new Date(iso)
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}.${pad(d.getMonth() + 1)}.${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`
}

/** ISO(UTC) → datetime-local 입력값(로컬 시각). */
function toLocalInput(iso: string | null): string {
  if (!iso) return ''
  const d = new Date(iso)
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`
}

/** 커뮤니티 이벤트 관리(#70). 그림 한 장(선택)과 게시글. */
export default function EventListPage({ onUnauthorized }: Props) {
  const [events, setEvents] = useState<CommunityEvent[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  /** 열린 모달. 'new'면 등록, 아니면 그 이벤트 수정. */
  const [editing, setEditing] = useState<'new' | CommunityEvent | null>(null)

  const reload = useCallback(() => {
    listEvents()
      .then((loaded) => {
        setEvents(loaded)
        setError(null)
      })
      .catch((err: unknown) => {
        if (err instanceof ApiError && err.status === 401) {
          onUnauthorized()
          return
        }
        setError(err instanceof ApiError ? err.message : '이벤트 목록을 불러오지 못했어요.')
      })
  }, [onUnauthorized])

  useEffect(() => {
    reload()
  }, [reload])

  const now = new Date()

  return (
    <>
      <div className="page-head">
        <h2>이벤트</h2>
        <button onClick={() => setEditing('new')}>+ 이벤트 추가</button>
      </div>
      <p className="muted page-desc">
        앱 커뮤니티 탭의 이벤트 목록에 보여요. 본문에 붙여 넣은 링크는 앱에서 눌러 열 수 있어요.
      </p>
      {error && <div className="error">{error}</div>}
      {events == null && !error && <p className="muted">불러오는 중…</p>}
      {events && events.length === 0 && <p className="muted">등록된 이벤트가 없어요.</p>}
      {events && events.length > 0 && (
        <table>
          <thead>
            <tr>
              <th></th>
              <th>제목</th>
              <th>상태</th>
              <th>노출 기간</th>
              <th>정렬</th>
              <th>등록일</th>
            </tr>
          </thead>
          <tbody>
            {events.map((event) => {
              const visibility = visibilityOf(event, now)
              return (
                <tr key={event.id} onClick={() => setEditing(event)}>
                  <td style={{ width: 104 }}>
                    {event.image_url ? (
                      <img className="thumb wide" src={event.image_url} alt="" />
                    ) : (
                      <div className="thumb wide placeholder">이미지 없음</div>
                    )}
                  </td>
                  <td>
                    <strong>{event.title}</strong>
                    <div className="muted clamp">{event.body}</div>
                  </td>
                  <td>
                    <span className={`badge ${visibility === 'hidden' ? 'expired' : visibility}`}>
                      {VISIBILITY_LABEL[visibility]}
                    </span>
                  </td>
                  <td className="muted">
                    {event.starts_at || event.ends_at
                      ? `${formatDateTime(event.starts_at)} ~ ${formatDateTime(event.ends_at)}`
                      : '상시'}
                  </td>
                  <td className="muted">{event.sort_order}</td>
                  <td className="muted">{formatDateTime(event.created_at)}</td>
                </tr>
              )
            })}
          </tbody>
        </table>
      )}

      {editing && (
        <EventModal
          event={editing === 'new' ? null : editing}
          onClose={() => setEditing(null)}
          onSaved={(saved) => {
            setEditing(saved)
            reload()
          }}
          onDeleted={() => {
            setEditing(null)
            reload()
          }}
        />
      )}
    </>
  )
}

function EventModal({
  event,
  onClose,
  onSaved,
  onDeleted,
}: {
  /** null이면 새로 등록. */
  event: CommunityEvent | null
  onClose: () => void
  onSaved: (event: CommunityEvent) => void
  onDeleted: () => void
}) {
  const [message, setMessage] = useState<string | null>(null)
  const saved = (next: CommunityEvent, text: string) => {
    setMessage(text)
    onSaved(next)
  }

  return (
    <Modal title={event ? `이벤트 수정 — ${event.title}` : '새 이벤트'} onClose={onClose}>
      {message && <div className="notice" style={{ marginTop: 0 }}>{message}</div>}
      <ContentSection event={event} onSaved={saved} />
      {event && <ImageSection event={event} onSaved={saved} />}
      {event && <DeleteSection event={event} onDeleted={onDeleted} />}
    </Modal>
  )
}

function ContentSection({
  event,
  onSaved,
}: {
  event: CommunityEvent | null
  onSaved: (event: CommunityEvent, message: string) => void
}) {
  const [title, setTitle] = useState(event?.title ?? '')
  const [body, setBody] = useState(event?.body ?? '')
  const [startsAt, setStartsAt] = useState(toLocalInput(event?.starts_at ?? null))
  const [endsAt, setEndsAt] = useState(toLocalInput(event?.ends_at ?? null))
  const [isActive, setIsActive] = useState(event?.is_active ?? true)
  const [sortOrder, setSortOrder] = useState(event?.sort_order ?? 0)
  const [error, setError] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)

  const save = async () => {
    setError(null)
    if (!title.trim()) {
      setError('제목을 입력해 주세요.')
      return
    }
    if (!body.trim()) {
      setError('내용을 입력해 주세요.')
      return
    }
    const start = startsAt ? new Date(startsAt) : null
    const end = endsAt ? new Date(endsAt) : null
    if (start && end && end < start) {
      setError('노출 종료가 시작보다 빠를 수 없어요.')
      return
    }
    const payload: CommunityEventPayload = {
      title: title.trim(),
      body: body.trim(),
      starts_at: start ? start.toISOString() : null,
      ends_at: end ? end.toISOString() : null,
      is_active: isActive,
      sort_order: sortOrder,
    }
    setSaving(true)
    try {
      const next = event ? await updateEvent(event.id, payload) : await createEvent(payload)
      onSaved(next, event ? '저장했어요.' : '등록했어요. 이어서 이미지를 올릴 수 있어요.')
    } catch (err) {
      setError(err instanceof ApiError ? err.message : '저장에 실패했어요.')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="card">
      <h3 style={{ marginTop: 0 }}>내용</h3>
      <div className="field">
        <label htmlFor="event-title">제목</label>
        <input id="event-title" maxLength={200} value={title} onChange={(e) => setTitle(e.target.value)} />
      </div>
      <div className="field">
        <label htmlFor="event-body">
          내용{' '}
          <span className="hint">
            링크는 주소를 그대로 붙여 넣으면 돼요(https://…). 글자에 링크를 걸려면
            [신청하기](https://…)
          </span>
        </label>
        <textarea
          id="event-body"
          rows={10}
          value={body}
          onChange={(e) => setBody(e.target.value)}
        />
      </div>
      <div className="row">
        <div className="field">
          <label htmlFor="event-starts">
            노출 시작 <span className="hint">비우면 즉시</span>
          </label>
          <input
            id="event-starts"
            type="datetime-local"
            value={startsAt}
            onChange={(e) => setStartsAt(e.target.value)}
          />
        </div>
        <div className="field">
          <label htmlFor="event-ends">
            노출 종료 <span className="hint">비우면 무기한</span>
          </label>
          <input
            id="event-ends"
            type="datetime-local"
            value={endsAt}
            onChange={(e) => setEndsAt(e.target.value)}
          />
        </div>
      </div>
      <div className="row">
        <div className="field">
          <label htmlFor="event-order">
            정렬 <span className="hint">작을수록 위, 같으면 최신순</span>
          </label>
          <input
            id="event-order"
            type="number"
            value={sortOrder}
            onChange={(e) => setSortOrder(Number(e.target.value) || 0)}
          />
        </div>
        <div className="field">
          <label>
            <input
              type="checkbox"
              checked={isActive}
              onChange={(e) => setIsActive(e.target.checked)}
            />{' '}
            앱에 노출
          </label>
        </div>
      </div>
      {error && <div className="error">{error}</div>}
      <div className="submit-row">
        <button onClick={save} disabled={saving}>
          {saving ? '저장 중…' : event ? '저장' : '등록'}
        </button>
      </div>
    </div>
  )
}

function ImageSection({
  event,
  onSaved,
}: {
  event: CommunityEvent
  onSaved: (event: CommunityEvent, message: string) => void
}) {
  const [file, setFile] = useState<File | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)

  const run = async (action: () => Promise<CommunityEvent>, done: string, failure: string) => {
    setError(null)
    setSaving(true)
    try {
      onSaved(await action(), done)
      setFile(null)
    } catch (err) {
      setError(err instanceof ApiError ? err.message : failure)
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="card">
      <h3 style={{ marginTop: 0 }}>이미지</h3>
      <p className="muted">목록 카드와 상세 화면 위쪽에 보여요. 선택이에요.</p>
      {event.image_url ? (
        <img className="thumb banner" src={event.image_url} alt="현재 이미지" />
      ) : (
        <p className="muted">등록된 이미지가 없어요.</p>
      )}
      <div className="field" style={{ marginTop: 12 }}>
        <input
          type="file"
          accept="image/jpeg,image/png,image/webp"
          onChange={(e) => setFile(e.target.files?.[0] ?? null)}
        />
      </div>
      {error && <div className="error">{error}</div>}
      <div className="submit-row">
        <button
          onClick={() =>
            file && run(() => setEventImage(event.id, file), '이미지를 저장했어요.', '업로드에 실패했어요.')
          }
          disabled={saving || !file}
        >
          {saving ? '처리 중…' : event.image_url ? '이미지 교체' : '이미지 등록'}
        </button>
        {event.image_url && (
          <button
            className="danger"
            onClick={() => run(() => deleteEventImage(event.id), '이미지를 지웠어요.', '삭제에 실패했어요.')}
            disabled={saving}
          >
            이미지 삭제
          </button>
        )}
      </div>
    </div>
  )
}

function DeleteSection({ event, onDeleted }: { event: CommunityEvent; onDeleted: () => void }) {
  const [confirming, setConfirming] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [deleting, setDeleting] = useState(false)

  const remove = async () => {
    setError(null)
    setDeleting(true)
    try {
      await deleteEvent(event.id)
      onDeleted()
    } catch (err) {
      setError(err instanceof ApiError ? err.message : '삭제에 실패했어요.')
      setDeleting(false)
    }
  }

  return (
    <div className="card">
      <h3 style={{ marginTop: 0 }}>삭제</h3>
      {error && <div className="error">{error}</div>}
      {confirming ? (
        <div className="confirm">
          <strong>이 이벤트를 삭제할까요?</strong> 이미지도 함께 지워지고 되돌릴 수 없어요.
          <div className="actions">
            <button className="danger" onClick={remove} disabled={deleting}>
              {deleting ? '삭제 중…' : '삭제'}
            </button>
            <button className="secondary" onClick={() => setConfirming(false)} disabled={deleting}>
              취소
            </button>
          </div>
        </div>
      ) : (
        <button className="danger" onClick={() => setConfirming(true)}>
          이벤트 삭제
        </button>
      )}
    </div>
  )
}
