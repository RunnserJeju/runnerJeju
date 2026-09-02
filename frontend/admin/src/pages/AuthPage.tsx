import { useState, type FormEvent } from 'react'

import { ApiError, getApiKey, saveApiKey, verifyApiKey } from '../api'

/** 최초 진입 화면. 키를 서버로 검증한 뒤에만 저장하고 대시보드로 넘어간다. */
export default function AuthPage({ onAuthed }: { onAuthed: () => void }) {
  const [key, setKey] = useState(getApiKey)
  const [error, setError] = useState<string | null>(null)
  const [checking, setChecking] = useState(false)

  const submit = async (event: FormEvent) => {
    event.preventDefault()
    const trimmed = key.trim()
    if (!trimmed) {
      setError('API 키를 입력해 주세요.')
      return
    }
    setError(null)
    setChecking(true)
    try {
      await verifyApiKey(trimmed)
      saveApiKey(trimmed)
      onAuthed()
    } catch (err) {
      setError(err instanceof ApiError ? err.message : '서버에 연결하지 못했어요.')
    } finally {
      setChecking(false)
    }
  }

  return (
    <div className="auth-page">
      <form className="auth-card" onSubmit={submit}>
        <h1>Runners Jeju Dashboard</h1>
        <p className="muted">관리자 API 키를 입력해 주세요.</p>
        <input
          type="password"
          placeholder="관리자 API 키"
          value={key}
          autoFocus
          onChange={(event) => setKey(event.target.value)}
        />
        {error && <div className="error" style={{ margin: 0 }}>{error}</div>}
        <button type="submit" disabled={checking}>
          {checking ? '확인 중…' : '접속'}
        </button>
      </form>
    </div>
  )
}
