import { useState, type FormEvent } from 'react'

import { ApiError, login, type AdminIdentity } from '../api'

/** 최초 진입 화면. 아이디/비밀번호로 로그인하면 서버가 세션 쿠키를 내려준다. */
export default function AuthPage({
  onAuthed,
}: {
  onAuthed: (who: AdminIdentity) => void
}) {
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [submitting, setSubmitting] = useState(false)

  const submit = async (event: FormEvent) => {
    event.preventDefault()
    if (!username.trim() || !password) {
      setError('아이디와 비밀번호를 입력해 주세요.')
      return
    }
    setError(null)
    setSubmitting(true)
    try {
      const who = await login(username.trim(), password)
      onAuthed(who)
    } catch (err) {
      setError(err instanceof ApiError ? err.message : '서버에 연결하지 못했어요.')
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <div className="auth-page">
      <form className="auth-card" onSubmit={submit}>
        <h1>Runners Jeju Dashboard</h1>
        <p className="muted">운영자 계정으로 로그인해 주세요.</p>
        <input
          type="text"
          placeholder="아이디"
          value={username}
          autoFocus
          autoComplete="username"
          onChange={(event) => setUsername(event.target.value)}
        />
        <input
          type="password"
          placeholder="비밀번호"
          value={password}
          autoComplete="current-password"
          onChange={(event) => setPassword(event.target.value)}
        />
        {error && <div className="error" style={{ margin: 0 }}>{error}</div>}
        <button type="submit" disabled={submitting}>
          {submitting ? '로그인 중…' : '로그인'}
        </button>
      </form>
    </div>
  )
}
