import { NOTICE_APP_LINK_PREFIX, type Notice, type NoticePayload } from '../api'

/** 등록/수정이 공유하는 공지 폼 값. 기간은 datetime-local 문자열(로컬 시각)로
 * 들고, 제출 시 validate()가 ISO(UTC)로 바꾼다. 빈 문자열 = 제한 없음. */
export interface NoticeFormValues {
  title: string
  body: string
  /** 외부 주소. 개발자가 넣은 앱 화면(app:…)이면 그 값을 그대로 들고 있다가 돌려보낸다. */
  linkUrl: string
  linkLabel: string
  startsAt: string
  endsAt: string
}

export function emptyNoticeValues(): NoticeFormValues {
  return { title: '', body: '', linkUrl: '', linkLabel: '', startsAt: '', endsAt: '' }
}

const isAppLink = (url: string) => url.startsWith(NOTICE_APP_LINK_PREFIX)

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
    linkUrl: notice.link_url ?? '',
    linkLabel: notice.link_label ?? '',
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

  const linkUrl = values.linkUrl.trim()
  const linkLabel = values.linkLabel.trim()
  if (linkUrl && !isAppLink(linkUrl) && !/^https?:\/\/\S+$/.test(linkUrl)) {
    return { ok: false, message: '링크는 http:// 또는 https://로 시작해야 해요.' }
  }
  if (linkLabel.length > 40) return { ok: false, message: '버튼 문구는 40자 이하여야 해요.' }

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
      link_url: linkUrl || null,
      link_label: linkUrl && linkLabel ? linkLabel : null,
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
          <label htmlFor="notice-link">
            버튼 링크 <span className="hint">다른 화면(혹은 외부 앱) 이동 필요 시 작성. 비우면 버튼 없음</span>
          </label>
          {isAppLink(values.linkUrl) ? (
            // 앱 화면 연결은 개발자가 DB에 넣는다 — 여기선 보여 주고 끊을 수만 있다.
            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              <span className="muted">앱 화면 연결: {values.linkUrl} (개발자 설정)</span>
              <button type="button" className="secondary" onClick={() => set({ linkUrl: '' })}>
                연결 해제
              </button>
            </div>
          ) : (
            <input
              id="notice-link"
              type="url"
              placeholder="https://"
              maxLength={500}
              value={values.linkUrl}
              onChange={(event) => set({ linkUrl: event.target.value })}
            />
          )}
        </div>
        <div className="field">
          <label htmlFor="notice-link-label">
            버튼 문구 <span className="hint">비우면 앱 기본 문구</span>
          </label>
          <input
            id="notice-link-label"
            type="text"
            maxLength={40}
            value={values.linkLabel}
            disabled={!values.linkUrl.trim()}
            onChange={(event) => set({ linkLabel: event.target.value })}
          />
        </div>
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
