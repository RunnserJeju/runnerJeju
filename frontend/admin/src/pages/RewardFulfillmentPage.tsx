import { useCallback, useEffect, useState } from 'react'

import {
  ApiError,
  completeRewardFulfillment,
  listCouponDraws,
  listRewardFulfillments,
  type CouponDraw,
  type RewardFulfillment,
} from '../api'
import { STATUS_LABEL } from './CouponListPage'

interface Props {
  onUnauthorized: () => void
}

type Tab = 'pending' | 'all' | 'draws'
const PAGE = 50

const RESULT_LABEL: Record<CouponDraw['result'], string> = {
  won: '당첨',
  lost: '낙첨',
  sold_out: '소진',
}

/**
 * 경품 지급 처리. 카카오톡 채널로 받은 캡처의 쿠폰 코드(또는 닉네임)로 찾아 "지급완료"를 누른다.
 * 지급완료는 앱 쿠폰함에서 사용완료로 보인다. 추첨 기록 탭은 "왜 못 받았나" 문의 대응용.
 */
export default function RewardFulfillmentPage({ onUnauthorized }: Props) {
  const [tab, setTab] = useState<Tab>('pending')
  const [draft, setDraft] = useState('')
  const [keyword, setKeyword] = useState('')
  const [page, setPage] = useState(0)
  const [total, setTotal] = useState(0)
  const [items, setItems] = useState<RewardFulfillment[] | null>(null)
  const [draws, setDraws] = useState<CouponDraw[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [message, setMessage] = useState<string | null>(null)
  const [busy, setBusy] = useState<string | null>(null)

  const fail = useCallback(
    (err: unknown, fallback: string) => {
      if (err instanceof ApiError && err.status === 401) {
        onUnauthorized()
        return
      }
      setError(err instanceof ApiError ? err.message : fallback)
    },
    [onUnauthorized],
  )

  const reload = useCallback(() => {
    setError(null)
    if (tab === 'draws') {
      listCouponDraws(null, keyword, PAGE, page * PAGE)
        .then((result) => {
          setTotal(result.total)
          setDraws(result.items)
        })
        .catch((err: unknown) => fail(err, '추첨 기록을 불러오지 못했어요.'))
      return
    }
    listRewardFulfillments(tab === 'pending', keyword, PAGE, page * PAGE)
      .then((result) => {
        setTotal(result.total)
        setItems(result.items)
      })
      .catch((err: unknown) => fail(err, '경품 목록을 불러오지 못했어요.'))
  }, [tab, keyword, page, fail])

  useEffect(() => {
    reload()
  }, [reload])

  const switchTab = (next: Tab) => {
    setTab(next)
    setPage(0)
    setItems(null)
    setDraws(null)
    setMessage(null)
  }

  const complete = async (item: RewardFulfillment) => {
    const who = item.nickname ?? '(닉네임 없음)'
    if (!window.confirm(`${who} · ${item.code}\n"${item.benefit}" 지급완료 처리할까요?`)) return
    setBusy(item.id)
    setError(null)
    try {
      await completeRewardFulfillment(item.id)
      setMessage(`${who}의 ${item.code} 지급완료 처리했어요. 앱 쿠폰함에도 사용완료로 보여요.`)
      reload()
    } catch (err) {
      fail(err, '지급완료 처리에 실패했어요.')
    } finally {
      setBusy(null)
    }
  }

  const pageCount = Math.max(1, Math.ceil(total / PAGE))

  return (
    <>
      <div className="page-head">
        <h2>경품 지급</h2>
      </div>
      <p className="muted page-desc">
        당첨자가 카카오톡 채널 '제주러닝위크'로 보낸 쿠폰 화면 캡처의 코드로 찾아 지급완료를 눌러요. 지급완료하면 앱
        쿠폰함에서 사용완료로 바뀌어요.
      </p>
      <div className="tabs">
        <button className={tab === 'pending' ? 'active' : undefined} onClick={() => switchTab('pending')}>
          미지급
        </button>
        <button className={tab === 'all' ? 'active' : undefined} onClick={() => switchTab('all')}>
          전체
        </button>
        <button className={tab === 'draws' ? 'active' : undefined} onClick={() => switchTab('draws')}>
          추첨 기록
        </button>
      </div>
      <form
        className="search-row"
        onSubmit={(event) => {
          event.preventDefault()
          setPage(0)
          setKeyword(draft)
        }}
      >
        <input
          placeholder={tab === 'draws' ? '닉네임' : '쿠폰 코드(예: K7F2-9QAD) 또는 닉네임'}
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
        />
        <button type="submit" className="secondary">
          검색
        </button>
      </form>
      {message && <div className="notice">{message}</div>}
      {error && <div className="error">{error}</div>}

      {tab !== 'draws' && (
        <>
          {items == null && !error && <p className="muted">불러오는 중…</p>}
          {items && items.length === 0 && (
            <p className="muted">{tab === 'pending' ? '지급할 경품이 없어요.' : '발급된 경품이 없어요.'}</p>
          )}
          {items && items.length > 0 && (
            <table>
              <thead>
                <tr>
                  <th>코드</th>
                  <th>회원</th>
                  <th>경품</th>
                  <th>발급</th>
                  <th>수령 기한</th>
                  <th>상태</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                {items.map((item) => (
                  <tr key={item.id}>
                    <td className="nowrap">
                      <code>{item.code}</code>
                    </td>
                    <td>{item.nickname ?? <span className="muted">(탈퇴/미설정)</span>}</td>
                    <td>
                      <strong>{item.benefit}</strong>
                      <div className="muted">{item.coupon_name}</div>
                    </td>
                    <td className="muted nowrap">{new Date(item.issued_at).toLocaleString()}</td>
                    <td className="muted nowrap">
                      {item.valid_until ? new Date(item.valid_until).toLocaleDateString() : '무기한'}
                    </td>
                    <td>
                      <span
                        className={`badge ${item.status === 'available' ? 'live' : item.status === 'used' ? 'scheduled' : 'expired'}`}
                      >
                        {item.status === 'used' ? '지급완료' : STATUS_LABEL[item.status]}
                      </span>
                      {item.used_at && (
                        <div className="muted nowrap">{new Date(item.used_at).toLocaleString()}</div>
                      )}
                    </td>
                    <td className="nowrap">
                      {item.status === 'available' && (
                        <button
                          className="small"
                          disabled={busy === item.id}
                          onClick={() => complete(item)}
                        >
                          {busy === item.id ? '처리 중…' : '지급완료 처리'}
                        </button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </>
      )}

      {tab === 'draws' && (
        <>
          {draws == null && !error && <p className="muted">불러오는 중…</p>}
          {draws && draws.length === 0 && <p className="muted">추첨 기록이 없어요.</p>}
          {draws && draws.length > 0 && (
            <table>
              <thead>
                <tr>
                  <th>시각</th>
                  <th>회원</th>
                  <th>쿠폰</th>
                  <th>결과</th>
                  <th>코드</th>
                </tr>
              </thead>
              <tbody>
                {draws.map((draw) => (
                  <tr key={draw.id}>
                    <td className="muted nowrap">{new Date(draw.drawn_at).toLocaleString()}</td>
                    <td>{draw.nickname ?? <span className="muted">(탈퇴/미설정)</span>}</td>
                    <td>{draw.coupon_name}</td>
                    <td>
                      <span
                        className={`badge ${draw.result === 'won' ? 'live' : draw.result === 'lost' ? 'expired' : 'scheduled'}`}
                      >
                        {RESULT_LABEL[draw.result]}
                      </span>
                    </td>
                    <td className="nowrap">{draw.code ? <code>{draw.code}</code> : '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </>
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
    </>
  )
}
