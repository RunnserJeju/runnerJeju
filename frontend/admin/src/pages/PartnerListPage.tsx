import { useCallback, useEffect, useState } from 'react'

import { ApiError, listPartners, PARTNER_VISIBILITY_LABEL, type Partner } from '../api'
import PartnerModal from '../modals/PartnerModal'
import SortTh, { useSort } from '../components/SortTh'

interface Props {
  /** 목록 로딩이 401이면(세션 만료 등) 인증 화면으로 되돌린다. */
  onUnauthorized: () => void
}

export default function PartnerListPage({ onUnauthorized }: Props) {
  const [partners, setPartners] = useState<Partner[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  /** 모달 대상. null=새 업체 등록, undefined=닫힘. */
  const [editing, setEditing] = useState<Partner | null | undefined>(undefined)
  const { sort, toggle, sorted } = useSort(partners, {
    name: (p) => p.name,
    address: (p) => p.address,
    benefit: (p) => p.benefit,
    pin: (p) => p.coupon_pin,
    instagram: (p) => instagramHandle(p.instagram),
    courses: (p) => p.course_count,
    used: (p) => p.coupon_used_count,
    visibility: (p) => p.visibility,
  })

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
      <p className="muted page-desc">
        여기서 등록한 업체를 코스 수정 화면에서 골라 연결하면 앱 지도에 마커로 표시돼요.
      </p>
      {error && <div className="error">{error}</div>}
      {partners == null && !error && <p className="muted">불러오는 중…</p>}
      {partners && partners.length === 0 && <p className="muted">등록된 협력업체가 없어요.</p>}
      {partners && partners.length > 0 && (
        <table>
          <thead>
            <tr>
              <th></th>
              <SortTh sortKey="name" sort={sort} onToggle={toggle}>
                이름
              </SortTh>
              <SortTh sortKey="address" sort={sort} onToggle={toggle}>
                주소
              </SortTh>
              <SortTh sortKey="benefit" sort={sort} onToggle={toggle}>
                혜택
              </SortTh>
              <SortTh sortKey="pin" sort={sort} onToggle={toggle} className="nowrap">
                쿠폰 번호
              </SortTh>
              <SortTh sortKey="instagram" sort={sort} onToggle={toggle}>
                인스타그램
              </SortTh>
              <SortTh sortKey="courses" sort={sort} onToggle={toggle} className="nowrap">
                연결 코스
              </SortTh>
              <SortTh sortKey="used" sort={sort} onToggle={toggle} className="nowrap">
                쿠폰 사용
              </SortTh>
              <SortTh sortKey="visibility" sort={sort} onToggle={toggle}>
                공개
              </SortTh>
            </tr>
          </thead>
          <tbody>
            {sorted!.map((partner) => (
              <tr key={partner.id} onClick={() => setEditing(partner)}>
                <td style={{ width: 56 }}>
                  {partner.thumbnail_url ? (
                    <img className="thumb" src={partner.thumbnail_url} alt="" />
                  ) : (
                    <div className="thumb placeholder">없음</div>
                  )}
                </td>
                <td>
                  <strong>{partner.name}</strong>
                </td>
                <td className="muted">
                  {partner.address ?? `${partner.lat.toFixed(5)}, ${partner.lng.toFixed(5)}`}
                </td>
                <td>{partner.benefit ?? '—'}</td>
                <td className={partner.coupon_pin ? 'nowrap' : 'nowrap muted'}>
                  {partner.coupon_pin ?? '미설정'}
                </td>
                <td className="nowrap muted">{instagramHandle(partner.instagram) ?? '—'}</td>
                <td className="nowrap">{partner.course_count}</td>
                <td className="nowrap">{partner.coupon_used_count}</td>
                <td className={partner.visibility === 'public' ? 'nowrap' : 'nowrap muted'}>
                  {PARTNER_VISIBILITY_LABEL[partner.visibility]}
                </td>
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

/** 인스타그램 값(계정명이나 URL)에서 계정명만 뽑아 @계정명으로. 못 뽑으면 원문. */
function instagramHandle(value: string | null): string | null {
  const raw = value?.trim()
  if (!raw) return null
  const match = raw.match(/instagram\.com\/([^/?#]+)/i)
  const handle = (match ? match[1] : raw).replace(/^@/, '')
  return `@${handle}`
}
