import '../../models/run_stamp.dart';

/// 러닝위크 한 회차(#70). 공개 중일 때만 서버가 내려준다.
class RunningWeek {
  const RunningWeek({
    required this.id,
    required this.title,
    required this.participated,
    this.description,
    this.imageUrl,
    this.bingo,
  });

  final String id;
  final String title;
  final String? description;

  /// 커뮤니티 상단 배너. 없으면 제목 카드로 그린다.
  final String? imageUrl;

  final bool participated;

  /// 참가 신청을 했고 운영자가 배치를 짰을 때만 있다.
  final Bingo? bingo;

  factory RunningWeek.fromJson(Map<String, dynamic> json) => RunningWeek(
    id: json['id'].toString(),
    title: json['title'] as String,
    description: json['description'] as String?,
    imageUrl: json['image_url'] as String?,
    participated: json['participated'] as bool? ?? false,
    bingo: json['bingo'] == null
        ? null
        : Bingo.fromJson(json['bingo'] as Map<String, dynamic>),
  );
}

/// 5x5 빙고판. 칸 하나 = 스탬프 하나이고, 그 스탬프를 받았으면 채워진다.
class Bingo {
  const Bingo({required this.cells, required this.completedLines});

  static const int size = 5;

  final List<BingoCell> cells;
  final int completedLines;

  int get acquiredCount => cells.where((c) => c.acquired).length;

  factory Bingo.fromJson(Map<String, dynamic> json) => Bingo(
    cells: [
      for (final cell in (json['cells'] as List? ?? const []))
        BingoCell.fromJson(cell as Map<String, dynamic>),
    ],
    completedLines: json['completed_lines'] as int? ?? 0,
  );
}

class BingoCell {
  const BingoCell({required this.position, required this.acquired, this.stamp});

  final int position;
  final bool acquired;

  /// 운영자가 숨긴 스탬프면 null(빈 칸).
  final StampDefinition? stamp;

  factory BingoCell.fromJson(Map<String, dynamic> json) => BingoCell(
    position: json['position'] as int,
    acquired: json['acquired'] as bool? ?? false,
    stamp: json['stamp'] == null
        ? null
        : StampDefinition.fromJson(json['stamp'] as Map<String, dynamic>),
  );
}

enum Gender { male, female }

enum Residence { jeju, nonJeju }

/// 참가 신청 폼 값. 서버 RunningWeekParticipationCreate와 같다.
class ParticipationForm {
  const ParticipationForm({
    required this.name,
    required this.phone,
    required this.gender,
    required this.age,
    required this.residence,
  });

  final String name;
  final String phone;
  final Gender gender;
  final int age;
  final Residence residence;

  Map<String, dynamic> toJson() => {
    'name': name,
    'phone': phone,
    'gender': gender.name,
    'age': age,
    'residence': residence == Residence.jeju ? 'jeju' : 'non_jeju',
    // 폼에서 동의 체크를 해야만 제출 버튼이 켜진다.
    'agreed': true,
  };
}
