import { useEffect, useRef, useState } from 'react'

export interface SearchOption {
  id: string
  label: string
  /** 이름 옆에 흐리게 붙는 보조 정보(주소 등). 검색 대상에도 들어간다. */
  sub?: string | null
}

interface Props {
  options: SearchOption[]
  onSelect: (id: string) => void
  /** 주면 고른 값을 입력칸에 계속 보여 준다(select처럼). 없으면 고른 뒤 입력칸을 비운다(추가용). */
  value?: string
  placeholder?: string
  /** 고를 것이 하나도 없을 때 입력칸에 보이는 문구. */
  emptyText?: string
  id?: string
  title?: string
  disabled?: boolean
}

/** 검색되는 고르기. 입력칸을 누르면 전체 후보가 펼쳐지고, 글자를 치면 이름·보조 정보
 * 부분일치만 남는다. */
export default function SearchSelect({
  options,
  onSelect,
  value,
  placeholder = '검색 또는 선택',
  emptyText = '추가할 항목이 없어요',
  id,
  title,
  disabled,
}: Props) {
  const [query, setQuery] = useState('')
  const [open, setOpen] = useState(false)
  /** 방향키로 고르는 중인 후보 위치. */
  const [active, setActive] = useState(0)
  const listRef = useRef<HTMLUListElement>(null)

  // 빈 값('')은 "안 고름"이다 — 입력칸에는 placeholder가 보인다.
  const selectedLabel = value ? (options.find((o) => o.id === value)?.label ?? '') : ''
  const keyword = query.trim().toLowerCase()
  const matches = keyword
    ? options.filter(
        (option) =>
          option.label.toLowerCase().includes(keyword) ||
          (option.sub ?? '').toLowerCase().includes(keyword),
      )
    : options

  const openList = () => {
    setOpen(true)
    // 고른 값이 있으면 그 위치에서 시작한다.
    const index = value === undefined ? 0 : Math.max(0, options.findIndex((o) => o.id === value))
    setActive(index)
  }

  const choose = (option: SearchOption) => {
    onSelect(option.id)
    setQuery('')
    setActive(0)
    if (value !== undefined) setOpen(false)
  }

  const onKeyDown = (event: React.KeyboardEvent<HTMLInputElement>) => {
    if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      event.preventDefault()
      if (!open) return openList()
      const next =
        event.key === 'ArrowDown'
          ? Math.min(active + 1, matches.length - 1)
          : Math.max(active - 1, 0)
      setActive(next)
      listRef.current?.children[next]?.scrollIntoView({ block: 'nearest' })
    } else if (event.key === 'Enter') {
      event.preventDefault()
      if (open && matches[active]) choose(matches[active])
    } else if (event.key === 'Escape' && open) {
      // 모달도 Esc로 닫히므로, 목록만 닫고 모달까지 가지 않게 막는다.
      event.stopPropagation()
      event.nativeEvent.stopImmediatePropagation()
      setOpen(false)
      setQuery('')
    }
  }

  const empty = options.length === 0

  // 마지막 후보를 고르면 입력칸이 비활성화되는데, 그때는 blur가 오지 않아 목록이 열린 채 남는다.
  useEffect(() => {
    if (empty) setOpen(false)
  }, [empty])
  // 값 모드에서 검색 중이 아니면 고른 값을 보여 준다.
  const shown = open || value === undefined ? query : selectedLabel

  return (
    <div className="combobox">
      <input
        id={id}
        // 칸이 좁아 이름이 잘려도 마우스를 올리면 전체가 보인다.
        title={selectedLabel ? (title ? `${title}: ${selectedLabel}` : selectedLabel) : title}
        value={shown}
        placeholder={empty ? emptyText : open && selectedLabel ? selectedLabel : placeholder}
        disabled={disabled || empty}
        onFocus={openList}
        onClick={() => !open && openList()}
        onBlur={() => {
          setOpen(false)
          setQuery('')
        }}
        onChange={(event) => {
          setQuery(event.target.value)
          setActive(0)
          setOpen(true)
        }}
        onKeyDown={onKeyDown}
      />
      {open && !empty && (
        <ul ref={listRef} className="combobox-list">
          {matches.length === 0 && <li className="muted">검색 결과가 없어요</li>}
          {matches.map((option, index) => (
            <li
              key={option.id}
              className={[
                index === active ? 'active' : '',
                option.id === value ? 'selected' : '',
              ]
                .filter(Boolean)
                .join(' ') || undefined}
              // blur보다 먼저 골라야 목록이 닫히기 전에 선택된다.
              onMouseDown={(event) => {
                event.preventDefault()
                choose(option)
              }}
              onMouseEnter={() => setActive(index)}
            >
              {option.label}
              {option.sub && <span className="muted"> · {option.sub}</span>}
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}
