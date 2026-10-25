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
import Modal from '../components/Modal'

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

/** 러닝위크 관리(#70). 회차마다 공개 기간·범위, 커뮤니티 배너, 참가자를 다룬다.
 * 빙고판 배치는 운영툴에서 하지 않는다 — 개발자가 코드·DB로 넣는다. */
export default function RunningWeekListPage({ onUnauthorized }: Props) {
  const [weeks, setWeeks] = useState<RunningWeek[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  /** 열린 모달. 'new'면 등록, 아니면 그 회차 수정. */
  const [editing, setEditing] = useState<'new' | RunningWeek | null>(null)

  const reload = useCallback(() => {
    listRunningWeeks()
      .then((loaded) => {
        setWeeks(loaded)
        setError(null)
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
              <th className="nowrap">회차</th>
              <th>제목</th>
              <th>상태</th>
              <th>공개 범위</th>
              <th>공개 기간</th>
              <th>참가자</th>
            </tr>
          </thead>
          <tbody>
            {weeks.map((week) => {
              const visibility = visibilityOf(week, now)
              return (
                <tr key={week.id} onClick={() => setEditing(week)}>
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
                </tr>
              )
            })}
          </tbody>
        </table>
      )}

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
  const [message, setMessage] = useState<string | null>(null)
  const saved = (next: RunningWeek, text: string) => {
    setMessage(text)
    onSaved(next)
  }

  return (
    <Modal title={week ? `러닝위크 ${week.round}회 — ${week.title}` : '새 러닝위크'} onClose={onClose}>
      {message && <div className="notice" style={{ marginTop: 0 }}>{message}</div>}
      <ContentSection week={week} onSaved={saved} />
      {week && <ImageSection week={week} onSaved={saved} />}
      {week && <ParticipantSection week={week} />}
    </Modal>
  )
}

function ContentSection({
  week,
  onSaved,
}: {
  week: RunningWeek | null
  onSaved: (week: RunningWeek, message: string) => void
}) {
  const [round, setRound] = useState(week ? String(week.round) : '')
  const [title, setTitle] = useState(week?.title ?? '')
  const [description, setDescription] = useState(week?.description ?? '')
  const [startsAt, setStartsAt] = useState(toLocalInput(week?.starts_at ?? null))
  const [endsAt, setEndsAt] = useState(toLocalInput(week?.ends_at ?? null))
  const [isActive, setIsActive] = useState(week?.is_active ?? true)
  const [visibility, setVisibility] = useState<CourseVisibility>(week?.visibility ?? 'admin')
  const [error, setError] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)

  const save = async () => {
    setError(null)
    if (!title.trim()) {
      setError('제목을 입력해 주세요.')
      return
    }
    if (round && !/^\d+$/.test(round)) {
      setError('회차는 숫자로 입력해 주세요.')
      return
    }
    const start = startsAt ? new Date(startsAt) : null
    const end = endsAt ? new Date(endsAt) : null
    if (start && end && end < start) {
      setError('공개 종료가 시작보다 빠를 수 없어요.')
      return
    }
    const payload: RunningWeekPayload = {
      round: round ? Number(round) : null,
      title: title.trim(),
      description: description.trim() || null,
      starts_at: start ? start.toISOString() : null,
      ends_at: end ? end.toISOString() : null,
      is_active: isActive,
      visibility,
    }
    setSaving(true)
    try {
      const next = week
        ? await updateRunningWeek(week.id, payload)
        : await createRunningWeek(payload)
      onSaved(
        next,
        week
          ? '저장했어요.'
          : '등록했어요. 이어서 배너를 올려 주세요.',
      )
    } catch (err) {
      setError(err instanceof ApiError ? err.message : '저장에 실패했어요.')
    } finally {
      setSaving(false)
    }
  }

  return (
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
            value={round}
            onChange={(e) => setRound(e.target.value.replace(/\D/g, ''))}
          />
        </div>
        <div className="field">
          <label htmlFor="rw-title">제목</label>
          <input id="rw-title" maxLength={200} value={title} onChange={(e) => setTitle(e.target.value)} />
        </div>
      </div>
      <div className="field">
        <label htmlFor="rw-description">
          소개 <span className="hint">러닝위크 화면의 참가 안내에 보여요</span>
        </label>
        <textarea
          id="rw-description"
          value={description}
          onChange={(e) => setDescription(e.target.value)}
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
            value={startsAt}
            onChange={(e) => setStartsAt(e.target.value)}
          />
        </div>
        <div className="field">
          <label htmlFor="rw-ends">
            공개 종료 <span className="hint">비우면 무기한</span>
          </label>
          <input
            id="rw-ends"
            type="datetime-local"
            value={endsAt}
            onChange={(e) => setEndsAt(e.target.value)}
          />
        </div>
      </div>
      <div className="field">
        <label>
          <input type="checkbox" checked={isActive} onChange={(e) => setIsActive(e.target.checked)} />{' '}
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
              checked={visibility === 'admin'}
              onChange={() => setVisibility('admin')}
            />{' '}
            운영자만 <span className="hint">role=admin 계정</span>
          </label>
          <label>
            <input
              type="radio"
              name="rw-visibility"
              value="public"
              checked={visibility === 'public'}
              onChange={() => setVisibility('public')}
            />{' '}
            일반 사용자 포함
          </label>
        </div>
      </div>
      {error && <div className="error">{error}</div>}
      <div className="submit-row">
        <button onClick={save} disabled={saving}>
          {saving ? '저장 중…' : week ? '저장' : '등록'}
        </button>
      </div>
    </div>
  )
}

function ImageSection({
  week,
  onSaved,
}: {
  week: RunningWeek
  onSaved: (week: RunningWeek, message: string) => void
}) {
  const [file, setFile] = useState<File | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)

  const run = async (action: () => Promise<RunningWeek>, done: string, failure: string) => {
    setError(null)
    setSaving(true)
    try {
      onSaved(await action(), done)
      setFile(null)
    } catch (err) {
      setError(err instanceof ApiError ? err.message : failure)
    } finally {
      setSaving(false)
    }
  }

  const upload = async () => {
    if (!file) return
    // 홈 배너와 같은 규격(21:9). 서버는 픽셀을 안 보니 여기서 막는다.
    const problem = await validateBannerImage(file)
    if (problem) {
      setError(problem)
      return
    }
    await run(() => setRunningWeekImage(week.id, file), '배너를 저장했어요.', '업로드에 실패했어요.')
  }

  return (
    <div className="card">
      <h3 style={{ marginTop: 0 }}>커뮤니티 배너</h3>
      <p className="muted">
        앱 커뮤니티 상단에 고정으로 보이고, 누르면 러닝위크 화면이 열려요. 홈 배너와 같은 규격 —{' '}
        {BANNER_SPEC.hint}. 없으면 제목 카드로 보여요.
      </p>
      {week.image_url ? (
        <img className="thumb banner" src={week.image_url} alt="현재 배너" />
      ) : (
        <p className="muted">등록된 배너가 없어요.</p>
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
          {saving ? '처리 중…' : week.image_url ? '배너 교체' : '배너 등록'}
        </button>
        {week.image_url && (
          <button
            className="danger"
            onClick={() =>
              run(() => deleteRunningWeekImage(week.id), '배너를 지웠어요.', '삭제에 실패했어요.')
            }
            disabled={saving}
          >
            배너 삭제
          </button>
        )}
      </div>
    </div>
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
    <div className="card">
      <h3 style={{ marginTop: 0 }}>참가자</h3>
      <p className="muted">개인정보라 신청일로부터 1년이 지나면 폐기해야 해요(폐기 예정일 열 참고).</p>
      {error && <div className="error">{error}</div>}
      {rows == null && !error && <p className="muted">불러오는 중…</p>}
      {rows && rows.length === 0 && <p className="muted">아직 참가자가 없어요.</p>}
      {rows && rows.length > 0 && (
        <>
          <table>
            <thead>
              <tr>
                <th>신청일</th>
                <th>이름</th>
                <th>연락처</th>
                <th>성별</th>
                <th>나이</th>
                <th>거주지</th>
                <th>폐기 예정</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
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
