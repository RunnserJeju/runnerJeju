import { useEffect, useState } from 'react'
import { useLocation, useParams } from 'react-router-dom'

import {
  ApiError,
  deleteCourseThumbnail,
  getCourse,
  replaceCourseGpx,
  setCourseThumbnail,
  updateCourse,
  type Course,
} from '../api'
import CourseForm, {
  toUpdatePayload,
  validate,
  valuesFromCourse,
  type CourseFormValues,
} from '../components/CourseForm'

export default function CourseEditPage() {
  const { id } = useParams<{ id: string }>()
  const location = useLocation()

  const [course, setCourse] = useState<Course | null>(null)
  const [values, setValues] = useState<CourseFormValues | null>(null)
  const [loadError, setLoadError] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(
    (location.state as { notice?: string } | null)?.notice ?? null,
  )

  useEffect(() => {
    if (!id) return
    getCourse(id)
      .then((loaded) => {
        setCourse(loaded)
        setValues(valuesFromCourse(loaded))
      })
      .catch((err: unknown) =>
        setLoadError(err instanceof ApiError ? err.message : '코스를 불러오지 못했어요.'),
      )
  }, [id])

  if (loadError) return <div className="error">{loadError}</div>
  if (!id || !course || !values) return <p className="muted">불러오는 중…</p>

  // 저장 성공 시 서버 응답으로 화면 상태를 갈아끼운다 — 다음 저장의 기준값이 된다.
  const applySaved = (saved: Course, message: string) => {
    setCourse(saved)
    setValues(valuesFromCourse(saved))
    setNotice(message)
    window.scrollTo({ top: 0 })
  }

  return (
    <>
      <h2>코스 수정 — {course.name}</h2>
      {notice && <div className="notice">{notice}</div>}

      <MetaSection
        courseId={id}
        values={values}
        onChange={(next) => {
          setValues(next)
          setNotice(null)
        }}
        onSaved={applySaved}
      />
      <GpxSection courseId={id} onSaved={applySaved} />
      <ThumbnailSection course={course} onSaved={applySaved} />
    </>
  )
}

function MetaSection({
  courseId,
  values,
  onChange,
  onSaved,
}: {
  courseId: string
  values: CourseFormValues
  onChange: (values: CourseFormValues) => void
  onSaved: (course: Course, message: string) => void
}) {
  const [error, setError] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)

  const save = async () => {
    setError(null)
    const validated = validate(values, { nameRequired: true })
    if (!validated.ok) {
      setError(validated.message)
      return
    }
    setSaving(true)
    try {
      const saved = await updateCourse(courseId, toUpdatePayload(validated.data))
      onSaved(saved, '메타데이터를 저장했어요.')
    } catch (err) {
      setError(err instanceof ApiError ? err.message : '저장에 실패했어요.')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="card">
      <h3 style={{ marginTop: 0 }}>메타데이터</h3>
      <CourseForm values={values} onChange={onChange} />
      {error && <div className="error">{error}</div>}
      <div className="submit-row">
        <button onClick={save} disabled={saving}>
          {saving ? '저장 중…' : '메타데이터 저장'}
        </button>
      </div>
    </div>
  )
}

function GpxSection({
  courseId,
  onSaved,
}: {
  courseId: string
  onSaved: (course: Course, message: string) => void
}) {
  const [file, setFile] = useState<File | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)
  /** 409를 받아 "기록 초기화" 확인을 기다리는 중인지. */
  const [needsConfirm, setNeedsConfirm] = useState(false)

  const replace = async (resetRecords: boolean) => {
    if (!file) {
      setError('새 GPX 파일을 선택해 주세요.')
      return
    }
    setError(null)
    setSaving(true)
    try {
      const saved = await replaceCourseGpx(courseId, file, resetRecords)
      setNeedsConfirm(false)
      setFile(null)
      onSaved(saved, '경로를 교체했어요.')
    } catch (err) {
      if (err instanceof ApiError && err.status === 409) {
        // 이 코스로 달린 기록이 있다 — 초기화에 동의해야 진행된다(서버 계약).
        setNeedsConfirm(true)
      } else {
        setError(err instanceof ApiError ? err.message : '경로 교체에 실패했어요.')
      }
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="card">
      <h3 style={{ marginTop: 0 }}>경로(GPX) 교체</h3>
      <p className="muted">
        경로만 새 GPX로 갈아끼운다. 메타데이터·썸네일은 그대로 둔다.
      </p>
      <div className="field">
        <input
          type="file"
          accept=".gpx,application/gpx+xml"
          onChange={(event) => {
            setFile(event.target.files?.[0] ?? null)
            setNeedsConfirm(false)
          }}
        />
      </div>
      {error && <div className="error">{error}</div>}
      {needsConfirm ? (
        <div className="confirm">
          <strong>이 코스로 달린 기록이 있어요.</strong> 경로를 바꾸면 완주 스탬프와
          검증 기록이 초기화돼요(개인 러닝 기록은 유지). 계속할까요?
          <div className="actions">
            <button className="danger" onClick={() => replace(true)} disabled={saving}>
              {saving ? '교체 중…' : '초기화하고 교체'}
            </button>
            <button className="secondary" onClick={() => setNeedsConfirm(false)} disabled={saving}>
              취소
            </button>
          </div>
        </div>
      ) : (
        <div className="submit-row">
          <button onClick={() => replace(false)} disabled={saving || !file}>
            {saving ? '교체 중…' : '경로 교체'}
          </button>
        </div>
      )}
    </div>
  )
}

function ThumbnailSection({
  course,
  onSaved,
}: {
  course: Course
  onSaved: (course: Course, message: string) => void
}) {
  const [file, setFile] = useState<File | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)

  const upload = async () => {
    if (!file) {
      setError('이미지 파일을 선택해 주세요.')
      return
    }
    setError(null)
    setSaving(true)
    try {
      const saved = await setCourseThumbnail(course.id, file)
      setFile(null)
      onSaved(saved, '썸네일을 저장했어요.')
    } catch (err) {
      setError(err instanceof ApiError ? err.message : '썸네일 업로드에 실패했어요.')
    } finally {
      setSaving(false)
    }
  }

  const remove = async () => {
    setError(null)
    setSaving(true)
    try {
      const saved = await deleteCourseThumbnail(course.id)
      onSaved(saved, '썸네일을 지웠어요.')
    } catch (err) {
      setError(err instanceof ApiError ? err.message : '썸네일 삭제에 실패했어요.')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="card">
      <h3 style={{ marginTop: 0 }}>썸네일</h3>
      {course.thumbnail_url ? (
        <img className="thumb large" src={course.thumbnail_url} alt="현재 썸네일" />
      ) : (
        <p className="muted">등록된 썸네일이 없어요.</p>
      )}
      <div className="field" style={{ marginTop: 12 }}>
        <input
          type="file"
          accept="image/jpeg,image/png,image/webp"
          onChange={(event) => setFile(event.target.files?.[0] ?? null)}
        />
      </div>
      {error && <div className="error">{error}</div>}
      <div className="submit-row">
        <button onClick={upload} disabled={saving || !file}>
          {saving ? '처리 중…' : course.thumbnail_url ? '썸네일 교체' : '썸네일 등록'}
        </button>
        {course.thumbnail_url && (
          <button className="danger" onClick={remove} disabled={saving}>
            썸네일 삭제
          </button>
        )}
      </div>
    </div>
  )
}
