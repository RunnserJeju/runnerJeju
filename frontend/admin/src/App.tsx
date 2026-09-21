import { Suspense, lazy, useEffect, useState } from 'react'

import { ApiError, getMe, logout, type AdminIdentity } from './api'
import AuthPage from './pages/AuthPage'
import CourseListPage from './pages/CourseListPage'
import CourseStatsPage from './pages/CourseStatsPage'
import LogsPage from './pages/LogsPage'
import NoticeListPage from './pages/NoticeListPage'
import UsersPage from './pages/UsersPage'

// 차트 라이브러리(recharts)가 커서 대시보드를 열 때만 내려받는다.
const StatsPage = lazy(() => import('./pages/StatsPage'))

type Auth =
  | { status: 'checking' }
  | { status: 'anon' }
  | { status: 'error' }
  | { status: 'authed'; who: AdminIdentity }

type Page = 'courses' | 'notices' | 'dashboard' | 'course-stats' | 'users' | 'logs'

/** 사이드바 메뉴. 그룹 제목 아래 항목이 나열된다. */
const MENU: { group: string; items: { key: Page; label: string }[] }[] = [
  {
    // 지표 쪽은 전부 조회 전용이다. 로그는 원본 행을 보는 화면이라 여기 둔다.
    // 대시보드는 그래프, 나머지는 표. 코스·회원은 목록형 자료라 따로 뺐다.
    group: '지표',
    items: [
      { key: 'dashboard', label: '대시보드' },
      { key: 'course-stats', label: '코스' },
      { key: 'users', label: '회원' },
      { key: 'logs', label: '로그' },
    ],
  },
  {
    group: '데이터 편집',
    items: [
      { key: 'courses', label: '코스' },
      { key: 'notices', label: '공지사항' },
    ],
  },
]

// 페이지가 몇 개 안 되어 라우터 없이 좌측 사이드바(state 하나)로 가른다.
// 등록/수정은 목록 위 모달로 처리한다.
export default function App() {
  const [auth, setAuth] = useState<Auth>({ status: 'checking' })
  const [page, setPage] = useState<Page>('dashboard')

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
        <span className="muted" style={{ marginLeft: 'auto' }}>
          {auth.who.display_name ?? auth.who.username}
        </span>
        <button className="secondary small" onClick={signOut}>
          로그아웃
        </button>
      </header>
      <div className="with-sidebar">
        <aside className="sidebar">
          {MENU.map((section) => (
            <div key={section.group} className="sidebar-group">
              <div className="sidebar-title">{section.group}</div>
              {section.items.map((item) => (
                <button
                  key={item.key}
                  className={page === item.key ? 'active' : undefined}
                  onClick={() => setPage(item.key)}
                >
                  {item.label}
                </button>
              ))}
            </div>
          ))}
        </aside>
        <main>
          {page === 'courses' && (
            <CourseListPage onUnauthorized={() => setAuth({ status: 'anon' })} />
          )}
          {page === 'notices' && (
            <NoticeListPage onUnauthorized={() => setAuth({ status: 'anon' })} />
          )}
          {page === 'dashboard' && (
            <Suspense fallback={<p className="muted">불러오는 중…</p>}>
              <StatsPage onUnauthorized={() => setAuth({ status: 'anon' })} />
            </Suspense>
          )}
          {page === 'course-stats' && (
            <CourseStatsPage onUnauthorized={() => setAuth({ status: 'anon' })} />
          )}
          {page === 'users' && (
            <UsersPage onUnauthorized={() => setAuth({ status: 'anon' })} />
          )}
          {page === 'logs' && (
            <LogsPage onUnauthorized={() => setAuth({ status: 'anon' })} />
          )}
        </main>
      </div>
    </>
  )
}

