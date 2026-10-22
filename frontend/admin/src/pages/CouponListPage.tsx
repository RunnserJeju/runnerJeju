import { useCallback, useEffect, useState } from 'react'

import {
  ApiError,
  issueCoupon,
  listCoupons,
  listIssuedCoupons,
  listPartners,
  listUsers,
  updateCoupon,
  type Coupon,
  type CouponPayload,
  type CouponTriggerType,
  type IssuedCoupon,
  type Partner,
  type UserSummary,
} from '../api'
import Modal from '../components/Modal'
import PartnerPicker from '../components/PartnerPicker'

interface Props {
  /** 목록 로딩이 401이면(세션 만료 등) 인증 화면으로 되돌린다. */
  onUnauthorized: () => void
}

const TRIGGER_LABEL: Record<CouponTriggerType, string> = {
  manual: '운영자 지급',
  course_complete: '코스 완주',
  bingo_complete: '빙고판 완성',
}

const TRIGGER_HINT: Record<CouponTriggerType, string> = {
  manual: '"지급" 탭에서 회원을 골라 직접 줘요.',
  course_complete:
    '러닝위크 참가자가 공개 기간에 아무 코스나 완주하면 자동으로 한 장. 코스마다 한 번.',
  bingo_complete:
    '러닝위크 빙고판 25칸을 다 채우면(=25개 코스 완주) 자동으로 한 장. 참가 신청한 사람만, 회차마다 한 번.',
}

/**
 * 쿠폰 관리. 템플릿은 서버 코드가 심고 여기서는 수정·지급·발급 현황만 다룬다 —
 * 운영툴에서 만들어 봤자 지급 조건을 붙일 수 없어서 추가·삭제 버튼이 없다.
 */
export default function CouponListPage({ onUnauthorized }: Props) {
  const [coupons, setCoupons] = useState<Coupon[] | null>(null)
  const [partners, setPartners] = useState<Partner[]>([])
  const [error, setError] = useState<string | null>(null)
  const [editing, setEditing] = useState<Coupon | null>(null)

  const reload = useCallback(() => {
    Promise.all([listCoupons(), listPartners()])
      .then(([loadedCoupons, loadedPartners]) => {
        setCoupons(loadedCoupons)
        setPartners(loadedPartners)
        setError(null)
      })
      .catch((err: unknown) => {
        if (err instanceof ApiError && err.status === 401) {
          onUnauthorized()
          return
        }
        setError(err instanceof ApiError ? err.message : '쿠폰 목록을 불러오지 못했어요.')
      })
  }, [onUnauthorized])

  useEffect(() => {
    reload()
  }, [reload])

  const partnerLabel = (coupon: Coupon) => {
    if (coupon.partner_ids.length === 0) return '모든 업체'
    const names = coupon.partner_ids.map(
      (id) => partners.find((p) => p.id === id)?.name ?? '(삭제된 업체)',
    )
    return names.length <= 2 ? names.join(', ') : `${names[0]} 외 ${names.length - 1}곳`
  }

  return (
    <>
      <div className="page-head">
        <h2>쿠폰</h2>
      </div>
      <p className="muted page-desc">
        등록된 쿠폰의 혜택 내용, 상태, 유효기간 등을 편집합니다. 
      </p>
      {error && <div className="error">{error}</div>}
      {coupons == null && !error && <p className="muted">불러오는 중…</p>}
      {coupons && coupons.length === 0 && <p className="muted">심어진 쿠폰이 없어요.</p>}
      {coupons && coupons.length > 0 && (
        <table>
          <thead>
            <tr>
              <th>이름</th>
              <th>지급 조건</th>
              <th>상태</th>
              <th>사용 업체</th>
              <th>유효기간</th>
              <th>발급 / 사용</th>
            </tr>
          </thead>
          <tbody>
            {coupons.map((coupon) => (
              <tr key={coupon.id} onClick={() => setEditing(coupon)}>
                <td>
                  <strong>{coupon.name}</strong>
                  <div className="muted clamp">{coupon.benefit}</div>
                </td>
                <td>{TRIGGER_LABEL[coupon.trigger_type] ?? coupon.trigger_type}</td>
                <td>
                  <span className={`badge ${coupon.is_active ? 'live' : 'expired'}`}>
                    {coupon.is_active ? '활성화' : '비활성화'}
                  </span>
                </td>
                <td className="muted">{partnerLabel(coupon)}</td>
                <td className="muted">
                  {coupon.valid_until ? new Date(coupon.valid_until).toLocaleString() : '무기한'}
                </td>
                <td className="muted">
                  {coupon.issued_count} / {coupon.used_count}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      {editing && (
        <CouponModal
          coupon={editing}
          onClose={() => setEditing(null)}
          onSaved={(saved) => {
            setEditing(saved)
            reload()
          }}
        />
      )}
    </>
  )
}

type Tab = 'edit' | 'issue' | 'issued'

function CouponModal({
  coupon,
  onClose,
  onSaved,
}: {
  coupon: Coupon
  onClose: () => void
  onSaved: (coupon: Coupon) => void
}) {
  const [tab, setTab] = useState<Tab>('edit')

  return (
    <Modal title={`쿠폰 — ${coupon.name}`} onClose={onClose}>
      <div className="tabs" style={{ marginTop: 0, marginBottom: 12 }}>
        <button className={tab === 'edit' ? 'active' : undefined} onClick={() => setTab('edit')}>
          수정
        </button>
        {coupon.trigger_type === 'manual' && (
          <button
            className={tab === 'issue' ? 'active' : undefined}
            onClick={() => setTab('issue')}
          >
            지급
          </button>
        )}
        <button
          className={tab === 'issued' ? 'active' : undefined}
          onClick={() => setTab('issued')}
        >
          발급 현황 ({coupon.issued_count})
        </button>
      </div>
      {tab === 'edit' && <CouponEditForm coupon={coupon} onSaved={onSaved} />}
      {tab === 'issue' && <CouponIssueSection coupon={coupon} onIssued={onSaved} />}
      {tab === 'issued' && <IssuedSection coupon={coupon} />}
    </Modal>
  )
}

/** ISO(UTC) → datetime-local 입력값("YYYY-MM-DDTHH:mm", 로컬 시각). */
function toLocalInput(iso: string | null): string {
  if (!iso) return ''
  const d = new Date(iso)
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`
}

interface FormValues {
  name: string
  benefit: string
  description: string
  validUntil: string
  isActive: boolean
  partnerIds: string[]
}

function CouponEditForm({
  coupon,
  onSaved,
}: {
  coupon: Coupon
  onSaved: (coupon: Coupon) => void
}) {
  const [values, setValues] = useState<FormValues>({
    name: coupon.name,
    benefit: coupon.benefit,
    description: coupon.description ?? '',
    validUntil: toLocalInput(coupon.valid_until),
    isActive: coupon.is_active,
    partnerIds: coupon.partner_ids,
  })
  const [error, setError] = useState<string | null>(null)
  const [message, setMessage] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)

  const set = (patch: Partial<FormValues>) => {
    setValues((prev) => ({ ...prev, ...patch }))
    setMessage(null)
  }

  const save = async () => {
    setError(null)
    const name = values.name.trim()
    const benefit = values.benefit.trim()
    if (!name) {
      setError('이름을 입력해 주세요.')
      return
    }
    if (!benefit) {
      setError('혜택을 입력해 주세요.')
      return
    }
    const payload: CouponPayload = {
      name,
      benefit,
      description: values.description.trim() || null,
      valid_until: values.validUntil ? new Date(values.validUntil).toISOString() : null,
      is_active: values.isActive,
      partner_ids: values.partnerIds,
    }
    setSaving(true)
    try {
      onSaved(await updateCoupon(coupon.id, payload))
      setMessage('저장했어요. 이미 발급된 쿠폰에도 바로 반영돼요.')
    } catch (err) {
      setError(err instanceof ApiError ? err.message : '저장에 실패했어요.')
    } finally {
      setSaving(false)
    }
  }

  return (
    <>
      {message && <div className="notice" style={{ marginTop: 0 }}>{message}</div>}
      <div className="card">
        <div className="field">
          <label>지급 조건</label>
          <div>
            <strong>{TRIGGER_LABEL[coupon.trigger_type] ?? coupon.trigger_type}</strong>
            <div className="hint">{TRIGGER_HINT[coupon.trigger_type]} 조건은 여기서 못 바꿔요.</div>
          </div>
        </div>
        <div className="field">
          <label htmlFor="coupon-name">이름</label>
          <input
            id="coupon-name"
            value={values.name}
            maxLength={200}
            onChange={(e) => set({ name: e.target.value })}
          />
        </div>
        <div className="field">
          <label htmlFor="coupon-benefit">
            혜택 <span className="hint">예) 아메리카노 1잔. 앱 쿠폰에 크게 보여요</span>
          </label>
          <input
            id="coupon-benefit"
            value={values.benefit}
            maxLength={500}
            onChange={(e) => set({ benefit: e.target.value })}
          />
        </div>
        <div className="field">
          <label htmlFor="coupon-description">
            설명 <span className="hint">사용 방법·주의사항. 앱 쿠폰 상세에 그대로 보여요</span>
          </label>
          <textarea
            id="coupon-description"
            value={values.description}
            onChange={(e) => set({ description: e.target.value })}
          />
        </div>
        <div className="field">
          <label htmlFor="coupon-valid-until">
            유효기간 <span className="hint">비우면 무기한. 지나면 발급된 쿠폰이 만료돼요</span>
          </label>
          <input
            id="coupon-valid-until"
            type="datetime-local"
            value={values.validUntil}
            onChange={(e) => set({ validUntil: e.target.value })}
          />
        </div>
        <PartnerPicker
          selectedIds={values.partnerIds}
          onChange={(ids) => set({ partnerIds: ids })}
          label="사용 가능 업체"
          hint="비워 두면 모든 협력업체에서 쓸 수 있어요"
        />
        <div className="field">
          <label>
            <input
              type="checkbox"
              checked={values.isActive}
              onChange={(e) => set({ isActive: e.target.checked })}
            />{' '}
            활성화
            <span className="hint">
              러닝위크 기간에만 켜 주세요. 켜져 있을 때만 자동 지급돼요. 이미 받은 쿠폰은 꺼도 그대로 쓸 수 있어요
            </span>
          </label>
        </div>
        {error && <div className="error">{error}</div>}
        <div className="submit-row">
          <button onClick={save} disabled={saving}>
            {saving ? '저장 중…' : '저장'}
          </button>
        </div>
      </div>
    </>
  )
}

const USER_PAGE = 20

/** 운영자 지급: 회원을 검색해 체크하고 한 번에 준다. 같은 사람에게 여러 번 줄 수도 있다. */
function CouponIssueSection({
  coupon,
  onIssued,
}: {
  coupon: Coupon
  onIssued: (coupon: Coupon) => void
}) {
  const [draft, setDraft] = useState('')
  const [keyword, setKeyword] = useState('')
  const [users, setUsers] = useState<UserSummary[] | null>(null)
  const [selected, setSelected] = useState<Map<string, UserSummary>>(new Map())
  const [error, setError] = useState<string | null>(null)
  const [message, setMessage] = useState<string | null>(null)
  const [issuing, setIssuing] = useState(false)

  useEffect(() => {
    listUsers(keyword, USER_PAGE, 0)
      .then((page) => setUsers(page.items))
      .catch((err: unknown) =>
        setError(err instanceof ApiError ? err.message : '회원을 불러오지 못했어요.'),
      )
  }, [keyword])

  const toggle = (user: UserSummary) => {
    setSelected((prev) => {
      const next = new Map(prev)
      if (next.has(user.id)) next.delete(user.id)
      else next.set(user.id, user)
      return next
    })
    setMessage(null)
  }

  const issue = async () => {
    if (selected.size === 0) return
    if (!window.confirm(`${selected.size}명에게 "${coupon.name}"을 지급할까요?`)) return
    setError(null)
    setIssuing(true)
    try {
      const result = await issueCoupon(coupon.id, [...selected.keys()])
      setMessage(`${result.issued}명에게 지급했어요.`)
      setSelected(new Map())
      onIssued({ ...coupon, issued_count: coupon.issued_count + result.issued })
    } catch (err) {
      setError(err instanceof ApiError ? err.message : '지급에 실패했어요.')
    } finally {
      setIssuing(false)
    }
  }

  const label = (user: UserSummary) => user.nickname ?? user.email ?? user.id.slice(0, 8)

  return (
    <div className="card">
      {message && <div className="notice" style={{ marginTop: 0 }}>{message}</div>}
      <form
        className="search-row"
        onSubmit={(event) => {
          event.preventDefault()
          setKeyword(draft)
        }}
      >
        <input
          placeholder="닉네임 또는 이메일"
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
        />
        <button type="submit" className="secondary">
          검색
        </button>
      </form>
      {error && <div className="error">{error}</div>}
      {users == null && !error && <p className="muted">불러오는 중…</p>}
      {users && users.length === 0 && <p className="muted">조건에 맞는 회원이 없어요.</p>}
      {users && users.length > 0 && (
        <table className="users-table">
          <thead>
            <tr>
              <th></th>
              <th>닉네임</th>
              <th>이메일</th>
              <th>완주</th>
            </tr>
          </thead>
          <tbody>
            {users.map((user) => (
              <tr key={user.id} onClick={() => toggle(user)}>
                <td style={{ width: 32 }}>
                  <input type="checkbox" checked={selected.has(user.id)} readOnly />
                </td>
                <td>{user.nickname ?? <span className="muted">(미설정)</span>}</td>
                <td className="muted">{user.email ?? '—'}</td>
                <td className="muted">{user.completed_count}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
      {selected.size > 0 && (
        <p className="muted" style={{ marginTop: 12 }}>
          고른 회원: {[...selected.values()].map(label).join(', ')}
        </p>
      )}
      <div className="submit-row">
        <button onClick={issue} disabled={issuing || selected.size === 0}>
          {issuing ? '지급 중…' : `${selected.size}명에게 지급`}
        </button>
      </div>
    </div>
  )
}

const ISSUED_PAGE = 20

const STATUS_LABEL: Record<IssuedCoupon['status'], string> = {
  available: '사용 가능',
  used: '사용함',
  expired: '만료',
}

function IssuedSection({ coupon }: { coupon: Coupon }) {
  const [page, setPage] = useState(0)
  const [total, setTotal] = useState(0)
  const [items, setItems] = useState<IssuedCoupon[] | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    listIssuedCoupons(coupon.id, ISSUED_PAGE, page * ISSUED_PAGE)
      .then((result) => {
        setTotal(result.total)
        setItems(result.items)
      })
      .catch((err: unknown) =>
        setError(err instanceof ApiError ? err.message : '발급 현황을 불러오지 못했어요.'),
      )
  }, [coupon.id, page])

  const pageCount = Math.max(1, Math.ceil(total / ISSUED_PAGE))

  return (
    <div className="card">
      {error && <div className="error">{error}</div>}
      {items == null && !error && <p className="muted">불러오는 중…</p>}
      {items && items.length === 0 && <p className="muted">아직 발급된 쿠폰이 없어요.</p>}
      {items && items.length > 0 && (
        <table className="users-table">
          <thead>
            <tr>
              <th>회원</th>
              <th>발급</th>
              <th>상태</th>
              <th>사용 업체</th>
              <th>사용 시각</th>
            </tr>
          </thead>
          <tbody>
            {items.map((item) => (
              <tr key={item.id}>
                <td>{item.nickname ?? <span className="muted">(탈퇴/미설정)</span>}</td>
                <td className="muted nowrap">{new Date(item.issued_at).toLocaleString()}</td>
                <td>
                  <span
                    className={`badge ${item.status === 'available' ? 'live' : item.status === 'used' ? 'scheduled' : 'expired'}`}
                  >
                    {STATUS_LABEL[item.status]}
                  </span>
                </td>
                <td>{item.used_partner_name ?? (item.used_at ? '(삭제된 업체)' : '—')}</td>
                <td className="muted nowrap">
                  {item.used_at ? new Date(item.used_at).toLocaleString() : '—'}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
      {pageCount > 1 && (
        <div className="pager">
          <button className="secondary small" disabled={page === 0} onClick={() => setPage(page - 1)}>
            이전
          </button>
          <span className="muted">
            {page + 1} / {pageCount}
          </span>
          <button
            className="secondary small"
            disabled={page + 1 >= pageCount}
            onClick={() => setPage(page + 1)}
          >
            다음
          </button>
        </div>
      )}
    </div>
  )
}
