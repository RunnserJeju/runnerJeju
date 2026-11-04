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
import { ImageSection, imageChanged, NO_IMAGE_CHANGE, type ImageChange } from '../components/ImageSections'
import { BANNER_SPEC, validateBannerImage } from '../components/imageSpec'
import Modal from '../components/Modal'
import NoticeForm, {
  validateNotice,
  valuesFromNotice,
  type NoticeFormValues,
} from '../components/NoticeForm'
import SaveFooter from '../components/SaveFooter'
import { runSteps, snapshot, type SaveStep } from '../utils/saveSteps'

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
  /** 서버에 저장된 내용의 스냅샷. values와 다르면 '공지 내용 변경'이다. */
  const [savedKey, setSavedKey] = useState('')
  const [banner, setBanner] = useState<ImageChange>(NO_IMAGE_CHANGE)
  const [loadError, setLoadError] = useState<string | null>(null)
  const [message, setMessage] = useState<string | null>(initialMessage ?? null)
  const [error, setError] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)
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
        const loaded = valuesFromNotice(found)
        setNotice(found)
        setValues(loaded)
        setSavedKey(snapshot(loaded))
      })
      .catch((err: unknown) =>
        setLoadError(err instanceof ApiError ? err.message : '공지를 불러오지 못했어요.'),
      )
  }, [noticeId])

  const contentDirty = values != null && snapshot(values) !== savedKey
  const bannerDirty = imageChanged(banner)
  const dirty = [contentDirty && '공지 내용', bannerDirty && '배너 이미지'].filter(
    (label): label is string => Boolean(label),
  )

  const save = async () => {
    if (!values || dirty.length === 0) return
    setError(null)
    setMessage(null)

    let body: ReturnType<typeof validateNotice> | null = null
    if (contentDirty) {
      body = validateNotice(values)
      if (!body.ok) {
        setError(body.message)
        return
      }
    }

    const steps: SaveStep[] = []
    if (body?.ok) {
      const data = body.data
      steps.push({
        label: '공지 내용',
        run: async () => {
          const saved = await updateNotice(noticeId, data)
          const next = valuesFromNotice(saved)
          setNotice(saved)
          setValues(next)
          setSavedKey(snapshot(next))
        },
      })
    }
    if (bannerDirty) {
      const { file } = banner
      steps.push({
        label: '배너 이미지',
        run: async () => {
          setNotice(file ? await setNoticeImage(noticeId, file) : await deleteNoticeImage(noticeId))
          setBanner(NO_IMAGE_CHANGE)
        },
      })
    }

    setSaving(true)
    const failure = await runSteps(steps)
    setSaving(false)
    onChanged()
    if (failure) {
      setError(failure)
      return
    }
    setMessage('저장했어요.')
    bodyRef.current?.scrollTo({ top: 0 })
  }

  return (
    <Modal
      title={notice ? `공지 수정 — ${notice.title}` : '공지 수정'}
      onClose={onClose}
      closable={!saving}
      bodyRef={bodyRef}
      footer={
        notice && values ? (
          <SaveFooter dirty={dirty} saving={saving} error={error} onSave={save} />
        ) : undefined
      }
    >
      {loadError && <div className="error">{loadError}</div>}
      {!loadError && (!notice || !values) && <p className="muted">불러오는 중…</p>}
      {notice && values && (
        <>
          {message && <div className="notice" style={{ marginTop: 0 }}>{message}</div>}

          <div className="card">
            <h3 style={{ marginTop: 0 }}>내용</h3>
            <NoticeForm
              values={values}
              onChange={(next) => {
                setValues(next)
                setMessage(null)
              }}
            />
          </div>
          <ImageSection
            title="배너 이미지"
            description={`올리면 앱 홈 상단 배너에 실리고, 누르면 이 공지가 열려요. ${BANNER_SPEC.hint}.`}
            imageClass="thumb banner"
            currentUrl={notice.image_url}
            value={banner}
            onChange={setBanner}
            validate={validateBannerImage}
          />
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
