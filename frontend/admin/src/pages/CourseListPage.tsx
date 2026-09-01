import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'

import { ApiError, listCourses, type Course } from '../api'

const DIFFICULTY_LABEL: Record<number, string> = { 1: '★', 2: '★★', 3: '★★★' }

export default function CourseListPage() {
  const [courses, setCourses] = useState<Course[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const navigate = useNavigate()

  useEffect(() => {
    listCourses()
      .then(setCourses)
      .catch((err: unknown) =>
        setError(err instanceof ApiError ? err.message : '코스 목록을 불러오지 못했어요.'),
      )
  }, [])

  return (
    <>
      <h2>코스 목록</h2>
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
              <th>태그</th>
              <th>완주</th>
            </tr>
          </thead>
          <tbody>
            {courses.map((course) => (
              <tr key={course.id} onClick={() => navigate(`/courses/${course.id}`)}>
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
                <td className="muted">{course.tags ?? '—'}</td>
                <td>{course.completed_count}명</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </>
  )
}
