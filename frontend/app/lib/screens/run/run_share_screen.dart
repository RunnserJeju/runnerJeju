import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/run_record.dart';
import '../../models/user_log.dart';
import '../../services/jeju_basemap.dart';
import '../../services/service_locator.dart';
import '../../services/user_log_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/transient_messenger.dart';
import '../../widgets/share/run_share_card.dart';

/// 공유 카드 미리보기. 배색을 고르고 시스템 공유 시트로 내보낸다.
///
/// 인스타 스토리에 직접 꽂는 대신 공유 시트를 거친다. 스토리 직접 공유는 Meta
/// App ID 등록이 전제라(없으면 인스타가 "지원하지 않는 앱"이라고 거절한다),
/// 그게 준비되기 전까지는 사용자가 시트에서 인스타그램을 한 번 더 고른다.
class RunShareScreen extends StatefulWidget {
  const RunShareScreen({
    super.key,
    required this.record,
    this.initialTheme = ShareCardTheme.dark,
    this.loadBasemap,
  });

  final RunRecord record;

  /// 처음 보여줄 배색. 사용자는 화면에서 바꿀 수 있다.
  final ShareCardTheme initialTheme;

  /// 배경 지형을 읽어 오는 방법. 비우면 에셋에서 읽는다.
  /// 테스트가 에셋 로딩을 기다리지 않게 하려고 열어 둔다.
  final Future<JejuBasemap?> Function()? loadBasemap;

  @override
  State<RunShareScreen> createState() => _RunShareScreenState();
}

class _RunShareScreenState extends State<RunShareScreen> {
  /// 캡처할 대상을 가리킨다. 미리보기와 내보낼 이미지가 같은 위젯이다.
  final GlobalKey _cardKey = GlobalKey();
  final TransientMessenger _messenger = TransientMessenger();

  late ShareCardTheme _theme = widget.initialTheme;
  bool _sharing = false;

  /// 배경 지형. 읽는 동안에는 null이고, 실패해도 null로 남는다 —
  /// 그때는 경로만 그린 카드가 나간다.
  JejuBasemap? _basemap;
  bool _loadingBasemap = true;

  @override
  void initState() {
    super.initState();
    _loadBasemap();
  }

  /// 배경 지형을 먼저 읽어 둔다. 캡처는 화면에 그려진 것을 그대로 굽기 때문에,
  /// 아직 읽는 중인 채로 공유하면 지형이 빠진 이미지가 나간다.
  Future<void> _loadBasemap() async {
    JejuBasemap? basemap;
    try {
      basemap = await (widget.loadBasemap?.call() ?? JejuBasemap.load());
    } catch (_) {
      // 지형은 카드를 더 좋게 만들 뿐 없으면 못 만드는 것이 아니다.
      basemap = null;
    }

    if (!mounted) return;
    setState(() {
      _basemap = basemap;
      _loadingBasemap = false;
    });
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);

    try {
      final file = await Services.instance.shareCardRenderer.toPngFile(
        _cardKey,
        name: 'runners_jeju_run.png',
      );
      if (!mounted) return;

      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          fileNameOverrides: const ['runners-jeju.png'],
          // 아이패드는 공유 시트를 띄울 자리를 알아야 한다. 없으면 화면 좌상단에
          // 붙거나 아예 예외가 난다.
          sharePositionOrigin: _shareOrigin(),
        ),
      );

      // 시트를 열었다고 공유된 것은 아니다(닫기·취소). 안드로이드는 어디로
      // 보냈는지 알려주지 않아 unavailable로 오는 경우가 많으므로, 성공 여부를
      // 단정하지 않고 상태를 그대로 남긴다.
      writeLog(
        LogName.runShare,
        detail: {
          LogKeys.courseId: ?widget.record.courseId,
          LogKeys.cardTheme: _theme.name,
          LogKeys.shareStatus: result.status.name,
        },
      );
    } catch (e) {
      if (!mounted) return;
      _messenger.show(context, '공유 카드를 만들지 못했어요');
      writeLog(LogName.runShareFailed, detail: {LogKeys.error: '$e'});
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  /// 공유 시트가 나올 자리(아이패드). 화면 아래 버튼 근처를 가리킨다.
  Rect _shareOrigin() {
    final size = MediaQuery.sizeOf(context);
    return Rect.fromCenter(
      center: Offset(size.width / 2, size.height - 80),
      width: 1,
      height: 1,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.inkSoft,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('공유하기'),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  // 카드는 늘 1080×1920으로 만들어지고 여기서만 줄어든다.
                  // RepaintBoundary가 줄어든 쪽을 감싸므로, 캡처할 때 그 축소분을
                  // 되돌려 1080px을 얻는다(ShareCardRenderer).
                  child: AspectRatio(
                    aspectRatio: RunShareCard.width / RunShareCard.height,
                    child: RepaintBoundary(
                      key: _cardKey,
                      child: FittedBox(
                        child: RunShareCard(
                          record: widget.record,
                          theme: _theme,
                          basemap: _basemap,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            _ThemePicker(
              selected: _theme,
              onChanged: (theme) => setState(() => _theme = theme),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: FilledButton.icon(
                onPressed: (_sharing || _loadingBasemap) ? null : _share,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.ink,
                  disabledBackgroundColor: AppColors.accent.withValues(
                    alpha: 0.4,
                  ),
                ),
                icon: (_sharing || _loadingBasemap)
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: AppColors.ink,
                        ),
                      )
                    : const Icon(Icons.ios_share_rounded),
                label: Text(
                  _loadingBasemap
                      ? '지도를 그리는 중'
                      : (_sharing ? '준비하는 중' : '스토리로 공유'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 배색 선택. 고를 게 둘뿐이라 세그먼트 대신 칩 두 개로 둔다.
///
/// [ChoiceChip]을 쓰지 않는다. 앱 전역 [ChipThemeData]가 흰 배경을 지정하고
/// 있어서, 어두운 이 화면에서는 비선택 칩이 흰 배경 + 흰 글씨가 되어 글자가
/// 사라진다. 색을 넘겨도 머티리얼3 칩은 테마 쪽을 따라가는 경로가 있어,
/// 전부 직접 그리는 편이 예측 가능하다.
class _ThemePicker extends StatelessWidget {
  const _ThemePicker({required this.selected, required this.onChanged});

  final ShareCardTheme selected;
  final ValueChanged<ShareCardTheme> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final (theme, label) in const [
          (ShareCardTheme.dark, '다크'),
          (ShareCardTheme.light, '라이트'),
        ])
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: _Pill(
              label: label,
              selected: theme == selected,
              onTap: () => onChanged(theme),
            ),
          ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 선택: 강조색 면 + 어두운 글씨. 비선택: 면 없이 테두리 + 흰 글씨.
    final foreground = selected ? AppColors.ink : Colors.white;

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? AppColors.accent : Colors.transparent,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected
                ? AppColors.accent
                : Colors.white.withValues(alpha: 0.35),
            width: 1.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
            child: Text(
              label,
              style: TextStyle(
                color: foreground,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
