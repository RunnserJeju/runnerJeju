interface Props {
  /** 저장 안 된 변경 항목 이름들. 비어 있으면 저장 버튼이 꺼진다. */
  dirty: string[]
  saving: boolean
  error: string | null
  onSave: () => void
  /** 기본 '전체 저장'. 새로 등록할 때는 '등록'. */
  label?: string
  /** 변경이 없어도 누를 수 있게(새로 등록). */
  alwaysEnabled?: boolean
}

/** 편집 창 우측 아래의 저장 영역. 편집 창에서 고친 모든 것의 저장을 이 버튼 하나가 맡는다. */
export default function SaveFooter({ dirty, saving, error, onSave, label = '전체 저장', alwaysEnabled }: Props) {
  return (
    <div className="modal-foot">
      {error ? (
        <div className="foot-msg error">{error}</div>
      ) : (
        <div className="foot-msg muted">
          {dirty.length > 0 ? `저장 안 된 변경: ${dirty.join(', ')}` : '변경된 내용이 없어요.'}
        </div>
      )}
      <button onClick={onSave} disabled={saving || (!alwaysEnabled && dirty.length === 0)}>
        {saving ? '저장 중…' : label}
      </button>
    </div>
  )
}
