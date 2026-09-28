import { useCallback, useEffect, useState } from 'react'

import { ApiError, listPartners, type Partner } from '../api'
import PartnerModal from '../modals/PartnerModal'

interface Props {
  /** 목록 로딩이 401이면(세션 만료 등) 인증 화면으로 되돌린다. */
  onUnauthorized: () => void
}

export default function PartnerListPage({ onUnauthorized }: Props) {
  const [partners, setPartners] = useState<Partner[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  /** 모달 대상. null=새 업체 등록, undefined=닫힘. */
  const [editing, setEditing] = useState<Partner | null | undefined>(undefined)

  const reload = useCallback(() => {
    listPartners()
      .then((loaded) => {
        setPartners(loaded)
        setError(null)
      })
      .catch((err: unknown) => {
        if (err instanceof ApiError && err.status === 401) {
          onUnauthorized()
          return
        }
        setError(err instanceof ApiError ? err.message : '협력업체 목록을 불러오지 못했어요.')
      })
  }, [onUnauthorized])

  useEffect(() => {
    reload()
  }, [reload])

  return (
    <>
      <div className="page-head">
        <h2>협력업체</h2>
        <button onClick={() => setEditing(null)}>+ 협력업체 추가</button>
      </div>
      <p className="muted" style={{ marginTop: -12 }}>
        여기서 등록한 업체를 코스 수정 화면에서 골라 연결하면 앱 지도에 마커로 표시돼요.
      </p>
      {error && <div className="error">{error}</div>}
      {partners == null && !error && <p className="muted">불러오는 중…</p>}
      {partners && partners.length === 0 && <p className="muted">등록된 협력업체가 없어요.</p>}
      {partners && partners.length > 0 && (
        <table>
          <thead>
            <tr>
              <th>이름</th>
              <th>주소</th>
              <th>혜택</th>
              <th>인스타그램</th>
              <th>연결 코스</th>
            </tr>
          </thead>
          <tbody>
            {partners.map((partner) => (
              <tr key={partner.id} onClick={() => setEditing(partner)}>
                <td>
                  <strong>{partner.name}</strong>
                </td>
                <td className="muted">
                  {partner.address ?? `${partner.lat.toFixed(5)}, ${partner.lng.toFixed(5)}`}
                </td>
                <td>{partner.benefit ?? '—'}</td>
                <td className="muted">{partner.instagram ?? '—'}</td>
                <td>{partner.course_count}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      {editing !== undefined && (
        <PartnerModal partner={editing} onClose={() => setEditing(undefined)} onChanged={reload} />
      )}
    </>
  )
}
