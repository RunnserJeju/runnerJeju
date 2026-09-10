//
//  RunActivityWidgetLiveActivity.swift
//  RunActivityWidget
//
//  러닝 상태를 잠금화면 + Dynamic Island에 띄우는 Live Activity.
//  값은 Runner(RunLiveActivityChannel)가 activity.update 로 넘기는
//  RunActivityAttributes.ContentState 이고 context.state 로 읽는다. 공유 저장소
//  (App Group)를 거치지 않으므로 별도 capability 가 필요 없다.
//  RunActivityAttributes.swift 는 Runner/ 에 있고 이 타겟에도 컴파일된다.
//

import ActivityKit
import WidgetKit
import SwiftUI

@available(iOS 16.2, *)
struct RunActivityWidgetLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: RunActivityAttributes.self) { context in
      // ── 잠금화면 카드 ──
      RunLockScreenView(state: context.state)
        .padding(16)
        .activityBackgroundTint(Color.black.opacity(0.85))
        .activitySystemActionForegroundColor(Color.white)

    } dynamicIsland: { context in
      let state = context.state

      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Label(
            state.paused ? "일시정지" : "러닝 중",
            systemImage: state.paused ? "pause.circle.fill" : "figure.run"
          )
          .font(.caption)
          .foregroundStyle(state.paused ? .orange : .green)
          .padding(.leading, 4)
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text("\(state.distanceKm) km")
            .font(.headline).monospacedDigit()
            .padding(.trailing, 4)
        }
        DynamicIslandExpandedRegion(.bottom) {
          HStack {
            islandMetric(title: "시간", value: state.time)
            Spacer()
            islandMetric(title: "페이스", value: state.pace)
          }
          .padding(.horizontal, 4)
        }
      } compactLeading: {
        Image(systemName: state.paused ? "pause.fill" : "figure.run")
          .foregroundStyle(state.paused ? .orange : .green)
      } compactTrailing: {
        Text("\(state.distanceKm)km").font(.caption2).monospacedDigit()
      } minimal: {
        Image(systemName: state.paused ? "pause.fill" : "figure.run")
          .foregroundStyle(state.paused ? .orange : .green)
      }
    }
  }

  @ViewBuilder
  private func islandMetric(title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(title).font(.caption2).foregroundStyle(.secondary)
      Text(value).font(.callout).fontWeight(.semibold).monospacedDigit()
    }
  }
}

// ── 잠금화면 카드 뷰 ──
@available(iOS 16.2, *)
struct RunLockScreenView: View {
  let state: RunActivityAttributes.ContentState

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 6) {
        Image(systemName: state.paused ? "pause.circle.fill" : "figure.run")
          .foregroundStyle(state.paused ? .orange : .green)
        Text(state.paused ? "러닝 일시정지" : "러닝 중")
          .font(.subheadline).fontWeight(.bold)
          .foregroundStyle(.white)
        Spacer()
      }

      HStack(alignment: .firstTextBaseline) {
        // 거리 (강조)
        VStack(alignment: .leading, spacing: 2) {
          Text("거리 (KM)").font(.caption2).foregroundStyle(.white.opacity(0.6))
          Text(state.distanceKm)
            .font(.system(size: 34, weight: .heavy)).monospacedDigit()
            .foregroundStyle(.white)
        }
        Spacer()
        metricColumn(title: "시간", value: state.time)
        Spacer()
        metricColumn(title: "페이스", value: state.pace)
      }
    }
  }

  @ViewBuilder
  private func metricColumn(title: String, value: String) -> some View {
    VStack(alignment: .trailing, spacing: 2) {
      Text(title).font(.caption2).foregroundStyle(.white.opacity(0.6))
      Text(value)
        .font(.title3).fontWeight(.semibold).monospacedDigit()
        .foregroundStyle(.white)
    }
  }
}
