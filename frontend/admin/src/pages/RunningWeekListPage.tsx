import { useCallback, useEffect, useState } from 'react'

import {
  ApiError,
  createRunningWeek,
  deleteRunningWeekImage,
  listParticipations,
  listRunningWeeks,
  setRunningWeekImage,
  updateRunningWeek,
  type CourseVisibility,
  type Participation,
  type RunningWeek,
  type RunningWeekPayload,
} from '../api'
import { BANNER_SPEC, validateBannerImage } from '../components/imageSpec'
import { ImageSection, imageChanged, NO_IMAGE_CHANGE, type ImageChange } from '../components/ImageSections'
import Modal from '../components/Modal'
import SaveFooter from '../components/SaveFooter'
import SortTh, { useSort } from '../components/SortTh'
import { runSteps, snapshot, type SaveStep } from '../utils/saveSteps'

interface Props {
  /** 목록 로딩이 401이면(세션 만료 등) 인증 화면으로 되돌린다. */
  onUnauthorized: () => void
}

type Visibility = 'hidden' | 'scheduled' | 'live' | 'expired'

/** 서버 app/running_week.is_visible과 같은 규칙. */
function visibilityOf(week: RunningWeek, now: Date): Visibility {
  if (!week.is_active) return 'hidden'
  if (week.starts_at && new Date(week.starts_at) > now) return 'scheduled'
  if (week.ends_at && new Date(week.ends_at) < now) return 'expired'
  return 'live'
}

const VISIBILITY_LABEL: Record<Visibility, string> = {
  hidden: '숨김',
  scheduled: '예약',
  live: '공개 중',
  expired: '종료',
}

/** 공개 범위(서버 visibility). 코스와 같다. */
const VISIBILITY_SCOPE_LABEL: Record<CourseVisibility, string> = {
  admin: '운영자만',
  public: '일반 사용자 포함',
}

function formatDateTime(iso: string | null): string {
  if (!iso) return '—'
  const d = new Date(iso)
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}.${pad(d.getMonth() + 1)}.${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`
}

/** ISO(UTC) → datetime-local 입력값(로컬 시각). */
function toLocalInput(iso: string | null): string {
  if (!iso) return ''
  const d = new Date(iso)
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`
}

/** 러닝위크 관리(#70). 위 표는 회차(배너·기간·범위), 아래 표는 고른 회차의 참가자.
 * 빙고판 배치는 운영툴에서 하지 않는다 — 개발자가 코드·DB로 넣는다. */
export default function RunningWeekListPage({ onUnauthorized }: Props) {
  const [weeks, setWeeks] = useState<RunningWeek[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  /** 열린 모달. 'new'면 등록, 아니면 그 회차 수정. */
  const [editing, setEditing] = useState<'new' | RunningWeek | null>(null)
  /** 아래 참가자 표가 보여 주는 회차. 처음엔 공개 중인 회차, 없으면 맨 위. */
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const { sort, toggle, sorted } = useSort(weeks, {
    round: (w) => w.round,
    title: (w) => w.title,
    status: (w) => VISIBILITY_LABEL[visibilityOf(w, new Date())],
    scope: (w) => VISIBILITY_SCOPE_LABEL[w.visibility],
    period: (w) => w.starts_at ?? w.ends_at,
    participants: (w) => w.participant_count,
  })

  const reload = useCallback(() => {
    listRunningWeeks()
      .then((loaded) => {
        setWeeks(loaded)
        setError(null)
        setSelectedId((current) => {
          if (current && loaded.some((w) => w.id === current)) return current
          const now = new Date()
          return (loaded.find((w) => visibilityOf(w, now) === 'live') ?? loaded[0])?.id ?? null
        })
      })
      .catch((err: unknown) => {
        if (err instanceof ApiError && err.status === 401) {
          onUnauthorized()
          return
        }
        setError(err instanceof ApiError ? err.message : '러닝위크 목록을 불러오지 못했어요.')
      })
  }, [onUnauthorized])

  useEffect(() => {
    reload()
  }, [reload])

  const now = new Date()
  const selected = weeks?.find((w) => w.id === selectedId) ?? null

  return (
    <>
      <div className="page-head">
        <h2>러닝위크</h2>
        <button onClick={() => setEditing('new')}>+ 회차 추가</button>
      </div>
      <p className="muted page-desc">
        공개 기간 안이면 앱 커뮤니티 상단에 배너가 뜨고, 누르면 러닝위크 화면이 열려요. 참가 신청한
        사람이 공개 기간에 완주하면 코스 스탬프와 함께 그 회차 러닝위크 스탬프를 받아요(쿠폰도
        참가자만).
      </p>
      {error && <div className="error">{error}</div>}
      {weeks == null && !error && <p className="muted">불러오는 중…</p>}
      {weeks && weeks.length === 0 && <p className="muted">등록된 러닝위크가 없어요.</p>}
      {weeks && weeks.length > 0 && (
        <table>
          <thead>
            <tr>
              <th></th>
              <SortTh sortKey="round" sort={sort} onToggle={toggle} className="nowrap">
                회차
              </SortTh>
              <SortTh sortKey="title" sort={sort} onToggle={toggle}>
                제목
              </SortTh>
              <SortTh sortKey="status" sort={sort} onToggle={toggle}>
                상태
              </SortTh>
              <SortTh sortKey="scope" sort={sort} onToggle={toggle}>
                공개 범위
              </SortTh>
              <SortTh sortKey="period" sort={sort} onToggle={toggle}>
                공개 기간
              </SortTh>
              <SortTh sortKey="participants" sort={sort} onToggle={toggle}>
                참가자
              </SortTh>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {sorted!.map((week) => {
              const visibility = visibilityOf(week, now)
              return (
                <tr
                  key={week.id}
                  className={week.id === selectedId ? 'selected' : undefined}
                  onClick={() => setSelectedId(week.id)}
                >
                  <td style={{ width: 104 }}>
                    {week.image_url ? (
                      <img className="thumb wide" src={week.image_url} alt="" />
                    ) : (
                      <div className="thumb wide placeholder">배너 없음</div>
                    )}
                  </td>
                  <td className="nowrap">{week.round}회</td>
                  <td>
                    <strong>{week.title}</strong>
                    {week.description && <div className="muted clamp">{week.description}</div>}
                  </td>
                  <td>
                    <span className={`badge ${visibility === 'hidden' ? 'expired' : visibility}`}>
                      {VISIBILITY_LABEL[visibility]}
                    </span>
                  </td>
                  <td className={week.visibility === 'public' ? undefined : 'muted'}>
                    {VISIBILITY_SCOPE_LABEL[week.visibility]}
                  </td>
                  <td className="muted">
                    {week.starts_at || week.ends_at
                      ? `${formatDateTime(week.starts_at)} ~ ${formatDateTime(week.ends_at)}`
                      : '상시'}
                  </td>
                  <td className="muted">{week.participant_count}명</td>
                  <td className="nowrap">
                    <button
                      className="secondary small"
                      onClick={(event) => {
                        event.stopPropagation()
                        setEditing(week)
                      }}
                    >
                      수정
                    </button>
                  </td>
                </tr>
              )
            })}
          </tbody>
        </table>
      )}

      {selected && <ParticipantSection week={selected} />}

      {editing && (
        <RunningWeekModal
          week={editing === 'new' ? null : editing}
          onClose={() => setEditing(null)}
          onSaved={(saved) => {
            setEditing(saved)
            reload()
          }}
        />
      )}
    </>
  )
}

interface WeekValues {
  round: string
  title: string
  description: string
  startsAt: string
  endsAt: string
  isActive: boolean
  visibility: CourseVisibility
}

function valuesFromWeek(week: RunningWeek | null): WeekValues {
  return {
    round: week ? String(week.round) : '',
    title: week?.title ?? '',
    description: week?.description ?? '',
    startsAt: toLocalInput(week?.starts_at ?? null),
    endsAt: toLocalInput(week?.ends_at ?? null),
    isActive: week?.is_active ?? true,
    visibility: week?.visibility ?? 'admin',
  }
}

function RunningWeekModal({
  week,
  onClose,
  onSaved,
}: {
  /** null이면 새로 등록. */
  week: RunningWeek | null
  onClose: () => void
  onSaved: (week: RunningWeek) => void
}) {
  const [values, setValues] = useState(() => valuesFromWeek(week))
  /** 서버에 저장된 내용의 스냅샷. values와 다르면 '내용 변경'이다. */
  const [savedKey, setSavedKey] = useState(() => snapshot(valuesFromWeek(week)))
  const [image, setImage] = useState<ImageChange>(NO_IMAGE_CHANGE)
  const [message, setMessage] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)

  const set = (patch: Partial<WeekValues>) => {
    setValues((prev) => ({ ...prev, ...patch }))
    setMessage(null)
  }

  const contentDirty = snapshot(values) !== savedKey
  const imageDirty = imageChanged(image)
  const dirty = [contentDirty && '내용', imageDirty && '커뮤니티 배너'].filter(
    (label): label is string => Boolean(label),
  )

  const save = async () => {
    setError(null)
    setMessage(null)
    let payload: RunningWeekPayload | null = null
    if (contentDirty || !week) {
      if (!values.title.trim()) return setError('제목을 입력해 주세요.')
      if (values.round && !/^\d+$/.test(values.round)) return setError('회차는 숫자로 입력해 주세요.')
      const start = values.startsAt ? new Date(values.startsAt) : null
      const end = values.endsAt ? new Date(values.endsAt) : null
      if (start && end && end < start) return setError('공개 종료가 시작보다 빠를 수 없어요.')
      payload = {
        round: values.round ? Number(values.round) : null,
        title: values.title.trim(),
        description: values.description.trim() || null,
        starts_at: start ? start.toISOString() : null,
        ends_at: end ? end.toISOString() : null,
        is_active: values.isActive,
        visibility: values.visibility,
      }
    }

    let latest: RunningWeek | null = null
    const steps: SaveStep[] = []
    if (payload) {
      const body = payload
      const snap = snapshot(values)
      steps.push({
        label: week ? '내용' : '등록',
        run: async () => {
          latest = week ? await updateRunningWeek(week.id, body) : await createRunningWeek(body)
          setSavedKey(snap)
        },
      })
    }
    if (week && imageDirty) {
      const { file } = image
      steps.push({
        label: '커뮤니티 배너',
        run: async () => {
          latest = file
            ? await setRunningWeekImage(week.id, file)
            : await deleteRunningWeekImage(week.id)
          setImage(NO_IMAGE_CHANGE)
        },
      })
    }

    setSaving(true)
    const failure = await runSteps(steps)
    setSaving(false)
    if (latest) onSaved(latest)
    if (failure) {
      setError(failure)
      return
    }
    setMessage(week ? '저장했어요.' : '등록했어요. 이어서 배너를 올려 주세요.')
  }

  return (
    <Modal
      title={week ? `러닝위크 ${week.round}회 — ${week.title}` : '새 러닝위크'}
      onClose={onClose}
      closable={!saving}
      footer={
        <SaveFooter
          dirty={dirty}
          saving={saving}
          error={error}
          onSave={save}
          label={week ? '전체 저장' : '등록'}
          alwaysEnabled={!week}
        />
      }
    >
      {message && <div className="notice" style={{ marginTop: 0 }}>{message}</div>}
      <div className="card">
        <h3 style={{ marginTop: 0 }}>내용</h3>
        <div className="row">
          <div className="field" style={{ flex: '0 0 120px' }}>
            <label htmlFor="rw-round">
              회차 <span className="hint">{week ? '' : '비우면 다음 회차'}</span>
            </label>
            <input
              id="rw-round"
              inputMode="numeric"
              maxLength={3}
              value={values.round}
              onChange={(e) => set({ round: e.target.value.replace(/\D/g, '') })}
            />
          </div>
          <div className="field">
            <label htmlFor="rw-title">제목</label>
            <input
              id="rw-title"
              maxLength={200}
              value={values.title}
              onChange={(e) => set({ title: e.target.value })}
            />
          </div>
        </div>
        <div className="field">
          <label htmlFor="rw-description">
            소개 <span className="hint">러닝위크 화면의 참가 안내에 보여요</span>
          </label>
          <textarea
            id="rw-description"
            value={values.description}
            onChange={(e) => set({ description: e.target.value })}
          />
        </div>
        <div className="row">
          <div className="field">
            <label htmlFor="rw-starts">
              공개 시작 <span className="hint">비우면 즉시</span>
            </label>
            <input
              id="rw-starts"
              type="datetime-local"
              value={values.startsAt}
              onChange={(e) => set({ startsAt: e.target.value })}
            />
          </div>
          <div className="field">
            <label htmlFor="rw-ends">
              공개 종료 <span className="hint">비우면 무기한</span>
            </label>
            <input
              id="rw-ends"
              type="datetime-local"
              value={values.endsAt}
              onChange={(e) => set({ endsAt: e.target.value })}
            />
          </div>
        </div>
        <div className="field">
          <label>
            <input
              type="checkbox"
              checked={values.isActive}
              onChange={(e) => set({ isActive: e.target.checked })}
            />{' '}
            앱에 공개 <span className="hint">끄면 공개 기간·범위와 상관없이 안 보여요</span>
          </label>
        </div>
        <div className="field">
          <label>
            공개 범위 <span className="hint">공개 기간과 별개로 "누가" 보는지</span>
          </label>
          <div className="row" style={{ gap: 16 }}>
            <label>
              <input
                type="radio"
                name="rw-visibility"
                value="admin"
                checked={values.visibility === 'admin'}
                onChange={() => set({ visibility: 'admin' })}
              />{' '}
              운영자만 <span className="hint">role=admin 계정</span>
            </label>
            <label>
              <input
                type="radio"
                name="rw-visibility"
                value="public"
                checked={values.visibility === 'public'}
                onChange={() => set({ visibility: 'public' })}
              />{' '}
              일반 사용자 포함
            </label>
          </div>
        </div>
      </div>
      {week && (
        <ImageSection
          title="커뮤니티 배너"
          description={`앱 커뮤니티 상단에 고정으로 보이고, 누르면 러닝위크 화면이 열려요. 홈 배너와 같은 규격 — ${BANNER_SPEC.hint}. 없으면 제목 카드로 보여요.`}
          imageClass="thumb banner"
          currentUrl={week.image_url}
          value={image}
          onChange={setImage}
          validate={validateBannerImage}
        />
      )}
    </Modal>
  )
}

const GENDER_LABEL = { male: '남', female: '여' } as const
const RESIDENCE_LABEL = { jeju: '도민', non_jeju: '도외' } as const

function csvCell(value: string | number): string {
  const text = String(value)
  return /[",\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text
}

function ParticipantSection({ week }: { week: RunningWeek }) {
  const [rows, setRows] = useState<Participation[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const { sort, toggle, sorted } = useSort(rows, {
    created: (r) => r.created_at,
    name: (r) => r.name,
    phone: (r) => r.phone,
    gender: (r) => GENDER_LABEL[r.gender],
    age: (r) => r.age,
    residence: (r) => RESIDENCE_LABEL[r.residence],
    expires: (r) => r.expires_at,
  })

  useEffect(() => {
    listParticipations(week.id)
      .then(setRows)
      .catch((err: unknown) =>
        setError(err instanceof ApiError ? err.message : '참가자를 불러오지 못했어요.'),
      )
  }, [week.id])

  const download = () => {
    if (!rows) return
    const header = ['신청일', '이름', '연락처', '성별', '나이', '거주지', '폼 버전', '폐기 예정']
    const lines = rows.map((r) =>
      [
        formatDateTime(r.created_at),
        r.name,
        r.phone,
        GENDER_LABEL[r.gender],
        r.age,
        RESIDENCE_LABEL[r.residence],
        r.form_version,
        formatDateTime(r.expires_at),
      ]
        .map(csvCell)
        .join(','),
    )
    // 엑셀이 한글을 깨뜨리지 않게 BOM을 붙인다.
    const blob = new Blob(['﻿' + [header.join(','), ...lines].join('\n')], {
      type: 'text/csv;charset=utf-8',
    })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `러닝위크_참가자_${week.title}.csv`
    a.click()
    URL.revokeObjectURL(url)
  }

  return (
    <div className="card" style={{ marginTop: 24 }}>
      <h3 style={{ marginTop: 0 }}>
        참가자 — {week.round}회 {week.title}
        {rows && <span className="muted"> · {rows.length}명</span>}
      </h3>
      <p className="muted">
        위 표에서 회차를 누르면 바뀌어요. 개인정보라 신청일로부터 1년이 지나면 폐기해야 해요(폐기 예정일 열 참고).
      </p>
      {error && <div className="error">{error}</div>}
      {rows == null && !error && <p className="muted">불러오는 중…</p>}
      {rows && rows.length === 0 && <p className="muted">아직 참가자가 없어요.</p>}
      {rows && rows.length > 0 && (
        <>
          <table>
            <thead>
              <tr>
                <SortTh sortKey="created" sort={sort} onToggle={toggle}>
                  신청일
                </SortTh>
                <SortTh sortKey="name" sort={sort} onToggle={toggle}>
                  이름
                </SortTh>
                <SortTh sortKey="phone" sort={sort} onToggle={toggle}>
                  연락처
                </SortTh>
                <SortTh sortKey="gender" sort={sort} onToggle={toggle}>
                  성별
                </SortTh>
                <SortTh sortKey="age" sort={sort} onToggle={toggle}>
                  나이
                </SortTh>
                <SortTh sortKey="residence" sort={sort} onToggle={toggle}>
                  거주지
                </SortTh>
                <SortTh sortKey="expires" sort={sort} onToggle={toggle}>
                  폐기 예정
                </SortTh>
              </tr>
            </thead>
            <tbody>
              {sorted!.map((r) => (
                <tr key={r.id}>
                  <td className="muted">{formatDateTime(r.created_at)}</td>
                  <td>{r.name}</td>
                  <td>{r.phone}</td>
                  <td>{GENDER_LABEL[r.gender]}</td>
                  <td>{r.age}</td>
                  <td>{RESIDENCE_LABEL[r.residence]}</td>
                  <td className="muted">{formatDateTime(r.expires_at)}</td>
                </tr>
              ))}
            </tbody>
          </table>
          <div className="submit-row">
            <button className="secondary" onClick={download}>
              CSV 내려받기
            </button>
          </div>
        </>
      )}
    </div>
  )
}
