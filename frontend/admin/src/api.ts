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
  stamp_image_url: string | null
  completed_count: number
}

/** 공지. image_url이 있으면 앱 홈 상단 배너로도 실린다. */
export interface Notice {
  id: string
  title: string
  body: string
  image_url: string | null
  starts_at: string | null
  ends_at: string | null
  created_at: string
}

/** 등록/수정(전체 교체) 페이로드. 서버 NoticeCreate/NoticeUpdate와 1:1. */
export interface NoticePayload {
  title: string
  body: string
  starts_at: string | null
  ends_at: string | null
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

/** 운영자 신원. 로그인/세션확인(GET /admin/auth/me) 응답. */
export interface AdminIdentity {
  username: string
  display_name: string | null
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
  // credentials: 세션 쿠키(HttpOnly)를 요청에 실어 보낸다. 인증 정보는 쿠키가
  // 전부이고 JS는 토큰을 만지지 않는다 — 옛 API 키 헤더 방식을 대체했다.
  const response = await fetch(path, { ...init, credentials: 'include' })

  if (!response.ok) {
    let detail = `요청 실패 (HTTP ${response.status})`
    try {
      const body = await response.json()
      if (typeof body.detail === 'string') detail = body.detail
    } catch {
      // JSON이 아니면 기본 메시지를 쓴다.
    }
    throw new ApiError(response.status, detail)
  }

  if (response.status === 204) return undefined as T
  return (await response.json()) as T
}

// --- 세션 인증 ---------------------------------------------------------

/** 아이디/비밀번호로 로그인. 성공 시 서버가 세션 쿠키를 내려준다. */
export function login(username: string, password: string): Promise<AdminIdentity> {
  return request('/admin/auth/login', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username, password }),
  })
}

/** 로그아웃. 서버가 세션을 폐기하고 쿠키를 지운다. */
export function logout(): Promise<void> {
  return request('/admin/auth/logout', { method: 'POST' })
}

/** 현재 로그인 상태 확인. 세션이 없으면 401(ApiError)을 던진다. */
export function getMe(): Promise<AdminIdentity> {
  return request('/admin/auth/me')
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

export function setCourseStampImage(id: string, file: File): Promise<Course> {
  const form = new FormData()
  form.set('file', file)
  return request(`/admin/courses/${id}/stamp-image`, { method: 'PUT', body: form })
}

export function deleteCourseStampImage(id: string): Promise<Course> {
  return request(`/admin/courses/${id}/stamp-image`, { method: 'DELETE' })
}

// --- 공지 ---------------------------------------------------------------

/** 전체 목록(예약·만료 포함). 공개 GET /notices는 노출 중인 것만 주고 앱 JWT가 필요하다. */
export function listNotices(): Promise<Notice[]> {
  return request('/admin/notices')
}

export function createNotice(payload: NoticePayload): Promise<Notice> {
  return request('/admin/notices', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  })
}

export function updateNotice(id: string, payload: NoticePayload): Promise<Notice> {
  return request(`/admin/notices/${id}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  })
}

export function deleteNotice(id: string): Promise<void> {
  return request(`/admin/notices/${id}`, { method: 'DELETE' })
}

export function setNoticeImage(id: string, file: File): Promise<Notice> {
  const form = new FormData()
  form.set('file', file)
  return request(`/admin/notices/${id}/image`, { method: 'PUT', body: form })
}

export function deleteNoticeImage(id: string): Promise<Notice> {
  return request(`/admin/notices/${id}/image`, { method: 'DELETE' })
}

export function geocode(address: string): Promise<{ results: GeocodeResult[] }> {
  return request(`/admin/geo/geocode?address=${encodeURIComponent(address)}`)
}
