//
//  RunActivityAttributes.swift
//
//  러닝 Live Activity의 데이터 스키마. Runner 앱과 RunActivityWidget 익스텐션
//  두 타겟에 모두 컴파일된다(Xcode Target Membership 둘 다 체크돼 있다).
//  ActivityKit은 이 타입 이름으로 앱↔위젯을 연결하므로 양쪽이 같은 이름·같은
//  필드여야 한다. 값은 ContentState에 실어 activity.update로 넘기고 시스템이
//  위젯 프로세스로 전달한다 — App Group 같은 공유 저장소가 필요 없다.
//

import ActivityKit
import Foundation

@available(iOS 16.2, *)
struct RunActivityAttributes: ActivityAttributes {
  /// 매 갱신마다 바뀌는 값. 4KB 제한이 있지만 문자열 셋과 Bool 하나라 넉넉하다.
  /// 키 이름은 Flutter의 RunLiveWidget._iosData 와 같아야 한다.
  struct ContentState: Codable, Hashable {
    /// "5.23" — Formatters.distanceKm.
    var distanceKm: String
    /// "32:41" 또는 "01:02:03" — Formatters.duration.
    var time: String
    /// "5'42\"" 또는 "--'--\"" — Formatters.pace.
    var pace: String
    /// 일시정지(또는 위치 끊김) 상태인지. 위젯 라벨·아이콘이 이걸 본다.
    var paused: Bool
  }
}
