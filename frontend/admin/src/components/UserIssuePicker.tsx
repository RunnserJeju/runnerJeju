import { useEffect, useState } from 'react'

import { ApiError, listUsers, type UserSummary } from '../api'

const USER_PAGE = 20

interface Props {
  /** 지급 확인 창 문구. */
  confirmText: (count: number) => string
  /** 고른 회원에게 지급하고, 화면에 띄울 결과 문구를 돌려준다. 실패는 throw. */
  onIssue: (userIds: string[]) => Promise<string>
}

/** 운영자 지급 UI: 회원을 검색해 체크하고 한 번에 준다. 쿠폰·스탬프 지급이 같이 쓴다. */
export default function UserIssuePicker({ confirmText, onIssue }: Props) {
  const [draft, setDraft] = useState('')
  const [keyword, setKeyword] = useState('')
  const [users, setUsers] = useState<UserSummary[] | null>(null)
  const [selected, setSelected] = useState<Map<string, UserSummary>>(new Map())
  const [error, setError] = useState<string | null>(null)
  const [message, setMessage] = useState<string | null>(null)
  const [issuing, setIssuing] = useState(false)

  useEffect(() => {
    listUsers(keyword, USER_PAGE, 0)
      .then((page) => setUsers(page.items))
      .catch((err: unknown) =>
        setError(err instanceof ApiError ? err.message : '회원을 불러오지 못했어요.'),
      )
  }, [keyword])

  const toggle = (user: UserSummary) => {
    setSelected((prev) => {
      const next = new Map(prev)
      if (next.has(user.id)) next.delete(user.id)
      else next.set(user.id, user)
      return next
    })
    setMessage(null)
  }

  const issue = async () => {
    if (selected.size === 0) return
    if (!window.confirm(confirmText(selected.size))) return
    setError(null)
    setIssuing(true)
    try {
      setMessage(await onIssue([...selected.keys()]))
      setSelected(new Map())
    } catch (err) {
      setError(err instanceof ApiError ? err.message : '지급에 실패했어요.')
    } finally {
      setIssuing(false)
    }
  }

  const label = (user: UserSummary) => user.nickname ?? user.email ?? user.id.slice(0, 8)

  return (
    <div className="card">
      {message && (
        <div className="notice" style={{ marginTop: 0 }}>
          {message}
        </div>
      )}
      <form
        className="search-row"
        onSubmit={(event) => {
          event.preventDefault()
          setKeyword(draft)
        }}
      >
        <input
          placeholder="닉네임 또는 이메일"
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
        />
        <button type="submit" className="secondary">
          검색
        </button>
      </form>
      {error && <div className="error">{error}</div>}
      {users == null && !error && <p className="muted">불러오는 중…</p>}
      {users && users.length === 0 && <p className="muted">조건에 맞는 회원이 없어요.</p>}
      {users && users.length > 0 && (
        <table className="users-table">
          <thead>
            <tr>
              <th></th>
              <th>닉네임</th>
              <th>이메일</th>
              <th>완주</th>
            </tr>
          </thead>
          <tbody>
            {users.map((user) => (
              <tr key={user.id} onClick={() => toggle(user)}>
                <td style={{ width: 32 }}>
                  <input type="checkbox" checked={selected.has(user.id)} readOnly />
                </td>
                <td>{user.nickname ?? <span className="muted">(미설정)</span>}</td>
                <td className="muted">{user.email ?? '—'}</td>
                <td className="muted">{user.completed_count}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
      {selected.size > 0 && (
        <p className="muted" style={{ marginTop: 12 }}>
          고른 회원: {[...selected.values()].map(label).join(', ')}
        </p>
      )}
      <div className="submit-row">
        <button onClick={issue} disabled={issuing || selected.size === 0}>
          {issuing ? '지급 중…' : `${selected.size}명에게 지급`}
        </button>
      </div>
    </div>
  )
}
