// 서버(FastAPI)와의 통신 전부. 동일 오리진 상대경로로 호출한다 —
// 운영은 FastAPI가 /admin-ui 를 서빙하고, 개발은 vite proxy가 8000으로 넘긴다.

export interface Facility {
  name: string | null
  address: string
  lat: number
  lng: number
}

export interface Course {
  id: string
  name: string
  distance_km: number
  difficulty: 1 | 2 | 3
  tags: string | null
  address: string
  parkings: Facility[]
  restrooms: Facility[]
  description: string | null
  estimated_time_min: number | null
  thumbnail_url: string | null
  completed_count: number
}

export interface GeocodeResult {
  address: string
  road_address: string | null
  lat: number
  lng: number
}

/** 수정(PATCH) 페이로드. 서버 CourseUpdate와 1:1. */
export interface CourseUpdatePayload {
  name: string
  distance_km: number
  difficulty: number
  address: string
  tags: string | null
  description: string | null
  estimated_time_min: number | null
  parkings: Facility[]
  restrooms: Facility[]
}

const API_KEY_STORAGE = 'adminApiKey'

export function getApiKey(): string {
  try {
    return localStorage.getItem(API_KEY_STORAGE) ?? ''
  } catch {
    return ''
  }
}

export function saveApiKey(value: string): void {
  try {
    localStorage.setItem(API_KEY_STORAGE, value)
  } catch {
    // localStorage를 못 쓰는 환경이면 매번 다시 입력하게 둔다.
  }
}

export class ApiError extends Error {
  constructor(
    readonly status: number,
    detail: string,
  ) {
    super(detail)
  }
}

async function request<T>(path: string, init: RequestInit = {}): Promise<T> {
  const headers = new Headers(init.headers)
  const key = getApiKey()
  if (key) headers.set('X-Admin-Api-Key', key)

  const response = await fetch(path, { ...init, headers })

  if (!response.ok) {
    let detail = `요청 실패 (HTTP ${response.status})`
    try {
      const body = await response.json()
      if (typeof body.detail === 'string') detail = body.detail
    } catch {
      // JSON이 아니면 기본 메시지를 쓴다.
    }
    if (response.status === 401) {
      detail = `API 키가 틀렸거나 비어 있어요. 상단에서 키를 확인해 주세요. (${detail})`
    }
    throw new ApiError(response.status, detail)
  }

  if (response.status === 204) return undefined as T
  return (await response.json()) as T
}

// 목록/상세도 /admin 경로를 쓴다 — 공개 GET /courses는 앱 로그인(JWT) 전용이다.
export function listCourses(): Promise<Course[]> {
  return request('/admin/courses')
}

export function getCourse(id: string): Promise<Course> {
  return request(`/admin/courses/${id}`)
}

export interface CourseCreateInput {
  file: File
  name: string
  distanceKm: number
  difficulty: number
  address: string
  tags: string
  description: string
  estimatedTimeMin: number | null
  parkings: Facility[]
  restrooms: Facility[]
}

export function createCourse(input: CourseCreateInput): Promise<Course> {
  const form = new FormData()
  form.set('file', input.file)
  form.set('distance_km', String(input.distanceKm))
  form.set('difficulty', String(input.difficulty))
  form.set('address', input.address)
  if (input.name.trim()) form.set('name', input.name.trim())
  if (input.tags.trim()) form.set('tags', input.tags.trim())
  if (input.description.trim()) form.set('description', input.description.trim())
  if (input.estimatedTimeMin != null) {
    form.set('estimated_time_min', String(input.estimatedTimeMin))
  }
  form.set('parkings', JSON.stringify(input.parkings))
  form.set('restrooms', JSON.stringify(input.restrooms))

  return request('/admin/courses/gpx', { method: 'POST', body: form })
}

export function updateCourse(
  id: string,
  payload: CourseUpdatePayload,
): Promise<Course> {
  return request(`/admin/courses/${id}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  })
}

export function replaceCourseGpx(
  id: string,
  file: File,
  resetRecords: boolean,
): Promise<Course> {
  const form = new FormData()
  form.set('file', file)
  form.set('reset_records', String(resetRecords))
  return request(`/admin/courses/${id}/gpx`, { method: 'PUT', body: form })
}

export function setCourseThumbnail(id: string, file: File): Promise<Course> {
  const form = new FormData()
  form.set('file', file)
  return request(`/admin/courses/${id}/thumbnail`, { method: 'PUT', body: form })
}

export function deleteCourseThumbnail(id: string): Promise<Course> {
  return request(`/admin/courses/${id}/thumbnail`, { method: 'DELETE' })
}

export function geocode(address: string): Promise<{ results: GeocodeResult[] }> {
  return request(`/admin/geo/geocode?address=${encodeURIComponent(address)}`)
}
