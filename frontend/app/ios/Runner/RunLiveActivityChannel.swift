//
//  RunLiveActivityChannel.swift
//  Runner
//
//  Flutter(RunLiveWidget) ↔ ActivityKit 다리. 러닝 상태를 잠금화면 + Dynamic
//  Island의 Live Activity로 띄운다. 메서드: isSupported · start · update · stop.
//  활동은 한 번에 하나만 유지한다(start가 이전 활동을 먼저 걷는다).
//  값은 RunActivityAttributes.ContentState로 넘어가므로 App Group·푸시 같은
//  추가 capability가 필요 없다. Info.plist의 NSSupportsLiveActivities면 충분하다.
//

import ActivityKit
import Flutter
import Foundation
import UIKit

enum RunLiveActivityChannel {
  static let name = "com.runnersjeju.runnersJeju/run_live_activity"

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: name, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard #available(iOS 16.2, *) else {
        // ActivityKit 미지원 기기. isSupported만 false로 답하고 나머지는 no-op.
        result(call.method == "isSupported" ? false : nil)
        return
      }
      switch call.method {
      case "isSupported":
        // 사용자가 설정에서 이 앱의 Live Activity를 끄면 false.
        result(ActivityAuthorizationInfo().areActivitiesEnabled)

      case "start", "update":
        guard let state = contentState(from: call.arguments) else {
          result(FlutterError(
            code: "bad_args",
            message: "distanceKm·time·pace·paused 가 모두 필요합니다",
            details: nil))
          return
        }
        let isStart = call.method == "start"
        // FlutterResult는 플랫폼(메인) 스레드에서 불러야 한다.
        Task { @MainActor in
          if isStart {
            result(await start(state))
          } else {
            await update(state)
            result(nil)
          }
        }

      case "stop":
        Task { @MainActor in
          await endAll()
          result(nil)
        }

      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // 러닝 중 앱이 죽으면 tracker도 같이 죽으니 잠금화면에 위젯을 남기지 않는다.
    // (백그라운드 위치 모드로 살아 있는 앱을 앱 전환기에서 밀어 끌 때 이게 온다.)
    NotificationCenter.default.addObserver(
      forName: UIApplication.willTerminateNotification, object: nil, queue: .main
    ) { _ in
      endAllBlocking()
    }
  }

  /// 앱 시작 시 호출. 이전 실행(크래시 등)이 남긴 활동을 정리한다.
  static func endLeftovers() {
    guard #available(iOS 16.2, *) else { return }
    Task { await endAll() }
  }

  /// 앱이 죽기 직전 호출. 비동기 end가 끝날 시간을 잠깐만 준다 — willTerminate는
  /// 몇 초 안에 돌아와야 한다.
  private static func endAllBlocking(timeout: TimeInterval = 2) {
    guard #available(iOS 16.2, *) else { return }
    let done = DispatchSemaphore(value: 0)
    Task {
      await endAll()
      done.signal()
    }
    _ = done.wait(timeout: .now() + timeout)
  }

  // MARK: - ActivityKit

  @available(iOS 16.2, *)
  private static func start(_ state: RunActivityAttributes.ContentState) async -> Bool {
    // 이전 러닝의 활동이 남아 있으면 걷어내고 새로 만든다.
    await endAll()
    do {
      _ = try Activity.request(
        attributes: RunActivityAttributes(),
        content: ActivityContent(state: state, staleDate: nil),
        pushType: nil)  // 앱이 직접 갱신한다 — 푸시·원격 갱신 권한 불필요.
      return true
    } catch {
      // 사용자가 Live Activity를 껐거나 시스템 활동 수 제한에 걸린 경우.
      return false
    }
  }

  @available(iOS 16.2, *)
  private static func update(_ state: RunActivityAttributes.ContentState) async {
    // 사용자가 잠금화면에서 지웠으면 목록이 비어 있고, 그럼 조용히 넘어간다.
    for activity in Activity<RunActivityAttributes>.activities {
      await activity.update(ActivityContent(state: state, staleDate: nil))
    }
  }

  @available(iOS 16.2, *)
  private static func endAll() async {
    for activity in Activity<RunActivityAttributes>.activities {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
  }

  @available(iOS 16.2, *)
  private static func contentState(from arguments: Any?) -> RunActivityAttributes.ContentState? {
    guard let args = arguments as? [String: Any],
          let distanceKm = args["distanceKm"] as? String,
          let time = args["time"] as? String,
          let pace = args["pace"] as? String,
          let paused = args["paused"] as? Bool
    else { return nil }
    return .init(distanceKm: distanceKm, time: time, pace: pace, paused: paused)
  }
}
