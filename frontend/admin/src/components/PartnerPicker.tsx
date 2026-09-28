import { useEffect, useState } from 'react'

import { ApiError, listPartners, type Partner } from '../api'

interface Props {
  selectedIds: string[]
  onChange: (ids: string[]) => void
}

/** 코스에 연결할 협력업체 고르기. 업체 등록·수정은 "협력업체" 메뉴에서 하고, 여기서는
 * 등록된 업체를 골라 순서만 정한다(위에 있을수록 앱에서 먼저 보인다). */
export default function PartnerPicker({ selectedIds, onChange }: Props) {
  const [partners, setPartners] = useState<Partner[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [pending, setPending] = useState('')

  useEffect(() => {
    listPartners()
      .then(setPartners)
      .catch((err: unknown) =>
        setError(err instanceof ApiError ? err.message : '협력업체 목록을 불러오지 못했어요.'),
      )
  }, [])

  const byId = new Map((partners ?? []).map((partner) => [partner.id, partner]))
  const available = (partners ?? []).filter((partner) => !selectedIds.includes(partner.id))

  const move = (index: number, delta: number) => {
    const next = [...selectedIds]
    const [moved] = next.splice(index, 1)
    next.splice(index + delta, 0, moved)
    onChange(next)
  }

  return (
    <div className="field">
      <label>
        협력업체
        <span className="hint">"협력업체" 메뉴에서 먼저 등록한 뒤 여기서 골라요. 위에 있을수록 앱에서 먼저 보여요</span>
      </label>
      {error && <div className="error">{error}</div>}
      {selectedIds.map((id, index) => {
        const partner = byId.get(id)
        return (
          <div key={id} className="facility">
            <div className="row">
              <div className="field" style={{ flex: 2 }}>
                <strong>{partner?.name ?? (partners ? '(삭제된 업체)' : '불러오는 중…')}</strong>
                {partner?.address && <span className="muted"> · {partner.address}</span>}
              </div>
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
                disabled={index === selectedIds.length - 1}
              >
                ↓
              </button>
              <button
                type="button"
                className="danger small"
                onClick={() => onChange(selectedIds.filter((selected) => selected !== id))}
              >
                빼기
              </button>
            </div>
          </div>
        )
      })}
      {partners && (
        <div className="row row-actions">
          <div className="field" style={{ flex: 2 }}>
            <select value={pending} onChange={(event) => setPending(event.target.value)}>
              <option value="">
                {available.length === 0 ? '추가할 업체가 없어요' : '업체 선택'}
              </option>
              {available.map((partner) => (
                <option key={partner.id} value={partner.id}>
                  {partner.name}
                  {partner.address ? ` (${partner.address})` : ''}
                </option>
              ))}
            </select>
          </div>
          <button
            type="button"
            className="secondary small"
            disabled={!pending}
            onClick={() => {
              onChange([...selectedIds, pending])
              setPending('')
            }}
          >
            + 연결
          </button>
        </div>
      )}
    </div>
  )
}
