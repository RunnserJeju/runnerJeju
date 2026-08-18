//
//  RunActivityWidgetBundle.swift
//  RunActivityWidget
//
//  러닝 잠금화면 위젯 번들. Live Activity 하나만 담는다.
//  (Xcode가 기본 생성한 RunActivityWidget / RunActivityWidgetControl /
//   AppIntent 파일은 이 기능에 불필요하므로 Xcode에서 삭제한다.)
//

import WidgetKit
import SwiftUI

@main
struct RunActivityWidgetBundle: WidgetBundle {
  var body: some Widget {
    if #available(iOS 16.1, *) {
      RunActivityWidgetLiveActivity()
    }
  }
}
