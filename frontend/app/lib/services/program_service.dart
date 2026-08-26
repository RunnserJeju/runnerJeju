import '../models/running_program.dart';

/// 러닝 프로그램 조회.
///
/// 서버 API가 아직 없어 지금은 빈 목록을 돌려준다. 프로그램이 서버에 생기면
/// 여기에 ProgramApi를 붙이고, 화면은 그대로 두면 된다.
class ProgramService {
  const ProgramService();

  /// 전체 프로그램 목록(커뮤니티 탭).
  Future<List<RunningProgram>> loadPrograms() async => const [];

  /// 내가 참여한 프로그램(마이페이지).
  Future<List<RunningProgram>> loadMyPrograms() async => const [];
}
