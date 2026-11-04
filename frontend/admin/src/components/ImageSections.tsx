import { useEffect, useState } from 'react'

/** 서버 admin/images.MAX_EXTRA_IMAGES와 같다. */
export const MAX_EXTRA_IMAGES = 10

const ACCEPT = 'image/jpeg,image/png,image/webp'

/** 이미지 한 장의 저장 전 변경: 새 파일을 골랐거나, 지우기로 했거나. 둘 다 아니면 변경 없음. */
export interface ImageChange {
  file: File | null
  removed: boolean
}
export const NO_IMAGE_CHANGE: ImageChange = { file: null, removed: false }
export const imageChanged = (change: ImageChange): boolean => change.file != null || change.removed

function useObjectUrl(file: File | null): string | null {
  const [url, setUrl] = useState<string | null>(null)
  useEffect(() => {
    if (!file) {
      setUrl(null)
      return
    }
    const next = URL.createObjectURL(file)
    setUrl(next)
    return () => URL.revokeObjectURL(next)
  }, [file])
  return url
}

/**
 * 이미지 한 장(썸네일·배너·도안 등). 파일을 고르거나 지우기만 해 두고, 실제 저장은 편집 창의
 * '전체 저장'이 한다. 고른 파일은 바로 미리 보여준다.
 */
export function ImageSection({
  title,
  description,
  imageClass = 'thumb large',
  currentUrl,
  removable,
  value,
  onChange,
  validate,
}: {
  title: string
  description?: string
  /** 미리보기 이미지의 CSS 클래스(thumb large / thumb banner / thumb large round). */
  imageClass?: string
  /** 서버에 저장된 지금 이미지. */
  currentUrl: string | null
  /** 지울 수 있는지. 기본은 저장된 이미지가 있을 때. */
  removable?: boolean
  value: ImageChange
  onChange: (next: ImageChange) => void
  /** 고르는 순간 규격 검사. 문제가 있으면 문구를 돌려주고 선택은 버린다. */
  validate?: (file: File) => Promise<string | null>
}) {
  const [error, setError] = useState<string | null>(null)
  /** 파일 입력을 비우려고 바꾼다. */
  const [inputKey, setInputKey] = useState(0)
  const previewUrl = useObjectUrl(value.file)
  const canRemove = removable ?? currentUrl != null

  const pick = async (file: File | null) => {
    setError(null)
    if (!file) return
    const problem = validate ? await validate(file) : null
    if (problem) {
      setError(problem)
      setInputKey((key) => key + 1)
      return
    }
    onChange({ file, removed: false })
  }

  const reset = () => {
    setError(null)
    setInputKey((key) => key + 1)
    onChange(NO_IMAGE_CHANGE)
  }

  return (
    <div className="card">
      <h3 style={{ marginTop: 0 }}>{title}</h3>
      {description && <p className="muted">{description}</p>}
      {value.file && previewUrl ? (
        <div className="image-preview">
          <img className={imageClass} src={previewUrl} alt="새로 고른 이미지" />
          <span className="pending-tag">저장하면 교체돼요</span>
        </div>
      ) : value.removed ? (
        <p className="muted">
          삭제 예정이에요 <span className="pending-tag">저장하면 삭제돼요</span>
        </p>
      ) : currentUrl ? (
        <img className={imageClass} src={currentUrl} alt="현재 이미지" />
      ) : (
        <p className="muted">등록된 이미지가 없어요.</p>
      )}
      <div className="field" style={{ marginTop: 12 }}>
        <input
          key={inputKey}
          type="file"
          accept={ACCEPT}
          onChange={(event) => pick(event.target.files?.[0] ?? null)}
        />
      </div>
      {error && <div className="error">{error}</div>}
      <div className="submit-row" style={{ marginTop: 8 }}>
        {value.file && (
          <button type="button" className="secondary small" onClick={reset}>
            선택 취소
          </button>
        )}
        {!value.file && !value.removed && canRemove && (
          <button
            type="button"
            className="danger small"
            onClick={() => onChange({ file: null, removed: true })}
          >
            삭제
          </button>
        )}
        {value.removed && (
          <button type="button" className="secondary small" onClick={reset}>
            삭제 취소
          </button>
        )}
      </div>
    </div>
  )
}

/** 추가 이미지의 저장 전 변경: 남길 기존 이미지(순서 포함)와 새로 올릴 파일들. */
export interface ImagesChange {
  urls: string[]
  added: File[]
}
export const imagesFrom = (urls: string[]): ImagesChange => ({ urls, added: [] })
export const imagesChanged = (current: string[], change: ImagesChange): boolean =>
  change.added.length > 0 ||
  change.urls.length !== current.length ||
  change.urls.some((url, index) => url !== current[index])

function PendingThumb({ file }: { file: File }) {
  const url = useObjectUrl(file)
  return url ? <img className="thumb" src={url} alt="새로 고른 이미지" /> : <div className="thumb placeholder" />
}

/**
 * 썸네일 말고 더 보여 줄 이미지. 여러 장을 골라 대기 목록에 쌓아 두고(추가 버튼), 순서를
 * 바꾸거나 빼는 것도 대기 상태로만 둔다. 실제 저장은 편집 창의 '전체 저장'이 한다.
 */
export function ImagesSection({
  value,
  onChange,
  description,
}: {
  value: ImagesChange
  onChange: (next: ImagesChange) => void
  /** 앱 어디에 보이는지 안내. */
  description: string
}) {
  const [picked, setPicked] = useState<File[]>([])
  const [inputKey, setInputKey] = useState(0)

  const total = value.urls.length + value.added.length
  const room = MAX_EXTRA_IMAGES - total
  const full = room <= 0

  const addPicked = () => {
    if (picked.length === 0 || full) return
    onChange({ ...value, added: [...value.added, ...picked.slice(0, room)] })
    setPicked([])
    setInputKey((key) => key + 1)
  }

  const move = (index: number, delta: number) => {
    const next = [...value.urls]
    const [moved] = next.splice(index, 1)
    next.splice(index + delta, 0, moved)
    onChange({ ...value, urls: next })
  }

  return (
    <div className="card">
      <h3 style={{ marginTop: 0 }}>추가 이미지</h3>
      <p className="muted">
        {description} 위에서부터 순서대로, 최대 {MAX_EXTRA_IMAGES}장. 새로 추가한 이미지는 기존 이미지 뒤에 붙어요.
      </p>
      {total === 0 && <p className="muted">등록된 이미지가 없어요.</p>}
      {value.urls.map((url, index) => (
        <div key={url} className="facility picked-row">
          <div className="row" style={{ alignItems: 'center' }}>
            <img className="thumb" src={url} alt={`추가 이미지 ${index + 1}`} />
            <div className="picked-name muted">{index + 1}번째</div>
            <button
              type="button"
              className="secondary small"
              onClick={() => move(index, -1)}
              disabled={index === 0}
            >
              ↑
            </button>
            <button
              type="button"
              className="secondary small"
              onClick={() => move(index, 1)}
              disabled={index === value.urls.length - 1}
            >
              ↓
            </button>
            <button
              type="button"
              className="danger small"
              onClick={() => onChange({ ...value, urls: value.urls.filter((u) => u !== url) })}
            >
              삭제
            </button>
          </div>
        </div>
      ))}
      {value.added.map((file, index) => (
        <div key={`${file.name}-${file.size}-${index}`} className="facility picked-row">
          <div className="row" style={{ alignItems: 'center' }}>
            <PendingThumb file={file} />
            <div className="picked-name muted">
              {value.urls.length + index + 1}번째 · {file.name}
              <span className="pending-tag">저장하면 추가돼요</span>
            </div>
            <button
              type="button"
              className="secondary small"
              onClick={() => onChange({ ...value, added: value.added.filter((f) => f !== file) })}
            >
              취소
            </button>
          </div>
        </div>
      ))}
      <div className="field" style={{ marginTop: 12 }}>
        <input
          key={inputKey}
          type="file"
          accept={ACCEPT}
          multiple
          disabled={full}
          onChange={(event) => setPicked(Array.from(event.target.files ?? []))}
        />
      </div>
      <div className="submit-row" style={{ marginTop: 8 }}>
        <button type="button" className="secondary" onClick={addPicked} disabled={full || picked.length === 0}>
          {full ? `${MAX_EXTRA_IMAGES}장까지예요` : picked.length > 1 ? `이미지 ${picked.length}장 추가` : '이미지 추가'}
        </button>
      </div>
    </div>
  )
}
