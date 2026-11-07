import { useEffect, useState } from 'react'

import { ApiError, getUserAdminActions, type AdminAction } from '../api'

interface Props {
  userId: string
  onUnauthorized: () => void
  /** 바뀔 때마다 다시 불러온다. 같은 팝업에서 회수·지급한 직후 반영용. */
  version: number
}

const ACTION_LABEL: Record<string, string> = {
  stamp_issue: '스탬프 지급',
  stamp_revoke: '스탬프 회수',
  coupon_issue: '쿠폰 지급',
  coupon_revoke: '쿠폰 회수',
  course_complete: '완주 인정',
  reward_fulfill: '리워드 지급완료',
}

/** detail에서 사람이 읽을 대상 이름을 고른다. 행위마다 키가 달라 순서대로 찾는다. */
function targetLabel(a: AdminAction): string {
  const d = a.detail
  const name = d.name ?? d.coupon_name ?? d.course_name
  const code = typeof d.code === 'string' ? ` (${d.code})` : ''
  return typeof name === 'string' ? `${name}${code}` : (a.target_id ?? '—')
}

/** 회원 상세 팝업의 운영 처리 이력. 운영툴에서 이 회원에게 한 지급·회수·완주 인정·지급완료. */
export default function UserAdminActionSection({ userId, onUnauthorized, version }: Props) {
  const [rows, setRows] = useState<AdminAction[] | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let stale = false
    setError(null)
    getUserAdminActions(userId)
      .then((result) => {
        if (!stale) setRows(result)
      })
      .catch((err) => {
        if (stale) return
        if (err instanceof ApiError && err.status === 401) {
          onUnauthorized()
          return
        }
        setError(err instanceof ApiError ? err.message : '처리 이력을 불러오지 못했어요.')
      })
    return () => {
      stale = true
    }
  }, [userId, onUnauthorized, version])

  return (
    <>
      <h3 style={{ marginTop: 24 }}>운영 처리 이력{rows ? ` (${rows.length})` : ''}</h3>
      {error && <div className="error">{error}</div>}
      {rows == null && !error && <p className="muted">불러오는 중…</p>}
      {rows && rows.length === 0 && <p className="muted">운영자가 처리한 내역이 없어요.</p>}
      {rows && rows.length > 0 && (
        <table className="users-table">
          <thead>
            <tr>
              <th>일시</th>
              <th>처리</th>
              <th>대상</th>
              <th>사유</th>
              <th>운영자</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((a) => (
              <tr key={a.id}>
                <td className="muted nowrap">{new Date(a.created_at).toLocaleString()}</td>
                <td>{ACTION_LABEL[a.action] ?? a.action}</td>
                <td>{targetLabel(a)}</td>
                <td className="muted">
                  {typeof a.detail.reason === 'string' ? a.detail.reason : '—'}
                </td>
                <td className="muted nowrap">{a.admin_username}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </>
  )
}
