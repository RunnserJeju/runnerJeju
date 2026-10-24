import { useState } from 'react'

import { ApiError } from '../api'

/** 서버 admin/images.MAX_EXTRA_IMAGES와 같다. */
export const MAX_EXTRA_IMAGES = 10

/**
 * 썸네일 한 장 등록·교체·삭제 카드. 코스·협력업체 수정 모달이 같이 쓴다.
 * T는 저장 응답(갱신된 코스/업체) — onSaved로 호출부 상태를 갈아끼운다.
 */
export function ThumbnailSection<T>({
  thumbnailUrl,
  upload,
  remove,
  onSaved,
  hint,
}: {
  thumbnailUrl: string | null
  upload: (file: File) => Promise<T>
  remove: () => Promise<T>
  onSaved: (saved: T, message: string) => void
  /** 규격 안내 한 줄(선택). */
  hint?: string
}) {
  const [file, setFile] = useState<File | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)

  const run = async (action: () => Promise<T>, done: string, failure: string) => {
    setError(null)
    setSaving(true)
    try {
      onSaved(await action(), done)
      return true
    } catch (err) {
      setError(err instanceof ApiError ? err.message : failure)
      return false
    } finally {
      setSaving(false)
    }
  }

  const doUpload = async () => {
    if (!file) {
      setError('이미지 파일을 선택해 주세요.')
      return
    }
    if (await run(() => upload(file), '썸네일을 저장했어요.', '썸네일 업로드에 실패했어요.')) {
      setFile(null)
    }
  }

  return (
    <div className="card">
      <h3 style={{ marginTop: 0 }}>썸네일</h3>
      {hint && <p className="muted">{hint}</p>}
      {thumbnailUrl ? (
        <img className="thumb large" src={thumbnailUrl} alt="현재 썸네일" />
      ) : (
        <p className="muted">등록된 썸네일이 없어요.</p>
      )}
      <div className="field" style={{ marginTop: 12 }}>
        <input
          type="file"
          accept="image/jpeg,image/png,image/webp"
          onChange={(event) => setFile(event.target.files?.[0] ?? null)}
        />
      </div>
      {error && <div className="error">{error}</div>}
      <div className="submit-row">
        <button onClick={doUpload} disabled={saving || !file}>
          {saving ? '처리 중…' : thumbnailUrl ? '썸네일 교체' : '썸네일 등록'}
        </button>
        {thumbnailUrl && (
          <button
            className="danger"
            onClick={() => run(remove, '썸네일을 지웠어요.', '썸네일 삭제에 실패했어요.')}
            disabled={saving}
          >
            썸네일 삭제
          </button>
        )}
      </div>
    </div>
  )
}

/** 썸네일 말고 더 보여 줄 이미지. 한 장씩 붙이고, 순서를 바꾸거나 뺀다. */
export function ImagesSection<T>({
  urls,
  add,
  set,
  onSaved,
  description,
}: {
  urls: string[]
  add: (file: File) => Promise<T>
  /** 순서 바꾸기·빼기. 지금 있는 URL로만 이뤄진 목록을 통째로 보낸다. */
  set: (urls: string[]) => Promise<T>
  onSaved: (saved: T, message: string) => void
  /** 앱 어디에 보이는지 안내. */
  description: string
}) {
  const [file, setFile] = useState<File | null>(null)
  /** 파일 입력을 비우려고 업로드할 때마다 바꾼다. */
  const [inputKey, setInputKey] = useState(0)
  const [error, setError] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)

  const run = async (action: () => Promise<T>, done: string, failure: string) => {
    setError(null)
    setSaving(true)
    try {
      onSaved(await action(), done)
      return true
    } catch (err) {
      setError(err instanceof ApiError ? err.message : failure)
      return false
    } finally {
      setSaving(false)
    }
  }

  const upload = async () => {
    if (!file) return
    const ok = await run(() => add(file), '이미지를 추가했어요.', '이미지 업로드에 실패했어요.')
    if (ok) {
      setFile(null)
      setInputKey((key) => key + 1)
    }
  }

  const move = (index: number, delta: number) => {
    const next = [...urls]
    const [moved] = next.splice(index, 1)
    next.splice(index + delta, 0, moved)
    run(() => set(next), '순서를 바꿨어요.', '순서 변경에 실패했어요.')
  }

  const remove = (url: string) =>
    run(
      () => set(urls.filter((u) => u !== url)),
      '이미지를 뺐어요.',
      '이미지 삭제에 실패했어요.',
    )

  const full = urls.length >= MAX_EXTRA_IMAGES

  return (
    <div className="card">
      <h3 style={{ marginTop: 0 }}>추가 이미지</h3>
      <p className="muted">
        {description} 위에서부터 순서대로, 최대 {MAX_EXTRA_IMAGES}장.
      </p>
      {urls.length === 0 && <p className="muted">등록된 이미지가 없어요.</p>}
      {urls.map((url, index) => (
        <div key={url} className="facility picked-row">
          <div className="row" style={{ alignItems: 'center' }}>
            <img className="thumb" src={url} alt={`추가 이미지 ${index + 1}`} />
            <div className="picked-name muted">{index + 1}번째</div>
            <button
              type="button"
              className="secondary small"
              onClick={() => move(index, -1)}
              disabled={saving || index === 0}
            >
              ↑
            </button>
            <button
              type="button"
              className="secondary small"
              onClick={() => move(index, 1)}
              disabled={saving || index === urls.length - 1}
            >
              ↓
            </button>
            <button
              type="button"
              className="danger small"
              onClick={() => remove(url)}
              disabled={saving}
            >
              삭제
            </button>
          </div>
        </div>
      ))}
      <div className="field" style={{ marginTop: 12 }}>
        <input
          key={inputKey}
          type="file"
          accept="image/jpeg,image/png,image/webp"
          disabled={full}
          onChange={(event) => setFile(event.target.files?.[0] ?? null)}
        />
      </div>
      {error && <div className="error">{error}</div>}
      <div className="submit-row">
        <button onClick={upload} disabled={saving || !file || full}>
          {saving ? '처리 중…' : full ? `${MAX_EXTRA_IMAGES}장까지예요` : '이미지 추가'}
        </button>
      </div>
    </div>
  )
}
