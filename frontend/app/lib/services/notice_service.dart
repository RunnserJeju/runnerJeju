import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/notice_api.dart';
import '../exceptions/app_exception.dart';
import '../models/notice.dart';

/// 비즈니스 로직 계층: 공지사항 조회.
class NoticeService {
  NoticeService(this._noticeApi, [FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final NoticeApi _noticeApi;
  final FlutterSecureStorage _storage;

  static String _dismissKey(String noticeId) => 'notice_dismissed_$noticeId';

  /// 사용자가 '다시 보지 않기'를 눌러 실행 시 팝업에서 뺀 공지인지. 이 기기에만 남는다.
  /// 저장소를 못 읽으면 안 누른 것으로 본다(팝업이 한 번 더 뜰 뿐).
  Future<bool> isLaunchDismissed(String noticeId) async {
    try {
      return await _storage.read(key: _dismissKey(noticeId)) != null;
    } catch (_) {
      return false;
    }
  }

  Future<void> dismissLaunch(String noticeId) async {
    try {
      await _storage.write(key: _dismissKey(noticeId), value: '1');
    } catch (_) {}
  }

  Future<List<Notice>> loadNotices() async {
    try {
      return await _noticeApi.fetchNotices();
    } catch (e) {
      throw AppException('공지사항을 불러오지 못했어요.', e);
    }
  }
}
