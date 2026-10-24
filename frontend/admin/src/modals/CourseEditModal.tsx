import { useEffect, useRef, useState } from 'react'

import {
  addCourseImage,
  ApiError,
  deleteCourseThumbnail,
  getCourse,
  replaceCourseGpx,
  setCourseImages,
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
import { ImagesSection, ThumbnailSection } from '../components/ImageSections'
import Modal from '../components/Modal'

interface Props {
  courseId: string
  /** 등록 모달에서 이어서 열릴 때 상단에 보여줄 메시지. */
  initialNotice?: string
  onClose: () => void
  /** 저장/교체/삭제가 반영될 때마다 — 목록 새로고침용. */
  onChanged: () => void
}

export default function CourseEditModal({ courseId, initialNotice, onClose, onChanged }: Props) {
  const [course, setCourse] = useState<Course | null>(null)
  const [values, setValues] = useState<CourseFormValues | null>(null)
  const [loadError, setLoadError] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(initialNotice ?? null)
  const bodyRef = useRef<HTMLDivElement | null>(null)

  useEffect(() => {
    getCourse(courseId)
      .then((loaded) => {
        setCourse(loaded)
        setValues(valuesFromCourse(loaded))
      })
      .catch((err: unknown) =>
        setLoadError(err instanceof ApiError ? err.message : '코스를 불러오지 못했어요.'),
      )
  }, [courseId])

  // 경로·썸네일 저장. 아직 저장 안 한 메타데이터 입력은 건드리지 않는다.
  const applyMedia = (saved: Course, message: string) => {
    setCourse(saved)
    setNotice(message)
    onChanged()
    bodyRef.current?.scrollTo({ top: 0 })
  }

  // 메타데이터 저장 성공 시 서버 응답으로 입력값도 갈아끼운다 — 다음 저장의 기준값이 된다.
  const applySaved = (saved: Course, message: string) => {
    applyMedia(saved, message)
    setValues(valuesFromCourse(saved))
  }

  return (
    <Modal
      title={course ? `코스 수정 — ${course.name}` : '코스 수정'}
      onClose={onClose}
      bodyRef={bodyRef}
    >
      {loadError && <div className="error">{loadError}</div>}
      {!loadError && (!course || !values) && <p className="muted">불러오는 중…</p>}
      {course && values && (
        <>
          {notice && <div className="notice" style={{ marginTop: 0 }}>{notice}</div>}

          <MetaSection
            courseId={courseId}
            values={values}
            onChange={(next) => {
              setValues(next)
              setNotice(null)
            }}
            onSaved={applySaved}
          />
          <GpxSection courseId={courseId} onSaved={applyMedia} />
          <ThumbnailSection
            thumbnailUrl={course.thumbnail_url}
            upload={(file) => setCourseThumbnail(course.id, file)}
            remove={() => deleteCourseThumbnail(course.id)}
            onSaved={applyMedia}
          />
          <ImagesSection
            urls={course.image_urls}
            description="앱 코스 상세의 시작 버튼 아래에 옆으로 미는 사진 띠예요. 사진은 원본 비율 그대로 잘리지 않고 나와요."
            add={(file) => addCourseImage(course.id, file)}
            set={(urls) => setCourseImages(course.id, urls)}
            onSaved={applyMedia}
          />
        </>
      )}
    </Modal>
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
      if (validated.alert) window.alert(validated.message)
      else setError(validated.message)
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
          {saving ? '저장 중…' : '저장'}
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
        경로를 새 GPX로 교체합니다. 
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
