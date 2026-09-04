import { useEffect, useState } from 'react'

import { ApiError, getMe, logout, type AdminIdentity } from './api'
import AuthPage from './pages/AuthPage'
import CourseListPage from './pages/CourseListPage'
import NoticeListPage from './pages/NoticeListPage'

type Auth =
  | { status: 'checking' }
  | { status: 'anon' }
  | { status: 'error' }
  | { status: 'authed'; who: AdminIdentity }

type Tab = 'courses' | 'notices'

const TABS: { key: Tab; label: string }[] = [
  { key: 'courses', label: '코스' },
  { key: 'notices', label: '공지사항' },
]

// 페이지가 둘뿐이라 라우터 없이 상단 탭(state)으로 가른다.
// 등록/수정은 목록 위 모달로 처리한다.
export default function App() {
  const [auth, setAuth] = useState<Auth>({ status: 'checking' })
  const [tab, setTab] = useState<Tab>('courses')

  // 최초 로드 시 세션이 살아있는지 서버에 물어본다(쿠키는 JS가 못 읽으므로).
  const checkSession = () => {
    setAuth({ status: 'checking' })
    getMe().then(
      (who) => setAuth({ status: 'authed', who }),
      (err) => {
        // 401만 "로그인 안 됨"이다. 네트워크/5xx 같은 일시적 실패까지 로그인
        // 화면으로 보내면, 실은 유효한 세션을 숨기게 된다 — 이 경우 재시도로 유도.
        const notAuthed = err instanceof ApiError && err.status === 401
        setAuth({ status: notAuthed ? 'anon' : 'error' })
      },
    )
  }
  useEffect(checkSession, [])

  if (auth.status === 'checking') {
    return <div className="auth-page"><p className="muted">확인 중…</p></div>
  }

  if (auth.status === 'error') {
    return (
      <div className="auth-page">
        <div className="auth-card">
          <p className="muted">서버에 연결하지 못했어요.</p>
          <button onClick={checkSession}>다시 시도</button>
        </div>
      </div>
    )
  }

  if (auth.status === 'anon') {
    return <AuthPage onAuthed={(who) => setAuth({ status: 'authed', who })} />
  }

  const signOut = async () => {
    try {
      await logout()
    } finally {
      // 서버 호출이 실패해도 화면은 로그아웃 상태로 돌린다.
      setAuth({ status: 'anon' })
    }
  }

  return (
    <>
      <header className="topbar">
        <h1>Runners Jeju Dashboard</h1>
        <nav>
          {TABS.map((t) => (
            <a
              key={t.key}
              href={`#${t.key}`}
              className={tab === t.key ? 'active' : undefined}
              onClick={(event) => {
                event.preventDefault()
                setTab(t.key)
              }}
            >
              {t.label}
            </a>
          ))}
        </nav>
        <span className="muted" style={{ marginLeft: 'auto' }}>
          {auth.who.display_name ?? auth.who.username}
        </span>
        <button className="secondary small" onClick={signOut}>
          로그아웃
        </button>
      </header>
      <main>
        {tab === 'courses' ? (
          <CourseListPage onUnauthorized={() => setAuth({ status: 'anon' })} />
        ) : (
          <NoticeListPage onUnauthorized={() => setAuth({ status: 'anon' })} />
        )}
      </main>
    </>
  )
}
