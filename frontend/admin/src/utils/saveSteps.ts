import { ApiError } from '../api'

/** 전체 저장의 한 단계. 성공하면 run이 화면 상태를 '저장된 값'으로 갈아끼워야 한다 —
 * 그래야 중간에 실패해 다시 눌렀을 때 이미 저장된 단계는 다시 안 나간다. */
export interface SaveStep {
  label: string
  run: () => Promise<void>
}

/** 단계를 순서대로 실행한다. 처음 실패에서 멈추고 오류 문구를, 다 되면 null을 돌려준다. */
export async function runSteps(steps: SaveStep[]): Promise<string | null> {
  for (const step of steps) {
    try {
      await step.run()
    } catch (err) {
      const reason = err instanceof ApiError || err instanceof Error ? err.message : '알 수 없는 오류'
      return `${step.label} 저장 실패: ${reason} (앞 단계는 저장됐어요. 다시 누르면 남은 것만 저장해요.)`
    }
  }
  return null
}

/** 값이 바뀌었는지 비교하려고 직렬화한 키. */
export const snapshot = (value: unknown): string => JSON.stringify(value)
