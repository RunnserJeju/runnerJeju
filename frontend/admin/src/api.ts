// 서버(FastAPI)와의 통신 전부. 동일 오리진 상대경로로 호출한다 —
// 운영은 FastAPI가 /admin-ui 를 서빙하고, 개발은 vite proxy가 8000으로 넘긴다.

export interface Facility {
  name: string | null
  address: string
  lat: number
  lng: number
}

/** 협력업체(코스 응답에 실리는 형태). 서버 PartnerSummary와 1:1. */
export interface PartnerSummary {
  id: string
  name: string
  address: string | null
  lat: number
  lng: number
  comment: string | null
  instagram: string | null
  benefit: string | null
  detail: Record<string, unknown>
}

/** 협력업체 관리 화면용. 서버 PartnerOut과 1:1. */
export interface Partner extends PartnerSummary {
  /** 연결된 코스 수. 삭제 경고에 쓴다. */
  course_count: number
  /** 이 업체에서 사용된 쿠폰 수(업체 이용률). */
  coupon_used_count: number
  created_at: string
  updated_at: string
}

/** 협력업체 등록/수정(전체 교체) 페이로드. 서버 PartnerPayload와 1:1. */
export interface PartnerPayload {
  name: string
  address: string | null
  lat: number
  lng: number
  comment: string | null
  instagram: string | null
  benefit: string | null
  detail: Record<string, unknown>
}

/** 공개 범위. null은 미설정(시드 스크립트로 올린 코스) — 앱에는 안 보인다. */
export type CourseVisibility = 'public' | 'admin'

export interface Course {
  id: string
  name: string
  distance_km: number
  difficulty: 1 | 2 | 3
  visibility: CourseVisibility | null
  tags: string | null
  address: string
  parkings: Facility[]
  restrooms: Facility[]
  partners: PartnerSummary[]
  description: string | null
  estimated_time_min: number | null
  thumbnail_url: string | null
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
  visibility: CourseVisibility
  address: string
  tags: string | null
  description: string | null
  estimated_time_min: number | null
  parkings: Facility[]
  restrooms: Facility[]
  /** 연결할 협력업체 id(보여줄 순서대로). 통째로 교체된다. */
  partner_ids: string[]
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
  visibility: CourseVisibility
  address: string
  tags: string
  description: string
  estimatedTimeMin: number | null
  parkings: Facility[]
  restrooms: Facility[]
  partnerIds: string[]
}

export function createCourse(input: CourseCreateInput): Promise<Course> {
  const form = new FormData()
  form.set('file', input.file)
  form.set('distance_km', String(input.distanceKm))
  form.set('difficulty', String(input.difficulty))
  form.set('visibility', input.visibility)
  form.set('address', input.address)
  if (input.name.trim()) form.set('name', input.name.trim())
  if (input.tags.trim()) form.set('tags', input.tags.trim())
  if (input.description.trim()) form.set('description', input.description.trim())
  if (input.estimatedTimeMin != null) {
    form.set('estimated_time_min', String(input.estimatedTimeMin))
  }
  form.set('parkings', JSON.stringify(input.parkings))
  form.set('restrooms', JSON.stringify(input.restrooms))
  form.set('partner_ids', JSON.stringify(input.partnerIds))

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

// --- 스탬프 -------------------------------------------------------------

/** 획득 조건 종류. 서버 app/stamp_rules.CONDITION_TYPES와 같아야 한다. */
export type StampConditionType = 'course_complete' | 'manual'

/** 스탬프 종류. 코스 완주는 조건의 하나(course_complete {course_id})다. */
export interface StampDefinition {
  id: string
  name: string
  description: string | null
  image_url: string | null
  condition_type: StampConditionType
  condition_params: { course_id?: string }
  is_active: boolean
  sort_order: number
  issued_count: number
  created_at: string
  updated_at: string
}

export interface StampDefinitionPayload {
  name: string
  description: string | null
  condition_type: StampConditionType
  condition_params: { course_id?: string }
  is_active: boolean
  sort_order: number
}

export function listStamps(): Promise<StampDefinition[]> {
  return request('/admin/stamps')
}

export function createStamp(payload: StampDefinitionPayload): Promise<StampDefinition> {
  return request('/admin/stamps', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  })
}

export function updateStamp(
  id: string,
  payload: StampDefinitionPayload,
): Promise<StampDefinition> {
  return request(`/admin/stamps/${id}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  })
}

export function setStampImage(id: string, file: File): Promise<StampDefinition> {
  const form = new FormData()
  form.set('file', file)
  return request(`/admin/stamps/${id}/image`, { method: 'PUT', body: form })
}

export function deleteStampImage(id: string): Promise<StampDefinition> {
  return request(`/admin/stamps/${id}/image`, { method: 'DELETE' })
}

// --- 러닝위크 -----------------------------------------------------------

export const BINGO_CELLS = 25

/** 러닝위크 회차. 공개 규칙은 공지와 같고, 공개 중이면 앱 커뮤니티 상단에 배너가 뜬다. */
export interface RunningWeek {
  id: string
  title: string
  description: string | null
  image_url: string | null
  starts_at: string | null
  ends_at: string | null
  is_active: boolean
  /** 칸 0~24에 놓은 스탬프 종류 id. 비어 있으면 빙고판을 아직 안 짠 것. */
  bingo_stamp_ids: string[]
  participant_count: number
  created_at: string
  updated_at: string
}

export interface RunningWeekPayload {
  title: string
  description: string | null
  starts_at: string | null
  ends_at: string | null
  is_active: boolean
}

export interface Participation {
  id: string
  user_id: string
  name: string
  phone: string
  gender: 'male' | 'female'
  age: number
  residence: 'jeju' | 'non_jeju'
  form_version: number
  agreed_at: string
  expires_at: string
  created_at: string
}

export function listRunningWeeks(): Promise<RunningWeek[]> {
  return request('/admin/running-weeks')
}

export function createRunningWeek(payload: RunningWeekPayload): Promise<RunningWeek> {
  return request('/admin/running-weeks', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  })
}

export function updateRunningWeek(id: string, payload: RunningWeekPayload): Promise<RunningWeek> {
  return request(`/admin/running-weeks/${id}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  })
}

export function setRunningWeekBingo(id: string, stampIds: string[]): Promise<RunningWeek> {
  return request(`/admin/running-weeks/${id}/bingo`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ stamp_ids: stampIds }),
  })
}

export function setRunningWeekImage(id: string, file: File): Promise<RunningWeek> {
  const form = new FormData()
  form.set('file', file)
  return request(`/admin/running-weeks/${id}/image`, { method: 'PUT', body: form })
}

export function deleteRunningWeekImage(id: string): Promise<RunningWeek> {
  return request(`/admin/running-weeks/${id}/image`, { method: 'DELETE' })
}

export function listParticipations(id: string): Promise<Participation[]> {
  return request(`/admin/running-weeks/${id}/participations`)
}

// --- 이벤트 -------------------------------------------------------------

/** 커뮤니티 이벤트. 그림(선택) + 게시글. 본문 링크는 앱에서 눌러 열 수 있다. */
export interface CommunityEvent {
  id: string
  title: string
  body: string
  image_url: string | null
  starts_at: string | null
  ends_at: string | null
  is_active: boolean
  sort_order: number
  created_at: string
  updated_at: string
}

export interface CommunityEventPayload {
  title: string
  body: string
  starts_at: string | null
  ends_at: string | null
  is_active: boolean
  sort_order: number
}

export function listEvents(): Promise<CommunityEvent[]> {
  return request('/admin/events')
}

export function createEvent(payload: CommunityEventPayload): Promise<CommunityEvent> {
  return request('/admin/events', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  })
}

export function updateEvent(id: string, payload: CommunityEventPayload): Promise<CommunityEvent> {
  return request(`/admin/events/${id}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  })
}

export function deleteEvent(id: string): Promise<void> {
  return request(`/admin/events/${id}`, { method: 'DELETE' })
}

export function setEventImage(id: string, file: File): Promise<CommunityEvent> {
  const form = new FormData()
  form.set('file', file)
  return request(`/admin/events/${id}/image`, { method: 'PUT', body: form })
}

export function deleteEventImage(id: string): Promise<CommunityEvent> {
  return request(`/admin/events/${id}/image`, { method: 'DELETE' })
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

// --- 협력업체 -----------------------------------------------------------

/** 전체 목록(이름순). 코스 폼의 업체 선택지로도 쓴다. */
export function listPartners(): Promise<Partner[]> {
  return request('/admin/partners')
}

export function createPartner(payload: PartnerPayload): Promise<Partner> {
  return request('/admin/partners', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  })
}

export function updatePartner(id: string, payload: PartnerPayload): Promise<Partner> {
  return request(`/admin/partners/${id}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  })
}

/** 삭제하면 연결된 코스에서도 빠진다(서버 FK CASCADE). */
export function deletePartner(id: string): Promise<void> {
  return request(`/admin/partners/${id}`, { method: 'DELETE' })
}

// --- 쿠폰 ---------------------------------------------------------------
// 템플릿 행은 서버 마이그레이션이 심는다 — 여기서는 수정·지급·현황만.

/** 지급 조건. 서버 app/coupon_rules.TRIGGER_TYPES와 같다. */
export type CouponTriggerType = 'manual' | 'course_complete'

export interface Coupon {
  id: string
  name: string
  description: string | null
  benefit: string
  valid_until: string | null
  trigger_type: CouponTriggerType
  /** 끄면 자동 지급이 멈춘다. 이미 발급된 쿠폰은 그대로 쓸 수 있다. */
  is_active: boolean
  /** 쓸 수 있는 업체. 비어 있으면 모든 업체. */
  partner_ids: string[]
  created_at: string
  issued_count: number
  used_count: number
}

export interface CouponPayload {
  name: string
  benefit: string
  description: string | null
  valid_until: string | null
  is_active: boolean
  partner_ids: string[]
}

export type CouponStatus = 'available' | 'used' | 'expired'

export interface IssuedCoupon {
  id: string
  user_id: string
  nickname: string | null
  issued_at: string
  used_at: string | null
  used_partner_name: string | null
  status: CouponStatus
}

export function listCoupons(): Promise<Coupon[]> {
  return request('/admin/coupons')
}

export function updateCoupon(id: string, payload: CouponPayload): Promise<Coupon> {
  return request(`/admin/coupons/${id}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  })
}

/** 고른 회원들에게 한 장씩 지급. 실제 발급된 수를 돌려준다. */
export function issueCoupon(id: string, userIds: string[]): Promise<{ issued: number }> {
  return request(`/admin/coupons/${id}/issue`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ user_ids: userIds }),
  })
}

export function listIssuedCoupons(
  id: string,
  limit: number,
  offset: number,
): Promise<{ total: number; items: IssuedCoupon[] }> {
  const params = new URLSearchParams({ limit: String(limit), offset: String(offset) })
  return request(`/admin/coupons/${id}/issued?${params}`)
}

// --- 홈 구성 ------------------------------------------------------------

/** 홈 섹션의 한 칸. 서버 HomeCurationItem과 1:1. id는 코스 또는 협력업체 id. */
export interface HomeCurationItem {
  id: string
  /** 큐레이션 설명. 앱 노출 방식은 아직 미정. */
  describe: string | null
  /** 형태 미정 부가 정보. 편집 UI는 없고 저장 시 그대로 돌려보낸다. */
  detail: Record<string, unknown>
}

/** 앱 홈 구성. 서버 HomeCurationOut과 1:1. 앞에 있을수록 먼저 나온다. */
export interface HomeCuration {
  /** '러닝 코스 큐레이션'에 띄울 코스. */
  courses: HomeCurationItem[]
  /** '추천 협력 업체'에 띄울 업체. */
  partners: HomeCurationItem[]
}

export function getHome(): Promise<HomeCuration> {
  return request('/admin/home')
}

/** 앱 홈 '러닝 코스 큐레이션'을 교체한다. 앞에 있을수록 먼저 나온다. */
export function setHomeCourses(items: HomeCurationItem[]): Promise<void> {
  return request('/admin/home/courses', {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ items }),
  })
}

/** 앱 홈 '추천 협력 업체'를 교체한다. 앞에 있을수록 먼저 나온다. */
export function setHomePartners(items: HomeCurationItem[]): Promise<void> {
  return request('/admin/home/partners', {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ items }),
  })
}

export function geocode(address: string): Promise<{ results: GeocodeResult[] }> {
  return request(`/admin/geo/geocode?address=${encodeURIComponent(address)}`)
}

// --- 지표 ---------------------------------------------------------------

/** 지표 하나의 메타. group_bys는 이 지표가 지원하는 쪼개기 차원. */
export interface MetricInfo {
  name: string
  label: string
  /** 드롭다운 묶음 이름(서버 registry가 정한다). */
  group: string
  group_bys: MetricGroupBy[]
}

export type MetricGroupBy = 'none' | 'day' | 'course'

/** 지표 값 한 점. key는 group_by에 따라 null(합계)/날짜/코스 id, name은 코스명. */
export interface MetricPoint {
  key: string | null
  name: string | null
  count: number
}

export interface MetricQuery {
  from?: string
  to?: string
  group_by?: MetricGroupBy
}

function metricParams(query: MetricQuery): string {
  const params = new URLSearchParams()
  if (query.from) params.set('from', query.from)
  if (query.to) params.set('to', query.to)
  if (query.group_by) params.set('group_by', query.group_by)
  const qs = params.toString()
  return qs ? `?${qs}` : ''
}

export function listMetrics(): Promise<MetricInfo[]> {
  return request('/admin/metrics')
}

export function getMetric(name: string, query: MetricQuery = {}): Promise<MetricPoint[]> {
  return request(`/admin/metrics/${name}${metricParams(query)}`)
}

/** 여러 지표를 한 번에. 응답은 {지표 이름: 점 목록}. */
export function getMetricsBatch(
  names: string[],
  query: MetricQuery = {},
): Promise<Record<string, MetricPoint[]>> {
  const qs = metricParams(query)
  const sep = qs ? '&' : '?'
  return request(`/admin/metrics/batch${qs}${sep}names=${names.join(',')}`)
}

// --- 회원 ---------------------------------------------------------------

export interface UserSummary {
  id: string
  nickname: string | null
  /** 가입에 쓰인 소셜 로그인. 보통 하나: kakao / apple / google. */
  providers: string[]
  email: string | null
  /** 최근 로그에 찍힌 기기(ios/android). 로그가 없으면 null. */
  platform: string | null
  /** 최근 로그에 찍힌 기기 모델(예: samsung SM-S918N, iPhone15,2). 없으면 null. */
  device: string | null
  created_at: string
  last_login_at: string | null
  completed_count: number
}

export interface UserDetail extends UserSummary {
  profile_image_url: string | null
  completed_courses: { course_id: string; name: string; acquired_at: string }[]
}

/** 회원 목록(탈퇴 제외, 가입일 최신순). keyword는 닉네임·이메일 부분일치. */
export function listUsers(
  keyword: string,
  limit: number,
  offset: number,
): Promise<{ total: number; items: UserSummary[] }> {
  const params = new URLSearchParams({ limit: String(limit), offset: String(offset) })
  if (keyword.trim()) params.set('keyword', keyword.trim())
  return request(`/admin/users?${params}`)
}

export function getUser(id: string): Promise<UserDetail> {
  return request(`/admin/users/${id}`)
}

// --- 원본 로그 ---------------------------------------------------------

export interface UserLogRow {
  id: string
  log_name: string
  user_id: string | null
  nickname: string | null
  session_id: string | null
  detail: Record<string, unknown>
  platform: string | null
  app_version: string | null
  created_at: string
}

export interface UserLogFilter {
  log_name?: string
  user_id?: string
  session_id?: string
  from?: string
  to?: string
}

export interface LogNameInfo {
  name: string
  label: string
  group: string
}

/** 앱이 보낼 수 있는 로그 이름 목록. 필터 드롭다운용. */
export function listLogNames(): Promise<LogNameInfo[]> {
  return request('/admin/user-logs/names')
}

/** 최신순 한 페이지. next_cursor를 다시 넘기면 다음 페이지가 이어진다. */
export function listUserLogs(
  filter: UserLogFilter,
  cursor?: string | null,
  limit = 50,
): Promise<{ items: UserLogRow[]; next_cursor: string | null }> {
  const params = new URLSearchParams()
  for (const [key, value] of Object.entries(filter)) {
    if (value) params.set(key, value)
  }
  params.set('limit', String(limit))
  if (cursor) params.set('cursor', cursor)
  return request(`/admin/user-logs?${params}`)
}
