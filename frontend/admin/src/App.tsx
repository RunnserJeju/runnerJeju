import { useState } from 'react'
import { HashRouter, NavLink, Navigate, Route, Routes } from 'react-router-dom'

import { getApiKey, saveApiKey } from './api'
import CourseCreatePage from './pages/CourseCreatePage'
import CourseEditPage from './pages/CourseEditPage'
import CourseListPage from './pages/CourseListPage'

// HashRouter: FastAPI StaticFiles에는 SPA fallback이 없어서, 경로를 해시에 실어야
// 새로고침해도 /admin-ui/index.html 하나로 해결된다.
export default function App() {
  const [apiKey, setApiKey] = useState(getApiKey)

  const updateKey = (value: string) => {
    setApiKey(value)
    saveApiKey(value)
  }

  return (
    <HashRouter>
      <header className="topbar">
        <h1>Runners Jeju 운영</h1>
        <nav>
          <NavLink to="/courses" className={({ isActive }) => (isActive ? 'active' : '')}>
            코스 목록
          </NavLink>
          <NavLink to="/courses/new" className={({ isActive }) => (isActive ? 'active' : '')}>
            새 코스 등록
          </NavLink>
        </nav>
        <div className="apikey">
          <label htmlFor="api-key">API 키</label>
          <input
            id="api-key"
            type="password"
            placeholder="관리자 API 키"
            value={apiKey}
            onChange={(event) => updateKey(event.target.value)}
          />
        </div>
      </header>
      <main>
        <Routes>
          <Route path="/" element={<Navigate to="/courses" replace />} />
          <Route path="/courses" element={<CourseListPage />} />
          <Route path="/courses/new" element={<CourseCreatePage />} />
          <Route path="/courses/:id" element={<CourseEditPage />} />
        </Routes>
      </main>
    </HashRouter>
  )
}
