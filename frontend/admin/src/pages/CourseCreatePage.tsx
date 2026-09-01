import { useState } from 'react'
import { useNavigate } from 'react-router-dom'

import { ApiError, createCourse, setCourseThumbnail } from '../api'
import CourseForm, { emptyValues, validate } from '../components/CourseForm'

export default function CourseCreatePage() {
  const [values, setValues] = useState(emptyValues)
  const [gpxFile, setGpxFile] = useState<File | null>(null)
  const [thumbnailFile, setThumbnailFile] = useState<File | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [submitting, setSubmitting] = useState(false)
  const navigate = useNavigate()

  const submit = async () => {
    setError(null)

    if (!gpxFile) {
      setError('GPX 파일을 선택해 주세요.')
      return
    }
    const validated = validate(values, { nameRequired: false })
    if (!validated.ok) {
      setError(validated.message)
      return
    }

    setSubmitting(true)
    try {
      const course = await createCourse({
        file: gpxFile,
        name: validated.data.name,
        distanceKm: validated.data.distanceKm,
        difficulty: validated.data.difficulty,
        address: validated.data.address,
        tags: validated.data.tags,
        description: validated.data.description,
        estimatedTimeMin: validated.data.estimatedTimeMin,
        parkings: validated.data.parkings,
        restrooms: validated.data.restrooms,
      })

      // 썸네일은 등록과 분리된 전용 엔드포인트다(docs/admin-web.md). 등록이 성공한
      // 뒤에 올리고, 실패해도 코스는 이미 만들어졌으므로 수정 화면에서 재시도한다.
      if (thumbnailFile) {
        try {
          await setCourseThumbnail(course.id, thumbnailFile)
        } catch (thumbError) {
          navigate(`/courses/${course.id}`, {
            state: {
              notice: `코스는 등록됐지만 썸네일 업로드에 실패했어요: ${
                thumbError instanceof ApiError ? thumbError.message : '알 수 없는 오류'
              }`,
            },
          })
          return
        }
      }
      navigate(`/courses/${course.id}`, { state: { notice: '코스를 등록했어요.' } })
    } catch (err) {
      setError(err instanceof ApiError ? err.message : '등록에 실패했어요.')
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <>
      <h2>새 코스 등록</h2>
      <div className="card">
        <div className="field">
          <label htmlFor="gpx-file">GPX 파일 (필수)</label>
          <input
            id="gpx-file"
            type="file"
            accept=".gpx,application/gpx+xml"
            onChange={(event) => setGpxFile(event.target.files?.[0] ?? null)}
          />
        </div>

        <CourseForm values={values} onChange={setValues} nameOptional />

        <div className="field">
          <label htmlFor="thumbnail-file">
            썸네일 <span className="hint">선택 — jpg/png/webp, 8MB 이하. 등록 직후 업로드된다</span>
          </label>
          <input
            id="thumbnail-file"
            type="file"
            accept="image/jpeg,image/png,image/webp"
            onChange={(event) => setThumbnailFile(event.target.files?.[0] ?? null)}
          />
        </div>

        {error && <div className="error">{error}</div>}

        <div className="submit-row">
          <button onClick={submit} disabled={submitting}>
            {submitting ? '등록 중…' : '코스 등록'}
          </button>
        </div>
      </div>
    </>
  )
}
