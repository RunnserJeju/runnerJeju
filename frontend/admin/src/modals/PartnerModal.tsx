import { useState } from 'react'

import {
  addPartnerImage,
  ApiError,
  createPartner,
  deletePartner,
  deletePartnerThumbnail,
  setPartnerImages,
  setPartnerThumbnail,
  updatePartner,
  type Partner,
} from '../api'
import {
  ImageSection,
  ImagesSection,
  imageChanged,
  imagesChanged,
  imagesFrom,
  NO_IMAGE_CHANGE,
  type ImageChange,
  type ImagesChange,
} from '../components/ImageSections'
import Modal from '../components/Modal'
import PartnerForm, {
  emptyPartnerValues,
  validatePartner,
  valuesFromPartner,
} from '../components/PartnerForm'
import SaveFooter from '../components/SaveFooter'
import { runSteps, snapshot, type SaveStep } from '../utils/saveSteps'

interface Props {
  /** 없으면 새 업체 등록, 있으면 그 업체 수정. */
  partner: Partner | null
  onClose: () => void
  /** 저장/삭제가 반영됐을 때 — 목록 새로고침용. */
  onChanged: () => void
}

/** 협력업체 등록·수정 모달. 폼 하나로 등록·수정을 다 하고, 썸네일·추가 이미지는 등록된 업체에만
 * 붙는다. 저장은 우측 아래 버튼 하나가 맡고, 바뀐 것만 서버에 보낸다. */
export default function PartnerModal({ partner: initial, onClose, onChanged }: Props) {
  const [partner, setPartner] = useState(initial)
  const [values, setValues] = useState(() =>
    initial ? valuesFromPartner(initial) : emptyPartnerValues(),
  )
  const [savedKey, setSavedKey] = useState(() =>
    snapshot(initial ? valuesFromPartner(initial) : emptyPartnerValues()),
  )
  const [thumb, setThumb] = useState<ImageChange>(NO_IMAGE_CHANGE)
  const [images, setImages] = useState<ImagesChange>(() => imagesFrom(initial?.image_urls ?? []))
  const [error, setError] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)
  const [confirmingDelete, setConfirmingDelete] = useState(false)

  const metaDirty = snapshot(values) !== savedKey
  const thumbDirty = imageChanged(thumb)
  const imagesDirty = partner != null && imagesChanged(partner.image_urls, images)
  const dirty = [
    metaDirty && '업체 정보',
    thumbDirty && '썸네일',
    imagesDirty && '추가 이미지',
  ].filter((label): label is string => Boolean(label))

  const save = async () => {
    setError(null)
    setNotice(null)
    let payload: ReturnType<typeof validatePartner> | null = null
    if (metaDirty || !partner) {
      payload = validatePartner(values)
      if (!payload.ok) {
        setError(payload.message)
        return
      }
    }

    const steps: SaveStep[] = []
    if (payload?.ok) {
      const body = payload.data
      steps.push({
        label: partner ? '업체 정보' : '등록',
        run: async () => {
          if (partner) {
            const saved = await updatePartner(partner.id, body)
            setPartner(saved)
            const next = valuesFromPartner(saved)
            setValues(next)
            setSavedKey(snapshot(next))
          } else {
            await createPartner(body)
          }
        },
      })
    }
    if (partner && thumbDirty) {
      const { file } = thumb
      steps.push({
        label: '썸네일',
        run: async () => {
          setPartner(
            file ? await setPartnerThumbnail(partner.id, file) : await deletePartnerThumbnail(partner.id),
          )
          setThumb(NO_IMAGE_CHANGE)
        },
      })
    }
    if (partner && imagesDirty) {
      const keep = images.urls
      if (imagesChanged(partner.image_urls, { urls: keep, added: [] })) {
        steps.push({
          label: '추가 이미지 순서·삭제',
          run: async () => {
            const saved = await setPartnerImages(partner.id, keep)
            setPartner(saved)
            setImages((prev) => ({ ...prev, urls: saved.image_urls }))
          },
        })
      }
      for (const file of images.added) {
        steps.push({
          label: `추가 이미지(${file.name})`,
          run: async () => {
            const saved = await addPartnerImage(partner.id, file)
            setPartner(saved)
            setImages((prev) => ({
              urls: saved.image_urls,
              added: prev.added.filter((f) => f !== file),
            }))
          },
        })
      }
    }

    setSaving(true)
    const failure = await runSteps(steps)
    setSaving(false)
    onChanged()
    if (failure) {
      setError(failure)
      return
    }
    // 예전 '저장'처럼 다 되면 창을 닫는다.
    onClose()
  }

  const remove = async () => {
    if (!partner) return
    setError(null)
    setSaving(true)
    try {
      await deletePartner(partner.id)
      onChanged()
      onClose()
    } catch (err) {
      setError(err instanceof ApiError ? err.message : '삭제에 실패했어요.')
      setSaving(false)
    }
  }

  return (
    <Modal
      title={partner ? `협력업체 수정 — ${partner.name}` : '새 협력업체 등록'}
      onClose={onClose}
      closable={!saving}
      footer={
        <SaveFooter
          dirty={dirty}
          saving={saving}
          error={error}
          onSave={save}
          label={partner ? '전체 저장' : '등록'}
          alwaysEnabled={!partner}
        />
      }
    >
      {notice && <div className="notice" style={{ marginTop: 0 }}>{notice}</div>}
      <div className="card">
        {partner && partner.course_count > 0 && (
          <p className="muted" style={{ marginTop: 0 }}>
            코스 {partner.course_count}개에 연결돼 있어요. 고치면 그 코스들에 바로 반영돼요.
          </p>
        )}
        <PartnerForm values={values} onChange={setValues} />
      </div>

      {partner && (
        <>
          <ImageSection
            title="썸네일"
            description="앱 협력업체 목록 카드에 정사각형으로 보여요. 없으면 업종 아이콘이 나와요."
            currentUrl={partner.thumbnail_url}
            value={thumb}
            onChange={setThumb}
          />
          <ImagesSection
            description="앱 업체 상세의 길찾기 버튼 아래에 옆으로 미는 사진 띠예요. 사진은 원본 비율 그대로 잘리지 않고 나와요."
            value={images}
            onChange={setImages}
          />
        </>
      )}

      {partner && (
        <div className="card">
          <h3 style={{ marginTop: 0 }}>삭제</h3>
          {confirmingDelete ? (
            <div className="confirm">
              <strong>이 협력업체를 삭제할까요?</strong>{' '}
              {partner.course_count > 0
                ? `연결된 코스 ${partner.course_count}개에서도 빠지고 되돌릴 수 없어요.`
                : '되돌릴 수 없어요.'}
              <div className="actions">
                <button className="danger" onClick={remove} disabled={saving}>
                  {saving ? '삭제 중…' : '삭제'}
                </button>
                <button
                  className="secondary"
                  onClick={() => setConfirmingDelete(false)}
                  disabled={saving}
                >
                  취소
                </button>
              </div>
            </div>
          ) : (
            <button className="danger" onClick={() => setConfirmingDelete(true)}>
              협력업체 삭제
            </button>
          )}
        </div>
      )}
    </Modal>
  )
}
