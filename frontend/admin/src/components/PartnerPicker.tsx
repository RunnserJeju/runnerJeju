import { useEffect, useState } from 'react'

import { ApiError, listPartners, type Partner } from '../api'
import SearchSelect from './SearchSelect'

interface Props {
  selectedIds: string[]
  onChange: (ids: string[]) => void
  /** 기본은 코스 연결용 문구. 쿠폰 사용 업체처럼 다른 자리에서 쓰면 바꾼다. */
  label?: string
  hint?: string
}

/** 등록된 협력업체 고르기. 업체 등록·수정은 "협력업체" 메뉴에서 하고, 여기서는
 * 골라서 순서만 정한다(코스에서는 위에 있을수록 앱에서 먼저 보인다). */
export default function PartnerPicker({
  selectedIds,
  onChange,
  label = '협력업체',
  hint = '"협력업체" 메뉴에서 먼저 등록한 뒤 여기서 골라요. 위에 있을수록 앱에서 먼저 보여요',
}: Props) {
  const [partners, setPartners] = useState<Partner[] | null>(null)
  const [error, setError] = useState<string | null>(null)

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
        {label}
        <span className="hint">{hint}</span>
      </label>
      {error && <div className="error">{error}</div>}
      {selectedIds.map((id, index) => {
        const partner = byId.get(id)
        return (
          <div key={id} className="facility picked-row">
            <div className="row">
              <div className="picked-name">
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
                제외
              </button>
            </div>
          </div>
        )
      })}
      {partners && (
        <SearchSelect
          options={available.map((partner) => ({
            id: partner.id,
            label: partner.name,
            sub: partner.address,
          }))}
          onSelect={(id) => onChange([...selectedIds, id])}
          emptyText="추가할 업체가 없어요"
        />
      )}
    </div>
  )
}
