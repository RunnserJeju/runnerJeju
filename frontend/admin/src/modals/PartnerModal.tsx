import { useState } from 'react'

import { ApiError, createPartner, deletePartner, updatePartner, type Partner } from '../api'
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

/** 협력업체 등록·수정 모달. 업체는 이미지 같은 별도 리소스가 없어 폼 하나로 끝난다
 * (공지처럼 등록/수정 모달을 나누지 않는다). */
export default function PartnerModal({ partner, onClose, onChanged }: Props) {
  const [values, setValues] = useState(() =>
    partner ? valuesFromPartner(partner) : emptyPartnerValues(),
  )
  const [error, setError] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)
  const [confirmingDelete, setConfirmingDelete] = useState(false)

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
