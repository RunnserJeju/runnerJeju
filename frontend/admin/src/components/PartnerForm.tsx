import { useRef, useState } from 'react'

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
  couponPin: string
  /** detail(JSONB). 운영자가 직접 고치지 않는다 — 업종 선택이 category만 바꾸고
   * 나머지 키는 받은 그대로 돌려보낸다. */
  detail: Record<string, unknown>
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
    couponPin: '',
    detail: {},
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
    couponPin: partner.coupon_pin ?? '',
    detail: partner.detail ?? {},
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

  const couponPin = values.couponPin.trim()
  if (couponPin && !/^\d{4}$/.test(couponPin)) {
    return { ok: false, message: '쿠폰 번호는 숫자 4자리여야 해요.' }
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
      coupon_pin: couponPin || null,
      detail: values.detail,
    },
  }
}

/** 업종. 앱은 detail.category 값으로 마커 색·아이콘을 고른다(Flutter PartnerCategory와
 * 같은 값). 목록에 없는 값은 앱에서 '기타'(other)로 보인다. */
export const PARTNER_CATEGORIES: { value: string; label: string }[] = [
  { value: 'cafe', label: '카페' },
  { value: 'food', label: '음식점' },
  { value: 'stay', label: '숙박' },
  { value: 'store', label: '상점' },
  { value: 'other', label: '기타' },
]

function categoryOf(detail: Record<string, unknown>): string {
  return typeof detail.category === 'string' ? detail.category : ''
}

/** category만 바꾼다(다른 키는 그대로). 빈 값이면 키를 지운다. */
function withCategory(detail: Record<string, unknown>, category: string): Record<string, unknown> {
  const { category: _previous, ...rest } = detail
  return category ? { ...rest, category } : rest
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
  // 좌표 확인 응답을 기다리는 동안 다른 칸을 고쳐도, 응답은 최신 값 위에 반영한다.
  const latest = useRef({ values, onChange })
  latest.current = { values, onChange }

  // 주차장/화장실(FacilityListEditor)과 같은 카카오 지오코딩. 주소가 선택이라 좌표는
  // 직접 입력해도 된다 — 확인은 좌표를 채워 주는 도우미일 뿐 필수 절차가 아니다.
  const pick = (result: GeocodeResult) => {
    latest.current.onChange({
      ...latest.current.values,
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
      <div className="row">
        <div className="field" style={{ flex: 2 }}>
          <label htmlFor="partner-name">이름</label>
          <input
            id="partner-name"
            maxLength={200}
            value={values.name}
            onChange={(e) => set('name', e.target.value)}
          />
        </div>
        <div className="field">
          <label htmlFor="partner-category">
            업종 <span className="hint">앱 마커 색·아이콘</span>
          </label>
          <select
            id="partner-category"
            value={categoryOf(values.detail)}
            onChange={(e) => set('detail', withCategory(values.detail, e.target.value))}
          >
            <option value="">기타</option>
            {PARTNER_CATEGORIES.map((category) => (
              <option key={category.value} value={category.value}>
                {category.label}
              </option>
            ))}
          </select>
        </div>
      </div>

      <div className="field">
        <label htmlFor="partner-address">
          주소 <span className="hint">선택 — "좌표 확인"으로 위도/경도를 채울 수 있어요</span>
        </label>
        <div className="row row-actions">
          <div className="field" style={{ flex: 2 }}>
            <input
              id="partner-address"
              maxLength={300}
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
        <textarea
          id="partner-benefit"
          rows={6}
          maxLength={500}
          value={values.benefit}
          onChange={(e) => set('benefit', e.target.value)}
        />
      </div>

      <div className="field">
        <label htmlFor="partner-coupon-pin">
          쿠폰 번호{' '}
          <span className="hint">
            숫자 4자리, 업체마다 달라야 해요 — 직원이 손님 폰에 입력하면 쿠폰이 사용돼요. 비우면 이
            업체에서 쿠폰을 못 써요
          </span>
        </label>
        <input
          id="partner-coupon-pin"
          inputMode="numeric"
          maxLength={4}
          placeholder="0000"
          value={values.couponPin}
          onChange={(e) => set('couponPin', e.target.value.replace(/\D/g, ''))}
          style={{ width: 120 }}
        />
      </div>

      <div className="field">
        <label htmlFor="partner-instagram">
          인스타그램 <span className="hint">선택 — @를 제외한 아이디</span>
        </label>
        <input
          id="partner-instagram"
          maxLength={200}
          placeholder="runnersjeju"
          value={values.instagram}
          onChange={(e) => set('instagram', e.target.value.replace(/^@+/, ''))}
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
    </>
  )
}
