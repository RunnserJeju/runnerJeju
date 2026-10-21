//
//  GpxShareChannel.swift
//  Runner
//
//  코스 GPX를 다른 앱으로 넘긴다. Flutter(CourseService)와 짝이고, 채널 이름은
//  안드로이드 다운로드 채널과 같다. 메서드: share.
//  파일 URL을 그대로 넘긴다 — 파일 앱의 공유와 같은 방식이라 가민 등이 받는다.
//  (열기 메뉴나 형식을 직접 붙인 NSItemProvider로는 가민이 받지 못했다.)
//

import Flutter
import UIKit

final class GpxShareChannel {
  static let name = "runners_jeju/downloads"
  private static let shared = GpxShareChannel()

  static func register(with messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: name, binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        guard let path = (call.arguments as? [String: Any])?["path"] as? String else {
          result(FlutterError(code: "bad_args", message: "path가 필요합니다", details: nil))
          return
        }
        let url = URL(fileURLWithPath: path)
        switch call.method {
        case "share": result(shared.share(url))
        default: result(FlutterMethodNotImplemented)
        }
      }
  }

  /// 공유 시트. GPX 앱들과 '파일에 저장'이 함께 뜬다.
  private func share(_ url: URL) -> Bool {
    guard let presenter = topViewController() else { return false }
    let shared = (try? copyToTemporary(url)) ?? url
    let sheet = UIActivityViewController(activityItems: [shared], applicationActivities: nil)
    sheet.popoverPresentationController?.sourceView = presenter.view
    sheet.popoverPresentationController?.sourceRect = anchor(in: presenter.view)
    presenter.present(sheet, animated: true)
    return true
  }

  /// Library/Caches(Flutter getTemporaryDirectory)에 둔 파일은 다른 앱으로 넘길 때
  /// 시스템(sharingd)이 읽지 못해 가민·순토가 아예 실행되지 않았다
  /// ("does not have read access to document"). tmp로 옮겨서 넘긴다.
  private func copyToTemporary(_ url: URL) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("gpx-share", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let target = directory.appendingPathComponent(url.lastPathComponent)
    try? FileManager.default.removeItem(at: target)
    try FileManager.default.copyItem(at: url, to: target)
    return target
  }

  private func anchor(in view: UIView) -> CGRect {
    CGRect(x: view.bounds.midX, y: view.bounds.height * 0.6, width: 1, height: 1)
  }

  private func topViewController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
    var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }
}
