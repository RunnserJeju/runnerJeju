interface Props {
  value: string
  onChange: (value: string) => void
}

/** 목록 페이지 우측 상단의 이름 검색 입력. 입력하는 대로 목록이 걸러진다. */
export default function NameSearch({ value, onChange }: Props) {
  return (
    <input
      className="name-search"
      type="search"
      placeholder="이름 검색"
      value={value}
      onChange={(e) => onChange(e.target.value)}
    />
  )
}

/** 이름에 검색어가 들어 있는지(대소문자·앞뒤 공백 무시). 검색어가 비면 전부 통과. */
export function matchesName(name: string, query: string): boolean {
  const q = query.trim().toLowerCase()
  return q === '' || name.toLowerCase().includes(q)
}
