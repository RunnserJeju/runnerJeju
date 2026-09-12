import { useState } from 'react'

import {
  ApiError,
  createCourse,
  setCourseStampImage,
  setCourseThumbnail,
  type Course,
} from '../api'
import CourseForm, { emptyValues, validate } from '../components/CourseForm'
import { STAMP_SPEC, validateStampImage } from '../components/imageSpec'
import Modal from '../components/Modal'

interface Props {
  onClose: () => void
  /** 등록 성공. notice는 수정 모달로 이어서 보여줄 메시지. */
  onCreated: (course: Course, notice: string) => void
}

export default function CourseCreateModal({ onClose, onCreated }: Props) {
  const [values, setValues] = useState(emptyValues)
  const [gpxFile, setGpxFile] = useState<File | null>(null)
  const [thumbnailFile, setThumbnailFile] = useState<File | null>(null)
  const [stampFile, setStampFile] = useState<File | null>(null)
  const [stampError, setStampError] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [submitting, setSubmitting] = useState(false)

  // 고르는 순간 규격을 검사해 틀린 파일은 선택 자체를 무효로 한다.
  const pickStamp = async (picked: File | null) => {
    setStampError(null)
    if (!picked) {
      setStampFile(null)
      return
    }
    const problem = await validateStampImage(picked)
    if (problem) {
      setStampError(problem)
      setStampFile(null)
      return
    }
    setStampFile(picked)
  }

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
        visibility: validated.data.visibility,
        address: validated.data.address,
        tags: validated.data.tags,
        description: validated.data.description,
        estimatedTimeMin: validated.data.estimatedTimeMin,
        parkings: validated.data.parkings,
        restrooms: validated.data.restrooms,
      })

      // 썸네일·스탬프 도안은 등록과 분리된 전용 엔드포인트다(docs/admin-web.md).
      // 등록이 성공한 뒤에 올리고, 실패해도 코스는 이미 만들어졌으므로 수정 모달에서
      // 재시도한다. 하나가 실패해도 나머지는 계속 올린다.
      const failures: string[] = []
      const uploads: [File | null, string, (id: string, f: File) => Promise<Course>][] = [
        [thumbnailFile, '썸네일', setCourseThumbnail],
        [stampFile, '스탬프 도안', setCourseStampImage],
      ]
      for (const [file, label, send] of uploads) {
        if (!file) continue
        try {
          await send(course.id, file)
        } catch (uploadError) {
          failures.push(
            `${label}: ${uploadError instanceof ApiError ? uploadError.message : '알 수 없는 오류'}`,
          )
        }
      }
      onCreated(
        course,
        failures.length
          ? `코스는 등록됐지만 이미지 업로드에 실패했어요 — ${failures.join(' / ')}`
          : '코스를 등록했어요.',
      )
    } catch (err) {
      setError(err instanceof ApiError ? err.message : '등록에 실패했어요.')
      setSubmitting(false)
    }
  }

  return (
    <Modal title="새 코스 등록" onClose={onClose} closable={!submitting}>
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

        <div className="field">
          <label htmlFor="stamp-file">
            완주 스탬프 도안 <span className="hint">선택 — {STAMP_SPEC.hint}</span>
          </label>
          <input
            id="stamp-file"
            type="file"
            accept="image/jpeg,image/png,image/webp"
            onChange={(event) => pickStamp(event.target.files?.[0] ?? null)}
          />
          {stampError && <div className="error">{stampError}</div>}
        </div>

        {error && <div className="error">{error}</div>}

        <div className="submit-row">
          <button onClick={submit} disabled={submitting}>
            {submitting ? '등록 중…' : '코스 등록'}
          </button>
        </div>
      </div>
    </Modal>
  )
}
