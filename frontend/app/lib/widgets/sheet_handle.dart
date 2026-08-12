import 'package:flutter/material.dart';

/// 아래에서 올라오는 시트 맨 위의 손잡이 막대.
///
/// 끌어올릴 수 있다는 신호라, 실제로 끌 수 있는 시트와 그 자리에 붙는 고정
/// 패널이 같은 모양을 써야 화면이 바뀔 때 아래쪽이 튀지 않는다.
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: const Color(0xFFDCDFE4),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}
