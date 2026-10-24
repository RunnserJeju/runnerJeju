import { useCallback, useEffect, useState } from 'react'

import {
  ApiError,
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

/** 지급 조건의 대상(코스·회차·줄 수)을 글로. 대상이 없는 종류는 null. */
function conditionDetail(
  stamp: StampDefinition,
  courses: Course[],
  weeks: RunningWeek[],
): string | null {
  const params = stamp.condition_params
  const course = () => courses.find((c) => c.id === params.course_id)?.name ?? '(없는 코스)'
  const week = () => {
    const found = weeks.find((w) => w.id === params.running_week_id)
    return found ? `${found.round}회 ${found.title}` : '(없는 회차)'
  }
  switch (stamp.condition_type) {
    case 'course_complete':
      return course()
    case 'running_week_course':
      return `${course()} · ${week()}`
    case 'bingo_lines':
      return `${params.lines}줄${params.lines === MAX_BINGO_LINES ? ' (판 전체)' : ''} · ${week()}`
    default:
      return null
  }
}

/**
 * 스탬프 종류 관리 — 표시 정보(이름·안내·도안·정렬·노출) 수정만 한다. 스탬프 종류는 코스 등록 때
 * 코스 스탬프가 하나 생기고, 그 밖의 종류는 개발자가 DB에 직접 넣는다. 지급 조건은 보여 주기만 한다.
 * 스탬프는 지우지 않고 노출을 끈다(발급 기록이 가리킨다).
 */
export default function StampListPage({ onUnauthorized }: Props) {
  const [stamps, setStamps] = useState<StampDefinition[] | null>(null)
  const [courses, setCourses] = useState<Course[]>([])
  const [weeks, setWeeks] = useState<RunningWeek[]>([])
  const [error, setError] = useState<string | null>(null)
  const [editing, setEditing] = useState<StampDefinition | null>(null)

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

  return (
    <>
      <div className="page-head">
        <h2>스탬프</h2>
      </div>
      <p className="muted page-desc">
        코스를 등록하면 그 코스의 완주 스탬프가 자동으로 하나 생겨요. 여기서는 이름·안내·도안·정렬·노출만
        고쳐요.
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
            {stamps.map((stamp) => {
              const detail = conditionDetail(stamp, courses, weeks)
              return (
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
                    {detail && <div className="muted">{detail}</div>}
                  </td>
                  <td>
                    <span className={`badge ${stamp.is_active ? 'live' : 'expired'}`}>
                      {stamp.is_active ? '노출' : '숨김'}
                    </span>
                  </td>
                  <td className="muted">{stamp.issued_count}명</td>
                  <td className="muted">{stamp.sort_order}</td>
                </tr>
              )
            })}
          </tbody>
        </table>
      )}

      {editing && (
        <StampModal
          stamp={editing}
          condition={[
            CONDITION_LABEL[editing.condition_type] ?? editing.condition_type,
            conditionDetail(editing, courses, weeks),
          ]
            .filter(Boolean)
            .join(' — ')}
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

function payloadFrom(stamp: StampDefinition): StampDefinitionPayload {
  return {
    name: stamp.name,
    description: stamp.description,
    is_active: stamp.is_active,
    sort_order: stamp.sort_order,
  }
}

function StampModal({
  stamp,
  condition,
  onClose,
  onSaved,
}: {
  stamp: StampDefinition
  /** 지급 조건을 글로 — 보여 주기만 한다. */
  condition: string
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
    setSaving(true)
    try {
      const saved = await updateStamp(stamp.id, {
        ...values,
        name: values.name.trim(),
        description: values.description?.trim() || null,
      })
      setMessage('저장했어요.')
      onSaved(saved)
    } catch (err) {
      setError(err instanceof ApiError ? err.message : '저장에 실패했어요.')
    } finally {
      setSaving(false)
    }
  }

  return (
    <Modal title={`스탬프 수정 — ${stamp.name}`} onClose={onClose}>
      {message && <div className="notice" style={{ marginTop: 0 }}>{message}</div>}
      <div className="card">
        <div className="field">
          <label>
            획득 조건 <span className="hint">여기서는 바꿀 수 없어요</span>
          </label>
          <div>{condition}</div>
        </div>
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
            {saving ? '저장 중…' : '저장'}
          </button>
        </div>
      </div>
      <StampImageSection stamp={stamp} onSaved={onSaved} />
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
