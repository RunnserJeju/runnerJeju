import { useCallback, useEffect, useState } from 'react'

import {
  ApiError,
  createEvent,
  deleteEvent,
  deleteEventImage,
  listEvents,
  listEventViews,
  reorderEvents,
  setEventImage,
  updateEvent,
  type CommunityEvent,
  type CourseVisibility,
  type CommunityEventPayload,
  type EventViewCount,
} from '../api'
import { ImageSection, imageChanged, NO_IMAGE_CHANGE, type ImageChange } from '../components/ImageSections'
import { OrderCell, OrderSaveRow, useListOrder } from '../components/ListOrder'
import Modal from '../components/Modal'
import SaveFooter from '../components/SaveFooter'
import { runSteps, snapshot, type SaveStep } from '../utils/saveSteps'

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

/**
 * 커뮤니티 이벤트 관리(#70). 그림 한 장(선택)과 게시글. 위에서부터 앱에 보이는 순서이고
 * ↑↓로 바꿔 저장한다(공지와 같다). 조회수는 앱이 상세를 열 때 남기는 로그를 센다.
 */
export default function EventListPage({ onUnauthorized }: Props) {
  const [events, setEvents] = useState<CommunityEvent[] | null>(null)
  /** 이벤트 id → 조회 수. 못 불러오면 null(열에 '—'). */
  const [views, setViews] = useState<Map<string, EventViewCount> | null>(null)
  const [error, setError] = useState<string | null>(null)
  /** 열린 모달. 'new'면 등록, 아니면 그 이벤트 수정. */
  const [editing, setEditing] = useState<'new' | CommunityEvent | null>(null)

  const reload = useCallback(() => {
    // 조회수는 곁가지다. 실패해도 목록은 보여야 하므로 따로 받는다.
    listEventViews()
      .then((loaded) => setViews(new Map(loaded.map((count) => [count.event_id, count]))))
      .catch(() => setViews(null))
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
  const order = useListOrder({
    items: events,
    save: reorderEvents,
    onSaved: setEvents,
    onUnauthorized,
  })
  const { ordered } = order

  return (
    <>
      <div className="page-head">
        <h2>이벤트</h2>
        <button onClick={() => setEditing('new')}>+ 이벤트 추가</button>
      </div>
      <p className="muted page-desc">
        앱 커뮤니티 탭의 이벤트 목록에 위에서부터 이 순서로 보여요. 본문에 붙여 넣은 링크는 앱에서
        눌러 열 수 있어요. 조회수는 앱에서 상세를 연 횟수(본 사람 수)예요.
      </p>
      {error && <div className="error">{error}</div>}
      {events == null && !error && <p className="muted">불러오는 중…</p>}
      {events && events.length === 0 && <p className="muted">등록된 이벤트가 없어요.</p>}
      {events && events.length > 0 && (
        <table>
          <thead>
            <tr>
              <th style={{ width: 32 }}>#</th>
              <th></th>
              <th>제목</th>
              <th>상태</th>
              <th>노출 기간</th>
              <th>조회수</th>
              <th>등록일</th>
              <th>순서</th>
            </tr>
          </thead>
          <tbody>
            {ordered.map((event, index) => {
              const visibility = visibilityOf(event, now)
              const count = views?.get(event.id)
              return (
                <tr key={event.id} onClick={() => setEditing(event)}>
                  <td>
                    <strong>{index + 1}</strong>
                  </td>
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
                  <td style={{ whiteSpace: 'nowrap' }}>
                    {views == null ? (
                      <span className="muted">—</span>
                    ) : (
                      <>
                        {(count?.views ?? 0).toLocaleString()}
                        <span className="muted"> ({(count?.viewers ?? 0).toLocaleString()}명)</span>
                      </>
                    )}
                  </td>
                  <td className="muted">{formatDateTime(event.created_at)}</td>
                  <OrderCell index={index} count={ordered.length} onMove={order.move} />
                </tr>
              )
            })}
          </tbody>
        </table>
      )}
      <OrderSaveRow state={order} />

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

interface EventValues {
  title: string
  body: string
  startsAt: string
  endsAt: string
  isActive: boolean
  visibility: CourseVisibility
}

function valuesFromEvent(event: CommunityEvent | null): EventValues {
  return {
    title: event?.title ?? '',
    body: event?.body ?? '',
    startsAt: toLocalInput(event?.starts_at ?? null),
    endsAt: toLocalInput(event?.ends_at ?? null),
    isActive: event?.is_active ?? true,
    visibility: event?.visibility ?? 'admin',
  }
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
  const [values, setValues] = useState(() => valuesFromEvent(event))
  /** 서버에 저장된 내용의 스냅샷. values와 다르면 '내용 변경'이다. */
  const [savedKey, setSavedKey] = useState(() => snapshot(valuesFromEvent(event)))
  const [image, setImage] = useState<ImageChange>(NO_IMAGE_CHANGE)
  const [message, setMessage] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)

  const set = (patch: Partial<EventValues>) => {
    setValues((prev) => ({ ...prev, ...patch }))
    setMessage(null)
  }

  const contentDirty = snapshot(values) !== savedKey
  const imageDirty = imageChanged(image)
  const dirty = [contentDirty && '내용', imageDirty && '이미지'].filter(
    (label): label is string => Boolean(label),
  )

  const save = async () => {
    setError(null)
    setMessage(null)
    let payload: CommunityEventPayload | null = null
    if (contentDirty || !event) {
      if (!values.title.trim()) return setError('제목을 입력해 주세요.')
      if (!values.body.trim()) return setError('내용을 입력해 주세요.')
      const start = values.startsAt ? new Date(values.startsAt) : null
      const end = values.endsAt ? new Date(values.endsAt) : null
      if (start && end && end < start) return setError('노출 종료가 시작보다 빠를 수 없어요.')
      payload = {
        title: values.title.trim(),
        body: values.body.trim(),
        starts_at: start ? start.toISOString() : null,
        ends_at: end ? end.toISOString() : null,
        is_active: values.isActive,
        visibility: values.visibility,
      }
    }

    let latest: CommunityEvent | null = null
    const steps: SaveStep[] = []
    if (payload) {
      const body = payload
      const snap = snapshot(values)
      steps.push({
        label: event ? '내용' : '등록',
        run: async () => {
          latest = event ? await updateEvent(event.id, body) : await createEvent(body)
          setSavedKey(snap)
        },
      })
    }
    if (event && imageDirty) {
      const { file } = image
      steps.push({
        label: '이미지',
        run: async () => {
          latest = file ? await setEventImage(event.id, file) : await deleteEventImage(event.id)
          setImage(NO_IMAGE_CHANGE)
        },
      })
    }

    setSaving(true)
    const failure = await runSteps(steps)
    setSaving(false)
    if (latest) onSaved(latest)
    if (failure) {
      setError(failure)
      return
    }
    setMessage(event ? '저장했어요.' : '등록했어요. 이어서 이미지를 올릴 수 있어요.')
  }

  return (
    <Modal
      title={event ? `이벤트 수정 — ${event.title}` : '새 이벤트'}
      onClose={onClose}
      closable={!saving}
      footer={
        <SaveFooter
          dirty={dirty}
          saving={saving}
          error={error}
          onSave={save}
          label={event ? '전체 저장' : '등록'}
          alwaysEnabled={!event}
        />
      }
    >
      {message && <div className="notice" style={{ marginTop: 0 }}>{message}</div>}
      <div className="card">
        <h3 style={{ marginTop: 0 }}>내용</h3>
        <div className="field">
          <label htmlFor="event-title">제목</label>
          <input
            id="event-title"
            maxLength={200}
            value={values.title}
            onChange={(e) => set({ title: e.target.value })}
          />
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
            value={values.body}
            onChange={(e) => set({ body: e.target.value })}
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
              value={values.startsAt}
              onChange={(e) => set({ startsAt: e.target.value })}
            />
          </div>
          <div className="field">
            <label htmlFor="event-ends">
              노출 종료 <span className="hint">비우면 무기한</span>
            </label>
            <input
              id="event-ends"
              type="datetime-local"
              value={values.endsAt}
              onChange={(e) => set({ endsAt: e.target.value })}
            />
          </div>
        </div>
        <div className="row">
          <div className="field">
            <label>
              <input
                type="checkbox"
                checked={values.isActive}
                onChange={(e) => set({ isActive: e.target.checked })}
              />{' '}
              앱에 노출
            </label>
          </div>
          <div className="field">
            <label htmlFor="ev-visibility">
              공개 범위 <span className="hint">운영자: role=admin 계정에만 보여요</span>
            </label>
            <select
              id="ev-visibility"
              value={values.visibility}
              onChange={(e) => set({ visibility: e.target.value as CourseVisibility })}
            >
              <option value="admin">운영자</option>
              <option value="public">전체 공개</option>
            </select>
          </div>
        </div>
      </div>
      {event && (
        <ImageSection
          title="이미지"
          description="목록 카드와 상세 화면 위쪽에 보여요. 선택이에요."
          imageClass="thumb banner"
          currentUrl={event.image_url}
          value={image}
          onChange={setImage}
        />
      )}
      {event && <DeleteSection event={event} onDeleted={onDeleted} />}
    </Modal>
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
