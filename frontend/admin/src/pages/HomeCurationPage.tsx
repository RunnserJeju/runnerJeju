import { useCallback, useEffect, useState, type ReactNode } from 'react'

import {
  ApiError,
  getHome,
  listCourses,
  listPartners,
  setHomeCourses,
  setHomePartners,
  type Course,
  type HomeCuration,
  type Partner,
} from '../api'

interface Props {
  /** 목록 로딩이 401이면(세션 만료 등) 인증 화면으로 되돌린다. */
  onUnauthorized: () => void
}

/**
 * 앱 홈의 두 섹션 구성: '러닝 코스 큐레이션'(코스)과 '추천 협력 업체'(업체).
 * 섹션마다 고른 항목을 순서대로 편집하고 저장하면 그 순서 그대로 앱 홈에 나온다.
 */
export default function HomeCurationPage({ onUnauthorized }: Props) {
  const [courses, setCourses] = useState<Course[] | null>(null)
  const [partners, setPartners] = useState<Partner[] | null>(null)
  const [home, setHome] = useState<HomeCuration | null>(null)
  const [error, setError] = useState<string | null>(null)

  const reload = useCallback(() => {
    Promise.all([listCourses(), listPartners(), getHome()])
      .then(([loadedCourses, loadedPartners, loadedHome]) => {
        setCourses(loadedCourses)
        setPartners(loadedPartners)
        setHome(loadedHome)
        setError(null)
      })
      .catch((err: unknown) => {
        if (err instanceof ApiError && err.status === 401) {
          onUnauthorized()
          return
        }
        setError(err instanceof ApiError ? err.message : '목록을 불러오지 못했어요.')
      })
  }, [onUnauthorized])

  useEffect(() => {
    reload()
  }, [reload])

  return (
    <>
      <div className="page-head">
        <h2>홈 구성</h2>
      </div>
      <p className="muted" style={{ marginTop: -12 }}>
        앱 홈에 띄울 코스와 협력업체를 고르고 순서를 정해요. 저장하면 앱을 새로 열거나 당겨서
        새로고침할 때 반영돼요. 아무것도 고르지 않으면 그 섹션은 앱 홈에서 숨겨져요.
      </p>
      {error && <div className="error">{error}</div>}
      {home == null && !error && <p className="muted">불러오는 중…</p>}

      {courses && home && (
        <HomeSection
          title="러닝 코스 큐레이션"
          noun="코스"
          items={courses}
          initialIds={home.course_ids}
          optionLabel={(c) => `${c.name} (${c.distance_km}km)`}
          renderItem={(c) => (
            <>
              <td style={{ width: 56 }}>
                {c.thumbnail_url ? (
                  <img className="thumb" src={c.thumbnail_url} alt="" />
                ) : (
                  <div className="thumb placeholder">없음</div>
                )}
              </td>
              <td>
                <strong>{c.name}</strong>
                <div className="muted">
                  {c.distance_km}km · {c.address}
                </div>
                {c.visibility !== 'public' && (
                  <div className="muted">비공개 코스라 일반 사용자 홈에는 안 보여요.</div>
                )}
              </td>
            </>
          )}
          save={setHomeCourses}
          onSaved={reload}
          onUnauthorized={onUnauthorized}
        />
      )}

      {partners && home && (
        <HomeSection
          title="추천 협력 업체"
          noun="협력업체"
          items={partners}
          initialIds={home.partner_ids}
          optionLabel={(p) => (p.address ? `${p.name} · ${p.address}` : p.name)}
          renderItem={(p) => (
            <td colSpan={2}>
              <strong>{p.name}</strong>
              <div className="muted">{p.benefit ?? '혜택 없음'}</div>
            </td>
          )}
          save={setHomePartners}
          onSaved={reload}
          onUnauthorized={onUnauthorized}
        />
      )}
    </>
  )
}

interface SectionProps<T extends { id: string }> {
  title: string
  /** 안내 문구에 쓰는 항목 이름. 예) '코스' */
  noun: string
  items: T[]
  /** 서버에 저장된 현재 구성(순서대로). */
  initialIds: string[]
  optionLabel: (item: T) => string
  /** 한 줄의 내용 칸(<td> 두 칸 분량). 순서·조작 칸은 이 컴포넌트가 붙인다. */
  renderItem: (item: T) => ReactNode
  save: (ids: string[]) => Promise<void>
  onSaved: () => void
  onUnauthorized: () => void
}

/** 한 섹션의 편집기: 고른 목록(순서 이동·빼기) + 추가 드롭다운 + 저장. */
function HomeSection<T extends { id: string }>({
  title,
  noun,
  items,
  initialIds,
  optionLabel,
  renderItem,
  save,
  onSaved,
  onUnauthorized,
}: SectionProps<T>) {
  const [ids, setIds] = useState<string[]>(initialIds)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [saved, setSaved] = useState(false)

  // 저장 뒤 목록을 다시 받으면 서버 값으로 맞춘다. 배열은 매번 새로 만들어지므로
  // 내용으로 비교한다.
  const initialKey = initialIds.join(',')
  useEffect(() => {
    setIds(initialKey ? initialKey.split(',') : [])
  }, [initialKey])

  const byId = new Map(items.map((item) => [item.id, item]))
  const picked = ids.map((id) => byId.get(id)).filter((item): item is T => item != null)
  const candidates = items.filter((item) => !ids.includes(item.id))
  const dirty = ids.join(',') !== initialKey

  const change = (next: string[]) => {
    setIds(next)
    setSaved(false)
  }

  const move = (index: number, delta: number) => {
    const next = [...ids]
    const [moved] = next.splice(index, 1)
    next.splice(index + delta, 0, moved)
    change(next)
  }

  const submit = async () => {
    setSaving(true)
    setError(null)
    try {
      await save(ids)
      setSaved(true)
      onSaved()
    } catch (err) {
      if (err instanceof ApiError && err.status === 401) {
        onUnauthorized()
        return
      }
      setError(err instanceof ApiError ? err.message : '저장하지 못했어요.')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="card">
      <h3 style={{ marginTop: 0 }}>{title}</h3>
      {picked.length === 0 ? (
        <p className="muted">고른 {noun}이 없어요. 앱 홈에서 이 섹션이 숨겨져요.</p>
      ) : (
        <table>
          <tbody>
            {picked.map((item, index) => (
              <tr key={item.id} style={{ cursor: 'default' }}>
                <td style={{ width: 32 }}>
                  <strong>{index + 1}</strong>
                </td>
                {renderItem(item)}
                <td style={{ width: 1, whiteSpace: 'nowrap' }}>
                  <div className="row" style={{ gap: 6 }}>
                    <button
                      className="secondary small"
                      disabled={index === 0}
                      onClick={() => move(index, -1)}
                      aria-label="위로"
                    >
                      ↑
                    </button>
                    <button
                      className="secondary small"
                      disabled={index === picked.length - 1}
                      onClick={() => move(index, 1)}
                      aria-label="아래로"
                    >
                      ↓
                    </button>
                    <button
                      className="danger small"
                      onClick={() => change(ids.filter((id) => id !== item.id))}
                    >
                      빼기
                    </button>
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      <div className="field" style={{ marginTop: 16 }}>
        <label>{noun} 추가</label>
        <select
          value=""
          disabled={candidates.length === 0}
          onChange={(e) => {
            if (e.target.value) change([...ids, e.target.value])
          }}
        >
          <option value="">
            {candidates.length === 0 ? `추가할 ${noun}이 없어요` : `${noun}을 고르면 맨 아래에 붙어요`}
          </option>
          {candidates.map((item) => (
            <option key={item.id} value={item.id}>
              {optionLabel(item)}
            </option>
          ))}
        </select>
      </div>

      {error && <div className="error">{error}</div>}
      <div className="submit-row">
        <button onClick={submit} disabled={!dirty || saving}>
          {saving ? '저장 중…' : '저장'}
        </button>
        {dirty && (
          <button className="secondary" onClick={() => change(initialKey ? initialKey.split(',') : [])}>
            되돌리기
          </button>
        )}
        {saved && !dirty && <span className="muted">저장했어요.</span>}
      </div>
    </div>
  )
}
