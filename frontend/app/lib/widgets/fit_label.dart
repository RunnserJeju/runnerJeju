import 'package:flutter/widgets.dart';

/// 버튼 글자. 한 줄로 두고, 자리가 모자라면 자르지 않고 줄여서 맞춘다.
///
/// 버튼이 나란히 놓인 팝업은 좁은 화면이나 큰 글씨 설정에서 글자가 잘리기 쉽다.
class FitLabel extends StatelessWidget {
  const FitLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(text, maxLines: 1, softWrap: false),
    );
  }
}
