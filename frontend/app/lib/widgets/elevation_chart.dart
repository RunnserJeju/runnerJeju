import 'package:flutter/material.dart';

import '../models/elevation_profile.dart';
import '../theme/app_theme.dart';

/// 코스의 고도 변화를 보여주는 선 그래프.
///
/// 차트 패키지를 새로 들이지 않고 [CustomPainter]로 직접 그린다. 그릴 것이
/// 선 하나와 눈금 몇 개뿐이라, 패키지를 붙이면 얻는 것보다 앱 크기와 의존성이
/// 늘어나는 쪽이 크다.
class ElevationChart extends StatelessWidget {
  const ElevationChart({super.key, required this.profile});

  final ElevationProfile profile;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 150,
      width: double.infinity,
      child: CustomPaint(painter: _ElevationChartPainter(profile)),
    );
  }
}

class _ElevationChartPainter extends CustomPainter {
  _ElevationChartPainter(this.profile);

  final ElevationProfile profile;

  /// 고도 눈금 라벨이 들어갈 왼쪽 여백과, 거리 라벨이 들어갈 아래 여백(px).
  static const double _labelGutter = 36;
  static const double _bottomGutter = 18;

  /// 선이 그래프 위아래 끝에 닿지 않도록 y축 범위에 얹는 여유(고도 폭 대비 비율).
  static const double _headroomRatio = 0.15;

  /// y축이 담는 최소 고도 폭(m).
  ///
  /// 해안 코스는 고도차가 몇 미터뿐인데(사계해안도로는 2.5~6.8m) 그 폭에 맞춰
  /// 늘려 그리면 평지가 산맥처럼 보인다. 최소 폭을 두어 평지는 평지로 보이게 한다.
  static const double _minSpanMeters = 40;

  static const Color _gridColor = Color(0xFFEDEFF2);
  static const Color _labelColor = Color(0xFFA3ABB6);

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(
      _labelGutter,
      6,
      size.width,
      size.height - _bottomGutter,
    );
    if (plot.width <= 0 || plot.height <= 0) return;

    final (low, high) = _verticalRange();

    double xOf(double distanceMeters) =>
        plot.left + plot.width * (distanceMeters / profile.distanceMeters);
    double yOf(double altitude) =>
        plot.bottom - plot.height * ((altitude - low) / (high - low));

    _paintGrid(canvas, plot, low, high, yOf);

    final line = Path();
    for (var i = 0; i < profile.samples.length; i++) {
      final sample = profile.samples[i];
      final offset = Offset(xOf(sample.distanceMeters), yOf(sample.altitudeMeters));
      if (i == 0) {
        line.moveTo(offset.dx, offset.dy);
      } else {
        line.lineTo(offset.dx, offset.dy);
      }
    }

    // 선 아래를 옅게 채운다. 채움이 없으면 눈금선과 굵기가 비슷해 선이 묻힌다.
    final area = Path.from(line)
      ..lineTo(plot.right, plot.bottom)
      ..lineTo(plot.left, plot.bottom)
      ..close();

    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.accent.withValues(alpha: 0.28),
            AppColors.accent.withValues(alpha: 0.02),
          ],
        ).createShader(plot),
    );

    canvas.drawPath(
      line,
      Paint()
        ..color = AppColors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    _paintPeak(canvas, plot, xOf, yOf);
    _paintDistanceLabels(canvas, plot);
  }

  /// y축이 담을 고도 범위(m). 데이터 범위를 가운데 두고 위아래로 넓힌다.
  (double, double) _verticalRange() {
    final span = ((profile.maxAltitude - profile.minAltitude) *
            (1 + _headroomRatio * 2))
        .clamp(_minSpanMeters, double.infinity);

    final center = (profile.minAltitude + profile.maxAltitude) / 2;
    var low = center - span / 2;

    // 해수면 위를 달리는 코스에 음수 눈금이 뜨면 잘못된 값처럼 보인다.
    if (low < 0 && profile.minAltitude >= 0) low = 0;

    return (low, low + span);
  }

  void _paintGrid(
    Canvas canvas,
    Rect plot,
    double low,
    double high,
    double Function(double) yOf,
  ) {
    final paint = Paint()
      ..color = _gridColor
      ..strokeWidth = 1;

    for (final altitude in [low, (low + high) / 2, high]) {
      final y = yOf(altitude);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), paint);
      _paintText(
        canvas,
        '${altitude.round()}',
        Offset(plot.left - 6, y),
        align: _Align.rightCenter,
      );
    }
  }

  /// 코스에서 가장 높은 지점. 어디서 제일 높아지는지는 숫자만으로는 알 수 없다.
  void _paintPeak(
    Canvas canvas,
    Rect plot,
    double Function(double) xOf,
    double Function(double) yOf,
  ) {
    final peak = profile.samples.reduce(
      (a, b) => b.altitudeMeters > a.altitudeMeters ? b : a,
    );
    final center = Offset(
      xOf(peak.distanceMeters),
      yOf(peak.altitudeMeters),
    );

    canvas.drawCircle(center, 4, Paint()..color = AppColors.accent);
    canvas.drawCircle(
      center,
      4,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    _paintText(
      canvas,
      '${peak.altitudeMeters.round()}m',
      // 라벨이 그래프 밖으로 나가지 않도록 점 위치를 안쪽으로 당겨 둔다.
      Offset(center.dx.clamp(plot.left + 16, plot.right - 16), center.dy - 9),
      align: _Align.bottomCenter,
      color: AppColors.accent,
      weight: FontWeight.w700,
    );
  }

  void _paintDistanceLabels(Canvas canvas, Rect plot) {
    final km = profile.distanceMeters / 1000;

    _paintText(
      canvas,
      '0km',
      Offset(plot.left, plot.bottom + 5),
      align: _Align.topLeft,
    );
    _paintText(
      canvas,
      '${km.toStringAsFixed(1)}km',
      Offset(plot.right, plot.bottom + 5),
      align: _Align.topRight,
    );
  }

  void _paintText(
    Canvas canvas,
    String text,
    Offset anchor, {
    required _Align align,
    Color color = _labelColor,
    FontWeight weight = FontWeight.w600,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: 10, fontWeight: weight, color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final offset = switch (align) {
      _Align.rightCenter =>
        Offset(anchor.dx - painter.width, anchor.dy - painter.height / 2),
      _Align.bottomCenter =>
        Offset(anchor.dx - painter.width / 2, anchor.dy - painter.height),
      _Align.topLeft => anchor,
      _Align.topRight => Offset(anchor.dx - painter.width, anchor.dy),
    };

    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(_ElevationChartPainter oldDelegate) =>
      oldDelegate.profile != profile;
}

/// [_ElevationChartPainter._paintText]에서 라벨을 앵커의 어느 쪽에 붙일지.
enum _Align { rightCenter, bottomCenter, topLeft, topRight }
