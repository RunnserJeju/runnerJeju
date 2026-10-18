import 'package:dio/dio.dart';

import '../../exceptions/app_exception.dart';
import '../../network/api_client.dart';
import 'running_week.dart';

/// 러닝위크 조회·참가 신청. 기능을 떼기 쉽게 API 호출까지 이 폴더 안에 둔다.
class RunningWeekService {
  RunningWeekService(this._client);

  final ApiClient _client;

  /// 지금 공개 중인 회차. 없으면 null.
  Future<RunningWeek?> loadCurrent() async {
    try {
      final response = await _client.dio.get('/running-weeks/current');
      final data = response.data;
      return data is Map<String, dynamic> ? RunningWeek.fromJson(data) : null;
    } catch (e) {
      throw AppException('러닝위크를 불러오지 못했어요.', e);
    }
  }

  /// 참가 신청. 성공하면 빙고판이 담긴 회차를 돌려준다.
  Future<RunningWeek> participate(String weekId, ParticipationForm form) async {
    try {
      final response = await _client.dio.post(
        '/running-weeks/$weekId/participations',
        data: form.toJson(),
      );
      return RunningWeek.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw AppException(_serverMessage(e) ?? '참가 신청에 실패했어요.', e);
    } catch (e) {
      throw AppException('참가 신청에 실패했어요.', e);
    }
  }

  /// 서버가 사람에게 보여줄 문장을 준 경우(이미 신청함, 연락처 형식 등).
  static String? _serverMessage(DioException e) {
    final detail = (e.response?.data as Map?)?['detail'];
    if (detail is String) return detail;
    if (detail is List && detail.isNotEmpty) {
      final message = (detail.first as Map?)?['msg'];
      if (message is String) return message.replaceFirst('Value error, ', '');
    }
    return null;
  }
}
