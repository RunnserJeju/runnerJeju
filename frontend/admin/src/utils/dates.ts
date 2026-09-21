/** 서버 지표의 '하루'는 KST 기준이라 브라우저 시간대와 무관하게 KST 날짜를 만든다. */
const KST_OFFSET_MS = 9 * 60 * 60 * 1000

export function kstToday(): string {
  return new Date(Date.now() + KST_OFFSET_MS).toISOString().slice(0, 10)
}

/** 오늘을 포함해 최근 days일의 시작 날짜. */
export function kstDaysAgo(days: number): string {
  return new Date(Date.now() + KST_OFFSET_MS - (days - 1) * 86400000)
    .toISOString()
    .slice(0, 10)
}

/** 'YYYY-MM-DD' → 'M/D'. 차트 축 라벨용. */
export function shortDate(iso: string): string {
  const [, m, d] = iso.split('-')
  return `${Number(m)}/${Number(d)}`
}
