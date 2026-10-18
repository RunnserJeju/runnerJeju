//
//  GpxShareChannel.swift
//  Runner
//
//  코스 GPX를 다른 앱으로 넘긴다. Flutter(CourseService)와 짝이고, 채널 이름은
//  안드로이드 다운로드 채널과 같다. 메서드: openInGpxApp · share.
//  .gpx는 기기마다 com.topografix.gpx 또는 public.gpx(iOS 27+)로 인식되어,
//  넘길 때 형식을 직접 붙인다.
//

import Flutter
import UIKit

final class GpxShareChannel: NSObject, UIDocumentInteractionControllerDelegate {
  static let name = "runners_jeju/downloads"
  private static let shared = GpxShareChannel()

  private static let topografixType = "com.topografix.gpx"
  private static let systemType = "public.gpx"

  // 메뉴가 떠 있는 동안 붙잡아 둬야 한다. 놓으면 메뉴가 바로 닫힌다.
  private var documentController: UIDocumentInteractionController?

  static func register(with messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: name, binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        guard let path = (call.arguments as? [String: Any])?["path"] as? String else {
          result(FlutterError(code: "bad_args", message: "path가 필요합니다", details: nil))
          return
        }
        let url = URL(fileURLWithPath: path)
        switch call.method {
        case "openInGpxApp": result(shared.openInGpxApp(url))
        case "share": result(shared.share(url))
        default: result(FlutterMethodNotImplemented)
        }
      }
  }

  /// GPX를 받는다고 선언한 앱만 보여준다. 그런 앱이 없으면 false.
  private func openInGpxApp(_ url: URL) -> Bool {
    guard let view = topViewController()?.view else { return false }
    let controller = UIDocumentInteractionController(url: url)
    controller.uti = Self.topografixType
    controller.delegate = self
    documentController = controller
    let shown = controller.presentOpenInMenu(from: anchor(in: view), in: view, animated: true)
    if !shown { documentController = nil }
    return shown
  }

  /// 공유 시트. 파일 하나를 두 GPX 형식으로 함께 등록해, 어느 쪽을 받는 앱이든 고를 수 있게 한다.
  private func share(_ url: URL) -> Bool {
    guard let presenter = topViewController() else { return false }
    let provider = NSItemProvider()
    provider.suggestedName = url.deletingPathExtension().lastPathComponent
    for type in [Self.topografixType, Self.systemType] {
      provider.registerFileRepresentation(
        forTypeIdentifier: type, fileOptions: [], visibility: .all
      ) { completion in
        completion(url, false, nil)
        return nil
      }
    }
    let sheet = UIActivityViewController(activityItems: [provider], applicationActivities: nil)
    sheet.popoverPresentationController?.sourceView = presenter.view
    sheet.popoverPresentationController?.sourceRect = anchor(in: presenter.view)
    presenter.present(sheet, animated: true)
    return true
  }

  func documentInteractionControllerDidDismissOpenInMenu(_ controller: UIDocumentInteractionController) {
    documentController = nil
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
