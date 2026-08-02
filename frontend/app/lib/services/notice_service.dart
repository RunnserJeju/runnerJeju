import '../api/notice_api.dart';
import '../exceptions/app_exception.dart';
import '../models/notice.dart';

/// 비즈니스 로직 계층: 공지사항 조회.
class NoticeService {
  NoticeService(this._noticeApi);

  final NoticeApi _noticeApi;

  Future<List<Notice>> loadNotices() async {
    try {
      return await _noticeApi.fetchNotices();
    } catch (e) {
      throw AppException('공지사항을 불러오지 못했어요.', e);
    }
  }

  Future<Notice> createNotice({required String title, required String body}) async {
    try {
      return await _noticeApi.createNotice(title: title, body: body);
    } catch (e) {
      throw AppException('공지사항을 등록하지 못했어요.', e);
    }
  }
}
