import { useCallback, useEffect, useState } from 'react'

import { ApiError, listCourses, type Course } from '../api'
import CourseCreateModal from '../modals/CourseCreateModal'
import CourseEditModal from '../modals/CourseEditModal'

const DIFFICULTY_LABEL: Record<number, string> = { 1: '★', 2: '★★', 3: '★★★' }
const VISIBILITY_LABEL = { public: '전체', admin: '운영자만' } as const

interface Props {
  /** 목록 로딩이 401이면(키 폐기 등) 인증 화면으로 되돌린다. */
  onUnauthorized: () => void
}

export default function CourseListPage({ onUnauthorized }: Props) {
  const [courses, setCourses] = useState<Course[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [creating, setCreating] = useState(false)
  /** 수정 모달 대상. notice는 등록 직후 이어서 열 때 전달된다. */
  const [editing, setEditing] = useState<{ id: string; notice?: string } | null>(null)

  const reload = useCallback(() => {
    listCourses()
      .then((loaded) => {
        setCourses(loaded)
        setError(null)
      })
      .catch((err: unknown) => {
        if (err instanceof ApiError && err.status === 401) {
          onUnauthorized()
          return
        }
        setError(err instanceof ApiError ? err.message : '코스 목록을 불러오지 못했어요.')
      })
  }, [onUnauthorized])

  useEffect(() => {
    reload()
  }, [reload])

  return (
    <>
      <div className="page-head">
        <h2>코스 목록</h2>
        <button onClick={() => setCreating(true)}>+ 코스 추가</button>
      </div>
      {error && <div className="error">{error}</div>}
      {courses == null && !error && <p className="muted">불러오는 중…</p>}
      {courses && courses.length === 0 && <p className="muted">등록된 코스가 없어요.</p>}
      {courses && courses.length > 0 && (
        <table>
          <thead>
            <tr>
              <th></th>
              <th>이름</th>
              <th>거리</th>
              <th>난이도</th>
              <th>공개</th>
              <th>태그</th>
              <th>완주</th>
            </tr>
          </thead>
          <tbody>
            {courses.map((course) => (
              <tr key={course.id} onClick={() => setEditing({ id: course.id })}>
                <td style={{ width: 56 }}>
                  {course.thumbnail_url ? (
                    <img className="thumb" src={course.thumbnail_url} alt="" />
                  ) : (
                    <div className="thumb placeholder">없음</div>
                  )}
                </td>
                <td>
                  <strong>{course.name}</strong>
                  <div className="muted">{course.address}</div>
                </td>
                <td>{course.distance_km}km</td>
                <td>{DIFFICULTY_LABEL[course.difficulty]}</td>
                <td className={course.visibility === 'public' ? undefined : 'muted'}>
                  {course.visibility ? VISIBILITY_LABEL[course.visibility] : '미설정'}
                </td>
                <td className="muted">{course.tags ?? '—'}</td>
                <td>{course.completed_count}명</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      {creating && (
        <CourseCreateModal
          onClose={() => setCreating(false)}
          onCreated={(course, notice) => {
            setCreating(false)
            reload()
            // 등록 직후 수정 모달을 이어서 열어 결과를 바로 확인/보완하게 한다.
            setEditing({ id: course.id, notice })
          }}
        />
      )}
      {editing && (
        <CourseEditModal
          courseId={editing.id}
          initialNotice={editing.notice}
          onClose={() => setEditing(null)}
          onChanged={reload}
        />
      )}
    </>
  )
}
