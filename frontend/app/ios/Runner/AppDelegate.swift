import Flutter
import MetricKit
import UIKit

// 카카오 로그인의 URL 콜백 처리는 kakao_flutter_sdk_common 플러그인이
// registrar.addApplicationDelegate(...)로 스스로 등록해서 처리한다.
// 여기서 따로 open url을 가로챌 필요가 없다.
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 이전 실행(크래시 등)이 잠금화면에 남긴 러닝 Live Activity를 걷는다.
    RunLiveActivityChannel.endLeftovers()
    // 지난 크래시·멈춤 진단을 OS가 넘겨주면 보관함에 쌓는다(Flutter의 CrashReporter가 올린다).
    CrashDiagnostics.shared.start()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // 러닝 잠금화면 위젯(Live Activity) 채널. Flutter의 RunLiveWidget과 짝.
    RunLiveActivityChannel.register(with: engineBridge.applicationRegistrar.messenger())
    // 러닝 지도 현위치 마커의 방향 삼각형. Flutter의 HeadingService와 짝.
    HeadingStreamHandler.register(with: engineBridge.applicationRegistrar.messenger())
    // 코스 GPX를 GPX 앱·공유 시트로 넘긴다. Flutter의 CourseService와 짝.
    GpxShareChannel.register(with: engineBridge.applicationRegistrar.messenger())
    // 크래시 보관함 위치·테스트 크래시. Flutter의 CrashReporter와 짝.
    CrashDiagnostics.register(with: engineBridge.applicationRegistrar.messenger())
  }
}

/// MetricKit 크래시·멈춤 진단을 크래시 보관함(Application Support/crash_outbox)에 쌓는다.
///
/// OS는 앱이 죽은 다음 실행 때(iOS 15+, 늦으면 몇 분 뒤) 진단을 넘겨준다. 한 건이
/// <id>.json(요약) + <id>.dump(진단 JSON)이고, json을 마지막에 내놓아 반쯤 쓴 건을 막는다.
/// 스택은 주소로 오므로 함수 이름은 배포 빌드의 dSYM으로 붙인다.
final class CrashDiagnostics: NSObject, MXMetricManagerSubscriber {
  static let shared = CrashDiagnostics()

  static var outboxDir: URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let dir = base.appendingPathComponent("crash_outbox", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  func start() {
    MXMetricManager.shared.add(self)
  }

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "runners_jeju/crash", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "outboxDir":
        result(outboxDir.path)
      case "collect":
        result(0)  // iOS는 OS가 진단을 밀어준다(didReceive). 따로 꺼낼 것이 없다.
      case "testCrash":
        result(nil)
        DispatchQueue.main.async { fatalError("RunnersJeju test crash") }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func didReceive(_ payloads: [MXMetricPayload]) {}

  func didReceive(_ payloads: [MXDiagnosticPayload]) {
    for payload in payloads {
      for diagnostic in payload.crashDiagnostics ?? [] {
        let parts: [String?] = [
          diagnostic.exceptionType.map { "exceptionType=\($0)" },
          diagnostic.exceptionCode.map { "exceptionCode=\($0)" },
          diagnostic.signal.map { "signal=\($0)" },
          diagnostic.terminationReason,
        ]
        save(kind: "ios_crash", at: payload.timeStampEnd, diagnostic: diagnostic,
             summary: parts.compactMap { $0 }.joined(separator: " "))
      }
      for diagnostic in payload.hangDiagnostics ?? [] {
        save(kind: "ios_hang", at: payload.timeStampEnd, diagnostic: diagnostic,
             summary: "hang \(diagnostic.hangDuration.converted(to: .seconds).value)s")
      }
    }
  }

  private func save(kind: String, at: Date, diagnostic: MXDiagnostic, summary: String) {
    let id = UUID().uuidString.lowercased()
    let dir = Self.outboxDir
    let meta: [String: Any] = [
      "id": id,
      "kind": kind,
      "occurred_at": ISO8601DateFormatter().string(from: at),
      "summary": String(summary.prefix(500)),
      "device": diagnostic.metaData.deviceType,
      "os_version": diagnostic.metaData.osVersion,
      // 올리는 앱은 그새 업데이트됐을 수 있다. 크래시 난 빌드를 따로 남긴다.
      "context": ["app_build_at_crash": diagnostic.metaData.applicationBuildVersion],
    ]
    do {
      try diagnostic.jsonRepresentation().write(to: dir.appendingPathComponent("\(id).dump"))
      let json = try JSONSerialization.data(withJSONObject: meta)
      let tmp = dir.appendingPathComponent("\(id).json.tmp")
      try json.write(to: tmp)
      try FileManager.default.moveItem(at: tmp, to: dir.appendingPathComponent("\(id).json"))
    } catch {
      // 보관함에 못 쓰면 이번 진단은 버린다. 앱 동작에는 영향이 없다.
    }
  }
}
