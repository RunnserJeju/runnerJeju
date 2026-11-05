import { useEffect, useState } from 'react'

import { ApiError, listUsers, type UserSummary } from '../api'

const USER_PAGE = 10

interface Props {
  /** 지급 확인 창 문구. */
  confirmText: (count: number) => string
  /** 고른 회원에게 지급하고, 화면에 띄울 결과 문구를 돌려준다. 실패는 throw. */
  onIssue: (userIds: string[]) => Promise<string>
  /** 이 페이지 회원 중 이미 받은 사람의 id. 주면 '보유'로 표시하고 고를 수 없게 한다. */
  loadHolders?: (userIds: string[]) => Promise<string[]>
}

/** 운영자 지급 UI: 회원을 검색해 체크하고 한 번에 준다. 쿠폰·스탬프 지급이 같이 쓴다. */
export default function UserIssuePicker({ confirmText, onIssue, loadHolders }: Props) {
  const [draft, setDraft] = useState('')
  const [keyword, setKeyword] = useState('')
  const [page, setPage] = useState(0)
  const [total, setTotal] = useState(0)
  const [users, setUsers] = useState<UserSummary[] | null>(null)
  const [holders, setHolders] = useState<Set<string>>(new Set())
  /** 지급 직후 보유 표시를 다시 불러오려는 신호. */
  const [issuedTick, setIssuedTick] = useState(0)
  const [selected, setSelected] = useState<Map<string, UserSummary>>(new Map())
  const [error, setError] = useState<string | null>(null)
  const [message, setMessage] = useState<string | null>(null)
  const [issuing, setIssuing] = useState(false)

  useEffect(() => {
    let stale = false
    listUsers(keyword, USER_PAGE, page * USER_PAGE)
      .then((result) => {
        if (stale) return
        setUsers(result.items)
        setTotal(result.total)
        setError(null)
      })
      .catch((err: unknown) => {
        if (!stale) setError(err instanceof ApiError ? err.message : '회원을 불러오지 못했어요.')
      })
    return () => {
      stale = true
    }
  }, [keyword, page])

  useEffect(() => {
    if (!loadHolders || !users || users.length === 0) {
      setHolders(new Set())
      return
    }
    let stale = false
    loadHolders(users.map((u) => u.id))
      .then((ids) => {
        if (!stale) setHolders(new Set(ids))
      })
      .catch(() => {
        if (!stale) setHolders(new Set())
      })
    return () => {
      stale = true
    }
    // loadHolders는 부모가 매 렌더 새로 만들 수 있어 users·지급 신호만 기준으로 다시 부른다.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [users, issuedTick])

  const toggle = (user: UserSummary) => {
    if (holders.has(user.id)) return
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
      setIssuedTick((n) => n + 1)
    } catch (err) {
      setError(err instanceof ApiError ? err.message : '지급에 실패했어요.')
    } finally {
      setIssuing(false)
    }
  }

  const label = (user: UserSummary) => user.nickname ?? user.email ?? user.id.slice(0, 8)
  const pageCount = Math.max(1, Math.ceil(total / USER_PAGE))

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
          setPage(0)
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
        <>
          <p className="muted" style={{ margin: '8px 0' }}>
            {keyword.trim() ? `“${keyword.trim()}” 검색 · ` : ''}총 {total.toLocaleString()}명
          </p>
          <table className="users-table">
            <thead>
              <tr>
                <th></th>
                <th>닉네임</th>
                <th>이메일</th>
                <th>완주</th>
                {loadHolders && <th></th>}
              </tr>
            </thead>
            <tbody>
              {users.map((user) => {
                const held = holders.has(user.id)
                return (
                  <tr
                    key={user.id}
                    onClick={() => toggle(user)}
                    style={held ? { opacity: 0.55, cursor: 'default' } : undefined}
                  >
                    <td style={{ width: 32 }}>
                      <input
                        type="checkbox"
                        checked={selected.has(user.id)}
                        disabled={held}
                        readOnly
                      />
                    </td>
                    <td>{user.nickname ?? <span className="muted">(미설정)</span>}</td>
                    <td className="muted">{user.email ?? '—'}</td>
                    <td className="muted">{user.completed_count}</td>
                    {loadHolders && (
                      <td>{held && <span className="badge scheduled">보유</span>}</td>
                    )}
                  </tr>
                )
              })}
            </tbody>
          </table>
        </>
      )}
      {pageCount > 1 && (
        <div className="pager">
          <button
            className="secondary small"
            disabled={page === 0}
            onClick={() => setPage(page - 1)}
          >
            이전
          </button>
          <span className="muted">
            {page + 1} / {pageCount}
          </span>
          <button
            className="secondary small"
            disabled={page + 1 >= pageCount}
            onClick={() => setPage(page + 1)}
          >
            다음
          </button>
        </div>
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
