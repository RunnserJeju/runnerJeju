import { useCallback, useEffect, useState } from 'react'

import {
  ApiError,
  deleteStampImage,
  issueStamp,
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
import {
  ImageSection,
  imageChanged,
  NO_IMAGE_CHANGE,
  type ImageChange,
} from '../components/ImageSections'
import Modal from '../components/Modal'
import SaveFooter from '../components/SaveFooter'
import UserIssuePicker from '../components/UserIssuePicker'
import SortTh, { useSort } from '../components/SortTh'
import { runSteps, snapshot, type SaveStep } from '../utils/saveSteps'

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
  const { sort, toggle, sorted } = useSort(stamps, {
    name: (s) => s.name,
    condition: (s) => CONDITION_LABEL[s.condition_type] ?? s.condition_type,
    active: (s) => s.is_active,
    issued: (s) => s.issued_count,
    order: (s) => s.sort_order,
  })

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
        코스를 등록하면 그 코스의 완주 스탬프가 자동으로 하나 생겨요. 여기서는
        이름·안내·도안·정렬·노출만 고쳐요.
      </p>
      {error && <div className="error">{error}</div>}
      {stamps == null && !error && <p className="muted">불러오는 중…</p>}
      {stamps && stamps.length === 0 && <p className="muted">등록된 스탬프가 없어요.</p>}
      {stamps && stamps.length > 0 && (
        <table>
          <thead>
            <tr>
              <th></th>
              <SortTh sortKey="name" sort={sort} onToggle={toggle}>
                이름
              </SortTh>
              <SortTh sortKey="condition" sort={sort} onToggle={toggle}>
                획득 조건
              </SortTh>
              <SortTh sortKey="active" sort={sort} onToggle={toggle}>
                상태
              </SortTh>
              <SortTh sortKey="issued" sort={sort} onToggle={toggle}>
                받은 사람
              </SortTh>
              <SortTh sortKey="order" sort={sort} onToggle={toggle}>
                정렬
              </SortTh>
            </tr>
          </thead>
          <tbody>
            {sorted!.map((stamp) => {
              const detail = conditionDetail(stamp, courses, weeks)
              return (
                <tr key={stamp.id} onClick={() => setEditing(stamp)}>
                  <td style={{ width: 64 }}>
                    {stamp.display_image_url ? (
                      <img className="thumb round" src={stamp.display_image_url} alt="" />
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
  /** 서버에 저장된 내용의 스냅샷. values와 다르면 '내용 변경'이다. */
  const [savedKey, setSavedKey] = useState(() => snapshot(payloadFrom(stamp)))
  const [image, setImage] = useState<ImageChange>(NO_IMAGE_CHANGE)
  const [error, setError] = useState<string | null>(null)
  const [message, setMessage] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)
  const [tab, setTab] = useState<'edit' | 'issue'>('edit')

  const set = (patch: Partial<StampDefinitionPayload>) => {
    setValues((prev) => ({ ...prev, ...patch }))
    setMessage(null)
  }

  const contentDirty = snapshot(values) !== savedKey
  const imageDirty = imageChanged(image)
  const dirty = [contentDirty && '내용', imageDirty && '도안'].filter((label): label is string =>
    Boolean(label),
  )

  const save = async () => {
    if (dirty.length === 0) return
    setError(null)
    setMessage(null)
    if (contentDirty && !values.name.trim()) {
      setError('이름을 입력해 주세요.')
      return
    }

    let latest: StampDefinition | null = null
    const steps: SaveStep[] = []
    if (contentDirty) {
      const snap = snapshot(values)
      steps.push({
        label: '내용',
        run: async () => {
          latest = await updateStamp(stamp.id, {
            ...values,
            name: values.name.trim(),
            description: values.description?.trim() || null,
          })
          setSavedKey(snap)
        },
      })
    }
    if (imageDirty) {
      const { file } = image
      steps.push({
        label: '도안',
        run: async () => {
          latest = file ? await setStampImage(stamp.id, file) : await deleteStampImage(stamp.id)
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
    setMessage('저장했어요.')
  }

  return (
    <Modal
      title={`스탬프 — ${stamp.name}`}
      onClose={onClose}
      closable={!saving}
      footer={
        tab === 'edit' ? (
          <SaveFooter dirty={dirty} saving={saving} error={error} onSave={save} />
        ) : undefined
      }
    >
      <div className="tabs" style={{ marginTop: 0, marginBottom: 12 }}>
        <button className={tab === 'edit' ? 'active' : undefined} onClick={() => setTab('edit')}>
          수정
        </button>
        <button className={tab === 'issue' ? 'active' : undefined} onClick={() => setTab('issue')}>
          지급
        </button>
      </div>
      {tab === 'issue' && (
        <>
          <p className="muted" style={{ marginTop: 0 }}>
            획득 조건과 노출 여부, 러닝위크 기간을 따지지 않고 스탬프만 줘요. 쿠폰 추첨이나 빙고 줄
            보상은 따라 나가지 않아요. 이미 가진 회원은 건너뛰어요.
          </p>
          <UserIssuePicker
            confirmText={(count) => `${count}명에게 "${stamp.name}" 스탬프를 지급할까요?`}
            onIssue={async (userIds) => {
              const result = await issueStamp(stamp.id, userIds)
              onSaved({ ...stamp, issued_count: stamp.issued_count + result.issued })
              return result.skipped > 0
                ? `${result.issued}명에게 지급했어요. (${result.skipped}명은 이미 갖고 있어 건너뜀)`
                : `${result.issued}명에게 지급했어요.`
            }}
          />
        </>
      )}
      {tab === 'edit' && (
        <>
          {message && (
            <div className="notice" style={{ marginTop: 0 }}>
              {message}
            </div>
          )}
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
          </div>
          <ImageSection
            title="도안"
            description={`앱이 원 안에 꽉 채워 그려요. 바꾸면 이미 받은 사람에게도 반영돼요. ${STAMP_SPEC.hint}.`}
            imageClass="thumb large round"
            currentUrl={stamp.display_image_url}
            removable={Boolean(stamp.image_url)}
            value={image}
            onChange={setImage}
            validate={validateStampImage}
          />
        </>
      )}
    </Modal>
  )
}
