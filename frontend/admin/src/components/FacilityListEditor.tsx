import { useRef, useState } from 'react'

import { ApiError, geocode, type GeocodeResult } from '../api'

/** 폼에서 편집 중인 주차장/화장실 한 곳. 좌표는 "확인"을 눌러야 채워진다. */
export interface FacilityDraft {
  name: string
  address: string
  lat: number | null
  lng: number | null
}

export function emptyFacility(): FacilityDraft {
  return { name: '', address: '', lat: null, lng: null }
}

interface Props {
  label: string
  items: FacilityDraft[]
  onChange: (items: FacilityDraft[]) => void
}

/** 주차장/화장실 목록 편집기. 주소를 적고 "좌표 확인"으로 카카오 지오코딩(/admin/geo/geocode)을
 * 거쳐 좌표를 채운다 — 서버가 좌표 없는 시설을 422로 거르기 때문에 필수 절차다. */
export default function FacilityListEditor({ label, items, onChange }: Props) {
  // 행마다 고정 key. 인덱스를 key로 쓰면 앞 행을 지울 때 주소 후보 같은 행 상태가 다른 행으로 옮겨 간다.
  const nextKey = useRef(0)
  const keys = useRef<number[]>([])
  while (keys.current.length < items.length) keys.current.push(nextKey.current++)
  keys.current.length = items.length

  return (
    <div className="field">
      <label>
        {label}
        <span className="hint">주소 입력 후 "좌표 확인"을 눌러야 저장할 수 있어요</span>
      </label>
      {items.map((item, index) => (
        <FacilityRow
          key={keys.current[index]}
          item={item}
          onChange={(next) => onChange(items.map((f, i) => (i === index ? next : f)))}
          onRemove={() => {
            keys.current.splice(index, 1)
            onChange(items.filter((_, i) => i !== index))
          }}
        />
      ))}
      <button
        type="button"
        className="secondary small"
        onClick={() => onChange([...items, emptyFacility()])}
      >
        + {label} 추가
      </button>
    </div>
  )
}

function FacilityRow({
  item,
  onChange,
  onRemove,
}: {
  item: FacilityDraft
  onChange: (item: FacilityDraft) => void
  onRemove: () => void
}) {
  const [candidates, setCandidates] = useState<GeocodeResult[] | null>(null)
  const [status, setStatus] = useState<string | null>(null)
  const [looking, setLooking] = useState(false)
  // 좌표 확인 응답을 기다리는 동안 폼의 다른 칸이 바뀌어도, 응답은 최신 값 위에 반영한다.
  const latest = useRef({ item, onChange })
  latest.current = { item, onChange }

  const lookup = async () => {
    const address = item.address.trim()
    if (!address) {
      setStatus('주소를 먼저 입력해 주세요.')
      return
    }
    setLooking(true)
    setStatus(null)
    setCandidates(null)
    try {
      const { results } = await geocode(address)
      if (results.length === 0) {
        setStatus('주소를 찾지 못했어요. 주소를 고쳐 주세요.')
      } else if (results.length === 1) {
        pick(results[0])
      } else {
        setCandidates(results)
      }
    } catch (error) {
      setStatus(error instanceof ApiError ? error.message : '좌표 확인에 실패했어요.')
    } finally {
      setLooking(false)
    }
  }

  const pick = (result: GeocodeResult) => {
    latest.current.onChange({
      ...latest.current.item,
      address: result.road_address ?? result.address,
      lat: result.lat,
      lng: result.lng,
    })
    setCandidates(null)
    setStatus(null)
  }

  const hasCoords = item.lat != null && item.lng != null

  return (
    <div className="facility">
      <div className="row">
        <div className="field">
          <input
            placeholder="이름 (선택)"
            value={item.name}
            onChange={(event) => onChange({ ...item, name: event.target.value })}
          />
        </div>
        <div className="field" style={{ flex: 2 }}>
          <input
            placeholder="주소 (필수)"
            value={item.address}
            onChange={(event) =>
              // 주소를 고치면 좌표는 무효다 — 다시 확인해야 한다.
              onChange({ ...item, address: event.target.value, lat: null, lng: null })
            }
          />
        </div>
        <button type="button" className="secondary small" onClick={lookup} disabled={looking}>
          {looking ? '확인 중…' : '좌표 확인'}
        </button>
        <button type="button" className="danger small" onClick={onRemove}>
          삭제
        </button>
      </div>
      <div className={`coord ${hasCoords ? 'ok' : ''}`}>
        {hasCoords
          ? `좌표 확인됨 (${item.lat!.toFixed(6)}, ${item.lng!.toFixed(6)})`
          : '좌표 미확인'}
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
  )
}
