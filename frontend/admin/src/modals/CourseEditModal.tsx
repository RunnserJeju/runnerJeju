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
import {
  ImageSection,
  ImagesSection,
  imageChanged,
  imagesChanged,
  imagesFrom,
  NO_IMAGE_CHANGE,
  type ImageChange,
  type ImagesChange,
} from '../components/ImageSections'
import Modal from '../components/Modal'
import SaveFooter from '../components/SaveFooter'
import { runSteps, snapshot, type SaveStep } from '../utils/saveSteps'

interface Props {
  courseId: string
  /** 등록 모달에서 이어서 열릴 때 상단에 보여줄 메시지. */
  initialNotice?: string
  onClose: () => void
  /** 저장이 반영될 때 — 목록 새로고침용. */
  onChanged: () => void
}

interface GpxChange {
  file: File | null
  /** 이 코스로 달린 기록이 있어도 초기화하고 교체. */
  resetRecords: boolean
}

export default function CourseEditModal({ courseId, initialNotice, onClose, onChanged }: Props) {
  const [course, setCourse] = useState<Course | null>(null)
  const [values, setValues] = useState<CourseFormValues | null>(null)
  /** 서버에 저장된 메타데이터의 스냅샷. values와 다르면 '메타데이터 변경'이다. */
  const [savedKey, setSavedKey] = useState('')
  const [thumb, setThumb] = useState<ImageChange>(NO_IMAGE_CHANGE)
  const [images, setImages] = useState<ImagesChange>(imagesFrom([]))
  const [gpx, setGpx] = useState<GpxChange>({ file: null, resetRecords: false })
  const [gpxInputKey, setGpxInputKey] = useState(0)
  const [loadError, setLoadError] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(initialNotice ?? null)
  const [error, setError] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)
  const bodyRef = useRef<HTMLDivElement | null>(null)

  useEffect(() => {
    getCourse(courseId)
      .then((loaded) => {
        const loadedValues = valuesFromCourse(loaded)
        setCourse(loaded)
        setValues(loadedValues)
        setSavedKey(snapshot(loadedValues))
        setImages(imagesFrom(loaded.image_urls))
      })
      .catch((err: unknown) =>
        setLoadError(err instanceof ApiError ? err.message : '코스를 불러오지 못했어요.'),
      )
  }, [courseId])

  const metaDirty = values != null && snapshot(values) !== savedKey
  const thumbDirty = imageChanged(thumb)
  const imagesDirty = course != null && imagesChanged(course.image_urls, images)
  const gpxDirty = gpx.file != null
  const dirty = [
    metaDirty && '메타데이터',
    gpxDirty && '경로(GPX)',
    thumbDirty && '썸네일',
    imagesDirty && '추가 이미지',
  ].filter((label): label is string => Boolean(label))

  /** 서버 응답으로 화면의 '저장된 값'을 갈아끼운다. */
  const adopt = (saved: Course, refreshValues: boolean) => {
    setCourse(saved)
    if (refreshValues) {
      const next = valuesFromCourse(saved)
      setValues(next)
      setSavedKey(snapshot(next))
    }
  }

  const save = async () => {
    if (!course || !values || dirty.length === 0) return
    setError(null)
    setNotice(null)

    // 호출 전에 메타데이터 검증부터 — 틀렸으면 아무것도 저장하지 않는다.
    let payload: ReturnType<typeof toUpdatePayload> | null = null
    if (metaDirty) {
      const validated = validate(values, { nameRequired: true })
      if (!validated.ok) {
        if (validated.alert) window.alert(validated.message)
        else setError(validated.message)
        return
      }
      payload = toUpdatePayload(validated.data)
    }
    if (gpx.file && gpx.resetRecords) {
      const ok = window.confirm(
        '경로를 바꾸면 이 코스의 완주 스탬프와 검증 기록이 초기화돼요(개인 러닝 기록은 유지). 계속할까요?',
      )
      if (!ok) return
    }

    // 바뀐 것만 호출한다. 메타데이터 → 경로 순서: 경로 교체가 거리를 다시 계산할 수 있어
    // 경로 결과가 마지막에 남게 한다.
    const steps: SaveStep[] = []
    if (payload) {
      const body = payload
      steps.push({
        label: '메타데이터',
        run: async () => adopt(await updateCourse(courseId, body), true),
      })
    }
    if (gpx.file) {
      const { file, resetRecords } = gpx
      steps.push({
        label: '경로(GPX)',
        run: async () => {
          try {
            adopt(await replaceCourseGpx(courseId, file, resetRecords), true)
          } catch (err) {
            if (err instanceof ApiError && err.status === 409) {
              throw new Error(
                '이 코스로 달린 기록이 있어요. 경로 카드의 "기록 초기화" 체크 후 다시 저장해 주세요.',
              )
            }
            throw err
          }
          setGpx({ file: null, resetRecords: false })
          setGpxInputKey((key) => key + 1)
        },
      })
    }
    if (thumbDirty) {
      const { file } = thumb
      steps.push({
        label: '썸네일',
        run: async () => {
          adopt(
            file ? await setCourseThumbnail(courseId, file) : await deleteCourseThumbnail(courseId),
            false,
          )
          setThumb(NO_IMAGE_CHANGE)
        },
      })
    }
    if (imagesDirty) {
      const keep = images.urls
      if (imagesChanged(course.image_urls, { urls: keep, added: [] })) {
        steps.push({
          label: '추가 이미지 순서·삭제',
          run: async () => {
            const saved = await setCourseImages(courseId, keep)
            adopt(saved, false)
            setImages((prev) => ({ ...prev, urls: saved.image_urls }))
          },
        })
      }
      for (const file of images.added) {
        steps.push({
          label: `추가 이미지(${file.name})`,
          run: async () => {
            const saved = await addCourseImage(courseId, file)
            adopt(saved, false)
            setImages((prev) => ({
              urls: saved.image_urls,
              added: prev.added.filter((f) => f !== file),
            }))
          },
        })
      }
    }

    setSaving(true)
    const failure = await runSteps(steps)
    setSaving(false)
    onChanged()
    if (failure) {
      setError(failure)
      return
    }
    setNotice('저장했어요.')
    bodyRef.current?.scrollTo({ top: 0 })
  }

  return (
    <Modal
      title={course ? `코스 수정 — ${course.name}` : '코스 수정'}
      onClose={onClose}
      closable={!saving}
      bodyRef={bodyRef}
      footer={
        course && values ? (
          <SaveFooter dirty={dirty} saving={saving} error={error} onSave={save} />
        ) : undefined
      }
    >
      {loadError && <div className="error">{loadError}</div>}
      {!loadError && (!course || !values) && <p className="muted">불러오는 중…</p>}
      {course && values && (
        <>
          {notice && <div className="notice" style={{ marginTop: 0 }}>{notice}</div>}

          <div className="card">
            <h3 style={{ marginTop: 0 }}>메타데이터</h3>
            <CourseForm
              values={values}
              onChange={(next) => {
                setValues(next)
                setNotice(null)
              }}
            />
          </div>

          <div className="card">
            <h3 style={{ marginTop: 0 }}>경로(GPX) 교체</h3>
            <p className="muted">
              새 GPX 파일을 고르고 우측 아래 '전체 저장'을 누르면 경로가 교체돼요.
            </p>
            <div className="field">
              <input
                key={gpxInputKey}
                type="file"
                accept=".gpx,application/gpx+xml"
                onChange={(event) =>
                  setGpx({ file: event.target.files?.[0] ?? null, resetRecords: false })
                }
              />
            </div>
            {gpx.file && (
              <label className="field">
                <input
                  type="checkbox"
                  checked={gpx.resetRecords}
                  onChange={(event) => setGpx({ ...gpx, resetRecords: event.target.checked })}
                />{' '}
                기록 초기화 <span className="hint">
                  이 코스로 달린 기록이 있으면 완주 스탬프·검증 기록이 초기화돼요(개인 러닝 기록은 유지).
                  기록이 있는데 체크하지 않으면 저장이 막혀요.
                </span>
              </label>
            )}
          </div>

          <ImageSection
            title="썸네일"
            currentUrl={course.thumbnail_url}
            value={thumb}
            onChange={setThumb}
          />
          <ImagesSection
            description="앱 코스 상세의 시작 버튼 아래에 옆으로 미는 사진 띠예요. 사진은 원본 비율 그대로 잘리지 않고 나와요."
            value={images}
            onChange={setImages}
          />
        </>
      )}
    </Modal>
  )
}
