// 이미지 규격 검사. 서버는 타입·용량만 보고 픽셀 크기는 안 본다(이미지 디코딩
// 라이브러리 없음) — 규격은 여기서 올리기 전에 막는다.

export const IMAGE_TYPES = ['image/jpeg', 'image/png', 'image/webp']
export const MAX_IMAGE_BYTES = 8 * 1024 * 1024

/** 완주 스탬프 도안. 앱이 원 안에 꽉 채워 그리므로 정사각형이어야 하고,
 * 3x 기기에서도 선명하도록 최소 512px. 상한은 용량 낭비를 막는 선. */
export const STAMP_SPEC = {
  minSide: 512,
  maxSide: 2048,
  hint: '정사각형(1:1) png/jpg/webp, 한 변 512~2048px, 8MB 이하. 배경 투명 png 권장',
} as const

/** 공지 배너. 앱 홈 상단에 21:9로 꽉 채워(cover) 그리므로 비율이 다르면 잘린다.
 * 앱 banner_carousel._kBannerAspectRatio와 같아야 한다. */
export const BANNER_SPEC = {
  ratio: 7 / 3,
  /** 비율 허용 오차. 1680×720 기준 ±1px 반올림 정도. */
  ratioTolerance: 0.01,
  minWidth: 1260,
  maxWidth: 4096,
  hint: '가로 21:9 jpg/png/webp, 1680×720 권장(최소 1260×540), 8MB 이하',
} as const

export interface ImageSize {
  width: number
  height: number
}

/** 브라우저가 디코드한 픽셀 크기. 이미지가 아니거나 깨졌으면 reject. */
export function readImageSize(file: File): Promise<ImageSize> {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file)
    const img = new Image()
    img.onload = () => {
      URL.revokeObjectURL(url)
      resolve({ width: img.naturalWidth, height: img.naturalHeight })
    }
    img.onerror = () => {
      URL.revokeObjectURL(url)
      reject(new Error('이미지를 읽을 수 없어요.'))
    }
    img.src = url
  })
}

function checkCommon(file: File): string | null {
  if (!IMAGE_TYPES.includes(file.type)) return 'jpg/png/webp 이미지만 올릴 수 있어요.'
  if (file.size > MAX_IMAGE_BYTES) return '이미지가 너무 커요. 8MB 이하여야 해요.'
  return null
}

/** 스탬프 도안 규격 검사. 통과하면 null, 아니면 사용자에게 보여줄 메시지. */
export async function validateStampImage(file: File): Promise<string | null> {
  const common = checkCommon(file)
  if (common) return common

  let size: ImageSize
  try {
    size = await readImageSize(file)
  } catch (err) {
    return err instanceof Error ? err.message : '이미지를 읽을 수 없어요.'
  }
  const { width, height } = size
  const { minSide, maxSide } = STAMP_SPEC
  if (width !== height) {
    return `정사각형이어야 해요. (현재 ${width}×${height})`
  }
  if (width < minSide) return `한 변이 ${minSide}px 이상이어야 해요. (현재 ${width}px)`
  if (width > maxSide) return `한 변이 ${maxSide}px 이하여야 해요. (현재 ${width}px)`
  return null
}

/** 공지 배너 규격 검사. 통과하면 null, 아니면 사용자에게 보여줄 메시지. */
export async function validateBannerImage(file: File): Promise<string | null> {
  const common = checkCommon(file)
  if (common) return common

  let size: ImageSize
  try {
    size = await readImageSize(file)
  } catch (err) {
    return err instanceof Error ? err.message : '이미지를 읽을 수 없어요.'
  }
  const { width, height } = size
  const { ratio, ratioTolerance, minWidth, maxWidth } = BANNER_SPEC
  if (Math.abs(width / height - ratio) > ratioTolerance) {
    return `가로 21:9여야 해요. 예) 1680×720 (현재 ${width}×${height})`
  }
  if (width < minWidth) return `가로가 ${minWidth}px 이상이어야 해요. (현재 ${width}px)`
  if (width > maxWidth) return `가로가 ${maxWidth}px 이하여야 해요. (현재 ${width}px)`
  return null
}
