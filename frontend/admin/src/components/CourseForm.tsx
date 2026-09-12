import type { Course, CourseUpdatePayload, CourseVisibility, Facility } from '../api'
import FacilityListEditor, { type FacilityDraft } from './FacilityListEditor'

/** 등록/수정이 공유하는 메타데이터 폼 값. 입력 중에는 전부 문자열로 들고,
 * 제출 시 validate()가 숫자 변환·필수값 검사를 한다. */
export interface CourseFormValues {
  name: string
  distanceKm: string
  difficulty: string
  /** '' | 'public' | 'admin'. 기본값 없음 — 제출 시 반드시 골라야 한다. */
  visibility: string
  address: string
  tags: string
  description: string
  estimatedTimeMin: string
  parkings: FacilityDraft[]
  restrooms: FacilityDraft[]
}

export function emptyValues(): CourseFormValues {
  return {
    name: '',
    distanceKm: '',
    difficulty: '1',
    visibility: '',
    address: '',
    tags: '',
    description: '',
    estimatedTimeMin: '',
    parkings: [],
    restrooms: [],
  }
}

export function valuesFromCourse(course: Course): CourseFormValues {
  const toDraft = (facility: Facility): FacilityDraft => ({
    name: facility.name ?? '',
    address: facility.address,
    lat: facility.lat,
    lng: facility.lng,
  })
  return {
    name: course.name,
    distanceKm: String(course.distance_km),
    difficulty: String(course.difficulty),
    visibility: course.visibility ?? '',
    address: course.address,
    tags: course.tags ?? '',
    description: course.description ?? '',
    estimatedTimeMin: course.estimated_time_min == null ? '' : String(course.estimated_time_min),
    parkings: course.parkings.map(toDraft),
    restrooms: course.restrooms.map(toDraft),
  }
}

export interface ValidatedCourseForm {
  name: string
  distanceKm: number
  difficulty: number
  visibility: CourseVisibility
  address: string
  tags: string
  description: string
  estimatedTimeMin: number | null
  parkings: Facility[]
  restrooms: Facility[]
}

/** 서버 규칙(app/schemas.py·admin/courses.py)과 같은 검사. 통과하면 변환된 값을,
 * 실패하면 message를 돌려준다. nameRequired: 등록은 GPX <name>으로 대신할 수 있어
 * 선택이고, 수정은 필수다. */
export function validate(
  values: CourseFormValues,
  { nameRequired }: { nameRequired: boolean },
): { ok: true; data: ValidatedCourseForm } | { ok: false; message: string } {
  if (nameRequired && !values.name.trim()) {
    return { ok: false, message: '이름을 입력해 주세요.' }
  }

  const distanceKm = Number(values.distanceKm)
  if (!Number.isInteger(distanceKm) || distanceKm < 1) {
    return { ok: false, message: '거리(km)는 1 이상의 정수여야 해요.' }
  }

  const difficulty = Number(values.difficulty)
  if (![1, 2, 3].includes(difficulty)) {
    return { ok: false, message: '난이도를 선택해 주세요.' }
  }

  const visibility = values.visibility
  if (visibility !== 'public' && visibility !== 'admin') {
    return { ok: false, message: '공개 범위를 선택해 주세요.' }
  }

  if (!values.address.trim()) {
    return { ok: false, message: '시작 지점 주소를 입력해 주세요.' }
  }

  let estimatedTimeMin: number | null = null
  if (values.estimatedTimeMin.trim()) {
    estimatedTimeMin = Number(values.estimatedTimeMin)
    if (!Number.isInteger(estimatedTimeMin) || estimatedTimeMin < 1) {
      return { ok: false, message: '예상 소요시간(분)은 1 이상의 정수여야 해요.' }
    }
  }

  const convertFacilities = (
    drafts: FacilityDraft[],
    label: string,
  ): Facility[] | string => {
    const result: Facility[] = []
    for (const draft of drafts) {
      if (!draft.address.trim() && !draft.name.trim()) continue // 빈 줄은 버린다.
      if (!draft.address.trim()) return `${label}의 주소가 비어 있어요.`
      if (draft.lat == null || draft.lng == null) {
        return `${label} "${draft.address}"의 좌표를 확인해 주세요("좌표 확인" 버튼).`
      }
      result.push({
        name: draft.name.trim() || null,
        address: draft.address.trim(),
        lat: draft.lat,
        lng: draft.lng,
      })
    }
    return result
  }

  const parkings = convertFacilities(values.parkings, '주차장')
  if (typeof parkings === 'string') return { ok: false, message: parkings }
  const restrooms = convertFacilities(values.restrooms, '화장실')
  if (typeof restrooms === 'string') return { ok: false, message: restrooms }

  return {
    ok: true,
    data: {
      name: values.name.trim(),
      distanceKm,
      difficulty,
      visibility,
      address: values.address.trim(),
      tags: normalizeTags(values.tags),
      description: values.description.trim(),
      estimatedTimeMin,
      parkings,
      restrooms,
    },
  }
}

/** "a, b,, c " → "a,b,c" — 서버는 쉼표 구분 문자열 하나를 저장한다. */
function normalizeTags(raw: string): string {
  return raw
    .split(',')
    .map((tag) => tag.trim())
    .filter((tag) => tag.length > 0)
    .join(',')
}

export function toUpdatePayload(data: ValidatedCourseForm): CourseUpdatePayload {
  return {
    name: data.name,
    distance_km: data.distanceKm,
    difficulty: data.difficulty,
    visibility: data.visibility,
    address: data.address,
    tags: data.tags || null,
    description: data.description || null,
    estimated_time_min: data.estimatedTimeMin,
    parkings: data.parkings,
    restrooms: data.restrooms,
  }
}

interface Props {
  values: CourseFormValues
  onChange: (values: CourseFormValues) => void
  /** 등록 폼이면 true — 이름이 선택값이 되고 힌트가 달라진다. */
  nameOptional?: boolean
}

export default function CourseForm({ values, onChange, nameOptional = false }: Props) {
  const set = <K extends keyof CourseFormValues>(key: K, value: CourseFormValues[K]) =>
    onChange({ ...values, [key]: value })

  return (
    <>
      <div className="field">
        <label htmlFor="course-name">
          이름
          {nameOptional && <span className="hint">비우면 GPX 파일의 &lt;name&gt;을 쓴다</span>}
        </label>
        <input
          id="course-name"
          value={values.name}
          onChange={(event) => set('name', event.target.value)}
        />
      </div>

      <div className="row">
        <div className="field">
          <label htmlFor="course-distance">
            거리(km) <span className="hint">왕복 안내값, 정수</span>
          </label>
          <input
            id="course-distance"
            type="number"
            min={1}
            value={values.distanceKm}
            onChange={(event) => set('distanceKm', event.target.value)}
          />
        </div>
        <div className="field">
          <label htmlFor="course-difficulty">난이도</label>
          <select
            id="course-difficulty"
            value={values.difficulty}
            onChange={(event) => set('difficulty', event.target.value)}
          >
            <option value="1">★ (쉬움)</option>
            <option value="2">★★ (보통)</option>
            <option value="3">★★★ (어려움)</option>
          </select>
        </div>
        <div className="field">
          <label htmlFor="course-visibility">
            공개 범위 <span className="hint">운영자만은 테스트용</span>
          </label>
          <select
            id="course-visibility"
            value={values.visibility}
            onChange={(event) => set('visibility', event.target.value)}
          >
            <option value="">선택</option>
            <option value="public">전체 공개</option>
            <option value="admin">운영자만</option>
          </select>
        </div>
        <div className="field">
          <label htmlFor="course-time">
            예상 소요시간(분) <span className="hint">선택</span>
          </label>
          <input
            id="course-time"
            type="number"
            min={1}
            value={values.estimatedTimeMin}
            onChange={(event) => set('estimatedTimeMin', event.target.value)}
          />
        </div>
      </div>

      <div className="field">
        <label htmlFor="course-address">시작 지점 주소</label>
        <input
          id="course-address"
          value={values.address}
          onChange={(event) => set('address', event.target.value)}
        />
      </div>

      <div className="field">
        <label htmlFor="course-tags">
          태그 <span className="hint">쉼표로 구분 — 예: 해안도로,제주시</span>
        </label>
        <input
          id="course-tags"
          value={values.tags}
          onChange={(event) => set('tags', event.target.value)}
        />
      </div>

      <div className="field">
        <label htmlFor="course-description">
          설명 <span className="hint">선택</span>
        </label>
        <textarea
          id="course-description"
          value={values.description}
          onChange={(event) => set('description', event.target.value)}
        />
      </div>

      <FacilityListEditor
        label="주차장"
        items={values.parkings}
        onChange={(parkings) => set('parkings', parkings)}
      />
      <FacilityListEditor
        label="화장실"
        items={values.restrooms}
        onChange={(restrooms) => set('restrooms', restrooms)}
      />
    </>
  )
}
