/** 표 데이터를 CSV 파일로 내려받게 한다. 브라우저에서 바로 만든다(서버 왕복 없음). */
export function downloadCsv(
  filename: string,
  header: string[],
  rows: (string | number | null | undefined)[][],
) {
  const escape = (value: string | number | null | undefined) => {
    const text = value == null ? '' : String(value)
    // 쉼표·따옴표·줄바꿈이 있으면 따옴표로 감싸고 내부 따옴표는 두 번 쓴다.
    return /[",\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text
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
