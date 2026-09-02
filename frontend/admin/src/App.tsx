import { useState } from 'react'

import { getApiKey } from './api'
import AuthPage from './pages/AuthPage'
import CourseListPage from './pages/CourseListPage'

// 페이지는 코스 목록 하나뿐이라 라우터 없이 인증 여부로만 화면을 가른다.
// 등록/수정은 목록 위 모달로 처리한다.
export default function App() {
  const [authed, setAuthed] = useState(() => getApiKey() !== '')

  if (!authed) {
    return <AuthPage onAuthed={() => setAuthed(true)} />
  }

  return (
    <>
      <header className="topbar">
        <h1>Runners Jeju Dashboard</h1>
        <button
          className="secondary small"
          style={{ marginLeft: 'auto' }}
          onClick={() => setAuthed(false)}
        >
          API 키 변경
        </button>
      </header>
      <main>
        <CourseListPage onUnauthorized={() => setAuthed(false)} />
      </main>
    </>
  )
}
