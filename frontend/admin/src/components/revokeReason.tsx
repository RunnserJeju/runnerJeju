/** 회수 사유를 묻는다. 비우거나 취소하면 null — 사유 없는 회수는 받지 않는다(이력에 남아야 하므로). */
export function askRevokeReason(message: string): string | null {
  const raw = window.prompt(`${message}\n\n회수 사유를 적어 주세요.`)
  if (raw == null) return null
  const reason = raw.trim()
  if (!reason) {
    window.alert('사유를 적어야 회수할 수 있어요.')
    return null
  }
  return reason.slice(0, 200)
}
