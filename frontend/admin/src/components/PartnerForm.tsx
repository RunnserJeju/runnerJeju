import { useState } from 'react'

import { ApiError, geocode, type GeocodeResult, type Partner, type PartnerPayload } from '../api'

/** 입력 중 값. 좌표도 직접 입력할 수 있어 문자열로 들고, 제출 시 validatePartner가 바꾼다. */
export interface PartnerFormValues {
  name: string
  address: string
  lat: string
  lng: string
  comment: string
  instagram: string
  benefit: string
  /** detail(JSONB) 원문. 형태가 정해지지 않아 JSON 객체를 그대로 편집한다. */
  detail: string
}

export function emptyPartnerValues(): PartnerFormValues {
  return {
    name: '',
    address: '',
    lat: '',
    lng: '',
    comment: '',
    instagram: '',
    benefit: '',
    detail: '{}',
  }
}

export function valuesFromPartner(partner: Partner): PartnerFormValues {
  return {
    name: partner.name,
    address: partner.address ?? '',
    lat: String(partner.lat),
    lng: String(partner.lng),
    comment: partner.comment ?? '',
    instagram: partner.instagram ?? '',
    benefit: partner.benefit ?? '',
    detail: JSON.stringify(partner.detail ?? {}, null, 2),
  }
}

/** 서버 PartnerPayload와 같은 규칙: 이름·좌표 필수, 나머지 선택. */
export function validatePartner(
  values: PartnerFormValues,
): { ok: true; data: PartnerPayload } | { ok: false; message: string } {
  const name = values.name.trim()
  if (!name) return { ok: false, message: '이름을 입력해 주세요.' }

  const lat = Number(values.lat)
  const lng = Number(values.lng)
  if (!values.lat.trim() || !values.lng.trim() || !Number.isFinite(lat) || !Number.isFinite(lng)) {
    return { ok: false, message: '위도/경도를 입력하거나 주소로 "좌표 확인"을 눌러 주세요.' }
  }
  if (Math.abs(lat) > 90 || Math.abs(lng) > 180) {
    return { ok: false, message: '좌표 범위가 올바르지 않아요. 위도와 경도가 바뀌지 않았는지 확인해 주세요.' }
  }

  let detail: Record<string, unknown>
  try {
    const parsed: unknown = JSON.parse(values.detail.trim() || '{}')
    if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) throw new Error()
    detail = parsed as Record<string, unknown>
  } catch {
    return { ok: false, message: 'detail은 JSON 객체여야 해요. 예: {"hours": "09:00-18:00"}' }
  }

  const optional = (value: string) => value.trim() || null
  return {
    ok: true,
    data: {
      name,
      address: optional(values.address),
      lat,
      lng,
      comment: optional(values.comment),
      instagram: optional(values.instagram),
      benefit: optional(values.benefit),
      detail,
    },
  }
}

interface Props {
  values: PartnerFormValues
  onChange: (values: PartnerFormValues) => void
}

export default function PartnerForm({ values, onChange }: Props) {
  const set = <K extends keyof PartnerFormValues>(key: K, value: PartnerFormValues[K]) =>
    onChange({ ...values, [key]: value })

  const [candidates, setCandidates] = useState<GeocodeResult[] | null>(null)
  const [status, setStatus] = useState<string | null>(null)
  const [looking, setLooking] = useState(false)

  // 주차장/화장실(FacilityListEditor)과 같은 카카오 지오코딩. 주소가 선택이라 좌표는
  // 직접 입력해도 된다 — 확인은 좌표를 채워 주는 도우미일 뿐 필수 절차가 아니다.
  const pick = (result: GeocodeResult) => {
    onChange({
      ...values,
      address: result.road_address ?? result.address,
      lat: String(result.lat),
      lng: String(result.lng),
    })
    setCandidates(null)
    setStatus(null)
  }

  const lookup = async () => {
    const address = values.address.trim()
    if (!address) {
      setStatus('주소를 먼저 입력해 주세요.')
      return
    }
    setLooking(true)
    setStatus(null)
    setCandidates(null)
    try {
      const { results } = await geocode(address)
      if (results.length === 0) setStatus('주소를 찾지 못했어요. 주소를 고치거나 좌표를 직접 입력해 주세요.')
      else if (results.length === 1) pick(results[0])
      else setCandidates(results)
    } catch (error) {
      setStatus(error instanceof ApiError ? error.message : '좌표 확인에 실패했어요.')
    } finally {
      setLooking(false)
    }
  }

  return (
    <>
      <div className="field">
        <label htmlFor="partner-name">이름</label>
        <input id="partner-name" value={values.name} onChange={(e) => set('name', e.target.value)} />
      </div>

      <div className="field">
        <label htmlFor="partner-address">
          주소 <span className="hint">선택 — "좌표 확인"으로 위도/경도를 채울 수 있어요</span>
        </label>
        <div className="row row-actions">
          <div className="field" style={{ flex: 2 }}>
            <input
              id="partner-address"
              value={values.address}
              onChange={(e) => set('address', e.target.value)}
            />
          </div>
          <button type="button" className="secondary small" onClick={lookup} disabled={looking}>
            {looking ? '확인 중…' : '좌표 확인'}
          </button>
        </div>
        {status && <div className="coord">{status}</div>}
        {candidates && (
          <div className="candidates">
            <span className="muted">주소 후보를 골라 주세요:</span>
            {candidates.map((candidate, index) => (
              <button
                key={index}
                type="button"
                className="secondary small"
                onClick={() => pick(candidate)}
              >
                {candidate.road_address ?? candidate.address}
                {candidate.road_address && candidate.road_address !== candidate.address && (
                  <span className="muted"> ({candidate.address})</span>
                )}
              </button>
            ))}
          </div>
        )}
      </div>

      <div className="row">
        <div className="field">
          <label htmlFor="partner-lat">위도</label>
          <input
            id="partner-lat"
            type="number"
            step="any"
            placeholder="33.xxxxxx"
            value={values.lat}
            onChange={(e) => set('lat', e.target.value)}
          />
        </div>
        <div className="field">
          <label htmlFor="partner-lng">경도</label>
          <input
            id="partner-lng"
            type="number"
            step="any"
            placeholder="126.xxxxxx"
            value={values.lng}
            onChange={(e) => set('lng', e.target.value)}
          />
        </div>
      </div>

      <div className="field">
        <label htmlFor="partner-benefit">
          혜택 <span className="hint">선택 — 예: 러너 인증 시 아메리카노 10% 할인</span>
        </label>
        <input
          id="partner-benefit"
          value={values.benefit}
          onChange={(e) => set('benefit', e.target.value)}
        />
      </div>

      <div className="field">
        <label htmlFor="partner-instagram">
          인스타그램 <span className="hint">선택 — 계정명이나 URL</span>
        </label>
        <input
          id="partner-instagram"
          value={values.instagram}
          onChange={(e) => set('instagram', e.target.value)}
        />
      </div>

      <div className="field">
        <label htmlFor="partner-comment">
          코멘트 <span className="hint">선택</span>
        </label>
        <textarea
          id="partner-comment"
          value={values.comment}
          onChange={(e) => set('comment', e.target.value)}
        />
      </div>

      <div className="field">
        <label htmlFor="partner-detail">
          detail <span className="hint">선택 — 형태 미정인 부가 정보(JSON 객체)</span>
        </label>
        <textarea
          id="partner-detail"
          value={values.detail}
          onChange={(e) => set('detail', e.target.value)}
          style={{ fontFamily: 'monospace' }}
        />
      </div>
    </>
  )
}
