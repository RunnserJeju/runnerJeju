import { useEffect, useState } from 'react'

import { ApiError, getUserStamps, type UserStamp } from '../api'

interface Props {
  userId: string
  onUnauthorized: () => void
}

/** 회원 상세 팝업의 보유 스탬프. 보기만 한다 — 지급은 스탬프 페이지에서 한다. */
export default function UserStampSection({ userId, onUnauthorized }: Props) {
  const [stamps, setStamps] = useState<UserStamp[] | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let stale = false
    setStamps(null)
    setError(null)
    getUserStamps(userId)
      .then((result) => {
        if (!stale) setStamps(result)
      })
      .catch((err) => {
        if (stale) return
        if (err instanceof ApiError && err.status === 401) {
          onUnauthorized()
          return
        }
        setError(err instanceof ApiError ? err.message : '스탬프를 불러오지 못했어요.')
      })
    return () => {
      stale = true
    }
  }, [userId, onUnauthorized])

  return (
    <>
      <h3 style={{ marginTop: 24 }}>보유 스탬프{stamps ? ` (${stamps.length})` : ''}</h3>
      {error && <div className="error">{error}</div>}
      {stamps == null && !error && <p className="muted">불러오는 중…</p>}
      {stamps && stamps.length === 0 && <p className="muted">받은 스탬프가 없어요.</p>}
      {stamps && stamps.length > 0 && (
        <table className="users-table">
          <thead>
            <tr>
              <th></th>
              <th>스탬프</th>
              <th>획득 일시</th>
              <th>획득 경로</th>
            </tr>
          </thead>
          <tbody>
            {stamps.map((stamp) => (
              <tr key={stamp.id}>
                <td style={{ width: 64 }}>
                  {stamp.display_image_url ? (
                    <img className="thumb round" src={stamp.display_image_url} alt="" />
                  ) : (
                    <div className="thumb round placeholder">없음</div>
                  )}
                </td>
                <td>
                  <strong>{stamp.name}</strong>
                </td>
                <td className="muted nowrap">{new Date(stamp.acquired_at).toLocaleString()}</td>
                <td className="muted">{stamp.from_run ? '러닝' : '운영자 지급'}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </>
  )
}
