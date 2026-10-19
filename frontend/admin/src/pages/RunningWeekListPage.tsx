import { useCallback, useEffect, useState } from 'react'

import {
  ApiError,
  BINGO_CELLS,
  createRunningWeek,
  deleteRunningWeekImage,
  listParticipations,
  listRunningWeeks,
  listStamps,
  setRunningWeekBingo,
  setRunningWeekImage,
  updateRunningWeek,
  type Participation,
  type RunningWeek,
  type RunningWeekPayload,
  type StampDefinition,
} from '../api'
import Modal from '../components/Modal'
import SearchSelect from '../components/SearchSelect'

interface Props {
  /** 목록 로딩이 401이면(세션 만료 등) 인증 화면으로 되돌린다. */
  onUnauthorized: () => void
}

type Visibility = 'hidden' | 'scheduled' | 'live' | 'expired'

/** 서버 routers/running_weeks.is_visible과 같은 규칙. */
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

/** 러닝위크 관리(#70). 회차마다 공개 기간, 커뮤니티 배너, 5x5 빙고 배치, 참가자를 다룬다. */
export default function RunningWeekListPage({ onUnauthorized }: Props) {
  const [weeks, setWeeks] = useState<RunningWeek[] | null>(null)
  const [stamps, setStamps] = useState<StampDefinition[]>([])
  const [error, setError] = useState<string | null>(null)
  /** 열린 모달. 'new'면 등록, 아니면 그 회차 수정. */
  const [editing, setEditing] = useState<'new' | RunningWeek | null>(null)

  const reload = useCallback(() => {
    Promise.all([listRunningWeeks(), listStamps()])
      .then(([loadedWeeks, loadedStamps]) => {
        setWeeks(loadedWeeks)
        setStamps(loadedStamps)
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
        공개 기간 안이면 앱 커뮤니티 상단에 배너가 뜨고, 누르면 러닝위크 화면이 열려요.
      </p>
      {error && <div className="error">{error}</div>}
      {weeks == null && !error && <p className="muted">불러오는 중…</p>}
      {weeks && weeks.length === 0 && <p className="muted">등록된 러닝위크가 없어요.</p>}
      {weeks && weeks.length > 0 && (
        <table>
          <thead>
            <tr>
              <th></th>
              <th>제목</th>
              <th>상태</th>
              <th>공개 기간</th>
              <th>빙고</th>
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
                  <td>
                    <strong>{week.title}</strong>
                    {week.description && <div className="muted clamp">{week.description}</div>}
                  </td>
                  <td>
                    <span className={`badge ${visibility === 'hidden' ? 'expired' : visibility}`}>
                      {VISIBILITY_LABEL[visibility]}
                    </span>
                  </td>
                  <td className="muted">
                    {week.starts_at || week.ends_at
                      ? `${formatDateTime(week.starts_at)} ~ ${formatDateTime(week.ends_at)}`
                      : '상시'}
                  </td>
                  <td className="muted">
                    {week.bingo_stamp_ids.length === BINGO_CELLS ? '배치 완료' : '미배치'}
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
          stamps={stamps}
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
  stamps,
  onClose,
  onSaved,
}: {
  /** null이면 새로 등록. */
  week: RunningWeek | null
  stamps: StampDefinition[]
  onClose: () => void
  onSaved: (week: RunningWeek) => void
}) {
  const [message, setMessage] = useState<string | null>(null)
  const saved = (next: RunningWeek, text: string) => {
    setMessage(text)
    onSaved(next)
  }

  return (
    <Modal title={week ? `러닝위크 — ${week.title}` : '새 러닝위크'} onClose={onClose}>
      {message && <div className="notice" style={{ marginTop: 0 }}>{message}</div>}
      <ContentSection week={week} onSaved={saved} />
      {week && <ImageSection week={week} onSaved={saved} />}
      {week && <BingoSection week={week} stamps={stamps} onSaved={saved} />}
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
  const [title, setTitle] = useState(week?.title ?? '')
  const [description, setDescription] = useState(week?.description ?? '')
  const [startsAt, setStartsAt] = useState(toLocalInput(week?.starts_at ?? null))
  const [endsAt, setEndsAt] = useState(toLocalInput(week?.ends_at ?? null))
  const [isActive, setIsActive] = useState(week?.is_active ?? true)
  const [error, setError] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)

  const save = async () => {
    setError(null)
    if (!title.trim()) {
      setError('제목을 입력해 주세요.')
      return
    }
    const start = startsAt ? new Date(startsAt) : null
    const end = endsAt ? new Date(endsAt) : null
    if (start && end && end < start) {
      setError('공개 종료가 시작보다 빠를 수 없어요.')
      return
    }
    const payload: RunningWeekPayload = {
      title: title.trim(),
      description: description.trim() || null,
      starts_at: start ? start.toISOString() : null,
      ends_at: end ? end.toISOString() : null,
      is_active: isActive,
    }
    setSaving(true)
    try {
      const next = week
        ? await updateRunningWeek(week.id, payload)
        : await createRunningWeek(payload)
      onSaved(next, week ? '저장했어요.' : '등록했어요. 이어서 배너와 빙고를 설정해 주세요.')
    } catch (err) {
      setError(err instanceof ApiError ? err.message : '저장에 실패했어요.')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="card">
      <h3 style={{ marginTop: 0 }}>내용</h3>
      <div className="field">
        <label htmlFor="rw-title">제목</label>
        <input id="rw-title" maxLength={200} value={title} onChange={(e) => setTitle(e.target.value)} />
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
          앱에 공개 <span className="hint">끄면 공개 기간 안이어도 안 보여요</span>
        </label>
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

  return (
    <div className="card">
      <h3 style={{ marginTop: 0 }}>커뮤니티 배너</h3>
      <p className="muted">
        앱 커뮤니티 상단에 고정으로 보이고, 누르면 러닝위크 화면이 열려요. 홈 배너와 같은 가로
        402:172 비율(약 2.3:1) 권장. 없으면 제목 카드로 보여요.
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
        <button
          onClick={() =>
            file &&
            run(() => setRunningWeekImage(week.id, file), '배너를 저장했어요.', '업로드에 실패했어요.')
          }
          disabled={saving || !file}
        >
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

function shuffled<T>(items: T[]): T[] {
  const copy = [...items]
  for (let i = copy.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1))
    ;[copy[i], copy[j]] = [copy[j], copy[i]]
  }
  return copy
}

function BingoSection({
  week,
  stamps,
  onSaved,
}: {
  week: RunningWeek
  stamps: StampDefinition[]
  onSaved: (week: RunningWeek, message: string) => void
}) {
  const [cells, setCells] = useState<string[]>(() =>
    week.bingo_stamp_ids.length === BINGO_CELLS
      ? week.bingo_stamp_ids
      : Array.from({ length: BINGO_CELLS }, () => ''),
  )
  const [error, setError] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)

  const active = stamps.filter((s) => s.is_active)
  const stampOptions = [
    { id: '', label: '비우기' },
    ...stamps.map((stamp) => ({
      id: stamp.id,
      label: stamp.is_active ? stamp.name : `${stamp.name} (숨김)`,
    })),
  ]

  const randomFill = () => {
    setError(null)
    if (active.length < BINGO_CELLS) {
      setError(`노출 중인 스탬프가 ${active.length}개라 25칸을 채울 수 없어요.`)
      return
    }
    setCells(shuffled(active).slice(0, BINGO_CELLS).map((s) => s.id))
  }

  const save = async () => {
    setError(null)
    if (cells.some((id) => !id)) {
      setError('25칸을 모두 채워 주세요.')
      return
    }
    if (new Set(cells).size !== cells.length) {
      setError('같은 스탬프를 두 칸에 놓을 수 없어요.')
      return
    }
    setSaving(true)
    try {
      onSaved(await setRunningWeekBingo(week.id, cells), '빙고 배치를 저장했어요.')
    } catch (err) {
      setError(err instanceof ApiError ? err.message : '저장에 실패했어요.')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="card">
      <h3 style={{ marginTop: 0 }}>빙고 배치 (5x5)</h3>
      <p className="muted">
        칸마다 스탬프 하나. 그 스탬프를 받으면 칸이 채워져요(러닝위크 전에 받은 것도 인정).
      </p>
      <div
        style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(5, minmax(0, 1fr))',
          gap: 6,
          marginBottom: 12,
        }}
      >
        {cells.map((id, index) => (
          <SearchSelect
            key={index}
            value={id}
            title={`${index + 1}번 칸`}
            placeholder={`${index + 1}번 칸`}
            options={stampOptions}
            onSelect={(picked) =>
              setCells((prev) => prev.map((cell, i) => (i === index ? picked : cell)))
            }
            emptyText="스탬프가 없어요"
          />
        ))}
      </div>
      {error && <div className="error">{error}</div>}
      <div className="submit-row">
        <button className="secondary" onClick={randomFill} disabled={saving}>
          랜덤 채우기
        </button>
        <button onClick={save} disabled={saving}>
          {saving ? '저장 중…' : '배치 저장'}
        </button>
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
