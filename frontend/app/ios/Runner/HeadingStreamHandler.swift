//
//  HeadingStreamHandler.swift
//  Runner
//
//  폰이 향한 방향(진북 기준, 도)을 Flutter(HeadingService)로 흘려보낸다.
//  Core Location이 융합한 heading을 쓴다. 이벤트는 {heading, accuracy(도,
//  모르면 -1), calibrated}. 진북을 못 구하면(trueHeading < 0) 보내지 않는다.
//

import CoreLocation
import Flutter
import UIKit

final class HeadingStreamHandler: NSObject, FlutterStreamHandler, CLLocationManagerDelegate {
  static let channelName = "runners_jeju/heading"
  private static let shared = HeadingStreamHandler()

  static func register(with messenger: FlutterBinaryMessenger) {
    FlutterEventChannel(name: channelName, binaryMessenger: messenger)
      .setStreamHandler(shared)
  }

  private let manager = CLLocationManager()
  private var sink: FlutterEventSink?

  private override init() {
    super.init()
    manager.delegate = self
    manager.headingFilter = 1
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    guard CLLocationManager.headingAvailable() else {
      return FlutterError(code: "UNAVAILABLE", message: "heading not available", details: nil)
    }
    sink = events
    syncHeadingOrientation()
    manager.startUpdatingHeading()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    manager.stopUpdatingHeading()
    sink = nil
    return nil
  }

  func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
    guard let sink else { return }
    // 화면이 가로로 돌았으면 기준 축을 맞춘다. 돌 때만 바뀌므로 매번 비교만 한다.
    syncHeadingOrientation()
    guard newHeading.trueHeading >= 0 else { return }
    sink([
      "heading": newHeading.trueHeading,
      "accuracy": newHeading.headingAccuracy,
      "calibrated": newHeading.headingAccuracy >= 0,
    ])
  }

  // 러닝 중에 시스템 보정 화면이 지도를 덮지 않게 한다. 보정이 필요한 동안은
  // headingAccuracy가 나빠져 Flutter가 삼각형을 숨긴다.
  func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
    false
  }

  /// heading은 headingOrientation 기준 축으로 계산된다. 인터페이스 방향과 기기
  /// 방향은 가로에서 좌우가 반대다(interface landscapeLeft = device landscapeRight).
  private func syncHeadingOrientation() {
    let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
    let orientation: CLDeviceOrientation
    switch scene?.interfaceOrientation {
    case .landscapeLeft: orientation = .landscapeRight
    case .landscapeRight: orientation = .landscapeLeft
    case .portraitUpsideDown: orientation = .portraitUpsideDown
    default: orientation = .portrait
    }
    if manager.headingOrientation != orientation {
      manager.headingOrientation = orientation
    }
  }
}
