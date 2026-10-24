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
import { ImagesSection, ThumbnailSection } from '../components/ImageSections'
import Modal from '../components/Modal'
import PartnerForm, {
  emptyPartnerValues,
  validatePartner,
  valuesFromPartner,
} from '../components/PartnerForm'

interface Props {
  /** 없으면 새 업체 등록, 있으면 그 업체 수정. */
  partner: Partner | null
  onClose: () => void
  /** 저장/삭제가 반영됐을 때 — 목록 새로고침용. */
  onChanged: () => void
}

/** 협력업체 등록·수정 모달. 폼 하나로 등록·수정을 다 하고(공지처럼 모달을 나누지 않는다),
 * 썸네일·추가 이미지는 등록된 업체에만 붙는다(코스 수정 모달과 같은 카드). */
export default function PartnerModal({ partner: initial, onClose, onChanged }: Props) {
  // 이미지 저장 응답으로 갈아끼운다. 폼 입력(values)은 건드리지 않는다.
  const [partner, setPartner] = useState(initial)
  const [values, setValues] = useState(() =>
    initial ? valuesFromPartner(initial) : emptyPartnerValues(),
  )
  const [error, setError] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)
  const [confirmingDelete, setConfirmingDelete] = useState(false)

  const applyMedia = (saved: Partner, message: string) => {
    setPartner(saved)
    setNotice(message)
    onChanged()
  }

  const save = async () => {
    setError(null)
    const validated = validatePartner(values)
    if (!validated.ok) {
      setError(validated.message)
      return
    }
    setSaving(true)
    try {
      if (partner) await updatePartner(partner.id, validated.data)
      else await createPartner(validated.data)
      onChanged()
      onClose()
    } catch (err) {
      setError(err instanceof ApiError ? err.message : '저장에 실패했어요.')
      setSaving(false)
    }
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
    >
      {notice && <div className="notice" style={{ marginTop: 0 }}>{notice}</div>}
      <div className="card">
        {partner && partner.course_count > 0 && (
          <p className="muted" style={{ marginTop: 0 }}>
            코스 {partner.course_count}개에 연결돼 있어요. 고치면 그 코스들에 바로 반영돼요.
          </p>
        )}
        <PartnerForm values={values} onChange={setValues} />
        {error && <div className="error">{error}</div>}
        <div className="submit-row">
          <button onClick={save} disabled={saving}>
            {saving ? '저장 중…' : partner ? '저장' : '등록'}
          </button>
        </div>
      </div>

      {partner && (
        <>
          <ThumbnailSection
            thumbnailUrl={partner.thumbnail_url}
            hint="앱 협력업체 목록 카드에 정사각형으로 보여요. 없으면 업종 아이콘이 나와요."
            upload={(file) => setPartnerThumbnail(partner.id, file)}
            remove={() => deletePartnerThumbnail(partner.id)}
            onSaved={applyMedia}
          />
          <ImagesSection
            urls={partner.image_urls}
            description="앱 업체 상세의 길찾기 버튼 아래에 옆으로 넘기며 보는 갤러리예요."
            add={(file) => addPartnerImage(partner.id, file)}
            set={(urls) => setPartnerImages(partner.id, urls)}
            onSaved={applyMedia}
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
