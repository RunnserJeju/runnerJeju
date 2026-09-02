import { useEffect, type ReactNode, type RefObject } from 'react'

interface Props {
  title: ReactNode
  onClose: () => void
  /** 제출 중처럼 닫으면 안 될 때 false — ESC/배경 클릭/X 전부 막힌다. */
  closable?: boolean
  /** 저장 후 스크롤 올리기 등 본문 스크롤 컨테이너가 필요할 때. */
  bodyRef?: RefObject<HTMLDivElement | null>
  children: ReactNode
}

export default function Modal({ title, onClose, closable = true, bodyRef, children }: Props) {
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape' && closable) onClose()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [closable, onClose])

  // 모달이 떠 있는 동안 뒤 페이지 스크롤 잠금.
  useEffect(() => {
    const prev = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    return () => {
      document.body.style.overflow = prev
    }
  }, [])

  return (
    <div
      className="modal-overlay"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget && closable) onClose()
      }}
    >
      <div className="modal">
        <div className="modal-head">
          <h2>{title}</h2>
          <button className="modal-close" onClick={onClose} disabled={!closable} aria-label="닫기">
            ×
          </button>
        </div>
        <div className="modal-body" ref={bodyRef}>
          {children}
        </div>
      </div>
    </div>
  )
}
