import type { Notice, NoticePayload } from '../api'

/** 등록/수정이 공유하는 공지 폼 값. 기간은 datetime-local 문자열(로컬 시각)로
 * 들고, 제출 시 validate()가 ISO(UTC)로 바꾼다. 빈 문자열 = 제한 없음. */
export interface NoticeFormValues {
  title: string
  body: string
  startsAt: string
  endsAt: string
}

export function emptyNoticeValues(): NoticeFormValues {
  return { title: '', body: '', startsAt: '', endsAt: '' }
}

/** ISO(UTC) → datetime-local 입력값("YYYY-MM-DDTHH:mm", 로컬 시각). */
function toLocalInput(iso: string | null): string {
  if (!iso) return ''
  const d = new Date(iso)
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`
}

export function valuesFromNotice(notice: Notice): NoticeFormValues {
  return {
    title: notice.title,
    body: notice.body,
    startsAt: toLocalInput(notice.starts_at),
    endsAt: toLocalInput(notice.ends_at),
  }
}

/** 서버 규칙(app/schemas.py NoticeCreate)과 같은 검사. */
export function validateNotice(
  values: NoticeFormValues,
): { ok: true; data: NoticePayload } | { ok: false; message: string } {
  const title = values.title.trim()
  const body = values.body.trim()
  if (!title) return { ok: false, message: '제목을 입력해 주세요.' }
  if (title.length > 200) return { ok: false, message: '제목은 200자 이하여야 해요.' }
  if (!body) return { ok: false, message: '내용을 입력해 주세요.' }

  const startsAt = values.startsAt ? new Date(values.startsAt) : null
  const endsAt = values.endsAt ? new Date(values.endsAt) : null
  if (startsAt && endsAt && endsAt < startsAt) {
    return { ok: false, message: '노출 종료가 시작보다 빠를 수 없어요.' }
  }

  return {
    ok: true,
    data: {
      title,
      body,
      starts_at: startsAt ? startsAt.toISOString() : null,
      ends_at: endsAt ? endsAt.toISOString() : null,
    },
  }
}

interface Props {
  values: NoticeFormValues
  onChange: (values: NoticeFormValues) => void
}

export default function NoticeForm({ values, onChange }: Props) {
  const set = (patch: Partial<NoticeFormValues>) => onChange({ ...values, ...patch })

  return (
    <>
      <div className="field">
        <label htmlFor="notice-title">제목</label>
        <input
          id="notice-title"
          type="text"
          maxLength={200}
          value={values.title}
          onChange={(event) => set({ title: event.target.value })}
        />
      </div>
      <div className="field">
        <label htmlFor="notice-body">내용</label>
        <textarea
          id="notice-body"
          value={values.body}
          onChange={(event) => set({ body: event.target.value })}
        />
      </div>
      <div className="row">
        <div className="field">
          <label htmlFor="notice-starts">
            노출 시작 <span className="hint">비우면 즉시</span>
          </label>
          <input
            id="notice-starts"
            type="datetime-local"
            value={values.startsAt}
            onChange={(event) => set({ startsAt: event.target.value })}
          />
        </div>
        <div className="field">
          <label htmlFor="notice-ends">
            노출 종료 <span className="hint">비우면 무기한</span>
          </label>
          <input
            id="notice-ends"
            type="datetime-local"
            value={values.endsAt}
            onChange={(event) => set({ endsAt: event.target.value })}
          />
        </div>
      </div>
    </>
  )
}
