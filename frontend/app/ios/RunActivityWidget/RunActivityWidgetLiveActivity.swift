//
//  RunActivityWidgetLiveActivity.swift
//  RunActivityWidget
//
//  러닝 상태를 잠금화면 + Dynamic Island에 띄우는 Live Activity.
//  데이터는 Flutter의 live_activities 패키지가 App Group UserDefaults에
//  `{activityId}_key` 형태로 넣어주고, 여기서 prefixedKey로 읽어 그린다.
//  키: distanceKm(String) · time(String) · pace(String) · paused(Bool)
//

import ActivityKit
import WidgetKit
import SwiftUI

// live_activities 패키지가 요구하는 고정 attributes 파이프.
// (이 타입 이름은 바꾸지 말 것 — 패키지 네이티브 쪽이 이 타입으로 활동을 만든다.)
struct LiveActivitiesAppAttributes: ActivityAttributes, Identifiable {
  public typealias LiveDeliveryData = ContentState

  public struct ContentState: Codable, Hashable {}

  var id = UUID()
}

// ⚠️ suiteName은 Flutter의 RunLiveWidget._appGroupId와 반드시 동일해야 한다.
// App Group capability가 아직 없으면(무료 팀 등) 공유 컨테이너가 없어 nil이
// 될 수 있으므로 .standard로 폴백한다 — 이 경우 값은 placeholder로만 뜬다.
let sharedDefault = UserDefaults(suiteName: "group.com.runnersjeju.runnersJeju") ?? .standard

extension LiveActivitiesAppAttributes {
  func prefixedKey(_ key: String) -> String {
    return "\(id)_\(key)"
  }
}

@available(iOS 16.1, *)
struct RunActivityWidgetLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: LiveActivitiesAppAttributes.self) { context in
      // ── 잠금화면 카드 ──
      RunLockScreenView(
        distanceKm: sharedDefault.string(forKey: context.attributes.prefixedKey("distanceKm")) ?? "0.00",
        time: sharedDefault.string(forKey: context.attributes.prefixedKey("time")) ?? "00:00",
        pace: sharedDefault.string(forKey: context.attributes.prefixedKey("pace")) ?? "--'--\"",
        paused: sharedDefault.bool(forKey: context.attributes.prefixedKey("paused"))
      )
      .padding(16)
      .activityBackgroundTint(Color.black.opacity(0.85))
      .activitySystemActionForegroundColor(Color.white)

    } dynamicIsland: { context in
      let distanceKm = sharedDefault.string(forKey: context.attributes.prefixedKey("distanceKm")) ?? "0.00"
      let time = sharedDefault.string(forKey: context.attributes.prefixedKey("time")) ?? "00:00"
      let pace = sharedDefault.string(forKey: context.attributes.prefixedKey("pace")) ?? "--'--\""
      let paused = sharedDefault.bool(forKey: context.attributes.prefixedKey("paused"))

      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Label(paused ? "일시정지" : "러닝 중", systemImage: paused ? "pause.circle.fill" : "figure.run")
            .font(.caption)
            .foregroundStyle(paused ? .orange : .green)
            .padding(.leading, 4)
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text("\(distanceKm) km")
            .font(.headline).monospacedDigit()
            .padding(.trailing, 4)
        }
        DynamicIslandExpandedRegion(.bottom) {
          HStack {
            islandMetric(title: "시간", value: time)
            Spacer()
            islandMetric(title: "페이스", value: pace)
          }
          .padding(.horizontal, 4)
        }
      } compactLeading: {
        Image(systemName: paused ? "pause.fill" : "figure.run")
          .foregroundStyle(paused ? .orange : .green)
      } compactTrailing: {
        Text("\(distanceKm)km").font(.caption2).monospacedDigit()
      } minimal: {
        Image(systemName: paused ? "pause.fill" : "figure.run")
          .foregroundStyle(paused ? .orange : .green)
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
@available(iOS 16.1, *)
struct RunLockScreenView: View {
  let distanceKm: String
  let time: String
  let pace: String
  let paused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 6) {
        Image(systemName: paused ? "pause.circle.fill" : "figure.run")
          .foregroundStyle(paused ? .orange : .green)
        Text(paused ? "러닝 일시정지" : "러닝 중")
          .font(.subheadline).fontWeight(.bold)
          .foregroundStyle(.white)
        Spacer()
      }

      HStack(alignment: .firstTextBaseline) {
        // 거리 (강조)
        VStack(alignment: .leading, spacing: 2) {
          Text("거리 (KM)").font(.caption2).foregroundStyle(.white.opacity(0.6))
          Text(distanceKm)
            .font(.system(size: 34, weight: .heavy)).monospacedDigit()
            .foregroundStyle(.white)
        }
        Spacer()
        metricColumn(title: "시간", value: time)
        Spacer()
        metricColumn(title: "페이스", value: pace)
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
