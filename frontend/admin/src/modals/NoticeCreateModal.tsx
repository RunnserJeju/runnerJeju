import { useState } from 'react'

import { ApiError, createNotice, setNoticeImage, type Notice } from '../api'
import Modal from '../components/Modal'
import NoticeForm, { emptyNoticeValues, validateNotice } from '../components/NoticeForm'

interface Props {
  onClose: () => void
  /** 등록 성공. message는 수정 모달로 이어서 보여줄 메시지. */
  onCreated: (notice: Notice, message: string) => void
}

export default function NoticeCreateModal({ onClose, onCreated }: Props) {
  const [values, setValues] = useState(emptyNoticeValues)
  const [imageFile, setImageFile] = useState<File | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [submitting, setSubmitting] = useState(false)

  const submit = async () => {
    setError(null)
    const validated = validateNotice(values)
    if (!validated.ok) {
      setError(validated.message)
      return
    }

    setSubmitting(true)
    try {
      const notice = await createNotice(validated.data)

      // 배너 이미지는 등록과 분리된 전용 엔드포인트다. 등록이 성공한 뒤에 올리고,
      // 실패해도 공지는 이미 만들어졌으므로 수정 모달에서 재시도한다.
      if (imageFile) {
        try {
          await setNoticeImage(notice.id, imageFile)
        } catch (imageError) {
          onCreated(
            notice,
            `공지는 등록됐지만 배너 이미지 업로드에 실패했어요: ${
              imageError instanceof ApiError ? imageError.message : '알 수 없는 오류'
            }`,
          )
          return
        }
      }
      onCreated(notice, '공지를 등록했어요.')
    } catch (err) {
      setError(err instanceof ApiError ? err.message : '등록에 실패했어요.')
      setSubmitting(false)
    }
  }

  return (
    <Modal title="새 공지 등록" onClose={onClose} closable={!submitting}>
      <div className="card">
        <NoticeForm values={values} onChange={setValues} />

        <div className="field">
          <label htmlFor="notice-image-file">
            배너 이미지{' '}
            <span className="hint">선택 — 가로 3:1 권장, jpg/png/webp, 8MB 이하. 올리면 홈 상단 배너에 실린다</span>
          </label>
          <input
            id="notice-image-file"
            type="file"
            accept="image/jpeg,image/png,image/webp"
            onChange={(event) => setImageFile(event.target.files?.[0] ?? null)}
          />
        </div>

        {error && <div className="error">{error}</div>}

        <div className="submit-row">
          <button onClick={submit} disabled={submitting}>
            {submitting ? '등록 중…' : '공지 등록'}
          </button>
        </div>
      </div>
    </Modal>
  )
}
