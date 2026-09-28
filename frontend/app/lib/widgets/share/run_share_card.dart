
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../models/run_record.dart';
import '../../services/jeju_basemap.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../utils/map_projection.dart';
import 'jeju_basemap_painter.dart';
import 'route_trace_painter.dart';

/// 공유 카드 배색.
enum ShareCardTheme {
  /// 검정 배경 + 강조색 경로. 스토리에서 가장 눈에 띈다.
  dark,

  /// 흰 배경 + 검정 경로. 인스타 피드 톤에 섞이는 쪽.
  light;

  bool get isDark => this == ShareCardTheme.dark;
}

/// 인스타 스토리로 내보낼 러닝 인증 카드.
///
/// 항상 설계 크기 [width]×[height]로 만들어지고, 호출부가 [FittedBox]로 줄여
/// 쓴다. 미리보기와 내보내는 이미지가 **같은 위젯**이라 둘이 어긋날 수 없고,
/// 폰트 크기·선 굵기·여백을 화면 크기에 맞춰 다시 계산할 일도 없다.
///
/// 스토리는 위아래가 인스타 UI에 가려진다(상단 [safeTop], 하단 [safeBottom]).
/// 모든 요소는 그 사이에만 놓인다.
class RunShareCard extends StatelessWidget {
  const RunShareCard({
    super.key,
    required this.record,
    this.theme = ShareCardTheme.dark,
    this.basemap,
  });

  final RunRecord record;
  final ShareCardTheme theme;

  /// 경로 뒤에 깔 제주 지형. 아직 읽는 중이면 null이고, 그때는 경로만 그린다.
  final JejuBasemap? basemap;

  /// 인스타 스토리 권장 해상도. 9:16.
  static const double width = 1080;
  static const double height = 1920;

  /// 경로(와 지도)가 놓이는 영역. 지도를 미리 받아 두려면 호출부도 이 크기를
  /// 알아야 해서 공개한다.
  static const double mapWidth = width - _sideMargin * 2;
  static const double mapHeight = 560;
  static const double _mapTop = 600;

  /// 인스타가 가리는 영역. 위는 프로필/닫기, 아래는 답장 바와 공유 버튼.
  static const double safeTop = 260;
  static const double safeBottom = 320;

  static const double _sideMargin = 80;

  /// 다크 배색의 본문색. 순백은 검정 배경에서 눈에 날카로워 살짝 내린다.
  static const Color _darkForeground = Color(0xFFF7F8F5);

  /// 라이트 배색에서 강조색을 대신하는 값.
  ///
  /// [AppColors.accent]를 [AppColors.paper] 위에 올리면 대비가 1.7:1로
  /// 숫자가 흐려진다. 같은 색조에서 명도만 내려 대비를 확보한다.
  static const Color _accentOnLight = Color(0xFF6E8F49);

  Color get _background => theme.isDark ? AppColors.ink : AppColors.paper;
  Color get _foreground => theme.isDark ? _darkForeground : AppColors.ink;
  Color get _accent => theme.isDark ? AppColors.accent : _accentOnLight;

  /// 경로선 색. 지형 위에서는 도로선과 확실히 갈라져야 해서 강조색을 쓴다.
  Color get _routeColor => basemap != null
      ? AppColors.accent
      : (theme.isDark ? _accent : AppColors.ink);

  /// 지형을 아직 못 읽었을 때 경로 뒤에 까는 면.
  Color get _mapPlaceholder => theme.isDark
      ? const Color(0xFF16181A)
      : const Color(0xFFECEEF1);

  /// 지형 배색. 카드 배경보다 한 단계만 밝거나 어둡게 둬서, 지형이 경로보다
  /// 앞으로 나오지 않게 한다.
  BasemapPalette get _basemapPalette => theme.isDark
      ? const BasemapPalette(
          sea: Color(0xFF0E1215),
          land: Color(0xFF1C2124),
          coastline: Color(0xFF3E4950),
          majorRoad: Color(0xFF515B5E),
          midRoad: Color(0xFF3D4548),
          minorRoad: Color(0xFF2E3437),
          label: Color(0xFF93A0AA),
          labelHalo: Color(0xFF1C2124),
        )
      : const BasemapPalette(
          sea: Color(0xFFDDE5EB),
          land: Color(0xFFF5F7F9),
          coastline: Color(0xFFAEB9C3),
          majorRoad: Color(0xFFC5CDD4),
          midRoad: Color(0xFFD8DEE4),
          minorRoad: Color(0xFFE6EAEE),
          label: Color(0xFF6E7A88),
          labelHalo: Color(0xFFF5F7F9),
        );

  @override
  Widget build(BuildContext context) {
    // 이 카드는 화면에 얹히기도 하고 이미지로 구워지기도 한다. 어느 쪽이든
    // 같은 그림이 나와야 하므로 문자 방향과 기본 텍스트 스타일을 조상에게
    // 기대지 않고 여기서 정한다 — Material 밖에 놓이면 글자에 노란 밑줄이
    // 그어지고, 그대로 PNG에 찍힌다.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: TextStyle(
          color: _foreground,
          decoration: TextDecoration.none,
          fontWeight: FontWeight.w400,
        ),
        child: _body(),
      ),
    );
  }

  Widget _body() {
    return SizedBox(
      width: width,
      height: height,
      child: ColoredBox(
        color: _background,
        // 설계 좌표를 그대로 쓴다. 시안의 y값이 코드의 y값이다.
        child: Stack(
          children: [
            Positioned(left: _sideMargin, top: 300, child: _logo()),
            Positioned(
              right: _sideMargin,
              top: 312,
              child: Text(
                Formatters.date(record.startedAt),
                style: _labelStyle(32),
              ),
            ),
            Positioned(
              left: _sideMargin,
              top: 412,
              right: _sideMargin,
              child: _title(),
            ),
            Positioned(left: _sideMargin, top: 510, child: _subtitle()),
            Positioned(
              left: _sideMargin,
              top: _mapTop,
              child: _routeArea(),
            ),
            Positioned(
              left: _sideMargin,
              top: 1196,
              child: Text('DISTANCE', style: _labelStyle(29, spacing: 6)),
            ),
            // 시안은 baseline 기준이지만 Flutter는 박스 top 기준이다. height가 1
            // 이므로 박스 높이는 정확히 글자 크기(196)이고, 1248에서 시작해야
            // 1444에서 끝나 아래 구분선(1472)을 덮지 않는다.
            //
            // 폭을 제한하고 [FittedBox]로 감싸는 이유: 거리 숫자는 자릿수가
            // 늘 수 있다. 제약이 없으면 '13.70'처럼 다섯 자리가 되는 순간
            // 카드 밖으로 나가는데, 잘리는 대신 줄어드는 쪽이 낫다.
            Positioned(
              left: _sideMargin,
              right: _sideMargin,
              top: 1248,
              child: SizedBox(
                height: 196,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: _distance(),
                ),
              ),
            ),
            Positioned(
              left: _sideMargin,
              right: _sideMargin,
              top: 1472,
              child: Container(
                height: 3,
                color: _foreground.withValues(alpha: 0.14),
              ),
            ),
            Positioned(
              left: _sideMargin,
              right: _sideMargin,
              top: 1498,
              child: _metrics(),
            ),
          ],
        ),
      ),
    );
  }

  /// 제주 지형 + 그 위의 경로.
  ///
  /// 지형과 경로가 **같은 투영**을 쓴다. 다른 기준으로 그리면 달린 길이 실제
  /// 해안선에서 벗어난 자리에 놓인다.
  Widget _routeArea() {
    final geo = basemap;
    final projection = MapProjection.fit(
      record.path,
      width: mapWidth,
      height: mapHeight,
    );

    return SizedBox(
      width: mapWidth,
      height: mapHeight,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (geo != null)
              CustomPaint(
                painter: JejuBasemapPainter(
                  basemap: geo,
                  projection: projection,
                  palette: _basemapPalette,
                  route: record.path,
                ),
              )
            else
              ColoredBox(color: _mapPlaceholder),
            CustomPaint(
              size: const Size(mapWidth, mapHeight),
              painter: RouteTracePainter(
                path: record.path,
                color: _routeColor,
                // 링 안쪽. 지형 위에서 카드 배경색으로 채우면 주변과 섞여
                // 출발점이 아니라 얼룩처럼 보인다.
                dotFill: geo != null ? Colors.white : _background,
                projection: geo != null ? projection : null,
              ),
            ),
            // ODbL이 요구하는 출처 표기. 지형을 실제로 그렸을 때만 붙인다.
            if (geo != null)
              Positioned(
                right: 16,
                bottom: 12,
                child: Text(
                  JejuBasemap.attribution,
                  style: TextStyle(
                    color: _foreground.withValues(alpha: 0.55),
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    height: 1,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 워터마크. 공유의 목적이 앱을 알리는 것이라 카드마다 반드시 들어간다.
  Widget _logo() => SvgPicture.asset(
    'assets/icons/rjc_logo.svg',
    height: 54,
    colorFilter: ColorFilter.mode(_foreground, BlendMode.srcIn),
  );

  Widget _title() => Text(
    record.courseName ?? '자유 러닝',
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      color: _foreground,
      fontSize: 66,
      fontWeight: FontWeight.w800,
      letterSpacing: -1.5,
      height: 1,
    ),
  );

  /// 제목 아래 한 줄.
  ///
  /// 코스 러닝이면 완주 인증 배지가 온다. 자유 러닝은 인증할 게 없으므로 출발
  /// 시각으로 대신 채운다 — 비워 두면 카드가 헐거워 보이고, 좌표를 옮기면
  /// 코스 러닝과 레이아웃이 갈라진다.
  Widget _subtitle() {
    if (!record.isCourseRun) {
      return Text(
        '${Formatters.timeOfDay(record.startedAt)} 출발',
        style: _labelStyle(34, spacing: 1),
      );
    }

    return Container(
      height: 66,
      padding: const EdgeInsets.symmetric(horizontal: 34),
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(33),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_rounded, size: 40, color: AppColors.ink),
          const SizedBox(width: 8),
          const Text(
            '완주 인증',
            style: TextStyle(
              color: AppColors.ink,
              fontSize: 33,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  /// 카드에서 가장 큰 요소. 거리 하나만 크게 두고 나머지는 아래 3열로 내린다.
  Widget _distance() => Row(
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        Formatters.distanceKm(record.distanceMeters),
        style: TextStyle(
          color: _foreground,
          fontSize: 196,
          fontWeight: FontWeight.w900,
          letterSpacing: -8,
          height: 1,
        ),
      ),
      const SizedBox(width: 20),
      Text(
        'KM',
        style: TextStyle(
          color: _accent,
          fontSize: 54,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    ],
  );

  /// 세 칸은 위를 맞춘다. 가운데 정렬로 두면 한 칸의 라벨이 두 줄로 감기는
  /// 순간 그 칸만 위아래로 벌어져, 아래쪽이 하단 세이프존을 넘는다.
  Widget _metrics() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: _metric('시간', Formatters.duration(record.duration))),
      Expanded(
        child: _metric('평균 페이스', Formatters.pace(record.paceSecondsPerKm)),
      ),
      // 단위는 값 옆에 작게 붙인다. 라벨에 '(km/h)'로 넣으면 라벨이 칸 폭
      // (306px)을 넘겨 두 줄이 되고, 값에 같은 크기로 붙이면 값이 잘린다.
      Expanded(
        child: _metric(
          '평균 속도',
          record.speedKmh?.toStringAsFixed(1) ?? '--',
          unit: 'km/h',
        ),
      ),
    ],
  );

  Widget _metric(String label, String value, {String? unit}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _foreground,
                fontSize: 56,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
                height: 1,
              ),
            ),
          ),
          if (unit != null) ...[
            const SizedBox(width: 8),
            Text(unit, style: _labelStyle(26, spacing: 0)),
          ],
        ],
      ),
      const SizedBox(height: 14),
      Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _labelStyle(28, spacing: 2.5),
      ),
    ],
  );

  TextStyle _labelStyle(double size, {double spacing = 3}) => TextStyle(
    color: AppColors.textSubtle,
    fontSize: size,
    fontWeight: FontWeight.w500,
    letterSpacing: spacing,
    height: 1,
  );
}
