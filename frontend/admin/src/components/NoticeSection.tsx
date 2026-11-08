import { useCallback, useEffect, useState } from 'react'

import { ApiError, listNotices, reorderNotices, type Notice } from '../api'
import NoticeCreateModal from '../modals/NoticeCreateModal'
import NoticeEditModal from '../modals/NoticeEditModal'

interface Props {
  /** 목록 로딩이 401이면(세션 만료 등) 인증 화면으로 되돌린다. */
  onUnauthorized: () => void
}

type Visibility = 'scheduled' | 'live' | 'expired'

/** 서버 routers/notices._is_visible과 같은 규칙. 앱에 지금 보이는지. */
function visibilityOf(notice: Notice, now: Date): Visibility {
  if (notice.starts_at && new Date(notice.starts_at) > now) return 'scheduled'
  if (notice.ends_at && new Date(notice.ends_at) < now) return 'expired'
  return 'live'
}

const VISIBILITY_LABEL: Record<Visibility, string> = {
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

/**
 * 저장 안 한 순서를 새로 받은 목록에 맞춘다. 순서를 바꾸던 중에 공지를 추가·삭제해도
 * 바꾸던 순서가 날아가지 않게 — 새 공지는 서버처럼 맨 앞에, 지운 공지는 뺀다.
 * 바꾸던 게 없으면 결과가 서버 순서와 같다.
 */
function keepLocalOrder(previous: string[] | null, loaded: Notice[]): string[] {
  const ids = loaded.map((notice) => notice.id)
  if (!previous) return ids
  const alive = new Set(ids)
  const known = new Set(previous)
  return [...ids.filter((id) => !known.has(id)), ...previous.filter((id) => alive.has(id))]
}

/**
 * 홈 구성 페이지의 공지사항 섹션. 위에서부터 앱 홈 배너·공지 목록에 나오고, 팝업이 켜진
 * 공지는 앱을 켤 때 이 순서대로 하나씩 뜬다. 순서는 ↑↓로 바꾸고 저장한다. 등록·수정은 모달.
 */
export default function NoticeSection({ onUnauthorized }: Props) {
  const [notices, setNotices] = useState<Notice[] | null>(null)
  /** 화면에 보이는 순서(공지 id). 저장 전이면 서버 순서와 다르다. */
  const [order, setOrder] = useState<string[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [orderError, setOrderError] = useState<string | null>(null)
  const [savingOrder, setSavingOrder] = useState(false)
  const [orderSaved, setOrderSaved] = useState(false)
  const [creating, setCreating] = useState(false)
  /** 수정 모달 대상. message는 등록 직후 이어서 열 때 전달된다. */
  const [editing, setEditing] = useState<{ id: string; message?: string } | null>(null)

  const reload = useCallback(() => {
    listNotices()
      .then((loaded) => {
        setNotices(loaded)
        setOrder((previous) => keepLocalOrder(previous, loaded))
        setError(null)
      })
      .catch((err: unknown) => {
        if (err instanceof ApiError && err.status === 401) {
          onUnauthorized()
          return
        }
        setError(err instanceof ApiError ? err.message : '공지 목록을 불러오지 못했어요.')
      })
  }, [onUnauthorized])

  useEffect(() => {
    reload()
  }, [reload])

  const now = new Date()
  const byId = new Map((notices ?? []).map((notice) => [notice.id, notice]))
  const ordered = (order ?? []).flatMap((id) => byId.get(id) ?? [])
  const serverKey = (notices ?? []).map((notice) => notice.id).join(',')
  const orderDirty = order != null && order.join(',') !== serverKey

  const move = (index: number, delta: number) => {
    if (!order) return
    const next = [...order]
    const [moved] = next.splice(index, 1)
    next.splice(index + delta, 0, moved)
    setOrder(next)
    setOrderSaved(false)
    setOrderError(null)
  }

  const saveOrder = async () => {
    if (!order) return
    setSavingOrder(true)
    setOrderError(null)
    try {
      const saved = await reorderNotices(order)
      setNotices(saved)
      setOrder(saved.map((notice) => notice.id))
      setOrderSaved(true)
    } catch (err) {
      if (err instanceof ApiError && err.status === 401) {
        onUnauthorized()
        return
      }
      setOrderError(err instanceof ApiError ? err.message : '순서를 저장하지 못했어요.')
    } finally {
      setSavingOrder(false)
    }
  }

  return (
    <div className="card">
      <div className="row" style={{ justifyContent: 'space-between', alignItems: 'center' }}>
        <h3 style={{ margin: 0 }}>공지사항</h3>
        <button onClick={() => setCreating(true)}>+ 공지 추가</button>
      </div>
      <p className="muted">
        위에서부터 앱에 보이는 순서예요. 이미지가 있는 공지만 홈 상단 배너에 나오고, 팝업이 켜진
        공지는 앱을 켤 때 이 순서대로 하나씩 떠요.
      </p>
      {error && <div className="error">{error}</div>}
      {notices == null && !error && <p className="muted">불러오는 중…</p>}
      {notices && notices.length === 0 && <p className="muted">등록된 공지가 없어요.</p>}
      {notices && notices.length > 0 && (
        <table>
          <thead>
            <tr>
              <th style={{ width: 32 }}>#</th>
              <th></th>
              <th>제목</th>
              <th>상태</th>
              <th>노출 기간</th>
              <th>등록일</th>
              <th>순서</th>
            </tr>
          </thead>
          <tbody>
            {ordered.map((notice, index) => {
              const visibility = visibilityOf(notice, now)
              return (
                <tr key={notice.id} onClick={() => setEditing({ id: notice.id })}>
                  <td>
                    <strong>{index + 1}</strong>
                  </td>
                  <td style={{ width: 104 }}>
                    {notice.image_url ? (
                      <img className="thumb wide" src={notice.image_url} alt="" />
                    ) : (
                      <div className="thumb wide placeholder">배너 없음</div>
                    )}
                  </td>
                  <td>
                    <strong>{notice.title}</strong>
                    <div className="muted clamp">{notice.body}</div>
                  </td>
                  <td>
                    <div className="row" style={{ gap: 4, flexWrap: 'nowrap' }}>
                      <span className={`badge ${visibility}`}>{VISIBILITY_LABEL[visibility]}</span>
                      {notice.show_on_launch && <span className="badge popup">팝업</span>}
                    </div>
                  </td>
                  <td className="muted">
                    {notice.starts_at || notice.ends_at
                      ? `${formatDateTime(notice.starts_at)} ~ ${formatDateTime(notice.ends_at)}`
                      : '상시'}
                  </td>
                  <td className="muted">{formatDateTime(notice.created_at)}</td>
                  {/* 행을 누르면 수정 모달이 열리므로 버튼 클릭은 행까지 올리지 않는다. */}
                  <td
                    style={{ width: 1, whiteSpace: 'nowrap' }}
                    onClick={(event) => event.stopPropagation()}
                  >
                    <div className="row" style={{ gap: 6 }}>
                      <button
                        className="secondary small"
                        disabled={index === 0}
                        onClick={() => move(index, -1)}
                        aria-label="위로"
                      >
                        ↑
                      </button>
                      <button
                        className="secondary small"
                        disabled={index === ordered.length - 1}
                        onClick={() => move(index, 1)}
                        aria-label="아래로"
                      >
                        ↓
                      </button>
                    </div>
                  </td>
                </tr>
              )
            })}
          </tbody>
        </table>
      )}
      {orderError && <div className="error">{orderError}</div>}
      {notices && notices.length > 1 && (orderDirty || orderSaved) && (
        <div className="submit-row">
          <button onClick={saveOrder} disabled={!orderDirty || savingOrder}>
            {savingOrder ? '저장 중…' : '순서 저장'}
          </button>
          {orderDirty && (
            <button
              className="secondary"
              onClick={() => {
                setOrder(notices.map((notice) => notice.id))
                setOrderError(null)
              }}
            >
              되돌리기
            </button>
          )}
          {orderSaved && !orderDirty && <span className="muted">순서를 저장했어요.</span>}
        </div>
      )}

      {creating && (
        <NoticeCreateModal
          onClose={() => setCreating(false)}
          onCreated={(notice, message) => {
            setCreating(false)
            reload()
            // 등록 직후 수정 모달을 이어서 열어 결과를 바로 확인/보완하게 한다.
            setEditing({ id: notice.id, message })
          }}
        />
      )}
      {editing && (
        <NoticeEditModal
          noticeId={editing.id}
          initialMessage={editing.message}
          onClose={() => setEditing(null)}
          onChanged={reload}
        />
      )}
    </div>
  )
}
