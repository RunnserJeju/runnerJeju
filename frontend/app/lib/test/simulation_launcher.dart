import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/geo_point.dart';
import '../services/location_service.dart';
import 'simulated_location_service.dart';

/// 디버그 빌드에서만 보이는 "시뮬레이션으로 달리기" 버튼. (kDebugMode로 판별 가능)
class SimulationStartButton extends StatelessWidget {
  const SimulationStartButton({
    super.key,
    required this.coursePath,
    required this.onStart,
  });

  /// 따라 달릴 코스. 비어 있으면 시뮬레이터가 제주시청 둘레를 돈다.
  final List<GeoPoint> coursePath;

  /// 고른 성향으로 만든 가짜 위치원. 호출부는 이걸 그대로 러닝에 넘기면 된다.
  final void Function(LocationService source) onStart;

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();

    return IconButton.filledTonal(
      icon: const Icon(Icons.science_outlined),
      tooltip: '시뮬레이션으로 달리기 (디버그 전용)',
      onPressed: () => _pickProfile(context),
    );
  }

  Future<void> _pickProfile(BuildContext context) async {
    final profile = await showModalBottomSheet<RunSimulationProfile>(
      context: context,
      builder: (sheetContext) => const _ProfileSheet(),
    );

    if (profile == null) return;

    onStart(
      SimulatedLocationService(route: () => coursePath, profile: profile),
    );
  }
}

class _ProfileSheet extends StatelessWidget {
  const _ProfileSheet();

  static const _options =
      <
        ({
          String title,
          String detail,
          IconData icon,
          RunSimulationProfile profile,
        })
      >[
        (
          title: '보통 주행',
          detail: '실시간 페이스. 6km 코스에 약 33분',
          icon: Icons.directions_run_rounded,
          profile: RunSimulationProfile.normal,
        ),
        (
          title: '20배속',
          detail: '점 간격은 그대로. 6km 코스에 약 100초',
          icon: Icons.fast_forward_rounded,
          profile: RunSimulationProfile.timeLapse,
        ),
        (
          title: 'GPS 불량',
          detail: '점이 크게 튀어 누적 거리가 부풀어 오른다',
          icon: Icons.signal_cellular_connected_no_internet_0_bar_rounded,
          profile: RunSimulationProfile.noisyGps,
        ),
        (
          title: '코스 이탈',
          detail: '중심선에서 크게 벗어난다. 서버 검증 확인용',
          icon: Icons.wrong_location_rounded,
          profile: RunSimulationProfile.offCourse,
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      // 작은 화면에서는 옵션 목록이 시트 높이를 넘친다(마지막 항목이 잘려서
      // 누를 수 없게 된다). 스크롤로 감싸 어떤 화면에서도 전부 닿게 한다.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
              child: Row(
                children: [
                  const Icon(Icons.science_outlined, size: 20),
                  const SizedBox(width: 8),
                  Text('시뮬레이션 주행', style: theme.textTheme.titleMedium),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Text(
                '가짜 GPS로 코스를 따라 달립니다. 종료하면 기록이 실제 서버에 저장돼요.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            for (final option in _options)
              ListTile(
                leading: Icon(option.icon),
                title: Text(option.title),
                subtitle: Text(option.detail),
                onTap: () => Navigator.of(context).pop(option.profile),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
