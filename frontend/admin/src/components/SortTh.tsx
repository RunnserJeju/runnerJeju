import { useState, type ReactNode } from 'react'

/** 표 열 정렬. 열 제목을 누르면 오름차순 → 내림차순 → 해제 순으로 돈다. */

export type SortValue = string | number | boolean | null | undefined
export type SortDir = 'asc' | 'desc'
export interface SortState {
  key: string
  dir: SortDir
}

/** 열 key → 그 행의 비교값. 날짜는 ISO 문자열 그대로 두면 사전순이 시간순이다. */
export type SortGetters<T> = Record<string, (row: T) => SortValue>

function compare(a: SortValue, b: SortValue): number {
  // 빈 값은 방향과 무관하게 맨 뒤.
  const aEmpty = a == null || a === ''
  const bEmpty = b == null || b === ''
  if (aEmpty && bEmpty) return 0
  if (aEmpty) return 1
  if (bEmpty) return -1
  if (typeof a === 'number' && typeof b === 'number') return a - b
  if (typeof a === 'boolean' && typeof b === 'boolean') return Number(b) - Number(a)
  return String(a).localeCompare(String(b), 'ko', { numeric: true })
}

export function sortRows<T>(rows: T[], sort: SortState | null, getters: SortGetters<T>): T[] {
  if (!sort) return rows
  const get = getters[sort.key]
  if (!get) return rows
  const sign = sort.dir === 'asc' ? 1 : -1
  return [...rows].sort((x, y) => {
    const c = compare(get(x), get(y))
    // 빈 값은 항상 뒤로 — 부호를 뒤집지 않는다.
    const xEmpty = get(x) == null || get(x) === ''
    const yEmpty = get(y) == null || get(y) === ''
    return xEmpty || yEmpty ? c : c * sign
  })
}

export function useSort<T>(rows: T[] | null, getters: SortGetters<T>) {
  const [sort, setSort] = useState<SortState | null>(null)
  const toggle = (key: string) =>
    setSort((prev) => {
      if (prev?.key !== key) return { key, dir: 'asc' }
      if (prev.dir === 'asc') return { key, dir: 'desc' }
      return null
    })
  return { sort, toggle, sorted: rows ? sortRows(rows, sort, getters) : null }
}

interface Props {
  sortKey: string
  sort: SortState | null
  onToggle: (key: string) => void
  className?: string
  children: ReactNode
}

export default function SortTh({ sortKey, sort, onToggle, className, children }: Props) {
  const active = sort?.key === sortKey
  return (
    <th
      className={['sortable', active ? 'active' : '', className ?? ''].filter(Boolean).join(' ')}
      onClick={() => onToggle(sortKey)}
      aria-sort={active ? (sort.dir === 'asc' ? 'ascending' : 'descending') : 'none'}
    >
      {children}
      <span className="sort-mark">{active ? (sort.dir === 'asc' ? '▲' : '▼') : '⇅'}</span>
    </th>
  )
}
