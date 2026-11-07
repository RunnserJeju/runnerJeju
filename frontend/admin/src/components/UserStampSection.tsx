import { useCallback, useEffect, useState } from 'react'

import { ApiError, getUserStamps, revokeUserStamp, type UserStamp } from '../api'
import { askRevokeReason } from './revokeReason'

interface Props {
  userId: string
  onUnauthorized: () => void
  /** 회수가 끝나면 부른다. 운영 처리 이력을 다시 불러오는 용도. */
  onChanged?: () => void
}

/** 회원 상세 팝업의 보유 스탬프. 지급은 스탬프 페이지에서, 회수는 여기서 한 개씩 한다. */
export default function UserStampSection({ userId, onUnauthorized, onChanged }: Props) {
  const [stamps, setStamps] = useState<UserStamp[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [busyId, setBusyId] = useState<string | null>(null)

  const handleError = useCallback(
    (err: unknown, fallback: string) => {
      if (err instanceof ApiError && err.status === 401) {
        onUnauthorized()
        return
      }
      setError(err instanceof ApiError ? err.message : fallback)
    },
    [onUnauthorized],
  )

  useEffect(() => {
    let stale = false
    setStamps(null)
    setError(null)
    getUserStamps(userId)
      .then((result) => {
        if (!stale) setStamps(result)
      })
      .catch((err) => {
        if (!stale) handleError(err, '스탬프를 불러오지 못했어요.')
      })
    return () => {
      stale = true
    }
  }, [userId, handleError])

  const revoke = async (stamp: UserStamp) => {
    const reason = askRevokeReason(
      `"${stamp.name}" 스탬프를 회수할까요?\n\n빙고판의 해당 칸도 비워져요. 이 스탬프로 이미 받은 빙고 줄 보상은 그대로 남아요(필요하면 쿠폰에서 따로 회수).`,
    )
    if (reason == null) return
    setBusyId(stamp.id)
    setError(null)
    try {
      await revokeUserStamp(userId, stamp.id, reason)
      setStamps((prev) => prev?.filter((s) => s.id !== stamp.id) ?? null)
      onChanged?.()
    } catch (err) {
      handleError(err, '스탬프를 회수하지 못했어요.')
    } finally {
      setBusyId(null)
    }
  }

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
              <th></th>
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
                <td className="nowrap" style={{ textAlign: 'right' }}>
                  <button
                    type="button"
                    className="danger small"
                    disabled={busyId != null}
                    onClick={() => void revoke(stamp)}
                  >
                    {busyId === stamp.id ? '회수 중…' : '회수'}
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </>
  )
}
