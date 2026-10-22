import { useCallback, useEffect, useState } from 'react'

import {
  ApiError,
  createStamp,
  deleteStampImage,
  listCourses,
  listRunningWeeks,
  listStamps,
  setStampImage,
  updateStamp,
  type Course,
  type RunningWeek,
  type StampConditionType,
  type StampDefinition,
  type StampDefinitionPayload,
} from '../api'
import { STAMP_SPEC, validateStampImage } from '../components/imageSpec'
import Modal from '../components/Modal'
import SearchSelect from '../components/SearchSelect'

interface Props {
  /** 목록 로딩이 401이면(세션 만료 등) 인증 화면으로 되돌린다. */
  onUnauthorized: () => void
}

const CONDITION_LABEL: Record<StampConditionType, string> = {
  course_complete: '코스 완주',
  running_week_course: '러닝위크 코스 완주',
  bingo_lines: '빙고 줄 완성',
  manual: '운영자 지급',
}

/** 5x5 빙고의 가로·세로·대각선 줄 수. 이 줄 수 스탬프가 판 전체 완성(스페셜 스탬프). */
const MAX_BINGO_LINES = 12

/**
 * 스탬프 종류 관리. 스탬프는 코스와 분리됐다(#71) — 코스 완주는 획득 조건의 하나다.
 * 스탬프는 지우지 않고 노출을 끈다(발급 기록이 가리킨다).
 */
export default function StampListPage({ onUnauthorized }: Props) {
  const [stamps, setStamps] = useState<StampDefinition[] | null>(null)
  const [courses, setCourses] = useState<Course[]>([])
  const [weeks, setWeeks] = useState<RunningWeek[]>([])
  const [error, setError] = useState<string | null>(null)
  /** 열린 모달. 'new'면 등록, 아니면 그 스탬프 수정. */
  const [editing, setEditing] = useState<'new' | StampDefinition | null>(null)

  const reload = useCallback(() => {
    Promise.all([listStamps(), listCourses(), listRunningWeeks()])
      .then(([loadedStamps, loadedCourses, loadedWeeks]) => {
        setStamps(loadedStamps)
        setCourses(loadedCourses)
        setWeeks(loadedWeeks)
        setError(null)
      })
      .catch((err: unknown) => {
        if (err instanceof ApiError && err.status === 401) {
          onUnauthorized()
          return
        }
        setError(err instanceof ApiError ? err.message : '스탬프 목록을 불러오지 못했어요.')
      })
  }, [onUnauthorized])

  useEffect(() => {
    reload()
  }, [reload])

  const courseName = (stamp: StampDefinition) =>
    courses.find((c) => c.id === stamp.condition_params.course_id)?.name ?? '(없는 코스)'
  const weekLabel = (stamp: StampDefinition) => {
    const week = weeks.find((w) => w.id === stamp.condition_params.running_week_id)
    return week ? `${week.round}회 ${week.title}` : '(없는 회차)'
  }

  return (
    <>
      <div className="page-head">
        <h2>스탬프</h2>
        <button onClick={() => setEditing('new')}>+ 스탬프 추가</button>
      </div>
      <p className="muted page-desc">
        코스를 등록하면 그 코스의 완주 스탬프가 자동으로 하나 생겨요. 이름·도안은 여기서 고쳐요.
      </p>
      {error && <div className="error">{error}</div>}
      {stamps == null && !error && <p className="muted">불러오는 중…</p>}
      {stamps && stamps.length === 0 && <p className="muted">등록된 스탬프가 없어요.</p>}
      {stamps && stamps.length > 0 && (
        <table>
          <thead>
            <tr>
              <th></th>
              <th>이름</th>
              <th>획득 조건</th>
              <th>상태</th>
              <th>받은 사람</th>
              <th>정렬</th>
            </tr>
          </thead>
          <tbody>
            {stamps.map((stamp) => (
              <tr key={stamp.id} onClick={() => setEditing(stamp)}>
                <td style={{ width: 64 }}>
                  {stamp.image_url ? (
                    <img className="thumb round" src={stamp.image_url} alt="" />
                  ) : (
                    <div className="thumb round placeholder">없음</div>
                  )}
                </td>
                <td>
                  <strong>{stamp.name}</strong>
                  {stamp.description && <div className="muted clamp">{stamp.description}</div>}
                </td>
                <td>
                  {CONDITION_LABEL[stamp.condition_type] ?? stamp.condition_type}
                  {stamp.condition_type === 'course_complete' && (
                    <div className="muted">{courseName(stamp)}</div>
                  )}
                  {stamp.condition_type === 'running_week_course' && (
                    <div className="muted">
                      {courseName(stamp)} · {weekLabel(stamp)}
                    </div>
                  )}
                  {stamp.condition_type === 'bingo_lines' && (
                    <div className="muted">
                      {stamp.condition_params.lines}줄
                      {stamp.condition_params.lines === MAX_BINGO_LINES && ' (판 전체)'} ·{' '}
                      {weekLabel(stamp)}
                    </div>
                  )}
                </td>
                <td>
                  <span className={`badge ${stamp.is_active ? 'live' : 'expired'}`}>
                    {stamp.is_active ? '노출' : '숨김'}
                  </span>
                </td>
                <td className="muted">{stamp.issued_count}명</td>
                <td className="muted">{stamp.sort_order}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      {editing && (
        <StampModal
          stamp={editing === 'new' ? null : editing}
          courses={courses}
          weeks={weeks}
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

function payloadFrom(stamp: StampDefinition | null): StampDefinitionPayload {
  return {
    name: stamp?.name ?? '',
    description: stamp?.description ?? null,
    condition_type: stamp?.condition_type ?? 'manual',
    condition_params: stamp?.condition_params ?? {},
    is_active: stamp?.is_active ?? true,
    sort_order: stamp?.sort_order ?? 0,
  }
}

function StampModal({
  stamp,
  courses,
  weeks,
  onClose,
  onSaved,
}: {
  /** null이면 새로 등록. */
  stamp: StampDefinition | null
  courses: Course[]
  weeks: RunningWeek[]
  onClose: () => void
  onSaved: (stamp: StampDefinition) => void
}) {
  const [values, setValues] = useState<StampDefinitionPayload>(() => payloadFrom(stamp))
  const [error, setError] = useState<string | null>(null)
  const [message, setMessage] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)

  const set = (patch: Partial<StampDefinitionPayload>) => {
    setValues((prev) => ({ ...prev, ...patch }))
    setMessage(null)
  }

  const save = async () => {
    setError(null)
    if (!values.name.trim()) {
      setError('이름을 입력해 주세요.')
      return
    }
    const needsCourse =
      values.condition_type === 'course_complete' || values.condition_type === 'running_week_course'
    const needsWeek =
      values.condition_type === 'running_week_course' || values.condition_type === 'bingo_lines'
    if (needsCourse && !values.condition_params.course_id) {
      setError('완주할 코스를 골라 주세요.')
      return
    }
    const { course_id, running_week_id, lines } = values.condition_params
    if (needsWeek && !running_week_id) {
      setError('러닝위크 회차를 골라 주세요.')
      return
    }
    if (values.condition_type === 'bingo_lines') {
      if (!lines || lines < 1 || lines > MAX_BINGO_LINES) {
        setError(`줄 수는 1~${MAX_BINGO_LINES} 사이로 입력해 주세요.`)
        return
      }
    }
    const payload: StampDefinitionPayload = {
      ...values,
      name: values.name.trim(),
      description: values.description?.trim() || null,
      condition_params:
        values.condition_type === 'course_complete'
          ? { course_id }
          : values.condition_type === 'running_week_course'
            ? { running_week_id, course_id }
            : values.condition_type === 'bingo_lines'
              ? { running_week_id, lines }
              : {},
    }
    setSaving(true)
    try {
      const saved = stamp ? await updateStamp(stamp.id, payload) : await createStamp(payload)
      setMessage(stamp ? '저장했어요.' : '등록했어요. 이어서 도안을 올릴 수 있어요.')
      onSaved(saved)
    } catch (err) {
      setError(err instanceof ApiError ? err.message : '저장에 실패했어요.')
    } finally {
      setSaving(false)
    }
  }

  return (
    <Modal title={stamp ? `스탬프 수정 — ${stamp.name}` : '새 스탬프'} onClose={onClose}>
      {message && <div className="notice" style={{ marginTop: 0 }}>{message}</div>}
      <div className="card">
        <div className="field">
          <label htmlFor="stamp-name">이름</label>
          <input
            id="stamp-name"
            value={values.name}
            maxLength={100}
            onChange={(e) => set({ name: e.target.value })}
          />
        </div>
        <div className="field">
          <label htmlFor="stamp-description">
            획득 조건 안내 <span className="hint">앱 스탬프 상세·빙고 칸에 그대로 보여요</span>
          </label>
          <textarea
            id="stamp-description"
            value={values.description ?? ''}
            onChange={(e) => set({ description: e.target.value })}
          />
        </div>
        <div className="field">
          <label htmlFor="stamp-condition">획득 조건</label>
          <select
            id="stamp-condition"
            value={values.condition_type}
            onChange={(e) =>
              set({
                condition_type: e.target.value as StampConditionType,
                condition_params: {},
              })
            }
          >
            <option value="course_complete">{CONDITION_LABEL.course_complete}</option>
            <option value="running_week_course">{CONDITION_LABEL.running_week_course}</option>
            <option value="bingo_lines">{CONDITION_LABEL.bingo_lines}</option>
            <option value="manual">{CONDITION_LABEL.manual}</option>
          </select>
          {values.condition_type === 'manual' && (
            <div className="hint">운영진이 데이터에 직접 넣어 지급해요(지금은 지급 계획 없음).</div>
          )}
        </div>
        {(values.condition_type === 'running_week_course' ||
          values.condition_type === 'bingo_lines') && (
          <div className="field">
            <label htmlFor="stamp-week">러닝위크 회차</label>
            <SearchSelect
              id="stamp-week"
              value={values.condition_params.running_week_id ?? ''}
              options={weeks.map((week) => ({ id: week.id, label: `${week.round}회 ${week.title}` }))}
              onSelect={(id) =>
                set({ condition_params: { ...values.condition_params, running_week_id: id } })
              }
              emptyText="등록된 러닝위크가 없어요"
            />
          </div>
        )}
        {(values.condition_type === 'course_complete' ||
          values.condition_type === 'running_week_course') && (
          <div className="field">
            <label htmlFor="stamp-course">
              코스
              {values.condition_type === 'running_week_course' && (
                <span className="hint">참가 신청한 사람이 이 회차 공개 기간에 완주하면 받아요. 빙고 칸이 돼요</span>
              )}
            </label>
            <SearchSelect
              id="stamp-course"
              value={values.condition_params.course_id ?? ''}
              options={courses.map((course) => ({ id: course.id, label: course.name }))}
              onSelect={(id) =>
                set({ condition_params: { ...values.condition_params, course_id: id } })
              }
              emptyText="등록된 코스가 없어요"
            />
          </div>
        )}
        {values.condition_type === 'bingo_lines' && (
          <div className="field">
            <label htmlFor="stamp-lines">
              줄 수{' '}
              <span className="hint">
                이 회차 빙고판에서 몇 줄을 채우면 받는지. {MAX_BINGO_LINES}이면 판 전체(=25개 코스
                완주) 스페셜 스탬프. 참가 신청한 사람만 받아요
              </span>
            </label>
            <input
              id="stamp-lines"
              type="number"
              min={1}
              max={MAX_BINGO_LINES}
              value={values.condition_params.lines ?? ''}
              onChange={(e) =>
                set({
                  condition_params: {
                    ...values.condition_params,
                    lines: e.target.value ? Number(e.target.value) : undefined,
                  },
                })
              }
            />
          </div>
        )}
        <div className="field">
          <label htmlFor="stamp-order">
            정렬 <span className="hint">작을수록 앞. 앱 스탬프 탭 순서</span>
          </label>
          <input
            id="stamp-order"
            type="number"
            value={values.sort_order}
            onChange={(e) => set({ sort_order: Number(e.target.value) || 0 })}
          />
        </div>
        <div className="field">
          <label>
            <input
              type="checkbox"
              checked={values.is_active}
              onChange={(e) => set({ is_active: e.target.checked })}
            />{' '}
            앱에 노출
          </label>
        </div>
        {error && <div className="error">{error}</div>}
        <div className="submit-row">
          <button onClick={save} disabled={saving}>
            {saving ? '저장 중…' : stamp ? '저장' : '등록'}
          </button>
        </div>
      </div>
      {stamp && <StampImageSection stamp={stamp} onSaved={onSaved} />}
    </Modal>
  )
}

function StampImageSection({
  stamp,
  onSaved,
}: {
  stamp: StampDefinition
  onSaved: (stamp: StampDefinition) => void
}) {
  const [file, setFile] = useState<File | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)

  // 고르는 순간 규격을 검사해 틀린 파일은 선택 자체를 무효로 한다.
  const pick = async (picked: File | null) => {
    setError(null)
    if (!picked) {
      setFile(null)
      return
    }
    const problem = await validateStampImage(picked)
    if (problem) {
      setError(problem)
      setFile(null)
      return
    }
    setFile(picked)
  }

  const run = async (action: () => Promise<StampDefinition>, failure: string) => {
    setError(null)
    setSaving(true)
    try {
      onSaved(await action())
      setFile(null)
    } catch (err) {
      setError(err instanceof ApiError ? err.message : failure)
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="card">
      <h3 style={{ marginTop: 0 }}>도안</h3>
      <p className="muted">
        앱이 원 안에 꽉 채워 그려요. 바꾸면 이미 받은 사람에게도 반영돼요. {STAMP_SPEC.hint}.
      </p>
      {stamp.image_url ? (
        <img className="thumb large round" src={stamp.image_url} alt="현재 도안" />
      ) : (
        <p className="muted">등록된 도안이 없어요(앱은 기본 도안을 써요).</p>
      )}
      <div className="field" style={{ marginTop: 12 }}>
        <input
          type="file"
          accept="image/jpeg,image/png,image/webp"
          onChange={(event) => pick(event.target.files?.[0] ?? null)}
        />
      </div>
      {error && <div className="error">{error}</div>}
      <div className="submit-row">
        <button
          onClick={() => file && run(() => setStampImage(stamp.id, file), '도안 업로드에 실패했어요.')}
          disabled={saving || !file}
        >
          {saving ? '처리 중…' : stamp.image_url ? '도안 교체' : '도안 등록'}
        </button>
        {stamp.image_url && (
          <button
            className="danger"
            onClick={() => run(() => deleteStampImage(stamp.id), '도안 삭제에 실패했어요.')}
            disabled={saving}
          >
            도안 삭제
          </button>
        )}
      </div>
    </div>
  )
}
