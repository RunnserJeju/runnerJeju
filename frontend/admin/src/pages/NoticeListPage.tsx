import { useCallback, useEffect, useState } from 'react'

import { ApiError, listNotices, type Notice } from '../api'
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

export default function NoticeListPage({ onUnauthorized }: Props) {
  const [notices, setNotices] = useState<Notice[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [creating, setCreating] = useState(false)
  /** 수정 모달 대상. message는 등록 직후 이어서 열 때 전달된다. */
  const [editing, setEditing] = useState<{ id: string; message?: string } | null>(null)

  const reload = useCallback(() => {
    listNotices()
      .then((loaded) => {
        setNotices(loaded)
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

  return (
    <>
      <div className="page-head">
        <h2>공지사항</h2>
        <button onClick={() => setCreating(true)}>+ 공지 추가</button>
      </div>
      <p className="muted" style={{ marginTop: -12 }}>
        이미지를 올린 공지는 앱 홈 상단 배너로도 실려요.
      </p>
      {error && <div className="error">{error}</div>}
      {notices == null && !error && <p className="muted">불러오는 중…</p>}
      {notices && notices.length === 0 && <p className="muted">등록된 공지가 없어요.</p>}
      {notices && notices.length > 0 && (
        <table>
          <thead>
            <tr>
              <th></th>
              <th>제목</th>
              <th>상태</th>
              <th>노출 기간</th>
              <th>등록일</th>
            </tr>
          </thead>
          <tbody>
            {notices.map((notice) => {
              const visibility = visibilityOf(notice, now)
              return (
                <tr key={notice.id} onClick={() => setEditing({ id: notice.id })}>
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
                    <span className={`badge ${visibility}`}>{VISIBILITY_LABEL[visibility]}</span>
                  </td>
                  <td className="muted">
                    {notice.starts_at || notice.ends_at
                      ? `${formatDateTime(notice.starts_at)} ~ ${formatDateTime(notice.ends_at)}`
                      : '상시'}
                  </td>
                  <td className="muted">{formatDateTime(notice.created_at)}</td>
                </tr>
              )
            })}
          </tbody>
        </table>
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
    </>
  )
}
