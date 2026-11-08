import { useEffect, useState } from 'react'

import { ApiError } from '../api'

/**
 * 저장 안 한 순서를 새로 받은 목록에 맞춘다. 순서를 바꾸던 중에 항목을 추가·삭제해도
 * 바꾸던 순서가 날아가지 않게 — 새 항목은 서버처럼 맨 앞에, 지운 항목은 뺀다.
 * 바꾸던 게 없으면 결과가 서버 순서와 같다.
 */
function keepLocalOrder(previous: string[] | null, loaded: { id: string }[]): string[] {
  const ids = loaded.map((item) => item.id)
  if (!previous) return ids
  const alive = new Set(ids)
  const known = new Set(previous)
  return [...ids.filter((id) => !known.has(id)), ...previous.filter((id) => alive.has(id))]
}

interface Options<T> {
  /** 서버가 준 목록(서버 순서). */
  items: T[] | null
  /** 순서 저장. 전부의 id를 보여줄 순서대로 보내고, 저장된 목록을 돌려받는다. */
  save: (ids: string[]) => Promise<T[]>
  /** 저장된 목록으로 바꿔 끼운다. */
  onSaved: (items: T[]) => void
  onUnauthorized: () => void
}

/**
 * 목록 순서를 ↑↓로 바꾸고 통째로 저장하는 표의 상태(공지·이벤트). 서버는 새 항목을 맨 앞에
 * 붙이고, 목록 전부를 받아 0부터 다시 매긴다(그새 바뀌었으면 409).
 */
export function useListOrder<T extends { id: string }>({
  items,
  save,
  onSaved,
  onUnauthorized,
}: Options<T>) {
  /** 화면에 보이는 순서(id). 저장 전이면 서버 순서와 다르다. */
  const [order, setOrder] = useState<string[] | null>(null)
  const [saving, setSaving] = useState(false)
  const [saved, setSaved] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (items) setOrder((previous) => keepLocalOrder(previous, items))
  }, [items])

  const byId = new Map((items ?? []).map((item) => [item.id, item]))
  const ordered = (order ?? []).flatMap((id) => byId.get(id) ?? [])
  const dirty = order != null && order.join(',') !== (items ?? []).map((item) => item.id).join(',')

  const move = (index: number, delta: number) => {
    if (!order) return
    const next = [...order]
    const [moved] = next.splice(index, 1)
    next.splice(index + delta, 0, moved)
    setOrder(next)
    setSaved(false)
    setError(null)
  }

  const submit = async () => {
    if (!order) return
    setSaving(true)
    setError(null)
    try {
      const result = await save(order)
      setOrder(result.map((item) => item.id))
      onSaved(result)
      setSaved(true)
    } catch (err) {
      if (err instanceof ApiError && err.status === 401) {
        onUnauthorized()
        return
      }
      setError(err instanceof ApiError ? err.message : '순서를 저장하지 못했어요.')
    } finally {
      setSaving(false)
    }
  }

  const revert = () => {
    setOrder((items ?? []).map((item) => item.id))
    setError(null)
  }

  return { ordered, move, dirty, saving, saved, error, submit, revert }
}

/** 행 끝의 ↑↓. 행을 누르면 수정 모달이 열리므로 버튼 클릭은 행까지 올리지 않는다. */
export function OrderCell({
  index,
  count,
  onMove,
}: {
  index: number
  count: number
  onMove: (index: number, delta: number) => void
}) {
  return (
    <td style={{ width: 1, whiteSpace: 'nowrap' }} onClick={(event) => event.stopPropagation()}>
      <div className="row" style={{ gap: 6 }}>
        <button
          className="secondary small"
          disabled={index === 0}
          onClick={() => onMove(index, -1)}
          aria-label="위로"
        >
          ↑
        </button>
        <button
          className="secondary small"
          disabled={index === count - 1}
          onClick={() => onMove(index, 1)}
          aria-label="아래로"
        >
          ↓
        </button>
      </div>
    </td>
  )
}

/** 표 아래 "순서 저장 / 되돌리기". 바꾼 게 있거나 방금 저장했을 때만 보인다. */
export function OrderSaveRow({ state }: { state: ReturnType<typeof useListOrder> }) {
  const { dirty, saving, saved, error, submit, revert } = state
  return (
    <>
      {error && <div className="error">{error}</div>}
      {(dirty || saved) && (
        <div className="submit-row">
          <button onClick={submit} disabled={!dirty || saving}>
            {saving ? '저장 중…' : '순서 저장'}
          </button>
          {dirty && (
            <button className="secondary" onClick={revert}>
              되돌리기
            </button>
          )}
          {saved && !dirty && <span className="muted">순서를 저장했어요.</span>}
        </div>
      )}
    </>
  )
}
