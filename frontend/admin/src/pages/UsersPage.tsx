import { useCallback, useEffect, useState } from 'react'

import { ApiError, getUser, listUsers, type UserDetail, type UserSummary } from '../api'
import Modal from '../components/Modal'

const PAGE_SIZE = 50

const PROVIDER_LABEL: Record<string, string> = {
  kakao: '카카오',
  apple: '애플',
  google: '구글',
}

const PLATFORM_LABEL: Record<string, string> = {
  ios: 'iPhone',
  android: 'Android',
}

interface Props {
  onUnauthorized: () => void
}

/** 회원 목록(가입일 최신순). 닉네임·이메일 검색, 페이지 이동, 행을 누르면 상세 팝업. */
export default function UsersPage({ onUnauthorized }: Props) {
  const [draft, setDraft] = useState('')
  const [keyword, setKeyword] = useState('')
  const [page, setPage] = useState(0)
  const [total, setTotal] = useState(0)
  const [users, setUsers] = useState<UserSummary[] | null>(null)
  const [detail, setDetail] = useState<UserDetail | null>(null)
  const [error, setError] = useState<string | null>(null)

  const handleError = useCallback(
    (err: unknown) => {
      if (err instanceof ApiError && err.status === 401) {
        onUnauthorized()
        return
      }
      setError(err instanceof ApiError ? err.message : '회원 목록을 불러오지 못했어요.')
    },
    [onUnauthorized],
  )

  useEffect(() => {
    setUsers(null)
    listUsers(keyword, PAGE_SIZE, page * PAGE_SIZE)
      .then((result) => {
        setUsers(result.items)
        setTotal(result.total)
        setError(null)
      })
      .catch(handleError)
  }, [keyword, page, handleError])

  const openDetail = (id: string) => {
    getUser(id).then(setDetail).catch(handleError)
  }

  const pageCount = Math.max(1, Math.ceil(total / PAGE_SIZE))

  return (
    <>
      <div className="page-head">
        <h2>회원</h2>
        <span className="muted">{total.toLocaleString()}명</span>
      </div>

      <form
        className="search-row"
        onSubmit={(event) => {
          event.preventDefault()
          setPage(0)
          setKeyword(draft)
        }}
      >
        <input
          placeholder="닉네임 또는 이메일"
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
        />
        <button type="submit">검색</button>
        {keyword && (
          <button
            type="button"
            className="secondary"
            onClick={() => {
              setDraft('')
              setKeyword('')
              setPage(0)
            }}
          >
            초기화
          </button>
        )}
      </form>

      {error && <div className="error">{error}</div>}
      {users == null && !error && <p className="muted">불러오는 중…</p>}
      {users && users.length === 0 && <p className="muted">조건에 맞는 회원이 없어요.</p>}
      {users && users.length > 0 && (
        <table className="users-table">
          <thead>
            <tr>
              <th>닉네임</th>
              <th>이메일</th>
              <th>가입 경로</th>
              <th>기기</th>
              <th>가입일</th>
              <th>최근 로그인</th>
              <th>완주</th>
            </tr>
          </thead>
          <tbody>
            {users.map((u) => (
              <tr key={u.id} onClick={() => openDetail(u.id)}>
                <td>
                  <strong>{u.nickname ?? <span className="muted">(없음)</span>}</strong>
                </td>
                <td className="muted">{u.email ?? '—'}</td>
                <td>{u.providers.map((p) => PROVIDER_LABEL[p] ?? p).join(', ') || '—'}</td>
                <td>{u.platform ? (PLATFORM_LABEL[u.platform] ?? u.platform) : <span className="muted">—</span>}</td>
                <td className="nowrap">{formatDate(u.created_at)}</td>
                <td className="nowrap muted">{u.last_login_at ? formatDate(u.last_login_at) : '—'}</td>
                <td>{u.completed_count}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      {pageCount > 1 && (
        <div className="pager">
          <button className="secondary small" disabled={page === 0} onClick={() => setPage(page - 1)}>
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

      {detail && (
        <Modal title={detail.nickname ?? '(닉네임 없음)'} onClose={() => setDetail(null)}>
          <table className="kv-table">
            <tbody>
              <tr>
                <th>이메일</th>
                <td>{detail.email ?? '—'}</td>
              </tr>
              <tr>
                <th>가입 경로</th>
                <td>{detail.providers.map((p) => PROVIDER_LABEL[p] ?? p).join(', ') || '—'}</td>
              </tr>
              <tr>
                <th>기기</th>
                <td>{detail.platform ? (PLATFORM_LABEL[detail.platform] ?? detail.platform) : '—'}</td>
              </tr>
              <tr>
                <th>가입일</th>
                <td>{formatDate(detail.created_at)}</td>
              </tr>
              <tr>
                <th>최근 로그인</th>
                <td>{detail.last_login_at ? formatDate(detail.last_login_at) : '—'}</td>
              </tr>
              <tr>
                <th>회원 id</th>
                <td>{detail.id}</td>
              </tr>
            </tbody>
          </table>
          <h3>완주한 코스 {detail.completed_count}개</h3>
          {detail.completed_courses.length === 0 ? (
            <p className="muted">아직 완주한 코스가 없어요.</p>
          ) : (
            <table className="kv-table">
              <tbody>
                {detail.completed_courses.map((c) => (
                  <tr key={c.course_id}>
                    <th>{formatDate(c.acquired_at)}</th>
                    <td>{c.name}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </Modal>
      )}
    </>
  )
}

function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString('ko-KR', {
    timeZone: 'Asia/Seoul',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  })
}
