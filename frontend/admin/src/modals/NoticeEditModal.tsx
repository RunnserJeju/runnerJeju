import { useEffect, useRef, useState } from 'react'

import {
  ApiError,
  deleteNotice,
  deleteNoticeImage,
  listNotices,
  setNoticeImage,
  updateNotice,
  type Notice,
} from '../api'
import Modal from '../components/Modal'
import NoticeForm, {
  validateNotice,
  valuesFromNotice,
  type NoticeFormValues,
} from '../components/NoticeForm'

interface Props {
  noticeId: string
  /** 등록 모달에서 이어서 열릴 때 상단에 보여줄 메시지. */
  initialMessage?: string
  onClose: () => void
  /** 저장/이미지/삭제가 반영될 때마다 — 목록 새로고침용. */
  onChanged: () => void
}

export default function NoticeEditModal({ noticeId, initialMessage, onClose, onChanged }: Props) {
  const [notice, setNotice] = useState<Notice | null>(null)
  const [values, setValues] = useState<NoticeFormValues | null>(null)
  const [loadError, setLoadError] = useState<string | null>(null)
  const [message, setMessage] = useState<string | null>(initialMessage ?? null)
  const bodyRef = useRef<HTMLDivElement | null>(null)

  // 단건 조회 엔드포인트가 없어 목록에서 고른다(공지는 소량).
  useEffect(() => {
    listNotices()
      .then((all) => {
        const found = all.find((n) => n.id === noticeId)
        if (!found) {
          setLoadError('공지를 찾을 수 없어요.')
          return
        }
        setNotice(found)
        setValues(valuesFromNotice(found))
      })
      .catch((err: unknown) =>
        setLoadError(err instanceof ApiError ? err.message : '공지를 불러오지 못했어요.'),
      )
  }, [noticeId])

  // 저장 성공 시 서버 응답으로 화면 상태를 갈아끼운다 — 다음 저장의 기준값이 된다.
  const applySaved = (saved: Notice, text: string) => {
    setNotice(saved)
    setValues(valuesFromNotice(saved))
    setMessage(text)
    onChanged()
    bodyRef.current?.scrollTo({ top: 0 })
  }

  return (
    <Modal
      title={notice ? `공지 수정 — ${notice.title}` : '공지 수정'}
      onClose={onClose}
      bodyRef={bodyRef}
    >
      {loadError && <div className="error">{loadError}</div>}
      {!loadError && (!notice || !values) && <p className="muted">불러오는 중…</p>}
      {notice && values && (
        <>
          {message && <div className="notice" style={{ marginTop: 0 }}>{message}</div>}

          <ContentSection
            noticeId={noticeId}
            values={values}
            onChange={(next) => {
              setValues(next)
              setMessage(null)
            }}
            onSaved={applySaved}
          />
          <ImageSection notice={notice} onSaved={applySaved} />
          <DeleteSection
            notice={notice}
            onDeleted={() => {
              onChanged()
              onClose()
            }}
          />
        </>
      )}
    </Modal>
  )
}

function ContentSection({
  noticeId,
  values,
  onChange,
  onSaved,
}: {
  noticeId: string
  values: NoticeFormValues
  onChange: (values: NoticeFormValues) => void
  onSaved: (notice: Notice, message: string) => void
}) {
  const [error, setError] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)

  const save = async () => {
    setError(null)
    const validated = validateNotice(values)
    if (!validated.ok) {
      setError(validated.message)
      return
    }
    setSaving(true)
    try {
      const saved = await updateNotice(noticeId, validated.data)
      onSaved(saved, '공지를 저장했어요.')
    } catch (err) {
      setError(err instanceof ApiError ? err.message : '저장에 실패했어요.')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="card">
      <h3 style={{ marginTop: 0 }}>내용</h3>
      <NoticeForm values={values} onChange={onChange} />
      {error && <div className="error">{error}</div>}
      <div className="submit-row">
        <button onClick={save} disabled={saving}>
          {saving ? '저장 중…' : '저장'}
        </button>
      </div>
    </div>
  )
}

function ImageSection({
  notice,
  onSaved,
}: {
  notice: Notice
  onSaved: (notice: Notice, message: string) => void
}) {
  const [file, setFile] = useState<File | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)

  const upload = async () => {
    if (!file) {
      setError('이미지 파일을 선택해 주세요.')
      return
    }
    setError(null)
    setSaving(true)
    try {
      const saved = await setNoticeImage(notice.id, file)
      setFile(null)
      onSaved(saved, '배너 이미지를 저장했어요.')
    } catch (err) {
      setError(err instanceof ApiError ? err.message : '이미지 업로드에 실패했어요.')
    } finally {
      setSaving(false)
    }
  }

  const remove = async () => {
    setError(null)
    setSaving(true)
    try {
      const saved = await deleteNoticeImage(notice.id)
      onSaved(saved, '배너 이미지를 지웠어요. 이제 텍스트 공지로만 보여요.')
    } catch (err) {
      setError(err instanceof ApiError ? err.message : '이미지 삭제에 실패했어요.')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="card">
      <h3 style={{ marginTop: 0 }}>배너 이미지</h3>
      <p className="muted">올리면 앱 홈 상단 배너에 실리고, 누르면 이 공지가 열려요. 가로 3:1 권장.</p>
      {notice.image_url ? (
        <img className="thumb banner" src={notice.image_url} alt="현재 배너" />
      ) : (
        <p className="muted">등록된 배너 이미지가 없어요.</p>
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
        <button onClick={upload} disabled={saving || !file}>
          {saving ? '처리 중…' : notice.image_url ? '이미지 교체' : '이미지 등록'}
        </button>
        {notice.image_url && (
          <button className="danger" onClick={remove} disabled={saving}>
            이미지 삭제
          </button>
        )}
      </div>
    </div>
  )
}

function DeleteSection({ notice, onDeleted }: { notice: Notice; onDeleted: () => void }) {
  const [confirming, setConfirming] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [deleting, setDeleting] = useState(false)

  const remove = async () => {
    setError(null)
    setDeleting(true)
    try {
      await deleteNotice(notice.id)
      onDeleted()
    } catch (err) {
      setError(err instanceof ApiError ? err.message : '삭제에 실패했어요.')
      setDeleting(false)
    }
  }

  return (
    <div className="card">
      <h3 style={{ marginTop: 0 }}>삭제</h3>
      {error && <div className="error">{error}</div>}
      {confirming ? (
        <div className="confirm">
          <strong>이 공지를 삭제할까요?</strong> 배너 이미지도 함께 지워지고 되돌릴 수 없어요.
          <div className="actions">
            <button className="danger" onClick={remove} disabled={deleting}>
              {deleting ? '삭제 중…' : '삭제'}
            </button>
            <button className="secondary" onClick={() => setConfirming(false)} disabled={deleting}>
              취소
            </button>
          </div>
        </div>
      ) : (
        <button className="danger" onClick={() => setConfirming(true)}>
          공지 삭제
        </button>
      )}
    </div>
  )
}
