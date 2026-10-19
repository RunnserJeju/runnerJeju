/** 표 데이터를 CSV 파일로 내려받게 한다. 브라우저에서 바로 만든다(서버 왕복 없음). */
export function downloadCsv(
  filename: string,
  header: string[],
  rows: (string | number | null | undefined)[][],
) {
  const escape = (value: string | number | null | undefined) => {
    let text = value == null ? '' : String(value)
    // 사용자가 적은 값이 = + - @로 시작하면 엑셀이 수식으로 실행한다. 앞에 '를 붙여 글자로 둔다.
    if (typeof value === 'string' && /^[=+\-@\t\r]/.test(text)) text = `'${text}`
    // 쉼표·따옴표·줄바꿈이 있으면 따옴표로 감싸고 내부 따옴표는 두 번 쓴다.
    return /[",\r\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text
  }
  const lines = [header, ...rows].map((row) => row.map(escape).join(','))
  // BOM을 붙여야 엑셀이 한글을 UTF-8로 읽는다.
  const blob = new Blob(['﻿' + lines.join('\n')], { type: 'text/csv;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  a.click()
  URL.revokeObjectURL(url)
}
