import Flutter
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
  }
}
